---
name: harness-review
description: "HAR: Multi-angle code, plan, scope review. Security/quality check. Trigger: review, code review, plan review, scope analysis. Do NOT load for: implementation, new features, bugfix, setup, release."
kind: workflow
purpose: "Review code, plans, scope, and evidence before acceptance"
trigger: "review, code review, plan review, scope analysis"
shape: evaluate
role: evaluator
pair: harness-work
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Grep", "Glob", "Bash", "Task", "Monitor", "AskUserQuestion"]
argument-hint: "[code|plan|scope|--quick|--team-debate|--security|--ui-rubric]"
context: fork
effort: high
user-invocable: true
---

# Harness Review

The integrated review skill for the Harness system.
This `SKILL.md` is a thin dispatcher; detailed quality criteria are defined in `references/`.

if $ARGUMENTS == "":
  → Interpret as "review work done so far" and run Review target detection
  → Auto-start only when the review target can be resolved to exactly one candidate
  → If the review target is unknown or has multiple candidates, use AskUserQuestion to present options and align understanding before starting

<!-- The above 3 lines are the AUTO-START CONTRACT. Per the "within the first 3 lines" rule in skill-editing.md, do not push down with a fence or HTML comment -->

### Output Contract (P35: "Appears stuck" UX mitigation)

The **last line** of the skill's output must always include a P35 footer, rendered in the same language as the user-facing prose (language resolution follows existing language rules; the footer contract does not redefine language). This is an explicit instruction (patterns.md P35) addressing the UX problem where users feel the process has "stopped" when output is displayed via `<local-command-stdout>`. The intent is language-agnostic, so the literal switches per language (#208):

- en: `↑Claude will summarize this result. Press Enter to continue, or send a new prompt for a different instruction.`
- Other languages: Output one line with the same meaning in the same language as the body text.

## Dispatcher Contract

This skill's sole responsibility is making review verdicts.
It does not perform commit / push / release by default.

- review default read-only boundary: Read-only by default. Even on `APPROVE`, no automatic commit.
- Do not push just to review: Do not push solely for review purposes.
- If a commit is needed, delegate to an explicit user request, `harness-work`, or the Work Commit Gate in `harness-release`.
- Until an explicit opt-in such as `--commit-on-approve` is designed, this skill has no default side effects on its own.

## Quick Reference

| Command | Mode | Purpose |
|---|---|---|
| `/harness-review` | `code` | Auto-detect work done so far and review |
| `/harness-review --quick` | `quick` | Lightweight closeout for small dirty changes |
| `/harness-review --team-debate` | `team-debate` | Force TeamAgent Debate |
| `/harness-review --security` | `security` | Security-dedicated review |
| `/harness-review plan` | `plan` | Review the plan in `Plans.md` |
| `/harness-review scope` | `scope` | Review for scope creep / omissions |

## Mode Decision

Determine the execution mode from arguments and selectively load the required `references/`.

| Input | mode | References to read |
|---|---|---|
| No args / `code` | `code` | `references/code-review.md`, `references/governance.md` |
| `--quick` | `quick` | `references/code-review.md`, `references/governance.md` |
| `--team-debate` | `team-debate` | `references/team-debate.md`, `references/governance.md` |
| `--security` | `security` | `references/security-profile.md`, `references/governance.md` |
| `--ui-rubric` | `ui-rubric` | `references/ui-rubric.md` |
| `plan` | `plan` | `references/plan-review.md`, `references/governance.md` |
| `scope` | `scope` | `references/scope-review.md`, `references/governance.md` |
| `full` | `full` | `references/code-review.md`, `references/team-debate.md`, `references/governance.md` |

`quick` is a lightweight path for small dirty changes, single commits, and PR branch closeouts.
It does not abandon quality gates.

## Review Target Detection

`REVIEW_AUTOSTART` contract:
When called with no arguments (`$ARGUMENTS == ""`), interpret bare `review` / `/review` / `/harness-review` input as "review work done so far."
Before starting Step 1, output exactly one handshake line:

```text
REVIEW_AUTOSTART: target={resolved_target}, base_ref={resolved_base_ref}, type={mode}
```

