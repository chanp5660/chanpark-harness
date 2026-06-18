# harness-loop: Wake-up Flow Details

Detailed entry procedure for each `harness-loop` wake-up.
An implementation reference that supplements the summary in SKILL.md.

---

## Entry Procedure on Each Wake-up (Detailed)

### Step 0: plugin bundle root Resolution

`harness-loop` calls helper scripts from the plugin bundle root, not the host project's cwd.
`Plans.md` and `.claude/state/...` remain on the host project side; only the scripts (the tools) are loaded from the plugin bundle.

```bash
resolve_harness_plugin_root() {
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/scripts" ]; then
        (cd "${CLAUDE_PLUGIN_ROOT}" && pwd -P)
        return 0
    fi

    if [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
        for candidate in "${CLAUDE_SKILL_DIR}/../.." "${CLAUDE_SKILL_DIR}/../../.."; do
            candidate_abs="$(cd "${candidate}" 2>/dev/null && pwd -P)" || continue
            if [ -f "${candidate_abs}/.claude-plugin/plugin.json" ] && [ -d "${candidate_abs}/scripts" ]; then
                printf '%s\n' "${candidate_abs}"
                return 0
            fi
        done
    fi

    echo "ERROR: cannot resolve Claude Harness plugin root. Set CLAUDE_PLUGIN_ROOT to the installed plugin bundle root." >&2
    return 1
}

HARNESS_PLUGIN_ROOT="$(resolve_harness_plugin_root)" || exit 1
```

- Use `CLAUDE_PLUGIN_ROOT` with highest priority if valid
- If `CLAUDE_PLUGIN_ROOT` is absent, derive the distribution source from `CLAUDE_SKILL_DIR`:
  - For `skills/harness-loop` distribution: `${CLAUDE_SKILL_DIR}/../..`
  - For `.agents/skills/harness-loop` mirror distribution: `${CLAUDE_SKILL_DIR}/../../..`
- Only treat candidates containing both `scripts/` and `.claude-plugin/plugin.json` as the plugin root
- Do not use `scripts/` from the host project cwd

### Step 0.1: Concurrent Launch Prevention Lock (Idempotency Guard (a))

```bash
LOCK_DIR=".claude/state/locks/loop-session.lock.d"
mkdir -p ".claude/state/locks"

# Atomic creation (fail immediately if already exists — avoids TOCTOU race)
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    existing=$(cat "${LOCK_DIR}/meta.json" 2>/dev/null || echo '{}')
    echo "ERROR: harness-loop is already running (lock dir exists: ${LOCK_DIR})" >&2
    echo "Lock contents: ${existing}" >&2
    echo "To force-clear, run: rm -rf ${LOCK_DIR}" >&2
    exit 10
fi

# Write lock metadata inside the lock directory
SESSION_ID="${CLAUDE_SESSION_ID:-unknown}"
ARGS_STR="$*"
cat > "${LOCK_DIR}/meta.json" <<EOF
{
  "pid": $$,
  "session_id": "${SESSION_ID}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "args": "${ARGS_STR}"
}
EOF

# Delete lock on exit (both normal and abnormal)
cleanup_loop_lock() {
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
}
trap cleanup_loop_lock EXIT INT TERM
```

- `LOCK_DIR` is `.claude/state/locks/loop-session.lock.d` (a directory)
- `mkdir` is atomic, so no TOCTOU race occurs (if two processes run simultaneously, only one succeeds)
- Lock metadata is written to `${LOCK_DIR}/meta.json` as JSON: `{"pid": <pid>, "session_id": <session>, "started_at": <ISO8601>, "args": "<args>"}`
- If a lock already exists, stop immediately with an `already running` error (exit 10)
- Lock is deleted on `EXIT` / `INT` / `TERM` — cleanup regardless of normal or abnormal exit
- `rm -rf` is idempotent (safe to delete twice)

### Step 0.5: State Consistency Check (Idempotency Guard (b))

