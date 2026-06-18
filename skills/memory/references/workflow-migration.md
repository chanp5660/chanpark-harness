---
name: migrate-workflow-files
description: "Migrate existing AGENTS.md/CLAUDE.md/Plans.md to the new format — inspects existing content, confirms carry-over items interactively, creates backups, and merges Plans preserving all tasks."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
---

# Migrate Workflow Files (Interactive Merge)

## Purpose

Updates the following files currently in use in an existing project to the **new format while respecting existing content**:

- `AGENTS.md`
- `CLAUDE.md`
- `Plans.md`

Key points:

- **Confirm carry-over information interactively** (nothing is silently discarded or overwritten)
- Always create a **backup** before making changes
- `Plans.md` follows the `merge-plans` policy to **update structure while preserving tasks**

---

## Prerequisites (Important)

This skill proceeds in the order: **user agreement → backup → generation → diff review**
to balance safety on first application with the intended behavior (new format).

---

## Inputs (Auto-detected within this skill)

- `project_name`: estimated via `basename $(pwd)`
- `date`: `YYYY-MM-DD`
- Existence of existing files:
  - `AGENTS.md`
  - `CLAUDE.md`
  - `Plans.md`
- Reference templates for the new format:
  - `templates/AGENTS.md.template`
  - `templates/CLAUDE.md.template`
  - `templates/Plans.md.template`

---

## Execution Flow

### Step 0: Detection and Agreement (Required)

1. Use `Read` to check for `AGENTS.md`, `CLAUDE.md`, and `Plans.md`.
2. If any exist, confirm with the user:
   - **Is it OK to migrate (update to new format)?**
   - Important: migration **includes content reorganization** (= some restructuring or rewording may occur)

If the user says NO:

- Abort this skill (change nothing)
- Instead, propose safe operations such as "merge only `.claude/settings.json`"

### Step 1: Review Existing Content (Summary)

`Read` each file and extract the following for a brief summary to present:

- **AGENTS.md**: Role assignments, handoff procedures, restrictions, environment/prerequisites
- **CLAUDE.md**: Key constraints (restrictions/permissions/branch policy), test procedures, commit conventions, operational rules
- **Plans.md**: Task structure, marker usage, current WIP/requested tasks

### Step 2: Confirm Carry-over Items (Interactive)

Based on the summary, ask the user about items to **retain/adjust** (5–10 questions is sufficient):

- Constraints that must be kept (e.g., no production deploy, restricted directories, security requirements)
- Role assignment assumptions (Solo/2-agent)
- Branch policy (main/staging, etc.)
- Representative test/build commands
- Plans marker usage (align with existing rules if any)

### Step 3: Create Backups (Required)

Store backups under `.claude-code-harness/backups/` in the project (often excluded from git).

Example:

- `.claude-code-harness/backups/2025-12-13/AGENTS.md`
- `.claude-code-harness/backups/2025-12-13/CLAUDE.md`
- `.claude-code-harness/backups/2025-12-13/Plans.md`

Use `Bash` with `mkdir -p` and `cp`.

### Step 4: Generate New Format (Merge)

#### 4-1. Plans.md (Task-preserving Merge)

Execute following the `merge-plans` policy:

- Preserve existing 🔴🟡🟢📦 tasks
- Update the marker legend and last-updated info from the template side
- If parsing fails, keep the backup and adopt the template

#### 4-2. AGENTS.md / CLAUDE.md (Template + Carry-over Block)

Build the skeleton from the template, then **relocate items confirmed in Step 2 to the appropriate places in the new format**.

Minimum policy:

- Do not remove existing "important rules"; keep them as a **"Project-specific Rules (Migrated)"** section
- Rewrite role assignments/flow to match the template format (preserve meaning)

### Step 5: Diff Review and Completion

- Briefly summarize changes via `git diff` (or file diff)
- Final check that key points (permissions/restrictions/task states) are as intended
- Fix immediately if any issues are found

---

## Deliverables (Completion Criteria)

- `AGENTS.md` / `CLAUDE.md` / `Plans.md` in the **new format** incorporating existing content
- Backups present in `.claude-code-harness/backups/`
- Plans tasks are intact (preserved)
