#!/usr/bin/env bash
# scripts/progress-detect-drift.sh
# Phase 65.4.3 - Progress Tracker drift detection (5 alert kinds)
#
# Purpose:
#   Inspect Plans.md and session state and generate 5 kinds of drift alerts.
#   Generated alerts are output as a JSON array conforming to the progress-alert.v1 schema.
#
# Schema: progress-alert.v1
#   {
#     kind: "scope-creep"|"time-overrun"|"repeated-failure"|"cost-warning"|"high-risk-file",
#     severity: "info"|"warn"|"critical",
#     message: string,
#     suggested_action: string,
#     triggered_at: ISO8601
#   }
#
# Usage:
#   progress-detect-drift.sh \
#     [--scope-creep-files <csv>]   # files edited that are not in Plans.md (CSV)
#     [--elapsed-min <int>]          # elapsed minutes
#     [--estimate-min <int>]         # estimated total minutes
#     [--repeated-failure-count <int>]  # consecutive test failure count
#     [--cost-so-far <float>]        # cost so far
#     [--cost-limit <float>]         # cost limit
#     [--high-risk-files <csv>]      # files matching harness.toml deny paths (CSV)
#
# If an input is empty / default, that alert kind is not emitted (no-op).
# Outputs a JSON array [{...}, ...] to stdout (may be empty).
#
# Detection conditions (per Plans.md DoD):
#   - scope-creep:    a file not present in Plans.md was edited
#   - time-overrun:   elapsed > estimate × 1.5
#   - repeated-failure: test fail count >= 3
#   - cost-warning:   cost_so_far / cost_limit >= 0.80 and cost_limit > 0
#   - high-risk-file: a file matching a harness.toml deny path was edited
#
# severity map:
#   - scope-creep:      warn
#   - time-overrun:     warn (1.5x), critical (2.0x or more)
#   - repeated-failure: critical
#   - cost-warning:     warn (80-100%), critical (100%+)
#   - high-risk-file:   critical

set -euo pipefail

usage() {
  cat <<'USAGE' >&2
Usage: progress-detect-drift.sh [options]

All optional (each input absent → corresponding alert not emitted):
  --scope-creep-files <csv>      CSV of files edited that are not in Plans.md
  --elapsed-min <int>            elapsed minutes (default 0)
  --estimate-min <int>           estimated total minutes (default 0)
  --repeated-failure-count <int> consecutive test failure count (default 0)
  --cost-so-far <float>          cost so far (default 0)
  --cost-limit <float>           cost limit (default 0)
  --high-risk-files <csv>        CSV of files matching harness.toml deny paths

Output: JSON array of progress-alert.v1 objects (may be empty)
Exit:   0 = success / 2 = usage error
USAGE
  exit 2
}

SCOPE_CREEP=""
ELAPSED_MIN=0
ESTIMATE_MIN=0
FAILURE_COUNT=0
COST_SO_FAR=0
COST_LIMIT=0
HIGH_RISK=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope-creep-files)        SCOPE_CREEP="${2:-}"; shift 2 ;;
    --elapsed-min)              ELAPSED_MIN="${2:-0}"; shift 2 ;;
    --estimate-min)             ESTIMATE_MIN="${2:-0}"; shift 2 ;;
    --repeated-failure-count)   FAILURE_COUNT="${2:-0}"; shift 2 ;;
    --cost-so-far)              COST_SO_FAR="${2:-0}"; shift 2 ;;
    --cost-limit)               COST_LIMIT="${2:-0}"; shift 2 ;;
    --high-risk-files)          HIGH_RISK="${2:-}"; shift 2 ;;
    -h|--help)                  usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 is required" >&2
  exit 2
fi

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

export TIMESTAMP_PY="$TIMESTAMP"
export SCOPE_CREEP_PY="$SCOPE_CREEP"
export ELAPSED_MIN_PY="$ELAPSED_MIN"
export ESTIMATE_MIN_PY="$ESTIMATE_MIN"
export FAILURE_COUNT_PY="$FAILURE_COUNT"
export COST_SO_FAR_PY="$COST_SO_FAR"
export COST_LIMIT_PY="$COST_LIMIT"
export HIGH_RISK_PY="$HIGH_RISK"

