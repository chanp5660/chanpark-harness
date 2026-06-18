---
name: session-memory
description: "Internal sub-skill for cross-session handoff, durable learning, and memory persistence. Invoked by session/memory workflows only. Do NOT load for: implementation, review, ad-hoc notes, or SSOT editing."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
user-invocable: false
disable-model-invocation: true
---

# Session Memory Skill

A skill for managing learning and memory across sessions.
Records and retrieves past work, decisions, and learned patterns.

---

## Trigger Phrases

This skill is automatically invoked by the following phrases:

- "what did we do last time?", "continue from last session"
- "show me the history", "past work"
- "tell me about this project"
- "what did we do last time?", "continue from before"

---

## Overview

This skill saves work history to `.claude/memory/` to enable
knowledge continuity across sessions.

It also clarifies **where important information should be stored** (details: `docs/MEMORY_POLICY.md`).

---

## Memory Structure

```
.claude/
├── memory/
│   ├── session-log.md      # Per-session logs
│   ├── decisions.md        # Important decisions
│   ├── patterns.md         # Learned patterns
│   └── context.json        # Project context
└── state/
    └── agent-trace.jsonl   # Agent Trace (tool execution history)
```

### Recommended Usage (SSOT / Local Separation)

- **SSOT (recommended for sharing)**: `decisions.md` / `patterns.md`  
  - Aggregates "decisions (Why)" and "reusable solutions (How)"
  - Each entry should have a **title + tags** (e.g., `#decision #db`) with an **Index** at the top
- **Local only**: `session-log.md` / `context.json` / `.claude/state/`  
  - Prone to noise and bloat; generally not Git-tracked (decide individually if needed)

---

## Automatically Recorded Information

### session-log.md

Each session record is assigned a session ID obtained from the runtime environment.
In Claude Code, `${CLAUDE_SESSION_ID}` is preferred; in Codex, the session / thread ID provided by the Codex runtime takes precedence.
If neither is available, the `.session_id` from `.claude/state/session.json` is read, with a datetime-based ID generated as a last fallback.
This improves traceability across sessions.

```markdown
## Session: 2024-01-15 14:30 (session: abc123def)

### Tasks Executed
- [x] Implemented user authentication
- [x] Created login page

### Generated Files
- src/lib/auth.ts
- src/app/login/page.tsx

### Key Decisions
- Authentication method: adopted Supabase Auth

### Handoff to Next Session
- Logout functionality not yet implemented
- Password reset also needed
```

> **Note**: `${CLAUDE_SESSION_ID}` is an environment variable automatically set by Claude Code.
> Since this variable may not exist in Codex, do not assume it is always present — use the Codex runtime's session / thread ID or `.claude/state/session.json` instead.

### decisions.md

```markdown
## Technology Choices

| Date | Decision | Reason |
|------|---------|------|
| 2024-01-15 | Supabase Auth | Free tier available, easy setup |
| 2024-01-14 | Next.js App Router | Latest best practices |

## Architecture

- Components: `src/components/`
- Utilities: `src/lib/`
- Type definitions: `src/types/`
```

### patterns.md

```markdown
## Project Patterns

### Component Naming
- PascalCase
- Examples: `UserProfile.tsx`, `LoginForm.tsx`

### API Endpoints
- `/api/v1/` prefix
- RESTful design

### Error Handling
- Wrap with try-catch
- Error messages in English
```

### context.json

```json
{
  "project_name": "my-blog",
  "created_at": "2024-01-14",
  "stack": {
    "frontend": "next.js",
    "backend": "next-api",
    "database": "supabase",
    "styling": "tailwind"
  },
  "current_phase": "Phase 2: Core Features",
  "last_session": "2024-01-15T14:30:00Z"
}
```

---

## Processing Flow

### At Session Start

1. Load `.claude/memory/context.json`
2. Review the previous session log
3. **Retrieve recent edit history from Agent Trace**
4. Identify incomplete tasks
5. Generate a context summary

