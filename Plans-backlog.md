# Plans-backlog.md — unscheduled capture

**No `cc:` markers in this file. Ever.** Not in a table, not in prose, not in a code
span. That is the one rule, and it is enforced by physics rather than by discipline:
every counter in this repo recognises a task by its marker, so a file with no markers
returns zero from all of them even if somebody points a counter at it by mistake.
There is no `cc:backlog` state — adding one would put the backlog straight back into
the progress numbers and undo the entire reason this file is separate.

## What goes here

Anything you want to remember but have not committed to doing. Ideas, half-formed
complaints, "we should probably…", links to read. Append freely; this file has no cap
and is allowed to grow, because nothing reads it on a schedule and nothing counts it.

## What does NOT go here

Work in flight. If you are doing it, it belongs in `Plans.md` as a table row with a
real status marker.

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

## Format

Plain bullets with a capture date. Not table rows — a second layer of safety, since the
canonical counter only ever looks at table rows.

```
- 2026-08-11 — Idea, one line, with enough context to be understandable in six months.
```

## When the active file is full

`harness-plan` routes new items here automatically once `Plans.md` passes the soft cap
of 25 active rows, and refuses to add to `Plans.md` at all past the hard cap of 30.
Both numbers live in `harness.toml [plans]`. Overflow lands in a recoverable place
instead of quietly making the active file unreadable.

---

## Captured

<!-- Append below. Newest last. -->

(nothing yet)
