#!/bin/bash
# scripts/accept-record-decision.sh
# Phase 65.2.3 - Record Acceptance Demo decision (memory write side)
#
# Usage:
#   accept-record-decision.sh --action <accept|override|reject> \
#       --user-request <text> --project <name> \
#       --recommendation <ship|wait|reject> \
#       [--override-reason <text>] \
#       [--verified-criteria-source <path>] \
#       [--post-launch-concerns <csv>] \
#       [--out -|<path>]
#
# Role:
#   Outputs a payload JSON conforming to the `acceptance-decision.v1` schema
#   that records the user's ship/wait/reject decision (accept / override /
#   reject of the Acceptance Demo recommendation). The actual
#   `mcp__harness__harness_mem_ingest` call is made by the skill (LLM context).
#
# Join with the Plan Brief side:
#   `data.user_request_hash` is the sha256 hex of the same user request string,
#   exactly matching Phase 65.1.4's `personal-preference.v1` -> a full
#   "plan -> acceptance" trace is retrievable via mem_graph or mem_search
#
# Action types:
#   - accept    : take the recommendation as-is (any of ship/wait/reject)
#                 -> recommendation_taken = true
#   - override  : take a decision different from the recommendation
#                 -> recommendation_taken = false, override_reason required
#   - reject    : make "reject" the final decision regardless of recommendation
#                 -> recommendation_taken = (recommendation == "reject")
#
# Schema: acceptance-decision.v1
#   data: {
#     user_request_hash             : sha256 hex (joins Plan Brief personal-preference.v1)
#     recommendation_shown          : "ship"|"wait"|"reject"  (value shown by Acceptance Demo HTML)
#     recommendation_taken          : bool                     (whether it was taken)
#     override_reason               : string                   (non-empty only on override)
#     verified_criteria_at_decision : [{name, passed, evidence}]
#     post_launch_concerns          : string[]
#     timestamp                     : ISO8601 UTC
#     project                       : string
#     action                        : "accept" | "override" | "reject"
#   }
#
# Tags (fixed):
#   ["personal-preference", "acceptance-decision"]
#
# Exit code: 0=success, 2=usage error, 3=runtime error

set -euo pipefail

usage() {
  cat <<USAGE >&2
Usage: $0 --action <accept|override|reject> \
          --user-request <text> --project <name> \
          --recommendation <ship|wait|reject> \
          [--override-reason <text>] \
          [--verified-criteria-source <path>] \
          [--post-launch-concerns <csv>] \
          [--out -|<path>]

Required:
  --action <accept|override|reject>      user decision action type
  --user-request <text>                  original request text that launched the Plan Brief
  --project <name>                       project name
  --recommendation <ship|wait|reject>    recommendation shown by the Acceptance Demo HTML

Optional:
  --override-reason <text>               reason on override / reject (default: "")
                                          required when action=override
  --verified-criteria-source <path>      Acceptance Demo verified_criteria JSON
                                          (default: empty array)
                                          format: {"items": [{"name", "passed", "evidence"}]}
  --post-launch-concerns <csv>           post-launch concerns (default: "")
  --out -|<path>                         output destination (- = stdout, default: stdout)

Output: JSON for harness_mem_ingest conforming to the acceptance-decision.v1 schema
USAGE
  exit 2
}

ACTION=""
USER_REQUEST=""
PROJECT=""
RECOMMENDATION=""
OVERRIDE_REASON=""
VERIFIED_CRITERIA_SOURCE=""
POST_LAUNCH_CONCERNS_CSV=""
OUT="-"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --action)                    ACTION="${2:-}";                    shift 2 ;;
    --user-request)              USER_REQUEST="${2:-}";              shift 2 ;;
    --project)                   PROJECT="${2:-}";                   shift 2 ;;
    --recommendation)            RECOMMENDATION="${2:-}";            shift 2 ;;
    --override-reason)           OVERRIDE_REASON="${2:-}";           shift 2 ;;
    --verified-criteria-source)  VERIFIED_CRITERIA_SOURCE="${2:-}";  shift 2 ;;
    --post-launch-concerns)      POST_LAUNCH_CONCERNS_CSV="${2:-}";  shift 2 ;;
    --out)                       OUT="${2:-}";                       shift 2 ;;
    -h|--help)                   usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

# ---- Required arguments ----

if [[ -z "$ACTION" || -z "$USER_REQUEST" || -z "$PROJECT" || -z "$RECOMMENDATION" ]]; then
  echo "ERROR: --action, --user-request, --project, --recommendation are required" >&2
  usage
fi

