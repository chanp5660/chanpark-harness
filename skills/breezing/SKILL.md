---
name: breezing
description: "Team execution mode — backward-compatible alias for harness-work with team orchestration."
kind: workflow
purpose: "Wrap harness-work with team execution orchestration"
trigger: "breezing, team execution, do everything"
shape: wrap
role: orchestrator
base: harness-work
pair: harness-review
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Write", "Edit", "Bash", "Grep", "Glob", "Task", "WebSearch", "Monitor"]
argument-hint: "[all|N-M|--reviewer-only|--parallel N|--no-commit|--no-discuss|--auto-mode]"
user-invocable: true
---

# Breezing — Team Execution Mode

> **Backward-compatible alias**: Runs `harness-work` in team execution mode.

## Narration Rules (UX Contract)

The enemy is **verbosity**, not progress reporting. **At startup, briefly state the execution plan before beginning execution.** Clear progress reporting is welcome. Only redundant repetition and empty preambles are prohibited.

### Required output at startup (banner + plan, 5 lines or fewer)

In the first response, show what will be done and in what order before making any tool calls:

```
🚀 claude / <model> / feat/hah-11-golden-rule-lint / Reviewer
Next steps:
1. Resolve model
2. Delegate diff review to Worker (read-only)
3. Summarize verdict in 3-5 lines → update Plans.md
```

Banner line (`🚀 claude / <model> / <branch> / <task>`) + plan in 2-4 lines. Output within 1 second, then proceed immediately to Step 1.

### Progress reporting is allowed (within readable bounds)

- One-line status for each step start and completion (`✓ model=claude-opus / branch=feat/hah-11`)
- Intermediate results needed for decisions (pre-check key points, resolved model, detected branch, etc.)
- One-line reason for each branching decision (e.g., "Reviewer-only delegation: Worker already completed on separate track")

### Prohibited (= verbosity)

- **Restating the same fact twice**: Do not re-explain something already stated
- **Empty preambles**: Lines like "Checking usage" that are self-evident from the tool call
- **3+ line backstory**: Long preambles that delay the conclusion. If context is needed, compress to 1 line
- **★ Insight blocks during startup sequence**: Insights appear only once in the final report

Violation examples (verbose):
```
× "Since the Reviewer stopped last time, routing to a separate track makes sense." (3+ line backstory)
× "Checking usage" → bash → "It can be called." (empty preamble + restating the same fact)
```

Correct examples (concise + plan stated):
```
🚀 claude / opus / feat/hah-11-golden-rule-lint / Reviewer
Next: resolve model → delegate diff review to Worker (read-only) → summarize verdict
```

## Quick Reference

