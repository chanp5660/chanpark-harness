---
name: breezing
description: "Team execution mode — backward-compatible alias for harness-work with team orchestration. Composer/composer 2.5 maps to the cursor backend."
kind: workflow
purpose: "Wrap harness-work with team execution orchestration"
trigger: "breezing, team execution, do everything, composer, composer 2.5, composer mode"
shape: wrap
role: orchestrator
base: harness-work
pair: harness-review
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "Task", "WebSearch", "Monitor"]
argument-hint: "[all|N-M|--codex|--cursor|--reviewer-only|--parallel N|--no-commit|--no-discuss|--auto-mode]"
user-invocable: true
---

# Breezing — Team Execution Mode

> **Backward-compatible alias**: Runs `harness-work` in team execution mode.

## Narration Rules (UX Contract)

The enemy is **verbosity**, not progress reporting. **At startup, briefly state the execution plan before beginning execution.** Clear progress reporting is welcome. Only redundant repetition and empty preambles are prohibited.

### Required output at startup (banner + plan, 5 lines or fewer)

In the first response, show what will be done and in what order before making any tool calls:

```
🚀 cursor / composer-2.5-fast / feat/hah-11-golden-rule-lint / Reviewer
Next steps:
1. Resolve backend/model
2. Delegate diff review to composer (read-only)
3. Summarize verdict in 3-5 lines → update Plans.md
```

Banner line (`🚀 <backend> / <model> / <branch> / <task>`) + plan in 2-4 lines. Output within 1 second, then proceed immediately to Step 1.

### Progress reporting is allowed (within readable bounds)

- One-line status for each step start and completion (`✓ backend=cursor / model=composer-2.5-fast`)
- Intermediate results needed for decisions (pre-check key points, resolved model, detected branch, etc.)
- One-line reason for each branching decision (e.g., "Reviewer-only delegation: Worker already completed on separate track")

### Prohibited (= verbosity)

- **Restating the same fact twice**: Do not re-explain something already stated
- **Empty preambles**: Lines like "Checking usage" that are self-evident from the tool call
- **3+ line backstory**: Long preambles that delay the conclusion. If context is needed, compress to 1 line
- **★ Insight blocks during startup sequence**: Insights appear only once in the final report

Violation examples (verbose):
```
× "composer 2.5 mode" = cursor backend delegating to Composer, right? (restating the interpretation)
× "Since the Reviewer stopped last time, routing to a separate track makes sense." (3+ line backstory)
× "Checking usage" → bash → "It can be called." (empty preamble + restating the same fact)
```

Correct examples (concise + plan stated):
```
🚀 cursor / composer-2.5-fast / feat/hah-11-golden-rule-lint / Reviewer
Next: resolve backend → delegate diff review to composer (read-only) → summarize verdict
```

## Quick Reference

