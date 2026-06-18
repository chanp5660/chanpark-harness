---
name: harness-progress
description: "Generate a Progress Tracker HTML for non-engineer vibecoders to glance at session progress (cc:WIP / cc:TODO / cc:DONE counts, percentage, elapsed/estimated minutes, cost so far/estimate, drift alerts). Uses Plans.md as source of truth, renders a single-file HTML with auto-regeneration support. Use when user asks for progress overview, session status snapshot, dashboard, or says: progress tracker, progress check, progress board, dashboard. Do NOT load for: actual implementation, code review, release work."
allowed-tools: ["Read", "Write", "Bash"]
argument-hint: "[--out <path>] [--no-open]"
---

# Harness Progress Tracker

Phase 65.4 (Progress Tracker) — 3rd surface of the cognitive-load HTML triplet.
Following Plan Brief / Acceptance Demo, this is the **3rd HTML surface**, designed to let you **grasp the full picture of an in-progress session at a glance on a single page**.

## Quick Reference

| Input | Behavior |
|---|---|
| `/harness-progress` | Generate and open a progress snapshot HTML for the current project |
| `/harness-progress --no-open` | Generate only (do not open browser, for PostToolUse hook use) |
| `/harness-progress --out <path>` | Specify output path (default: `out/progress-snapshot.html`) |

## Mission

> Generate a single HTML page that lets a non-engineer vibecoder **understand in 3 seconds in a browser**:
> "How many tasks are done in this session, how far along are we, when will it finish, and how much has it cost?"

**Does**:
- Aggregate cc:TODO / cc:WIP / cc:DONE counts from Plans.md
- Calculate progress_pct (completion rate) (cc:DONE ÷ total tasks × 100)
- Display elapsed minutes / estimated total minutes / cost so-far / cost estimate
- Display drift alerts (populated from Phase 65.4.3 onward)

**Does NOT** (this cycle):
- Live updates via WebSocket / SSE (static HTML, updated by regeneration)
- Historical comparison of past sessions (separate axis in Phase 65.4.4)
- Cross-project view across other projects (independent from Phase 65.3)

## Schema: progress-snapshot.v1

Detailed spec: [schemas/progress-snapshot.v1.schema.json](${CLAUDE_SKILL_DIR}/schemas/progress-snapshot.v1.schema.json)

```yaml
schema:        progress-snapshot.v1
project:       <basename of git repo>
current_task:  <one-line summary of the first cc:WIP item, empty string if none>
progress_pct:  <integer 0-100, cc:DONE ÷ total tasks × 100 rounded>
todo_tasks:    [{number, title}]    ← cc:TODO items only
wip_tasks:     [{number, title}]    ← cc:WIP items only
done_tasks:    [{number, title, commit}]   ← cc:DONE [hash] items only, hash is 7 chars
elapsed_minutes:          <int, read from state file>
estimated_total_minutes:  <int, read from state file>
cost_so_far_usd:          <float, read from state file>
cost_estimate_usd:        <float, read from state file>
alerts:                    []   ← populated from Phase 65.4.3 onward
generated_at:             <ISO8601 UTC>
```

## Execution Flow

### Step 0: Get PROJECT_NAME

```bash
PROJECT_NAME="$(basename "$(git rev-parse --show-toplevel)" 2>/dev/null || echo "current")"
```

### Step 1: Assemble snapshot

```bash
SNAPSHOT_JSON="$(mktemp /tmp/progress-snapshot-XXXX.json)"
bash scripts/progress-snapshot.sh \
  --plans Plans.md \
  --project "$PROJECT_NAME" \
  > "$SNAPSHOT_JSON"
```

`scripts/progress-snapshot.sh` (implemented in Phase 65.4.1) parses Plans.md
and outputs JSON conforming to the `progress-snapshot.v1` schema.

### Step 2: Render HTML

```bash
OUT_PATH="${OUT_PATH:-out/progress-snapshot.html}"
mkdir -p "$(dirname "$OUT_PATH")"

bash scripts/render-html.sh \
  --template progress \
  --data "$SNAPSHOT_JSON" \
  --out "$OUT_PATH"
```

### Step 3: Open in browser

Execute only when the `--no-open` flag is **absent** (skip for background regeneration from PostToolUse hook):

```bash
bash scripts/plan-brief-open.sh --path "$OUT_PATH"
```

## Cross-project search (default OFF)

In Phase 65.4.4, a `--cross-project-group <name>` flag will be added. In this cycle (65.4.1), it is default OFF and aggregates the current project only.

## Failure modes

| Condition | Behavior |
|---|---|
| Plans.md not found | `progress-snapshot.sh` exits with exit 1 (clear error message) |
| Plans.md has no tasks | Snapshot generated with `progress_pct: 0` and empty arrays (HTML shows "no tasks") |
| State file (elapsed minutes etc.) not found | Fallback with `elapsed_minutes: 0`, `cost_so_far_usd: 0` (no warning) |
| `git` not installed / outside git repo | Fallback with `project: "current"` |

## Related

- `harness-plan-brief` (Phase 65.1.x) — 1st surface (pre-implementation briefing)
- `harness-accept` (Phase 65.2.x) — 2nd surface (acceptance decision)
- `harness-progress` (this skill, Phase 65.4.x) — 3rd surface (progress dashboard)
- Feature extensions in 65.4.2 (PostToolUse auto-regen), 65.4.3 (5 drift alert types), 65.4.4 (past decision lookup)