```bash
/breezing                       # Ask for scope
/breezing all                   # Run all tasks
/breezing 3-6                   # Run tasks 3–6
/breezing --reviewer-only       # Delegate Reviewer only (Worker already complete on separate track)
/breezing --parallel 2 all      # Run all tasks with 2-way parallelism
/breezing --no-discuss all      # Skip planning discussion, run all tasks
/breezing --auto-mode all       # Attempt Auto Mode rollout on compatible parent session
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `all` | Target all incomplete tasks | - |
| `N` or `N-M` | Specify task number or range | - |
| `--reviewer-only` | Delegate only the Reviewer to an independent track (assumes Worker implementation is already complete) | false |
| `--parallel N` | Number of parallel Implementers | auto |
| `--no-commit` | Suppress automatic commits | false |
| `--no-discuss` | Skip planning discussion | false |
| `--auto-mode` | Explicitly request Auto Mode rollout on the harness side. Distinct from `--enable-auto-mode` which became unnecessary in CC 2.1.111 | false |

> **CC 2.1.111 note**:
> In Opus 4.7, `/effort xhigh` can be used literally.
> Built-in `/ultrareview` should only be added when explicitly requested; it does not replace the default review.

> **Long-session recommendation (CC 2.1.108+)**:
> If the session is expected to exceed 30 minutes, after resolving the plugin bundle root, run
> `bash "${HARNESS_PLUGIN_ROOT}/scripts/enable-1h-cache.sh"` to opt in to 1-hour prompt cache.
> This script appends `export ENABLE_PROMPT_CACHING_1H=1` to `env.local` (idempotent).
> With the default 5-minute TTL cache, sessions exceeding 1 hour in breezing can accumulate cache misses
> and increase input token costs by up to 12×, so opt in explicitly for long team runs.
> See [`docs/long-running-harness.md`](../../docs/long-running-harness.md) for details.

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
| Worker ×N | `chanpark-harness:worker` | `bypassPermissions` (current) / Auto Mode (follow-up)* | Implementation |
| Advisor | `chanpark-harness:advisor` | Read-only | Policy advice (`PLAN` / `CORRECTION` / `STOP`) |
| Reviewer | `chanpark-harness:reviewer` | `bypassPermissions` (current) / Auto Mode (follow-up)* | Independent review |

> *If the parent session or frontmatter specifies `bypassPermissions`, that takes precedence. Distribution templates currently use `bypassPermissions`, so Auto Mode is a follow-up rollout target and not the default behavior.

### Reviewer-only mode (`--reviewer-only`)

Worker implementation is already complete (finished on a separate track), and only the Reviewer needs to run on an independent track. This is a read-only delegation, so **no worktree, no cherry-pick, no Lead diff review** required:

1. Banner + plan: `🚀 claude / opus / review` + "Next: delegate diff review to Reviewer → summarize verdict"
2. Lead spawns a `chanpark-harness:reviewer` agent for `"diff review: <base_ref>..HEAD"`
3. Lead interprets Reviewer output (REQUEST_CHANGES / APPROVE) 
4. If APPROVE, Lead updates Plans.md `cc:done [hash]`

**Use cases**:
- Worker complete; distribute only the Reviewer to a separate track
- Escape route when parallel execution left Reviewer work pending

## Flow Summary

```
breezing [scope] [--parallel N] [--no-discuss] [--auto-mode]
    │
    ↓ Load harness-work with team mode
    │
Phase 0: Planning Discussion (skipped with --no-discuss)
Phase A: Pre-delegate (team initialization)
Phase B: Delegate (Worker implementation + Advisor when needed + Reviewer review)
Phase C: Post-delegate (integration verification + Plans.md update + commit)
```

## Advisor Protocol

See `harness-work` Advisor Protocol (common to all modes).

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

Breezing limits notifications to "meaningful milestones" to avoid noise during long runs.

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

### Review Policy

Review follows the unified policy in `harness-work` — see the "Review Loop" and "Application in Breezing Mode" sections.

### Completion Report (Phase C — generated by Lead)

After all tasks complete, **Lead** generates a rich completion report following these steps:

1. Collect all cherry-pick commits with `git log --oneline {base_ref}..HEAD`
2. Get overall change scale with `git diff --stat {base_ref}..HEAD`
3. Extract remaining `cc:TODO` / `cc:WIP` tasks from Plans.md
4. Output following the Breezing template in the "Completion Report Format" section of `harness-work`

> **Generated by Lead**, not Workers or hooks. Lead reads git + Plans.md in Phase C to generate the report.

### Phase 0: Planning Discussion

Three-question check (Q1 scope / Q2 dependencies / Q3 risk flags) run before Phase A; skipped with `--no-discuss`. See `harness-work` Breezing Mode for the full Q1/Q2/Q3 prompts.

### Universal Violations Injection

Reviewer-accumulated gotchas are automatically injected into subsequent Worker briefings within the same session. Managed by `harness-work` Phase B; session-only, discarded at session end (policy: issue #87).

### Dependency-graph-based task assignment

Tasks with a Depends column are executed in graph order (independent tasks first, parallel spawn possible). See `harness-work` Phase A/B for the full algorithm.

## Related Skills

- `harness-work` — From single tasks to team execution (core)
- `harness-sync` — Progress sync
- `harness-review` — Code review (auto-invoked within breezing)
