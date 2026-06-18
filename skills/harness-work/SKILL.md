---
name: harness-work
description: "HAR: Execute Plans.md tasks from single task to full parallel team run. Trigger: implement, execute, do everything, breezing, team run, parallel, composer, composer 2.5. Do NOT load for: planning, review, release, setup."
kind: workflow
purpose: "Execute Plans.md tasks end to end"
trigger: "implement, execute, do everything, breezing, team run, parallel, composer, composer 2.5, composer mode"
shape: workflow
role: executor
pair: harness-review
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Write", "Edit", "Grep", "Glob", "Bash", "Task", "Monitor"]
argument-hint: "[all] [task-number|range] [--codex] [--parallel N] [--no-commit] [--resume id] [--breezing] [--auto-mode] [--tdd-bypass]"
user-invocable: true
effort: high
---

# Harness Work

The unified execution skill for the Harness framework.
Consolidates the following former skills:

- `work` — Plans.md task implementation (scope determined automatically)
- `impl` — Feature implementation (task-based)
- `breezing` — Full-team automated execution
- `parallel-workflows` — Parallel workflow optimization
- `ci` — Recovery from CI failures

## Quick Reference

| User Input | Mode | Behavior |
|------------|--------|------|
| `/harness-work` | **auto** | Automatically selected based on task count (see below) |
| `/harness-work all` | **auto** | Run all incomplete tasks in auto mode |
| `/harness-work 3` | solo | Execute only task 3 immediately |
| `/harness-work --parallel 5` | parallel | Force parallel execution with 5 workers |
| `/harness-work --codex` | codex | Delegate to Codex CLI (explicit only) |
| Cursor host (adapter candidate) | cursor | Task/subagent routing via `.cursor/AGENTS.md`; not auto-selected |
| `/harness-work --breezing` | breezing | Force team execution |
| `/harness-work 3 --plan roadmap` | solo | Run task 3 from the named plan `roadmap` |

## Execution Mode Auto Selection (when no explicit flag is given)

When no explicit mode flag (`--parallel`, `--breezing`, `--codex`) is provided,
the optimal mode is automatically selected based on the number of target tasks:

| Target Task Count | Auto-Selected Mode | Reason |
|-------------|---------------|------|
| **1 task** | Solo | Minimum overhead. Direct implementation is fastest. |
| **2–3 tasks** | Parallel (Task tool) | Threshold at which Worker isolation starts to pay off. |
| **4+ tasks** | Breezing | Effective three-way separation: Lead coordination + Worker parallelism + independent Reviewer. |

### Rules

1. **Explicit flags always override auto mode**
   - `--parallel N` → Parallel mode (regardless of task count)
   - `--breezing` → Breezing mode (regardless of task count)
   - `--codex` → Codex mode (regardless of task count)
2. **`--codex` activates only when explicitly specified**. Auto-selection is disabled because some environments do not have Codex CLI installed.
3. `--codex` can be combined with other modes: `--codex --breezing` → Codex + Breezing

## Execution Backend Selection

The backend (which runtime **implements** the code) is orthogonal to the execution mode (topology: solo / parallel / breezing).
While the execution mode determines how many workers run and how tasks are split, the backend determines who actually does the implementing.

| backend | Implementation party | Delegation command |
|---------|------------|------------|
| `claude` (default) | Task subagent (`agents/worker.md`) | Spawn worker via Agent tool |
| `codex` | Codex CLI | `bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" task --write "<prompt>"` |
| `cursor` | cursor-agent (model `composer-2.5-fast`) | `bash "${HARNESS_PLUGIN_ROOT}/scripts/cursor-companion.sh" task --write --workspace <worktree> "<prompt>"` |

### Resolution Procedure

