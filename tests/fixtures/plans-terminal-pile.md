# Plans.md — fixture: a pile of terminal rows behind one unfinished row

Pins the PER-ROW archive rule (`scripts/plans-sweep.sh` T2).

The archive trigger used to be a whole-FILE condition: every row terminal AND the file
untouched for `archive_days`. This fixture is the counter-example that rule cannot
handle — 12 finished rows held hostage by a single `cc:todo` that nobody will ever
close. Under the file-level rule the sweep reports "no candidates" forever, the active
row caps never trip (they count active rows only, and there is exactly one), and T1
cannot see it either — T1 targets ACTIVE rows, so even with T1 on it reports A1 and
says nothing about the 12 finished rows piling up behind it. The file grows without
bound in the one file that opens by default.

Expected under the per-row rule: all 12 terminal rows are reported as archive
candidates; `A1` is not.

| ID | Task | DoD | Depends | Status |
|----|------|-----|---------|--------|
| D1 | Wire the counter through the shared loader | loader is the only parse point | - | cc:done |
| D2 | Anchor marker matching to the status cell | prose no longer counts | - | cc:done |
| D3 | Add the dropped state to every consumer | all nine agree | D2 | cc:done |
| D4 | Split the backlog into its own file | no markers in it | - | cc:done |
| D5 | Teach the HUD the new denominator | blocked rows included | D1 | cc:done |
| D6 | Repair the escaped status cells | 20 of 20 counted | - | cc:done |
| D7 | Stop the WIP guard trapping sessions | owner-scoped only | - | cc:done |
| D8 | Move the legend out of the active file | file fits the budget | - | cc:done |
| X1 | Second progress bar in the HUD | reason recorded in this cell | - | cc:dropped |
| X2 | A cc:backlog marker | reason recorded in this cell | - | cc:dropped |
| X3 | Auto-rewrite stale rows on a timer | reason recorded in this cell | - | cc:dropped |
| X4 | Byte cap as admission control | reason recorded in this cell | - | cc:dropped |
| A1 | Perpetually unfinished, blocks nothing under the per-row rule | never | - | cc:todo |
