# Cleanup Reference

Detailed execution steps, thresholds, and archive destinations for each `/maintenance` subcommand.

## Common: Environment Variables (shared SSOT with the binary's auto-cleanup hook)

| Variable | Default | Source |
|----------|---------|--------|
| `SESSION_LOG_MAX_LINES` | 500 | binary `hook auto-cleanup` |
| `CLAUDE_MD_MAX_LINES` | 100 | same |
| `LOGS_RETAIN_DAYS` | 30 | Retention period for files in `.claude/logs/` |

If the user specifies a different threshold in free-form text, that value takes priority.

**Plans.md thresholds do not live here.** They live in `harness.toml [plans]` and are
read by `scripts/plans-sweep.sh`, `scripts/hook-handlers/session-monitor.sh` and
`scripts/hook-handlers/plans-watcher.sh`:

| Key | Default | Bounds |
|-----|---------|--------|
| `soft_cap` / `hard_cap` | 25 / 30 | active rows (`cc:todo` + `cc:wip` + `cc:blocked`) |
| `max_lines` | 80 | the whole active file, boilerplate included — **reported, never refused** |
| `wip_cap` | 1 | `cc:wip` rows |
| `archive_days` | 14 | per-row: age of a terminal row before it is an archive candidate |
| `backlog_stale_days` | 90 | age of a live `Plans-backlog.md` bullet before it is reported |

The old `PLANS_MAX_LINES=200` and `ARCHIVE_AFTER_DAYS=7` entries were removed: 200 lines
is two and a half times the budget the file is now held to, and the archive trigger is
`archive_days` per row, not a file-wide age.

---

## plans — Plans.md Archiving

### Prerequisites

1. If the `.claude/state/.ssot-synced-this-session` flag does not exist → prompt `/memory sync`.
2. Lines tagged `cc:wip`, `cc:todo`, `cc:blocked` or `pm:requested` **must never be moved** — only terminal rows (`cc:done`, `cc:dropped`) are archivable.
3. **Destination**: `.claude/memory/archive/Plans-<YYYY-MM-DD>.md`. Nothing scans that
   directory, which is the entire point — physical separation is much cheaper to enforce
   than teaching four separate counters to skip a section, and a single archive
   *sentence* once inflated the done count by one (v1.3.6).
4. **Archive from the sweep, not by hand.** `scripts/plans-sweep.sh` reports which
   **rows** qualify — any terminal row whose git-blame author-time is older than
   `archive_days` — and you move exactly those. Archiving must be a pure function of
   state and time. The moment it becomes a way to make an awkward file look tidy, the
   archive stops being a record and starts being a hiding place.

   The rule is **per row, not per file**. It used to require the whole file to be
   terminal, and that turned one never-finished `cc:todo` into a permanent block on
   archiving everything around it — measured at 120 done rows and 125 lines with the
   sweep still reporting "no candidates". Linear's own rule is per issue, and the row is
   the thing being archived, so the row is the thing the condition is on.

   Because the trigger is per row, running the sweep is always available: an over-budget
   file (`max_lines`) is never stuck. If the sweep genuinely offers no candidates and the
   file is still over budget, the rows are all young and the answer is to shorten the
   descriptions, not to move rows out early.
5. `Plans-backlog.md` is **never counted and never auto-cleaned**, but it is not
   lifecycle-free. It has four dispositions — promote, decline, duplicate, snooze — and
   `scripts/plans-sweep.sh` (T3) reports live bullets older than `backlog_stale_days` so
   they get one. Declining is written in the file as a struck-through bullet plus
   `declined <date>: <reason>`; declined bullets are inert everywhere and may be moved in
   bulk to `.claude/memory/archive/Plans-<YYYY-MM-DD>.md` alongside terminal rows.
   **Never delete a bullet to retire it** — deletion is the one disposition that leaves
   no record.

### Steps

```bash
PLANS="Plans.md"
cp "$PLANS" "$PLANS.bak.$(date +%s)"

# 1. Measure current state
wc -l "$PLANS"
grep -cE '\[x\].*(pm:approved|cc:done|cc:dropped)' "$PLANS" || true

# 2. Extract lines completed 7+ days ago (handle individually with Edit tool)
#    Target: `- [x] ... (YYYY-MM-DD) ... pm:approved` / `cc:done` / `cc:dropped`
#    Exclude: lines containing cc:wip / cc:todo / cc:blocked / pm:requested

# 3. Append extracted lines to the "## 📦 Archive" section
#    If the archive section does not exist, create it at the end of the file
```

### Archive Section Format

```markdown
## 📦 Archive

### YYYY-MM (grouped by month)

- [x] Old task A (2026-04-05) pm:approved
- [x] Old task B (2026-04-07) cc:dropped
```

