#!/usr/bin/env bash
# scripts/plans-sweep.sh
# Staleness sweep for Plans.md — proposes, never writes.
#
# Usage:
#   plans-sweep.sh [--root <dir>] [--plans <file>] [--backlog <file>]
#                  [--stale-days N] [--archive-days N] [--backlog-stale-days N]
#                  [--enable-stale] [--disable-archive] [--disable-backlog]
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
# Three triggers, with deliberately different default states:
#
#   T1  stale suggestion   — a cc:todo / cc:blocked row untouched for `stale_days`
#                            is reported as a cc:dropped CANDIDATE.
#                            DEFAULT OFF. Evidence for it is weak: this repository has
#                            an observed abandonment rate of 0/20, so there is no
#                            distribution of "how long a doomed task lives" to fit a
#                            threshold to. Opt in with --enable-stale.
#
#   T2  archive suggestion — PER ROW. Any terminal row (cc:done / cc:dropped) whose
#                            git-blame author-time is older than `archive_days` is an
#                            archive candidate, regardless of what else is in the file.
#                            DEFAULT ON.
#
#                            This used to be a FILE-level rule ("every row is terminal
#                            AND the file is untouched"), and that was a hole big enough
#                            to reopen the failure the whole design targets: one
#                            perpetually-unfinished cc:todo row suppressed archiving of
#                            the entire file, forever. Nothing else caught it — the
#                            caps count active rows only, and T1 targets active rows
#                            only and ships off. Reproduced: 120 cc:done rows plus one
#                            cc:todo, 125 lines, and the sweep printed "no candidates".
#
#                            Linear's rule, which this design cites, is per-ISSUE:
#                            "closed issues are auto-archived after they have remained
#                            completed, canceled or auto-closed and inactive for the
#                            full auto-archive period". Not per-view, not per-project.
#                            A pure function of state and time means the state of the
#                            ROW, because the row is the thing being archived.
#
#   T3  backlog staleness  — a live Plans-backlog.md bullet whose capture date is older
#                            than `backlog_stale_days` is reported.
#                            DEFAULT ON, read-only like the rest.
#
#                            The backlog is the default sink for every new item, so
#                            without an age report its only exits were promotion and
#                            silent deletion — an idea could never be recorded as
#                            "decided against", which is precisely the gap cc:dropped
#                            was introduced to close on the active side. Bullets already
#                            struck through (`- ~~...~~ declined <date>: reason`) are
#                            the DECLINED disposition and are skipped here: they are
#                            resolved, not stale.
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
BACKLOG=""
STALE_DAYS=""
ARCHIVE_DAYS=""
BACKLOG_STALE_DAYS=""
STALE_ENABLED=""
ARCHIVE_ENABLED=""
BACKLOG_ENABLED=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root)          ROOT="${2:-}"; shift 2 ;;
    --plans)         PLANS="${2:-}"; shift 2 ;;
    --backlog)       BACKLOG="${2:-}"; shift 2 ;;
    --stale-days)    STALE_DAYS="${2:-}"; shift 2 ;;
    --archive-days)  ARCHIVE_DAYS="${2:-}"; shift 2 ;;
    --backlog-stale-days) BACKLOG_STALE_DAYS="${2:-}"; shift 2 ;;
    --enable-stale)  STALE_ENABLED=true; shift ;;
    --disable-archive) ARCHIVE_ENABLED=false; shift ;;
    --disable-backlog) BACKLOG_ENABLED=false; shift ;;
    -h|--help)
      sed -n '2,75p' "$0" >&2
      exit 0 ;;
    *) echo "plans-sweep: unknown argument: $1" >&2; exit 0 ;;
  esac
done

ROOT="${ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
PLANS="${PLANS:-$ROOT/Plans.md}"
BACKLOG="${BACKLOG:-$ROOT/Plans-backlog.md}"
QUIET="${HARNESS_SWEEP_QUIET:-0}"

# The backlog sweep is independent of Plans.md: a project can have captured ideas going
# stale while its active file is missing entirely.
if [ ! -f "$PLANS" ] && [ ! -f "$BACKLOG" ]; then
  [ "$QUIET" = "1" ] || echo "plans-sweep: no Plans.md at $PLANS"
  exit 0
fi

