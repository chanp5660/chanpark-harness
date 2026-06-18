---
name: agent-browser
description: "Browser automation through the repo agent-browser CLI. Explicit helper for navigation, forms, screenshots, scraping, and web-app checks. Prefer Browser Use or Playwright when available. Do NOT load for: sharing URLs, embedding links, or editing screenshot files."
allowed-tools: ["Bash", "Read"]
user-invocable: false
disable-model-invocation: true
context: fork
argument-hint: "[url] [--headless]"
---

# Agent Browser Skill

A skill for browser automation. Uses the agent-browser CLI to perform UI debugging, verification, and automated interactions.

---

## Trigger Phrases

This skill is auto-invoked by the following phrases:

- "open this page", "check the URL"
- "click on", "type into", "fill the form"
- "take a screenshot"
- "check the UI", "test the screen"
- "open this page", "click on", "fill the form", "screenshot"

---

## Feature Overview

| Feature | Details |
|---------|---------|
| **Browser Automation** | See [references/browser-automation.md](${CLAUDE_SKILL_DIR}/references/browser-automation.md) |
| **AI Snapshot Workflow** | See [references/ai-snapshot-workflow.md](${CLAUDE_SKILL_DIR}/references/ai-snapshot-workflow.md) |

## Execution Steps

### Step 0: Verify agent-browser

```bash
# Check installation
which agent-browser

# If not installed
npm install -g agent-browser
agent-browser install
```

### Step 1: Classify the user's request

| Request Type | Action |
|-------------|--------|
| Open a URL | `agent-browser open <url>` |
| Click an element | snapshot → `agent-browser click @ref` |
| Fill a form | snapshot → `agent-browser fill @ref "text"` |
| Check state | `agent-browser snapshot -i -c` |
| Screenshot | `agent-browser screenshot <path>` |
| Debug | `agent-browser --headed open <url>` |

### Step 2: AI Snapshot Workflow (recommended)

For most operations, first **take a snapshot** and then interact via element references:

```bash
# 1. Open the page
agent-browser open https://example.com

# 2. Take a snapshot (AI-oriented, interactive elements only)
agent-browser snapshot -i -c

# Example output:
# - link "Home" [ref=e1]
# - button "Login" [ref=e2]
# - input "Email" [ref=e3]
# - input "Password" [ref=e4]
# - button "Submit" [ref=e5]

# 3. Interact via element references
agent-browser click @e2           # Click the Login button
agent-browser fill @e3 "user@example.com"
agent-browser fill @e4 "password123"
agent-browser click @e5           # Submit
```

### Step 3: Verify the result

```bash
# Check current state via snapshot
agent-browser snapshot -i -c

# Or check the URL
agent-browser get url

# Take a screenshot
agent-browser screenshot result.png
```

---

## Quick Reference

### Basic Operations

| Command | Description |
|---------|-------------|
| `open <url>` | Open a URL |
| `snapshot -i -c` | AI-oriented snapshot |
| `click @e1` | Click an element |
| `fill @e1 "text"` | Fill a form field |
| `type @e1 "text"` | Type text into an element |
| `press Enter` | Press a key |
| `screenshot [path]` | Take a screenshot |
| `close` | Close the browser |

### Navigation

| Command | Description |
|---------|-------------|
| `back` | Go back |
| `forward` | Go forward |
| `reload` | Reload the page |

### Information Retrieval

| Command | Description |
|---------|-------------|
| `get text @e1` | Get text content |
| `get html @e1` | Get HTML content |
| `get url` | Get current URL |
| `get title` | Get page title |

### Waiting

| Command | Description |
|---------|-------------|
| `wait @e1` | Wait for an element |
| `wait 1000` | Wait 1 second |

### Debugging

| Command | Description |
|---------|-------------|
| `--headed` | Show the browser window |
| `console` | Show console logs |
| `errors` | Show page errors |
| `highlight @e1` | Highlight an element |

---

## Session Management

Manage multiple tabs/sessions in parallel:

```bash
# Specify a session
agent-browser --session admin open https://admin.example.com
agent-browser --session user open https://example.com

# List sessions
agent-browser session list

# Operate within a specific session
agent-browser --session admin snapshot -i -c
```

---

## Choosing Between agent-browser and MCP Browser Tools

| Tool | Recommended | Use Case |
|------|-------------|----------|
| **agent-browser** | ★★★ | First choice. Powerful AI-oriented snapshots |
| chrome-devtools MCP | ★★☆ | When Chrome is already open |
| playwright MCP | ★★☆ | Complex E2E tests |

**Rule**: Try agent-browser first; fall back to MCP tools only if it does not work.

---

## Notes

- agent-browser runs in headless mode by default
- Use the `--headed` option to display the browser window
- Sessions remain active until explicitly closed with `close`
- Use sessions to maintain authenticated state on sites that require login