Resolve once at the start of a run. Backend determination **must always go through the resolver** — do not read `HARNESS_IMPL_BACKEND` env directly for the decision:

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/resolve-impl-backend.sh"
```

Precedence (highest to lowest): `--backend <v>` / `--cursor` / `--codex` flags > `HARNESS_IMPL_BACKEND` env var > same key in project `env.local` > same key in user `~/.config/claude-harness/impl-backend.env` > default `claude`. Project settings override user scope.
Explicit flags (`--backend` / `--cursor` / `--codex`) always override env, file, and default.

### Natural Language Backend Trigger

When the user says `composer` / `Composer` / `composer 2.5` / `composer mode`, treat it as a `cursor backend` specification.
This carries the same intent as `--cursor`, but the final backend value must always be resolved via `resolve-impl-backend.sh`.
When resolving, pass `--backend cursor` as an explicit override so it takes priority over env, project, user file, and default.
Lead does not interpret `composer` as an additional agent inside a Claude Worker; per the non-`claude` backend convention, it calls `cursor-companion.sh` directly without routing through a Worker agent.

### Role-Scoped Constraint

The backend is **role-scoped**. Only the implementation (worker) role uses the resolved backend.
Both the Reviewer and Advisor roles are always pinned to the brain (`--host claude`, Opus).
Do not route Reviewer to the cursor / codex backend (the backend that produced the implementation must not review its own output).

```bash
# Only the implementation role follows the resolved backend (e.g. if backend=cursor, resolves to composer-2.5-fast)
bash "${HARNESS_PLUGIN_ROOT}/scripts/model-routing.sh" --host cursor --role worker --field model
# review / advisor are always pinned to claude (Opus)
bash "${HARNESS_PLUGIN_ROOT}/scripts/model-routing.sh" --host claude --role reviewer --field model
bash "${HARNESS_PLUGIN_ROOT}/scripts/model-routing.sh" --host claude --role advisor --field model
```

> The authoritative source for model names is `model-routing.sh`. The `composer-2.5-fast` value in this document is a reference only; actual resolution follows the command above (to prevent drift).

### Non-`claude` Backend Topology (No Worker Intermediary)

When the backend is `codex` or `cursor`, **Lead does not spawn a Worker agent (`chanpark-harness:worker`)**.
Instead, Lead calls `cursor-companion.sh` / `codex-companion.sh` directly.
The Worker layer is only involved when backend=`claude`.

Wiring:

| backend | Route |
|---------|------|
| `claude` (default) | Lead → Worker (`chanpark-harness:worker` agent) → … → Lead review → cherry-pick |
| `codex` | Lead → `codex-companion.sh task --write` → Lead review → cherry-pick |
| `cursor` | Lead → `cursor-companion.sh task --write --workspace <isolated-wt>` → Lead review → cherry-pick |

Inserting a Worker between Lead and a non-claude backend creates a double-delegation chain (Lead → Worker → companion → composer/codex), making the Worker's role meaningless — its agent contract self_review gate is vacuous because non-claude backends do not produce `worker-report.v1` or `self_review`. Lead skips the Worker and calls the companion directly.

Even for non-claude backend companion calls, Lead first creates a dedicated worktree, normalizes the companion stdout into the `companion-result.v1` shape (`{baseCommit, commit, worktreePath, branch, files_changed, summary}`), and then passes it through the existing Lead review / cherry-pick path. On `REQUEST_CHANGES`, instead of using `SendMessage`, Lead re-runs `cursor-companion.sh` / `codex-companion.sh` in the same worktree, re-reviews `baseCommit..HEAD`, and performs a range cherry-pick.

### Non-`claude` Backend self_review Gate

When the backend is `codex` or `cursor`, neither `worker-report.v1` nor the `self_review` array is produced.
Therefore Lead **skips** the self_review gate and treats Lead's own diff review as the sole quality gate (same treatment as the existing codex path).

### cursor Backend Banner (Required Before Delegation)

When the backend is `cursor`, Lead must output the following one-line banner before delegating:

```
⚠️ cursor backend: model=composer-2.5-fast / R01-R13 guardrails are not applied inside cursor-agent / output is untrusted until Lead review
```

cursor write delegation runs inside a worktree with its own `.git`, and Lead cherry-picks into main (R01-R13 is applied via the cherry-pick path).
See `.claude/rules/cursor-cli-only.md` for governance details.

### Lead Pre-cherry-pick Gate (contract grep required)

Before merging non-claude backend (cursor / codex) output into main, Lead must pass a **two-stage gate: visual diff + contract grep**. Do not APPROVE on visual diff alone.

| Gate | Command | What it detects |
|--------|----------|----------------|
| Visual diff | `git show <sha>` | Whether changes are as intended, no unintended file touches, support tier wording unchanged |
| Contract grep | `bash tests/test-support-claim-wording.sh` | Breakage of public support claim wording |
| Contract grep | `bash scripts/ci/check-consistency.sh` | Breakage of fixed-string contracts in i18n / locale / mirror / capability matrix |
| Contract grep | `bash tests/validate-plugin.sh` | Plugin distribution contract and hook wiring |

**Cherry-pick only when all gates PASS**. If any gate fails, revert or re-delegate to composer (explicitly requiring the same string contracts to be preserved).

Rationale: docs / README / locale / capability-matrix / spec.md contain **fixed-string contracts** monitored by grep. composer tends to mechanically reduce apparent linguistic redundancy, and what looks like a "clean dedup" in a visual diff can silently break fixed phrases.

## Options

| Option | Description | Default |
|----------|------|----------|
| `all` | Target all incomplete tasks | - |
| `N` or `N-M` | Task number or range | - |
| `--parallel N` | Number of parallel workers | auto |
| `--sequential` | Force sequential execution | - |
| `--codex` | Delegate implementation to Codex CLI (explicit only; not auto-selected) | false |
| `--backend <claude\|codex\|cursor>` | Explicit backend selection (applies to worker role only; highest precedence) | claude |
| `--cursor` | cursor backend (like `--codex`, explicit only; not auto-selected because some environments do not have cursor-agent installed) | false |
| `--plan NAME` | Use the named plan from `plans/manifest.json` | active/default |
| `--no-commit` | Suppress automatic commit | false |
| `--resume <id\|latest>` | Resume a previous session. Combining with `/recap` is recommended after a long gap. | - |
| `--breezing` | Team execution with Lead/Worker/Reviewer | false |
| `--no-tdd` | Skip TDD phase | false |
| `--tdd-bypass` | Bypass forced TDD in emergencies only. Record `HARNESS_TDD_BYPASS_REASON` or an explicit reason in the audit log. | false |
| `--no-simplify` | Skip Auto-Refinement | false |
| `--auto-mode` | Explicitly opt in to Harness-side Auto Mode rollout. This is distinct from `--enable-auto-mode`, which became unnecessary in CC 2.1.111. | false |

## Progressive Disclosure

First, confirm only the entry points, auto-selection logic, and stop conditions in this main body.
Read the details only when they become necessary.

| Detail | Reference |
|---|---|
| Concrete procedures for Solo / Parallel / Codex / Breezing | `references/execution-modes.md` |
| Codex review, Reviewer fallback, AI Residuals, fix loop | `references/review-loop.md` |
| Completion report generation for Solo / Breezing | `references/completion-report.md` |
| Re-ticketing on test/CI failure | `references/failure-reticketing.md` |
| Criteria for spec source-of-truth checks | `docs/plans/spec-ssot.md` |

### Important Stop Conditions

- Stop if `Plans.md` is in an old format and the DoD / Depends / Status columns cannot be read.
- If the spec affects implementation decisions but no project spec SSOT can be found, create or update the spec before implementing.
- Do not proceed to implementation if a sprint-contract is required but not ready.
- Do not mark a task complete while critical or major review findings remain.
- Do not resolve issues by weakening tests, skipping them, or relaxing expectations to match the implementation.
- Call helper scripts from `${HARNESS_PLUGIN_ROOT}/scripts/`, not from the host project's `scripts/`.
- When multiple Plans.md files exist, do not switch plans within a single run. If necessary, start a new run with `--plan NAME` specified explicitly.

> **Token Optimization (v2.1.69+)**: For lightweight tasks that do not involve git operations,
> enable `includeGitInstructions: false` in plugin settings to reduce prompt tokens.

> **Prompt Cache (CC 2.1.108+)**: For longer implementation sessions or heavy `--resume` usage,
> prefer `ENABLE_PROMPT_CACHING_1H=1`.

## Scope Dialog (when no arguments are given)

```
/harness-work
How far should we go?
1) Next task: the next incomplete task in Plans.md → execute in Solo mode
2) Everything (recommended): complete all remaining tasks → auto mode selected by task count
3) Specify by number: enter task number(s) (e.g. 3, 5-7) → auto mode selected by count
```

If arguments are provided, execute immediately (skip the dialog):
- `/harness-work all` → all tasks, auto mode selected
- `/harness-work 3-6` → 4 tasks, so Breezing is auto-selected

## Effort Level Control (Opus 4.8 / v2.1.111+)

Effort is the official dial for selecting a model's reasoning intensity. There are four levels: `low(○)/medium(◐)/high(●)/xhigh`.
Use `/effort auto` to reset to the default (`max` was retired in v2.1.72; `xhigh` is its successor).

In Opus 4.8, thinking is off by default, and effort is the primary lever for reasoning depth (effort has more impact than in any previous Opus).
When you observe shallow reasoning, raise the effort rather than working around it in the prompt.
For this reason, the old approach of **injecting free-text markers (e.g. `ultrathink`) into spawn prompts is retired**,
replaced by a unified approach of **selecting the effort tier for Worker spawning** based on a complexity score.
This aligns with `docs/model-routing-policy.md` (do not infer effort from free-text) and
`.claude/rules/opus-4-7-prompt-audit.md` pass condition 5 (`xhigh` is chosen by the caller).

### Multi-Factor Scoring

Accumulate the following scores when starting a task.

| Factor | Condition | Score |
|------|------|--------|
| File count | 4 or more files to be changed | +1 |
| Directory | Includes core/, guardrails/, or security/ | +1 |
| Keyword | Includes architecture, security, design, or migration | +1 |
| Failure history | Agent memory contains a failure record for the same task | +2 |
| Explicit specification | PM template includes `effort: high` / `effort: xhigh` (legacy `ultrathink` also accepted) | +3 (auto-adopted) |

### Determining the Effort Tier (do not inject)

Use the score to determine the effort tier as an **escalation signal** (do **not** write marker strings like `ultrathink` into spawn prompts).
There are only two applicable levers:

- **Session `/effort`**: Before entering a batch of complex tasks, the host sets `/effort high` / `/effort xhigh` (the most reliable lever, effective session-wide).
- **Worker frontmatter**: The `effort` field in `agents/worker.md` (default: `medium`) acts as a floor. Because CC's Agent/Task spawn API does not expose per-spawn effort settings, there is no mechanism to raise effort for individual workers. Scores are recorded in `worker-report.v1` under `task_complexity_note` so the Lead can use them as a basis for raising session effort.

| Score | code-risk (includes core/guardrails/security/architecture/migration) | Effort tier |
|--------|-----------------------------------|-------------|
| 0–2 | Any | `medium` (Worker frontmatter default) |
| ≥ 3 | No | `high` |
| ≥ 3 | Yes | `xhigh` |

The same logic applies in breezing mode (managed centrally by harness-work).
Since Workers run on Sonnet 4.6, `xhigh` is effectively downgraded to `high` at runtime, but raising the tier itself remains valid (see `docs/effort-level-policy.md`).

## Execution Mode Details

### Harness Helper Script Root

Helper scripts bundled with Harness must always be called from the plugin bundle root, not from the target project's `scripts/`.

```bash
HARNESS_PLUGIN_ROOT="${HARNESS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -z "$HARNESS_PLUGIN_ROOT" ] && [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
  probe="$(cd "${CLAUDE_SKILL_DIR}" && pwd)"
  while [ "$probe" != "/" ] && [ ! -d "$probe/scripts" ]; do
    probe="$(cd "$probe/.." && pwd)"
  done
  [ -d "$probe/scripts" ] && HARNESS_PLUGIN_ROOT="$probe"
