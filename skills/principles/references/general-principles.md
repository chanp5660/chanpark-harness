---
name: core-general-principles
description: "Provides fundamental development principles and safety rules. Basic guidelines that apply to all tasks."
---

# General Principles

These are the fundamental principles for working with claude-code-harness. They apply to all workflows.

---

## Safety Principles

### 1. Verify Before Changing

Before editing any file, always confirm:

- **Read the contents with the Read tool**: Understand the existing code before making changes
- **Understand the scope of impact**: Consider the effect a change may have on other files
- **Consider backups**: Check `git status` before making significant changes

### 2. Edit with Minimal Diff

```
❌ Bad: Rewrite the entire file
✅ Good: Use the Edit tool to change only the necessary parts
```

### 3. Respect Configuration Files

Follow the settings in `claude-code-harness.config.json`:

- `safety.mode`: dry-run / apply-local / apply-and-push
- `paths.protected`: Do not modify protected paths
- `paths.allowed_modify`: Only modify paths that are explicitly allowed

---

## Work Principles

### 1. Always Update Plans.md

- When starting a task: `cc:TODO` → `cc:WIP`
- When completing a task: `cc:WIP` → `cc:Done`
- When blocked: Add `blocked` and record the reason

### 2. Proceed Incrementally

```
1. Investigate & Understand → 2. Plan → 3. Implement → 4. Verify → 5. Report
```

### 3. Handling Errors

- Up to 3 automatic retries
- If unresolved, escalate (report)
- Clearly document the error and the remediation steps attempted

---

## Communication Principles

### VibeCoder Support

To ensure non-technical users can understand:

- **Avoid jargon**: Or accompany it with a plain-language explanation
- **Present the next action**: e.g., "Next, say ___"
- **Visualize progress**: Make clear what has been completed and what remains

### Coordination with PM (Cursor)

- **Share state via Plans.md**: Maintain it as the single source of truth
- **Completion reports go through `/handoff-to-cursor`**: Follow the prescribed format
- **Stay in scope**: Confirm before doing any work outside the requested scope

---

## Prohibited Actions

1. **Direct deployment to production** (staging only)
2. **Hardcoding sensitive information** (use `.env`)
3. **Modifying protected paths** (`.github/`, `secrets/`, etc.)
4. **Destructive operations without user confirmation** (`rm -rf`, etc.)
