#!/usr/bin/env bash
# subagent-tracker.sh
# Tracker for the Claude Code 2.1.0 SubagentStart/SubagentStop hooks
#
# Usage:
#   ./subagent-tracker.sh start   # at subagent start
#   ./subagent-tracker.sh stop    # at subagent stop
#
# Environment variables (available at SubagentStop):
#   AGENT_ID              - subagent identifier
#   AGENT_TRANSCRIPT_PATH - path to the transcript file

set -euo pipefail

# === configuration ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/path-utils.sh" 2>/dev/null || true

# Detect the project root
PROJECT_ROOT="${PROJECT_ROOT:-$(detect_project_root 2>/dev/null || pwd)}"

# Log directory
LOG_DIR="${PROJECT_ROOT}/.claude/logs"
SUBAGENT_LOG="${LOG_DIR}/subagent-history.jsonl"

# === utility functions ===

ensure_log_dir() {
  mkdir -p "${LOG_DIR}" 2>/dev/null || true
}

get_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# === main processing ===

action="${1:-}"

case "${action}" in
  start)
    ensure_log_dir

    # Get information from environment variables (when available)
    agent_id="${AGENT_ID:-unknown}"

    # Create the log entry
    log_entry=$(cat <<EOF
{"event":"subagent_start","timestamp":"$(get_timestamp)","agent_id":"${agent_id}"}
EOF
)

    # Append in JSONL format
    echo "${log_entry}" >> "${SUBAGENT_LOG}" 2>/dev/null || true

    # Success response (JSON format the hook expects)
    echo '{"decision":"approve","reason":"Subagent start tracked"}'
    ;;

  stop)
    ensure_log_dir

    # Get information from environment variables
    agent_id="${AGENT_ID:-unknown}"
    transcript_path="${AGENT_TRANSCRIPT_PATH:-}"

    # Get a transcript summary (if it exists)
    transcript_summary=""
    if [[ -n "${transcript_path}" && -f "${transcript_path}" ]]; then
      # Take the last 50 lines and summarize
      transcript_summary=$(tail -50 "${transcript_path}" 2>/dev/null | head -c 500 || echo "")
      transcript_summary="${transcript_summary//\"/\\\"}"  # escape
      transcript_summary="${transcript_summary//$'\n'/\\n}"  # escape newlines
    fi

    # Create the log entry
    log_entry=$(cat <<EOF
{"event":"subagent_stop","timestamp":"$(get_timestamp)","agent_id":"${agent_id}","transcript_path":"${transcript_path}","transcript_preview":"${transcript_summary:0:200}"}
EOF
)

    # Append in JSONL format
    echo "${log_entry}" >> "${SUBAGENT_LOG}" 2>/dev/null || true

    # Success response
    echo '{"decision":"approve","reason":"Subagent stop tracked"}'
    ;;

  *)
    echo '{"decision":"approve","reason":"Unknown action, skipping"}'
    ;;
esac

exit 0
