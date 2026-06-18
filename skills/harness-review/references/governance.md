# Review Governance

## In a nutshell

Return `APPROVE` only when you can say with evidence that there are no critical problems.

## Clear Acceptance Bar

Conditions for `APPROVE`:

- Zero critical / major findings
- No contradiction with the spec source of truth (`spec_path`) or `spec_skip_reason`
- No contradiction with `Plans.md` task / DoD / Depends
- No evidence of regression in existing behavior, tests, UX, CLI, configuration, docs, or distribution mirror
- Evidence exists in the form of verification commands, diff, file:line, test results, etc.
- No unresolved TeamAgent Debate disagreements

## Severity

| severity | Meaning | Verdict |
|---|---|---|
| critical | Directly leads to secret exposure, data destruction, privilege destruction, or release failure | REQUEST_CHANGES |
| major | DoD not met, spec source of truth violation, clear regression, dangerous without test execution | REQUEST_CHANGES |
| minor | Quality would improve but not severe enough to block shipment | APPROVE allowed |
| recommendation | Optional improvement | APPROVE allowed |

If only minor / recommendation findings exist, do not necessarily block.
If blocking, explain concretely why it is major.

## AskUserQuestion / decision_needed

For decisions where guessing would cause breakage, use `decision_needed` rather than `REQUEST_CHANGES`.

Examples of `decision_needed`:

- The spec source of truth needs to be changed
- `Plans.md` DoD / Depends need to be changed
- The user needs to choose between security and UX priority
- A business decision is needed on whether to preserve or remove backward compatibility

Use AskUserQuestion when available.
In Codex environments or other cases where it is unavailable, output `decision_needed.v1` to stdout and do not proceed by guessing.

## Side effects

review default read-only boundary:

- Do not automatically commit even on `APPROVE`
- Do not push just to review
- commit / push / release are the responsibility of `harness-work` / `harness-release` / explicit user request

## Output evidence

Required:

- Target scope
- Review commands executed
- Tests executed
- Accepted findings
- Rejected findings
- Clean result or remaining issues
- Acceptance bar for spec source of truth / Plans.md / regression

`APPROVE` with empty evidence is invalid.
