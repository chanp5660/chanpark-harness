#!/usr/bin/env bash
# scripts/progress-snapshot.sh
# Phase 65.4.1 - Plans.md → progress-snapshot.v1 JSON
#
# Purpose:
#   Extract the cc:todo / cc:wip / cc:done counts and lists from the Plans.md
#   task table and generate snapshot JSON for the harness-progress skill.
#
# Usage:
#   progress-snapshot.sh --plans <path> --project <name> [--state-file <path>]
#
# Schema: progress-snapshot.v1 (skills/harness-progress/schemas/)
#
# Expected Plans.md format:
#   | <number> | <title> | <DoD> | <Depends> | <Status> |
#   Status is cc:todo / cc:wip / cc:done [hash] (legacy cc:TODO / cc:WIP / cc:完了 are also readable)
#   pm:* is out of scope for this snapshot
#
# Optional: --state-file
#   read elapsed_minutes / cost_so_far_usd etc. from
#   .claude/state/session-cost.json (all 0 if absent)

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: progress-snapshot.sh --plans <path> --project <name> [--state-file <path>]

Required:
  --plans <path>       Plans.md file path
  --project <name>     project name (basename of repo)

Optional:
  --state-file <path>  session state JSON
                       expected fields: elapsed_minutes / estimated_total_minutes /
                                   cost_so_far_usd / cost_estimate_usd
                       falls back to all 0 if absent

Exit: 0=success / 1=runtime error / 2=usage error
USAGE
  exit 2
}

PLANS_PATH=""
PROJECT=""
STATE_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plans)      PLANS_PATH="${2:-}"; shift 2 ;;
    --project)    PROJECT="${2:-}"; shift 2 ;;
    --state-file) STATE_FILE="${2:-}"; shift 2 ;;
    -h|--help)    usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$PLANS_PATH" || -z "$PROJECT" ]]; then
  echo "ERROR: --plans and --project are required" >&2
  usage
fi

if [[ ! -f "$PLANS_PATH" ]]; then
  echo "ERROR: Plans.md not found: $PLANS_PATH" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

# state defaults
ELAPSED_MIN=0
ESTIMATE_MIN=0
COST_SO_FAR=0
COST_ESTIMATE=0

