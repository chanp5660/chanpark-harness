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
#   "| 27.2   | <title> | <DoD> | <Depends> | cc:done (2026-07-14: measured on hw) |"
#   "| T001   | <title> | <DoD> | <Depends> | cc:blocked |"
# ID may be numeric (65.4.1) or alphanumeric with leading letters (T001).
# Status matching is case-insensitive (uppercase/legacy alias forms are accepted when reading).
# Use the part of the title up to the first "。" as a one-line summary.
#
# The row is split on "|" rather than matched by one regex. The former regex pinned the
# table to exactly five columns and demanded a bare marker in the status cell, so a
# six-column table, or the very common "cc:done (why)" note, dropped the whole row from
# the snapshot: a real nine-done Plans.md reported done=1. Status is now the LAST
# non-empty cell (code spans stripped inside it), which is the rule in
# scripts/lib/plans-markers.awk, hud/statusline.sh and the plans-watcher hook.

ID_RE = re.compile(r"^[A-Za-z]*\d+(?:\.\d+)*$")
CODESPAN_RE = re.compile(r"`[^`]*`")


def parse_table_row(line):
    """-> (id, title, status) for a task row, else None."""
    if not line.lstrip().startswith("|"):
        return None
    cells = [c.strip() for c in line.rstrip("\n").split("|")]
    while cells and cells[0] == "":
        cells.pop(0)
    while cells and cells[-1] == "":
        cells.pop()
    if len(cells) < 2 or not ID_RE.match(cells[0]):
        return None  # header, separator and prose-in-a-table rows have no task ID
    status = CODESPAN_RE.sub("", cells[-1]).strip()
    status = re.sub(r"^cursor:", "cc:", status, flags=re.IGNORECASE)
    return cells[0], cells[1], status

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

in_fence = False

with open(PLANS_PATH, "r", encoding="utf-8") as f:
    for line in f:
        # ── skip documentation, not task records ──
        stripped = line.lstrip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence or stripped.startswith("<!--"):
            continue

        # ── pipe-table row ──
        m = parse_table_row(line)
        if m:
            number, title, status = m
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