fi
```

All subsequent `node "${HARNESS_PLUGIN_ROOT}/scripts/..."` / `bash "${HARNESS_PLUGIN_ROOT}/scripts/..."` calls assume this resolved root.

### Backend-Resolved Executor Path (Solo / Parallel / Breezing)

Solo, Parallel, and Breezing all select the implementation executor from the same resolver result.
`harness-work 3 --cursor` and a user/project `HARNESS_IMPL_BACKEND=cursor` setting must not fall through to local Read/Write/Edit/Bash, even for a single-task run.

```
resolver_backend_arg = ""
if explicit_backend_value in ["claude", "codex", "cursor"]:
    resolver_backend_arg = "--backend {explicit_backend_value}"
backend = bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/resolve-impl-backend.sh\" {resolver_backend_arg}")
if explicit_flag == "--cursor":
    backend = "cursor"
if explicit_flag == "--codex":
    backend = "codex"

if topology in ["solo", "parallel"] and backend in ["cursor", "codex"]:
    BASE_REF = git("rev-parse", "HEAD")
    WT_ID = "{task.number}-$(date +%Y%m%d-%H%M%S)-$$"
    worktree_path = ".claude/worktrees/{backend}-{WT_ID}"
    worktree_branch = "{backend}-work/{WT_ID}"
    bash("mkdir -p .claude/worktrees && git worktree add -b {worktree_branch} {worktree_path} {BASE_REF}")
    companion_prompt = "{task prompt}\n\nAfter making changes, create exactly one git commit in this worktree before returning."
    if backend == "cursor":
        companion_output = bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/cursor-companion.sh\" task --write --workspace {worktree_path} \"{companion_prompt}\"")
    else:
        companion_state_file = "{worktree_path}/.claude/state/codex-primary-environment.json"
        companion_output = bash("HARNESS_CODEX_PRIMARY_ENV_STATE_FILE={companion_state_file} bash \"${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh\" task --write -C {worktree_path} \"{companion_prompt}\"")
    latest_commit = git("-C", worktree_path, "rev-parse", "HEAD")
    if backend == "cursor" and git("-C", worktree_path, "status", "--porcelain") != "":
        git("-C", worktree_path, "add", "-A")
        git("-C", worktree_path, "-c", "user.name=cursor-composer", "-c", "user.email=cursor-composer@local", "commit", "--no-verify", "-m", "cursor: delegated change")
        latest_commit = git("-C", worktree_path, "rev-parse", "HEAD")
    if latest_commit == BASE_REF:
        raise EscalationError("{backend} companion produced no commit")
    worker_result = {type: "companion-result.v1", baseCommit: BASE_REF, commit: latest_commit, worktreePath: worktree_path, branch: worktree_branch, files_changed: git("-C", worktree_path, "diff", "--name-only", "{BASE_REF}..HEAD"), summary: companion_output}
    enter_non_claude_companion_review_loop(worker_result)
else:
    run_native_solo_or_parallel()