```bash
/breezing                       # Ask for scope (claude backend)
/breezing all                   # Run all tasks (claude backend)
/breezing 3-6                   # Run tasks 3–6
/breezing --codex all           # Delegate all tasks via Codex CLI
/breezing --cursor              # cursor backend lean path (--no-discuss all by default)
/breezing --cursor --reviewer-only  # Delegate Reviewer only to cursor (Worker already complete on separate track)
/breezing composer 2.5 all      # Natural language trigger: treated as cursor backend
/breezing --parallel 2 all      # Run all tasks with 2-way parallelism
/breezing --no-discuss all      # Skip planning discussion, run all tasks
/breezing --auto-mode all       # Attempt Auto Mode rollout on compatible parent session
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `all` | Target all incomplete tasks | - |
| `N` or `N-M` | Specify task number or range | - |
| `--codex` | Delegate implementation via Codex CLI | false |
| `--cursor` | cursor backend lean path (equivalent to `HARNESS_IMPL_BACKEND=cursor`). Skips Worker agent spawn / self_review / sprint-contract 3-stage chain / Phase 0, and begins delegation within 3 seconds of startup | false |
| `--reviewer-only` | Delegate only the Reviewer to an independent track (assumes Worker implementation is already complete). Combine with `--cursor` to route to Composer | false |
| `--parallel N` | Number of parallel Implementers | auto |
| `--no-commit` | Suppress automatic commits | false |
| `--no-discuss` | Skip planning discussion | true when `--cursor` |
| `--auto-mode` | Explicitly request Auto Mode rollout on the harness side. Distinct from `--enable-auto-mode` which became unnecessary in CC 2.1.111 | false |

## Natural Language Backend Triggers

`composer` / `Composer` / `composer 2.5` / `composer mode` are officially treated as triggers for the `cursor backend`.
This is equivalent intent to `--cursor`, and Lead resolves the backend via `resolve-impl-backend.sh`.
At resolution, pass as an explicit override `--backend cursor`, taking priority over env / project / user file / default.

| Input example | Interpretation | Execution path |
|---|---|---|
| `composer 2.5` | `cursor backend` | Lead → `cursor-companion.sh task --write --workspace <wt>` |
| `composer, run everything` | `cursor backend` | Lead → `cursor-companion.sh task --write --workspace <wt>` |
| `composer mode` | `cursor backend` | Lead → `cursor-companion.sh task --write --workspace <wt>` |

`composer` is not an additional agent spawned inside the Claude Worker.
Following the non-`claude` backend topology, Lead calls `cursor-companion.sh` directly without interposing a Worker agent.

> **CC 2.1.111 note**:
> In Opus 4.7, `/effort xhigh` can be used literally.
> Built-in `/ultrareview` should only be added when explicitly requested; it does not replace the default review.

> **Long-session recommendation (CC 2.1.108+)**:
> If the session is expected to exceed 30 minutes, after resolving the plugin bundle root, run
> `bash "${HARNESS_PLUGIN_ROOT}/scripts/enable-1h-cache.sh"` to opt in to 1-hour prompt cache.
> This script appends `export ENABLE_PROMPT_CACHING_1H=1` to `env.local` (idempotent).
> With the default 5-minute TTL cache, sessions exceeding 1 hour in breezing can accumulate cache misses
> and increase input token costs by up to 12×, so opt in explicitly for long team runs.
> Codex CLI child processes (`scripts/codex-companion.sh task --write`, etc.) normally inherit the env and
> read `ENABLE_PROMPT_CACHING_1H`, but if `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` is active, a shell wrapper
> that explicitly maintains the export is required. See
> [`docs/long-running-harness.md`](../../docs/long-running-harness.md) for details.

## Execution

**This skill delegates to `harness-work`.** Run `harness-work` with the following settings:

1. **Pass arguments through to `harness-work` unchanged**
2. **Enforce team execution mode** — Three-way separation: Lead → Worker spawn → Reviewer spawn
3. **Lead focuses solely on delegation** — does not write code directly
4. **Auto Mode is opt-in** — `--auto-mode` is accepted as a rollout flag for compatible parent sessions
5. **Advisor only when needed** — Lead calls the Advisor only when Worker returns `advisor-request.v1`

### Differences from `harness-work`

| Feature | `harness-work` | `breezing` (this skill) |
|------|-----------------|------------------------|
| Parallelism | Automatic partitioning as needed | **Role separation: Lead / Worker / Reviewer** |
| Lead's role | Coordinate + implement | **Delegate (coordination only)** |
| Review | Lead self-review | **Independent Reviewer** |
| Default scope | Next task | **All tasks** |

### Team Composition

| Role | Agent Type | Mode | Responsibility |
|------|-----------|------|------|
| Lead | (self) | - | Coordination, direction, task distribution |
| Worker ×N | `claude-code-harness:worker` | `bypassPermissions` (current) / Auto Mode (follow-up)* | Implementation |
| Advisor | `claude-code-harness:advisor` | Read-only | Policy advice (`PLAN` / `CORRECTION` / `STOP`) |
| Reviewer | `claude-code-harness:reviewer` | `bypassPermissions` (current) / Auto Mode (follow-up)* | Independent review |

> *If the parent session or frontmatter specifies `bypassPermissions`, that takes precedence. Distribution templates currently use `bypassPermissions`, so Auto Mode is a follow-up rollout target and not the default behavior.

### Codex Mode (`--codex`)

Mode that delegates all implementation to Codex CLI via the official plugin `codex-plugin-cc`:

```bash
# Delegate task (write-enabled)
bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" task --write "task content"

