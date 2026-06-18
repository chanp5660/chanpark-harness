---
name: merge-plans
description: "Merge-update Plans.md while preserving user tasks. Use when multiple Plans.md files need to be consolidated."
allowed-tools: ["Read", "Write", "Edit"]
---

# Merge Plans Skill

A skill for updating an existing Plans.md by applying template structure
while preserving the user's task data.

---

## Purpose

- Preserve user tasks (🔴🟡🟢📦 sections)
- Update template structure and marker definitions
- Update last-modified information

---

## Plans.md Structure

```markdown
# Plans.md - Task Management

> **Project**: {{PROJECT_NAME}}
> **Last Updated**: {{DATE}}
> **Updated by**: Claude Code

---

## 🔴 In-Progress Tasks        ← user data (preserve)

## 🟡 Pending Tasks            ← user data (preserve)

## 🟢 Completed Tasks          ← user data (preserve)

## 📦 Archive                  ← user data (preserve)

## Marker Legend               ← updated from template

## Last Update Info            ← update the date
```

---

## Merge Algorithm

### Step 1: Split into Sections

```
Split the existing Plans.md into the following sections:

1. Header (# Plans.md ... ---)
2. 🔴 In-Progress Tasks (up to the next section)
3. 🟡 Pending Tasks (up to the next section)
4. 🟢 Completed Tasks (up to the next section)
5. 📦 Archive (up to the next section)
6. Marker Legend (up to the next section)
7. Last Update Info (to end of file)
```

### Step 2: Extract Task Sections

```bash
extract_section() {
  local file="$1"
  local start_marker="$2"
  local end_markers="$3"  # pipe-separated end markers

  awk -v start="$start_marker" -v ends="$end_markers" '
    BEGIN { in_section = 0; split(ends, end_arr, "|") }
    $0 ~ start { in_section = 1; next }
    in_section {
      for (i in end_arr) {
        if ($0 ~ end_arr[i]) { in_section = 0; exit }
      }
      if (in_section) print
    }
  ' "$file"
}

# Extract each section
TASKS_WIP=$(extract_section "$PLANS_FILE" "## 🔴" "## 🟡|## 🟢|## 📦|## Marker Legend|---")
TASKS_TODO=$(extract_section "$PLANS_FILE" "## 🟡" "## 🔴|## 🟢|## 📦|## Marker Legend|---")
TASKS_DONE=$(extract_section "$PLANS_FILE" "## 🟢" "## 🔴|## 🟡|## 📦|## Marker Legend|---")
TASKS_ARCHIVE=$(extract_section "$PLANS_FILE" "## 📦" "## 🔴|## 🟡|## 🟢|## Marker Legend|---")
```

### Step 3: Validate Tasks

```bash
# Verify sections are not empty
count_tasks() {
  echo "$1" | grep -c "^\s*- \[" || echo "0"
}

WIP_COUNT=$(count_tasks "$TASKS_WIP")
TODO_COUNT=$(count_tasks "$TASKS_TODO")
DONE_COUNT=$(count_tasks "$TASKS_DONE")
ARCHIVE_COUNT=$(count_tasks "$TASKS_ARCHIVE")

echo "Tasks to preserve:"
echo "  In-Progress: $WIP_COUNT"
echo "  Pending: $TODO_COUNT"
echo "  Completed: $DONE_COUNT"
echo "  Archive: $ARCHIVE_COUNT"
```

### Step 4: Generate New Plans.md

```markdown
# Plans.md - Task Management

> **Project**: {{PROJECT_NAME}}
> **Last Updated**: {{DATE}}
> **Updated by**: Claude Code

---

## 🔴 In-Progress Tasks

<!-- List cc:WIP tasks here -->

{{TASKS_WIP}}

---

## 🟡 Pending Tasks

<!-- List cc:TODO, pm:requested tasks here -->

{{TASKS_TODO}}

---

## 🟢 Completed Tasks

<!-- List cc:done, pm:approved tasks here -->

{{TASKS_DONE}}

---

## 📦 Archive

<!-- Move old completed tasks here -->

{{TASKS_ARCHIVE}}

---

## Marker Legend

| Marker | Meaning |
|---------|------|
| `pm:requested` | Task requested by PM |
| `cc:TODO` | Claude Code not started |
| `cc:WIP` | Claude Code in progress |
| `cc:done` | Claude Code done (awaiting confirmation) |
| `pm:approved` | PM confirmed |
| `blocked` | Blocked (include reason) |

---

## Last Update Info

- **Updated at**: {{DATE}}
- **Last Session**: Claude Code
- **Branch**: main
- **Update type**: Plugin update
```

---

## Handling Empty Sections

If a section has no tasks, insert default text:

```markdown
## 🔴 In-Progress Tasks

<!-- List cc:WIP tasks here -->

(none currently)
```

---

## Error Handling

### If Plans.md Cannot Be Parsed

```bash
if ! validate_plans_structure "$PLANS_FILE"; then
  echo "⚠️ Could not parse the structure of Plans.md"
  echo "Keeping backup and using new template instead"

  # Backup
  cp "$PLANS_FILE" "${PLANS_FILE}.bak.$(date +%Y%m%d%H%M%S)"

  # Use template
  use_template_instead=true
fi
```

### If Required Sections Are Missing

Fill in missing sections with template defaults.

---

## Output

| Field | Description |
|------|------|
| `merge_successful` | Merge success flag |
| `tasks_wip_count` | Number of in-progress tasks |
| `tasks_todo_count` | Number of pending tasks |
| `tasks_done_count` | Number of completed tasks |
| `tasks_archive_count` | Number of archived tasks |
| `backup_created` | Whether a backup was created |

---

## Usage Example

```bash
# Invoke the skill
merge_plans \
  --existing "./Plans.md" \
  --template "$PLUGIN_PATH/templates/Plans.md.template" \
  --output "./Plans.md" \
  --project-name "my-project" \
  --date "$(date +%Y-%m-%d)"
```

---

## Related Skills

- `update-2agent-files` - Full update flow
- `generate-workflow-files` - New file generation
