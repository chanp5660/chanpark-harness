# chanpark-harness — Usage Guide

A practical, example-driven reference for the day-to-day workflow. This assumes the plugin
is already installed (see **[INSTALL.md](INSTALL.md)** if not). For a short overview, see the
[README](../README.md).

All skills are namespaced under the plugin, e.g. `/chanpark-harness:harness-plan`. Every
command can also be triggered in natural language ("make a plan", "run everything"), but the
slash form with explicit arguments gives you the most precise control.

---

## TL;DR

The plugin bundles **plan → work → review → sync** into one loop. The single source of
truth (SoT) for all work is one file at the project root — **`Plans.md`** — and every task is
tracked with English status markers.

| Marker | Meaning |
|--------|---------|
| `cc:todo` | Not started |
| `cc:wip` | In progress |
| `cc:done` | Worker finished (usually with a commit hash: `cc:done [a1b2c3d]`) |
| `cc:blocked` | Blocked (reason required) |
| `pm:requested` / `pm:approved` | PM requested / PM approved |

> Markers are written lowercase in English and matched case-insensitively by the binary.

A typical day:

```text
/chanpark-harness:harness-plan create    # 1) decide what to build → write Plans.md
/chanpark-harness:harness-work all       # 2) execute the tasks in Plans.md
/chanpark-harness:harness-review         # 3) review the result
/chanpark-harness:harness-sync           # 4) reconcile implementation with Plans.md + retro
```

---

## 1. `harness-plan` — planning

**Role:** turn an idea/requirement into an actionable `Plans.md` task list. Also manages
progress state.

### Subcommands

| Input | Action |
|-------|--------|
| `harness-plan create` | New plan (questions → research → task breakdown → write Plans.md) |
| `harness-plan add <name>: <desc> [--phase N]` | Add a task (as `cc:todo`) |
| `harness-plan update <task#> [wip\|done\|blocked]` | Change a status marker |
| `harness-plan sync` | Reconcile implementation with Plans.md (= `harness-sync`) |
| `harness-plan list` | List multiple named plans |
| `harness-plan switch <name>` | Switch the active plan |

### Example A — plan a new feature

```text
/chanpark-harness:harness-plan create
```

Asks "what are we building?" in up to 3 questions, optionally consults web research /
existing specs / memory, runs a priority matrix (Required / Recommended / Optional / Reject),
and writes `Plans.md`. For non-trivial plans it adds Product / Architecture / Security / QA /
Skeptic validation passes.

When `create` finishes it also tells you the **next-session launch command**, e.g.:

```text
New session launch command: claude
First input after launch: /chanpark-harness:breezing all
Best suited for: Phase 1 has several tasks, so a team run is natural
```

### Example B — add a single task

```text
/chanpark-harness:harness-plan add login-ratelimit: add a 5-requests/min-per-IP limit --phase 2
```

### Example C — mark a task done (manual)

```text
/chanpark-harness:harness-plan update 2.3 done
```

`harness-work` updates markers automatically, so manual `update` is mostly for corrections.

### Make every DoD verifiable

Each task in Plans.md gets a one-line **DoD (Definition of Done)** that must be answerable
Yes/No.

- ❌ "works fine"
- ✅ "all of `pytest tests/auth/` passes, 0 lint errors"

### TDD tags (optional)

- `[tdd:required]` — force writing a failing test first
- `[tdd:skip:docs-only]` — skip TDD with a stated reason

---

## 2. `harness-work` — execution

**Role:** actually implement the tasks in `Plans.md`. The execution mode is chosen
automatically by task count.

### Automatic mode selection (when you pass no flag)

| Target task count | Auto mode | Why |
|-------------------|-----------|-----|
| 1 | **Solo** | Direct implementation is fastest |
| 2–3 | **Parallel** | Worker isolation starts to pay off |
| 4+ | **Breezing** | Lead orchestration + parallel Workers + a separate independent Reviewer |

### Common usage

