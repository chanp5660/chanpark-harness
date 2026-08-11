#!/bin/bash
# wip-guard.sh
# Deterministic WIP guard for the Stop and PreCompact hooks.
#
# Replaces the former haiku `agent` hooks, whose prompts never defined what to do
# when Plans.md is absent — so the model improvised (sometimes "no file => no WIP
# => allow", sometimes "cannot verify"), which is both non-deterministic and, in the
# fail-open direction, a silent pass when Plans.md merely moved.
#
# Usage:  wip-guard.sh stop        # Stop hook: block on WIP
#         wip-guard.sh precompact  # PreCompact hook: warn on WIP
#
# Input:  stdin — hook payload JSON (session_id; stop mode also reads stop_hook_active)
# Output: stdout — hook JSON, or nothing at all when the session may proceed
#
# Exit paths (all exit 0; the hook must never break Claude Code):
#   A. Plans.md absent         -> silent allow. The project does not use harness
#                                 planning. This is a normal state, not an error.
#   B. Plans.md unreadable     -> block/warn. WIP status is UNKNOWN; this is the real
#                                 silent-failure point and must not pass quietly.
#   C. Plans.md clean          -> silent allow, via a different branch than A.
#   D. Plans.md has WIP        -> block (stop) / systemMessage warning (precompact).
#   E. stop_hook_active=true   -> silent allow. Breaks the infinite stop-hook loop
#                                 that would otherwise occur when Claude Code has
#                                 already blocked once in this stop cycle.
#   F. Self-tracked block loop -> silent allow. See "Host-independent loop breaker".
#   G. Session does not own    -> silent allow. See "Session ownership".
#      the WIP
#
# Host-independent loop breaker (Path F):
#   Path E relies on `stop_hook_active`, a field the HOST supplies. Claude Code sets
#   it; a host that does not (observed with some third-party clients) leaves the guard
#   with no way out, and it blocks every single turn forever — the session can never
#   end. Path F therefore keeps its own record under
#   <project>/.claude/state/wip-guard/ and suppresses a repeat block that lands within
#   HARNESS_WIP_GUARD_COOLDOWN seconds (default 300) of the previous one, whether or
#   not the host tells us anything. The cooldown, rather than a plain per-session
#   counter, is what keeps the guard meaningful later in a long session: block once,
#   let the turn through, and re-arm after the user has moved on.
#
# Session ownership (Path G):
#   A WIP marker means "somebody is mid-task", not "every session in this project is
#   forbidden to end". plans-watcher.sh records the session that last edited Plans.md
#   while WIP was present, in .claude/state/wip-guard/owner.json. When that record
#   exists and names a DIFFERENT session, this one is merely visiting — asking a
#   question, reading code — and is allowed to stop silently. With no owner recorded
#   (legacy state, or WIP introduced outside the editor) the guard falls back to its
#   original project-wide behaviour, bounded by Path F.
#
# Modes (HARNESS_WIP_GUARD_MODE, stop mode only):
#   block  Emit {"decision":"block"} on WIP. Default; preserves prior behaviour.
#   warn   Emit a systemMessage instead — visible, never traps the session.
#   off    Same as HARNESS_DISABLE_WIP_GUARD=1.
#
# Dialect handling:
#   - HTML comment lines (<!-- ... -->) are SKIPPED entirely, even when they
#     contain cc:wip. Comments are documentation, not task records.
#   - Table rows (lines starting with optional space + '|'): status is the LAST
#     non-empty cell, with code spans stripped *within that cell only*. This
#     preserves the v1.3.2 fix where a task description cell may quote `cc:wip`
#     but the status cell is `cc:done`.
#   - Checklist items (^[[:space:]]*- \[[ xX]\]): code spans are NOT stripped
#     globally — the marker legitimately lives in one (e.g. `cc:wip`). Status is
#     determined by the presence of cc:wip anywhere on the line. ID is derived
#     from a **bold title** or the leading text before the first backtick.
#   - All other lines (prose, headings, legend text) are NEVER counted.
#
# Marker matching is ANCHORED and word-bounded, matching scripts/lib/plans-markers.awk:
# the status must START with cc:wip and must not continue into a longer word. Only
# cc:wip arms this guard. cc:blocked is waiting on something but is not in progress;
# cc:done and cc:dropped are both terminal — dropping a task releases the Stop guard
# exactly like finishing it, which is what makes "decide not to do this" a usable exit.
#
# This guard reads Plans.md only. Plans-backlog.md holds unstructured capture and carries
# no cc: markers by design, so no amount of backlog text can ever arm the Stop guard.
#
# Opt-out: HARNESS_DISABLE_WIP_GUARD=1 disables the guard entirely.

