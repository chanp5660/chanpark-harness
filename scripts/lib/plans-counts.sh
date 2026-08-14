#!/usr/bin/env bash
# scripts/lib/plans-counts.sh
# Shared Plans.md count loader — the ONE place that parses the counter's output.
#
# Source it, then call plans_counts_load:
#
#   . "$SCRIPT_DIR/../lib/plans-counts.sh"
#   plans_counts_load "/path/to/Plans.md" || echo "counter unavailable"
#   echo "$PLANS_DONE / $PLANS_TOTAL"
#
# Exports (all integers, all always set — 0 on any failure):
#   PLANS_TODO PLANS_WIP PLANS_BLOCKED     active states (still debt)
#   PLANS_DONE PLANS_DROPPED               terminal states (both count as progress)
#   PLANS_PM_REQUESTED PLANS_PM_APPROVED   gate markers, counted separately
#   PLANS_UNKNOWN                          status cells that look like a marker but
#                                          match nothing in the closed vocabulary
#   PLANS_ACTIVE   = todo + wip + blocked
#   PLANS_TERMINAL = done + dropped
#   PLANS_TOTAL    = active + terminal          (unknown is NOT in the denominator;
#                                                it is a defect signal, not a state)
#   PLANS_PCT      = 100 * terminal / total     (0 when total is 0)
#
# Returns 0 on success, 1 when the file or the counter is unreadable (counts stay 0).
#
# Why this file exists
# --------------------
# The marker vocabulary used to be re-implemented in at least nine places — the HUD
# had two dialects of its own, wip-guard another two, progress-snapshot a Python
# startswith chain — and they had already drifted apart from each other before anyone
# tried to add a state. Every consumer now reads the same numbers from the same awk
# program, so adding the next state is a one-file change plus a guard case.
#
# progress = terminal / total, NOT done / total. A dropped task is a decision that has
# been made; leaving it out of the numerator would train the operator never to drop
# anything. blocked IS in the denominator (the HUD used to omit it, which overstated
# completion on any plan with a blocked row).

# Resolve the counter relative to THIS file, so the loader works no matter what the
# caller's working directory is.
_plans_counts_awk() {
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s/plans-markers.awk' "$here"
}

plans_counts_reset() {
  PLANS_TODO=0; PLANS_WIP=0; PLANS_DONE=0; PLANS_BLOCKED=0; PLANS_DROPPED=0
  PLANS_PM_REQUESTED=0; PLANS_PM_APPROVED=0; PLANS_UNKNOWN=0
  PLANS_ACTIVE=0; PLANS_TERMINAL=0; PLANS_TOTAL=0; PLANS_PCT=0
}

plans_counts_load() {
  local file="$1" counter raw key val pair
  plans_counts_reset

  counter="$(_plans_counts_awk)"
  [ -n "$file" ] && [ -f "$file" ] && [ -r "$file" ] || return 1
  [ -r "$counter" ] || return 1

  raw="$(awk -f "$counter" "$file" 2>/dev/null)"
  [ -n "$raw" ] || return 1

  # Labelled k=v parsing: an unrecognised key is ignored rather than shifting every
  # later field, which is the whole point of moving off the positional format.
  for pair in $raw; do
    key="${pair%%=*}"; val="${pair#*=}"
    case "$val" in ''|*[!0-9]*) continue ;; esac
    case "$key" in
      todo)         PLANS_TODO="$val" ;;
      wip)          PLANS_WIP="$val" ;;
      done)         PLANS_DONE="$val" ;;
      blocked)      PLANS_BLOCKED="$val" ;;
      dropped)      PLANS_DROPPED="$val" ;;
      pm_requested) PLANS_PM_REQUESTED="$val" ;;
      pm_approved)  PLANS_PM_APPROVED="$val" ;;
      unknown)      PLANS_UNKNOWN="$val" ;;
    esac
  done

  PLANS_ACTIVE=$((PLANS_TODO + PLANS_WIP + PLANS_BLOCKED))
  PLANS_TERMINAL=$((PLANS_DONE + PLANS_DROPPED))
  PLANS_TOTAL=$((PLANS_ACTIVE + PLANS_TERMINAL))
  if [ "$PLANS_TOTAL" -gt 0 ]; then
    PLANS_PCT=$(( (PLANS_TERMINAL * 100 + PLANS_TOTAL / 2) / PLANS_TOTAL ))
  else
    PLANS_PCT=0
  fi
  return 0
}

plans_counts_reset
