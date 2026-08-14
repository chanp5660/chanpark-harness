# plans-prose-marker-inflation.md — Test Fixture
#
# Regression fixture for the v1.3.6 marker-counting bug.
#
# The vendored Go binary's plans-watcher matched cc:* as unanchored substrings anywhere
# in the file, so the archive sentence below was counted as a tenth finished task and
# .claude/state/plans-state.json reported cc_done = 10 for a nine-row table.
#
# Expected canonical counts (scripts/lib/plans-markers.awk):
#   todo=6  wip=0  done=9  blocked=0  dropped=0  pm_requested=0  pm_approved=0  unknown=0
#
# Every marker outside a status cell in this file MUST be ignored:
#   - the archive sentence in prose                      (cc:done)
#   - the drop-rationale sentence in prose               (cc:dropped)
#   - the marker legend table, marker in the FIRST cell  (cc:todo / cc:wip / cc:blocked / cc:dropped)
#   - the fenced code block                              (cc:wip / cc:done / cc:dropped)
#   - the HTML comment                                   (cc:done)
#   - a description cell quoting a marker in a code span (`cc:wip`)
#   - the bare word "blocked" in prose
#
# dropped=0 is asserted here on purpose. Prose ABOUT dropping tasks is exactly the kind
# of sentence a plan file accumulates once the state exists, and an unanchored counter
# would report phantom retirements — the same defect as the archive sentence, one state
# later. The guard would prove nothing if the fixture did not carry the trap.

- **Archive**: Phase 22~26 moved to `Plans-archive-2026-07-27.md` (all cc:done).
- **Note**: nothing is blocked right now; the earlier item that was blocked shipped.
- **Pruning**: two candidates from Phase 21 were retired as cc:dropped before this file was written.

## Marker legend

| Marker | State | Description |
|--------|-------|-------------|
| cc:todo | To do | Scheduled for implementation |
| cc:wip | In progress | Currently being implemented |
| cc:blocked | Blocked | Waiting on a dependency task |
| cc:dropped | Dropped | Decided against; terminal, counts toward progress |

<!-- Reviewer note: 27.4 was already cc:done before this table was written. -->

```
| 99 | Example row from the docs | DoD | - | cc:wip |
| 98 | Another example          | DoD | - | cc:done |
| 97 | How to retire a task     | DoD | - | cc:dropped |
```

## Phase 27

| ID | Task | DoD | Depends | Status |
|----|------|-----|---------|--------|
| 27.0 | Correct the port document | Rewritten | - | cc:done (2026-06-17: full rewrite) |
| 27.1 | numpy 2.x compatibility gate | Import + inference pass | - | cc:done |
| 27.2 | VRAM and fps measurement | Numbers recorded | 27.1 | cc:done [a1b2c3d] |
| 27.3 | Package the core | `pip install -e .` succeeds | 27.1 | cc:done |
| 27.4 | Operation event sender | Unit tests pass | 27.3 | cc:done |
| 27.5 | Frame processor | Unit tests pass | 27.3 | cc:done |
| 27.6 | Mock edge-api E2E | POST count equals log count | 27.5 | cc:done |
| 27.7 | Adapter scaffold | Import succeeds | 27.5 | cc:done |
| 27.8 | Stream integration — the row that flips `cc:wip` to done | Toggle works | 27.7 | cc:done |

## Phase 28

| ID | Task | DoD | Depends | Status |
|----|------|-----|---------|--------|
| 28.1 | On-site ROI setup UI | Manual drag saves the cache | - | cc:todo |
| 28.2 | Installation guide | Reproduced once on new hardware | 28.1 | cc:todo |
| 28.3 | Test result report | Pass/Fail recorded per item | 28.2 | cc:todo |
| 28.4 | Motion score threshold rationale | Threshold documented | - | cc:todo |

## Phase 29

| ID | Task | DoD | Depends | Status |
|----|------|-----|---------|--------|
| 29.1 | Experiment plan | Three axes defined | - | cc:todo |
| 29.2 | Backend comparison table | Nine cells filled | 29.1 | cc:todo |
