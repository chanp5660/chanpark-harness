# Command Reference

Details of the commands used in the PM ↔ Claude Code workflow.

---

## Claude Code Commands

### /setup

Initial project setup (formerly `/harness-init`).

```
/setup
```

**Generated files**:
- Plans.md - Task management
- AGENTS.md - Role division definition
- CLAUDE.md - Claude Code settings
- .claude/rules/ - Project rules

---

### /plan-with-agent

Plan and break down tasks.

```
/plan-with-agent [task description]
```

**Example**:
```
/plan-with-agent I want to implement user authentication
```

**Output**: Tasks are added to Plans.md

---

### /work

Execute tasks in Plans.md.

```
/work
```

**Features**:
- Auto-detects tasks with `cc:TODO` or `pm:requested`
- Supports parallel execution of multiple tasks
- Automatically updates to `cc:done` upon completion

---

### /sync-status

Output a summary of the current status.

```
/sync-status
```

**Example output**:
```
📊 Current Status
- In progress: 2
- Not started: 5
- Complete (awaiting review): 1
```

---

### /handoff-to-pm

Completion report to PM.

```
/handoff-to-pm
```

**Information included**:
- List of completed tasks
- Modified files
- Test results
- Suggested next actions

---

## PM Commands (reference)

### /handoff-to-claude

Request tasks from Claude Code. Lead spawns a Worker agent to carry out the assigned work.

### /review-cc-work

Review Claude Code's completion report.
If unable to approve (request_changes), update Plans.md and **generate the revision request message with `/claude-code-harness/handoff-to-claude` and pass it directly**.

---

## Skills (auto-activated in conversation)

### handoff-to-pm

**Trigger**: "report completion to PM", "report work complete"

Generates a completion report from Worker → PM.

### handoff-to-impl

**Trigger**: "hand off to the implementer", "request from Claude Code"

Formats a task request from PM → Worker.

---

## Command Usage Flow

```
[Session start]
    │
    ▼
/sync-status  ←── Check current status
    │
    ▼
/work  ←── Execute tasks
    │
    ▼
/handoff-to-pm  ←── Completion report
    │
    ▼
[Session end]
```