def enter_non_claude_companion_review_loop(worker_result):
    # companion-result.v1 has no worker_id and no worker_result.self_review.
    # Do not use the Worker-only SendMessage/self_review loop for cursor/codex.
    latest_commit = worker_result.commit
    diff_text = git("-C", worker_result.worktreePath, "diff", "{worker_result.baseCommit}..HEAD")
    verdict = codex_exec_review(diff_text) or reviewer_agent_review(diff_text)
    review_count = 0
    MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3
    while verdict == "REQUEST_CHANGES" and review_count < MAX_REVIEWS:
        previous_commit = latest_commit
        if backend == "cursor":
            companion_output = bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/cursor-companion.sh\" task --write --workspace {worker_result.worktreePath} \"Review findings:\n{issues}\n\nFix the findings and commit the result.\"")
        else:
            companion_state_file = "{worker_result.worktreePath}/.claude/state/codex-primary-environment.json"
            companion_output = bash("HARNESS_CODEX_PRIMARY_ENV_STATE_FILE={companion_state_file} bash \"${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh\" task --write -C {worker_result.worktreePath} \"Review findings:\n{issues}\n\nFix the findings and commit the result.\"")
        latest_commit = git("-C", worker_result.worktreePath, "rev-parse", "HEAD")
        if backend == "cursor" and git("-C", worker_result.worktreePath, "status", "--porcelain") != "":
            git("-C", worker_result.worktreePath, "add", "-A")
            git("-C", worker_result.worktreePath, "-c", "user.name=cursor-composer", "-c", "user.email=cursor-composer@local", "commit", "--no-verify", "-m", "cursor: review fix")
            latest_commit = git("-C", worker_result.worktreePath, "rev-parse", "HEAD")
        if latest_commit == previous_commit:
            raise EscalationError("{backend} companion retry produced no new commit")
        worker_result.commit = latest_commit
        worker_result.summary = companion_output
        diff_text = git("-C", worker_result.worktreePath, "diff", "{worker_result.baseCommit}..HEAD")
        verdict = codex_exec_review(diff_text) or reviewer_agent_review(diff_text)
        review_count++
    if verdict == "APPROVE":
        git cherry-pick --no-commit {worker_result.baseCommit}..{worker_result.commit}
```

Parallel applies this resolver path per task.
When the backend is `cursor` / `codex`, do not use native Worker spawn; instead create an isolated companion worktree per task, normalize it into `companion-result.v1`, then enter the non-Claude companion-dedicated range review / cherry-pick loop.

### Solo Mode (auto-selected for 1 task)

1. Read Plans.md and identify the target task.
   - **If Plans.md does not exist**: Automatically call `harness-plan create --ci` to generate Plans.md and continue.
   - If the header lacks DoD / Depends columns: print `Plans.md is in an old format. Please regenerate with harness-plan create.` → **stop**.
   - **If the conversation contains tasks not listed in Plans.md**: Extract requirements from the preceding conversation context and auto-append to Plans.md as `cc:TODO`.
     - Extraction logic: Detect action verbs in user messages (e.g. "add", "fix", "implement").
     - Appended entries must conform to the v2 format (Task / Content / DoD / Depends / Status).
     - After appending, display "Appended the following to Plans.md" to the user (5-second timeout prompt, default: continue).
1.5. **Task Context Check** (30 seconds):
   - From the task's "Content" and "DoD", infer and display the **purpose** (the problem this task solves) in one line.
   - Use `git grep` / `Glob` to infer and display the **impact scope** (files/modules affected by the change).
   - If the inference is confident: proceed to implementation without delay.
   - If the inference is not confident: ask the user one question only ("Is this understanding correct?").
1.6. **Spec Source-of-Truth Preflight**:
   - Search for an existing project spec SSOT (e.g. `docs/spec/00-project-spec.md`, `docs/ARCHITECTURE.md`, `docs/HANDOFF.md`, `docs/oem/PROJECT_COMPASS.md`, `docs/specs/`).
   - If the task changes product behavior / API / data model / permissions / billing / integrations / tenant boundaries and no spec exists, create `docs/spec/00-project-spec.md`.
   - If the spec is outdated or contradicts the task, update the spec before implementing.
   - For typo / format / dependency bump / docs-only / behavior-preserving refactor tasks, record the skip reason and continue.
   - Include `spec_path` or `spec_skip_reason` in the context passed to Worker / Reviewer.
2. Update the task to `cc:WIP`.
3. **TDD Phase** (when `[skip:tdd]` is absent and a test framework is present):
   a. Create the test file first (Red).
   b. Confirm it fails.
   c. Record the FAIL evidence to `.claude/state/tdd-red-log/<task-id>.jsonl` using `bash "${HARNESS_PLUGIN_ROOT}/scripts/log-tdd-red.sh"`. In environments where the script is unavailable, attach the literal failing test output as `self_review` evidence in the worker-report.
   d. When using `--tdd-bypass`, explicitly set `HARNESS_TDD_BYPASS=1` and `HARNESS_TDD_BYPASS_REASON="<reason>"`, and record why TDD was skipped in the sprint-contract / worker-report.
4. Generate `sprint-contract.json` with `node "${HARNESS_PLUGIN_ROOT}/scripts/generate-sprint-contract.js" <task-id>`.
5. Add Reviewer perspective via `bash "${HARNESS_PLUGIN_ROOT}/scripts/enrich-sprint-contract.sh"`, then confirm approved with `bash "${HARNESS_PLUGIN_ROOT}/scripts/ensure-sprint-contract-ready.sh"`.
6. **Advisor Consult (only when needed)**:
   - For high-risk tasks (`needs-spike` / `security-sensitive` / `state-migration`), consult once before the first execution.
   - If the same failure cause occurs twice in a row, consult before the third attempt.
   - If plateau detection returns `PIVOT_REQUIRED`, consult once before escalating to the user.
   - Receive the result as `advisor-response.v1`: treat `PLAN` as restructuring the approach, `CORRECTION` as a local fix, and `STOP` as immediate escalation.
   - Consult at most once per `trigger_hash`. Maximum 3 consultations per task.
7. Implement the code via the backend-resolved executor path (Green).
   - backend=`claude`: implement via local / native Read/Write/Edit/Bash path.
   - backend=`cursor` / `codex`: implement via the companion worktree path above and pass `companion-result.v1` to the shared review loop.
8. Auto-Refinement with `/code-review --fix` (formerly `/simplify`; skip with `--no-simplify`).
9. **Automated Review Stage** (see "Review Loop"):
   - Run review with Codex exec as priority, fall back to internal Reviewer agent.
   - If `reviewer_profile` in `sprint-contract.json` is `runtime`, run `bash "${HARNESS_PLUGIN_ROOT}/scripts/run-contract-review-checks.sh"`.
   - On REQUEST_CHANGES: fix based on findings → re-review (`MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3`).
   - On APPROVE, proceed to the next step. Do not finalize completion on self-check alone.
10. Normalize and save the review artifact with `bash "${HARNESS_PLUGIN_ROOT}/scripts/write-review-result.sh"` (for browser profile, pass `--browser-result`; when `browser_verdict == PENDING_BROWSER`, use the static verdict).
11. Auto-commit with `git commit` (skip with `--no-commit`).
12. Update the task to `cc:Done` with the commit hash.
   - Get the most recent commit hash (7-character short form) with `git log --oneline -1`.
   - Update Plans.md Status to `cc:Done [a1b2c3d]`.
   - When there is no commit (`--no-commit`), use `cc:Done` without a hash.
13. **Rich completion report** (see "Completion Report Format").
14. **Automatic re-planning on failure** (test/CI failures only):
    - Check the test execution results.
    - On failure: save the proposed fix task to state and add it to Plans.md via an approval command (see "Automatic Failure Re-ticketing").
    - On success: proceed to the next task.

### Parallel Mode (auto-selected for 2–3 tasks / forced with `--parallel N`)

Run `[P]`-marked tasks in parallel with N workers.
When `--parallel N` is explicitly specified, this mode is used regardless of task count.
Use git worktrees to isolate tasks when writes to the same file would conflict.
The implementation executor for each task follows the Backend-resolved executor path.
When `--parallel N --cursor`, `--backend cursor`, or the default `HARNESS_IMPL_BACKEND=cursor` is set, Parallel also uses a per-task Cursor companion worktree instead of native Worker spawn.

### Codex Mode (`--codex` explicit only)

Delegate tasks to Codex CLI via the official plugin `codex-plugin-cc` companion.

```bash
# Task delegation (writable, worktree-isolated)
BASE_REF="$(git rev-parse HEAD)"
WT_ID="codex-$(date +%Y%m%d-%H%M%S)-$$"
WORKTREE_PATH=".claude/worktrees/${WT_ID}"
git worktree add -b "codex-work/${WT_ID}" "$WORKTREE_PATH" "$BASE_REF"
HARNESS_CODEX_PRIMARY_ENV_STATE_FILE="$WORKTREE_PATH/.claude/state/codex-primary-environment.json" \
  bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" task --write -C "$WORKTREE_PATH" \
  "Task content. Before finishing, create exactly one git commit in this worktree."

