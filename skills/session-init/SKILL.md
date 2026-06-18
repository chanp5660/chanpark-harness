---
name: session-init
description: "Internal sub-skill for session startup checks, Plans.md status, git state, and harness-mem resume pack. Invoked by session/startup workflows only. Do NOT load for: implementation, reviews, or mid-session tasks."
allowed-tools: ["Read", "Write", "Bash", "mcp__harness__harness_mem_resume_pack", "mcp__harness__harness_mem_sessions_list", "mcp__harness__harness_mem_health"]
user-invocable: false
disable-model-invocation: true
---

# Session Init Skill

A skill that performs environment checks and current task status assessment at the start of a session.

---

## Invocation Conditions

This skill is invoked internally from `session` / SessionStart workflows.
The user-facing entry point is `/session` or the standard session startup flow.

Legacy trigger phrases:

- "start session"
- "begin work"
- "start today's work"
- "check current status"
- "what should I work on?"
- "start session"
- "what should I work on?"

---

## Overview

The Session Init skill automatically checks the following at the start of a Claude Code session:

1. **Git state**: current branch, uncommitted changes
2. **Plans.md**: in-progress tasks, requested tasks
3. **AGENTS.md**: role assignments, prohibited actions
4. **Previous session**: handoff notes review
5. **Latest snapshot**: progress snapshot summary and diff from last session

---

## Execution Steps

### Step 0: File State Check (Auto Cleanup)

Check file sizes before starting the session:

```bash
# Check Plans.md line count
if [ -f "Plans.md" ]; then
  lines=$(wc -l < Plans.md)
  if [ "$lines" -gt 200 ]; then
    echo "⚠️ Plans.md has ${lines} lines. Recommend running 'clean up' to reorganize."
  fi
fi

# Check session-log.md line count
if [ -f ".claude/memory/session-log.md" ]; then
  lines=$(wc -l < .claude/memory/session-log.md)
  if [ "$lines" -gt 500 ]; then
    echo "⚠️ session-log.md has ${lines} lines. Recommend running 'clean up session log' to reorganize."
  fi
fi
```

If cleanup is needed, display a suggestion (does not block work).

### Step 0.5: Legacy Local Memory Compatibility (Optional)

The current standard is the Unified Harness Memory in Step 0.7.
Legacy local memory compatibility checks are generally not needed; refer to them individually only when a specific migration verification is required.

> **Note**: In normal operation, skip this step and treat the shared DB Resume Pack as the sole resume source.

### Step 0.7: Unified Harness Memory Resume Pack (Required)

Retrieve the resume context from the shared harness DB (`~/.harness-mem/harness-mem.db`).

Required call:

```text
harness_mem_resume_pack(project, session_id?, limit=5, include_private=false)
```

Operational rules:
- `project` must always be set to the current project name
- `session_id` is resolved in this order: `$CLAUDE_SESSION_ID` → `.session_id` in `.claude/state/session.json`
- Using the first result of `harness_mem_sessions_list(project, limit=1)` is limited to read-only (resume confirmation); do not use it for writes via `record_checkpoint` / `finalize_session`
- Inject the retrieved result into the session startup context
- On retrieval failure, check daemon status with `harness_mem_health()`, explicitly report the failure, and continue
- Recovery order: `scripts/harness-memd doctor` → `scripts/harness-memd cleanup-stale` → `scripts/harness-memd start`

### Step 1: Environment Check

Run the following in parallel:

```bash
# Git state
git status -sb
git log --oneline -3
```

```bash
# Plans.md
cat Plans.md 2>/dev/null || echo "Plans.md not found"
```

```bash
# Key points from AGENTS.md
head -50 AGENTS.md 2>/dev/null || echo "AGENTS.md not found"
```

### Step 2: Assess Task Status

Extract the following from Plans.md:

- `cc:WIP` - tasks carried over from the previous session
- `pm:requested` - newly requested tasks from PM
- `cc:TODO` - tasks assigned but not yet started

### Step 3: Output Status Report

```markdown
## 🚀 Session Start

**Date/Time**: {{YYYY-MM-DD HH:MM}}
**Branch**: {{branch}}
**Session ID**: ${CLAUDE_SESSION_ID}

---

### 📋 Today's Tasks

**Priority Tasks**:
- {{tasks marked pm:requested or cc:WIP}}

**Other Tasks**:
- {{list of cc:TODO tasks}}

---

### ⚠️ Notes

{{Important constraints and prohibited actions from AGENTS.md}}

---

**Ready to begin work?**
```

---

## Output Format

At session start, concisely present the following information:

| Item | Content |
|------|---------|
| Current branch | e.g. `staging` |
| Priority tasks | Top 1-2 most important tasks |
| Notes | Summary of prohibited actions |
| Next action | Concrete suggestions |

---

## Related Commands

- `/work` - Execute tasks (parallel execution supported)
- `/sync-status` - Plans.md progress summary
- `/maintenance` - Automatic file cleanup

---

## Notes

- **Always check AGENTS.md**: Understand role assignments before starting work
- **If Plans.md is missing**: Direct the user to `/harness-init`
- **If previous work was interrupted**: Confirm whether to continue