if [[ -n "$STATE_FILE" && -f "$STATE_FILE" ]]; then
  ELAPSED_MIN="$(jq -r '.elapsed_minutes // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  ESTIMATE_MIN="$(jq -r '.estimated_total_minutes // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  COST_SO_FAR="$(jq -r '.cost_so_far_usd // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
  COST_ESTIMATE="$(jq -r '.cost_estimate_usd // 0' "$STATE_FILE" 2>/dev/null || echo 0)"
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export PLANS_PATH_PY="$PLANS_PATH"
export PROJECT_PY="$PROJECT"
export TIMESTAMP_PY="$TIMESTAMP"
export ELAPSED_MIN_PY="$ELAPSED_MIN"
export ESTIMATE_MIN_PY="$ESTIMATE_MIN"
export COST_SO_FAR_PY="$COST_SO_FAR"
export COST_ESTIMATE_PY="$COST_ESTIMATE"

exec python3 - <<'PYEOF'
import os
import re
import json
import sys

PLANS_PATH = os.environ["PLANS_PATH_PY"]
PROJECT = os.environ["PROJECT_PY"]
TIMESTAMP = os.environ["TIMESTAMP_PY"]
ELAPSED_MIN = int(os.environ["ELAPSED_MIN_PY"] or 0)
ESTIMATE_MIN = int(os.environ["ESTIMATE_MIN_PY"] or 0)

def to_float(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return 0.0

COST_SO_FAR = to_float(os.environ["COST_SO_FAR_PY"])
COST_ESTIMATE = to_float(os.environ["COST_ESTIMATE_PY"])

# Parse Plans.md task rows (v2 pipe-table format):
#   "| 65.4.1 | <title> | <DoD> | <Depends> | cc:todo |"
#   "| 65.4.1 | <title> | <DoD> | <Depends> | cc:done [a1b2c3d] |"
#   "| T001   | <title> | <DoD> | <Depends> | cc:blocked |"
# ID may be numeric (65.4.1) or alphanumeric with leading letters (T001).
# Status matching is case-insensitive (cc:TODO / cc:WIP / cc:Done / cc:BLOCKED all valid).
# Use the part of the title up to the first "。" as a one-line summary.

ROW_RE = re.compile(
    r"^\|\s*([A-Za-z]*\d+(?:\.\d+)*)\s*\|\s*(.+?)\s*\|\s*.+?\s*\|\s*.+?\s*\|\s*(cc:\S+(?:\s*\[[^\]]+\])?)\s*\|\s*$"
)

# Parse checklist format (two status-embedding variants):
#   "- [ ] <title> `cc:todo`"    (marker in backticks)
#   "- [x] <title> cc:done"      (bare marker at end)
# Requires the "- [?]" structural anchor; prose lines are NOT matched.
CHECKLIST_RE = re.compile(
    r"^\s*-\s+\[[ xX]\]\s+(.+?)\s*(?:`(cc:\S+)`|(cc:\S+))\s*$"
)

todo = []
wip = []
done = []
blocked = []

def _short(title):
    s = title.split("。")[0]
    return s[:77] + "..." if len(s) > 80 else s

with open(PLANS_PATH, "r", encoding="utf-8") as f:
    for line in f:
        # ── pipe-table row ──
        m = ROW_RE.match(line)
        if m:
            number, title, status = m.group(1), m.group(2), m.group(3)
            short_title = _short(title)
            sl = status.lower()

            if sl.startswith("cc:todo"):
                todo.append({"number": number, "title": short_title})
            elif sl.startswith("cc:wip"):
                wip.append({"number": number, "title": short_title})
            elif sl.startswith("cc:done") or status.startswith("cc:完了"):
                commit_match = re.search(r"\[([0-9a-fA-F]{4,})\]", status)
                commit = commit_match.group(1)[:7] if commit_match else ""
                done.append({"number": number, "title": short_title, "commit": commit})
            elif sl.startswith("cc:blocked"):
                blocked.append({"number": number, "title": short_title})
            continue

        # ── checklist row ──
        c = CHECKLIST_RE.match(line)
        if c:
            title = c.group(1).strip()
            short_title = _short(title)
            cc_status = (c.group(2) or c.group(3) or "").lower()

            if cc_status.startswith("cc:todo"):
                todo.append({"number": "", "title": short_title})
            elif cc_status.startswith("cc:wip"):
                wip.append({"number": "", "title": short_title})
            elif cc_status.startswith("cc:done") or cc_status.startswith("cc:完了"):
                done.append({"number": "", "title": short_title, "commit": ""})
            elif cc_status.startswith("cc:blocked"):
                blocked.append({"number": "", "title": short_title})

total = len(todo) + len(wip) + len(done) + len(blocked)
if total == 0:
    progress_pct = 0
else:
    progress_pct = round(len(done) * 100 / total)

current_task = wip[0]["title"] if wip else ""

# Derived helpers (for section expansion in render-html.sh)
done_recent = done[-5:][::-1]  # latest 5, newest first

# Build alerts for each blocked task (consumed by {{#alerts}} in progress.html.template)
alerts = [
    {
        "severity": "warn",
        "kind": "blocked",
        "message": (
            f"Task {item['number']}: {item['title']} is blocked."
            if item["number"]
            else f"{item['title']} is blocked."
        ),
        "suggested_action": "Resolve blockers to continue progress.",
    }
    for item in blocked
]

snapshot = {
    "schema": "progress-snapshot.v1",
    "project": PROJECT,
    "current_task": current_task,
    "progress_pct": progress_pct,
    "todo_tasks": todo,
    "wip_tasks": wip,
    "done_tasks": done,
    "blocked_tasks": blocked,
    "elapsed_minutes": ELAPSED_MIN,
    "estimated_total_minutes": ESTIMATE_MIN,
    "cost_so_far_usd": COST_SO_FAR,
    "cost_estimate_usd": COST_ESTIMATE,
    "alerts": alerts,
    "generated_at": TIMESTAMP,
    "_done_recent_items": done_recent,
    "_todo_count": len(todo),
    "_wip_count": len(wip),
    "_done_count": len(done),
    "_blocked_count": len(blocked),
}

print(json.dumps(snapshot, ensure_ascii=False, indent=2))
PYEOF
