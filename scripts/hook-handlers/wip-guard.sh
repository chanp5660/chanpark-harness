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
# Opt-out: HARNESS_DISABLE_WIP_GUARD=1 disables the guard entirely.

set +e # never abort the host session

MODE="${1:-stop}"

if [ "${HARNESS_DISABLE_WIP_GUARD:-0}" = "1" ]; then
  echo "[chanpark-harness] wip-guard: disabled via HARNESS_DISABLE_WIP_GUARD" >&2
  exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
STDIN_JSON="$(cat 2>/dev/null)"

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
  esc="$(json_escape "$msg")"
  if [ "$MODE" = "stop" ]; then
    printf '{"decision":"block","reason":"%s"}\n' "$esc"
  else
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
      rest = task_text
      last_marker = ""
      while (match(rest, /cc:[A-Za-z]+/)) {
        last_marker = tolower(substr(rest, RSTART, RLENGTH))
        rest = substr(rest, RSTART + RLENGTH)
      }

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

    if (tolower(status) ~ /cc:wip/) {
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

# --- Path D: WIP tasks present ------------------------------------------------
if [ "$MODE" = "stop" ]; then
  esc="$(json_escape "WIP tasks remain: ${WIP_LIST}. Consider completing them or marking them blocked before stopping.")"
  printf '{"decision":"block","reason":"%s"}\n' "$esc"
else
  esc="$(json_escape "Compacting context with WIP tasks in progress: ${WIP_LIST}. Key context about these tasks may be lost after compaction. Consider completing or checkpointing them first.")"
  printf '{"systemMessage":"Warning: %s"}\n' "$esc"
fi
exit 0
