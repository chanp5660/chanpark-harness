# Plans-backlog.md — fixture: capture-date staleness and the declined disposition

Pins `scripts/plans-sweep.sh` T3 and the "declined bullets are inert" rule.

Contains, deliberately:

- one ancient LIVE bullet, which must be reported as stale;
- one recent LIVE bullet, which must not;
- one DECLINED bullet older than every threshold, which must be skipped — a retired idea
  is resolved, not stale, and reporting it forever would make declining useless;
- one undated bullet, which is live but can never age;
- a fenced example, which is not a bullet at all.

```
- 2011-01-01 — fenced example. Never counted, never reported.
```

## Captured

- 2012-06-15 — Ancient live capture that nobody ever pitched or declined
- 2099-01-01 — Capture dated in the future; live, and never stale
- ~~2010-02-02 — Retired idea from long ago~~ declined 2026-08-11: superseded by the sweep
- Undated bullet, live but ageless because it carries no capture date
