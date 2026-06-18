---
name: harness-orchestration
description: "Show how much this session/project orchestrated across backends (Claude / Codex / Cursor). Renders an on-demand HTML scorecard + terminal summary from the orchestration ledger and lifetime totals. Use when the user asks to see orchestration usage, a backend scorecard, which backend was used, how much Codex/Cursor was used, lifetime totals, or wants something to show off. Do NOT load for: implementing tasks, reviews, planning, or release."
allowed-tools: ["Read", "Bash"]
disallowed-tools: ["Write", "Edit", "MultiEdit"]
argument-hint: "[--out <path>|--no-open|--terminal]"
---

# Harness Orchestration Scorecard

A read-only skill that visualizes backend utilization for this session/project (Claude=host / delegations to Codex / Cursor).
The authoritative records are `.claude/state/orchestration-ledger.jsonl` (appended by the companion on each delegation, Phase 90.1.1) and
`.claude/state/orchestration-totals.json` (idempotently rolled up at session end/completion, Phase 90.1.2).

> Display is on-demand only. Do not show during active work; invoke this skill when the user wants to see the data.
> Once at full-task completion, the task-completed hook automatically emits a terminal summary (via a separate code path, not this skill).

## Quick Reference

- **"Show me orchestration usage"** → generate and open the HTML scorecard
- **"Which backend was used"** / **"How much Codex/Cursor"** → terminal summary
- **"Show lifetime totals"** / **"Something to show off"** → HTML scorecard (lifetime totals are the highlight)

## Deliverables

| Output | Artifact |
|--------|----------|
| HTML scorecard | `scripts/orchestration-scorecard.sh --format html-data` → `scripts/render-html.sh --template orchestration` produces a single HTML file |
| Terminal summary | `scripts/orchestration-scorecard.sh --format terminal` (3-5 lines) |

Tri-state: `used` (count>0) / `available` (configured but unused) / `not-configured` (binary absent = neutral, not broken).
If there are zero delegations, degrade gracefully to "no delegations observed".

## Execution

Call helper scripts from the plugin bundle root:

```bash
HARNESS_PLUGIN_ROOT="${HARNESS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
```

### Terminal Summary (`--terminal`)

```bash
bash "${HARNESS_PLUGIN_ROOT}/scripts/orchestration-scorecard.sh" --format terminal
```

Summarize and present the 3-5 output lines as-is.

### HTML Scorecard (default / `--out` / `--no-open`)

```bash
OUT="${1:-.claude/state/orchestration-scorecard.html}"   # override with --out <path>
bash "${HARNESS_PLUGIN_ROOT}/scripts/orchestration-scorecard.sh" --format html-data \
  | bash "${HARNESS_PLUGIN_ROOT}/scripts/render-html.sh" --template orchestration --data - --out "$OUT"
```

- Unless `--no-open` is specified, present the path after generation and guide the user to open it in a browser (auto-open is environment-dependent, so presenting the path is the baseline behavior).
- No redaction is applied: scorecard data is structurally non-sensitive (counts + backend names + repo basename + timestamps only). The no-secret guarantee is enforced by the upstream ledger contract.

## Related Skills

- `harness-progress` — progress dashboard (task progress; this skill focuses on backend utilization)
- `harness-work` / `breezing` — implementation (the side that actually uses backends)
