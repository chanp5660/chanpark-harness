---
name: ui
description: "Explicit helper for UI components, hero sections, forms, feedback, and contact surfaces. Do NOT load for: authentication, backend implementation, database work, or business logic."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
user-invocable: false
disable-model-invocation: true
---

# UI Skills

A collection of skills responsible for generating UI components and forms.

## Constraint Priority and Application Conditions

1. By default, apply the constraints in `${CLAUDE_SKILL_DIR}/references/ui-skills.md` with the highest priority.
2. Apply `${CLAUDE_SKILL_DIR}/references/frontend-design.md` **only when explicitly requested**, such as for "distinctive / unique / expressive / brand-forward" designs.
3. The MUST/NEVER rules in UI Skills are maintained by default. However, the following exceptions are permitted **only when explicitly requested by the user**:
   - Gradients, glows, and strong decorative elements
   - Animations (additions or extensions)
   - Custom easing

## Feature Details

| Feature | Detail |
|------|------|
| **Constraint set** | See [references/ui-skills.md](${CLAUDE_SKILL_DIR}/references/ui-skills.md) / [references/frontend-design.md](${CLAUDE_SKILL_DIR}/references/frontend-design.md) |
| **Component generation** | See [references/component-generation.md](${CLAUDE_SKILL_DIR}/references/component-generation.md) |
| **Feedback forms** | See [references/feedback-forms.md](${CLAUDE_SKILL_DIR}/references/feedback-forms.md) |

## Execution Steps

1. **Apply the constraint set** (following priority order)
2. **Quality gate** (Step 0)
3. Classify the user's request
4. Read the appropriate reference file from "Feature Details" above
5. Generate according to its contents

### Step 0: Quality Gate (a11y Checklist)

When generating UI components, ensure accessibility:

```markdown
♿ Accessibility Checklist

The generated UI should satisfy the following:

### Required
- [ ] Set alt attributes on images
- [ ] Associate form elements with labels
- [ ] Keyboard operable (Tab key moves focus)
- [ ] Focus state is visually apparent

### Recommended
- [ ] Information conveyed without relying on color alone
- [ ] Contrast ratio 4.5:1 or higher (text)
- [ ] Appropriate use of aria-label / aria-describedby
- [ ] Heading structure (h1 → h2 → h3) is logical

### Interactive Elements
- [ ] Buttons have descriptive labels (e.g. "View product details" not just "Details")
- [ ] Focus trap for modals/dialogs
- [ ] Error messages are read by screen readers
```

### For VibeCoder

```markdown
♿ Designing for everyone

1. **Add descriptions to images**
   - Use "Red sneakers, front view" instead of "Product image"

2. **Make clickable areas keyboard-accessible**
   - Navigate with Tab, confirm with Enter

3. **Don't rely on color alone**
   - For errors, use icon + text in addition to red color
```
