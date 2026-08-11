# Plans-backlog.md — unscheduled capture

**No `cc:` markers in this file. Ever.** Not in a table, not in prose, not in a code
span. That is the one rule, and it is enforced by physics rather than by discipline:
every counter in this repo recognises a task by its marker, so a file with no markers
returns zero from all of them even if somebody points a counter at it by mistake.
There is no `cc:backlog` state — adding one would put the backlog straight back into
the progress numbers and undo the entire reason this file is separate.

## What goes here

Anything you want to remember but have not committed to doing. Ideas, half-formed
complaints, "we should probably…", links to read.

## What does NOT go here

Work in flight. If you are doing it, it belongs in `Plans.md` as a table row with a
real status marker.

## Format

Plain bullets with a capture date. Not table rows — a second layer of safety, since the
canonical counter only ever looks at table rows.

```
- 2026-08-11 — Idea, one line, with enough context to be understandable in six months.
```

The date is load-bearing: `scripts/plans-sweep.sh` reads it. A bullet with no date is
counted as live and never ages, so it can never be reported.

## Four dispositions — every item has an exit

This file is the default destination for new items, which makes its lifecycle the whole
question. If the only exit were promotion, the file would be a one-way sink and would
grow without limit — the same failure `cc:dropped` was introduced to close on the active
side, reappearing one file over. Linear's Triage offers accept / duplicate / decline /
snooze; these are the same four, written for a text file.

| Disposition | How | Effect |
|-------------|-----|--------|
| **Promote** | Rewrite the bullet as a full `Plans.md` row with an ID and a DoD, then delete the bullet | Enters the active set |
| **Decline** | Strike the bullet through in place and append `declined <YYYY-MM-DD>: <reason>` | Retired, still on the record |
| **Duplicate** | Decline it, naming the surviving row or bullet in the reason | Retired without losing the trail |
| **Snooze** | Re-date the bullet to today | Resets its staleness clock, explicitly and visibly |

Declining is what the terminal drop marker is on the active side: a decision, recorded,
costing one line. (The marker itself still may not appear in this file — the disposition
is carried by the strike-through, not by a marker.)

```
- ~~2026-02-03 — Add a second progress bar to the HUD~~ declined 2026-08-11: the HUD
  already shows terminal/total; a second bar would just restate it.
```

Deleting a bullet is the only disposition with no record, which is exactly what these
four exist to replace.

**Declined bullets are inert.** They are excluded from the live count in the session
monitor, skipped by the T3 staleness report, and never compared by
`scripts/plans-dupe-check.sh` — a retired idea must not keep flagging its own successor.
Once they accumulate, move them in bulk to
`.claude/memory/archive/Plans-<YYYY-MM-DD>.md`, the same place terminal rows go.

## Promotion is a rewrite, on purpose

To start work on a backlog item, **rewrite it by hand** as a table row in `Plans.md`
with an ID, a Definition of Done and `cc:todo`. There is no automatic promotion and
there will not be one.

The friction is the feature. Shape Up's backlog-free discipline works because pitching
an idea costs you something — you have to convince a colleague. Working solo with
agents, nobody is there to lobby, so the cost of adding work drops to zero and the list
grows without limit. Retyping the item as a proper row, with a DoD you have to actually
write, is the substitute for that missing conversation. If an item is not worth
restating in full, it was not worth doing.

## What is swept, and what is not

This file has **no row cap and no line budget** — it is capture, and capping capture
just moves the loss somewhere unrecorded. What it does have is an age report:
`scripts/plans-sweep.sh` (T3) lists live bullets older than `backlog_stale_days`
(90 days, `harness.toml [plans]`) so that they surface and get one of the four
dispositions. Like every other trigger in the sweep, T3 **only prints**. Nothing in this
repo edits a bullet on a timer.

Duplicates: `scripts/plans-dupe-check.sh <description>` compares a proposed item against
both `Plans.md` rows and the live bullets here, and prints anything at Jaccard >= 0.4.
Advisory — it never refuses a write.

## When the active file is full

`harness-plan` routes new items here automatically once `Plans.md` passes the soft cap
of 25 active rows, and refuses to add to `Plans.md` at all past the hard cap of 30.
Both numbers live in `harness.toml [plans]`. Overflow lands in a recoverable place
instead of quietly making the active file unreadable.

---

## Captured

<!-- Append below. Newest last. -->

(nothing yet)
