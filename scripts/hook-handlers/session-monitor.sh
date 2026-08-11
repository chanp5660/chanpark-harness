#!/bin/bash
# session-monitor.sh
# SessionStart monitor: print the "Session Start - Project State" block.
#
# Replaces `harness hook session-monitor` in the vendored Go binary, following the
# precedent set by plans-watcher.sh. Two defects forced the takeover, both measured on
# this repository:
#
#   1. The binary counts cc:* markers as UNANCHORED substrings anywhere in Plans.md.
#      On a file whose only mention of "blocked" was a legend row and a prose sentence
#      it reported `blocked 1`, inventing a blocked task that does not exist. The
#      canonical counter (scripts/lib/plans-markers.awk) reports 0.
#   2. Its marker legend is compiled in as a fixed six-row table. There is no Go source
#      in this repository and the binary cannot be rebuilt here, so a new state can
#      never appear in the block the binary prints — it would announce a vocabulary
#      that no longer matches the one every script enforces.
#
# What this prints that the binary could not:
#   - counts from the anchored counter, including cc:dropped and the unknown bucket;
#   - active / backlog / archive as THREE SEPARATE numbers. That separation is the
#     point of the three-file layout: Plans.md holds work in flight, Plans-backlog.md
#     holds unstructured capture that no counter reads, and the archive holds terminal
#     rows that have left the active set. Collapsing them into one number is how a
#     ledger silently grows until nobody reads it.
#
# Input:  stdin — SessionStart payload JSON (ignored; the block is derived from the repo)
# Output: stdout — plain text, injected into the session as context
#
# Always exits 0: a monitor must never break the host session.
#
# Opt-out: HARNESS_DISABLE_SESSION_MONITOR=1 disables the block entirely.

set +e # never abort the host session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNTS_LIB="$SCRIPT_DIR/../lib/plans-counts.sh"

if [ "${HARNESS_DISABLE_SESSION_MONITOR:-0}" = "1" ]; then
  echo "[chanpark-harness] session-monitor: disabled via HARNESS_DISABLE_SESSION_MONITOR" >&2
  exit 0
fi

cat > /dev/null 2>&1   # drain stdin; the payload carries nothing this block needs

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
PLANS="$PROJECT_ROOT/Plans.md"
BACKLOG="$PROJECT_ROOT/Plans-backlog.md"
ARCHIVE_DIR="$PROJECT_ROOT/.claude/memory/archive"
RULE="────────────────────────────────────"

PROJECT_NAME="$(basename "$PROJECT_ROOT" 2>/dev/null)"
BRANCH=""
if command -v git > /dev/null 2>&1; then
  BRANCH="$(GIT_OPTIONAL_LOCKS=0 git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null)"
fi

printf 'Session Start - Project State\n'
printf '%s\n' "$RULE"
printf 'Project: %s\n' "${PROJECT_NAME:-unknown}"
[ -n "$BRANCH" ] && printf 'Branch: %s\n' "$BRANCH"
printf '%s\n' "$RULE"
printf '\n'

# --- Active set: Plans.md, through the shared loader -------------------------------
if [ -r "$COUNTS_LIB" ] && [ -f "$PLANS" ]; then
  # shellcheck source=../lib/plans-counts.sh
  . "$COUNTS_LIB"
  if plans_counts_load "$PLANS"; then
    printf 'Plans.md (active set)\n'
    printf '   todo %s · wip %s · blocked %s   →  active %s\n' \
      "$PLANS_TODO" "$PLANS_WIP" "$PLANS_BLOCKED" "$PLANS_ACTIVE"
    printf '   done %s · dropped %s          →  terminal %s of %s (%s%%)\n' \
      "$PLANS_DONE" "$PLANS_DROPPED" "$PLANS_TERMINAL" "$PLANS_TOTAL" "$PLANS_PCT"
    [ "${PLANS_PM_REQUESTED:-0}" -gt 0 ] 2>/dev/null &&
      printf '   pm:requested %s awaiting pickup\n' "$PLANS_PM_REQUESTED"

    # An unrecognised marker is a file defect. The vocabulary is closed precisely so
    # that a typo is loud instead of being absorbed into a neighbouring bucket.
    if [ "${PLANS_UNKNOWN:-0}" -gt 0 ] 2>/dev/null; then
      printf '   !! %s status cell(s) match no known marker — use cc:todo/wip/blocked/done/dropped\n' \
        "$PLANS_UNKNOWN"
    fi

    # Caps come from harness.toml [plans]; the defaults here keep the monitor useful
    # in a project that has not configured them.
    toml_int() {
      grep -E "^[[:space:]]*$1[[:space:]]*=" "$PROJECT_ROOT/harness.toml" 2>/dev/null |
        head -1 | grep -oE '[0-9]+' | head -1
    }
    SOFT_CAP="$(toml_int soft_cap)"; HARD_CAP="$(toml_int hard_cap)"
    MAX_LINES="$(toml_int max_lines)"
    SOFT_CAP="${SOFT_CAP:-25}"; HARD_CAP="${HARD_CAP:-30}"; MAX_LINES="${MAX_LINES:-80}"

    # Two independent budgets, reported together because they bound different things.
    # The row caps bound how much WORK is in flight; the line budget bounds whether the
    # file can still be read in one screen. Neither implies the other: at the hard cap
    # of 30 rows the file measured 93 lines before the long-form legend was moved out to
    # skills/harness-plan/references/plans-format.md, and terminal rows awaiting archive
    # add length without touching the row count at all.
    PLANS_LINES="$(wc -l < "$PLANS" 2>/dev/null | tr -d ' ')"
    PLANS_LINES="${PLANS_LINES:-0}"
    printf '   rows %s/%s active (soft %s) · %s/%s lines\n' \
      "$PLANS_ACTIVE" "$HARD_CAP" "$SOFT_CAP" "$PLANS_LINES" "$MAX_LINES"

    if [ "$PLANS_ACTIVE" -gt "$HARD_CAP" ] 2>/dev/null; then
      printf '   !! active rows %s exceed the hard cap of %s — new work must go to Plans-backlog.md\n' \
        "$PLANS_ACTIVE" "$HARD_CAP"
    elif [ "$PLANS_ACTIVE" -gt "$SOFT_CAP" ] 2>/dev/null; then
      printf '   ~ active rows %s exceed the soft cap of %s — route new work to Plans-backlog.md\n' \
        "$PLANS_ACTIVE" "$SOFT_CAP"
    fi
    # Length overflow is REPORTED, never refused: refusing a write because a description
    # is well written would punish good writing, which is why §2.5 rejects a line cap as
    # admission control. The remedy is always to move terminal rows out, not to write less.
    if [ "$PLANS_LINES" -gt "$MAX_LINES" ] 2>/dev/null; then
      printf '   !! Plans.md is %s lines, over the %s-line budget by %s — run the archive sweep and\n' \
        "$PLANS_LINES" "$MAX_LINES" "$((PLANS_LINES - MAX_LINES))"
      printf '      move terminal rows to .claude/memory/archive/. Writes are never refused on length.\n'
    fi
    if [ "${PLANS_WIP:-0}" -gt 1 ] 2>/dev/null; then
      printf '   ~ %s tasks are cc:wip; the loop is serial and expects at most one\n' "$PLANS_WIP"
    fi
  fi
