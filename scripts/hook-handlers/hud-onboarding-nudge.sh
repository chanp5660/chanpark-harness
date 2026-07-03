#!/bin/bash
# hud-onboarding-nudge.sh
# SessionStart hook handler: discoverability nudge for the optional HUD status line.
#
# The plugin cannot ship a main `statusLine` via its manifest, so first-time users
# may never learn that `/chanpark-harness:hud setup` exists. This handler emits a
# one-line tip when NO status line is configured yet. It is deliberately
# non-intrusive: if the user already has any `statusLine` (the chanpark HUD or their
# own), it stays silent and never touches their settings.
#
# Output: SessionStart hookSpecificOutput JSON (additionalContext).
# Usage: bash hud-onboarding-nudge.sh
# Hook event: SessionStart

set -euo pipefail

# Consume any piped JSON input so the hook never breaks on stdin.
if [ ! -t 0 ]; then
  cat >/dev/null 2>&1 || true
fi

emit() {
  # $1 = additionalContext string (already JSON-safe; we only ever pass fixed literals)
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$1"
}

# Explicit opt-out: marker file or env variable suppresses the nudge permanently.
if [ "${CHANPARK_HUD_NUDGE_OFF:-}" = "1" ] || [ -f "${HOME}/.claude/state/chanpark-hud-nudge-off" ]; then
  exit 0
fi

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

# A status line is considered "configured" if the "statusLine" KEY IS PRESENT (any value,
# including null). Both detection paths use identical "key present" semantics so jq and
# the grep fallback agree. Previously jq used `// null` which treated null as absent —
# that caused re-nudging after `/hud off` (which sets statusLine to null or removes it).
# Now: key present = configured, key absent = not configured, in all paths.
#
# We also check settings.local.json and the project-level .claude/settings.json so that
# users who configured statusLine in those files are not re-nudged.
_has_statusline_key() {
  local f="$1"
  [ -f "$f" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e 'has("statusLine")' "$f" >/dev/null 2>&1
  else
    grep -q '"statusLine"' "$f" 2>/dev/null
  fi
}

configured="false"
for _settings_file in \
    "$CONFIG_DIR/settings.json" \
    "$CONFIG_DIR/settings.local.json" \
    "${CLAUDE_PROJECT_DIR:-.}/.claude/settings.json"
do
  if _has_statusline_key "$_settings_file"; then
    configured="true"
    break
  fi
done

if [ "$configured" = "true" ]; then
  # User already has a status line configured — respect their choice, emit nothing at all.
  exit 0
fi

emit "💡 HUD status line not configured — run /chanpark-harness:hud setup to enable it (model · ctx% · git · Plans.md task counts). Optional; ignore to skip."
exit 0