# Via stdin (for large prompts)
CODEX_PROMPT=$(mktemp /tmp/codex-prompt-XXXXXX.md)
# Write out task content
cat "$CODEX_PROMPT" | bash "${HARNESS_PLUGIN_ROOT}/scripts/codex-companion.sh" task --write
rm -f "$CODEX_PROMPT"
```

### Execution Backend (persistent)

Setting `HARNESS_IMPL_BACKEND=cursor` (via `bash "${HARNESS_PLUGIN_ROOT}/scripts/set-impl-backend.sh" cursor`)
makes cursor the default worker backend without per-run flags. The review / advisor roles remain fixed to Opus.
The authoritative reference for backend selection (precedence, role-scope, self_review skip, cursor banner) is
the "Execution Backend Selection" section in `harness-work`.

The Cursor Backend Fast Path below is a separate axis that enables the same lean path via a per-run flag (`--cursor`); read both sections together.

### Cursor Backend Fast Path (`--cursor` / lean mode)

Active when `--cursor` is specified or when env `HARNESS_IMPL_BACKEND=cursor` is set. Lead calls `cursor-companion.sh` directly without interposing a Worker layer (Phase 85 SSOT, `.claude/rules/cursor-cli-only.md` Topology section).

#### Steps removed (savings vs. claude backend)

| Step | Reason removed | Time saved |
|---|---|---|
| `claude-code-harness:worker` agent spawn | cursor backend has no Worker intermediary | 5-30s |
| self_review 5-item gate | `worker-report.v1` is not generated with cursor, so unnecessary | 10-60s × retry |
| sprint-contract 3-stage chain (generate→enrich→ensure) | No contract needed if no Worker contract | 2-5s × N |
| Phase 0 Q1-Q3 interactive | `--no-discuss all` by default (Lead reads Plans/Depends directly) | 15-30s |
| Effort scoring | No ultrathink injection needed for cursor backend | 0.5-1s × N |
| Plans.md re-parse (per task) | In-session cache (short-circuits on mtime+hash) | 3-8s |

Total: baseline `15-35s` → target `3-7s` reduction in time to first cursor delegation for task 1.

#### Default flow (cursor backend)

1. **Banner + execution plan** (`🚀 cursor / <model> / <branch> / <task>` + 2-4 next steps, 5 lines or fewer, within 1 second)
2. **1 bash for parallel pre-check**: `git branch --show-current` + `cat VERSION` + `Plans.md tail` + `cursor-agent --version`
3. **1 bash for resolve**: `bash "${HARNESS_PLUGIN_ROOT}/scripts/resolve-impl-backend.sh"` + `bash "${HARNESS_PLUGIN_ROOT}/scripts/model-routing.sh" --host cursor --role worker --field model`
4. **Delegate immediately**: `bash "${HARNESS_PLUGIN_ROOT}/scripts/cursor-companion.sh" task --write --workspace <wt> "<task>"`
5. Lead diff-reviews cursor output → cherry-pick → update Plans.md `cc:done [hash]`

#### Reviewer-only mode (`--cursor --reviewer-only`) — read = lean

Worker implementation is already complete (finished on a separate track via claude / Codex), and only the Reviewer needs to run on an independent track (Composer). This is a read-only delegation, so **no worktree, no cherry-pick, no Lead diff review** required:

1. Banner + plan: `🚀 cursor / composer-2.5-fast / review` + "Next: delegate diff review to composer → summarize verdict"
2. `bash "${HARNESS_PLUGIN_ROOT}/scripts/cursor-companion.sh" task "diff review: <base_ref>..HEAD"` — **no `--write` or `--workspace`**
   - Without `--write`, companion defaults to `--mode ask` (hard read-only stop)
   - On the cursor side, file writes and command execution are disabled; worktree isolation is not needed
3. Lead interprets cursor output (REQUEST_CHANGES / APPROVE equivalent) and stores it as advisory in `dual_review.cursor_verdict`
4. **Primary verdict comes from the Opus reviewer.** cursor alone cannot confirm APPROVE (consistent with the immutable rule in harness-work/SKILL.md: "the backend that implemented the work must not review its own output")
5. If APPROVE, Lead updates Plans.md `cc:done [hash]`

Items omitted in read mode: dedicated `.git` worktree / Lead diff review / cherry-pick / `worker-report.v1` / self_review 5-item gate.
Items still required in read mode: `.cursorignore` / egress allowlist (`*.cursor.sh`) / permissions.json (best-effort). See `.claude/rules/cursor-cli-only.md` "Read mode delegation (lean path)" section for details.

**Use cases**:
- Escape route when the Reviewer is stopped by Anthropic-side server rate limits
- Worker complete; distribute only the Reviewer to a separate track
- Manual fallback when Codex review auth fails

#### Cursor adapter support claim

Cursor remains at the `internal-compatible` tier (Phase 87 / PR #174 promotion). A `supported` public claim continues to be gated until CI-gated workflow smoke requirements are met. The `--cursor` lean path does not promote the support tier.

Bootstrap route: `.cursor/AGENTS.md` + `.cursor-plugin/plugin.json`.

Verification:

```bash
bash tests/test-cursor-adapter-candidate.sh
bash tests/test-support-claim-wording.sh
```

## Flow Summary

```
breezing [scope] [--codex] [--parallel N] [--no-discuss] [--auto-mode]
    │
    ↓ Load harness-work with team mode
    │
