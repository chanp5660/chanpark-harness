#!/usr/bin/env bash
# scripts/plans-sweep.sh
# Staleness sweep for Plans.md — proposes, never writes.
#
# Usage:
#   plans-sweep.sh [--root <dir>] [--plans <file>] [--stale-days N] [--archive-days N]
#                  [--enable-stale] [--disable-archive]
#
# Exit: 0 always (this is advisory tooling; it must never fail a session or a hook).
#       Prints nothing at all when there is nothing to suggest and HARNESS_SWEEP_QUIET=1.
#
# THIS SCRIPT NEVER MODIFIES A FILE. That is a design constraint, not an omission.
# Linear can safely auto-cancel stale issues because it has an activity feed, an undo,
# and a UI that shows the change. A markdown file has none of the three: silently
# rewriting a row to cc:dropped is invisible until somebody reads a diff, and the first
# time a tool retires work behind your back is the last time you leave it enabled.
# So the sweep reports candidates and a human (or a confirmed skill pass) does the edit.
#
# Two triggers, with deliberately different default states:
#
#   T1  stale suggestion   — a cc:todo / cc:blocked row untouched for `stale_days`
#                            is reported as a cc:dropped CANDIDATE.
#                            DEFAULT OFF. Evidence for it is weak: this repository has
#                            an observed abandonment rate of 0/20, so there is no
#                            distribution of "how long a doomed task lives" to fit a
#                            threshold to. Opt in with --enable-stale.
#
#   T2  archive suggestion — every row is terminal (done/dropped) AND the file has not
#                            been edited for `archive_days`.
#                            DEFAULT ON. Evidence for it is strong: it is a pure
#                            function of state and time, both directly observable, and
#                            replayed against this repository's history it fires on
#                            exactly the real condition (a fully-completed ledger left
#                            unarchived for a month).
#
# Threshold provenance (default 14 days, configurable in harness.toml [plans]):
#   measured maximum legitimate dwell, cc:todo -> cc:done  = 4.129 days
#   safety factor x2 (engineering default, not fitted)     = 8.26 days
#   rounded up to the next weekly boundary a human reviews = 14 days
#   retro-check: applying 14 days to all 20 historical rows cancels 0 of them.
# The strongest honest claim for 14 is not "fitted" but "provably destroys nothing in
# any observed history". Anything shorter would have fired on four rows that were
# waiting on a human approval gate — and a decision gate is a healthy state, not rot.
#
# Per-row last-touch comes from `git blame --line-porcelain`, so no date column is
# added to the schema. Known limit: reformatting the file resets every blame timestamp.
# The migration to this layout IS such a reformat, so the sweep's clock starts there.

set -uo pipefail

ROOT=""
PLANS=""
STALE_DAYS=""
ARCHIVE_DAYS=""
STALE_ENABLED=""
ARCHIVE_ENABLED=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root)          ROOT="${2:-}"; shift 2 ;;
    --plans)         PLANS="${2:-}"; shift 2 ;;
    --stale-days)    STALE_DAYS="${2:-}"; shift 2 ;;
    --archive-days)  ARCHIVE_DAYS="${2:-}"; shift 2 ;;
    --enable-stale)  STALE_ENABLED=true; shift ;;
    --disable-archive) ARCHIVE_ENABLED=false; shift ;;
    -h|--help)
      sed -n '2,50p' "$0" >&2
      exit 0 ;;
    *) echo "plans-sweep: unknown argument: $1" >&2; exit 0 ;;
  esac
done

ROOT="${ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
PLANS="${PLANS:-$ROOT/Plans.md}"
QUIET="${HARNESS_SWEEP_QUIET:-0}"

[ -f "$PLANS" ] || { [ "$QUIET" = "1" ] || echo "plans-sweep: no Plans.md at $PLANS"; exit 0; }

# --- Config: harness.toml [plans], overridable by flags ----------------------------
toml_val() {  # $1 key -> value, or empty
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$ROOT/harness.toml" 2>/dev/null |
    head -1 | sed 's/.*=[[:space:]]*//' | tr -d '"' | tr -d "'" | awk '{print $1}'
}
[ -n "$STALE_DAYS" ]      || STALE_DAYS="$(toml_val stale_days)"
[ -n "$ARCHIVE_DAYS" ]    || ARCHIVE_DAYS="$(toml_val archive_days)"
[ -n "$STALE_ENABLED" ]   || STALE_ENABLED="$(toml_val stale_sweep_enabled)"
[ -n "$ARCHIVE_ENABLED" ] || ARCHIVE_ENABLED="$(toml_val archive_sweep_enabled)"
STALE_DAYS="${STALE_DAYS:-14}"
ARCHIVE_DAYS="${ARCHIVE_DAYS:-14}"
STALE_ENABLED="${STALE_ENABLED:-false}"
ARCHIVE_ENABLED="${ARCHIVE_ENABLED:-true}"
case "$STALE_DAYS" in ''|*[!0-9]*) STALE_DAYS=14 ;; esac
case "$ARCHIVE_DAYS" in ''|*[!0-9]*) ARCHIVE_DAYS=14 ;; esac