# Via stdin (for large prompts)
CODEX_PROMPT=$(mktemp /tmp/codex-prompt-XXXXXX.md)
# Write task content to the file
cat "$CODEX_PROMPT" | HARNESS_CODEX_PRIMARY_ENV_STATE_FILE="$WORKTREE_PATH/.claude/state/codex-primary-environment.json" \
  bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" task --write -C "$WORKTREE_PATH"
rm -f "$CODEX_PROMPT"

# After Lead review approves, incorporate the range
git -C "$WORKTREE_PATH" diff "$BASE_REF..HEAD"
WORKTREE_HEAD="$(git -C "$WORKTREE_PATH" rev-parse HEAD)"
git cherry-pick --no-commit "$BASE_REF..$WORKTREE_HEAD"
```

The companion communicates with Codex via the App Server Protocol,
providing job management, thread resume, and structured output.
Validate the result and fix it yourself if it does not meet quality standards.

### Cursor Mode (adapter candidate; not auto-selected)

In a Cursor host, `.cursor/AGENTS.md` and `.cursor-plugin/plugin.json` are
the bootstrap route. Cursor remains a `candidate` — making supported claims is prohibited.

- **Solo / Parallel**: Task tool or `.cursor/agents/worker.md` subagent
- **Breezing**: Worker parallelism for non-overlapping file groups only;
  Reviewer / cherry-pick / Advisor run serially as in the core
- **Multitask / background agents**: Smoke target only. Do not claim Claude Agent Teams parity.

Model routing:

```bash
bash scripts/model-routing.sh --host cursor --role worker --format json
```

Explicit Task/subagent `model` takes priority over the routed default.

Validation:

```bash
bash tests/test-cursor-adapter-candidate.sh
```

### Breezing Mode (auto-selected for 4+ tasks / forced with `--breezing`)

Team execution with separated Lead / Worker / Advisor / Reviewer roles.
Assumes native subagent orchestration using `spawn_agent`, `wait`, `send_input`, `resume_agent`, `close_agent` in Codex;
does not follow the old TeamCreate / TaskCreate-based description.
In Cursor, maps to Task/subagent/background agents, but the serial responsibility for review/cherry-pick remains on the core side (adapter smoke target).

**Permission Policy**:
- The current shipped default is `bypassPermissions`.
- `--auto-mode` is treated as an opt-in rollout flag for compatible parent sessions.
- Do not write the undocumented `autoMode` value to `permissions.defaultMode` or agent frontmatter `permissionMode`.

> **CC v2.1.69+**: The platform prohibits nested teammates, so do not add redundant anti-nesting language to Worker/Reviewer prompts.

```
Lead (this agent)
├── Worker (task-worker agent) — implementation
├── Advisor (chanpark-harness:advisor) — strategy advice
└── Reviewer (code-reviewer agent) — review
```

**Phase A: Pre-delegate (preparation)**:
1. Read Plans.md and identify the target tasks.
2. Analyze the dependency graph and determine execution order (Depends column).
3. Score the effort for each task (determine effort tier — high/xhigh).
4. Generate `sprint-contract.json` with `node "${HARNESS_PLUGIN_ROOT}/scripts/generate-sprint-contract.js"`.
5. Add Reviewer perspective with `bash "${HARNESS_PLUGIN_ROOT}/scripts/enrich-sprint-contract.sh"`, and stop if not approved via `bash "${HARNESS_PLUGIN_ROOT}/scripts/ensure-sprint-contract-ready.sh"`.

**Phase B: Delegate (Worker spawn → Advisor when needed → review → cherry-pick)**:

Execute the following **sequentially** for each task (in dependency order):

> **API Note**: The following is written in Claude Code API syntax.
> In Codex environments, replace `Agent(...)` with `spawn_agent(...)` and `SendMessage(...)` with `send_input(...)`.
> See the API mapping table in `team-composition.md` for details.

```
for task in execution_order:
    # B-1. Generate sprint-contract
    contract_path = bash("node \"${HARNESS_PLUGIN_ROOT}/scripts/generate-sprint-contract.js\" {task.number}")
    contract_path = bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/enrich-sprint-contract.sh\" {contract_path} --check \"Verify DoD from reviewer perspective\" --approve")
    bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/ensure-sprint-contract-ready.sh\" {contract_path}")

    # B-2. Spawn Worker (foreground, worktree-isolated)
    # The Agent tool return value includes agentId — used by SendMessage in the fix loop
    Plans.md: task.status = "cc:WIP"  # Update when starting (tasks not yet started remain cc:TODO)

    # Propagate universal violations even when /harness-work is run successively
    # (Assume universal_violations = [] is initialized on first run)
    briefing_header = ""
    if universal_violations:
        briefing_header = (
            "🚨 Universal violations already detected in this session (must not recur):\n"
            + "\n".join(f"- {v}" for v in universal_violations)
            + "\n\n"
        )

    worker_result = Agent(
        subagent_type="chanpark-harness:worker",
        prompt=briefing_header + "Task: {task.content}\nDoD: {task.DoD}\ncontract_path: {contract_path}\nmode: breezing",
        isolation="worktree",
        run_in_background=false  # Run in foreground → wait for Worker to complete
    )
    worker_id = worker_result.agentId  # Retain for SendMessage
    # worker_result contains {commit, worktreePath, files_changed, summary}

    # B-3. Lead calls Advisor only when Worker returns an advice request
    if worker_result.type == "advisor-request.v1":
        advisor_result = Advisor(
            prompt=worker_result.request_json
        )
        worker_result = SendMessage(
            to=worker_id,
            message="advisor-response.v1: {advisor_result}"
        )

    # B-3.5. self_review gate (Lead verifies mechanically before spawning Reviewer)
    # Worker's worker-report.v1 must have all active self_review rules, all verified=true and evidence non-empty
    # When tdd.enforce.enabled=true and tdd_required=true, `tdd-red-evidence-attached` is also required as an active rule
    # If any rule has verified=false or evidence=="" → do not spawn Reviewer; send back to Worker
    self_review_failures = 0
    MAX_SELF_REVIEW_RETRIES = 2  # Lead escalates on the 3rd attempt (retries=2)
    while True:
        unverified = [
            r for r in worker_result.self_review
            if (not r.get("verified")) or (not r.get("evidence"))
        ]
        if not unverified:
            break  # All rules verified → proceed to B-4 (actual review)
        self_review_failures += 1
        if self_review_failures > MAX_SELF_REVIEW_RETRIES:
            # Unverified items remain after 3 send-backs → escalate to Lead
            Plans.md: task.status = "cc:TODO"  # Revert to pre-start state
            raise EscalationError(f"self_review has unverified rules after 3 send-backs (rules: {[u['rule'] for u in unverified]})")
        # Send back to Worker (do not spawn Reviewer)
        SendMessage(
            to=worker_id,
            message=f"self_review has unverified rules: {[u['rule'] for u in unverified]}. Fill in the evidence for each rule with actual command output or literal test results. When TDD is required, attach .claude/state/tdd-red-log/<task-id>.jsonl or literal failing test output, then set verified=true and amend."
        )
        worker_result = wait_for_response(worker_id)

    # B-4. Lead runs review (Codex exec preferred)
    diff_text = git("-C", worker_result.worktreePath, "show", worker_result.commit)
    verdict = codex_exec_review(diff_text) or reviewer_agent_review(diff_text)
    profile = jq(contract_path, ".review.reviewer_profile")
    review_input = "review-output.json"
    if profile == "runtime":
        review_input = bash("cd {worker_result.worktreePath} && bash \"${HARNESS_PLUGIN_ROOT}/scripts/run-contract-review-checks.sh\" {contract_path}")
        runtime_verdict = jq(review_input, ".verdict")
        if runtime_verdict == "REQUEST_CHANGES":
            verdict = "REQUEST_CHANGES"
        elif runtime_verdict == "DOWNGRADE_TO_STATIC":
            pass  # No runtime validation command → keep static verdict as-is
    browser_result = ""
    if profile == "browser":
        # Reuse route / browser_mode / execution_instructions from browser artifact to launch browser runner
        browser_artifact = bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/generate-browser-review-artifact.sh\" {contract_path}")
        browser_result = bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/browser-review-runner.sh\" {browser_artifact}")
        browser_verdict = jq(browser_result, ".browser_verdict")
        if browser_verdict == "REQUEST_CHANGES":
            verdict = "REQUEST_CHANGES"
        elif browser_verdict == "APPROVE" and verdict != "REQUEST_CHANGES":
            verdict = "APPROVE"
        # When browser_verdict == PENDING_BROWSER, maintain the static verdict
    # If review_input is DOWNGRADE_TO_STATIC, use static review result
    if review_input != "review-output.json" and jq(review_input, ".verdict") == "DOWNGRADE_TO_STATIC":
        review_input = "review-output.json"  # Fall back to static review result
    bash("bash \"${HARNESS_PLUGIN_ROOT}/scripts/write-review-result.sh\" {review_input} {latest_commit} --browser-result {browser_result}")

    # B-5. Fix loop (on REQUEST_CHANGES, up to contract's max_iterations)
    # Worker has already completed in foreground, but can be resumed with SendMessage
    # (CC: SendMessage(to: agentId) / Codex: resume_agent(agent_id) + send_input)
    review_count = 0
    # Read max_iterations only when sprint-contract exists. Default to 3 (backward-compatible)
    MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3
    latest_commit = worker_result.commit
    while verdict == "REQUEST_CHANGES" and review_count < MAX_REVIEWS:
        SendMessage(to=worker_id, message="Review findings: {issues}\nPlease fix and amend.")
        # Worker fixes → amends → returns the updated commit hash
        updated_result = wait_for_response(worker_id)
        latest_commit = updated_result.commit
        diff_text = git("-C", worker_result.worktreePath, "show", latest_commit)
        verdict = codex_exec_review(diff_text) or reviewer_agent_review(diff_text)
        review_count++

    # B-6. APPROVE → cherry-pick into trunk (via feature branch)
    # Worker's Branch Guard ensures trunk HEAD does not move; commit is expected on the feature branch
    if verdict == "APPROVE":
        TRUNK=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||' || echo "main")
        git checkout "$TRUNK"  # safety: no-op if already on trunk
        # Check whether the feature branch commit is already on trunk (fallback for Branch Guard failure)
        if git("merge-base", "--is-ancestor", latest_commit, "HEAD"):
            pass  # Already on trunk — no cherry-pick needed (re-entry guard)
        else:
            git cherry-pick --no-commit {latest_commit}  # feature branch → trunk
            git commit -m "{task.content}"
        # Remove Worker's worktree, then delete the feature branch
        if worker_result.worktreePath:
            git worktree remove {worker_result.worktreePath} --force
        if worker_result.branch and worker_result.branch not in ["main", "master"] and worker_result.branch != TRUNK:
            git branch -D {worker_result.branch}
        Plans.md: task.status = "cc:Done [{hash}]"
        # Record auto-checkpoint (idempotency guard (c))
        # Call immediately after rewriting Plans.md. Fail-open (|| true) to not stop the loop on failure
        HASH=$(git rev-parse --short HEAD)
        REVIEW_RESULT_PATH=".claude/state/review-results/${task.number}.review-result.json"
        bash "${HARNESS_PLUGIN_ROOT}/scripts/auto-checkpoint.sh" \
            "${task.number}" "${HASH}" "${contract_path}" "${REVIEW_RESULT_PATH}" \
            || true  # fail-open: continues even when harness-mem is not running
    else:
        → Escalate to user

    # B-7. Progress feed
    print("📊 Progress: Task {completed}/{total} done — {task.content}")
