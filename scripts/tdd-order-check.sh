#!/bin/bash
# tdd-order-check.sh
# TDD is enabled by default. Emit a warning that recommends tests-first (does not block)
#
# Purpose: run after Write|Edit in PostToolUse
# Behavior:
#   - When Plans.md has a cc:WIP task (TDD enabled by default)
#   - But skip WIP tasks that carry the [skip:tdd] marker
#   - A source file (*.ts, *.tsx, *.js, *.jsx) was edited
#   - The corresponding test file (*.test.*, *.spec.*) has not been edited yet
#   -> Print a warning message (does not block)

set -euo pipefail

# Get info about the edited file
TOOL_INPUT="${TOOL_INPUT:-}"
FILE_PATH=""

# Extract file_path from TOOL_INPUT (works on both macOS/Linux)
if [[ -n "$TOOL_INPUT" ]]; then
    # Use jq when available (safest)
    if command -v jq &>/dev/null; then
        FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty' 2>/dev/null || true)
    else
        # Fallback: extract with sed (POSIX compatible)
        FILE_PATH=$(echo "$TOOL_INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null || true)
    fi
fi

# Exit if there is no file path
if [[ -z "$FILE_PATH" ]]; then
    exit 0
fi

# Check whether the file is a test file
is_test_file() {
    local file="$1"
    [[ "$file" =~ \.(test|spec)\.(ts|tsx|js|jsx)$ ]] || \
    [[ "$file" =~ __tests__/ ]] || \
    [[ "$file" =~ /tests?/ ]]
}

# Check whether the file is a source file (excluding test files)
is_source_file() {
    local file="$1"
    [[ "$file" =~ \.(ts|tsx|js|jsx)$ ]] && ! is_test_file "$file"
}

# Check whether there is an active WIP task
has_active_wip_task() {
    if [[ -f "Plans.md" ]]; then
        grep -q 'cc:WIP' Plans.md 2>/dev/null
        return $?
    fi
    return 1
}

# Check whether the WIP task carries the [skip:tdd] marker
is_tdd_skipped() {
    if [[ -f "Plans.md" ]]; then
        grep -q '\[skip:tdd\].*cc:WIP\|cc:WIP.*\[skip:tdd\]' Plans.md 2>/dev/null
        return $?
    fi
    return 1
}

# Check whether a test file was edited during this session (simplified)
test_edited_this_session() {
    # Check .claude/state/session-changes.json if present
    local state_file=".claude/state/session-changes.json"
    if [[ -f "$state_file" ]]; then
        grep -q '\.test\.\|\.spec\.\|__tests__' "$state_file" 2>/dev/null
        return $?
    fi
    return 1
}

# Main processing
main() {
    # Skip if not a source file
    if ! is_source_file "$FILE_PATH"; then
        exit 0
    fi

    # Skip if it is a test file
    if is_test_file "$FILE_PATH"; then
        exit 0
    fi

    # Skip if there is no WIP task
    if ! has_active_wip_task; then
        exit 0
    fi

    # Skip if the [skip:tdd] marker is present
    if is_tdd_skipped; then
        exit 0
    fi

    # Skip if a test file has already been edited
    if test_edited_this_session; then
        exit 0
    fi

    # Print a warning (does not block)
    cat << 'EOF'
{
  "decision": "approve",
  "reason": "TDD reminder",
  "systemMessage": "TDD is enabled by default. Writing tests first is recommended.\n\nYou just edited a source file, but its corresponding test file has not been edited yet.\n\nRecommendation: create the test file (*.test.ts, *.spec.ts) first, then implement the source.\n\nTo skip, add the [skip:tdd] marker to the relevant task in Plans.md.\n\nThis is a warning and does not block."
}
EOF
}

main
