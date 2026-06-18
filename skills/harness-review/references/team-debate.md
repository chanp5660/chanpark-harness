# TeamAgent Debate

## In a nutshell

TeamAgent Debate is a read-only review pass where separate perspectives read the same change to reduce oversights.

## When required

Run when any of the following apply:

- The change spans multiple modules
- The change touches security / auth / release / distribution / mirror
- Alignment with the spec source of truth or `Plans.md` is unclear
- Regression risk is high
- Per-perspective evaluation diverges within the reviewer
- The same issue has been failed on re-review twice in a row

## Agents

| Agent | Primary question |
|---|---|
| Spec Agent | Find contradictions between the spec source of truth and the implementation diff |
| Plans Agent | Verify alignment between `Plans.md` task / DoD / Depends and the diff |
| Regression Agent | Detect regressions in existing behavior, tests, distribution mirror, CLI/skill UX |
| Skeptic Agent | Find major risks overlooked under the assumption that approval is desired |

Minimum 2 perspectives, up to 4 when needed.
All agents are read-only.

## Fallback

Do not skip this step even when native TeamAgent is unavailable.

Available fallbacks:

- reviewer subagent
- explicitly separated manual-pass

Record one of the following in `team_agent_mode`:

- `native`
- `manual-pass`
- `unavailable`

When `unavailable` and a manual-pass is also impossible, stop with `decision_needed`.

## Output

```json
{
  "team_debate": {
    "required": true,
    "mode": "native | manual-pass | unavailable",
    "team_agent_mode": "native | manual-pass | unavailable",
    "agents": ["Spec Agent", "Plans Agent", "Regression Agent"],
    "disagreements": [],
    "acceptance_bar": {
      "spec_alignment": "pass",
      "plans_alignment": "pass",
      "regression_safety": "pass"
    }
  }
}
```

## Acceptance Bar

If a TeamAgent Debate disagreement is equivalent to critical / major, issue `REQUEST_CHANGES`.
When downgrading to minor / recommendation, write the reason with supporting evidence.
