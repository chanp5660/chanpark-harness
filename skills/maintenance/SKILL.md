---
name: maintenance
description: "File cleanup and archiving. Tidies up bloated Plans.md, session-log.md, old logs, and state files. Trigger: /maintenance, cleanup, archive, organize, split session-log. Do NOT load for: implementation, review, release, new feature development."
allowed-tools: ["Read", "Write", "Edit", "Grep", "Glob", "Bash"]
argument-hint: "[plans|session-log|logs|state|all] [--dry-run]"
user-invocable: true
effort: low
---

# Maintenance

A single-purpose skill for tidying up cluttered files. Invoke when the auto-cleanup-hook emits a warning or as routine housekeeping.

> **Prerequisite**: Before any destructive operation (archive moves, line deletions), verify that important information from Plans.md / session-log.md has been promoted to the SSOT (decisions.md / patterns.md). If not yet synced, run `/memory sync` first.

## Quick Reference

| Subcommand | Target | Typical trigger |
|------------|--------|----------------|
| `maintenance plans` | Archive completed tasks from Plans.md | "clean up Plans.md", "move old tasks" |
| `maintenance session-log` | Split session-log.md by month | "split session-log", "log is too long" |
| `maintenance logs` | Delete old files in `.claude/logs/` | "clean up logs", "delete logs older than 30 days" |
| `maintenance state` | Trim `agent-trace.jsonl` / `harness-usage.json` | "trace bloat", "compress state" |
| `maintenance all` | Run all four subcommands in sequence | "clean everything", "full cleanup" |

Adding `--dry-run` lists what would be done without executing anything. Free-form instructions (e.g. "also delete old archives", "keep only this session-log") are parsed in Step 1 and applied as processing parameters from Step 2 onward.

## Execution Steps

1. **Parse user instructions**: Extract the subcommand plus any free-form details (exclusions, destination, day thresholds).
2. **SSOT sync check**: If `.claude/state/.ssot-synced-this-session` is absent, prompt `/memory sync` (required only when touching Plans.md).
3. **Open the reference file**: Read `${CLAUDE_SKILL_DIR}/references/cleanup.md` and execute the relevant section.
4. **Report Before/After**: Display line counts and deletion counts, then finish.

## Subcommand Details

See [cleanup.md](./references/cleanup.md) for per-target execution steps, thresholds, and archive destinations.

## Integration with auto-cleanup-hook

The PostToolUse hook (`scripts/auto-cleanup-hook.sh` / Go version `auto_cleanup_hook.go`) detects line-count overflows in Plans.md, session-log.md, and CLAUDE.md and returns feedback recommending archiving via `/maintenance`. When you see that warning, run the relevant subcommand.

## Notes

- **Do not move in-progress tasks**: `cc:WIP`, `pm:pending` are excluded from archiving.
- **Archive destination is fixed**: `.claude/memory/archive/` — confirm with the user before moving files elsewhere.
- **Backup**: Before editing any file over 200 lines, take a local backup with `cp <file> <file>.bak.$(date +%s)`.
- **CLAUDE.md: warnings only**: Do not auto-edit it. Only suggest a split.

## Related Skills

- `memory` — SSOT promotion (updates decisions.md / patterns.md) before cleaning Plans.md
- `harness-setup` — periodic maintenance right after setup can also be triggered via `harness-setup`
- `session-init` — controls maintenance recommendation notifications at session start
