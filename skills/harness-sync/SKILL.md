---
name: harness-sync
description: "HAR: Sync Plans.md with implementation. Drift detect, marker update, retrospective. Trigger: sync-status, where am I, check progress. --snapshot for snapshots. Do NOT load for: planning, implementation, review, release."
kind: workflow
purpose: "Reconcile Plans.md, git, and implementation state"
trigger: "sync-status, where am I, check progress"
shape: workflow
role: synchronizer
pair: harness-plan
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Edit", "Bash", "Grep", "Glob"]
argument-hint: "[--snapshot|--no-retro]"
user-invocable: true
effort: medium
---

# Harness Sync

Reconciles Plans.md with implementation state, detects drift, and updates markers.
Standalone replacement for the former `sync-status` and `harness-plan sync` subcommands.

## Quick Reference

| User Input | Behavior |
|------------|----------|
| `harness-sync` | Progress sync + retrospective (default ON) |
| `harness-sync --no-retro` | Progress sync only (skip retrospective) |
| `harness-sync --snapshot` | Save snapshot (point-in-time progress record) |
| `harness-sync --plan roadmap` | Sync the named plan `roadmap` |
| "where am I?" / "check progress" | Same as above |

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `--snapshot` | Save current progress as a snapshot | false |
| `--no-retro` | Skip the retrospective | false (runs by default) |
| `--plan NAME` | Use a named plan from `plans/manifest.json` | active/default |

## Step 0: Validate Plans.md

Verify that Plans.md exists and is correctly formatted. If there are issues, report them and stop.
In repos with multiple Plans.md files, confirm the target plan via `scripts/plan-registry.sh list` or `--plan NAME` before reading.

| State | Guidance |
|-------|----------|
| Plans.md does not exist | `Plans.md not found. Create one with harness-plan create.` → **stop** |
| Header missing DoD / Depends columns (v1 format) | `Plans.md is in the old format (3 columns). Regenerate as v2 (5 columns) with harness-plan create. Existing tasks will be carried over automatically.` → **stop** |
| v2 format (5 columns) | Proceed to Step 1 |

## Step 1: Gather Current State (parallel)

```bash
# Plans.md state
cat Plans.md

# Git change state
git status
git diff --stat HEAD~3

# Recent commit history
git log --oneline -10

# Agent trace (recently edited files)
tail -20 .claude/state/agent-trace.jsonl 2>/dev/null | jq -r '.files[].path' | sort -u
```

## Step 1.5: Analyze Agent Trace

Retrieve the recent edit history from the Agent Trace and cross-reference it with tasks in Plans.md:

```bash
# List of recently edited files
RECENT_FILES=$(tail -20 .claude/state/agent-trace.jsonl 2>/dev/null | \
  jq -r '.files[].path' | sort -u)

# Project info
PROJECT=$(tail -1 .claude/state/agent-trace.jsonl 2>/dev/null | \
  jq -r '.metadata.project')
```

**Cross-reference checks**:

| Check Item | Detection Method |
|------------|-----------------|
| Files edited that are not in Plans.md | Agent Trace vs task descriptions |
| Files that differ from what the task describes | Expected files vs actually edited files |
| Tasks with no edits for a long time | Agent Trace timeline vs WIP duration |

## Step 2: Detect Drift

| Check Item | Detection Method |
|------------|-----------------|
| Completed but still `cc:WIP` | Commit history vs marker |
| Started but still `cc:TODO` | Changed files vs marker |
| `cc:done` but not yet committed | git status vs marker |

## Step 3: Propose Plans.md Updates

If drift is detected, propose and apply updates:

```
Plans.md update needed

| Task | Current | After | Reason |
|------|---------|-------|--------|
| XX   | cc:WIP | cc:done | Already committed |
| YY   | cc:TODO | cc:WIP | File already edited |

Apply updates? (yes / no)
```

## Step 4: Output Progress Summary

```markdown
## Progress Summary

**Project**: {{project_name}}

| Status | Count |
|--------|-------|
| Not started (cc:TODO) | {{count}} |
| In progress (cc:WIP) | {{count}} |
| Done (cc:done) | {{count}} |
| PM reviewed (pm:reviewed) | {{count}} |

**Progress**: {{percent}}%

### Recently Edited Files (Agent Trace)
- {{file1}}
- {{file2}}
```

