# Typical Workflow Examples

Real-world flow of the two-agent workflow.

---

## Example 1: New Feature Development

### Phase 1: PM (Cursor) Creates Tasks

```markdown
# Plans.md

## 🟡 Pending Tasks

- [ ] User profile editing feature `pm:requested`
  - Edit name, email, and avatar image
  - With validation
  - Save change history
```

**PM says**: "Please ask Claude Code to implement the profile editing feature"

---

### Phase 2: Claude Code Starts Work

```bash
# Run in Claude Code
/work
```

**Claude Code's work**:
1. Load Plans.md
2. Detect `pm:requested` task
3. Update marker to `cc:WIP`
4. Begin implementation
5. Quality review with `/harness-review`
6. Fix issues if flagged → re-review (loop, up to 3 times)
7. Review OK → Auto-commit

```markdown
# Plans.md (after update)

## 🔴 In-Progress Tasks

- [ ] User profile editing feature `cc:WIP`
  - Edit name, email, and avatar image
  - With validation
  - Save change history
  - Related files:
    - `src/components/ProfileForm.tsx`
    - `src/lib/api/profile.ts`
```

---

### Phase 3: Claude Code Reports Completion (2-Agent only)

After Review OK and Auto-commit, in 2-Agent mode run `/handoff-to-cursor` to report to PM.

> **In Solo mode, handoff is not needed** — Review OK → Auto-commit completes /work.

```bash
# Run in Claude Code (2-Agent mode only)
/handoff-to-cursor
```

**Generated report**:

```markdown
## 📋 Completion Report: User Profile Editing Feature

### What was implemented
- Created ProfileForm component
- Profile API endpoint
- Validation with Zod
- Added change history table

### Changed files
- src/components/ProfileForm.tsx (+150 lines)
- src/lib/api/profile.ts (+80 lines)
- src/lib/validations/profile.ts (+25 lines)
- prisma/schema.prisma (+10 lines)

### Review result
✅ harness-review APPROVE (no Critical/High findings)

### Test results
✅ All tests passed (12/12)

### Next actions
- [ ] Verify behavior in staging environment
- [ ] Design review
```

---

### Phase 4: PM Reviews

```markdown
# Plans.md (after PM update)

## 🟢 Completed Tasks

- [x] User profile editing feature `pm:approved` (2024-01-15)
```

---

## Example 2: Emergency Bug Fix

### Emergency Request from PM

```markdown
## 🟡 Pending Tasks

- [ ] 🔥 [URGENT] Fix login error `pm:requested`
  - Symptom: Specific users cannot log in
  - Error: "Invalid token format"
  - Priority: Highest
```

### Claude Code's Response

1. Start with `/work`
2. Investigate error logs
3. Identify root cause and fix
4. Add tests
5. Review with `/harness-review` (fix issues then re-review if flagged)
6. Review OK → Auto-commit
7. Completion report with `/handoff-to-cursor` (2-Agent only; omit in Solo mode)

---

## Example 3: Auto-Fix on CI Failure

### CI Fails

```
GitHub Actions: ❌ Build failed
- TypeScript error in src/utils/date.ts:45
```

### Claude Code's Auto-Response

1. Detect error
2. Fix type error
3. Re-commit and push

**If failed 3 times**:

```markdown
## ⚠️ CI Escalation

Three fix attempts were made but the issue could not be resolved.

### Attempted fixes
1. Added type annotation → failed
2. Updated type definition file → failed
3. Adjusted tsconfig → failed

### Estimated cause
External library type definitions may be outdated

### Recommended actions
- [ ] Update @types/xxx to latest version
- [ ] Verify the library version itself
```

---

## Example 4: Parallel Task Execution

### When multiple tasks exist

```markdown
## 🟡 Pending Tasks

- [ ] Refactor header component `cc:TODO`
- [ ] Refactor footer component `cc:TODO`
- [ ] Add tests: utility functions `cc:TODO`
```

### When /work is executed

Claude Code determines whether parallel execution is possible:
- Independent tasks → parallel execution
- Dependencies present → sequential execution

```
🚀 Starting parallel execution
├─ Agent 1: Header refactoring
├─ Agent 2: Footer refactoring
└─ Agent 3: Add tests
```
