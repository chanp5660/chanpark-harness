# scripts/lib/plans-markers.awk
# Canonical Plans.md marker counter — the single definition of "a task is in state X".
#
# Usage:  awk -f scripts/lib/plans-markers.awk Plans.md
# Output: one line, six space-separated integers, in this fixed order:
#           todo wip done blocked pm_requested pm_approved
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
# Why this file exists: the vendored Go binary's plans-watcher counted markers as
# unanchored substrings anywhere in the file, so a sentence mentioning cc:done
# inflated the done count. hud/statusline.sh already anchored on the table cell;
# this file makes that rule canonical and shared.
#
# Compat aliases (kept because harness has always claimed to read them):
#   cursor:<state>  is an alias of  cc:<state>
#   cc:完了 / cursor:完了  -> done
#   pm:依頼中              -> pm:requested

BEGIN { in_fence = 0; todo = 0; wip = 0; done = 0; blocked = 0; pm_req = 0; pm_app = 0 }

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

  # Prefix match: the cell may carry a trailing note, e.g. "cc:done [a1b2c3d]"
  # or "cc:done (2026-06-17: rewrote section 4)".
  if      (status ~ /^cc:todo/)      todo++
  else if (status ~ /^cc:wip/)       wip++
  else if (status ~ /^cc:done/)      done++
  else if (status ~ /^cc:完了/)      done++
  else if (status ~ /^cc:blocked/)   blocked++
  else if (status ~ /^pm:requested/) pm_req++
  else if (status ~ /^pm:依頼中/)    pm_req++
  else if (status ~ /^pm:approved/)  pm_app++
}

END { printf "%d %d %d %d %d %d\n", todo, wip, done, blocked, pm_req, pm_app }