elif [ ! -f "$PLANS" ]; then
  printf 'Plans.md: not found (this project does not use harness planning)\n'
fi

# --- Backlog: counted as LINES, never as tasks -------------------------------------
# Plans-backlog.md carries no cc: markers by design, so there is nothing for a marker
# counter to find and the file cannot leak into any progress number. Reporting its size
# keeps it from becoming invisible, which is the failure mode of a write-only list.
if [ -f "$BACKLOG" ]; then
  # Bullets under the "## Captured" heading only, fenced examples excluded — the file's
  # own instructions are written in bullets and a format example lives in a code fence.
  #
  # LIVE and DECLINED are separated. A struck-through bullet is the backlog's terminal
  # state (its cc:dropped), and folding it into one number would make declining an idea
  # look identical to never having decided — which is how the file ends up with no exit
  # but promotion, and grows forever.
  BACKLOG_COUNTS="$(awk '
    { t=$0; sub(/^[[:space:]]+/,"",t)
      if (substr(t,1,3)=="```") { f=!f; next }
      if (f) next
      if (t ~ /^## +Captured/) { cap=1; next }
      if (t ~ /^## /) { cap=0; next }
      if (!cap) next
      if (t !~ /^[-*][[:space:]]+/) next
      b=t; sub(/^[-*][[:space:]]+/,"",b)
      if (b ~ /^~~/) d++; else n++ }
    END { printf "%d %d\n", n+0, d+0 }' "$BACKLOG" 2>/dev/null)"
  BACKLOG_N="${BACKLOG_COUNTS%% *}"; BACKLOG_D="${BACKLOG_COUNTS##* }"
  printf 'Plans-backlog.md: %s live · %s declined — unscheduled capture (no markers, no counts)\n' \
    "${BACKLOG_N:-0}" "${BACKLOG_D:-0}"
fi

# --- Archive: files, not rows ------------------------------------------------------
if [ -d "$ARCHIVE_DIR" ]; then
  ARCHIVE_N="$(find "$ARCHIVE_DIR" -maxdepth 1 -name 'Plans-*.md' -type f 2>/dev/null | wc -l | tr -d ' ')"
  printf 'Archive: %s file(s) under .claude/memory/archive/ (never scanned by any counter)\n' \
    "${ARCHIVE_N:-0}"
fi

# --- Sweep suggestions (read-only; never rewrites anything) ------------------------
SWEEP="$SCRIPT_DIR/../plans-sweep.sh"
if [ -x "$SWEEP" ]; then
  SWEEP_OUT="$(HARNESS_SWEEP_QUIET=1 bash "$SWEEP" --root "$PROJECT_ROOT" 2>/dev/null)"
  [ -n "$SWEEP_OUT" ] && printf '\n%s\n' "$SWEEP_OUT"
fi

# --- harness-mem companion ---------------------------------------------------------
MEM_SETUP="$PROJECT_ROOT/.claude/state/harness-mem-companion-setup.json"
if [ -f "$MEM_SETUP" ]; then
  MEM_STATUS=""
  if command -v jq > /dev/null 2>&1; then
    MEM_STATUS="$(jq -r '.status // empty' "$MEM_SETUP" 2>/dev/null)"
  else
    MEM_STATUS="$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$MEM_SETUP" | head -1)"
  fi
  [ -n "$MEM_STATUS" ] && printf 'harness-mem companion: %s\n' "$MEM_STATUS"
fi

# --- Advisor drift -----------------------------------------------------------------
ADVISOR_REQ="$PROJECT_ROOT/.claude/state/advisor-request.json"
if [ -f "$ADVISOR_REQ" ] && [ ! -f "$PROJECT_ROOT/.claude/state/advisor-response.json" ]; then
  printf 'advisor drift: a request is open with no response recorded\n'
fi

exit 0
