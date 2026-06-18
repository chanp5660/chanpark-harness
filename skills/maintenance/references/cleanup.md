# Cleanup Reference

Detailed execution steps, thresholds, and archive destinations for each `/maintenance` subcommand.

## Common: Environment Variables (shared SSOT with auto-cleanup-hook)

| Variable | Default | Source |
|----------|---------|--------|
| `PLANS_MAX_LINES` | 200 | `scripts/auto-cleanup-hook.sh` |
| `SESSION_LOG_MAX_LINES` | 500 | same |
| `CLAUDE_MD_MAX_LINES` | 100 | same |
| `ARCHIVE_AFTER_DAYS` | 7 | Age threshold for completed tasks in Plans.md |
| `LOGS_RETAIN_DAYS` | 30 | Retention period for files in `.claude/logs/` |

If the user specifies a different threshold in free-form text, that value takes priority.

---

## plans — Plans.md Archiving

### Prerequisites

1. If the `.claude/state/.ssot-synced-this-session` flag does not exist → prompt `/memory sync`.
2. Lines tagged `cc:WIP`, `pm:pending`, `cursor:pending` **must never be moved**.

### Steps

```bash
PLANS="Plans.md"
cp "$PLANS" "$PLANS.bak.$(date +%s)"

# 1. Measure current state
wc -l "$PLANS"
grep -c '\[x\].*pm:confirmed\|cursor:confirmed' "$PLANS" || true

# 2. Extract lines completed 7+ days ago (handle individually with Edit tool)
#    Target: `- [x] ... (YYYY-MM-DD) ... pm:confirmed|cursor:confirmed`
#    Exclude: lines containing cc:WIP / pm:pending / cursor:pending

# 3. Append extracted lines to the "## 📦 Archive" section
#    If the archive section does not exist, create it at the end of the file
```

### Archive Section Format

```markdown
## 📦 Archive

### YYYY-MM (grouped by month)

- [x] Old task A (2026-04-05) pm:confirmed
- [x] Old task B (2026-04-07) cursor:confirmed
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
| "raise the threshold to 300 lines" | Temporarily override env vars such as `PLANS_MAX_LINES=300` |

---

## Prohibited Actions

- ❌ Auto-editing `.claude/memory/decisions.md` / `patterns.md` (direct SSOT modification is forbidden)
- ❌ Compressing or archiving `CHANGELOG.md` (history must not be deleted)
- ❌ Any operations under `.git/`
- ❌ Deleting lines without a backup (files over 200 lines must always be backed up first)
