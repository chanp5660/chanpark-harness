---
name: vibecoder-guide
description: "A guide skill that enables VibeCoder (non-technical users) to drive development using natural language. Use when providing guidance for non-technical users."
allowed-tools: ["Read"]
---

# VibeCoder Guide

A skill that guides VibeCoder (non-technical users) to drive development using natural language alone.
Automatically responds to questions like "what should I do?" or "what's next?".

---

## Trigger Phrases

This skill auto-activates on the following phrases:

- "what should I do?", "how should I proceed?"
- "what's next?", "what do I do next?"
- "what can I do?", "what should I work on?"
- "I'm stuck", "I don't understand", "help"
- "show me how to use this"
- "what should I do?", "what's next?", "help"

---

## Overview

VibeCoder lets you discover the next action just by asking naturally,
without knowing any technical commands or workflows.

---

## Response Patterns

### Pattern 1: No project exists yet

> **Let's start a project first!**
>
> **Example phrases:**
> - "I want to create a blog"
> - "I want to build a task management app"
> - "I want to make a portfolio site"
>
> A rough idea is fine. Tell me what you want to build.

### Pattern 2: Plans.md exists but no tasks are in progress

> **You have a plan. Let's start working!**
>
> **Current plan:**
> - Phase 1: Foundation setup
> - Phase 2: Core features
> - ...
>
> **Example phrases:**
> - "Start Phase 1"
> - "Do the first task"
> - "Do everything"

### Pattern 3: A task is in progress

> **Work is in progress**
>
> **Current task:** {{task name}}
> **Progress:** {{completed}}/{{total}}
>
> **Example phrases:**
> - "Continue"
> - "Next task"
> - "How far have we gotten?"

### Pattern 4: After a phase completes

> **Phase complete!**
>
> **What you can do next:**
> - "Verify it works" → Start the development server
> - "Review it" → Check code quality
> - "Move to the next phase" → Begin the next batch of work
> - "Commit" → Save the changes

### Pattern 5: An error occurred

> **A problem occurred**
>
> **Situation:** {{error summary}}
>
> **Example phrases:**
> - "Fix it" → Attempt automatic repair
> - "Explain it" → Explain the problem in detail
> - "Skip it" → Move on to the next task

---

## Common Phrase Reference Table

| What you want to do | How to say it |
|---------------------|---------------|
| Start a project | "I want to build ___" |
| View the plan | "Show me the plan" / "What's the current status?" |
| Start working | "Start" / "Build it" / "Do Phase 1" |
| Continue work | "Continue" / "Next" |
| Verify it works | "Run it" / "Show me" |
| Check the code | "Review it" / "Check it" |
| Save changes | "Commit" / "Save" |
| When stuck | "What should I do?" / "Help" |
| Hand off everything | "Do everything" / "Take it from here" |

---

## Context Assessment

This skill checks the following to select the appropriate response:

1. **Presence of AGENTS.md** → Whether the project has been initialized
2. **Contents of Plans.md** → Whether a plan exists and current progress
3. **Current task state** → Presence of `cc:WIP` markers
4. **Recent errors** → Whether a problem has occurred

---

## Implementation Notes

When this skill is invoked:

1. Analyze the current state
2. Select the appropriate pattern
3. Present concrete "example phrases"
4. Wait for the user's next action

**Important**: Avoid technical jargon and explain things in plain, accessible language.
