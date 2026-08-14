# Plans.md format reference

The long-form definition of the plan file format. It lives here rather than inside
`Plans.md` because `Plans.md` has a line budget (`harness.toml [plans] max_lines`, 80)
and this material was 40+ lines of it — boilerplate that pushed a full 30-row plan to 93
lines, past the point where the file reads in one screen. The rules did not change; only
their address did.

Read this when authoring or repairing a plan file. The executable definition is
`scripts/lib/plans-markers.awk`; everything below describes what that program does.

## The three files

| File | Holds | Read by counters |
|------|-------|------------------|
| `Plans.md` | Active work + terminal rows not yet archived | yes |
| `Plans-backlog.md` | Unscheduled capture, plain bullets, **no `cc:` markers** | no |
| `.claude/memory/archive/Plans-<YYYY-MM-DD>.md` | Terminal rows that have left the active set | no |

Separation is by **file boundary**, not by heading. A `## Backlog` section is not a
filter: every parser scans the whole file, so a section would land straight in the
counts and the denominator. That is the v1.3.6 bug one level up.

## Table dialect is required

A marker counts as a task **only when it is the status cell** — the last non-empty cell
of a table row. A checklist (`- [ ] task cc:todo`) is not a table row, so the canonical
counter scores it zero and the HUD, the plans-watcher hook and the progress snapshot all
report an empty plan. Earlier template versions shipped the checklist form, and new
projects started with a blank HUD as a result.

**Columns**: `ID` (`1.1`, `T001`, …), `Task`, `DoD`, `Depends` (`-`, `1.1`, or
`1.1, 1.2`), `Status`.

**DoD**: one verifiable line, Yes/No evaluable. "Works properly" is not a DoD.

Prose, the legend, fenced examples, HTML comments and a Description cell that quotes a
marker are all ignored by the counter.

## Marker vocabulary — closed

Finer distinctions belong in the Task cell, never in a new marker.

| Marker | Class | Meaning | In denominator | Counts as progress |
|--------|-------|---------|----------------|--------------------|
| `cc:todo` | active | Not started | yes | no |
| `cc:wip` | active | In progress (at most one at a time) | yes | no |
| `cc:blocked` | active | Waiting on something — still debt, reason required | yes | no |
| `cc:done` | terminal | Completed | yes | **yes** |
| `cc:dropped` | terminal | **Decided against.** Reason required in the Task cell | yes | **yes** |
| `pm:requested` | gate | PM requested work | counted separately | — |
| `pm:approved` | gate | PM confirmed completion | counted separately | — |

`progress = (done + dropped) / (todo + wip + blocked + done + dropped)`

Input aliases, normalised on read: `cursor:*` → `cc:*`, uppercase spellings (matching is
case-insensitive), the two legacy Japanese spellings kept as read aliases, and
`cc:cancelled` / `cc:canceled` → `cc:dropped`. Write the canonical lowercase form.
`dropped` is canonical because it has exactly one spelling, while `cancelled`/`canceled`
splits in two, and a marker that splits in two eventually goes uncounted.

A trailing note on the status cell is fine: `cc:done [a1b2c3d]`,
`cc:done (2026-06-17: rewrote §4)`, `cc:dropped — superseded by 2.4`.

### Dropping is progress, not failure

A task decided against is resolved. If retiring work lowered the completion percentage,
the rational move would be to never retire anything, and the file would grow until
nobody opened it — the exact failure this vocabulary exists to kill. `cc:dropped` is
displayed separately everywhere it appears, so a plan cannot reach 100% by quietly
abandoning itself.

### Unknown is a defect, not a state

A status cell matching nothing above is reported as `unknown` rather than folded into a
neighbouring bucket. A row that vanishes from the denominator is worse than a row in the
wrong column.

## Budgets

| Budget | Value | Counted over | Overflow |
|--------|-------|--------------|----------|
| Soft row cap | 25 | active rows only | warn; route new items to `Plans-backlog.md` |
| Hard row cap | 30 | active rows only | refuse to add to `Plans.md`; route to the backlog |
| WIP cap | 1 | `cc:wip` rows | one active bet at a time; `wip-guard` assumes it |
| Line budget | 80 | **whole file**, boilerplate included | **report, never refuse** — run the sweep and archive terminal rows |

All four live in `harness.toml [plans]`.

Row caps count active rows only, or the cap would fight the archive sweep. The line
budget counts everything, because unreadability does not care which rows are finished.
The two are independent and both are needed: terminal rows waiting to be archived add
length without touching the row count.

Length overflow is **reported, never refused**. Refusing a write because a description
is well written would punish good writing, which is why a line cap was rejected as
admission control. The remedy is always to move terminal rows out, never to write less.

Where the notice appears: `scripts/hook-handlers/session-monitor.sh` at session start,
and `scripts/hook-handlers/plans-watcher.sh` on every write to `Plans.md` — the second
one matters because the session monitor does not run in headless `-p` mode.

## Archiving

Archiving is the job of `scripts/plans-sweep.sh`, which **proposes and never writes**.

The rule is **per row**: any terminal row untouched for `archive_days` (git-blame
author-time) is a candidate, no matter what else is in the file. It is deliberately not
a whole-file condition — gating on "every row is terminal" let one never-finished
`cc:todo` hold an unbounded pile of `cc:done` rows in the active file forever.

Do not hand-move rows out to make the file look tidy. An archive that doubles as a
hiding place for uncomfortable work stops being a record.

## Backlog dispositions

`Plans-backlog.md` has four resolutions, all manual, all recorded in the file:

| Disposition | How | Effect |
|-------------|-----|--------|
| Promote | Rewrite the bullet as a full `Plans.md` row with an ID and a DoD, then delete the bullet | Enters the active set |
| Decline | Strike the bullet through and append `declined <YYYY-MM-DD>: <reason>` | Retired, still on the record. This is the backlog's `cc:dropped` |
| Duplicate | Decline it, naming the surviving row or bullet in the reason | Retired without losing the trail |
| Snooze | Re-date the bullet to today | Resets its staleness clock, explicitly and visibly |

Declined bullets are excluded from the live count and from the T3 staleness report, and
may be moved to the archive file in bulk once they pile up. Deleting a bullet outright
is the one disposition with no record, and is the thing these four exist to replace.

## Optional extended syntax

| Syntax | Meaning | Example |
|--------|---------|---------|
| `[P]` | Parallelizable with other ready tasks | `Build the product API [P]` |
| `[tdd:required]` | Write a failing test first | `Auth token refresh [tdd:required]` |
| `[tdd:skip:<reason>]` | Skip TDD, with a stated reason | `[tdd:skip:docs-only]` |

`<reason>` must not be empty.
