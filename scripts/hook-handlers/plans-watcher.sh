#!/bin/bash
# plans-watcher.sh
# PostToolUse handler for Plans.md edits: refresh .claude/state/plans-state.json and
# surface the state delta (task completed / new PM request) back into the session.
#
# Replaces `harness hook plans-watcher` in the vendored Go binary. The binary counted
# markers as unanchored, case-insensitive substrings anywhere in the file, so a prose
# sentence such as
#
#   - **Archive**: Phase 22~26 moved to Plans-archive-2026-07-27.md (all cc:done).
#
# was counted as a finished task: a nine-row table reported cc_done = 10. hud/statusline.sh
# already anchored its count on the table status cell, so the two paths disagreed on the
# same file. The binary is vendored from upstream with no Go source in this repo, so the
# count could not be fixed in place — this script takes over the handler and reads the
# canonical counter in scripts/lib/plans-markers.awk instead.
#
# Behaviour parity with the binary handler it replaces (measured, not assumed):
#   - Fires only when the edited path is <cwd>/Plans.md; anything else emits an empty
#     additionalContext and exits 0.
#   - Always rewrites .claude/state/plans-state.json.
#   - Emits the framed status block only on a delta:
#       pm:requested increased -> "New task: request from PM"     (takes precedence)
#       cc:done increased      -> "Task completed: ready to report to PM"
#       cc:dropped increased   -> "Task dropped: decided against" (added with the
#                                 dropped state; retiring work is a decision and must
#                                 be as visible as finishing it)
#     Any other change (todo/wip/blocked) is recorded silently.
#   - Writes pm-notification.md / cursor-notification.md only when a message is emitted.
#
# Input:  stdin — PostToolUse payload JSON (cwd, tool_input.file_path)
# Output: stdout — {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"..."}}
#
# Always exits 0: a hook must never break the host session.
#
# Opt-out: HARNESS_DISABLE_PLANS_WATCHER=1 disables the handler entirely.

set +e # never abort the host session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNTS_LIB="$SCRIPT_DIR/../lib/plans-counts.sh"

emit_empty() {
  printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":""}}\n'
  exit 0
}

if [ "${HARNESS_DISABLE_PLANS_WATCHER:-0}" = "1" ]; then
  echo "[chanpark-harness] plans-watcher: disabled via HARNESS_DISABLE_PLANS_WATCHER" >&2
  emit_empty
fi

STDIN_JSON="$(cat 2>/dev/null)"

# --- Payload fields -----------------------------------------------------------
# jq when available; a grep/sed fallback keeps the handler working without it.
json_field() {
  local filter="$1" pattern="$2"
  if command -v jq > /dev/null 2>&1; then
    printf '%s' "$STDIN_JSON" | jq -r "$filter" 2> /dev/null
  else
    printf '%s' "$STDIN_JSON" | grep -o "$pattern" 2> /dev/null | head -1 |
      sed 's/.*"\([^"]*\)"$/\1/'
  fi
}

HOOK_CWD="$(json_field '.cwd // empty' '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"')"
FILE_PATH="$(json_field '.tool_input.file_path // empty' '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"')"

PROJECT_ROOT="${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[ -z "$FILE_PATH" ] && emit_empty