Phase 0: Planning Discussion (skipped with --no-discuss)
Phase A: Pre-delegate (team initialization)
Phase B: Delegate (Worker implementation + Advisor when needed + Reviewer review)
Phase C: Post-delegate (integration verification + Plans.md update + commit)
```

## Advisor Protocol

Workers do not spawn additional generic subagents.
When unsure, return only a structured JSON consultation request; Lead calls the Advisor.

1. Worker → `advisor-request.v1`
2. Lead → Advisor
3. Advisor → `advisor-response.v1`
4. Lead → returns advice to the same Worker to continue
5. Reviewer sees only the final deliverable

Consultation conditions are aligned with loop / solo:

- Before the first execution of a high-risk task (`needs-spike` / `security-sensitive` / `state-migration`)
- After the same root cause has failed twice in a row
- Just before returning `PIVOT_REQUIRED` due to a plateau
- Same `trigger_hash` only once. Maximum 3 consultations per task

### Progress Feed (progress notifications during Phase B)

Lead outputs progress in the following format after each Worker task completion:

```
📊 Progress: Task {completed}/{total} complete — "{task_subject}"
```

**Output examples**:
```
📊 Progress: Task 1/5 complete — "Add failed task re-ticketing to harness-work"
📊 Progress: Task 2/5 complete — "Add --snapshot to harness-sync"
📊 Progress: Task 3/5 complete — "Add progress feed to breezing"
```

> **Design intent**: breezing often runs for extended periods.
> This allows users to glance at the terminal and immediately know how far execution has progressed.
> The task-completed.sh hook outputs equivalent information via systemMessage, complementing Lead's output.

### Silence Policy (notification management for long runs)

In Codex `0.123.0` realtime handoff, background agents receive transcript deltas and can explicitly go silent when not needed.
Breezing's progress feed is aligned with this premise, limiting notifications to "meaningful milestones".

Report:

- Task completion, blocked, validation failure, review `REQUEST_CHANGES`
- Advisor `PLAN` / `CORRECTION` / `STOP`
- Reviewer `APPROVE` / `REQUEST_CHANGES`
- advisor / reviewer drift, plateau, contract readiness failure
- Summary when the user explicitly requests status

Stay silent for:

- Receipt of a transcript delta with no change to verdict or status
- Fine-grained tool stdout increments that are sufficiently captured in the log
- Heartbeats while parallel Workers are waiting

Baseline frequency: once per task completion.
Rather than increasing heartbeats for reassurance, separate responsibility to status / log / drift detection.
However, do not silence: unanswered Advisor requests, pending Reviewer results, or warnings immediately before a plateau.

### Monitor Tool Usage Guide (CC 2.1.98+)

When monitoring long-running commands, use the **Monitor tool** rather than polling (periodically reading the tail of a file with Read). Monitor delivers each stdout line from a background process as a sequential notification to Lead, providing lower latency and lower token consumption than polling.

**Application examples**:
- Monitoring `go test ./... -v` progress during execution
- Tracking GitHub Actions progress with `gh run watch`
- Immediate build error detection for `npm run build --watch` / `vite build --watch`
- Detecting Codex job completion with `codex-companion.sh status <job-id>`
- Tracking deployment logs with `docker-compose logs -f` / `kubectl logs -f`

**Decision criteria**:

| Target | Use Monitor? | Reason |
|---|---|---|
| Agent (Worker / Reviewer) completion monitoring | Not needed | The Agent layer handles its own completion notifications |
| Shell process launched with `run_in_background: true` | Recommended | Each stdout line is delivered as a sequential notification |
| Short one-shot commands (single `go test` run) | Not needed | Standard Bash tool execution is sufficient |
| Long-running tail / watch / stream commands | Recommended | More efficient than polling |

**Typical pattern in Breezing Lead**:

```
Lead:
  Task(Worker1, ...)           ← Waiting for Agent completion (Monitor not needed)
  Task(Worker2, ...)           ← Same
  Bash(run_in_background, "gh run watch --exit-status")
  Monitor(tailCommand="...")   ← Immediate CI failure detection → correction instructions to Worker
