---
name: harness-loop
description: "Long-running task loop using /loop (Claude Code dynamic mode) and ScheduleWakeup to re-enter with fresh context on each wake-up. Internally invokes harness-work through Agent. Trigger: long-running, loop, wake-up, autonomous. Do NOT load for: one-shot task execution, review, release, planning."
kind: workflow
purpose: "Re-enter long-running Plans.md execution with fresh context"
trigger: "long-running, loop, wake-up, autonomous"
shape: delegate
role: orchestrator
base: harness-work
pair: harness-sync
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Edit", "Bash", "Task", "ScheduleWakeup", "mcp__harness__harness_mem_resume_pack", "mcp__harness__harness_mem_record_checkpoint"]
argument-hint: "[all|N-M] [--max-cycles N] [--pacing worker|ci|plateau|night]"
user-invocable: true
---

# harness-loop

A meta-skill that combines `/loop` (CC dynamic mode) with `ScheduleWakeup` to
**re-enter long-running tasks with a fresh context on each wake-up**.

On each wake-up, it invokes `harness-work --breezing` via Agent,
forming a re-entrant loop where 1 cycle = 1 completed task.

> **Long-session helpers (CC 2.1.108+)**:
> When you return, run `/recap` to refresh the summary, then check `/harness-loop status`.
> For workflows with extended away periods or frequent re-entries, prefer `ENABLE_PROMPT_CACHING_1H=1`.

> **Long-session recommendation (CC 2.1.108+)**:
> If the session is expected to exceed 30 minutes, after resolving the plugin bundle root,
> run `bash "${HARNESS_PLUGIN_ROOT}/scripts/enable-1h-cache.sh"` to opt in to 1-hour prompt caching.

## Quick Reference

| Input | Behavior |
|-------|----------|
| `/harness-loop all` | Loop over all incomplete tasks (default: max 8 cycles) |
| `/harness-loop all --max-cycles 3` | Stop after 3 cycles |
| `/harness-loop 41.1-41.3 --pacing ci` | Run a task range with CI pacing |
| `/harness-loop all --plan roadmap` | Loop over the named plan `roadmap` |
| `/harness-loop all --pacing night` | Overnight batch (3600s interval) |
| `/harness-loop status` | Check the status of the running loop |
| `/harness-loop stop` | Request the running loop to stop |

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `all` | Target all incomplete tasks | - |
| `N-M` | Specify a task number range | - |
| `--plan NAME` | Use a named plan from `plans/manifest.json` | active/default |
| `--max-cycles N` | Maximum number of cycles | `8` |
| `--pacing <mode>` | Wake-up interval mode | `worker` (270s) |

### pacing Value Mapping

| pacing | delaySeconds | Use case |
|--------|-------------|----------|
| `worker` | 270 | Re-enter immediately after Worker completes (within 5 min cache warm) |
| `ci` | 270 | Wait for short-duration CI jobs |
| `plateau` | 1200 | 20 min (retry interval after plateau detection) |
| `night` | 3600 | Overnight long-running batch |

> **Constraint**: `ScheduleWakeup`'s `delaySeconds` is clamped at runtime to **[60, 3600]**.
> `worker` / `ci` at 270s and `night` at 3600s are within this range.
> `plateau` at 1200s is also within range. When specifying a value directly, always use 60 or above and 3600 or below.

## Launch Flow (Entry on Each Wake-up)

Full details: [`${CLAUDE_SKILL_DIR}/references/flow.md`](${CLAUDE_SKILL_DIR}/references/flow.md)

### plugin bundle root Resolution

`harness-loop` calls helper scripts from the plugin bundle root, not the host project's cwd.
Think of it as keeping the workbench (host project) and the toolbox (plugin bundle) separate.

At the start of each wake-up, `HARNESS_PLUGIN_ROOT` is determined in the following order:

1. If `CLAUDE_PLUGIN_ROOT` exists and contains `scripts/`, use it.
2. If `CLAUDE_PLUGIN_ROOT` is absent, derive the plugin bundle root from `CLAUDE_SKILL_DIR`:
   - For `skills/harness-loop` distribution: `${CLAUDE_SKILL_DIR}/../..`
   - For `.agents/skills/harness-loop` mirror distribution: `${CLAUDE_SKILL_DIR}/../../..`
3. If neither resolves, stop and re-run after setting `CLAUDE_PLUGIN_ROOT` to the plugin bundle root.

`Plans.md` and `.claude/state/...` reside on the host project side.
Only helper scripts are loaded from `${HARNESS_PLUGIN_ROOT}/scripts/...`.

In repos with multiple Plans.md files, specify `--plan NAME` explicitly when starting a long-running run.
The runner retains the Plans file resolved at startup across cycles; do not switch the active plan mid-run.

