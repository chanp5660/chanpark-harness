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
#   Status is one of the closed vocabulary: cc:todo / cc:wip / cc:blocked (active) and
#   cc:done [hash] / cc:dropped (terminal). Legacy cc:TODO / cc:WIP / cc:完了 and the
#   cc:cancelled / cc:canceled spellings are accepted on input.
#   pm:* is out of scope for this snapshot
#   progress_pct = (done + dropped) / (todo + wip + blocked + done + dropped)
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

# Closed marker vocabulary, mirroring scripts/lib/plans-markers.awk. Matching is
# ANCHORED and WORD-BOUNDED, not a startswith() chain: startswith("cc:wip") also
# swallowed "cc:wip-paused", so an invented state was silently filed under its parent
# and the operator never learned the state does not exist. A trailing note
# ("cc:done [a1b2c3d]", "cc:done (2026-07-14: measured on hw)") is still accepted.
MARKER_ALIASES = {
    "cc:todo": "todo",
    "cc:wip": "wip",
    "cc:done": "done",
    "cc:完了": "done",
    "cc:blocked": "blocked",
    "cc:dropped": "dropped",
    "cc:cancelled": "dropped",   # industry spelling, accepted on input
    "cc:canceled": "dropped",    # US variant of the same
}
WORD_CHAR_RE = re.compile(r"[A-Za-z0-9_-]")


def classify(status):
    """Status cell -> bucket name, or None when it is not a task status at all,
    or 'unknown' when it advertises a marker that is not in the vocabulary."""
    s = re.sub(r"^cursor:", "cc:", status.strip(), flags=re.IGNORECASE).lower()
    for marker, bucket in MARKER_ALIASES.items():
        if s.startswith(marker):
            rest = s[len(marker):]
            if not rest or not WORD_CHAR_RE.match(rest[0]):
                return bucket
    if s.startswith("cc:") or s.startswith("pm:"):
        return "unknown"
    return None


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
dropped = []
unknown = []

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
            bucket = classify(status)

            if bucket == "todo":
                todo.append({"number": number, "title": short_title})
            elif bucket == "wip":
                wip.append({"number": number, "title": short_title})
            elif bucket == "done":
                commit_match = re.search(r"\[([0-9a-fA-F]{4,})\]", status)
                commit = commit_match.group(1)[:7] if commit_match else ""
                done.append({"number": number, "title": short_title, "commit": commit})
            elif bucket == "blocked":
                blocked.append({"number": number, "title": short_title})
            elif bucket == "dropped":
                dropped.append({"number": number, "title": short_title})
            elif bucket == "unknown":
                unknown.append({"number": number, "title": short_title, "status": status})
            continue

        # ── checklist row ──
        c = CHECKLIST_RE.match(line)
        if c:
            title = c.group(1).strip()
            short_title = _short(title)
            cc_status = c.group(2) or c.group(3) or ""
            bucket = classify(cc_status)

            if bucket == "todo":
                todo.append({"number": "", "title": short_title})
            elif bucket == "wip":
                wip.append({"number": "", "title": short_title})
            elif bucket == "done":
                done.append({"number": "", "title": short_title, "commit": ""})
            elif bucket == "blocked":
                blocked.append({"number": "", "title": short_title})
            elif bucket == "dropped":
                dropped.append({"number": "", "title": short_title})
            elif bucket == "unknown":
                unknown.append({"number": "", "title": short_title, "status": cc_status})

# terminal-complete semantics: done AND dropped are both finished states, and both
# stay in the denominator. progress is terminal/total, not done/total — if abandoning
# a task lowered the percentage, nobody would ever abandon one, and the plan would only
# ever grow. `unknown` is a file defect rather than a state, so it is surfaced as an
# alert instead of being folded into the ratio.
active = len(todo) + len(wip) + len(blocked)
terminal = len(done) + len(dropped)
total = active + terminal
if total == 0:
    progress_pct = 0
else:
    progress_pct = round(terminal * 100 / total)

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
] + [
    {
        "severity": "warn",
        "kind": "unknown-marker",
        "message": (
            f"Task {item['number']}: status {item['status']!r} matches no known marker."
            if item["number"]
            else f"A status cell reads {item['status']!r}, which matches no known marker."
        ),
        "suggested_action": (
            "Use one of cc:todo / cc:wip / cc:blocked / cc:done / cc:dropped. "
            "The vocabulary is closed; put finer detail in the description cell."
        ),
    }
    for item in unknown
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
    "dropped_tasks": dropped,
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
    "_dropped_count": len(dropped),
    "_unknown_count": len(unknown),
    "_active_count": active,
    "_terminal_count": terminal,
    "_total_count": total,
}

print(json.dumps(snapshot, ensure_ascii=False, indent=2))
PYEOF
