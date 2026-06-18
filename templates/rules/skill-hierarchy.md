---
_harness_template: rules/skill-hierarchy.md
_harness_version: 2.6.1
---

# Skill Hierarchy Guidelines

## Overview

Skills in chanpark-harness follow a two-layer structure: **parent skills (categories)** and **child skills (specific capabilities)**.

```
skills/
├── impl/                      # Parent skill (SKILL.md)
│   ├── SKILL.md              # Category overview and routing
│   └── work-impl-feature/    # Child skill
│       └── doc.md            # Concrete procedure
├── harness-review/
│   ├── SKILL.md
│   ├── code-review/
│   │   └── doc.md
│   └── security-review/
│       └── doc.md
...
```

## Required Rules

### 1. After reading the parent skill, also read the child skill

After invoking a parent skill via the Skill tool, **you must also Read the child skill (doc.md) that matches the user's intent**.

```
✅ Correct flow:
1. Invoke "impl" via the Skill tool → obtain SKILL.md content
2. Determine the user's intent (e.g., feature implementation)
3. Read work-impl-feature/doc.md via the Read tool
4. Follow the procedure in doc.md

❌ Incorrect:
1. Invoke "impl" via the Skill tool
2. Read only SKILL.md and start working (ignoring child skills)
```

### 2. How to choose a child skill

| User intent | Skill to invoke | Child skill to read |
|---------------|---------------|-----------------|
| "Implement a feature" | impl | work-impl-feature/doc.md |
| "Review my code" | harness-review | code-review/doc.md |
| "Security check" | harness-review | security-review/doc.md |
| "Build it" | verify | build-verify/doc.md |

### 3. When multiple child skills apply

Ask the user to clarify, or select the single most relevant one to begin with.

---

## Why This Matters

- The parent SKILL.md contains only "overview and routing."
- The child doc.md contains "concrete procedures, checklists, and pattern collections."
- Skipping the child skill results in incomplete work.

---

## Integration with PostToolUse Hook

A reminder is automatically displayed after you use the Skill tool.
From the displayed list of child skills, Read the one that applies.
