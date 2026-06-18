---
name: ci
description: "CI red? Call us. Pipeline fire brigade deploys. Use when user mentions CI failures, build errors, test failures, or pipeline issues. Do NOT load for: local builds, standard implementation work, reviews, or setup."
allowed-tools: ["Read", "Grep", "Bash", "Task", "Monitor"]
user-invocable: true
context: fork
argument-hint: "[analyze|fix|run]"
---

# CI/CD Skills

A skill set for diagnosing and resolving CI/CD pipeline issues.

---

## Trigger Conditions

- "CI is broken" / "GitHub Actions failed"
- "Build error" / "Tests are failing"
- "Fix the pipeline"

---

## Feature Overview

| Feature | Details | Trigger |
|---------|---------|---------|
| **Failure Analysis** | See [references/analyzing-failures.md](${CLAUDE_SKILL_DIR}/references/analyzing-failures.md) | "Check the logs" / "Find the root cause" |
| **Test Fixing** | See [references/fixing-tests.md](${CLAUDE_SKILL_DIR}/references/fixing-tests.md) | "Fix the tests" / "Suggest a fix" |

---

## Execution Steps

1. **Test vs. Implementation judgment** (Step 0)
2. Classify user intent (analyze or fix)
3. Assess complexity (see below)
4. Read the appropriate reference file from "Feature Overview" above, or launch the ci-cd-fixer sub-agent
5. Verify results and re-run if necessary

### Step 0: Test vs. Implementation Judgment (Quality Gate)

When a CI failure occurs, first triage the root cause:

```
CI Failure Reported
    ↓
┌─────────────────────────────────────────┐
│       Test vs. Implementation           │
├─────────────────────────────────────────┤
│  Analyze the root cause of the error:  │
│  ├── Implementation is wrong → fix it  │
│  ├── Test is outdated → ask the user   │
│  └── Environment issue → fix env       │
└─────────────────────────────────────────┘
```

#### Prohibited Actions (Integrity Protection)

```markdown
⚠️ Prohibited actions when CI fails

The following "fixes" are NOT allowed:

| Prohibited | Example | Correct approach |
|------------|---------|-----------------|
| Skipping tests | `it.skip(...)` | Fix the implementation |
| Removing assertions | delete `expect()` | Verify the expected value |
| Bypassing CI checks | `continue-on-error` | Fix the root cause |
| Relaxing lint rules | `eslint-disable` | Fix the code |
```

#### Decision Flow

```markdown
🔴 CI is failing

**A decision is required**:

1. **Implementation is wrong** → Fix the implementation ✅
2. **Test expected values are outdated** → Ask the user for confirmation
3. **Environment issue** → Fix the environment configuration

⚠️ Tampering with tests (skipping, deleting assertions) is prohibited

Which case applies?
```

#### When Approval Is Required

If a test/configuration change is unavoidable:

```markdown
## 🚨 Test/Configuration Change Approval Request

### Reason
[Why this change is necessary]

### Changes
[Diff]

### Alternatives Considered
- [ ] Confirmed that fixing the implementation alone cannot resolve this

Waiting for explicit user approval
```

### Using Extended Git Log Flags (CC 2.1.49+)

Use structured git logs to identify the commit responsible for a CI failure.

#### Identifying the Responsible Commit

```bash
# Analyze commits in a structured format
git log --format="%h|%s|%an|%ad" --date=short -10

# Analyze chronological order with topological sort
git log --topo-order --oneline -20

# Correlate changed files with the root cause
git log --raw --oneline -5
```

#### Common Use Cases

| Use Case | Flag | Effect |
|----------|------|--------|
| **Identify failure cause** | `--format="%h|%s"` | Structured commit list |
| **Chronological tracking** | `--topo-order` | Tracking with merge order considered |
| **Assess change impact** | `--raw` | Detailed file change display |
| **Exclude merge commits** | `--cherry-pick --no-merges` | Extract only real commits |

#### Example Output

```markdown
🔍 CI Failure Root Cause Analysis

Recent commits (structured):
| Hash | Subject | Author | Date |
|------|---------|--------|------|
| a1b2c3d | feat: update API | Alice | 2026-02-04 |
| e4f5g6h | test: add tests | Bob | 2026-02-03 |

Changed files (--raw):
├── src/api/endpoint.ts (Modified) ← type error originated here
├── tests/api.test.ts (Modified)
└── package.json (Modified)

→ Commit a1b2c3d is likely responsible
  Type error: src/api/endpoint.ts:42
```

## Sub-Agent Integration

Launch ci-cd-fixer via the Task tool when any of the following conditions are met:

- The fix → re-run → failure loop has occurred **2 or more times**
- Or the error spans multiple files and is complex

**Launch pattern:**

```
Task tool:
  subagent_type="ci-cd-fixer"
  prompt="Diagnose and fix the CI failure. Error log: {error_log}"
```

ci-cd-fixer operates in safety-first mode (dry-run by default).
See `agents/ci-cd-fixer.md` for details.

---

## For VibeCoder Users

```markdown
🔧 How to describe a broken CI

1. **"CI is down" / "It went red"**
   - Automated tests are failing

2. **"Why is it failing?"**
   - I want you to investigate the cause

3. **"Fix it"**
   - Attempt an automatic fix

💡 Important: "cheating" fixes are prohibited
   - ❌ Deleting or skipping tests
   - ✅ Fixing the code correctly

If you think the test itself might be wrong,
confirm first before deciding on the approach
```
