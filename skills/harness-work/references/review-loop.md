# Review Loop

The review loop is shared by Solo, Parallel, and Breezing.

## Order

1. Spawn the internal `reviewer` agent with the diff.
2. Run AI Residuals with:

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/review-ai-residuals.sh" --base-ref "${BASE_REF}" --include-untracked
```

3. Normalize the review artifact with `write-review-result.sh`.

## Verdict Threshold

| Severity | Verdict effect |
|---|---|
| `critical` | Any finding means `REQUEST_CHANGES` |
| `major` | Any finding means `REQUEST_CHANGES` |
| `minor` | Does not change verdict |
| `recommendation` | Does not change verdict |

Minor-only and recommendation-only reviews must approve.

## Repair Loop

Repeat fix and review until either:

- verdict becomes `APPROVE`
- `review.max_iterations` from the sprint contract is reached
- default maximum of 3 reviews is reached

Breezing repair instructions go back to the same Worker via `SendMessage`.