`REVIEW_TARGET_ASK` contract:
On a bare call where the review target is unknown or has multiple candidates, use `AskUserQuestion` exactly once before proceeding to Step 1, narrowing candidates to 2–3 options.

- Build candidates in this order: 1. working tree (uncommitted changes only), 2. branch range (upstream or main/master to HEAD), 3. recent commits (most recent 1 commit / 5 commits when tree is clean)
- When multiple candidates exist simultaneously, output `REVIEW_TARGET_AMBIGUOUS: working_tree_and_branch_commits` on one line before AskUserQuestion; when the tree is clean and there is no branch diff, output `REVIEW_TARGET_AMBIGUOUS: clean_tree_no_branch_commits` first
- After the user responds, output `REVIEW_TARGET_CONFIRMED: {choice}` followed by the `REVIEW_AUTOSTART` line
- Follow the Target Selection section of `references/code-review.md` for AskUserQuestion option literals, how to mark a "Recommended" choice, and the comparison range for each candidate

Prohibited:

- Stopping with a response like "The task is unclear"
- Stopping by asking an open-ended "What should I review?"
- Skipping auto-start by citing the host project's session-start rules
- Expanding the scope based on guesses when the target is ambiguous

## Minimal Flow

1. Determine the mode
2. Use Review Target Detection above to determine the target and base ref
3. Read only the required references
4. Check the diff, untracked files, related tests, the spec source of truth, and `Plans.md`
5. Return `APPROVE` / `REQUEST_CHANGES` / `decision_needed`
6. For `REQUEST_CHANGES`, specify the remediation approach for critical / major findings and the conditions for re-review after fixes

## Review Governance Contract

See `references/governance.md` for details.
Only the minimum acceptance bar is fixed here.

### Clear Acceptance Bar

Return `APPROVE` only when all of the following are satisfied:

- Zero critical / major findings
- No contradiction with the spec source of truth (`spec_path`) or an explicitly stated `spec_skip_reason`
- No contradiction with `Plans.md` task / DoD / Depends
- No evidence of regression in existing tests, existing UX, existing CLI, existing configuration, existing docs, or the distribution mirror
- Verification evidence exists. Outputting `APPROVE` with empty evidence is prohibited.
- If a TeamAgent Debate was run, all disagreements are either resolved or downgraded to `minor` / `recommendation` with justification

### TeamAgent Debate

See `references/team-debate.md` for details.
TeamAgent Debate is a read-only review pass that deliberately collides differing viewpoints.

| Agent | Primary question |
|---|---|
| Spec Agent | Find contradictions between the spec source of truth and the implementation diff |
| Plans Agent | Verify alignment between `Plans.md` task / DoD / Depends and the diff |
| Regression Agent | Detect regressions in existing behavior, tests, distribution mirror, CLI/skill UX |
| Skeptic Agent | Find major risks overlooked under the assumption that approval is desired |

Even when native TeamAgent is unavailable, this gate must not be skipped.
Reproduce the same 2–4 viewpoints using an available reviewer subagent or an explicitly separated read-only manual-pass, and record `native` / `manual-pass` / `unavailable` in `team_agent_mode`.

## Code Review Summary

See `references/code-review.md` for details.
A standard code review covers the following:

- Security
- Performance
- Quality
- Accessibility
- AI Residuals
- Spec Alignment
- Plans Alignment
- Regression Safety
- TDD compliance

Spec alignment check is mandatory.
When `spec_path` is present, verify the diff does not contradict the spec source of truth; when a spec is needed but absent, evaluate the validity of `spec_skip_reason`.
`Plans.md` alignment check and regression alignment check are handled at the same gate.

For `AI Residuals`, prefer using `scripts/review-ai-residuals.sh` and `scripts/review-weak-supervision-report.sh`.
Use `--include-untracked` when untracked files should also be inspected.
`mockData`, `dummy`, `fake`, `localhost`, `TODO`, `FIXME`, `it.skip`, `test.skip`, `expect(true).toBe(true)` are candidates; determine severity from diff context.
The finding stage prioritizes coverage. Even minor findings must be retained in `observations[]` / `recommendations[]`; gating happens only at the verdict stage (Opus 4.8 has a tendency to suppress low-severity reports — see Finding coverage in `references/code-review.md`).

