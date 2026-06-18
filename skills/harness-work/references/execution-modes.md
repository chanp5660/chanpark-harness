# Execution Modes

`harness-work` chooses the lightest execution mode that still preserves review
and validation.

## Shared Preflight

1. Read `Plans.md` and identify the selected task set.
2. Stop if the task table lacks `Task`, `DoD`, `Depends`, or `Status`.
3. Check whether a project spec SSOT exists when product behavior can drift.
   Prefer existing project-level docs, then `docs/spec/00-project-spec.md`.
4. If the task changes product behavior, API, data model, permissions, billing,
   integrations, or tenant boundaries and no stable spec exists, create or
   update the spec before implementation.
5. Skip spec creation only for mechanical work such as typo, formatting,
   dependency bump, docs-only, or behavior-preserving refactor tasks. Record
   the skip reason in the task context or sprint contract.
6. Resolve helper scripts through `HARNESS_PLUGIN_ROOT`, not the caller
   project's `scripts/` directory.
7. Mark only the selected task as `cc:WIP`.
8. Generate and approve a sprint contract before implementation when the task
   needs reviewable DoD checks.

## Solo

Use for one task. The parent session implements directly, validates, runs the
review loop, commits unless `--no-commit` is set, and marks `Plans.md`
`cc:Done [hash]`.

## Parallel

Use for two or three independent tasks, or when `--parallel N` is explicit.
Lead spawns a Worker agent per task. Workers may use isolated worktrees when
file ownership can conflict. Lead still owns final integration and status
updates.

## Breezing

Use for four or more tasks, or when `--breezing` is explicit. Lead coordinates
Workers, Advisor, and Reviewer while preserving the implementation/review
boundary. Lead uses the Claude Code `Agent` / `SendMessage` API to orchestrate
Workers.
