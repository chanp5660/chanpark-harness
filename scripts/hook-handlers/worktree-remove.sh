#!/bin/bash
# worktree-remove.sh — WorktreeRemove hook handler
# Clean up worktree-specific resources when a Breezing subagent finishes.
#
# Input (stdin JSON):
#   session_id, cwd, hook_event_name
#
# Design: handles only worktree-specific temporary files.
#         Whole-session cleanup is handled by SessionEnd.

set -euo pipefail

# === Read the JSON payload from stdin ===
INPUT=""
if [ ! -t 0 ]; then
  INPUT="$(cat 2>/dev/null)"
fi

# Skip if the payload is empty
if [ -z "${INPUT}" ]; then
  echo '{"decision":"approve","reason":"WorktreeRemove: no payload"}'
  exit 0
fi

# === Field extraction ===
SESSION_ID=""
CWD=""

if command -v jq >/dev/null 2>&1; then
  _jq_parsed="$(echo "${INPUT}" | jq -r '[
    (.session_id // ""),
    (.cwd // "")
  ] | @tsv' 2>/dev/null)"
  if [ -n "${_jq_parsed}" ]; then
    IFS=$'\t' read -r SESSION_ID CWD <<< "${_jq_parsed}"
  fi
  unset _jq_parsed
elif command -v python3 >/dev/null 2>&1; then
  _parsed="$(echo "${INPUT}" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('session_id', ''))
    print(d.get('cwd', ''))
except:
    print('')
    print('')
" 2>/dev/null)"
  SESSION_ID="$(echo "${_parsed}" | sed -n '1p')"
  CWD="$(echo "${_parsed}" | sed -n '2p')"
fi

if [ -z "${SESSION_ID}" ]; then
  echo '{"decision":"approve","reason":"WorktreeRemove: no session_id"}'
  exit 0
fi

# === Clean up worktree-specific temporary files ===

# Only remove temp files that belong to THIS session (identified by SESSION_ID).
# An empty/unset SESSION_ID would widen the glob to every session's files, so guard
# explicitly — even though SESSION_ID is already validated non-empty above.
if [ -n "${SESSION_ID}" ]; then
  # Codex prompt temp files scoped to this session
  rm -f /tmp/codex-prompt-*"${SESSION_ID}"*.md 2>/dev/null || true

  # Harness Codex logs scoped to this session
  rm -f /tmp/harness-codex-*"${SESSION_ID}"*.log 2>/dev/null || true
fi

# Clean up worktree-info.json
if [ -n "${CWD}" ] && [ -f "${CWD}/.claude/state/worktree-info.json" ]; then
  rm -f "${CWD}/.claude/state/worktree-info.json" 2>/dev/null || true
fi

# === Response ===
echo '{"decision":"approve","reason":"WorktreeRemove: cleaned up worktree resources"}'
exit 0