**Using Agent Trace**:
```bash
# Get list of files edited in the last session
tail -50 .claude/state/agent-trace.jsonl | jq -r '.files[].path' | sort -u

# Get project metadata
tail -1 .claude/state/agent-trace.jsonl | jq '.metadata'
```

### During Session

1. Record important decisions in `decisions.md`
2. Add new patterns to `patterns.md`
3. Log file creation in `session-log.md`

### At Session End

1. Generate session summary
2. Update `context.json`
3. Record handoff items for next session

---

## Memory Optimization (CC 2.1.49+)

Since Claude Code 2.1.49, memory usage at session resume has been reduced by **68%**.

### Recommended Workflow

```bash
# Use --resume for long sessions
claude --resume

# Split large tasks and resume sessions
claude --resume "continue from here"
```

| Scenario | Recommendation |
|---------|------|
| Long implementation sessions | Resume every 1–2 hours |
| Large-scale refactoring | Split into feature units per session |
| Out-of-memory warning | Immediately resume with `--resume` |

> Memory efficiency has improved significantly — actively take advantage of session resume.

### /recap — In-Session Status Check (CC 2.1.108+)

The `/recap` command (an alias for `/rewind`) added in CC 2.1.108 is used to quickly review
what has been done so far within the current session.
It is most effective when combined with checking in during long sessions or before switching back to another session with `--resume`.

**Recommended Timing**:

| Timing | Usage |
|---------|------|
| Just before resuming with `--resume` | Use `/recap` to consolidate context, then run `claude --resume` |
| Before a Breezing Worker resumes | Confirm in-session progress with `/recap` before moving to the next task |
| Midpoint of long sessions (1+ hour) | `/recap` to check status → manually append to `session-log.md` if needed |

```bash
# Typical usage flow
# 1. Check current work status
/recap

# 2. Optionally append to session-log.md, then resume the session
claude --resume
```

> `/recap` only reviews within the current session. For content from previous sessions, use `session-log.md` or context inheritance via `claude --resume`.

---

## Usage Examples

### Starting from Where We Left Off

```
User: "continue from last session"

Claude Code:
📋 Last Session (2024-01-15)

Completed tasks:
- User authentication
- Login page

Incomplete:
- Logout functionality
- Password reset

Say "implement logout" to continue.
```

### Checking Project Status

```
User: "tell me about this project"

Claude Code:
📁 Project: my-blog

Tech stack:
- Next.js + Tailwind CSS + Supabase

Current phase: Core feature development
Progress: 40% complete

Recent decisions:
- Adopted Supabase Auth
- Using App Router
```

---

## Relationship with Claude Code Auto-Memory (D22)

Claude Code 2.1.32+ includes an "auto-memory" feature that automatically saves cross-session learning to `~/.claude/projects/<project>/memory/MEMORY.md`.

The Harness memory system coexists with this as a **3-layer architecture**:

| Layer | System | Content | Management |
|----|---------|------|------|
| **Layer 1** | Claude Code Auto-Memory | General learning (avoiding mistakes, tool usage) | Implicit / automatic |
| **Layer 2** | Harness SSOT | Project-specific decisions and patterns | Explicit / manual |
| **Layer 3** | Agent Memory | Per-agent task learning | Agent-defined |

**When to use which**:
- If Layer 1 insights are important to the entire project → promote to Layer 2 with `/memory ssot`
- Leave everyday learning to Layer 1 (do not disable it)
- When using Agent Teams, be mindful of concurrent writes

Details: [D22: 3-Layer Memory Architecture](../../.claude/memory/decisions.md#d22-3-layer-memory-architecture)

---

## Notes

- **Auto-save**: It is recommended to use a `hooks/Stop` hook to automatically append a summary to `session-log.md` at session end (if not set up, manual operation is fine)
- **Privacy**: Do not record confidential information
- **Git policy**: `decisions.md` / `patterns.md` are recommended for sharing; `session-log.md` / `context.json` / `.claude/state/` are recommended as local-only (details: `docs/MEMORY_POLICY.md`)
- **Size management**: When logs grow large, it is recommended to ask "organize the session log"
