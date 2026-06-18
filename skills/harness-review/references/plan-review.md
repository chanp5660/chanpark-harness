# Plan Review

## In a nutshell

Plan Review checks whether `Plans.md` is written at the right granularity and in the right order for implementation.

## Checkpoints

- Each task represents a single unit of completion
- DoD is verifiable
- Depends relationships are not circular
- Status matches reality
- Tasks requiring a spec source of truth have `spec_path` or a task to create one
- The implementation order does not defer high-risk parts unnecessarily
- review / release / mirror / docs closeout steps are not missing

## Verdict

| State | Verdict |
|---|---|
| DoD is measurable, Depends are valid, scope is clear | APPROVE |
| DoD is vague, dependencies are broken, spec required but missing | REQUEST_CHANGES |
| Scope must be changed without a user decision | decision_needed |

## Output

In Plan Review, prioritize file:line references.
Base findings on the relevant lines in `Plans.md`, docs, and the spec source of truth.