```bash
# Run a lightweight consistency check in --quick mode at the start of wake-up
# If it fails, stop the loop immediately (guards against corrupted Plans.md or uninitialized environment)
if bash "${HARNESS_PLUGIN_ROOT}/tests/validate-plugin.sh" --quick; then
    : # OK — continue
else
    echo "harness-loop: state consistency check failed — stopping loop" >&2
    echo "Details: run bash \"${HARNESS_PLUGIN_ROOT}/tests/validate-plugin.sh\" --quick to investigate" >&2
    exit 1
fi
```

- `${HARNESS_PLUGIN_ROOT}/tests/validate-plugin.sh --quick` is lightweight and completes within a few seconds
- Checks: existence of `.claude/state/` / existence + v2 format of Plans.md / sprint-contract format
- The full validate (39 verification items) is not run
- If this check fails due to an intentionally corrupted Plans.md, the loop stops immediately

### Step 1: Read Plans.md First

```bash
# Extract cc:WIP / cc:TODO tasks and identify the leading task's task_id
grep -E "cc:(WIP|TODO)" Plans.md | head -1
```

- If a `cc:WIP` task remains: possibly interrupted in the previous cycle → obtain task_id and continue
- If a `cc:TODO` task exists: obtain task_id as the next target task
- If neither: **all tasks complete** → loop ends normally

> **41.1.2 prerequisite**: If `plans-watcher.sh` protects Plans.md with flock,
> read Plans.md within that flock scope.
> Before the 41.1.2 release, direct reads without flock are acceptable.

### Step 2: Check for sprint-contract & Generate if Missing

```bash
CONTRACT_PATH=".claude/state/contracts/${task_id}.sprint-contract.json"

if [ ! -f "${CONTRACT_PATH}" ]; then
    # Contract not yet generated → generate it
    node "${HARNESS_PLUGIN_ROOT}/scripts/generate-sprint-contract.js" "${task_id}"

    # Step 2.5: Promote draft → approved (first generation only)
    # generate-sprint-contract.js initializes with review.status == "draft",
    # so promotion must happen before ensure-sprint-contract-ready.sh (which requires "approved")
    bash "${HARNESS_PLUGIN_ROOT}/scripts/enrich-sprint-contract.sh" "${CONTRACT_PATH}" \
      --check "Auto-approved on wake-up (DoD verified from reviewer perspective for harness-loop)" \
      --approve
fi
```

- Check for `.claude/state/contracts/${task_id}.sprint-contract.json`
- If absent, generate with `node "${HARNESS_PLUGIN_ROOT}/scripts/generate-sprint-contract.js" ${task_id}`
  (Note: planned rename from .sh→.js in 41.5.1; for now call the existing name via node)
- **Immediately after generation (first time only)**: promote `draft` → `approved` with `enrich-sprint-contract.sh --approve`
  - `generate-sprint-contract.js` initializes with `review.status == "draft"`
  - `ensure-sprint-contract-ready.sh` (next Step 3) only accepts `approved`
  - Placing this inside the `if [ ! -f ... ]` block ensures existing contracts (already approved in previous cycles) are unaffected
- After generation, reuse `${CONTRACT_PATH}` in subsequent steps

### Step 3: Contract Readiness Check

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/ensure-sprint-contract-ready.sh" "${CONTRACT_PATH}"
```

- Confirm `review.status == "approved"` in the sprint-contract
- Stop with an error if an unapproved contract remains

### Step 4: Reload Resume Pack

```
Step 4. harness-mem resume-pack reload:
  Call the mcp__harness__harness_mem_resume_pack tool.
  Required arguments:
    - project: the current project name (follow the implementation example in the existing session-init skill.
              Example: get the repository root with `basename $(git rev-parse --show-toplevel)` and pass it)
  optional: session_id (when resuming from a previous session)

  Example (pseudocode):
    resume_pack = mcp__harness__harness_mem_resume_pack(
      project="claude-code-harness",
      session_id=<session_id from the previous checkpoint>
    )