## Step 4.5: Save Snapshot (when `--snapshot` is specified)

When `--snapshot` is provided, save the current progress state as a timestamped snapshot.

### Save Location

Save as JSON in the `.claude/state/snapshots/` directory:

```bash
SNAPSHOT_DIR="${PROJECT_ROOT}/.claude/state/snapshots"
mkdir -p "${SNAPSHOT_DIR}"
SNAPSHOT_FILE="${SNAPSHOT_DIR}/progress-$(date -u +%Y%m%dT%H%M%SZ).json"
```

### Snapshot Contents

```json
{
  "timestamp": "2026-03-08T10:30:00Z",
  "phase": "Phase 26",
  "progress": {
    "total": 16,
    "todo": 5,
    "wip": 3,
    "done": 6,
    "confirmed": 2
  },
  "progress_rate": 50,
  "recent_commits": ["abc1234 feat: ...", "def5678 fix: ..."],
  "recent_files": ["skills/harness-work/SKILL.md", "..."],
  "notes": ""
}
```

### Diff Comparison

If a previous snapshot exists, display the diff:

```markdown
## Snapshot Diff

| Metric | Previous ({{prev_time}}) | Current | Change |
|--------|--------------------------|---------|--------|
| Progress | {{prev}}% | {{current}}% | +{{diff}}%pt |
| Done tasks | {{prev_done}} | {{current_done}} | +{{diff_done}} |
| WIP tasks | {{prev_wip}} | {{current_wip}} | {{diff_wip}} |
```

> **Design intent**: snapshots are used manually when the user wants to record the current state at a point in time.
> This is a separate feature from the automatic progress feed during breezing (26.2.3).

## Step 5: Suggest Next Actions

```
Next steps

**Priority 1**: {{task}}
- Reason: {{pending request / waiting to unblock}}

**Recommended**: harness-work, harness-review
```

## Anomaly Detection

| Situation | Warning |
|-----------|---------|
| Multiple `cc:WIP` markers | Multiple tasks progressing simultaneously |
| `pm:pending` unhandled | Handle the PM request first |
| Large discrepancy | Task tracking is falling behind |
| WIP not updated for 3+ days | Check if blocked |

## Step 6: Retrospective (default ON)

If there is at least one `cc:done` task, the retrospective runs automatically.
Can be explicitly skipped with `--no-retro`.

### Step R1: Collect Completed Tasks

```bash
# Extract cc:done / pm:reviewed tasks from Plans.md
grep -E 'cc:done|pm:reviewed' Plans.md

# Recent completion commit history
git log --oneline --since="7 days ago"

# Change scale
git diff --stat HEAD~10
```

### Step R2: Retrospective — 4 Items

| Item | Analysis Method |
|------|----------------|
| **Estimation accuracy** | Infer expected file count from Plans.md task descriptions → compare with actual changed file count from `git diff --stat` |
| **Blocker causes** | Aggregate reason patterns from tasks marked `blocked` (technical / external dependency / unclear spec) |
| **Quality marker hit rate** | Check whether tasks tagged with markers like `[feature:security]` actually produced related issues |
| **Scope change** | Task count at Plans.md initial commit vs current task count (added/removed) |

### Step R3: Output Retrospective Summary

```markdown
## Retrospective Summary

**Period**: {{start_date}} – {{end_date}}

| Metric | Value |
|--------|-------|
| Completed tasks | {{count}} |
| Blockers encountered | {{blocked_count}} |
| Scope change | +{{added}} / -{{removed}} |
| Estimation accuracy | Estimated {{est}} files → actual {{actual}} files |

### Learnings
- {{1-2 lines of learnings}}

### Actions for Next Time
- {{1-2 lines of improvement actions}}
```

### Step R4: Record in harness-mem

Record retrospective results in harness-mem so they can be referenced during the next `create`.
Save location: the relevant agent memory under `.claude/agent-memory/`.

## Related Skills

- `harness-plan` — Plan creation and task management
- `harness-work` — Task implementation
- `harness-review` — Code review