```

### Advisor Protocol (common to all modes)

The Advisor is neither the implementer nor the reviewer.
The Advisor steps in only when there is uncertainty, acting as a consultant to help the executor decide the next step.

1. Worker does not spawn additional generic subagents; it returns `advisor-request.v1` only when needed.
2. Lead calls the Advisor exactly once.
3. Advisor returns one of `PLAN` / `CORRECTION` / `STOP`.
4. Lead passes that advice back to the same Worker to continue.
5. Reviewer looks only at the final artifact. The Reviewer does not issue APPROVE / REQUEST_CHANGES on the Advisor's response.

### Advisor in Solo Mode

In solo execution, the parent session itself acts as Lead.
This means "implement yourself, consult the Advisor yourself, then send for independent review at the end."

- Consultation conditions are the same as in loop / breezing.
- Consultation budget is also the same: maximum 3 times per task.
- `STOP` halts immediately and escalates to the user.
- The review artifact gate is not skipped.

### Sprint Contract

A `sprint-contract` is a small contract file that encodes "what constitutes acceptance of this task" in a form readable with the same meaning by both machines and humans.
The default save location is `.claude/state/contracts/<task-id>.sprint-contract.json`.

```bash
node "${HARNESS_PLUGIN_ROOT}/scripts/generate-sprint-contract.js" 32.1.1
```

The generated artifact includes the following.

- `checks`: Acceptance criteria decomposed from the DoD
- `non_goals`: What is explicitly out of scope for this task
- `runtime_validation`: Validation commands such as test, lint, typecheck
- `browser_validation`: UI flow verification items the browser reviewer must cover
- `browser_mode`: `scripted` or `exploratory`
- `route`: Whether the browser reviewer uses `playwright` / `agent-browser` / `chrome-devtools`
- `risk_flags`: e.g. `needs-spike`, `security-sensitive`, `ux-regression`
- `reviewer_profile`: `static`, `runtime`, or `browser`

**Phase C: Post-delegate (integration and reporting)**:
1. Aggregate the commit logs for all tasks.
2. Output the **rich completion report** (Breezing template in "Completion Report Format").
3. Final verification of Plans.md (confirm all tasks are marked `cc:Done`).

## Handling CI Failures

When CI fails:

1. Check the logs to identify the error.
2. Apply the fix.
3. If the same cause fails 3 times, stop the automatic fix loop.
4. Escalate with a summary of the failure logs, attempted fixes, and remaining issues.

## Automatic Failure Re-ticketing

When tests/CI fail after a task is complete, automatically generate a proposed fix task and update Plans.md after approval:

### Trigger Conditions

| Condition | Action |
|------|----------|
| Test fails after `cc:Done` | Save proposed fix task to state and wait for approval |
| CI failure (fewer than 3 times) | Apply fix and increment failure count |
| CI failure (3rd time) | Present proposed fix task + escalate |

### Automatic Fix Task Generation

1. Classify the failure cause (syntax_error / import_error / type_error / assertion_error / timeout / runtime_error).
2. Save the proposed fix task to `.claude/state/pending-fix-proposals.jsonl`:
   - Number: original task number + `.fix` suffix (e.g. `26.1.fix`)
   - Content: `fix: [original task name] - [failure cause category]`
   - DoD: tests/CI must pass
   - Depends: original task number
3. When the user sends `approve fix <task_id>`, add it to Plans.md as `cc:TODO`.
4. `reject fix <task_id>` discards the proposal. When there is only one pending item, `yes` / `no` also works.

## Review Loop

The quality validation stage that runs automatically after implementation is complete (after step 5).
Applied uniformly across **all modes** (Solo / Parallel / Breezing).
In Parallel mode, each Worker runs the same loop as step 10 (accepting external review).

### Review Execution Priority

```
1. Codex exec (preferred)
   ↓ codex command not found or timeout (120s)
