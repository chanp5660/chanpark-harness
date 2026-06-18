---
name: core-diff-aware-editing
description: "Edit files with minimal diff to minimize impact on existing code."
allowed-tools: ["Read", "Edit"]
---

# Diff-Aware Editing

A skill for making changes to files with the smallest possible diff.
Prevents destruction of existing code and produces changes that are easy to review.

---

## Core Principles

### 1. Read Before Edit

**Always read the target file before editing it**

```
❌ Bad: Overwrite the entire file with the Write tool
✅ Good: Read → Verify contents → Use Edit to change only the necessary parts
```

### 2. Prioritize Minimal Diff

Keep changes to the absolute minimum:

- Preserve existing indentation and formatting
- Leave existing comments in place
- Match the coding style already in use

### 3. Change One Meaningful Unit at a Time

```typescript
// ❌ Bad: Mixing unrelated changes
// Adding a function + reformatting + reorganizing imports

// ✅ Good: Focus on one change
// Adding a function only
```

---

## How to Use the Edit Tool

### Pattern 1: Simple Replacement

```
old_string: "const value = 1"
new_string: "const value = 2"
```

### Pattern 2: Adding a Code Block

```
old_string: "// TODO: implement feature"
new_string: "// Feature implemented
const feature = () => {
  // implementation
}"
```

### Pattern 3: Modifying a Function

```
old_string: "function getData() {
  return []
}"
new_string: "function getData() {
  const data = fetchData()
  return data
}"
```

---

## Patterns to Avoid

### 1. Rewriting the Entire File

```
❌ Using the Write tool to rewrite a 100-line file from scratch
✅ Using the Edit tool to fix only the 5 lines that need changing
```

### 2. Mixing in Formatting Changes

```
❌ Changing indentation at the same time as adding a feature
✅ Add the feature only. Handle formatting in a separate commit
```

### 3. Adding Unnecessary Blank Lines or Comments

```
❌ Imposing your own style
✅ Follow the existing style
```

---

## Pre-Edit Checklist

1. [ ] Verified the target file with Read
2. [ ] Identified the exact location that needs to change
3. [ ] Understood the existing style (indentation, naming conventions)
4. [ ] Confirmed the change is within `paths.allowed_modify`
5. [ ] Can visualize the expected behavior after the change

---

## Post-Edit Verification

```bash
# Review the diff
git diff

# Check the line count changed (is it larger than expected?)
git diff --stat

# Check for syntax errors
npm run build 2>&1 | head -20
# or
npx tsc --noEmit
```

---

## Editing Multiple Files

When editing multiple files:

1. **Order by dependency**: Type definitions → Implementation → Tests
2. **Ensure consistency**: Make related changes together
3. **Keep intermediate states buildable**: The build should pass after each individual edit

---

## Handling Edit Errors

If an error occurs during editing:

1. **Re-read the original code**: Use Read to check the current state
2. **Verify the old_string match**: Pay close attention to whitespace and line endings
3. **Split and retry**: Break large changes into smaller pieces
