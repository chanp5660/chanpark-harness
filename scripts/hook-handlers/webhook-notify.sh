#!/bin/bash
# webhook-notify.sh
# POST to an external webhook only when HARNESS_WEBHOOK_URL is set.
# The HTTP hook's url field does not expand environment variables,
# so this is implemented with a command hook + curl.
#
# Usage: bash webhook-notify.sh <event-name>
# Input: stdin JSON from Claude Code hooks
# Env:
#   HARNESS_WEBHOOK_URL (optional, skip if unset) — external webhook POST
#   HARNESS_TERMINAL_NOTIFY (optional) — CC 2.1.141+ terminalSequence opt-in
#     Details: .claude/rules/hooks-2.1.139-plus.md

set -euo pipefail

EVENT_NAME="${1:-unknown}"

# Load the terminalSequence helper (CC 2.1.141+)
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${_SCRIPT_DIR}/../lib/terminal-notify.sh" ]; then
  # shellcheck disable=SC1091
  source "${_SCRIPT_DIR}/../lib/terminal-notify.sh"
fi

# Helper that builds the terminalSequence JSON field for output.
# Args: $1 = title, $2 = body (optional)
# Stdout: `,"terminalSequence":"..."` or an empty string
_render_terminal_sequence_field() {
  if ! command -v build_terminal_sequence >/dev/null 2>&1; then
    return 0
  fi
  local _seq _encoded
  _seq="$(build_terminal_sequence "${1:-}" "${2:-}")"
  if [ -z "${_seq}" ]; then
    return 0
  fi
  _encoded="$(encode_terminal_sequence_json "${_seq}")"
  if [ -n "${_encoded}" ]; then
    printf ',"terminalSequence":%s' "${_encoded}"
  fi
}

# If HARNESS_WEBHOOK_URL is unset, do nothing and exit (opt-in).
# But if only terminalSequence is opted in, fire a local notification.
if [ -z "${HARNESS_WEBHOOK_URL:-}" ]; then
  _ts_field="$(_render_terminal_sequence_field "Claude Code: ${EVENT_NAME}" "")"
  if [ -n "${_ts_field}" ]; then
    printf '{"decision":"approve","reason":"webhook URL not configured; local terminal notify only"%s}\n' "${_ts_field}"
  else
    echo '{"decision":"approve","reason":"webhook URL not configured, skipping"}'
  fi
  exit 0
fi

# Read the hook payload from stdin
PAYLOAD=""
if [ ! -t 0 ]; then
  PAYLOAD=$(cat)
fi

# Mask the URL (secret protection: show only the scheme)
# Hides user:pass@host, ?token=xxx, /services/T00/B00/xxx, etc.
MASKED_URL="$(echo "${HARNESS_WEBHOOK_URL}" | sed -E 's|^(https?://).*|\1***/***|')"

# POST with curl (5 second timeout; on failure still approve and continue, but report the result)
HTTP_CODE=""
CURL_EXIT=0
HTTP_CODE=$(curl --silent --output /dev/null --write-out "%{http_code}" --max-time 5 \
  --request POST \
  --header "Content-Type: application/json" \
  --header "X-Harness-Event: ${EVENT_NAME}" \
  --data "${PAYLOAD:-"{}"}" \
  "${HARNESS_WEBHOOK_URL}" 2>/dev/null) || CURL_EXIT=$?

# terminalSequence payload (emit a title for success/failure each)
_TS_FIELD_SUCCESS="$(_render_terminal_sequence_field "Claude Code: ${EVENT_NAME}" "webhook sent")"
_TS_FIELD_FAILURE="$(_render_terminal_sequence_field "Claude Code: ${EVENT_NAME} (failed)" "webhook delivery failed")"

# Build JSON safely if jq is available, otherwise use a fixed message
if [ "$CURL_EXIT" -ne 0 ]; then
  if command -v jq >/dev/null 2>&1; then
    _BASE="$(jq -nc --arg reason "webhook delivery failed (curl exit $CURL_EXIT)" \
           --arg msg "[webhook-notify] POST to ${MASKED_URL} failed (curl exit $CURL_EXIT)" \
           '{"decision":"approve","reason":$reason,"systemMessage":$msg}')"
    if [ -n "${_TS_FIELD_FAILURE}" ]; then
      printf '%s\n' "${_BASE%\}}${_TS_FIELD_FAILURE}}"
    else
      printf '%s\n' "${_BASE}"
    fi
  else
    printf '{"decision":"approve","reason":"webhook delivery failed","systemMessage":"[webhook-notify] POST failed"%s}\n' "${_TS_FIELD_FAILURE}"
  fi
elif [ "${HTTP_CODE:-000}" -ge 200 ] && [ "${HTTP_CODE:-000}" -lt 300 ] 2>/dev/null; then
  printf '{"decision":"approve","reason":"webhook notification sent"%s}\n' "${_TS_FIELD_SUCCESS}"
else
  if command -v jq >/dev/null 2>&1; then
    _BASE="$(jq -nc --arg reason "webhook returned HTTP ${HTTP_CODE}" \
           --arg msg "[webhook-notify] POST to ${MASKED_URL} returned HTTP ${HTTP_CODE}" \
           '{"decision":"approve","reason":$reason,"systemMessage":$msg}')"
    if [ -n "${_TS_FIELD_FAILURE}" ]; then
      printf '%s\n' "${_BASE%\}}${_TS_FIELD_FAILURE}}"
    else
      printf '%s\n' "${_BASE}"
    fi
  else
    printf '{"decision":"approve","reason":"webhook returned HTTP %s","systemMessage":"[webhook-notify] POST returned HTTP %s"%s}\n' "${HTTP_CODE}" "${HTTP_CODE}" "${_TS_FIELD_FAILURE}"
  fi
fi