exec python3 - <<'PYEOF'
import os
import json
import sys

TIMESTAMP = os.environ["TIMESTAMP_PY"]

def to_int(s):
    try:
        return int(s)
    except (TypeError, ValueError):
        return 0

def to_float(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return 0.0

def parse_csv(s):
    if not s:
        return []
    return [x.strip() for x in s.split(",") if x.strip()]

scope_creep_files = parse_csv(os.environ.get("SCOPE_CREEP_PY", ""))
elapsed_min = to_int(os.environ.get("ELAPSED_MIN_PY", "0"))
estimate_min = to_int(os.environ.get("ESTIMATE_MIN_PY", "0"))
failure_count = to_int(os.environ.get("FAILURE_COUNT_PY", "0"))
cost_so_far = to_float(os.environ.get("COST_SO_FAR_PY", "0"))
cost_limit = to_float(os.environ.get("COST_LIMIT_PY", "0"))
high_risk_files = parse_csv(os.environ.get("HIGH_RISK_PY", ""))

alerts = []

# 1. scope-creep
if scope_creep_files:
    alerts.append({
        "kind": "scope-creep",
        "severity": "warn",
        "message": f"{len(scope_creep_files)} file(s) not in Plans.md were edited: {', '.join(scope_creep_files[:3])}",
        "suggested_action": "Confirm the edits are within the intended scope, or add a task to Plans.md",
        "triggered_at": TIMESTAMP,
    })

# 2. time-overrun
if estimate_min > 0 and elapsed_min > 0:
    ratio = elapsed_min / estimate_min
    if ratio >= 2.0:
        alerts.append({
            "kind": "time-overrun",
            "severity": "critical",
            "message": f"Elapsed {elapsed_min} min exceeds {ratio:.1f}x the estimated {estimate_min} min",
            "suggested_action": "Reduce the scope of remaining work, or consider splitting into another session",
            "triggered_at": TIMESTAMP,
        })
    elif ratio >= 1.5:
        alerts.append({
            "kind": "time-overrun",
            "severity": "warn",
            "message": f"Elapsed {elapsed_min} min exceeded {ratio:.1f}x the estimated {estimate_min} min",
            "suggested_action": "Re-estimate the time needed for the remaining tasks",
            "triggered_at": TIMESTAMP,
        })

# 3. repeated-failure
if failure_count >= 3:
    alerts.append({
        "kind": "repeated-failure",
        "severity": "critical",
        "message": f"Tests have failed {failure_count} times in a row",
        "suggested_action": "Pause root-cause investigation and escalate to the user",
        "triggered_at": TIMESTAMP,
    })

# 4. cost-warning
if cost_limit > 0:
    pct = cost_so_far / cost_limit
    if pct >= 1.0:
        alerts.append({
            "kind": "cost-warning",
            "severity": "critical",
            "message": f"Cost ${cost_so_far:.2f} exceeded the limit ${cost_limit:.2f} ({pct*100:.0f}%)",
            "suggested_action": "Stop the session and resume the remaining tasks under a separate budget",
            "triggered_at": TIMESTAMP,
        })
    elif pct >= 0.80:
        alerts.append({
            "kind": "cost-warning",
            "severity": "warn",
            "message": f"Cost ${cost_so_far:.2f} reached {pct*100:.0f}% of the limit ${cost_limit:.2f}",
            "suggested_action": "Reprioritize the remaining tasks and narrow to essential items",
            "triggered_at": TIMESTAMP,
        })

# 5. high-risk-file
if high_risk_files:
    alerts.append({
        "kind": "high-risk-file",
        "severity": "critical",
        "message": f"Edit attempt on {len(high_risk_files)} file(s) matching harness.toml deny paths: {', '.join(high_risk_files[:3])}",
        "suggested_action": "Revert the edit, or confirm with the user whether to change the deny path settings",
        "triggered_at": TIMESTAMP,
    })

print(json.dumps(alerts, ensure_ascii=False, indent=2))
sys.exit(0)
PYEOF