2. Internal Reviewer agent (fallback)
```

### APPROVE / REQUEST_CHANGES Criteria

Pass the following threshold criteria to the reviewer, and have the verdict determined **by these criteria only**.
Improvement suggestions outside these criteria are returned as `recommendations` but do not affect the verdict.

| Severity | Definition | Impact on verdict |
|--------|------|-----------------|
| **critical** | Security vulnerability, data loss risk, potential production outage | 1 finding → REQUEST_CHANGES |
| **major** | Breaking existing functionality, clear contradiction with spec, failing tests | 1 finding → REQUEST_CHANGES |
| **minor** | Naming improvements, missing comments, style inconsistency | No impact on verdict |
| **recommendation** | Best practice suggestions, future improvement ideas | No impact on verdict |

> **Important**: When there are only minor / recommendation findings, **always return APPROVE**.
> "Nice to have" improvements are not grounds for REQUEST_CHANGES.

### Codex Exec Review (via official plugin)

Retain the HEAD at task start as `BASE_REF` and review the diff against that ref.
Use the companion review of the official plugin `codex-plugin-cc`.

```bash
# Record base ref at task start (run before cc:WIP update in Step 2)
BASE_REF=$(git rev-parse HEAD)

# ... after implementation is complete ...

# Run the official plugin's structured review
bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" review --base "${BASE_REF}"
REVIEW_EXIT=$?
```

**Verdict mapping** (official plugin → Harness format):

The official plugin returns structured output conforming to `review-output.schema.json`.
Conversion rules to Harness verdict format:

| Official plugin | Harness | Verdict impact |
|---|---|---|
| `approve` | `APPROVE` | - |
| `needs-attention` | `REQUEST_CHANGES` | - |
| `findings[].severity: critical` | `critical_issues[]` | 1 finding → REQUEST_CHANGES |
| `findings[].severity: high` | `major_issues[]` | 1 finding → REQUEST_CHANGES |
| `findings[].severity: medium/low` | `recommendations[]` | No impact on verdict |

AI Residuals scanning continues to run via `bash "${HARNESS_PLUGIN_ROOT}/scripts/review-ai-residuals.sh"`,
and the final verdict is determined by combining it with the companion review result.

```bash
# AI Residuals scan (can run in parallel with companion review)
AI_RESIDUALS_JSON="$(bash "${HARNESS_PLUGIN_ROOT}/scripts/review-ai-residuals.sh" --base-ref "${BASE_REF}" --include-untracked 2>/dev/null || echo '{"tool":"review-ai-residuals","scan_mode":"diff","base_ref":null,"include_untracked":true,"files_scanned":[],"untracked_files_scanned":[],"summary":{"verdict":"APPROVE","major":0,"minor":0,"recommendation":0,"total":0},"observations":[]}')"
```

### Internal Reviewer Agent Fallback

When Codex exec is unavailable (`command -v codex` fails or exit code ≠ 0):

```
Agent tool: subagent_type="reviewer"
prompt: "Please review the following changes. Criteria: critical/major → REQUEST_CHANGES, minor/recommendation only → APPROVE. diff: {git diff ${BASE_REF}}"
```

The Reviewer agent runs safely in read-only mode (Write/Edit/Bash disabled).

### Fix Loop (on REQUEST_CHANGES)

```
review_count = 0
# Read max_iterations only when sprint-contract exists. Default to 3 (backward-compatible)
contract_path = get_sprint_contract_path()  # e.g. .claude/state/contracts/<task-id>.sprint-contract.json
MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3