```

Immediately after waking up with a fresh context, memory from the previous cycle is gone.
Re-inject the following via the `harness-mem resume-pack` equivalent:

- `decisions.md` — architecture decisions
- `patterns.md` — reusable patterns
- `session-state` — the previous work state
- The most recent cycle's `checkpoint` — what was completed

> **Note**: Reload the resume pack after Step 3 (contract readiness check).
> Skipping this risks re-implementing artifacts from the previous cycle.

### Step 4.5: Advisor Consult (Only When Needed)

The loop is executor-driven; the advisor is called only when needed.
Consultation timing is fixed at the following 3 points:

1. Before the first run of a high-risk task
2. After 2 consecutive failures with the same cause
3. Just before stopping due to `PIVOT_REQUIRED`

```bash
TRIGGER_HASH="${task_id}:${reason_code}:$(normalize_error_signature "${summary_or_risk}")"

if ! advisor_trigger_seen "${TRIGGER_HASH}"; then
    RESPONSE_FILE=$(
        bash "${HARNESS_PLUGIN_ROOT}/scripts/run-advisor-consultation.sh" \
          --request-file ".claude/state/codex-loop/${task_id}.${reason_code}.advisor-request.json" \
          --response-file ".claude/state/codex-loop/${task_id}.${reason_code}.advisor-response.json"
    )
    DECISION=$(jq -r '.decision' "${RESPONSE_FILE}")
fi
```

- `PLAN` / `CORRECTION`: prepend advice to the next executor prompt and re-run
- `STOP`: stop the loop and record in `run.json` under `last_decision`, `last_trigger`, `last_model`
- The same `trigger_hash` is consulted only once
- Maximum 3 consultations per task

### Step 5: Execute 1 Task Cycle

Spawn `chanpark-harness:worker` via the Agent tool:

> **Important**: Specify `"chanpark-harness:worker"` for `subagent_type`, not `"harness-work"`.
> `harness-work` is a skill, not an agent. The existing agents are `worker` / `reviewer`.
> Specifying `"harness-work"` will cause Agent spawn to fail, stopping the loop on the first Worker launch.

```python
worker_result = Agent(
    subagent_type="chanpark-harness:worker",  # ← worker agent (not a skill)
    prompt="""
    Task: ${task_id}
    DoD: <extracted from Plans.md>
    contract_path: ${CONTRACT_PATH}
    mode: breezing
    After completion: return the commit hash, branch, and change summary.
    """,
    isolation="worktree",
    run_in_background=false  # foreground execution (wait until complete)
)
# worker_result: { commit, branch, worktreePath, files_changed, summary }
```

Because Worker operates in `mode: breezing`:
- It only commits on the feature branch and does not touch main
- Changes are stored in `worktreePath`
- Lead (harness-loop) handles review → cherry-pick in Steps 5.5/5.6

> **Codex loop implementation difference**: In the Codex version, `${HARNESS_PLUGIN_ROOT}/scripts/codex-loop.sh` launches a background task
> and prepends advisor-returned guidance to the next prompt to re-run the same task.

> **Implementation note**: `Bash("harness-work --breezing")` can also serve as an alternative,
> but using the Agent tool provides cleaner context isolation and is easier to debug.

### Step 5.5: Lead Review Execution

Lead performs a review on the commit returned by Worker:

```bash
# Get diff (targeting the commit inside the worktree)
diff_text=$(git -C "${worker_result.worktreePath}" show "${worker_result.commit}")

# ── (a) Codex companion review: run in Worker's worktree directory ──────────────
# If Lead is in the main repo dir, diff will be empty (risk of unconditional APPROVE).
# By cd-ing into Worker's worktreePath before calling review, the correct diff is passed.
#
# If worktreePath is empty or identical to the main repo (environment where worktree isolation doesn't work),
# run in Lead dir (fallback equivalent to existing behavior).

MAIN_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
WORKER_PATH="${worker_result.worktreePath:-}"