# --- Config: harness.toml [plans], overridable by flags ----------------------------
toml_val() {  # $1 key -> value, or empty
  grep -E "^[[:space:]]*$1[[:space:]]*=" "$ROOT/harness.toml" 2>/dev/null |
    head -1 | sed 's/.*=[[:space:]]*//' | tr -d '"' | tr -d "'" | awk '{print $1}'
}
[ -n "$STALE_DAYS" ]      || STALE_DAYS="$(toml_val stale_days)"
[ -n "$ARCHIVE_DAYS" ]    || ARCHIVE_DAYS="$(toml_val archive_days)"
[ -n "$BACKLOG_STALE_DAYS" ] || BACKLOG_STALE_DAYS="$(toml_val backlog_stale_days)"
[ -n "$STALE_ENABLED" ]   || STALE_ENABLED="$(toml_val stale_sweep_enabled)"
[ -n "$ARCHIVE_ENABLED" ] || ARCHIVE_ENABLED="$(toml_val archive_sweep_enabled)"
[ -n "$BACKLOG_ENABLED" ] || BACKLOG_ENABLED="$(toml_val backlog_sweep_enabled)"
STALE_DAYS="${STALE_DAYS:-14}"
ARCHIVE_DAYS="${ARCHIVE_DAYS:-14}"
BACKLOG_STALE_DAYS="${BACKLOG_STALE_DAYS:-90}"
STALE_ENABLED="${STALE_ENABLED:-false}"
ARCHIVE_ENABLED="${ARCHIVE_ENABLED:-true}"
BACKLOG_ENABLED="${BACKLOG_ENABLED:-true}"
case "$STALE_DAYS" in ''|*[!0-9]*) STALE_DAYS=14 ;; esac
case "$ARCHIVE_DAYS" in ''|*[!0-9]*) ARCHIVE_DAYS=14 ;; esac
case "$BACKLOG_STALE_DAYS" in ''|*[!0-9]*) BACKLOG_STALE_DAYS=90 ;; esac

NOW="$(date +%s 2>/dev/null)"
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac   # no usable clock -> say nothing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COUNTS_LIB="$SCRIPT_DIR/lib/plans-counts.sh"
[ -r "$COUNTS_LIB" ] || exit 0
# shellcheck source=lib/plans-counts.sh
. "$COUNTS_LIB"
# A missing/unreadable Plans.md leaves every count at 0 and only disables T1/T2; T3
# reads Plans-backlog.md and must still run.
plans_counts_load "$PLANS" || true

OUT=""
add() { OUT="${OUT}${OUT:+
}$1"; }

# Per-row last-touch for Plans.md, computed at most once and shared by T1 and T2.
BLAME=""
if [ -f "$PLANS" ] && command -v git > /dev/null 2>&1 &&
   GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" rev-parse --git-dir > /dev/null 2>&1; then
  BLAME="$(GIT_OPTIONAL_LOCKS=0 git -C "$ROOT" blame --line-porcelain -- "$PLANS" 2>/dev/null)"
fi

# --- T1: stale active rows -> cc:dropped candidates --------------------------------
if [ "$STALE_ENABLED" = "true" ] && [ "$PLANS_ACTIVE" -gt 0 ]; then
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

# --- T2: PER-ROW terminal rows past archive_days -> archive candidates -------------
#
# The condition is on the ROW, never on the file. `PLANS_ACTIVE` is deliberately absent
# from this test: gating on an empty active set let a single never-finished cc:todo
# hold an arbitrarily large pile of cc:done rows in the active file indefinitely.
if [ "$ARCHIVE_ENABLED" != "false" ] && [ "$PLANS_TERMINAL" -gt 0 ]; then
  ARCH_ROWS=""
  if [ -n "$BLAME" ]; then
    ARCH_ROWS="$(printf '%s\n' "$BLAME" | awk -v now="$NOW" -v days="$ARCHIVE_DAYS" '
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
        # Same anchored rule the canonical counter uses, restricted to terminal states.
        bounded = 0
        if (index(s,"cc:done") == 1    && substr(s,8,1)  !~ /[A-Za-z0-9_-]/) bounded = 1
        if (index(s,"cc:dropped") == 1 && substr(s,11,1) !~ /[A-Za-z0-9_-]/) bounded = 1
        if (!bounded) next
        printf "   %-8s terminal %d days (%s)\n", id, age, s
      }')"
  fi
  if [ -n "$ARCH_ROWS" ]; then
    N_ARCH="$(printf '%s\n' "$ARCH_ROWS" | grep -c .)"
    add "plans sweep — T2 archive candidates (${N_ARCH} terminal row(s) >= ${ARCHIVE_DAYS}d untouched):"
    add "$ARCH_ROWS"
    add "   Move these rows to .claude/memory/archive/Plans-$(date +%Y-%m-%d).md."
    add "   Active rows stay put — this is a per-row rule, so ${PLANS_ACTIVE} unfinished row(s)"
    add "   do not hold the finished ones in the active file."
    add "   Suggestion only. Nothing has been changed."
  elif [ -z "$BLAME" ]; then
    # No git blame available (no repo, or the file is untracked). Fall back to the
    # file-level signal, which is strictly weaker and says so.
    MTIME="$(stat -c %Y "$PLANS" 2>/dev/null || stat -f %m "$PLANS" 2>/dev/null)"
    case "${MTIME:-}" in ''|*[!0-9]*) MTIME="" ;; esac
    if [ -n "$MTIME" ]; then
      AGE=$(( (NOW - MTIME) / 86400 ))
      if [ "$AGE" -ge "$ARCHIVE_DAYS" ]; then
        add "plans sweep — T2 archive suggested (no per-row history available):"
        add "   ${PLANS_TERMINAL} terminal row(s) (done ${PLANS_DONE}, dropped ${PLANS_DROPPED}) and the file"
        add "   has not been modified for ${AGE} days (threshold ${ARCHIVE_DAYS})."
        add "   git blame is unavailable here, so row ages could not be read individually."
        add "   Move the terminal rows to .claude/memory/archive/Plans-$(date +%Y-%m-%d).md."
        add "   Suggestion only. Nothing has been changed."
      fi
    fi
  fi
