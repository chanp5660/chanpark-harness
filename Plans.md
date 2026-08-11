# Plans.md — chanpark-harness

> **Active work only.** Terminal rows move to `.claude/memory/archive/`; unscheduled
> ideas live in `Plans-backlog.md`. This is the file that opens by default, and it is
> meant to stay short enough that opening it is never a chore.

- **Last updated**: 2026-08-11
- **Layout**: `Plans.md` (active) · `Plans-backlog.md` (capture, no markers) · `.claude/memory/archive/Plans-<date>.md` (terminal rows)
- **Caps**: 25 active rows soft / 30 hard / 1 `cc:wip` — see `harness.toml [plans]`

---

## Active

| ID | Task | DoD | Depends | Status |
|----|------|-----|---------|--------|

<!-- No active work. Add rows here, or capture unscheduled ideas in Plans-backlog.md. -->

---

## Marker Legend

The vocabulary is **closed**. Finer distinctions go in the Description cell, never into
a new marker — the canonical definition is `scripts/lib/plans-markers.awk` and every
consumer reads it through `scripts/lib/plans-counts.sh`.

| Marker | Class | Meaning | In denominator | Counts as progress |
|--------|-------|---------|----------------|--------------------|
| `cc:todo` | active | Not started | yes | no |
| `cc:wip` | active | In progress (at most one) | yes | no |
| `cc:blocked` | active | Waiting on something — still debt | yes | no |
| `cc:done` | terminal | Completed | yes | **yes** |
| `cc:dropped` | terminal | **Decided against.** Reason goes in the Description cell | yes | **yes** |
| `pm:requested` | gate | PM requested work | counted separately | — |
| `pm:approved` | gate | PM confirmed completion | counted separately | — |

Input aliases, normalised on read: `cursor:*` → `cc:*`, `cc:完了` → `cc:done`,
`pm:依頼中` → `pm:requested`, `cc:cancelled` / `cc:canceled` → `cc:dropped`.

`progress = (done + dropped) / (todo + wip + blocked + done + dropped)`

Dropping a task **advances** the plan rather than penalising it. If retiring work
lowered the percentage, the rational move would be to never retire anything, and the
file would grow until nobody read it — which is the failure this vocabulary was built
to kill. `cc:dropped` is reported separately everywhere it appears, so a plan cannot
reach 100% by quietly abandoning itself.

A status cell that matches nothing above is counted as `unknown` and flagged, not
silently absorbed into a neighbouring bucket. A row that vanishes from the denominator
is worse than a row in the wrong column.

**Only the last non-empty cell of a table row is a status.** Prose, legends, fenced
examples, HTML comments and a Description cell quoting a marker never count.

---

## History

Phases 1–6 (20 tasks, 2026-07-03 → 2026-07-08, all `cc:done`) were archived on
2026-08-11 to `.claude/memory/archive/Plans-2026-08-11.md`. The T2 archive sweep
(`scripts/plans-sweep.sh`) flagged this file on its first run: fully terminal, and
untouched for 33 days.