set +e # never abort the host session

MODE="${1:-stop}"
GUARD_MODE="${HARNESS_WIP_GUARD_MODE:-block}"
COOLDOWN="${HARNESS_WIP_GUARD_COOLDOWN:-300}"

if [ "${HARNESS_DISABLE_WIP_GUARD:-0}" = "1" ] || [ "$GUARD_MODE" = "off" ]; then
  echo "[chanpark-harness] wip-guard: disabled (HARNESS_DISABLE_WIP_GUARD / mode=off)" >&2
  exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STDIN_JSON="$(cat 2>/dev/null)"
GUARD_STATE_DIR="$PROJECT_ROOT/.claude/state/wip-guard"

# Read a top-level string field out of the hook payload. jq when available; a sed
# fallback otherwise, because the guard must work on a bare shell.
json_field() {
  local field="$1"
  if command -v jq > /dev/null 2>&1; then
    printf '%s' "$STDIN_JSON" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null
  else
    printf '%s' "$STDIN_JSON" |
      sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}

SESSION_ID="$(json_field session_id)"
[ -z "$SESSION_ID" ] && SESSION_ID="nosession"
# Filename-safe: the session id reaches us from the host and is never trusted as a path.
SESSION_KEY="$(printf '%s' "$SESSION_ID" | tr -c '[:alnum:]._-' '_' | cut -c1-64)"

