#!/bin/bash
# show-failures.sh
# Display an aggregated summary of the StopFailure log
#
# Reads stop-failures.jsonl and outputs counts by error code, the 5 most
# recent events, and recommended actions. Called from harness-sync
# --show-failures. Can also be run standalone.
#
# Usage: bash scripts/show-failures.sh [--days N] [--json]
#   --days N  number of days to aggregate (default: 30)
#   --json    output as JSON (for pipelines)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load path-utils.sh
if [ -f "${SCRIPT_DIR}/path-utils.sh" ]; then
  source "${SCRIPT_DIR}/path-utils.sh"
fi

# Detect the project root
if declare -F detect_project_root > /dev/null 2>&1; then
  PROJECT_ROOT="${PROJECT_ROOT:-$(detect_project_root 2>/dev/null || pwd)}"
else
  PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
fi

# State directory (CLAUDE_PLUGIN_DATA aware)
if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
  _project_hash="$(printf '%s' "${PROJECT_ROOT}" | { shasum -a 256 2>/dev/null || sha256sum 2>/dev/null || echo "default  -"; } | cut -c1-12)"
  [ -z "${_project_hash}" ] && _project_hash="default"
  STATE_DIR="${CLAUDE_PLUGIN_DATA}/projects/${_project_hash}"
else
  STATE_DIR="${PROJECT_ROOT}/.claude/state"
fi
LOG_FILE="${STATE_DIR}/stop-failures.jsonl"

# === argument parsing ===
DAYS=30
JSON_OUTPUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --days)
      if [ $# -lt 2 ] || ! [[ ${2} =~ ^[0-9]+$ ]]; then
        echo "Error: --days requires a positive integer" >&2
        exit 1
      fi
      DAYS="$2"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    *) shift ;;
  esac
done

# === check that the log file exists ===
if [ ! -f "${LOG_FILE}" ] || [ ! -s "${LOG_FILE}" ]; then
  if [ "${JSON_OUTPUT}" = true ]; then
    echo '{"total":0,"entries":[],"summary":"No StopFailure events recorded."}'
  else
    echo "No StopFailure log found (${LOG_FILE})"
    echo ""
    echo "This is good news — no session stop failures caused by API errors have occurred."
  fi
  exit 0
fi

# === jq required ===
if ! command -v jq > /dev/null 2>&1; then
  # Without jq, only show the line count
  LINE_COUNT=$(wc -l < "${LOG_FILE}" | tr -d ' ')
  echo "StopFailure log: ${LINE_COUNT} entries (jq is required for detailed output)"
  echo "Log file: ${LOG_FILE}"
  exit 0
fi

# === aggregation ===
CUTOFF_DATE=$(date -u -v-${DAYS}d +"%Y-%m-%dT" 2>/dev/null || date -u -d "${DAYS} days ago" +"%Y-%m-%dT" 2>/dev/null || echo "")

# All entries or period filter
if [ -n "${CUTOFF_DATE}" ]; then
  FILTERED=$(jq -c "select(.timestamp >= \"${CUTOFF_DATE}\")" "${LOG_FILE}" 2>/dev/null || cat "${LOG_FILE}")
else
  FILTERED=$(cat "${LOG_FILE}")
fi

TOTAL=$(echo "${FILTERED}" | grep -c '^{' 2>/dev/null || echo "0")

if [ "${TOTAL}" -eq 0 ]; then
  if [ "${JSON_OUTPUT}" = true ]; then
    echo '{"total":0,"entries":[],"summary":"No events in the specified period."}'
  else
    echo "StopFailure events in the last ${DAYS} days: 0"
  fi
  exit 0
fi

# Counts by error code
COUNT_429=$(echo "${FILTERED}" | jq -r 'select(.error_code == "429") | .error_code' 2>/dev/null | wc -l | tr -d ' ')
COUNT_401=$(echo "${FILTERED}" | jq -r 'select(.error_code == "401") | .error_code' 2>/dev/null | wc -l | tr -d ' ')
COUNT_500=$(echo "${FILTERED}" | jq -r 'select(.error_code == "500") | .error_code' 2>/dev/null | wc -l | tr -d ' ')
COUNT_OTHER=$(( TOTAL - COUNT_429 - COUNT_401 - COUNT_500 ))
[ "${COUNT_OTHER}" -lt 0 ] && COUNT_OTHER=0

# 5 most recent
RECENT=$(echo "${FILTERED}" | tail -5 | jq -r '[.timestamp, .error_code, .session_id, .message] | join(" | ")' 2>/dev/null || echo "(parse error)")

# === output ===
if [ "${JSON_OUTPUT}" = true ]; then
  jq -nc \
    --argjson total "${TOTAL}" \
    --argjson c429 "${COUNT_429}" \
    --argjson c401 "${COUNT_401}" \
    --argjson c500 "${COUNT_500}" \
    --argjson cother "${COUNT_OTHER}" \
    --argjson days "${DAYS}" \
    '{
      total: $total,
      period_days: $days,
      by_code: { "429": $c429, "401": $c401, "500": $c500, other: $cother }
    }'
else
  echo "StopFailure summary (last ${DAYS} days)"
  echo "========================================"
  echo ""
  echo "Total: ${TOTAL}"
  echo ""
  echo "Error distribution:"
  [ "${COUNT_429}" -gt 0 ] && echo "  429 (Rate Limit): ${COUNT_429}"
  [ "${COUNT_401}" -gt 0 ] && echo "  401 (Auth):       ${COUNT_401}"
  [ "${COUNT_500}" -gt 0 ] && echo "  500 (Server):     ${COUNT_500}"
  [ "${COUNT_OTHER}" -gt 0 ] && echo "  Other:            ${COUNT_OTHER}"
  [ "${TOTAL}" -eq 0 ] && echo "  (no events)"
  echo ""
  echo "5 most recent:"
  echo "${RECENT}" | while IFS= read -r line; do
    [ -n "${line}" ] && echo "  ${line}"
  done
  echo ""

  # Recommended actions
  if [ "${COUNT_429}" -ge 5 ]; then
    echo "Recommended: 429 errors are frequent. Reduce the number of parallel Breezing Workers."
  elif [ "${COUNT_429}" -ge 1 ]; then
    echo "Info: 429 errors occurred ${COUNT_429} time(s). If they recur, consider adjusting the Worker count."
  fi
  if [ "${COUNT_401}" -ge 1 ]; then
    echo "Recommended: authentication errors occurred. Refresh authentication with claude auth login."
  fi
fi
