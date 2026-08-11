# Plans.md — chanpark-harness

> **Active work only.** Terminal rows move to `.claude/memory/archive/`; unscheduled
> ideas live in `Plans-backlog.md`. This file opens by default and is budgeted to stay
> readable in one screen.

- **Last updated**: 2026-08-11
- **Budgets** (`harness.toml [plans]`): 25 active rows soft / 30 hard · 1 `cc:wip` ·
  **80 lines** whole-file. Rows over the hard cap are refused into the backlog; length
  over budget is reported, never refused — archive terminal rows instead.
- **Format, legend, aliases, dispositions**: `skills/harness-plan/references/plans-format.md`.
  Executable definition: `scripts/lib/plans-markers.awk`.

---

## Active

| ID | Task | DoD | Depends | Status |
|----|------|-----|---------|--------|

<!-- No active work. Add rows here, or capture unscheduled ideas in Plans-backlog.md. -->

---

## Markers

`cc:todo` · `cc:wip` · `cc:blocked` (active, in the denominator) — `cc:done` ·
`cc:dropped` (terminal, both count as progress) — `pm:requested` · `pm:approved`
(gates, counted separately). The vocabulary is **closed**; an unrecognised status cell
is reported as `unknown`, never absorbed into a neighbouring bucket.

`progress = (done + dropped) / (todo + wip + blocked + done + dropped)`. Dropping
**advances** the plan: if retiring work lowered the percentage, the rational move would
be to never retire anything, and this file would grow until nobody read it.

**Only the last non-empty cell of a table row is a status.** Prose, this section, fenced
examples, HTML comments and a Task cell quoting a marker never count.

---

## History

Phases 1–6 (20 tasks, 2026-07-03 → 2026-07-08, all `cc:done`) were archived on
2026-08-11 to `.claude/memory/archive/Plans-2026-08-11.md`.