NOW="$(date +%s 2>/dev/null)"
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac   # no usable clock -> say nothing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNTS_LIB="$SCRIPT_DIR/lib/plans-counts.sh"
[ -r "$COUNTS_LIB" ] || exit 0
# shellcheck source=lib/plans-counts.sh
. "$COUNTS_LIB"
plans_counts_load "$PLANS" || exit 0

OUT=""
add() { OUT="${OUT}${OUT:+
}$1"; }

# --- T1: stale active rows -> cc:dropped candidates --------------------------------
if [ "$STALE_ENABLED" = "true" ] && [ "$PLANS_ACTIVE" -gt 0 ]; then
  BLAME=""
  if command -v git > /dev/null 2>&1 && GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
    BLAME="$(GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" blame --line-porcelain -- "$PLANS" 2>/dev/null)"
  fi
  if [ -n "$BLAME" ]; then
    # One subprocess, one awk pass: pair each source line with its author-time, then
    # apply exactly the counter's anchored status rule to decide whether it is a row
    # that can go stale (todo/blocked are debt; terminal rows are already resolved).
    CANDIDATES="$(printf '%s\n' "$BLAME" | awk -v now="$NOW" -v days="$STALE_DAYS" '
      /^author-time /   { at = $2; next }
      /^\t/ {
        line = substr($0, 2)
        age = int((now - at) / 86400)
        if (age < days) next
        t = line; sub(/^[[:space:]]+/, "", t)
        if (substr(t,1,3) == "```" || substr(t,1,4) == "<!--") next
        if (line !~ /^[[:space:]]*\|/) next
        n = split(line, c, "|")
        s = ""
        for (i = n; i >= 1; i--) { v = c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                                   if (v != "") { gsub(/`[^`]*`/, "", v); s = tolower(v); break } }
        id = ""
        for (i = 1; i <= n; i++) { v = c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                                   if (v != "") { id = v; break } }
        sub(/^cursor:/, "cc:", s)
        bounded = 0
        if (index(s,"cc:todo") == 1    && substr(s,8,1)  !~ /[A-Za-z0-9_-]/) bounded = 1
        if (index(s,"cc:blocked") == 1 && substr(s,11,1) !~ /[A-Za-z0-9_-]/) bounded = 1
        if (!bounded) next
        printf "   %-8s untouched %d days (%s)\n", id, age, s
      }')"
    if [ -n "$CANDIDATES" ]; then
      add "plans sweep — T1 stale candidates (>= ${STALE_DAYS}d untouched):"
      add "$CANDIDATES"
      add "   Suggestion only. Retire with cc:dropped and a reason in the description cell,"
      add "   or touch the row to reset its clock. Nothing has been changed."
    fi
  fi
fi

# --- T2: fully terminal + untouched file -> archive suggestion ---------------------
if [ "$ARCHIVE_ENABLED" != "false" ] && [ "$PLANS_TOTAL" -gt 0 ] && [ "$PLANS_ACTIVE" -eq 0 ]; then
  MTIME=""
  if command -v git > /dev/null 2>&1 && GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
    MTIME="$(GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" log -1 --format=%at -- "$PLANS" 2>/dev/null)"
  fi
  case "${MTIME:-}" in ''|*[!0-9]*) MTIME="$(stat -c %Y "$PLANS" 2>/dev/null || stat -f %m "$PLANS" 2>/dev/null)" ;; esac
  case "${MTIME:-}" in ''|*[!0-9]*) MTIME="" ;; esac
  if [ -n "$MTIME" ]; then
    AGE=$(( (NOW - MTIME) / 86400 ))
    if [ "$AGE" -ge "$ARCHIVE_DAYS" ]; then
      add "plans sweep — T2 archive suggested:"
      add "   All ${PLANS_TOTAL} row(s) are terminal (done ${PLANS_DONE}, dropped ${PLANS_DROPPED}) and Plans.md"
      add "   has not been edited for ${AGE} days (threshold ${ARCHIVE_DAYS})."
      add "   Move the terminal rows to .claude/memory/archive/Plans-$(date +%Y-%m-%d).md."
      add "   Suggestion only. Nothing has been changed."
    fi
  fi
fi

if [ -z "$OUT" ]; then
  [ "$QUIET" = "1" ] || echo "plans sweep: no candidates (active ${PLANS_ACTIVE}, terminal ${PLANS_TERMINAL}/${PLANS_TOTAL})"
  exit 0
fi

printf '%s\n' "$OUT"
exit 0