| Input | Action |
|-------|--------|
| `harness-work` | "How far should I go?" scope dialog (next task / all / specific number) |
| `harness-work all` | All incomplete tasks, mode auto-selected by count |
| `harness-work 3` | Just task 3, immediately (Solo) |
| `harness-work 3-6` | 4 tasks → Breezing automatically |
| `harness-work --parallel 5` | Force parallel, 5 workers |
| `harness-work --breezing` | Force team run |
| `harness-work --resume latest` | Continue the previous session |
| `harness-work 3 --no-commit` | Suppress auto-commit |

### Example A — just the next task

```text
/chanpark-harness:harness-work 5
```

Infers the task's purpose/impact in one line → `cc:wip` → (if a test framework exists)
TDD Red → implement (Green) → auto-refactor (`/code-review --fix`) → auto-review → commit →
`cc:done [hash]` → prints a completion report.

### Example B — "do everything" (team run)

```text
/chanpark-harness:harness-work all
```

With 4+ tasks this runs Breezing. The Lead spawns Workers in dependency order, each task is
implemented in isolation in a worktree → Reviewer reviews → on APPROVE it is cherry-picked to
trunk.

### Things to know during execution

- **Auto-review is never skipped.** If any critical/major finding remains, the task is not
  marked `cc:done`.
- **Review pass criteria:** only minor/recommendation findings → always APPROVE. Even one
  critical/major → REQUEST_CHANGES → fix loop (default max 3 rounds).
- **Tests are never weakened to pass** (skill rule).
- **On CI failure:** if the same cause fails 3 times, the auto-fix loop stops and escalates to
  you.
- After a task completes, if tests/CI fail, a fix task like `26.1.fix` is proposed → add it to
  Plans.md with `approve fix 26.1.fix`.

### `breezing` is an alias

`/chanpark-harness:breezing all` = `/chanpark-harness:harness-work --breezing all`
(a backward-compatible alias for team-run mode).

---

## 3. `harness-loop` — long-running loop

**Role:** run a **long task** that needs waits over 5 minutes / session re-entry, re-entering
with **fresh context** on each wake-up. Internally calls `harness-work` (worker) for one task
per cycle. **1 cycle = 1 task completed.**

### Usage

| Input | Action |
|-------|--------|
| `harness-loop all` | Loop all incomplete tasks (default max 8 cycles) |
| `harness-loop all --max-cycles 3` | Stop after 3 cycles |
| `harness-loop 41.1-41.3 --pacing ci` | Range of tasks, CI pacing |
| `harness-loop all --pacing night` | Overnight batch (3600s interval) |
| `harness-loop status` | Check a running loop's status |
| `harness-loop stop` | Request the loop to stop |

### Pacing (wake-up interval)

| pacing | interval | use |
|--------|----------|-----|
| `worker` (default) | 270s | Re-enter right after a worker finishes (cache still warm under 5 min) |
| `ci` | 270s | Waiting on short CI jobs |
| `plateau` | 1200s | Retry after a stall is detected (20 min) |
| `night` | 3600s | Overnight long batch |

### Example — clear the backlog overnight

Launch a new session with a 1-hour prompt cache:

```bash
ENABLE_PROMPT_CACHING_1H=1 claude
```

First input:

```text
/chanpark-harness:harness-loop all --pacing night --max-cycles 8
```

After each task it records a checkpoint and schedules the next wake-up. It exits cleanly when
there are no incomplete tasks. On a plateau or an advisor STOP it stops immediately and
reports to you.

### Stop conditions

| Condition | Result |
|-----------|--------|
| `cycles >= max_cycles` | Normal stop (limit reached) |
| `PIVOT_REQUIRED` (stall) | Abnormal stop → asks for your decision |
| No incomplete tasks | Normal stop (all done) |

### loop vs work

- **One-off / short task** → `harness-work`
- **Waits over 5 min, re-entry, overnight batch** → `harness-loop`

---

## 4. `harness-review` — review

**Role:** review code/plan/scope from multiple angles (security, quality). Authoring and
review are **always separate passes** (no self-approve in the same context — a separate
reviewer owns the approval pass).

### Example

```text
/chanpark-harness:harness-review        # review the current diff
```

- critical/major → REQUEST_CHANGES
- only minor/recommendation → APPROVE