# ---------------------------------------------------------------------------
# Path E (stop mode only): stop_hook_active loop-breaker.
# Claude Code sets stop_hook_active:true once a stop hook has already blocked
# in the current stop cycle. Re-blocking would create an infinite loop.
# ---------------------------------------------------------------------------
if [ "$MODE" = "stop" ]; then
  _sha_val="false"
  if command -v jq > /dev/null 2>&1; then
    _sha_val="$(printf '%s' "$STDIN_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
  else
    # grep/sed fallback — no jq required
    _sha_grep="$(printf '%s' "$STDIN_JSON" | grep -o '"stop_hook_active"[[:space:]]*:[[:space:]]*true' 2>/dev/null || true)"
    [ -n "$_sha_grep" ] && _sha_val="true"
  fi
  if [ "$_sha_val" = "true" ]; then
    echo "[chanpark-harness] wip-guard: stop_hook_active=true; allowing to break stop-hook loop" >&2
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Plans.md lookup order (previously undefined; now explicit)
#   1. $HARNESS_PLANS_FILE  (absolute or project-relative override)
#   2. <project root>/Plans.md   <- canonical location
#   3. <project root>/docs/Plans.md
# ---------------------------------------------------------------------------
find_plans() {
  local candidate
  if [ -n "${HARNESS_PLANS_FILE:-}" ]; then
    case "$HARNESS_PLANS_FILE" in
      /*) candidate="$HARNESS_PLANS_FILE" ;;
      *) candidate="$PROJECT_ROOT/$HARNESS_PLANS_FILE" ;;
    esac
    [ -e "$candidate" ] && printf '%s' "$candidate"
    return
  fi
  for candidate in "$PROJECT_ROOT/Plans.md" "$PROJECT_ROOT/docs/Plans.md"; do
    if [ -e "$candidate" ]; then
      printf '%s' "$candidate"
      return
    fi
  done
}

# JSON string escaping for the reason/message payload.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr '\n' ' '
}

# ---------------------------------------------------------------------------
# Path F: host-independent loop breaker.
#
# Returns 0 ("suppress this block") when the previous block for this session
# landed less than $COOLDOWN seconds ago, and 1 ("go ahead and block") otherwise,
# stamping the current time on the way out.
#
# This deliberately does NOT depend on stop_hook_active: a host that omits that
# field would otherwise leave the guard blocking on every turn with no exit.
# ---------------------------------------------------------------------------
loop_breaker_should_suppress() {
  local stamp now prev age
  stamp="$GUARD_STATE_DIR/$SESSION_KEY.last-block"
  now="$(date +%s 2> /dev/null)"
  # No usable clock -> fail OPEN (suppress). A guard that cannot measure its own
  # cooldown must not be the reason a session can never end.
  case "$now" in
    '' | *[!0-9]*)
      echo "[chanpark-harness] wip-guard: no usable clock; suppressing block to stay safe" >&2
      return 0
      ;;
  esac

  if [ -r "$stamp" ]; then
    prev="$(cat "$stamp" 2> /dev/null)"
    case "$prev" in
      '' | *[!0-9]*) prev="" ;;
    esac
    if [ -n "$prev" ]; then
      age=$((now - prev))
      if [ "$age" -ge 0 ] && [ "$age" -lt "$COOLDOWN" ]; then
        echo "[chanpark-harness] wip-guard: repeat block ${age}s < ${COOLDOWN}s cooldown for session ${SESSION_ID}; allowing (loop breaker)" >&2
        return 0
      fi
    fi
  fi

  mkdir -p "$GUARD_STATE_DIR" 2> /dev/null
  printf '%s\n' "$now" > "$stamp" 2> /dev/null
  # Opportunistic housekeeping: stamps older than 7 days belong to dead sessions.
  find "$GUARD_STATE_DIR" -maxdepth 1 -name '*.last-block' -mtime +7 -delete 2> /dev/null
  return 1
}

# ---------------------------------------------------------------------------
# Path G: session ownership.
#
# Returns 0 when a recorded owner exists and is NOT this session — i.e. the WIP
# belongs to somebody else and this session is only visiting.
# ---------------------------------------------------------------------------
another_session_owns_wip() {
  local owner_file owner
  owner_file="$GUARD_STATE_DIR/owner.json"
  [ -r "$owner_file" ] || return 1

  if command -v jq > /dev/null 2>&1; then
    owner="$(jq -r '.session_id // empty' "$owner_file" 2> /dev/null)"
  else
    owner="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$owner_file" | head -1)"
  fi

  [ -n "$owner" ] || return 1
  [ "$owner" = "$SESSION_ID" ] && return 1

  echo "[chanpark-harness] wip-guard: WIP owned by session ${owner}, not ${SESSION_ID}; allowing" >&2
  return 0
}

# ---------------------------------------------------------------------------
# Emit the stop-mode verdict, honouring GUARD_MODE and the loop breaker.
# precompact never blocks, so it never routes through here.
# ---------------------------------------------------------------------------
emit_stop_verdict() {
  local msg esc
  msg="$1"
  esc="$(json_escape "$msg")"

  if [ "$GUARD_MODE" = "warn" ]; then
    printf '{"systemMessage":"WIP guard: %s"}\n' "$esc"
    return
  fi

  if loop_breaker_should_suppress; then
    # Still say it once, visibly, so the allow is not silent to the user.
    printf '{"systemMessage":"WIP guard (not blocking): %s"}\n' "$esc"
    return
  fi

  printf '{"decision":"block","reason":"%s"}\n' "$esc"
}

# ---------------------------------------------------------------------------
# PreCompact only: harness-loop owns the session -> suppress all WIP output.
# ---------------------------------------------------------------------------
if [ "$MODE" = "precompact" ]; then
  LOCK_DIR="$PROJECT_ROOT/.claude/state/locks/loop-session.lock.d"
  if [ -d "$LOCK_DIR" ] && [ -f "$LOCK_DIR/meta.json" ] && command -v jq > /dev/null 2>&1; then
    lock_sid="$(jq -r '.session_id // empty' "$LOCK_DIR/meta.json" 2>/dev/null)"
    hook_sid="$(printf '%s' "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null)"
    if [ -n "$lock_sid" ] && [ "$lock_sid" = "$hook_sid" ]; then
      echo "[chanpark-harness] wip-guard: harness-loop owns this session; suppressed" >&2
      exit 0
    fi
  fi
fi

PLANS="$(find_plans)"

# --- Path A: Plans.md absent --------------------------------------------------
if [ -z "$PLANS" ]; then
  echo "[chanpark-harness] wip-guard: no Plans.md under $PROJECT_ROOT; project does not use harness planning; allowing" >&2
  exit 0
fi

# --- Path B: Plans.md present but unreadable ----------------------------------
unreadable_reason=""
if [ ! -f "$PLANS" ]; then
  unreadable_reason="$PLANS exists but is not a regular file"
elif [ ! -r "$PLANS" ]; then
  unreadable_reason="$PLANS exists but is not readable (permission denied)"
elif ! head -c 1 "$PLANS" > /dev/null 2>&1; then
  unreadable_reason="$PLANS exists but could not be read (I/O or encoding error)"
fi

if [ -n "$unreadable_reason" ]; then
  msg="Plans.md could not be read: ${unreadable_reason}. WIP status is unknown — resolve before continuing."
  if [ "$MODE" = "stop" ]; then
    emit_stop_verdict "$msg"
  else
    esc="$(json_escape "$msg")"
    printf '{"systemMessage":"Warning: %s"}\n' "$esc"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Paths C/D: Plans.md readable — collect WIP task IDs.
#
# Three dialects are handled; everything else is silently skipped:
#
# 1. HTML comments  (<!-- ... -->)  — SKIP entirely. These are documentation
#    and section labels; any cc:wip inside them is instructional, not a record.
#
# 2. Table rows  (^[[:space:]]*|)  — status = LAST non-empty cell, with code
#    spans stripped *within that cell* so that a description cell quoting
#    `cc:wip` does not shadow a real status cell of `cc:done`.
#    ID = FIRST non-empty cell.
#
# 3. Checklist items  (^[[:space:]]*- \[[ xX]\])  — do NOT pre-strip code
#    spans; the marker legitimately lives in one (`cc:wip`). WIP is detected
#    by searching the task text as-is. ID is derived from **bold title** or
#    leading text before the first backtick; falls back to "line N".
#
# Case-insensitive match: cc:WIP is treated as cc:wip throughout.
# ---------------------------------------------------------------------------
WIP_IDS="$(awk '
  {
    line = $0

    trimmed = line
    gsub(/^[[:space:]]+/, "", trimmed)

    # --- Skip fenced code blocks -------------------------------------------
    # Marker-bearing examples inside ``` fences are documentation, not records.
    if (substr(trimmed, 1, 3) == "```") { in_fence = !in_fence; next }
    if (in_fence) next

    # --- Skip HTML comment lines (<!-- ... --> and <!-- open) ---------------
    if (substr(trimmed, 1, 4) == "<!--") next

    id = ""
    status = ""

    if (line ~ /^[[:space:]]*\|/) {
      # TABLE DIALECT: split on | first, then strip code spans per cell.
      n = split(line, cell, "|")
      # Status = last non-empty cell (code spans stripped within that cell)
      for (i = n; i >= 1; i--) {
        s = cell[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        if (s != "") {
          gsub(/`[^`]*`/, "", s)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          status = s
          break
        }
      }
      # ID = first non-empty cell
      for (i = 1; i <= n; i++) {
        s = cell[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        if (s != "") { id = s; break }
      }

    } else if (line ~ /^[[:space:]]*- \[[ xX]\]/) {
      # CHECKLIST DIALECT: do NOT strip code spans globally.
      # The cc:wip marker legitimately lives in a code span.
      task_text = line
      sub(/^[[:space:]]*- \[[ xX]\][[:space:]]*/, "", task_text)

      # The status is the LAST cc: marker on the line. A task may quote another
      # marker in its text (e.g. a task about the marker parser itself); only the
      # trailing marker records the state of the task itself.
      # NOTE: no apostrophes in this awk program — it is single-quoted in shell.
      # The character class includes "-" so that a hyphenated state is captured
      # WHOLE. With /cc:[A-Za-z]+/ the match stopped at the hyphen, so "cc:wip-paused"
      # was truncated to "cc:wip" and armed the guard on a task that is explicitly
      # not in progress — one such row could keep a session from ever ending.
      rest = task_text
      last_marker = ""
      while (match(rest, /cc:[A-Za-z-]+/)) {
        last_marker = tolower(substr(rest, RSTART, RLENGTH))
        rest = substr(rest, RSTART + RLENGTH)
      }
      sub(/-+$/, "", last_marker)     # trailing hyphen is punctuation, not the state

      if (last_marker == "cc:wip") {
        status = "cc:wip"
        # Derive a readable ID
        id = task_text
        if (match(id, /\*\*[^*]+\*\*/)) {
          # Bold title: strip the ** delimiters
          id = substr(id, RSTART + 2, RLENGTH - 4)
        } else {
          # Leading text before the first backtick (or end of line)
          sub(/[[:space:]]*`.*$/, "", id)
          sub(/[[:space:]]+$/, "", id)
          if (length(id) > 50) id = substr(id, 1, 50) "..."
        }
        if (id == "") id = "line " NR
      }
    }
    # Prose, headings, legend text, sub-bullets, etc. -> status = "" -> skipped

    # ANCHORED match, not a substring search. The old rule was `~ /cc:wip/`, which
    # matched anywhere in the status cell and matched any longer state that merely
    # begins with it. Two consequences, both measured:
    #   - "cc:wip-paused" (an explicitly NOT-in-progress row) blocked Stop forever;
    #   - a status cell reading "was cc:wip, now cc:done" blocked on the stale mention.
    # The rule now mirrors scripts/lib/plans-markers.awk: the cell must START with the
    # marker, and the next character must not continue the word. A trailing note
    # ("cc:wip [a1b2]", "cc:wip (since Tue)") is still recognised.
    st = tolower(status)
    sub(/^cursor:/, "cc:", st)
    if (index(st, "cc:wip") == 1 && substr(st, 7, 1) !~ /[A-Za-z0-9_-]/) {
      if (id == "") id = "line " NR
      print id
    }
  }
' "$PLANS")"

# Render the list: first 20 ids, comma-separated, with an explicit note when the
# list was truncated (a silent cut would read as "these are all of them").
# NOTE: `paste -sd ', '` is wrong here — POSIX treats the argument as a ROTATING
# list of delimiters, so three ids join as "a,b c" rather than "a, b, c".
WIP_COUNT="$(printf '%s' "$WIP_IDS" | grep -c . 2> /dev/null)"
WIP_LIST="$(printf '%s\n' "$WIP_IDS" | grep . | head -20 | paste -sd ',' - | sed 's/,/, /g')"
if [ "${WIP_COUNT:-0}" -gt 20 ]; then
  WIP_LIST="${WIP_LIST}, ... and $((WIP_COUNT - 20)) more"
fi

# --- Path C: readable, no WIP -------------------------------------------------
if [ -z "$WIP_IDS" ]; then
  echo "[chanpark-harness] wip-guard: $PLANS readable, 0 WIP tasks; allowing" >&2
  exit 0
fi

# --- Path G: WIP exists, but it belongs to a different session ----------------
# Checked here rather than earlier so the log line only appears when there is
# actual WIP to disown.
if [ "$MODE" = "stop" ] && another_session_owns_wip; then
  exit 0
fi

# --- Path D: WIP tasks present ------------------------------------------------
if [ "$MODE" = "stop" ]; then
  emit_stop_verdict "WIP tasks remain: ${WIP_LIST}. Consider completing them or marking them blocked before stopping."
else
  esc="$(json_escape "Compacting context with WIP tasks in progress: ${WIP_LIST}. Key context about these tasks may be lost after compaction. Consider completing or checkpointing them first.")"
  printf '{"systemMessage":"Warning: %s"}\n' "$esc"
fi
exit 0