```
wake-up
  │
  ▼
[Step 0] Resolve plugin bundle root into HARNESS_PLUGIN_ROOT
  Use CLAUDE_PLUGIN_ROOT if valid
  Otherwise derive plugin bundle root from CLAUDE_SKILL_DIR
  Note: do NOT reference scripts/ in the host project cwd
  │
  ▼
[Step 1] Read Plans.md first
  Identify the leading cc:WIP / cc:TODO task (obtain task_id)
  Note: no incomplete tasks → loop ends (normal completion)
  │
  ▼
[Step 2] Check for sprint-contract & generate if missing
  Check for .claude/state/contracts/${task_id}.sprint-contract.json
  If absent, generate with: node "${HARNESS_PLUGIN_ROOT}/scripts/generate-sprint-contract.js" ${task_id}
  Immediately after generation (first time only): bash "${HARNESS_PLUGIN_ROOT}/scripts/enrich-sprint-contract.sh" <contract-path> \
    --check "Auto-approved on wake-up (DoD verified from reviewer perspective for harness-loop)" \
    --approve  ← promote draft → approved
  (Existing contracts are already approved — skip)
  │
  ▼
[Step 3] Contract readiness check
  bash "${HARNESS_PLUGIN_ROOT}/scripts/ensure-sprint-contract-ready.sh" <contract-path>
  │
  ▼
[Step 4] Reload resume pack
  harness-mem resume-pack (re-inject context)
  │
  ▼
[Step 4.5] Advisor consult (only when needed)
  Before first run of a high-risk task / after 2nd failure with same cause / just before plateau
  Compose an `advisor-request.v1` and consult
  │
  ├── PLAN        → prepend advice to the next executor prompt
  ├── CORRECTION  → re-run as a targeted correction instruction
  └── STOP        → stop the loop immediately and record the reason
  │
  ▼
[Step 5] Execute 1 task cycle
  worker_result = Agent(
      subagent_type="chanpark-harness:worker",  # worker agent (not harness-work)
      prompt="Task: ${task_id}\nDoD: <extracted from Plans.md>\ncontract_path: ${CONTRACT_PATH}\nmode: breezing",
      isolation="worktree",
      run_in_background=false
  )
  # worker_result: { commit, branch, worktreePath, files_changed, summary }
  │
  ▼
[Step 5.5] Lead review
  diff_text = git show worker_result.commit
  verdict = reviewer_agent_review(diff_text)
  See flow.md for details
  │
  ▼
[Step 5.6] APPROVE → cherry-pick to main / REQUEST_CHANGES → revision loop (max_iterations from contract, default 3)
  APPROVE: git cherry-pick → update Plans.md to cc:done [{hash}] → delete feature branch
  Still rejected after REQUEST_CHANGES x MAX_REVIEWS: escalate
  See flow.md for details
  │
  ▼
[Step 6] Plateau check
  bash "${HARNESS_PLUGIN_ROOT}/scripts/detect-review-plateau.sh" ${current_task_id}
  │
  ├── PIVOT_REQUIRED (exit 2)   → stop loop + user escalation
  ├── INSUFFICIENT_DATA (exit 1) → continue
  └── PIVOT_NOT_REQUIRED (exit 0) → continue
  │
  ▼
[Step 7] Cycle count check
  │
  ├── cycles >= max_cycles → stop loop (limit reached)
  │
  ▼
[Step 8] Record checkpoint
  harness_mem_record_checkpoint(
      session_id, title, content=cycle result summary
  )
  │
  ▼
[Step 9] Schedule next wake-up
  ScheduleWakeup(
      delaySeconds=<pacing value>,
      prompt="/harness-loop <same args>",
      reason="Cycle {N}/{max} complete — proceeding to next task"
  )
```

## Cycle Stop Conditions

| Condition | Stop Type | Response |
|-----------|-----------|----------|
| `cycles >= max_cycles` | Normal stop (limit reached) | Report to user |
| `PIVOT_REQUIRED` (exit 2) | Abnormal stop (escalation) | Ask user for decision |
| No incomplete tasks | Normal stop (all complete) | Output completion report |

When `--max-cycles 3` is specified, the loop stops after 3 completed cycles.
With the default (`--max-cycles 8`), it stops after 8 cycles.

## Progress Reports / Silence Policy

In a long-running loop, interim reports are treated as "notifications when a decision changes," not as heartbeats for reassurance.
Remain explicitly silent when nothing needs to be said.

Report when:

- A cycle completes, the limit is reached, all tasks are done, or the loop is blocked
- Validation failure, review `REQUEST_CHANGES`, plateau detection, or advisor `STOP`
- Advisor / reviewer drift, or contract readiness failure
- The user requests a `status` summary

Remain silent when:

- Only transcript deltas have accumulated with no change in task / review / advisor state
- Only minor stdout has been added to the log
- Waiting in pacing interval before the next wake-up

Default behavior is "one final report per cycle."
However, an unanswered Advisor request, a pending Reviewer result, or a pre-plateau warning take priority over the silence policy.

## Integration with /loop

This skill is used in combination with CC's `/loop` (dynamic mode).

When `/loop` is enabled, CC continues autonomous re-entry execution,
and at the end of each cycle, `ScheduleWakeup` is called to schedule the next wake-up.

`/loop` sentinel: `<<autonomous-loop-dynamic>>`

Each wake-up starts with a **fresh context**, preventing context contamination from previous cycles.
Reloading the resume pack via `harness-mem resume-pack` is mandatory (Step 4).

## Checkpoint Recording

`harness_mem_record_checkpoint` schema:

```json
{
  "session_id": "<session ID>",
  "title": "harness-loop cycle {N}/{max}: {task name}",
  "content": "one-line summary of cycle_result + commit hash"
}
```

## Advisor Strategy

The executor is the primary actor in this skill; the advisor is called only when needed.
Think of it as the assignee working independently most of the time and consulting a senior only at difficult points.

Consultation conditions are fixed; natural-language "low confidence" judgments are not used.

| Condition | Consult? |
|-----------|----------|
| `needs-spike` / `security-sensitive` / `state-migration` | Yes |
| `<!-- advisor:required -->` | Yes |
| 2nd failure with the same cause | Yes |
| Just before stopping due to plateau | Yes |

The same trigger is consulted only once.
This is determined using `trigger_hash = task_id + reason_code + normalized_error_signature`.

## Related Skills

- `harness-work` — task implementation skill executed on each cycle
- `harness-plan` — planning for tasks targeted by the loop
- `harness-review` — review of individual tasks
- `session-control` — session state management
