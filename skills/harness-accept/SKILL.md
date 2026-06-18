---
name: harness-accept
description: "Generate an Acceptance Demo HTML for non-engineer vibecoders right before ship/wait/reject decision. Reads back the acceptance_criteria that were stored as personal-preference.v1 by harness-plan-brief (joined by user_request_hash), then renders a single-file HTML showing each criterion as verified or unverified along with a ship/wait/reject recommendation. Use when the user asks for an acceptance review, wants to decide whether to ship a delivered task, or says: acceptance demo, accept demo, acceptance review, acceptance decision, ship/wait/reject decision, acceptance inspection review. Do NOT load for: implementation, code review, release work."
allowed-tools: ["Read", "Write", "Edit", "Bash"]
argument-hint: "[task-description]"
user-invocable: true
---

# harness-accept

A skill for non-engineer clients and producers that presents the ship / wait / reject acceptance decision for a completed implementation task as a **single HTML page**.
Use this at cognitive load peak stage (3): the acceptance decision stage.

Operates as the read-side counterpart to Phase 65.1.x (`harness-plan-brief`), retrieving the `acceptance_criteria` approved during the Plan Brief and evaluating them.

## Quick Reference

- "**Create an Acceptance Demo**" → this skill
- "**I want to make an acceptance decision**" → this skill
- "**ship/wait/reject decision**" → this skill

## Responsibility Boundaries

| Scope | This skill's responsibility |
|-------|-----------------------------|
| Search | **Current project only** (always specify `project: <current>`, `strict_project: true`) |
| Cross-project | **Not performed** (opt-in via `--cross-project-group <name>` flag from Phase 65.3 onward) |
| Plan Brief integration | Read `personal-preference.v1` (Phase 65.1.4) using `user_request_hash` as join key |
| Writing | Not performed (memory write after acceptance approval is the responsibility of `accept-record-decision.sh`) |
| Recommendation calculation | Threshold judgment at 0.8 / 0.5 based on verified / total criteria ratio. Logic is computed immediately before `scripts/render-html.sh` |

## Input

Pass the user's request as the `[task-description]` argument (use the same text as at Plan Brief time).
If no argument is provided, accept it interactively.

## Output

| Output | Path | Format |
|--------|------|--------|
| Acceptance Demo HTML | `.claude/state/views/accept-<timestamp>.html` | Self-contained HTML (no server, no JS framework) |
| Acceptance context JSON | `.claude/state/views/accept-<timestamp>.context.json` | `acceptance-context.v1` schema |

## Schema: `acceptance-context.v1`

```json
{
  "schema": "acceptance-context.v1",
  "user_request": "string",
  "user_request_hash": "sha256 hex (join key with personal-preference.v1 on the Plan Brief side)",
  "demo_artifacts": [
    { "kind": "video|screenshot|text", "path": "string" }
  ],
  "verified_criteria": [
    { "name": "string", "passed": true, "evidence": "string" }
  ],
  "tdd_verified": "yes|no|not-required|skip:<reason>",
  "unverified_caveats": ["string"],
  "past_issue_patterns": [
    { "pattern_id": "P5", "title": "string", "verified_in_current_task": true }
  ],
  "recommendation": "ship|wait|reject",
  "recommendation_evidence": ["string"],
  "project": "string",
  "generated_at": "ISO8601"
}
```

For the complete schema, see [`schemas/acceptance-context.v1.schema.json`](${CLAUDE_SKILL_DIR}/schemas/acceptance-context.v1.schema.json).

## Recommendation Calculation Logic

```
verified_count    = count of verified_criteria where passed=true
total_criteria    = count of verified_criteria
ratio             = verified_count / total_criteria  (0 when total=0)

  ratio >= 0.8 → "ship"
  ratio >= 0.5 → "wait"
  ratio <  0.5 → "reject"
  total = 0    → "reject" (0 criteria means judgment is impossible; fail safe to reject)
```

Record literal numeric values in `recommendation_evidence` as the basis for evaluation.
Example: `"verified 4 / total 5 (80%) → meets ship threshold"`

## Execution Flow

When the skill is invoked, Claude follows the steps below.

### Step 1: Resolve project name and user_request_hash

```bash
PROJECT_NAME="$(basename "$(git rev-parse --show-toplevel)")"
USER_REQUEST_HASH="$(printf '%s' "$USER_REQUEST" | sha256sum | awk '{print $1}')"
```

If `PROJECT_NAME` is empty (outside a git repo), use `current` as the default.

### Step 2: Search harness-mem **project-only** and retrieve the Plan Brief record (default)

When the `--cross-project-group <name>` flag is **absent** from the arguments (default behavior):

Call `mcp__harness__harness_mem_search` with the following parameters:

```
project: <PROJECT_NAME>
strict_project: true
tags: ["personal-preference", "plan-brief-approval"]
limit: 10
```

> **Important**: The `project` parameter is **required**. Specify `strict_project: true` and **never** perform a cross-project search.

Filter the retrieved records by `data.user_request_hash == <USER_REQUEST_HASH>` and select the most recent one.
This record holds the approval content from the Plan Brief (chosen_option / acceptance_criteria, etc.).

