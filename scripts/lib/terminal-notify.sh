#!/bin/bash
# terminal-notify.sh
# Shared helper that builds the CC 2.1.141+ hook JSON output `terminalSequence` field.
# Opt-in via the HARNESS_TERMINAL_NOTIFY env (details: .claude/rules/hooks-2.1.139-plus.md)
#
# Usage: after sourcing, call build_terminal_sequence "<title>" "<body>" to
#        print an OSC sequence string to stdout. Returns an empty string if the env is unset.
#
# Env: HARNESS_TERMINAL_NOTIFY (optional)
#   unset / "0" : do not output a sequence
#   "1" / "bell" : BEL (\x07)
#   "title"     : OSC 0 window title update
#   "osc9"      : OSC 9 macOS / iTerm notification
#   "notify"    : OSC 777 KDE/GNOME desktop notification
#
# Security:
#   - Strip control characters from title / body (prevent terminal corruption)
#   - Allow non-ASCII printable characters, but never include ESC / BEL / ST, etc.

set -euo pipefail

# Strip control characters (0x00-0x1F, 0x7F)
# Args:
#   $1: input string
# Stdout: the string with control characters removed
_terminal_notify_sanitize() {
  # printf would interpret \xXX, so strip safely with tr
  printf '%s' "${1:-}" | tr -d '\000-\037\177' 2>/dev/null || true
}

# Build the terminal sequence
# Args:
#   $1: title (e.g. "Build complete")
#   $2: body (optional, used only with OSC 777)
# Stdout: the built sequence string (escaped, JSON-safe)
build_terminal_sequence() {
  local mode="${HARNESS_TERMINAL_NOTIFY:-}"
  local title body
  title="$(_terminal_notify_sanitize "${1:-}")"
  body="$(_terminal_notify_sanitize "${2:-}")"

  # Empty string if opt-in is unset
  case "${mode}" in
    ''|0) return 0 ;;
  esac

  # bell does not use the title, so it fires even when empty.
  # For other modes, do not generate a sequence if the title is empty.
  if [ "${mode}" != "1" ] && [ "${mode}" != "bell" ] && [ -z "${title}" ]; then
    return 0
  fi

  # ESC = \x1b, BEL = \x07, ST = \x1b\\
  local ESC BEL
  ESC=$'\x1b'
  BEL=$'\x07'

  case "${mode}" in
    1|bell)
      printf '%s' "${BEL}"
      ;;
    title)
      printf '%s]0;%s%s' "${ESC}" "${title}" "${BEL}"
      ;;
    osc9)
      printf '%s]9;%s%s' "${ESC}" "${title}" "${BEL}"
      ;;
    notify)
      # OSC 777;notify;title;body
      if [ -n "${body}" ]; then
        printf '%s]777;notify;%s;%s%s' "${ESC}" "${title}" "${body}" "${BEL}"
      else
        printf '%s]777;notify;%s%s' "${ESC}" "${title}" "${BEL}"
      fi
      ;;
    *)
      # Unknown values are a no-op (silent ignore; value range documented in the rule)
      ;;
  esac
}

# Encode the built sequence into a JSON-safe string
# Use jq if available, otherwise a simple \u escape implementation
# Args:
#   $1: sequence (raw bytes)
# Stdout: a JSON string literal (without surrounding quotes)
encode_terminal_sequence_json() {
  local seq="${1:-}"
  if [ -z "${seq}" ]; then
    return 0
  fi
  if command -v jq >/dev/null 2>&1; then
    # jq -Rs encodes raw input into a JSON string (with quotes)
    # Output it expecting to be used directly as a JSON value without stripping quotes downstream
    printf '%s' "${seq}" | jq -Rs . 2>/dev/null || printf '""'
  else
    # Simple fallback: escape only ESC / BEL
    local out
    out="$(printf '%s' "${seq}" \
      | sed -e 's/\\/\\\\/g' \
            -e 's/"/\\"/g' \
            -e $'s/\x1b/\\\\u001b/g' \
            -e $'s/\x07/\\\\u0007/g')"
    printf '"%s"' "${out}"
  fi
}