fi

# --- T3: Plans-backlog.md capture-date staleness -----------------------------------
#
# Read-only, like T1 and T2. The backlog is the default destination for new items, so
# it needs an exit that is neither promotion nor silent deletion. The age report is one
# half; the DECLINED disposition documented in Plans-backlog.md is the other.
#
# Only bullets under "## Captured" count, fenced examples are skipped, and a bullet that
# is already struck through (`- ~~text~~ declined <date>: reason`) is a RESOLVED item,
# not a stale one.
BACKLOG_STALE=""
BACKLOG_LIVE=0
BACKLOG_DECLINED=0
if [ "$BACKLOG_ENABLED" != "false" ] && [ -f "$BACKLOG" ]; then
  BACKLOG_REPORT="$(awk -v now="$NOW" -v days="$BACKLOG_STALE_DAYS" '
    function days_since(y, m, d,   ts, era, yoe, doy, doe) {
      # Days-from-civil (Howard Hinnant). mktime() is a gawk extension and this has to
      # run under mawk and busybox awk too.
      m = m + 0; y = y + 0; d = d + 0
      y -= (m <= 2)
      era = int((y >= 0 ? y : y - 399) / 400)
      yoe = y - era * 400
      doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
      doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
      ts = (era * 146097 + doe - 719468) * 86400
      return int((now - ts) / 86400)
    }
    { t = $0; sub(/^[[:space:]]+/, "", t)
      if (substr(t,1,3) == "```") { f = !f; next }
      if (f) next
      if (t ~ /^## +Captured/) { cap = 1; next }
      if (t ~ /^## /) { cap = 0; next }
      if (!cap) next
      if (t !~ /^[-*][[:space:]]+/) next
      body = t; sub(/^[-*][[:space:]]+/, "", body)
      if (body ~ /^~~/) { declined++; next }
      live++
      if (match(body, /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) == 0) { undated++; next }
      ds = substr(body, 1, 10)
      split(ds, p, "-")
      age = days_since(p[1], p[2], p[3])
      if (age < days) next
      label = body; sub(/^[0-9-]+[[:space:]]*(—|-)?[[:space:]]*/, "", label)
      if (length(label) > 52) label = substr(label, 1, 49) "..."
      printf "   %s  captured %d days ago  %s\n", ds, age, label
    }
    END { printf "@@ live=%d declined=%d undated=%d\n", live+0, declined+0, undated+0 }
  ' "$BACKLOG" 2>/dev/null)"
  BACKLOG_STALE="$(printf '%s\n' "$BACKLOG_REPORT" | grep -v '^@@ ' | grep . )"
  BACKLOG_SUMMARY="$(printf '%s\n' "$BACKLOG_REPORT" | grep '^@@ ' | head -1)"
  BACKLOG_LIVE="$(printf '%s' "$BACKLOG_SUMMARY" | sed -n 's/.*live=\([0-9]*\).*/\1/p')"
  BACKLOG_DECLINED="$(printf '%s' "$BACKLOG_SUMMARY" | sed -n 's/.*declined=\([0-9]*\).*/\1/p')"
  BACKLOG_LIVE="${BACKLOG_LIVE:-0}"; BACKLOG_DECLINED="${BACKLOG_DECLINED:-0}"
  if [ -n "$BACKLOG_STALE" ]; then
    N_STALE="$(printf '%s\n' "$BACKLOG_STALE" | grep -c .)"
    add "plans sweep — T3 backlog staleness (${N_STALE} of ${BACKLOG_LIVE} live item(s) >= ${BACKLOG_STALE_DAYS}d old):"
    add "$BACKLOG_STALE"
    add "   Four dispositions, all manual: PROMOTE (rewrite as a Plans.md row),"
    add "   DECLINE (strike the bullet through and append 'declined <date>: reason'),"
    add "   DUPLICATE (decline it, naming the surviving item), SNOOZE (re-date to today)."
    add "   Declining is the backlog's cc:dropped — it retires an idea without deleting it."
    add "   Suggestion only. Nothing has been changed."
  fi
fi

if [ -z "$OUT" ]; then
  [ "$QUIET" = "1" ] || echo "plans sweep: no candidates (active ${PLANS_ACTIVE}, terminal ${PLANS_TERMINAL}/${PLANS_TOTAL}, backlog live ${BACKLOG_LIVE:-0} declined ${BACKLOG_DECLINED:-0})"
  exit 0
fi

printf '%s\n' "$OUT"
exit 0