# Resolve a relative file_path against the project root, then require an exact match
# on <project root>/Plans.md. docs/Plans.md and other Plans.md copies are out of scope,
# matching the handler this replaces.
case "$FILE_PATH" in
  /*) ABS_PATH="$FILE_PATH" ;;
  *) ABS_PATH="$PROJECT_ROOT/$FILE_PATH" ;;
esac
PLANS="$PROJECT_ROOT/Plans.md"
[ "$ABS_PATH" != "$PLANS" ] && emit_empty
[ -f "$PLANS" ] && [ -r "$PLANS" ] || emit_empty

# --- Count ---------------------------------------------------------------------
# Read through the shared loader (scripts/lib/plans-counts.sh) rather than parsing the
# counter's line here. The counter emits labelled k=v pairs precisely so that adding a
# state cannot shift a field: the old positional read would have put "0 0" into a JSON
# number and written a malformed plans-state.json the moment a seventh column appeared.
if [ ! -r "$COUNTS_LIB" ]; then
  echo "[chanpark-harness] plans-watcher: count loader not found at $COUNTS_LIB; skipped" >&2
  emit_empty
fi
# shellcheck source=../lib/plans-counts.sh
. "$COUNTS_LIB"
plans_counts_load "$PLANS" || emit_empty
CC_TODO="$PLANS_TODO"; CC_WIP="$PLANS_WIP"; CC_DONE="$PLANS_DONE"
CC_BLOCKED="$PLANS_BLOCKED"; CC_DROPPED="$PLANS_DROPPED"; CC_UNKNOWN="$PLANS_UNKNOWN"
PM_PENDING="$PLANS_PM_REQUESTED"; PM_CONFIRMED="$PLANS_PM_APPROVED"

STATE_DIR="$PROJECT_ROOT/.claude/state"
STATE_FILE="$STATE_DIR/plans-state.json"

# Refuse to follow a symlinked state directory — the binary applies the same guard.
if [ -L "$STATE_DIR" ]; then
  echo "[chanpark-harness] plans-watcher: state dir is a symlink: $STATE_DIR; skipped" >&2
  emit_empty
fi
mkdir -p "$STATE_DIR" 2> /dev/null || emit_empty

# --- Previous state (missing file reads as all-zero, i.e. a first run is a delta) ---
prev_of() {
  local key="$1"
  [ -f "$STATE_FILE" ] || { printf '0'; return; }
  local v
  v="$(grep -o "\"$key\"[[:space:]]*:[[:space:]]*[0-9]\+" "$STATE_FILE" 2> /dev/null |
    head -1 | grep -o '[0-9]\+$')"
  printf '%s' "${v:-0}"
}
PREV_DONE="$(prev_of cc_done)"
PREV_DROPPED="$(prev_of cc_dropped)"
PREV_PM_PENDING="$(prev_of pm_pending)"

# --- Save state (write-then-rename so a reader never sees a half-written file) ---
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TMP_STATE="$STATE_FILE.tmp.$$"
cat > "$TMP_STATE" << EOF
{
  "timestamp": "$TS",
  "pm_pending": $PM_PENDING,
  "cc_todo": $CC_TODO,
  "cc_wip": $CC_WIP,
  "cc_done": $CC_DONE,
  "cc_blocked": $CC_BLOCKED,
  "cc_dropped": $CC_DROPPED,
  "cc_unknown": $CC_UNKNOWN,
  "active": $PLANS_ACTIVE,
  "terminal": $PLANS_TERMINAL,
  "total": $PLANS_TOTAL,
  "pm_confirmed": $PM_CONFIRMED
}
EOF
mv -f "$TMP_STATE" "$STATE_FILE" 2> /dev/null || rm -f "$TMP_STATE" 2> /dev/null

# --- WIP ownership (consumed by wip-guard.sh Path G) ----------------------------
# The session that edits Plans.md while WIP is present is the session doing the work.
# Recording it here lets the Stop guard block only that session, instead of locking
# every session in the project out of ever finishing — including ones that only came
# to ask a question. When WIP drops to zero the record is removed, so a stale owner
# can never keep the guard armed.
GUARD_STATE_DIR="$STATE_DIR/wip-guard"
OWNER_FILE="$GUARD_STATE_DIR/owner.json"
SESSION_ID="$(json_field '.session_id // empty' '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"')"
if [ "${CC_WIP:-0}" -gt 0 ] 2> /dev/null; then
  if [ -n "$SESSION_ID" ]; then
    mkdir -p "$GUARD_STATE_DIR" 2> /dev/null
    TMP_OWNER="$OWNER_FILE.tmp.$$"
    if printf '{\n  "session_id": "%s",\n  "cc_wip": %s,\n  "timestamp": "%s"\n}\n' \
      "$SESSION_ID" "$CC_WIP" "$TS" > "$TMP_OWNER" 2> /dev/null; then
      mv -f "$TMP_OWNER" "$OWNER_FILE" 2> /dev/null || rm -f "$TMP_OWNER" 2> /dev/null
    else
      rm -f "$TMP_OWNER" 2> /dev/null
    fi
  fi
else
  rm -f "$OWNER_FILE" 2> /dev/null
fi

# --- Delta -> message ----------------------------------------------------------
HEADLINE=""
NEXT_STEP=""
NOTE_SECTION=""
NOTE_BODY=""
if [ "$PM_PENDING" -gt "$PREV_PM_PENDING" ] 2> /dev/null; then
  HEADLINE="New task: request from PM"
  NEXT_STEP="   → Check the status with /sync-status and start with /work"
  NOTE_SECTION="New tasks"
  NOTE_BODY="A new task has been requested by PM (pm:requested)."
elif [ "$CC_DONE" -gt "$PREV_DONE" ] 2> /dev/null; then
  HEADLINE="Task completed: ready to report to PM"
  NEXT_STEP="   → Report with /handoff-to-pm-claude (or /handoff-to-cursor)"
  NOTE_SECTION="Completed tasks"
  NOTE_BODY="Impl Claude has completed the task. Please review (cc:done)."
elif [ "$CC_DROPPED" -gt "$PREV_DROPPED" ] 2> /dev/null; then
  # Dropping is a decision, and a decision deserves the same visibility as a completion.
  # Left silent, retiring work would feel like a lesser act than finishing it — which is
  # exactly how a backlog learns to grow forever.
  HEADLINE="Task dropped: decided against, recorded as terminal"
  NEXT_STEP="   → Confirm the reason is in the description cell; run the archive sweep when the phase closes"
  NOTE_SECTION="Dropped tasks"
  NOTE_BODY="A task was retired without being implemented (cc:dropped). It still counts toward progress."
fi

[ -z "$HEADLINE" ] && emit_empty

# --- Notification files (PM handoff surface) -----------------------------------
NOTE="$(
  cat << EOF
# Notification to PM

**Generated**: $(date +'%Y-%m-%d %H:%M:%S')

## Status changes

### $NOTE_SECTION

$NOTE_BODY

---

**Next action**: review in PM Claude and re-request if needed (/handoff-to-impl-claude).
EOF
)"
printf '%s\n' "$NOTE" > "$STATE_DIR/pm-notification.md" 2> /dev/null
printf '%s\n' "$NOTE" > "$STATE_DIR/cursor-notification.md" 2> /dev/null

# --- Session context -----------------------------------------------------------
RULE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
CONTEXT="$(
  cat << EOF
$RULE
Plans.md update detected
$RULE
$HEADLINE
$NEXT_STEP

Current status:
   pm:requested   : $PM_PENDING
   cc:todo        : $CC_TODO
   cc:wip         : $CC_WIP
   cc:blocked     : $CC_BLOCKED
   cc:done        : $CC_DONE
   cc:dropped     : $CC_DROPPED
   pm:approved    : $PM_CONFIRMED
   progress       : $PLANS_TERMINAL/$PLANS_TOTAL terminal (${PLANS_PCT}%)$( [ "${CC_UNKNOWN:-0}" -gt 0 ] && printf '\n   unrecognised   : %s status cell(s) match no known marker' "$CC_UNKNOWN" )
$RULE
EOF
)"

# JSON string escaping that preserves newlines as \n (wip-guard.sh flattens them to
# spaces; this payload is a rendered block and must keep its line breaks).
json_escape() {
  printf '%s' "$1" | awk '
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t")
      out = out (NR > 1 ? "\\n" : "") $0 }
    END { printf "%s", out }
  '
}

printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' \
  "$(json_escape "$CONTEXT")"
exit 0
