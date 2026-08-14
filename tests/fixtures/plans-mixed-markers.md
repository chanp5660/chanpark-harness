# plans-mixed-markers.md — Test Fixture
#
# Contains BOTH status formats to exercise counter/parser edge cases.
#
# Expected counts (v2 table rows only — prose and checklists are NOT counted as table rows):
#   cc:todo   → 1 (row)  +  cc:TODO  → 1 (row)  = 2 table rows with todo-status
#   cc:wip    → 1 (row)  +  cc:WIP   → 1 (row)  = 2 table rows with wip-status
#   cc:done   → 1 (row)  +  cc:Done  → 1 (row)  = 2 table rows with done-status
#   cc:blocked → 1 (row)
#   cc:dropped → 1 (row) + cc:cancelled → 1 (row, alias) = 2 table rows with dropped-status
#   cc:wip-paused → 1 (row) counted as UNKNOWN, never as wip
#   Total v2 table rows: 10
#
# The last two lines are the load-bearing ones:
#   - cc:cancelled is an INPUT ALIAS of cc:dropped. `dropped` is canonical because it
#     has a single spelling; `cancelled`/`canceled` is the industry word and splits in
#     two, and a marker that splits in two is a marker that silently vanishes.
#   - cc:wip-paused must NOT be absorbed by cc:wip. Under the old prefix match it was,
#     and because wip-guard shares this vocabulary a single such row blocked Stop
#     forever: the session could never end. It is now reported as `unknown`, which is
#     visible, keeps the denominator honest, and does not arm any guard.
#
# Checklist lines (separate format — NOT table rows):
#   - [ ] cc:todo  → 1
#   - [x] cc:done  → 1
#
# Prose mentions (must NOT be counted by table/checklist counters):
#   "cc:wip"  → 1 prose sentence (ignored by counters)
#
# T001-style ID rows: 1

## Sprint v2 Table

| ID   | Task                        | Content                                    | DoD                                      | Depends | Status                   |
|------|-----------------------------|--------------------------------------------|------------------------------------------|---------|--------------------------|
| T001 | Add baseline checks         | Create scripts/ci/check-baseline.sh        | Script exits 0 on clean repo             | —       | cc:todo                  |
| T002 | Fix identity mismatch       | Align harness.toml with plugin.json name   | check-regression-guard passes identity   | T001    | cc:TODO                  |
| T003 | Fix grep paths              | Replace /usr/bin/grep with grep            | check-regression-guard passes grep-path  | T001    | cc:wip                   |
| T004 | Add english-only guard      | Validate CJK absence in agents/ skills/    | check-regression-guard passes english    | T001    | cc:WIP                   |
| T005 | Update README               | Reflect new CI scripts in documentation    | README updated, links valid              | T002    | cc:done                  |
| T006 | Bump version                | Increment plugin.json + harness.toml       | Version fields in sync                   | T005    | cc:Done [abc1234]        |
| T007 | Freeze binary paths         | Audit all hook paths for hardcoded /usr/   | Zero /usr/bin refs outside bin/          | T003    | cc:blocked               |
| T008 | Rewrite the HUD in Node     | Port statusline.sh to a compiled renderer  | Rejected: repo forbids a build step      | —       | cc:dropped               |
| T009 | Vendor a second marketplace | Mirror the catalog to a backup host        | Rejected: no second host exists          | —       | cc:cancelled             |
| T010 | Await the upstream Go source| Blocked on a release that may never happen | n/a — state is not in the vocabulary     | T003    | cc:wip-paused            |

## Checklist Format (legacy / alternate)

- [ ] Some task `cc:todo`
- [x] Done task `cc:done`

## Prose Section

The team is currently monitoring progress and the next step will transition from cc:wip to cc:done once the CI pipeline is stable.