if [ -n "${WORKER_PATH}" ] && [ "${WORKER_PATH}" != "${MAIN_REPO_ROOT}" ]; then
    # Run review inside Worker's worktree → see the actual diff on the Worker feature branch
    ( cd "${WORKER_PATH}" && bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" review --base "${BASE_REF}" )
    REVIEW_EXIT=$?
    # review-output.json is created in the Worker worktree dir, so manage it as an absolute path
    REVIEW_OUTPUT_PATH="${WORKER_PATH}/review-output.json"
else
    # Fallback: run in Lead dir (environment where worktree isolation doesn't work)
    bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" review --base "${BASE_REF}"
    REVIEW_EXIT=$?
    REVIEW_OUTPUT_PATH="$(pwd)/review-output.json"
fi
# → verdict is written to the file indicated by REVIEW_OUTPUT_PATH
# All subsequent steps must use $REVIEW_OUTPUT_PATH (do not directly reference the relative path "review-output.json")

# ── (b) reviewer_profile branch (check review.reviewer_profile in sprint-contract) ──
# Use the CONTRACT_PATH value already resolved in Steps 2/3 as-is (do not overwrite here)
if command -v jq >/dev/null 2>&1; then
    REVIEWER_PROFILE=$(jq -r '.review.reviewer_profile // "static"' "${CONTRACT_PATH}" 2>/dev/null || echo "static")
else
    REVIEWER_PROFILE="static"
fi

case "${REVIEWER_PROFILE}" in
    runtime)
        # Run runtime verification commands, which may override the verdict
        # run-contract-review-checks.sh runs inside Worker's worktree (because the test environment is inside the worktree)
        # Important: stdout of run-contract-review-checks.sh is the artifact "file path" (not a JSON payload)
        if [ -n "${WORKER_PATH}" ] && [ "${WORKER_PATH}" != "${MAIN_REPO_ROOT}" ]; then
            RUNTIME_ARTIFACT_PATH=$(
                cd "${WORKER_PATH}" && bash "${HARNESS_PLUGIN_ROOT}/scripts/run-contract-review-checks.sh" "${CONTRACT_PATH}" 2>/dev/null
            ) || RUNTIME_ARTIFACT_PATH=""
        else
            RUNTIME_ARTIFACT_PATH=$(
                bash "${HARNESS_PLUGIN_ROOT}/scripts/run-contract-review-checks.sh" "${CONTRACT_PATH}" 2>/dev/null
            ) || RUNTIME_ARTIFACT_PATH=""
        fi

        # If empty (script failed), treat as DOWNGRADE_TO_STATIC
        if [ -z "${RUNTIME_ARTIFACT_PATH}" ]; then
            RUNTIME_ARTIFACT_PATH=""
            RUNTIME_VERDICT="DOWNGRADE_TO_STATIC"
        else
            # If a relative path, convert to absolute using WORKER_PATH (or Lead dir) as the base
            if [[ "${RUNTIME_ARTIFACT_PATH}" != /* ]]; then
                if [ -n "${WORKER_PATH}" ] && [ "${WORKER_PATH}" != "${MAIN_REPO_ROOT}" ]; then
                    RUNTIME_ARTIFACT_PATH="${WORKER_PATH}/${RUNTIME_ARTIFACT_PATH}"
                else
                    RUNTIME_ARTIFACT_PATH="$(pwd)/${RUNTIME_ARTIFACT_PATH}"
                fi
            fi

            # Read verdict from the artifact file
            if command -v jq >/dev/null 2>&1; then
                RUNTIME_VERDICT=$(jq -r '.verdict // "DOWNGRADE_TO_STATIC"' "${RUNTIME_ARTIFACT_PATH}" 2>/dev/null || echo "DOWNGRADE_TO_STATIC")
            else
                RUNTIME_VERDICT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('verdict','DOWNGRADE_TO_STATIC'))" "${RUNTIME_ARTIFACT_PATH}" 2>/dev/null || echo "DOWNGRADE_TO_STATIC")
            fi
        fi

        if [ "${RUNTIME_VERDICT}" = "REQUEST_CHANGES" ]; then
            # Runtime verification failed → override verdict with REQUEST_CHANGES
            # Pass runtime artifact to write-review-result.sh (do not use static review-output.json)
            EFFECTIVE_VERDICT="REQUEST_CHANGES"
            REVIEW_RESULT_INPUT="${RUNTIME_ARTIFACT_PATH}"
        elif [ "${RUNTIME_VERDICT}" = "DOWNGRADE_TO_STATIC" ]; then
            # No runtime verification command → use static verdict as-is
            EFFECTIVE_VERDICT=""  # → read from REVIEW_OUTPUT_PATH
            REVIEW_RESULT_INPUT="${REVIEW_OUTPUT_PATH}"
        else
            EFFECTIVE_VERDICT="${RUNTIME_VERDICT}"
            REVIEW_RESULT_INPUT="${RUNTIME_ARTIFACT_PATH}"
        fi
        ;;
    browser)
        # Generate artifact for use by the browser reviewer
        # Browser artifact is a PENDING_BROWSER scaffold. Actual browser execution is handled by the reviewer agent.
        # The verdict in review-result remains static (not PENDING_BROWSER).
        bash "${HARNESS_PLUGIN_ROOT}/scripts/generate-browser-review-artifact.sh" "${CONTRACT_PATH}" 2>/dev/null || true
        EFFECTIVE_VERDICT=""  # → read from REVIEW_OUTPUT_PATH (use static verdict)
        REVIEW_RESULT_INPUT="${REVIEW_OUTPUT_PATH}"
        ;;
    *)
        # static (default): use verdict from Codex companion review as-is
        EFFECTIVE_VERDICT=""
        REVIEW_RESULT_INPUT="${REVIEW_OUTPUT_PATH}"
        ;;
esac

# If EFFECTIVE_VERDICT is not set, read from REVIEW_OUTPUT_PATH (absolute path)
if [ -z "${EFFECTIVE_VERDICT}" ]; then
    if command -v jq >/dev/null 2>&1; then
        EFFECTIVE_VERDICT=$(jq -r '.verdict // "REQUEST_CHANGES"' "${REVIEW_OUTPUT_PATH}" 2>/dev/null || echo "REQUEST_CHANGES")
    else
        EFFECTIVE_VERDICT=$(python3 -c "import json,sys; d=json.load(open(sys.argv[1])); print(d.get('verdict','REQUEST_CHANGES'))" "${REVIEW_OUTPUT_PATH}" 2>/dev/null || echo "REQUEST_CHANGES")
    fi
fi

# Normalize and save review-result
# REVIEW_RESULT_INPUT is the runtime artifact path when runtime REQUEST_CHANGES, otherwise REVIEW_OUTPUT_PATH
# This ensures runtime REQUEST_CHANGES is correctly propagated to pretooluse-guard (addresses issue 4)
bash "${HARNESS_PLUGIN_ROOT}/scripts/write-review-result.sh" "${REVIEW_RESULT_INPUT}" "${worker_result.commit}"
```

**Verdict determination**:

| verdict | Action |
|---------|--------|
| `APPROVE` | Proceed to Step 5.6 (cherry-pick) |
| `REQUEST_CHANGES` | Enter revision loop (up to 3 times) |

**Revision loop (on REQUEST_CHANGES)**:

```python
review_count = 0
latest_commit = worker_result.commit
worker_id = worker_result.agentId
# Read max_iterations only when sprint-contract exists. Default to 3 for backward compatibility.
MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3

while verdict == "REQUEST_CHANGES" and review_count < MAX_REVIEWS:
    # Instruct Worker to revise (resume via SendMessage)
    SendMessage(to=worker_id, message=f"Review comments: {issues}\nPlease revise and amend.")
    updated_result = wait_for_response(worker_id)
    latest_commit = updated_result.commit
    diff_text = git("-C", worker_result.worktreePath, "show", latest_commit)
    verdict = codex_exec_review(diff_text) or reviewer_agent_review(diff_text)
    review_count += 1

if review_count >= MAX_REVIEWS and verdict != "APPROVE":
    # Escalate
    raise PivotRequired(f"Still REQUEST_CHANGES after {MAX_REVIEWS} revisions: {issues}")
```

### Step 5.6: APPROVE → Cherry-pick to main

```bash
# Return to trunk branch (Worker works on feature branch)
TRUNK=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
git checkout "${TRUNK}"

# Confirm the feature branch commit is not yet merged into trunk (prevent re-entry)
if ! git merge-base --is-ancestor "${latest_commit}" HEAD; then
    git cherry-pick --no-commit "${latest_commit}"
    git commit -m "${task_title}"
fi

# ── (c) cleanup order: worktree remove → branch -D ────────────────────────────────
# While the feature branch is checked out in a worktree,
# `git branch -D` gives "branch is checked out at <path>" error.
# Running worktree remove first allows branch -D to work safely.
#
# Order:
#   1. cherry-pick → incorporated into main (git commit done above)
#   2. worktree remove (delete the worktree where the feature branch was checked out)
#   3. branch -D (now safe to delete since the worktree has been removed)

MAIN_REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
WORKER_PATH="${worker_result.worktreePath:-}"

# Step 2: worktree remove
if [ -n "${WORKER_PATH}" ] && [ "${WORKER_PATH}" != "${MAIN_REPO_ROOT}" ]; then
    git worktree remove "${WORKER_PATH}" --force 2>/dev/null || true
fi

# Step 3: branch -D (safe now that worktree has been removed)
if [ -n "${worker_result.branch}" ] && \
   [ "${worker_result.branch}" != "main" ] && \
   [ "${worker_result.branch}" != "master" ] && \
   [ "${worker_result.branch}" != "${TRUNK}" ]; then
    git branch -D "${worker_result.branch}" 2>/dev/null || true
fi
```

Update Plans.md:

```bash
# Update cc:WIP → cc:done [{hash}]
HASH=$(git rev-parse --short HEAD)
# Update the relevant task line in Plans.md
```

### Step 6: Plateau Check

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/detect-review-plateau.sh" ${current_task_id}
PLATEAU_EXIT=$?
# Note: current_task_id is the task_id identified in Step 1
```

| exit code | Meaning | Action |
|-----------|---------|--------|
| `0` | `PIVOT_NOT_REQUIRED` | Continue |
| `1` | `INSUFFICIENT_DATA` | Continue (insufficient data) |
| `2` | `PIVOT_REQUIRED` | Consult advisor once. **Stop loop** + escalate only on `STOP` or when consultation quota is exhausted |

**Escalation message on PIVOT_REQUIRED**:

```
harness-loop: stopped due to plateau detection (cycle {N}/{max})

Detected issue:
  {plateau details: output from detect-review-plateau.sh}

Suggested actions:
  1. Manually review the task content
  2. Re-run with `--pacing plateau` to extend the interval
  3. Skip the problematic task and restart `/harness-loop`

Please check the current state of Plans.md.
```

### Step 7: Cycle Count Check

```
cycles_completed += 1
if cycles_completed >= max_cycles:
    stop loop
    print(f"harness-loop: stopped after {max_cycles} cycles")
    return
```

- Default `max_cycles = 8`
- When `--max-cycles N` is specified, stop after N cycles

**Persisting the cycle count**:
- Embed the count in the `prompt` argument of `ScheduleWakeup`:
  ```
  /harness-loop all --max-cycles 8 --cycles-done {N} --pacing worker
  ```
- On wake-up, read `--cycles-done N` to restore the count

### Step 8: Record Checkpoint

```json
{
  "session_id": "<current session ID>",
  "title": "harness-loop cycle {N}/{max}: {task_completed}",
  "content": "cycle {N} complete. commit: {commit}. changes: {files_changed}. next: {next_task}"
}
```

Record in memory using the `harness_mem_record_checkpoint` tool.
Automatically included in the next wake-up's resume pack.

### Step 9: Schedule Next Wake-up

```
ScheduleWakeup(
    delaySeconds=<value corresponding to pacing>,
    prompt="/harness-loop <same args> --cycles-done {N}",
    reason="Cycle {N}/{max} complete: {task_completed}"
)
```

**delaySeconds by pacing**:

| pacing | delaySeconds | Rationale |
|--------|-------------|-----------|
| `worker` | 270 | Re-enter immediately after Worker completes (within 5 min cache warm) |
| `ci` | 270 | Wait for minimum CI job completion time |
| `plateau` | 1200 | 20 min cool-down period (plateau avoidance) |
| `night` | 3600 | Overnight batch (maximum clamp value) |

> **Clamp constraint**: `ScheduleWakeup` clamps `delaySeconds` at runtime to `[60, 3600]`.
> Values below 60 are raised to 60; values above 3600 are lowered to 3600.
> All design values are within range, but take care with future changes.

---

## Cycle Stop Condition Matrix

| Condition | Cycles | exit | Stop Reason | User Notification |
|-----------|--------|------|-------------|-------------------|
| `cycles >= max_cycles` | N (limit) | 0 | Normal limit | "Stopped after {N} cycles" |
| `PIVOT_REQUIRED` | any | 2 | Plateau detected | Escalation details |
| No incomplete tasks | any | 0 | All tasks complete | Completion report |
| User cancel | any | - | Manual interrupt | - |

---

## pacing Selection Guide

### Which pacing to use

```
What is the nature of the task?
│
├── Want to re-enter immediately after Worker completes
│     → worker (270s)
│
├── Need to wait for CI / test completion
│     → ci (270s)
│     Note: if CI takes more than 270s, adjust --pacing manually
│
├── Plateau detected — want to add interval
│     → plateau (1200s)
│
└── Leave overnight and check in the morning
      → night (3600s)
```

### When to change pacing

- **Initial launch**: `worker` (default) is usually sufficient
- **Many CI waits**: switch to `--pacing ci`
- **After plateau detection**: consider auto-switching with `--pacing plateau` (see Step 5)
- **Overnight runs**: launch with `--pacing night` and leave running

---

## ScheduleWakeup Constraints Detail

### Runtime constraint on delaySeconds

```
ScheduleWakeup(delaySeconds=X)
  → X < 60  → clamp to 60
  → X > 3600 → clamp to 3600
  → 60 <= X <= 3600 → used as-is
```

### Relationship with cache TTL

ScheduleWakeup's cache TTL is **5 min (300s)**.

- `worker` / `ci` at 270s is within 5 min → wake-up with cache still warm
- `plateau` at 1200s and `night` at 3600s wake up after cache expires
  → Step 4 (resume pack reload) is particularly important in these cases

### Passing arguments to the next wake-up

How to carry the cycle count to the next wake-up:

```bash
# Embed the current cycle count in the prompt
NEXT_PROMPT="/harness-loop ${SCOPE} --max-cycles ${MAX_CYCLES} --cycles-done ${CYCLES_DONE} --pacing ${PACING}"

ScheduleWakeup(
    delaySeconds=${DELAY},
    prompt="${NEXT_PROMPT}",
    reason="cycle ${CYCLES_DONE}/${MAX_CYCLES} complete"
)
```

---

## Reference: spike 41.0.0 Verification Results

This design is based on the proof-of-concept results from spike 41.0.0:

- `ScheduleWakeup`: confirmed to exist as an internal tool. delay [60, 3600] clamp, cache 5min TTL
- `/loop`: confirmed to exist as CC dynamic mode. sentinel `<<autonomous-loop-dynamic>>`
- `harness_mem_record_checkpoint`: confirmed to exist (schema: session_id / title / content are required)

Update this file if any of these assumptions change.
