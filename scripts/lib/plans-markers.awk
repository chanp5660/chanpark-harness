# scripts/lib/plans-markers.awk
# Canonical Plans.md marker counter — the single definition of "a task is in state X".
#
# Usage:  awk -f scripts/lib/plans-markers.awk Plans.md
# Output: one line of labelled key=value pairs, in this fixed order:
#           todo=N wip=N done=N blocked=N dropped=N pm_requested=N pm_approved=N unknown=N
#
# Prefer scripts/lib/plans-counts.sh over parsing this line by hand: it is the shared
# loader every consumer uses, and it also derives active/terminal/total.
#
# ABI note (deliberate, one-time break)
# ------------------------------------
# This used to print six bare integers that callers read POSITIONALLY
# ("read -r TODO WIP DONE BLOCKED PM_REQ PM_APP"). Adding a seventh column would have
# silently shifted every reader — plans-watcher.sh would have written "0 0" into a JSON
# number field and produced invalid JSON. Labels make every future state additive:
# an unknown key is simply ignored by a reader that does not know it.
#
# Counting rule
# -------------
# A marker counts ONLY when it is the status cell of a markdown table row:
#
#   | 27.1 | Fix the parser | DoD | - | cc:done |     <- counted (done)
#   Phase 22~26 moved to the archive (all cc:done).   <- NOT counted (prose)
#
# The status cell is the LAST non-empty cell of the row, with code spans stripped
# *within that cell only*. That preserves the case where a description cell quotes
# a marker (`cc:wip`) while the real status cell says cc:done, and it also rejects
# the marker legend table, whose first cell is the marker but whose last cell is
# a prose description.
#
# Skipped outright: fenced code blocks (``` ... ```), HTML comment lines, and every
# line that is not a table row (prose, headings, checklists, sub-bullets).
#
# Checklist rows ("- [x] Ship it `cc:done`") are deliberately NOT counted here. This
# counter feeds the HUD and plans-state.json, neither of which has ever counted them;
# scripts/progress-snapshot.sh and wip-guard.sh do handle that dialect on purpose.
#
# Word-boundary matching (not prefix matching)
# --------------------------------------------
# A marker matches only when the character right after it is not [A-Za-z0-9_-].
# The old rule was a bare prefix match, so an invented state was ABSORBED by its
# parent bucket instead of being reported:
#
#   cc:wip-paused    -> counted as wip, AND armed the Stop guard, trapping the session
#   cc:done-reverted -> counted as done
#
# Trailing notes still work, because they are separated by a space or a bracket:
#   "cc:done [a1b2c3d]", "cc:done (2026-06-17: rewrote section 4)".
#
# The closed vocabulary
# ---------------------
#   active   : cc:todo  cc:wip  cc:blocked          (still debt)
#   terminal : cc:done  cc:dropped                  (both contribute to progress)
#   gate     : pm:requested  pm:approved            (counted separately)
#
# cc:dropped means "decided against". It is terminal, it STAYS IN THE DENOMINATOR
# and it counts toward progress exactly like cc:done. That is the load-bearing half:
# if dropping a task lowered the completion percentage, the operator learns never to
# drop anything and the file grows forever, which is the failure this vocabulary exists
# to kill. Finer distinctions belong in the description cell, never in a new marker.
#
# The unknown bucket
# ------------------
# A status cell that looks like a marker (cc:* / pm:*) but matches nothing known is
# counted as `unknown` rather than being dropped on the floor. Previously such a row
# vanished from every bucket AND from the denominator, so the total silently shrank —
# a corrupted denominator is worse than a wrong bucket. Consumers surface `unknown`
# so a typo ("cc:cancelled" misspelt further, "cc:donee") is visible instead of silent.
#
# Compat aliases (kept because harness has always claimed to read them):
#   cursor:<state>              is an alias of  cc:<state>
#   cc:完了 / cursor:完了       -> done
#   pm:依頼中                   -> pm:requested
#   cc:cancelled / cc:canceled  -> dropped   (industry spelling, both variants;
#                                             `dropped` is canonical because it has
#                                             exactly one spelling and cannot drift)

# Does `s` begin with marker `m`, ended by a non-word character (or end of cell)?
function marker(s, m,   rest) {
  if (index(s, m) != 1) return 0
  rest = substr(s, length(m) + 1)
  if (rest == "") return 1
  return (substr(rest, 1, 1) !~ /[A-Za-z0-9_-]/)
}

BEGIN {
  in_fence = 0
  todo = 0; wip = 0; done = 0; blocked = 0; dropped = 0
  pm_req = 0; pm_app = 0; unknown = 0
}

{
  line = $0
  trimmed = line
  gsub(/^[[:space:]]+/, "", trimmed)

  # Fenced code blocks hold documentation examples, not task records.
  if (substr(trimmed, 1, 3) == "```") { in_fence = !in_fence; next }
  if (in_fence) next

  # HTML comments are documentation/section labels.
  if (substr(trimmed, 1, 4) == "<!--") next

  # Table rows only.
  if (line !~ /^[[:space:]]*\|/) next

  n = split(line, cell, "|")
  status = ""
  for (i = n; i >= 1; i--) {
    s = cell[i]
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    if (s != "") {
      gsub(/`[^`]*`/, "", s)                          # strip code spans in the status cell
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      status = tolower(s)
      break
    }
  }
  if (status == "") next

  # Normalize the cursor: alias onto cc: before matching.
  sub(/^cursor:/, "cc:", status)

  if      (marker(status, "cc:todo"))      todo++
  else if (marker(status, "cc:wip"))       wip++
  else if (marker(status, "cc:done"))      done++
  else if (marker(status, "cc:完了"))      done++
  else if (marker(status, "cc:blocked"))   blocked++
  else if (marker(status, "cc:dropped"))   dropped++
  else if (marker(status, "cc:cancelled")) dropped++
  else if (marker(status, "cc:canceled"))  dropped++
  else if (marker(status, "pm:requested")) pm_req++
  else if (marker(status, "pm:依頼中"))    pm_req++
  else if (marker(status, "pm:approved"))  pm_app++
  # A cell that advertises itself as a marker but matches nothing known must stay
  # visible; silently discarding it corrupts the denominator.
  else if (status ~ /^cc:/ || status ~ /^pm:/) unknown++
}

END {
  printf "todo=%d wip=%d done=%d blocked=%d dropped=%d pm_requested=%d pm_approved=%d unknown=%d\n", \
    todo, wip, done, blocked, dropped, pm_req, pm_app, unknown
}