### Step 2 (alt): Cross-project search (Phase 65.3.5 opt-in)

Only when the `--cross-project-group <name>` flag is **present** in the arguments, retrieve similar plan-brief-approval / acceptance-decision history from other projects in the cross-group (D43 Option α):

```bash
MEMBERS_JSON="$(bash scripts/load-cross-project-groups.sh --group "<name>" 2>/dev/null)" || {
  echo "ERROR: cross-project group not found: <name>" >&2
  exit 1
}
```

If `MEMBERS_JSON` is `[]`, fall back to the default single-project search.

If `MEMBERS_JSON` is non-empty, issue one MCP search per member project:

```
for each project in MEMBERS_JSON:
  mcp__harness__harness_mem_search(
    project: <member>,
    strict_project: true,
    tags: ["personal-preference", "plan-brief-approval"],
    limit: 10
  )
```

Merge the results on the client side and filter by `data.user_request_hash == <USER_REQUEST_HASH>`.
Hash matches almost always originate from the same user request, so duplicates across projects are rare, but deduplicate by id to be safe.

Because adopting a cross-project record may cause chosen_option / acceptance_criteria from other past projects to leak in, always use the **`--with-redaction` flag** when generating HTML output:

```bash
bash scripts/render-html.sh --template accept ... --with-redaction
```

For details, see the "Phase 65.3 Implementation Decisions (D43)" section in `.claude/rules/cross-repo-handoff.md`.

### Step 3: Retrieve past issue patterns (Phase 65.2.2 delegation)

```bash
bash scripts/accept-past-issues.sh --project "$PROJECT_NAME" --task "$USER_REQUEST" > "$PAST_ISSUES_JSON"
```

This script performs a semantic search over patterns.md (P1-P33) and past `acceptance-context.v1` records, returning up to 3 `past-issue.v1` entries, each with a `verified_in_current_task: bool` field.

### Step 4: Assemble verified_criteria

Evaluate the current task status for each acceptance_criteria item from the Plan Brief.
The user (or Claude) presents "verified evidence" and fills in the `evidence` string.

If `evidence` is an empty string, a warning is displayed in the HTML (DoD c).

For tasks that require TDD, the Acceptance Demo must always include a `TDD verified: yes|no` line.
If TDD is not required or is skipped, display `TDD verified: not-required` or `TDD verified: skip:<reason>`.
`yes` is only allowed when a Red trail in `.claude/state/tdd-red-log/<task-id>.jsonl` or literal failing test output can be confirmed.

### Step 5: Calculate the recommendation

Determine ship / wait / reject according to the "Recommendation Calculation Logic" above.

### Step 6: Generate the HTML

Call `scripts/render-html.sh` (Phase 65.1.1) with `templates/html/accept.html.template`:

```bash
bash scripts/render-html.sh \
  --template accept \
  --data "$CONTEXT_JSON" \
  --out "$HTML_OUT"
```

### Step 7: Automatically open in browser

Reuse `scripts/plan-brief-open.sh` (the **generic OS dispatcher** introduced in Phase 65.1.2):

```bash
bash scripts/plan-brief-open.sh "$HTML_OUT"
```

> **Note**: The script name contains "plan-brief", but it is actually a kind-neutral OS-specific browser open dispatcher.
> It was introduced first in Phase 65.1.2, hence the historical name. It is also reused for other purposes such as Layer 3 (final scan immediately before HTML generation).
> If the `BROWSER=true` env variable is set (CI environment), the open is **skipped** and only the path is printed via `printf`.

### Step 8: Await user decision

Confirm whether the user will adopt or override the ship / wait / reject recommendation.
The memory write after the decision is the responsibility of a separate skill (`accept-record-decision.sh`, Phase 65.2.3).

## Failure Behavior

| Failure | Behavior |
|---------|----------|
| `mcp__harness__harness_mem_search` unreachable | Display a warning and continue with `verified_criteria` as an empty array (recommendation = reject) |
| Plan Brief record not found | Emit a warning and continue with `verified_criteria` as an empty array |
| `git rev-parse --show-toplevel` fails | Continue with `PROJECT_NAME=current` |
| `accept-past-issues.sh` fails | Continue with `past_issue_patterns: []` (best-effort) |
| `render-html.sh` fails | Print error to stderr and exit 1 |

## Related

- `harness-plan-brief` (Phase 65.1.2) — The planning-stage counterpart skill. This skill joins and reads `personal-preference.v1` from the Plan Brief using `user_request_hash`
- `scripts/accept-past-issues.sh` (Phase 65.2.2) — Retrieves past issue patterns (read side)
- `scripts/accept-record-decision.sh` (Phase 65.2.3) — Writes approval memory (`acceptance-decision.v1`)
- `scripts/render-html.sh` (Phase 65.1.1) — HTML template engine
- `scripts/plan-brief-open.sh` (Phase 65.1.2) — Generic OS browser dispatcher
- `harness-progress` skill (Phase 65.4.1) — Progress management skill (the middle of the 3 surfaces)
