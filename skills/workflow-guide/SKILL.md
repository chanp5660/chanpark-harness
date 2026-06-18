---
name: workflow-guide
description: "Explicit helper for PM ↔ Claude Code workflow guidance. Do NOT load for: solo implementation, workflow setup, handoff execution, or general process coaching."
allowed-tools: ["Read"]
user-invocable: false
disable-model-invocation: true
---

# Workflow Guide Skill

A skill that provides guidance for the PM ↔ Claude Code workflow.

---

## Trigger Phrases

This skill is activated by the following phrases:

- "tell me about the workflow"
- "explain the work process"
- "how should I proceed?"
- "how does the workflow work?"
- "explain 2-agent workflow"

---

## Overview

This skill explains the role division and collaboration method between the PM and Claude Code (Worker).

---

## Two-Agent Workflow

### Role Division

| Agent | Role | Responsibilities |
|-------|------|-----------------|
| **PM** | Project Manager | Task assignment, review, production deploy decisions |
| **Claude Code** | Worker | Implementation, testing, CI fixes, staging deploy |

### Workflow Diagram

```
┌─────────────────────────────────────────────────────────┐
│                      PM                                 │
│  · Add tasks to Plans.md                                │
│  · Request work from Claude Code (/handoff-to-claude)   │
│  · Review completion reports                            │
│  · Make production deploy decisions                     │
└─────────────────────┬───────────────────────────────────┘
                      │ Task request
                      ▼
┌─────────────────────────────────────────────────────────┐
│                  Claude Code (Worker)                   │
│  · Execute tasks with /work (parallel execution ready)  │
│  · Implement → Test → Commit                            │
│  · Auto-fix on CI failure (up to 3 times)               │
│  · Report completion with /handoff-to-pm                │
└─────────────────────┬───────────────────────────────────┘
                      │ Completion report
                      ▼
┌─────────────────────────────────────────────────────────┐
│                      PM                                 │
│  · Review changes                                       │
│  · Verify staging behavior                              │
│  · Execute production deploy (after approval)           │
└─────────────────────────────────────────────────────────┘
```

---

## Task Management via Plans.md

### Marker Reference

| Marker | Meaning | Set by |
|--------|---------|--------|
| `pm:requested` | Requested by PM | PM |
| `cc:TODO` | Not yet started by Claude Code | Either |
| `cc:WIP` | Claude Code in progress | Claude Code |
| `cc:done` | Claude Code complete | Claude Code |
| `pm:approved` | PM review complete | PM |
| `blocked` | Blocked | Either |

### Task State Transitions

```
pm:requested → cc:WIP → cc:done → pm:approved
```

---

## Main Commands

### Claude Code Side

| Command | Purpose |
|---------|---------|
| `/harness-init` | Project setup |
| `/plan-with-agent` | Planning and task breakdown |
| `/work` | Execute tasks (parallel execution ready) |
| `/handoff-to-pm` | Completion report (to PM) |
| `/sync-status` | Status check |

### Skills (auto-activated in conversation)

| Skill | Trigger example |
|-------|----------------|
| `handoff-to-pm` | "report completion to PM" |
| `handoff-to-impl` | "hand off to the implementer" |

### PM Side (reference)

| Command | Purpose |
|---------|---------|
| `/handoff-to-claude` | Request tasks from Claude Code |
| `/review-cc-work` | Review completion report |

---

## CI/CD Rules

### Claude Code's Scope of Responsibility

- ✅ Up to staging deploy
- ✅ Auto-fix on CI failure (up to 3 times)
- ❌ Production deploy is prohibited

### The 3-Attempt Rule

If CI fails 3 consecutive times:
1. Stop auto-fixing
2. Generate an escalation report
3. Defer the decision to PM

---

## Frequently Asked Questions

### Q: What if a task is unclear?

A: Ask the PM for clarification, or use `/sync-status` to organize the current state.

### Q: What if CI keeps failing?

A: Do not auto-fix more than 3 times — escalate to PM instead.

---

## Related Documents

- AGENTS.md - Detailed role division
- CLAUDE.md - Claude Code-specific settings
- Plans.md - Task management file
