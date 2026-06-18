---
name: state-transition
description: "Execute session state transitions using session-state.sh"
allowed-tools: [Read, Bash]
---

# State Transition

Executes transitions between session states.

## Input

Workflow variables:
- `target_state` (string): The target state to transition to
- `event_name` (string): The triggering event
- `event_data` (string, optional): Additional event data (JSON)

## Valid States

| State | Description |
|-------|-------------|
| `idle` | Session not yet started |
| `initialized` | SessionStart completed |
| `planning` | Preparing for Plan/Work |
| `executing` | /work is running |
| `reviewing` | review is running |
| `verifying` | build/test is running |
| `escalated` | Awaiting human confirmation |
| `completed` | Output finalized |
| `failed` | Unrecoverable error |
| `stopped` | Stop hook reached |

## Representative Transitions

| From | Event | To |
|------|-------|----|
| idle | session.start | initialized |
| initialized | plan.ready | planning |
| planning | work.start | executing |
| executing | work.task_complete | reviewing |
| reviewing | verify.start | verifying |
| verifying | verify.passed | completed |
| verifying | verify.failed | escalated |
| * | session.stop | stopped |
| stopped | session.resume | initialized |

## Execution

```bash
./scripts/session-state.sh --state <state> --event <event> [--data <json>]
```

### Example: Transition to executing state

```bash
./scripts/session-state.sh --state executing --event work.start
```

### Example: Escalation (with data)

```bash
./scripts/session-state.sh --state escalated --event escalation.requested \
  --data '{"reason":"Build failed 3 times","retry_count":3}'
```

## Expected Results

- `state`, `updated_at`, `last_event_id`, and `event_seq` in `.claude/state/session.json` are updated
- The event is appended to `.claude/state/session.events.jsonl`
- Invalid transitions output an error to stderr and exit with a non-zero code

## Error Handling

If a transition fails (e.g., invalid transition):
1. Output the current state and allowed transitions to stderr
2. Return a non-zero exit code
3. The caller (workflow) handles escalation
