# Dual Review (--dual) / Triple Review (--cursor opt-in)

Run Claude Reviewer and Codex Reviewer in parallel to improve review quality through different model perspectives.
`--dual` is not merely a double-check; it combines TeamAgent Debate when needed to
eliminate gaps against the spec source of truth, Plans.md, and regression checks from multiple viewpoints.

Using the `--cursor` flag alongside (or `--dual --cursor` for a triple review) allows cursor (composer-2.5-fast)
to run as **second-opinion only**. See `references/cursor-review.md` for details.

## Prerequisites

- Codex CLI is installed (verify with `scripts/codex-companion.sh setup --json`)
- If Codex is unavailable, fall back to Claude-only review
- When using `--cursor`, cursor-agent must be installed (`setup-cursor.sh --check`). If unavailable, degrade with `cursor_verdict: unavailable`

## Execution Flow

1. Check Codex availability

   ```bash
   CODEX_AVAILABLE="$(bash scripts/codex-companion.sh setup --json 2>/dev/null | jq -r '.ready // false')"
   ```

2. Launch Claude Reviewer via Task tool (normal review flow)

3. If Codex is available, launch `scripts/codex-companion.sh review` in parallel

   ```bash
   # Specify --base when BASE_REF is provided. Use --json to get structured output
   bash scripts/codex-companion.sh review --base "${BASE_REF:-HEAD~1}" --json
   ```

4. Wait for both results

5. Run TeamAgent Debate if any of the following apply:
   - Claude and Codex verdicts diverge
   - There is a mismatch or unconfirmed item in the spec source of truth, Plans.md, or regression checks
   - There is at least one `critical` / `major` candidate
   - `--team-debate` is specified

6. Fix the acceptance bar before merging verdicts

## TeamAgent Debate

TeamAgent Debate is treated as a read-only review pass that deliberately collides differing viewpoints.

| Agent | Primary question |
|-------|----------|
| Spec Agent | Does the spec source of truth contradict the implementation? |
| Plans Agent | Do `Plans.md` task / DoD / Depends align with the evidence trail? |
| Regression Agent | Are there regressions in existing behavior, tests, distribution mirror, CLI/skill UX? |
| Skeptic Agent | What major risks are being overlooked under the assumption that approval is desired? |

Use the Task tool in Claude Code.
In Codex environments where native TeamAgent may not be available,
reproduce the same perspectives using a Codex reviewer subagent, `codex-companion.sh review`, or an explicitly separated manual-pass,
and record the result in `team_agent_mode`.

## Acceptance Bar

The final `APPROVE` requires all of the following:

- Zero `critical` / `major` findings
- No contradiction with the spec source of truth or `spec_skip_reason`
- No contradiction with `Plans.md` task / DoD / Depends
- No evidence of regression in existing behavior, tests, distribution mirror, CLI/skill UX
- All Claude / Codex / TeamAgent disagreements are resolved or downgraded to `minor` / `recommendation` with justification

## Verdict Merge Rules

Evaluate in the following order:

   - Both APPROVE → `APPROVE`
   - Either is REQUEST_CHANGES → `REQUEST_CHANGES` (adopt the stricter one)
   - TeamAgent Debate leaves a disagreement equivalent to `critical` / `major` → `REQUEST_CHANGES`
   - spec source of truth / Plans.md / regression gate fails → `REQUEST_CHANGES`
   - `critical_issues`: merge both lists (no deduplication)
   - `major_issues`: merge both lists (no deduplication)
   - `recommendations`: merge with deduplication

## Output Format

Add a `dual_review` field to the standard `review-result.v1` schema:

```json
{
  "schema_version": "review-result.v1",
  "verdict": "APPROVE | REQUEST_CHANGES",
  "dual_review": {
    "claude_verdict": "APPROVE | REQUEST_CHANGES",
    "codex_verdict": "APPROVE | REQUEST_CHANGES | unavailable | timeout",
    "merged_verdict": "APPROVE | REQUEST_CHANGES",
    "divergence_notes": "Reason when verdicts diverge. Example: Claude detected a major Performance issue; Codex found no problem"
  },
  "acceptance_bar": {
    "critical_major_zero": true,
    "spec_alignment": "pass | fail | not_applicable",
    "plans_alignment": "pass | fail | not_applicable",
    "regression_safety": "pass | fail | not_applicable",
    "verification_evidence": "pass | fail | not_applicable"
  },
  "team_debate": {
    "required": true,
    "mode": "native | codex-companion | manual-pass | unavailable",
    "agents": ["Spec Agent", "Plans Agent", "Regression Agent"],
    "disagreements": []
  },
  "critical_issues": [],
  "major_issues": [],
  "observations": [],
  "recommendations": []
}
```

### Special values for `codex_verdict`

| Value | Meaning |
|----|------|
| `"unavailable"` | Codex CLI is not installed or unavailable |
| `"timeout"` | Codex review timed out (no response within 120 seconds) |

## Fallback

- **Codex unavailable**: Run Claude alone and record `codex_verdict: "unavailable"`
- **Codex timeout**: Adopt Claude's verdict as-is and record `codex_verdict: "timeout"`
- **Codex output malformed**: Treat as a parse failure and record `codex_verdict: "unavailable"`
- **TeamAgent unavailable**: Record `team_debate.mode: "unavailable"` and the reason; perform at minimum a manual-pass covering Spec / Plans / Regression

Even when Codex is unavailable or timed out, do not skip the acceptance bar for spec source of truth, Plans.md, and regression checks.
If TeamAgent is unavailable and a manual-pass is also impossible, stop with `decision_needed` rather than `REQUEST_CHANGES`.

## Writing Divergence Notes

When verdicts match (`claude_verdict == codex_verdict`), set `divergence_notes` to an empty string.

When verdicts diverge, record in the following format:

```
Claude: REQUEST_CHANGES (Security - SQL injection risk)
Codex: APPROVE (determined no issue at the same location)
Adopted: REQUEST_CHANGES (stricter verdict takes priority)
```