```

This allows Lead to improve reaction speed in the "Worker complete → CI failure detected → correction instructions" cycle.

### Review Policy (unified across all modes)

Even in breezing mode, review follows the unified policy of **Codex exec preferred → internal Reviewer fallback**.
See the "Review Loop" section in `harness-work` for details.

- Worker implements and commits inside worktree → returns `worker-report.v1` (self_review 5 items) to Lead
- **self_review gate (before Reviewer spawn)**: Lead mechanically verifies `self_review[].verified` and `evidence`. If even one item has `verified:false` or `evidence:""`, Lead auto-returns to Worker without spawning Reviewer (maximum 2 times within the same session; escalate on the 3rd)
- Lead reviews via Codex exec (120s timeout, fallback: Reviewer agent)
- REQUEST_CHANGES → Lead sends correction instructions to Worker via SendMessage; Worker amends (up to `MAX_REVIEWS` times. `MAX_REVIEWS = read_contract(contract_path, ".review.max_iterations") or 3`)
- APPROVE → **Lead** cherry-picks to main → updates Plans.md to `cc:done [{hash}]`

### Completion Report (Phase C — generated by Lead)

After all tasks complete, **Lead** generates a rich completion report following these steps:

1. Collect all cherry-pick commits with `git log --oneline {base_ref}..HEAD`
2. Get overall change scale with `git diff --stat {base_ref}..HEAD`
3. Extract remaining `cc:TODO` / `cc:WIP` tasks from Plans.md
4. Output following the Breezing template in the "Completion Report Format" section of `harness-work`

> **Generated by Lead**, not Workers or hooks. Lead reads git + Plans.md in Phase C to generate the report.

### Phase 0: Planning Discussion (structured 3-question check)

Before executing all tasks, verify plan health with the following 3 questions.
All are skipped when `--no-discuss` is specified.

**Q1. Scope confirmation**:
> "Running {{N}} tasks. Is the scope appropriate?"

If too many, propose filtering by priority (Required > Recommended > Optional).

**Q2. Dependency check** (only when Plans.md has a Depends column):
> "Task {{X}} depends on {{Y}}. Is the execution order correct?"

Read the Depends column and display the dependency chain. Error if circular dependency is detected.

**Q3. Risk flags** (only when `[needs-spike]` tasks exist):
> "Task {{Z}} is marked `[needs-spike]`. Run the spike first?"

If incomplete `[needs-spike]` tasks exist, confirm whether to run the spike first.

If all 3 questions pass, proceed to Phase A (designed to complete in 30 seconds total).

### Universal Violations Injection (learning propagation between Workers in a session)

Automatically injects universal gotchas accumulated by the Reviewer within the same `/breezing` run into the briefing header of the next Worker. **Valid within the same session only** (discarded at session end; not written to `session-memory`).

```python
# Initialize Lead process in-memory array at Phase A start
universal_violations = []  # List[str] — accumulated within this session

# Inject at the top of the briefing just before spawning a Worker in Phase B:
def build_worker_briefing(task, contract_path):
    header = ""
    if universal_violations:
        header = (
            "🚨 Universal violations detected in this session (do not repeat):\n"
            + "\n".join(f"- {v}" for v in universal_violations)
            + "\n\n"
        )
    return header + f"Task: {task.content}\nDoD: {task.DoD}\ncontract_path: {contract_path}\nmode: breezing"

# After Reviewer returns review-result.v1, Lead extracts only scope="universal" and accumulates:
for update in reviewer_result.memory_updates:
    # Backward compatible: strings are treated as task-specific → ignored
    if isinstance(update, str):
        continue
    if update.get("scope") == "universal":
        universal_violations.append(update["text"])
```

**Policy**: To avoid over-engineering, do not persist to `session-memory` or `decisions.md`. Retain only in Lead process in-memory array and discard at the end of the `/breezing` session (per the policy in issue #87).

### Dependency-graph-based task assignment

When Plans.md has a Depends column (v2 format), execute tasks following the dependency graph:

1. Execute **tasks with Depends = `-`** first. If multiple independent tasks exist, parallel spawn is possible
2. After each Worker completes, Lead reviews → cherry-picks (see harness-work Phase B)
3. Once a dependency task is cherry-picked to main, execute the tasks that depended on it next
4. Repeat until all tasks are complete

> **Note**: "Worker complete → review → cherry-pick" for each task is sequential.
> Parallelization applies only to the Worker spawn phase for independent tasks (Depends = `-`).

## Codex Native Orchestration

Codex uses native subagents.
Representative control primitives are `spawn_agent`, `wait`, `send_input`, `resume_agent`, `close_agent`.

> **Claude Code vs Codex communication API** (SSOT: API mapping table in `team-composition.md`):
> - Claude Code: `SendMessage(to: agentId, message: "...")` to send correction instructions to Worker
> - Codex: `resume_agent(agent_id)` to resume Worker → `send_input(agent_id, "...")` to send instructions
>
> Pseudo-code in harness-work is written in Claude Code syntax. Translate to the above when running in a Codex environment.

## Related Skills

- `harness-work` — From single tasks to team execution (core)
- `harness-sync` — Progress sync
- `harness-review` — Code review (auto-invoked within breezing)
