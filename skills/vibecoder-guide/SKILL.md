---
name: vibecoder-guide
description: "Explicit helper for non-technical VibeCoder coaching: what to ask next, how to describe work, and how to stay safe. Do NOT load for: direct implementation, technical review, or PM workflow."
allowed-tools: ["Read"]
user-invocable: false
disable-model-invocation: true
---

# VibeCoder Guide Skill

A skill that guides VibeCoder (non-technical users) so they can drive development using only natural language.
Automatically responds to questions like "What should I do?" or "What's next?"

---

## Trigger Phrases

This skill auto-activates on the following phrases:

- "What should I do?" / "What do I do?"
- "What should I do next?" / "What's next?"
- "What can I do?" / "What should I be doing?"
- "I'm stuck" / "I don't understand" / "Help"
- "How do I use this?"
- "what should I do?", "what's next?", "help"

---

## Overview

VibeCoder lets you find out your next action simply by asking in natural language —
no knowledge of technical commands or workflows required.

---

## Response Patterns

### Pattern 1: No project exists yet

> 🎯 **Let's start a project first!**
>
> **Example phrases:**
> - "I want to build a blog"
> - "I want to build a task management app"
> - "I want to build a portfolio site"
>
> A rough idea is fine. Just tell me what you want to create.

### Pattern 2: Plans.md exists but no task is in progress

> 📋 **You have a plan. Let's get started!**
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

> 🔧 **Work in progress**
>
> **Current task:** {{task name}}
> **Progress:** {{completed}}/{{total}}
>
> **Example phrases:**
> - "Continue"
> - "Next task"
> - "How far along are we?"

### Pattern 4: After a phase completes

> ✅ **Phase complete!**
>
> **What you can do next:**
> - "Check that it works" → Start the development server
> - "Review it" → Run a code quality check
> - "Move to the next phase" → Begin the next set of work
> - "Commit" → Save the changes

### Pattern 5: An error occurred

> ⚠️ **A problem has occurred**
>
> **Situation:** {{error summary}}
>
> **Example phrases:**
> - "Fix it" → Attempt automatic repair
> - "Explain it" → Get a detailed description of the problem
> - "Skip it" → Move on to the next task

---

## Common Phrase Reference

| What you want to do | What to say |
|---------------------|-------------|
| Start a project | "I want to build ___" |
| View the plan | "Show me the plan" / "What's the current status?" |
| Start working | "Start" / "Build it" / "Do Phase 1" |
| Continue work | "Continue" / "Next" |
| Check that it works | "Run it" / "Show me" |
| Review the code | "Review it" / "Check it" |
| Save changes | "Commit" / "Save" |
| When stuck | "What should I do?" / "Help" |
| Hand everything off | "Do everything" / "Take care of it all" |

---

## Context Detection

This skill checks the following to select the appropriate response:

1. **Presence of AGENTS.md** → Whether the project has been initialized
2. **Contents of Plans.md** → Whether a plan exists and current progress
3. **Current task state** → Whether a `cc:WIP` marker is present
4. **Recent errors** → Whether a problem has occurred

---

## Implementation Notes

When this skill activates:

1. Analyze the current state
2. Select the appropriate pattern
3. Present concrete "example phrases"
4. Wait for the user's next action

**Important**: Avoid technical jargon; explain everything in plain, accessible language.
