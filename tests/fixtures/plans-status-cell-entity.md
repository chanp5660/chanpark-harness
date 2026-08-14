# plans-status-cell-entity.md — Test Fixture
#
# Regression fixture for the marker DEFLATION bug (the mirror image of
# plans-prose-marker-inflation.md).
#
# Commit 598f4a11 ("chore: audit follow-ups") neutralised marker tokens that were
# QUOTED IN A DESCRIPTION CELL by substituting `cc:` -> `cc&#58;`. The substitution
# was applied to the WHOLE LINE, so on every row whose description quoted a marker
# it also hit the STATUS cell. Four rows of the real Plans.md ended up with a status
# cell reading `cc&#58;done`, which:
#
#   - renders as a perfectly normal `cc:done` in every markdown viewer, and
#   - is invisible to the canonical counter, which sees no `cc:` prefix at all.
#
# Result: a 20-row all-done ledger reported done=16. A silent 20% undercount.
#
# Expected canonical counts (scripts/lib/plans-markers.awk):
#   todo=1 wip=1 done=3 blocked=1 dropped=1 pm_requested=0 pm_approved=0 unknown=0
#
# The invariant the guard pins: NO status cell may contain an HTML entity. The repair
# belongs in the escaping step, never in the counter — teaching the counter to decode
# `&#58;` would also decode the marker legend below, which is escaped ON PURPOSE so
# that a legend row is never mistaken for a task.

## Marker legend (escaped on purpose — these must never be counted)

| Marker | State | Description |
|--------|-------|-------------|
| cc&#58;todo | To do | Scheduled for implementation |
| cc&#58;wip | In progress | Currently being implemented |
| cc&#58;dropped | Dropped | Decided against; terminal |

## Phase 1

| ID | Task | DoD | Depends | Status |
|----|------|-----|---------|--------|
| 1.1 | Unify marker spelling; remove every `cc&#58;Done` from the skills | Single grep check passes | - | cc:done |
| 1.2 | Escape quoted markers such as cc&#58;todo in description cells only | Status cells stay literal | 1.1 | cc:done [2fb3396b] |
| 1.3 | Teach the counter about cc&#58;dropped | New bucket reported | 1.1 | cc:done (2026-08-11: shipped) |
| 1.4 | Write the deflation guard, mirroring the cc&#58;done inflation guard | Guard fails on a broken status cell | 1.3 | cc:todo |
| 1.5 | Wire the shared loader into every consumer of cc&#58;wip counts | Four consumers converted | 1.3 | cc:wip |
| 1.6 | Re-vendor the upstream binary so its cc&#58;blocked counter anchors too | No Go source here | - | cc:blocked |
| 1.7 | Rewrite the HUD in Node so cc&#58;done renders faster | Rejected: no build step allowed | - | cc:dropped |
