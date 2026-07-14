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
# Input:  stdin — hook payload JSON (only `session_id` is used, precompact mode)
# Output: stdout — hook JSON, or nothing at all when the session may proceed
#
# Exit paths (all exit 0; the hook must never break Claude Code):
#   A. Plans.md absent      -> silent allow. The project does not use harness
#                              planning. This is a normal state, not an error.
#   B. Plans.md unreadable  -> block/warn. WIP status is UNKNOWN; this is the real
#                              silent-failure point and must not pass quietly.
#   C. Plans.md clean       -> silent allow, via a different branch than A.
#   D. Plans.md has WIP     -> block (stop) / systemMessage warning (precompact).
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
# The marker is only honoured in the row's STATUS position, so a task whose
# *description* quotes `cc:wip` (e.g. a task about the marker parser itself)
# is not miscounted. Inline code spans are stripped before matching.
#   - table row  `| 1.2 | title | ... | cc:wip |` -> status = last non-empty cell
#   - other rows -> the whole (code-span-stripped) line
# Legacy uppercase variants (cc:WIP) match case-insensitively.
# ---------------------------------------------------------------------------
WIP_IDS="$(awk '
  {
    line = $0
    gsub(/`[^`]*`/, "", line)          # drop inline code spans
    status = line
    id = ""
    if (line ~ /^[[:space:]]*\|/) {
      n = split(line, cell, "|")
      for (i = n; i >= 1; i--) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell[i])
        if (cell[i] != "") { status = cell[i]; break }
      }
      for (i = 1; i <= n; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", cell[i])
        if (cell[i] != "") { id = cell[i]; break }
      }
    }
    if (tolower(status) ~ /cc:wip/) {
      if (id == "") id = "line " NR
      print id
    }
  }
' "$PLANS" | head -20 | paste -sd ', ' -)"

# --- Path C: readable, no WIP -------------------------------------------------
if [ -z "$WIP_IDS" ]; then
  echo "[chanpark-harness] wip-guard: $PLANS readable, 0 WIP tasks; allowing" >&2
  exit 0
fi

# --- Path D: WIP tasks present ------------------------------------------------
if [ "$MODE" = "stop" ]; then
  esc="$(json_escape "WIP tasks remain: ${WIP_IDS}. Consider completing them or marking them blocked before stopping.")"
  printf '{"decision":"block","reason":"%s"}\n' "$esc"
else
  esc="$(json_escape "Compacting context with WIP tasks in progress: ${WIP_IDS}. Key context about these tasks may be lost after compaction. Consider completing or checkpointing them first.")"
  printf '{"systemMessage":"Warning: %s"}\n' "$esc"
fi
exit 0