### Output When Nothing Is Found

```
✅ Plans.md: 180 lines (limit 200). 6 completed tasks, 0 older than 7 days. No cleanup needed.
```

### Post-Execution Report Example

```
✅ Plans.md cleanup complete
- Line count: 250 → 178 (-72)
- Archived: 9 tasks (2026-03 group)
- Backup: Plans.md.bak.1712900000
```

---

## session-log — Monthly Split of session-log.md

Target: `.claude/memory/session-log.md`. A split is recommended when it exceeds 500 lines.

### Steps

```bash
LOG=".claude/memory/session-log.md"
ARCHIVE_DIR=".claude/memory/archive/sessions"
mkdir -p "$ARCHIVE_DIR"

# 1. Entries are assumed to be separated by `## YYYY-MM-DD` headers
# 2. Keep the most recent 30 days; split anything older into monthly files
#    Output: .claude/memory/archive/sessions/YYYY-MM.md (append)
# 3. Remove the moved entries from the original file
```

### Split File Format

Add the following header at the top of each `archive/sessions/YYYY-MM.md`:

```markdown
# Session Log — YYYY-MM

Moved from `.claude/memory/session-log.md` on entries from N days and earlier.
Move date: YYYY-MM-DD
```

### Post-Execution Report Example

```
✅ session-log.md split complete
- Line count: 620 → 180
- Split to: archive/sessions/2026-03.md (+230 lines), 2026-02.md (+210 lines)
```

---

## logs — Delete Old Files in `.claude/logs/`

### Steps

```bash
LOGS_DIR=".claude/logs"
[ -d "$LOGS_DIR" ] || exit 0

# List targets with dry-run
find "$LOGS_DIR" -type f -mtime +${LOGS_RETAIN_DAYS:-30} -print

# Execute deletion
find "$LOGS_DIR" -type f -mtime +${LOGS_RETAIN_DAYS:-30} -delete
```

### Report Example

```
✅ logs/ cleanup complete
- Deleted: 12 files (older than 30 days)
- Remaining: 34 files
```

---

## state — Trim agent-trace / harness-usage

`.claude/state/agent-trace.jsonl` and `.claude/state/harness-usage.json` are append-only / growing JSON files that can reach tens of megabytes if left unchecked.

### Trimming agent-trace.jsonl

```bash
TRACE=".claude/state/agent-trace.jsonl"
[ -f "$TRACE" ] || exit 0

# Keep only the last 1000 lines
tail -1000 "$TRACE" > "$TRACE.tmp" && mv "$TRACE.tmp" "$TRACE"
```

### Compacting harness-usage.json

```bash
USAGE=".claude/state/harness-usage.json"
[ -f "$USAGE" ] || exit 0

# Delete entries older than 60 days (write the jq condition after inspecting the actual structure with Read)
# Read the file first to confirm its structure before processing
```

### Report Example

```
✅ state trim complete
- agent-trace.jsonl: 8421 lines → 1000 lines
- harness-usage.json: entries before 2026-02 deleted
```

---

## all — Run Everything

Execute in order: plans → session-log → logs → state. Stop and report to the user if an error occurs at any step.

### Execution Flow

1. SSOT sync check (only when plans is included in the targets)
2. Run each subcommand in sequence
3. Display a Before/After summary at the end

### Report Example

```
✅ Full maintenance complete

| Target | Before | After | Change |
|--------|--------|-------|--------|
| Plans.md | 250 lines | 178 lines | -72 (9 archived) |
| session-log.md | 620 lines | 180 lines | -440 (2 files split) |
| logs/ | 46 files | 34 files | -12 (>30 days) |
| agent-trace.jsonl | 8421 lines | 1000 lines | -7421 |

Backup: Plans.md.bak.1712900000
```

---

## Handling Common Additional Instructions

| Instruction | Action |
|-------------|--------|
| "also delete old archives" | Additionally delete items in `.claude/memory/archive/` older than N days |
| "dry-run" | Replace all deletions/moves with `echo`; only list what would be removed |
| "keep this file" | Exclude the specified file from the target list before running |
| "raise the session-log threshold to 900 lines" | Temporarily override env vars such as `SESSION_LOG_MAX_LINES=900` |
| "raise the Plans.md line budget" | Edit `max_lines` in `harness.toml [plans]`, and say what it now costs to read the file. It is not an env var, because a budget you can raise per-invocation is not a budget |

---

## Prohibited Actions

- ❌ Auto-editing `.claude/memory/decisions.md` / `patterns.md` (direct SSOT modification is forbidden)
- ❌ Compressing or archiving `CHANGELOG.md` (history must not be deleted)
- ❌ Any operations under `.git/`
- ❌ Deleting lines without a backup (files over 200 lines must always be backed up first)
