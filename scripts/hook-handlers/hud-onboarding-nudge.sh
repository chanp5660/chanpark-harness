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

CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CONFIG_DIR/settings.json"

# A status line is considered "configured" if a non-null .statusLine key is present.
# Both detection paths use the same "key present" semantics so jq and the grep
# fallback agree: a user who has touched statusLine config is left alone.
configured="false"
if [ -f "$SETTINGS" ]; then
  if command -v jq >/dev/null 2>&1; then
    has_sl="$(jq -r 'if (.statusLine // null) == null then "no" else "yes" end' "$SETTINGS" 2>/dev/null || echo "no")"
    [ "$has_sl" = "yes" ] && configured="true"
  elif grep -q '"statusLine"' "$SETTINGS" 2>/dev/null; then
    configured="true"
  fi
fi

if [ "$configured" = "true" ]; then
  # User already has a status line — respect their choice, emit nothing at all.
  exit 0
fi

emit "💡 HUD status line not configured — run /chanpark-harness:hud setup to enable it (model · ctx% · git · Plans.md task counts). Optional; ignore to skip."
exit 0