> Note: for a quick bug/cleanup review of the current working-tree diff there is also the
> repo-provided `/code-review`. `/code-review ultra` is a cloud multi-agent deep review (billed,
> user-triggered only).

---

## 5. `harness-sync` — synchronization

**Role:** compare the actual implementation (git status/log, agent trace) against `Plans.md`,
find drifted markers, and propose corrections. If any `cc:done` tasks exist, it automatically
runs a **retrospective** (records learnings about estimate accuracy, blocker patterns, scope
changes).

### Usage

| Input | Action |
|-------|--------|
| `harness-sync` | Reconcile progress + retro |
| `harness-sync --no-retro` | Skip the retro |
| `harness-sync --snapshot` | Snapshot |

### Example — "where am I right now?"

```text
/chanpark-harness:harness-sync
```

Or in natural language: "where am I?", "check progress". If you've been away a while, run
`/recap` then `/chanpark-harness:harness-sync`.

---

## 6. `maintenance` — cleanup & archiving

**Role:** clean up / archive a bloated `Plans.md`, `session-log.md`, old logs, and state
files. Use it when the auto-cleanup hook warns, or for periodic upkeep.

### Subcommands

| Input | Target |
|-------|--------|
| `maintenance plans` | Archive completed tasks in Plans.md |
| `maintenance session-log` | Split session-log.md by month |
| `maintenance logs` | Delete old files in `.claude/logs/` |
| `maintenance state` | Compact state files like `agent-trace.jsonl` |
| `maintenance all` | Run the 4 above in sequence |
| `... --dry-run` | Preview what would happen with no real changes |

### Example — preview safely, then clean

```text
/chanpark-harness:maintenance all --dry-run   # 1) see what would be cleaned first
/chanpark-harness:maintenance plans           # 2) actually run
```

### Cautions (built-in skill rules)

- Before destructive ops (archiving/deleting lines), confirm important info in
  Plans.md/session-log was promoted to the SSOT (decisions.md/patterns.md). If not, run
  `/chanpark-harness:memory sync` first.
- `cc:wip` and `pm:requested` tasks are **excluded** from archiving (in-progress and
  pending-approval work is left alone).
- The archive location is fixed at `.claude/memory/archive/`.
- CLAUDE.md is never auto-edited — only split suggestions are offered.

---

## 7. Auxiliary commands (often used together)

| Command | Use |
|---------|-----|
| `harness-setup` | Project init, tool/memory/CI setup |
| `harness-release` | Version bump + CHANGELOG + GitHub release automation |
| `memory` | Manage the SSOT (decisions.md/patterns.md), search/save memory |
| `harness-plan-brief` | (For non-engineers) pre-implementation plan preview HTML |
| `harness-progress` | (For non-engineers) progress dashboard HTML |
| `harness-accept` | (For non-engineers) ship/wait/reject acceptance decision HTML |

---

## 8. Recommended full workflow (copy-paste)

```text
# (1) plan
/chanpark-harness:harness-plan create
# → writes Plans.md, tells you the next launch command

# (2) execute — pick one
/chanpark-harness:harness-work all                 # normal: count-based auto mode
/chanpark-harness:harness-loop all --pacing night  # long/overnight: new session + ENABLE_PROMPT_CACHING_1H=1

# (3) review
/chanpark-harness:harness-review

# (4) sync + retro
/chanpark-harness:harness-sync

# (5) cleanup (periodic)
/chanpark-harness:maintenance all --dry-run
/chanpark-harness:maintenance all

# (6) release
/chanpark-harness:harness-release
```

---

## 9. Common sticking points

- **"Plans.md is in the old format" and it stops** → regenerate with
  `/chanpark-harness:harness-plan create` (needs DoD / Depends / Status columns).
- **Review keeps returning REQUEST_CHANGES** → a critical/major finding remains. After the
  default 3 fix rounds, if it persists it escalates.
- **Using multiple Plans.md** → don't switch plans within one run. Start fresh with an explicit
  `--plan <name>`.
- **Long sessions** → launch with `ENABLE_PROMPT_CACHING_1H=1 claude` to cut re-entry cost.
