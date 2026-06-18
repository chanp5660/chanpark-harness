# Scope Review

## In a nutshell

Scope Review checks whether anything that should be done is missing and whether anything beyond what is needed has been done.

## Checkpoints

- The user request and the diff match
- The task's DoD is satisfied
- No unrelated refactoring is mixed in
- The required scope of docs / tests / mirror / changelog is complete
- Any increase in public surface area has been confirmed
- Migration / release / permission boundaries have not been changed unilaterally

## Scope creep

Scope creep is "the work scope expanding beyond what is needed."
For example, starting to modify a release script during a docs-fix task is dangerous.

When scope creep is found, split it into one of the following:

- Needed for the current DoD: document explicitly in the plan and proceed
- Not needed for the current DoD: extract into a separate task

## Verdict

| State | Verdict |
|---|---|
| Request and diff match | APPROVE |
| DoD not met or unneeded changes mixed in | REQUEST_CHANGES |
| Business decision needed for scope change | decision_needed |