### TDD compliance check

For tasks where TDD is required, verify evidence of `skip_tdd_reason`, a red log, and focused tests.
Do not `APPROVE` without evidence.

## Quick Summary

Principles for the lightweight path:

- Fix the target selection first
- The final report must include: review command / tests / accepted findings / rejected findings / clean result
- stop-on-clean: Do not add further reviews just for appearance after a clean result

The Reviewer agent (`chanpark-harness:reviewer`) runs the review and closeout — review
command, tests, accepted/rejected findings — and returns a `review-result.v1`.

## Plan Review Summary

See `references/plan-review.md` for details.
Plan Review examines the DoD / Depends / Status in `Plans.md` and the implementation order.
If a task requires a spec source of truth but `spec_path` is absent, stop with `decision_needed`.

## Scope Review Summary

See `references/scope-review.md` for details.
Scope Review checks whether the boundaries of requirements, diff, tests, and docs have expanded beyond what is needed.
If scope changes are required, do not proceed by guessing — return to `AskUserQuestion` or plan updates.

## Security / UI

- Security: `references/security-profile.md`
- UI rubric: `references/ui-rubric.md`
- high-res vision flow: `references/vision-high-res-flow.md`

`/ultrareview` is not called by default within the Harness flow.
This prevents replacing the connections to review-result.v1, commit guard, and sprint-contract in the Harness flow.
`claude ultrareview [target] --json` is treated only as a second-opinion from CI / scripts.

## PR Host Boundary

GitHub-first.
GitHub is the source of truth for review facts on the PR host; the local diff is treated as supplementary evidence.
Local uncommitted reviews are not pushed to GitHub.

## Output Contract

User-facing prose follows the explicit session or project language.
If no language is configured, use English. Use Japanese only when
`i18n.language: ja`, `CLAUDE_CODE_HARNESS_LANG=ja`, or an explicit session
instruction requests Japanese output.
Machine-readable values stay English.

Start with the result summary.

~~~markdown
## Review Result

### {APPROVE | REQUEST_CHANGES | decision_needed} - {one-line conclusion}

Target: `{BASE_REF}..HEAD` or `{target}`
Verification: {commands run}

Strengths:
- ...

Findings:
- [severity] file:line - issue and evidence

Next Actions:
- ...

Details:
```json
{
  "schema_version": "review-result.v1",
  "verdict": "APPROVE | REQUEST_CHANGES",
  "decision_needed": {
    "required": false,
    "ask_tool": "AskUserQuestion"
  },
  "accepted_findings": [],
  "rejected_findings": [],
  "acceptance_bar": {
    "critical_major_zero": true,
    "spec_alignment": "pass | fail | not_applicable",
    "plans_alignment": "pass | fail | not_applicable",
    "regression_safety": "pass | fail | not_applicable",
    "verification_evidence": "pass | fail | not_applicable"
  },
  "team_debate": {
    "required": false,
    "mode": "native | manual-pass | unavailable",
    "team_agent_mode": "native | manual-pass | unavailable",
    "agents": [],
    "disagreements": []
  },
  "critical_issues": [],
  "major_issues": [],
  "observations": [],
  "recommendations": []
}
```
~~~

## Tool Availability

The contracts for the acceptance bar, spec source of truth, `Plans.md`, regression checks, post-fix re-review, and AskUserQuestion / `decision_needed.v1` are always in effect.

| Tool | Fallback when unavailable |
|---|---|
| TeamAgent Debate via Task tool | reviewer subagent / manual-pass |
| AskUserQuestion | Output `decision_needed.v1` to stdout; do not proceed by guessing |
| TaskList | Read `Plans.md` directly |

## Related Skills

- `harness-work`: Execute fixes after `REQUEST_CHANGES`
- `harness-plan`: Update plan / scope / spec
- `harness-release`: Commit / release reviewed work
