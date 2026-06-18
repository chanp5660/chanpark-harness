# sync subcommand — Progress Sync Flow

Reconcile implementation status with Plans.md, detect and update discrepancies.

## Step 0: Plans.md Validation

Verify that Plans.md exists and has a valid format. If there is a problem, provide guidance immediately and stop.

| State | Guidance |
|-------|----------|
| Plans.md does not exist | `Plans.md not found. Create one with /harness-plan create.` → **stop** |
| Header is missing DoD / Depends columns (v1 format) | `Plans.md is in the old format (3 columns). Regenerate it as v2 (5 columns) with /harness-plan create. Existing tasks will be carried over automatically.` → **stop** |
| v2 format (5 columns) | Proceed to Step 1 as-is |

## Step 1: Collect Current State (parallel)

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

## Step 1.5: Agent Trace Analysis

Retrieve recent edit history from the Agent Trace and reconcile with Plans.md tasks:

```bash
# List of recently edited files
RECENT_FILES=$(tail -20 .claude/state/agent-trace.jsonl 2>/dev/null | \
  jq -r '.files[].path' | sort -u)

# Project info
PROJECT=$(tail -1 .claude/state/agent-trace.jsonl 2>/dev/null | \
  jq -r '.metadata.project')
```

**Reconciliation points**:

| Check item | Detection method |
|------------|-----------------|
| File edits not in Plans.md | Agent Trace vs. task descriptions |
| Files different from task descriptions | Expected files vs. actual edits |
| Tasks with no long-running edits | Agent Trace timeline vs. WIP duration |

## Step 2: Discrepancy Detection

| Check item | Detection method |
|------------|-----------------|
| Already complete but marked `cc:WIP` | Commit history vs. marker |
| Already started but marked `cc:TODO` | Changed files vs. marker |
| Marked `cc:done` but not committed | git status vs. marker |

### Artifact Hash Backward Compatibility

Both `cc:done [a1b2c3d]` format (with commit hash) and `cc:done` (without hash) are recognized.

**Matching rules**:
- `cc:done` → treated as complete without hash
- `cc:done [xxxxxxx]` → treated as complete with hash. Retain the 7-character short hash
- When hash is present, can verify commit existence against `git log --oneline`

> **Backward compatibility**: The no-hash format remains valid. Existing Plans.md files are not broken.

## Step 3: Plans.md Update Proposal

If discrepancies are detected, propose and execute:

```
Plans.md update required

| Task | Current | Updated | Reason |
|------|---------|---------|--------|
| XX   | cc:WIP | cc:done | Already committed |
| YY   | cc:TODO | cc:WIP | File already edited |

Update? (yes / no)
```

## Step 4: Progress Summary Output

```markdown
## Progress Summary

**Project**: {{project_name}}

| Status | Count |
|--------|-------|
| Not started (cc:TODO) | {{count}} |
| In progress (cc:WIP) | {{count}} |
| Complete (cc:done) | {{count}} |
| PM reviewed (pm:approved) | {{count}} |

**Progress**: {{percent}}%

### Recently Edited Files (Agent Trace)
- {{file1}}
- {{file2}}
```

## Step 5: Next Action Proposal

```
Next steps

**Priority 1**: {{task}}
- Reason: {{requested / waiting to unblock}}

**Recommended**: harness-work, harness-review
```

## Anomaly Detection

| Situation | Warning |
|-----------|---------|
| Multiple `cc:WIP` | Multiple tasks are progressing simultaneously |
| `pm:requested` unprocessed | Handle the PM request first |
| Large discrepancy | Task tracking is not keeping up |
| WIP with no updates for 3+ days | Check whether it is blocked |

## Step 6: Retrospective (default ON)

When running `sync`, if one or more `cc:done` tasks exist, automatically run a retrospective.
Can be explicitly skipped with `--no-retro`.

### Step R1: Collect Completed Tasks

```bash
# Extract cc:done / pm:approved tasks from Plans.md
grep -E 'cc:done|pm:approved' Plans.md

# Recent completion commit history
git log --oneline --since="7 days ago"

# Change volume
git diff --stat HEAD~10
```

### Step R2: Retrospective 4 items

| Item | Analysis method |
|------|----------------|
| **Estimation accuracy** | Infer expected file count from Plans.md task descriptions → compare with actual changed file count from `git diff --stat` |
| **Blocker causes** | Aggregate reason patterns for tasks with `blocked` markers (technical / external dependency / unclear spec) |
| **Quality marker hit rate** | For tasks tagged `[feature:security]` etc., check whether related issues actually occurred |
| **Scope changes** | Task count at first commit of Plans.md vs. current count (added/removed) |

### Step R3: Retrospective Summary Output

```markdown
## Retrospective Summary

**Period**: {{start_date}} — {{end_date}}

| Metric | Value |
|--------|-------|
| Completed tasks | {{count}} |
| Blockers occurred | {{blocked_count}} |
| Scope changes | +{{added}} / -{{removed}} |
| Estimation accuracy | Expected {{est}} files → Actual {{actual}} files |

### Learnings
- {{1-2 lines of learnings}}

### Actions for next time
- {{1-2 lines of improvement actions}}
```

### Step R4: Record to harness-mem

Record the retrospective results to harness-mem so they can be referenced during the next `create`.
Save location: the relevant agent memory under `.claude/agent-memory/`.
