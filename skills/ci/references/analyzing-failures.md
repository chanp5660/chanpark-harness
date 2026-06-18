---
name: ci-analyze-failures
description: "Analyze CI failure logs and identify the root cause. Use when tests or builds fail in a CI/CD pipeline."
allowed-tools: ["Read", "Grep", "Bash"]
---

# CI Analyze Failures

A skill for analyzing CI/CD pipeline failures and identifying their root cause.
Interprets logs from GitHub Actions, GitLab CI, and similar systems.

---

## Inputs

- **CI logs**: Logs from the failed job
- **run_id**: CI run identifier (if available)
- **Repository context**: CI configuration files

---

## Outputs

- **Root cause identified**: Specific cause of the failure
- **Fix suggestions**: Proposed remediation steps

---

## Execution Steps

### Step 1: Check CI Status

```bash
# For GitHub Actions
gh run list --limit 5

# View the latest failure
gh run view --log-failed
```

### Step 2: Retrieve Failure Logs

```bash
# Logs for a specific run
gh run view {{run_id}} --log

# Only the failed steps
gh run view {{run_id}} --log-failed
```

### Step 3: Analyze Error Patterns

#### Build Errors

```
Pattern: "error TS\d+:" or "Build failed"
Possible causes:
- TypeScript type errors
- Missing dependencies
- Syntax errors
```

#### Test Errors

```
Pattern: "FAIL" or "✕" or "AssertionError"
Possible causes:
- Test assertions failing
- Test timeouts
- Mock mismatches
```

#### Dependency Errors

```
Pattern: "npm ERR!" or "Could not resolve"
Possible causes:
- package.json inconsistency
- Private package authentication
- Version conflicts
```

#### Environment Errors

```
Pattern: "not found" or "undefined"
Possible causes:
- Missing environment variables
- Missing secrets
- Path issues
```

### Step 4: Output Analysis Results

```markdown
## 🔍 CI Failure Analysis

**Run ID**: {{run_id}}
**Failure time**: {{timestamp}}
**Failed step**: {{step_name}}

### Root Cause

**Error type**: {{Build / Test / Dependency / Environment}}

**Error message**:
```
{{core error excerpt}}
```

**Root cause analysis**:
{{Specific explanation of the cause}}

### Related Files

| File | Relevance |
|------|-----------|
| `{{path}}` | {{how it is related}} |

### Fix Suggestions

1. {{Specific fix step 1}}
2. {{Specific fix step 2}}

### Automated Fix Feasibility

- Automated fix: {{Possible / Not possible}}
- Reason: {{reason}}
```

---

## Error Pattern Dictionary

### TypeScript Errors

| Error Code | Meaning | Typical Fix |
|------------|---------|-------------|
| TS2304 | Name not found | Add import |
| TS2322 | Type mismatch | Fix the type |
| TS2345 | Argument type mismatch | Fix the argument |
| TS7006 | Implicit any | Add type annotation |

### npm Errors

| Error | Meaning | Typical Fix |
|-------|---------|-------------|
| ERESOLVE | Dependency resolution failed | Delete package-lock & reinstall |
| ENOENT | File not found | Check the path |
| EACCES | Permission error | Check CI configuration |

### Jest/Vitest Errors

| Error | Meaning | Typical Fix |
|-------|---------|-------------|
| Timeout | Test timed out | Extend timeout or fix async handling |
| Snapshot | Snapshot mismatch | Run `npm test -- -u` |

---

## Priority for Multiple Errors

1. **Build errors**: Fix first — nothing else can proceed
2. **Dependency errors**: Must be resolved before building
3. **Test errors**: Address after the build succeeds
4. **Lint errors**: Address last

---

## Connecting to the Next Action

After analysis is complete:

> 📊 **Analysis Complete**
>
> **Cause**: {{summary of root cause}}
>
> **Next actions**:
> - "Fix it" → Attempt automatic fix
> - "More detail" → Run deeper analysis
> - "Skip" → Switch to manual handling

---

## Notes

- **Logs can be large**: Extract only the critical sections
- **Watch for cascading errors**: Find the first error in the chain
- **Account for environment differences**: Consider differences between local and CI environments
