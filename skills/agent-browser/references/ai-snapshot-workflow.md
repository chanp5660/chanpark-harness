# AI Snapshot Workflow

A workflow for AI agents leveraging the `snapshot` command in agent-browser.

---

## Overview

The `snapshot` command retrieves the page's accessibility tree and assigns a reference ID (`@e1`, `@e2`, etc.) to each element. This provides:

1. **No CSS selectors needed**: No dependency on dynamic IDs or class names
2. **Context awareness**: The role of each element (button, input, link) is clear
3. **Deterministic interaction**: Operations via references such as `@e1` are reliable

---

## Basic Workflow

### Step 1: Open the page

```bash
agent-browser open https://example.com
```

### Step 2: Take a snapshot

```bash
agent-browser snapshot -i -c
```

**Option description**:
- `-i, --interactive`: Show only interactive elements (buttons, links, input fields, etc.)
- `-c, --compact`: Remove empty structural elements for a compact view

**Example output**:
```
✓ Example Domain
  https://example.com/

- link "Home" [ref=e1]
- link "About" [ref=e2]
- button "Login" [ref=e3]
- input "Search" [ref=e4]
- button "Search" [ref=e5]
```

### Step 3: Interact via element references

```bash
# Click a link
agent-browser click @e1

# Type into a search form
agent-browser fill @e4 "search query"

# Click the search button
agent-browser click @e5
```

### Step 4: Verify the result

```bash
# Snapshot the new state
agent-browser snapshot -i -c
```

---

## Snapshot Option Details

### `-i, --interactive`

Show only interactive elements. Useful for narrowing down the target of an operation.

```bash
# Interactive elements only
agent-browser snapshot -i

# All elements (including text nodes)
agent-browser snapshot
```

### `-c, --compact`

Remove empty structural elements (divs, spans with no content, etc.).

```bash
# Compact output
agent-browser snapshot -c

# Show full structure
agent-browser snapshot
```

### `-d, --depth <n>`

Limit the depth of the tree. Useful for getting an overview of large pages.

```bash
# Up to depth 3
agent-browser snapshot -d 3
```

### `-s, --selector <sel>`

Scope the snapshot to a specific selector.

```bash
# Inside a login form only
agent-browser snapshot -s "form.login"

# Inside navigation only
agent-browser snapshot -s "nav"
```

### Combining options

```bash
# Recommended: interactive + compact
agent-browser snapshot -i -c

# Interactive elements inside a form only
agent-browser snapshot -i -c -s "form"

# Shallow tree for a quick overview
agent-browser snapshot -i -d 2
```

---

## Use-Case Workflows

### Login Flow

```bash
# 1. Open the login page
agent-browser open https://example.com/login

# 2. Take a snapshot
agent-browser snapshot -i -c
# Output:
# - input "Email" [ref=e1]
# - input "Password" [ref=e2]
# - button "Login" [ref=e3]
# - link "Forgot password?" [ref=e4]

# 3. Enter credentials
agent-browser fill @e1 "user@example.com"
agent-browser fill @e2 "password123"

# 4. Click the login button
agent-browser click @e3

# 5. Verify the result
agent-browser snapshot -i -c
agent-browser get url
```

### Form Submission

```bash
# 1. Open the form page
agent-browser open https://example.com/contact

# 2. Snapshot inside the form
agent-browser snapshot -i -c -s "form"
# Output:
# - input "Name" [ref=e1]
# - input "Email" [ref=e2]
# - textarea "Message" [ref=e3]
# - button "Send" [ref=e4]

# 3. Fill the form
agent-browser fill @e1 "John Doe"
agent-browser fill @e2 "john@example.com"
agent-browser fill @e3 "Hello, this is a test message."

# 4. Submit
agent-browser click @e4

# 5. Verify
agent-browser snapshot -i -c
```

### Navigation Exploration

```bash
# 1. Open the top page
agent-browser open https://example.com

# 2. Check the navigation
agent-browser snapshot -i -c -s "nav"
# Output:
# - link "Home" [ref=e1]
# - link "Products" [ref=e2]
# - link "About" [ref=e3]
# - link "Contact" [ref=e4]

# 3. Navigate to the Products page
agent-browser click @e2

# 4. Inspect the new page structure
agent-browser snapshot -i -c
```

### Interacting with Dynamic Content

```bash
# 1. Open the page
agent-browser open https://example.com/dashboard

# 2. Initial snapshot
agent-browser snapshot -i -c

# 3. Open a dropdown
agent-browser click @e5

# 4. Wait for dynamic content to load
agent-browser wait 500

# 5. New snapshot (dropdown menu is now visible)
agent-browser snapshot -i -c
# New elements appear:
# - menuitem "Option 1" [ref=e10]
# - menuitem "Option 2" [ref=e11]
# - menuitem "Option 3" [ref=e12]

# 6. Select an option
agent-browser click @e11
```

---

## Troubleshooting

### Element Not Found

```bash
# Full snapshot (all elements)
agent-browser snapshot

# Narrow down with a specific selector
agent-browser snapshot -s "#target-element"

# Wait and retry
agent-browser wait 2000
agent-browser snapshot -i -c
```

### Dynamic Pages

```bash
# Snapshot after JavaScript execution
agent-browser eval "document.querySelector('#load-more').click()"
agent-browser wait 1000
agent-browser snapshot -i -c
```

### Elements Inside an iframe

```bash
# Snapshot the main frame
agent-browser snapshot -i -c

# Elements inside an iframe cannot be accessed directly;
# use eval to interact with iframe content
agent-browser eval "document.querySelector('iframe').contentDocument.querySelector('button').click()"
```

---

## Best Practices

### 1. Always start with a snapshot

Always take a snapshot before interacting to understand the current state of the page.

### 2. Use interactive + compact as the default

```bash
agent-browser snapshot -i -c
```

### 3. Verify state after each operation

```bash
agent-browser click @e1
agent-browser snapshot -i -c  # Check the result
```

### 4. Add appropriate waits

Insert waits when dynamic content is involved:

```bash
agent-browser click @e1
agent-browser wait 500
agent-browser snapshot -i -c
```

### 5. Leverage sessions

Use sessions to maintain authenticated state:

```bash
agent-browser --session myapp open https://example.com/login
# ... perform login ...
# Continue subsequent operations in the same session
agent-browser --session myapp open https://example.com/dashboard
```