while verdict == "REQUEST_CHANGES" and review_count < MAX_REVIEWS:
    1. Parse the review findings (critical / major only)
    2. Implement the fix for each finding
    3. Run the review again (same criteria, same priority)
    review_count++

if review_count >= MAX_REVIEWS and verdict != "APPROVE":
    → Escalate to user
    → Display "Applied fixes MAX_REVIEWS times but the following critical/major findings remain" + list of findings
    → Wait for user decision (continue / abort)
```

### Application in Breezing Mode

In Breezing mode, **Lead** runs the review loop (see Phase B above):

1. Worker implements and commits in the worktree → returns result to Lead.
2. Lead reviews with Codex exec (preferred) / Reviewer agent (fallback).
3. REQUEST_CHANGES → Lead sends fix instructions to Worker via SendMessage → Worker amends.
4. After fix, re-review (up to `MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3` times).
5. APPROVE → Lead cherry-picks into trunk (default branch) → updates Plans.md to `cc:Done [{hash}]`.

## Completion Report Format

A visual summary automatically output when a task is complete (`cc:Done` + after commit).
Designed to communicate the changes and their impact to non-specialists as well.

### Template

```
┌─────────────────────────────────────────────┐
│  ✓ Task {N} Done: {task name}               │
├─────────────────────────────────────────────┤
│                                              │
│  ■ What was done                             │
│    • {change 1}                              │
│    • {change 2}                              │
│                                              │
│  ■ What changed                              │
│    Before: {old behavior}                    │
│    After:  {new behavior}                    │
│                                              │
│  ■ Changed files ({N} files)                 │
│    {file path 1}                             │
│    {file path 2}                             │
│                                              │
│  ■ Remaining work                            │
│    • Task {X} ({status}): {content}  ← Plans.md  │
│    • Task {Y} ({status}): {content}  ← Plans.md  │
│    ({M} incomplete tasks in Plans.md)        │
│                                              │
│  commit: {hash} | review: {APPROVE}          │
└─────────────────────────────────────────────┘
```

### Generation Rules

1. **What was done**: Auto-extracted from `git diff --stat HEAD~1` and commit message. Minimize technical jargon; start with a verb.
2. **What changed**: Infer Before/After from the task's "Content" and "DoD". Emphasize changes to the user experience.
3. **Changed files**: Retrieved from `git diff --name-only HEAD~1`. If more than 5 files, abbreviate and show the count.
4. **Remaining work**: List `cc:TODO` / `cc:WIP` tasks in Plans.md. Explicitly indicate whether they are recorded in Plans.md.
5. **Review**: Display the review result (APPROVE / REQUEST_CHANGES → APPROVE).

### Reporting in Parallel Mode

- **1 task** (when `--parallel` is forced): Use the Solo template.
- **Multiple tasks**: Use the Breezing aggregation template (see below).

### Reporting in Breezing Mode

Output collectively after all tasks are complete. List each task in abbreviated form (what was done + commit hash only),
then output an overall summary (total files changed + remaining work) at the end:

```
┌─────────────────────────────────────────────┐
│  ✓ Breezing Done: {N}/{M} tasks             │
├─────────────────────────────────────────────┤
│                                              │
│  1. ✓ {task name 1}           [{hash1}]     │
│  2. ✓ {task name 2}           [{hash2}]     │
│  3. ✓ {task name 3}           [{hash3}]     │
│                                              │
│  ■ Overall changes                           │
│    {N} files changed, {A} insertions(+),    │
│    {D} deletions(-)                         │
│                                              │
│  ■ Remaining work                            │
│    {K} incomplete tasks in Plans.md          │
│    • Task {X}: {content}                     │
│                                              │
└─────────────────────────────────────────────┘
```

## Related Skills

- `harness-plan` — Plan the tasks to execute
- `harness-sync` — Synchronize implementation with Plans.md
- `harness-review` — Review the implementation
- `harness-release` — Version bump and release