case "$ACTION" in
  accept|override|reject) ;;
  *)
    echo "ERROR: --action must be one of: accept|override|reject (got: $ACTION)" >&2
    exit 2
    ;;
esac

case "$RECOMMENDATION" in
  ship|wait|reject) ;;
  *)
    echo "ERROR: --recommendation must be one of: ship|wait|reject (got: $RECOMMENDATION)" >&2
    exit 2
    ;;
esac

# override_reason is required when action=override
if [[ "$ACTION" == "override" && -z "$OVERRIDE_REASON" ]]; then
  echo "ERROR: --override-reason is required when --action override" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found" >&2
  exit 3
fi

# ---- Determine recommendation_taken ----
#   accept    -> true
#   override  -> false
#   reject    -> (recommendation == "reject")  <- if rec is reject, user also rejects = taken
case "$ACTION" in
  accept)
    RECOMMENDATION_TAKEN="true"
    ;;
  override)
    RECOMMENDATION_TAKEN="false"
    ;;
  reject)
    if [[ "$RECOMMENDATION" == "reject" ]]; then
      RECOMMENDATION_TAKEN="true"
    else
      RECOMMENDATION_TAKEN="false"
    fi
    ;;
esac

# ---- sha256 hex (logic identical to Phase 65.1.4) ----

sha256_of_text() {
  local text="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$text" | sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s' "$text" | shasum -a 256 | awk '{print $1}'
  else
    echo "ERROR: neither sha256sum nor shasum found" >&2
    exit 3
  fi
}

USER_REQUEST_HASH="$(sha256_of_text "$USER_REQUEST")"

# ---- Normalize verified_criteria_at_decision ----

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/accept-record-decision.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
NORM_CRITERIA="$TMP_DIR/criteria.json"

if [[ -n "$VERIFIED_CRITERIA_SOURCE" ]]; then
  if [[ ! -f "$VERIFIED_CRITERIA_SOURCE" ]]; then
    echo "ERROR: --verified-criteria-source file not found: $VERIFIED_CRITERIA_SOURCE" >&2
    exit 3
  fi
  if ! jq -e '.' "$VERIFIED_CRITERIA_SOURCE" >/dev/null 2>&1; then
    echo "ERROR: --verified-criteria-source is not valid JSON" >&2
    exit 3
  fi
  jq '[.items[]? | {
    name:     (.name // ""),
    passed:   (.passed // false),
    evidence: (.evidence // "")
  }]' "$VERIFIED_CRITERIA_SOURCE" > "$NORM_CRITERIA"
else
  echo '[]' > "$NORM_CRITERIA"
fi

# ---- Convert post_launch_concerns to an array ----

if [[ -z "$POST_LAUNCH_CONCERNS_CSV" ]]; then
  POST_LAUNCH_CONCERNS_JSON='[]'
else
  POST_LAUNCH_CONCERNS_JSON="$(printf '%s' "$POST_LAUNCH_CONCERNS_CSV" | awk -F',' '{
    printf "[";
    for (i = 1; i <= NF; i++) {
      gsub(/^[ \t]+|[ \t]+$/, "", $i);
      if (i > 1) printf ",";
      gsub(/"/, "\\\"", $i);
      printf "\"%s\"", $i;
    }
    printf "]";
  }')"
fi

# ---- timestamp ----

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---- Assemble payload ----

PAYLOAD="$(jq -n \
  --arg hash "$USER_REQUEST_HASH" \
  --arg rec "$RECOMMENDATION" \
  --argjson taken "$RECOMMENDATION_TAKEN" \
  --arg override "$OVERRIDE_REASON" \
  --slurpfile criteria "$NORM_CRITERIA" \
  --argjson concerns "$POST_LAUNCH_CONCERNS_JSON" \
  --arg ts "$TIMESTAMP" \
  --arg proj "$PROJECT" \
  --arg action "$ACTION" \
  '{
    schema: "acceptance-decision.v1",
    observation_type: "decision",
    tags: ["personal-preference", "acceptance-decision"],
    project: $proj,
    data: {
      user_request_hash: $hash,
      recommendation_shown: $rec,
      recommendation_taken: $taken,
      override_reason: $override,
      verified_criteria_at_decision: ($criteria | first),
      post_launch_concerns: $concerns,
      timestamp: $ts,
      project: $proj,
      action: $action
    }
  }')"

if [[ "$OUT" == "-" || -z "$OUT" ]]; then
  printf '%s\n' "$PAYLOAD"
else
  printf '%s\n' "$PAYLOAD" > "$OUT"
fi
