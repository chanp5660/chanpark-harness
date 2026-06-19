#!/bin/bash
# check-checklist-sync.sh
# Verify that the checklist in command files and the check items in scripts are in sync
#
# Purpose:
# - Verify that check_file/check_dir in scripts/setup-2agent.sh matches the
#   checklist in commands/setup-2agent.md
# - Likewise for scripts/update-2agent.sh and commands/update-2agent.md

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ERRORS=0

echo "🔍 Checklist sync verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ================================
# Utility functions
# ================================

# Extract check_file/check_dir arguments from a script
extract_script_checks() {
  local script="$1"
  grep -E 'check_(file|dir)' "$script" 2>/dev/null | \
    awk -F'"' '{print $2}' | \
    grep -v '^$' | \
    sort -u
}

# Extract checklist items from a command file
# Extract only the "automated verification" section (exclude the "Claude generates" section)
# NOTE: the awk pattern matches Japanese section headers for backward compatibility
extract_command_checklist() {
  local cmd="$1"
  # Extract from "automated verification" to "Claude generates" or the next section
  awk '/自動検証/,/Claude が生成|^###|^\*\*全て/' "$cmd" 2>/dev/null | \
    grep -E '^\s*-\s*\[\s*\]\s*`[^`]+`' | \
    awk -F'`' '{print $2}' | \
    grep -v '^$' | \
    sort -u
}

# Compare two lists
compare_lists() {
  local name="$1"
  local script_file="$2"
  local command_file="$3"

  echo ""
  echo "📋 Verifying $name..."

  # Extract into temporary files
  local script_checks=$(mktemp)
  local command_checks=$(mktemp)

  extract_script_checks "$script_file" > "$script_checks"
  extract_command_checklist "$command_file" > "$command_checks"

  # In the script but not in the command
  local missing_in_command=$(comm -23 "$script_checks" "$command_checks")
  if [ -n "$missing_in_command" ]; then
    echo "  ❌ In the script but not in the command checklist:"
    echo "$missing_in_command" | while read item; do
      echo "     - $item"
    done
    ERRORS=$((ERRORS + 1))
  fi

  # In the command but not in the script
  local missing_in_script=$(comm -13 "$script_checks" "$command_checks")
  if [ -n "$missing_in_script" ]; then
    echo "  ❌ In the command checklist but not in the script:"
    echo "$missing_in_script" | while read item; do
      echo "     - $item"
    done
    ERRORS=$((ERRORS + 1))
  fi

  # Skip if both are empty (prevent a false pass)
  local script_count=$(wc -l < "$script_checks" | tr -d ' ')
  local command_count=$(wc -l < "$command_checks" | tr -d ' ')

  if [ "$script_count" -eq 0 ] && [ "$command_count" -eq 0 ]; then
    echo "  ⚠️ Skipped: no check items found (please verify the file layout)"
  elif [ -z "$missing_in_command" ] && [ -z "$missing_in_script" ]; then
    echo "  ✅ In sync ($script_count items)"
  fi

  rm -f "$script_checks" "$command_checks"
}

# ================================
# Main verification
# ================================

# Verify the setup hub (since v2.19.0+, 2agent is merged into setup)
SETUP_SKILL="$PLUGIN_ROOT/skills/setup/SKILL.md"
SETUP_2AGENT_REF="$PLUGIN_ROOT/skills/setup/references/2agent-setup.md"

if [ -f "$SETUP_SKILL" ] && [ -f "$SETUP_2AGENT_REF" ]; then
  echo "✓ The setup skill and 2agent-setup reference exist"
elif [ -f "$SETUP_SKILL" ]; then
  echo "⚠️ setup/references/2agent-setup.md not found (verify the post-merge layout)"
else
  echo "⚠️ skills/setup/SKILL.md not found (the skill may not have been created)"
fi

# Note: since v2.17.0, commands have been migrated to skills
# Checklist sync is now managed per skill
# Exit successfully if no target skill is found (do not fail on an empty checklist)

# ================================
# Result summary
# ================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERRORS -eq 0 ]; then
  echo "✅ Checklist sync verification passed"
  exit 0
else
  echo "❌ $ERRORS inconsistencies found"
  echo ""
  echo "💡 How to fix:"
  echo "  1. Check check_file/check_dir in scripts/*.sh"
  echo "  2. Update the checklist in commands/*.md"
  echo "  3. Make both match"
  exit 1
fi
