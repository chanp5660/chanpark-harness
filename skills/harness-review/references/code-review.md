# Code Review Flow

## In a nutshell

Collect the diff, examine the implementation, spec, Plans, regression, and tests, then block only the problems that must be blocked.

## Target Selection

Referenced from the Review Target Detection (`REVIEW_TARGET_ASK` contract) in `SKILL.md`.
The AskUserQuestion option literals, recommended order, and comparison range for each candidate when the target is ambiguous on a bare call are fixed here.

When multiple candidates exist simultaneously (`REVIEW_TARGET_AMBIGUOUS: working_tree_and_branch_commits`):

- Uncommitted changes only (Recommended): Compare staged / unstaged / untracked against HEAD
- Review everything: Review branch base..HEAD and uncommitted changes together
- Commits only: Review only committed work in branch base..HEAD

When the tree is clean and there is no branch diff (`REVIEW_TARGET_AMBIGUOUS: clean_tree_no_branch_commits`):

- Most recent 1 commit (Recommended): HEAD~1..HEAD
- Most recent 5 commits: HEAD~5..HEAD
- Another range: Wait for a user-specified ref

After the user responds:

```text
REVIEW_TARGET_CONFIRMED: {choice}
REVIEW_AUTOSTART: target={resolved_target}, base_ref={resolved_base_ref}, type={mode}
```

## Step 1: collect diff

Items to check:

```bash
git status --short
git diff --stat "${BASE_REF:-HEAD}"
git diff "${BASE_REF:-HEAD}"
git ls-files --others --exclude-standard
```

Untracked files do not appear in `git diff`.
Always include them in scope.

## Step 2: static scans

AI Residuals:

```bash
bash scripts/review-ai-residuals.sh --base "${BASE_REF:-HEAD}"
bash scripts/review-weak-supervision-report.sh
```

Candidates:

- `mockData`
- `dummy`
- `fake`
- `localhost`
- `TODO`
- `FIXME`
- `it.skip`
- `describe.skip`
- `test.skip`
- `expect(true).toBe(true)`

Do not make something major simply because a candidate was found.
Determine severity from diff context based on whether it "directly leads to a shipment failure or misconfiguration."
However, do not silently discard even minor findings — record them as observations (see Finding coverage below).

## Step 3: eight review lenses

| Perspective | What to look for |
|---|---|
| Security | SQL injection, cross-site scripting, secret leak, permission bypass |
| Performance | N+1, needless heavy IO, blocking work |
| Quality | duplicate logic, unclear boundary, fragile parsing |
| Accessibility | labels, focus, contrast, keyboard path |
| AI Residuals | fake success, skipped tests, mock-only implementation |
| Spec Alignment | Contradictions with the spec source of truth |
| Plans Alignment | Alignment with `Plans.md` task / DoD / Depends |
| Regression Safety | Regressions in existing behavior, mirror, CLI/skill UX |

## TDD compliance

For tasks where TDD is required, look for evidence that a failing test was confirmed first.
However, for cases where TDD is excessive such as docs-only or refactor-only changes, recording the skip reason is sufficient.

## Finding coverage (Opus 4.8)

Separate the finding stage from the verdict stage.

- The finding stage **prioritizes coverage**. Record all discovered issues with severity and confidence level, including uncertain or minor findings (retain in `review-result.v1`'s `observations[]` / `recommendations[]`).
- Gating happens only at the verdict stage (critical / major → `REQUEST_CHANGES`, minor only → `APPROVE`).
- "Does it directly lead to a shipment failure or misconfiguration?" is **the determination of severity**, not **the determination of whether to record it**. Do not silently discard a minor finding.

Opus 4.8 has a tendency to faithfully follow "do not report low-severity findings," investigate but suppress reporting, and reduce recall.
Discarding findings is the responsibility of the verdict stage, not the investigation stage.

## Verdict

1. critical / major found → `REQUEST_CHANGES`
2. spec source of truth / `Plans.md` / regression gate fails → `REQUEST_CHANGES`
3. Decision required → `decision_needed`
4. Only minor / recommendation → `APPROVE`
5. Insufficient evidence → `REQUEST_CHANGES` or `decision_needed`

## Post-fix Re-review

After `REQUEST_CHANGES`, always perform a re-review after fixes.
If the same issue is failed twice in a row, force a TeamAgent Debate.
