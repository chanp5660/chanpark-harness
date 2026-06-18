---
name: ci-fix-failing-tests
description: "Guide for fixing tests that fail in CI. Use when the cause of a CI failure has been identified and an automatic fix is to be attempted."
allowed-tools: ["Read", "Edit", "Bash"]
---

# CI Fix Failing Tests

A skill for fixing tests that fail in CI.
Applies fixes to either the test code or the implementation code.

---

## Inputs

- **Failing test info**: Test name, error message
- **Test file**: Source of the failing test
- **Code under test**: Implementation being tested

---

## Outputs

- **Fixed code**: Corrected test or implementation
- **Confirmation that tests pass**

---

## Execution Steps

### Step 1: Identify the Failing Test

```bash
# Run tests locally
npm test 2>&1 | tail -50

# Run a specific file's tests
npm test -- {{test-file}}
```

### Step 2: Classify the Error Type

#### Type A: Assertion Failure

```
Expected: "expected value"
Received: "actual value"
```

→ The implementation differs from what is expected, or the test expected value is wrong

#### Type B: Timeout

```
Timeout - Async callback was not invoked within the 5000ms timeout
```

→ An async operation did not complete, or took too long

#### Type C: Type Error

```
TypeError: Cannot read properties of undefined
```

→ null/undefined access, or an initialization problem

#### Type D: Mock-Related

```
expected mockFn to have been called
```

→ Mock not configured correctly, or the function was never called

### Step 3: Determine the Fix Strategy

```markdown
## Fix Strategy Decision

1. **If the test is correct** → Fix the implementation
2. **If the implementation is correct** → Fix the test
3. **If both need changes** → Prioritize the implementation

Decision criteria:
- Which is correct according to the spec/requirements?
- What changed recently?
- Impact on other tests
```

### Step 4: Implement the Fix

#### Fixing an Assertion Failure

```typescript
// When the test expected value is wrong
it('calculates correctly', () => {
  // Before fix
  expect(calculate(2, 3)).toBe(5)
  // After fix (if spec says multiplication)
  expect(calculate(2, 3)).toBe(6)
})

// When the implementation is wrong
// → Fix the implementation file
```

#### Fixing a Timeout

```typescript
// Extend the timeout
it('fetches data', async () => {
  // ...
}, 10000)  // Extended to 10 seconds

// Or use async/await correctly
it('fetches data', async () => {
  await waitFor(() => {
    expect(screen.getByText('Data')).toBeInTheDocument()
  })
})
```

#### Fixing Mock-Related Issues

```typescript
// Add mock configuration
vi.mock('../api', () => ({
  fetchData: vi.fn().mockResolvedValue({ data: 'mock' })
}))

// Reset in beforeEach
beforeEach(() => {
  vi.clearAllMocks()
})
```

### Step 5: Verify After Fixing

```bash
# Re-run the failing test
npm test -- {{test-file}}

# Run all tests (regression check)
npm test
```

---

## Fix Pattern Reference

### Updating Snapshots

```bash
# Update snapshots
npm test -- -u

# Only for a specific test
npm test -- {{test-file}} -u
```

### Fixing Async Tests

```typescript
// Use findBy (auto-waits)
const element = await screen.findByText('Text')

// Use waitFor
await waitFor(() => {
  expect(mockFn).toHaveBeenCalled()
})
```

### Updating Mock Data

```typescript
// Update mocks to match implementation changes
const mockData = {
  id: 1,
  name: 'Test',
  createdAt: new Date().toISOString()  // new field
}
```

---

## Post-Fix Checklist

- [ ] The previously failing test now passes
- [ ] No other tests were broken
- [ ] The fix aligns with the intended behavior
- [ ] Tests are not overly permissive

---

## Completion Report Format

```markdown
## ✅ Test Fix Complete

### Changes Made

| Test | Problem | Fix |
|------|---------|-----|
| `{{test name}}` | {{problem}} | {{fix applied}} |

### Verification Results

```
Tests: {{passed}} passed, {{total}} total
```

### Next Actions

"Commit this" or "Re-run CI"
```

---

## Notes

- **Do not delete tests**: Deletion is a last resort
- **Skips are temporary only**: Permanent skips are prohibited
- **Identify the root cause**: Avoid surface-level fixes
