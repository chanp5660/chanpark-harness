---
name: init-memory-ssot
description: "Initialize the project's SSOT memory (decisions/patterns) and optional session-log. Use during initial setup or for projects where .claude/memory has not yet been configured."
allowed-tools: ["Read", "Write"]
---

# Init Memory SSOT

Initializes the **SSOT** files under `.claude/memory/`.

- `decisions.md` (SSOT for important decisions)
- `patterns.md` (SSOT for reusable solutions)
- `session-log.md` (session log; recommended for local use only)

Detailed policy: `docs/MEMORY_POLICY.md`

---

## Execution Steps

### Step 1: Check for Existing Files

- `.claude/memory/decisions.md`
- `.claude/memory/patterns.md`
- `.claude/memory/session-log.md`

Do **not** overwrite files that already exist.

### Step 2: Initialize from Templates (Only if Missing)

Templates:

- `templates/memory/decisions.md.template`
- `templates/memory/patterns.md.template`
- `templates/memory/session-log.md.template`

Replace `{{DATE}}` with today's date (e.g., `2025-12-13`).

### Step 3: Report Completion

- List of files created
- Git policy (`decisions/patterns` recommended for shared tracking; `session-log/.claude/state` recommended for local-only)
