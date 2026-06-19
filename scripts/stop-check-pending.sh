#!/bin/bash
# stop-check-pending.sh
# On Stop, check for unresolved pending-skills and warn
#
# Usage: run automatically from the Stop hook (type: command)
# Input: stdin JSON (Claude Code hooks)
# Output: human-readable text warning (written directly to stdout)

set +e

STATE_DIR=".claude/state"
PENDING_DIR="${STATE_DIR}/pending-skills"

# If the pending directory does not exist, exit without output
if [ ! -d "$PENDING_DIR" ]; then
  exit 0
fi

# Check pending files
PENDING_FILES=$(ls "$PENDING_DIR"/*.pending 2>/dev/null || true)

if [ -z "$PENDING_FILES" ]; then
  exit 0
fi

# When there are unresolved pending entries
PENDING_COMMANDS=""
for f in $PENDING_FILES; do
  CMD_NAME=$(basename "$f" .pending)
  PENDING_COMMANDS="${PENDING_COMMANDS}${CMD_NAME}, "
done
PENDING_COMMANDS=$(echo "$PENDING_COMMANDS" | sed 's/, $//')

# Clear pending entries (already warned)
rm -f "$PENDING_DIR"/*.pending 2>/dev/null || true

# Write the human-readable text warning to stdout
cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚠️  Quality gate not run — warning
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The following commands ran, but the corresponding Skill was not invoked:
  → ${PENDING_COMMANDS}

This may lead to the following issues:
  1. Missing usage statistics: Skill usage history was not recorded
  2. Quality guardrails not run: review/verification skills may not have been applied

Recommended: manually run /harness-review to perform a quality check.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

EOF

exit 0
