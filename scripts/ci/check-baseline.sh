#!/usr/bin/env bash
# scripts/ci/check-baseline.sh
# Syntax/JSON validation runner for the chanpark-harness plugin repo.
#
# Usage:
#   bash scripts/ci/check-baseline.sh                   # validate all git-tracked *.sh and *.json
#   bash scripts/ci/check-baseline.sh file1 file2 ...   # validate specific files only
#
# Exit: 0 when all non-skiplisted files pass; 1 otherwise.
# shellcheck: run if available; report warnings but only ERROR-level findings are fatal.

set -eu

# ---------------------------------------------------------------------------
# KNOWN_BAD: skip-list for pre-existing failures at baseline creation.
# legacy failures at baseline creation (2026-07-03) — ratchet: do not add entries
# ---------------------------------------------------------------------------
KNOWN_BAD=""
# (empty — no pre-existing failures detected at HEAD during baseline creation)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

is_known_bad() {
  local f="$1"
  local entry
  for entry in $KNOWN_BAD; do
    if [ "$entry" = "$f" ]; then
      return 0
    fi
  done
  return 1
}

validate_sh() {
  local f="$1"
  if is_known_bad "$f"; then
    echo "SKIP (known-bad): $f"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    return
  fi
  if bash -n "$f" 2>/dev/null; then
    echo "PASS (bash -n): $f"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL (bash -n): $f"
    bash -n "$f" 2>&1 | sed 's/^/  /' || true
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

validate_json() {
  local f="$1"
  if is_known_bad "$f"; then
    echo "SKIP (known-bad): $f"
    SKIP_COUNT=$((SKIP_COUNT + 1))
    return
  fi
  if jq empty "$f" 2>/dev/null; then
    echo "PASS (jq empty): $f"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL (jq empty): $f"
    jq empty "$f" 2>&1 | sed 's/^/  /' || true
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_shellcheck() {
  local f="$1"
  if ! command -v shellcheck > /dev/null 2>&1; then
    return 0  # shellcheck unavailable — skip silently (already reported once)
  fi
  # Run shellcheck; capture exit code separately from output
  local sc_out
  sc_out=$(shellcheck -S error "$f" 2>&1) || {
    echo "FAIL (shellcheck ERROR): $f"
    printf '%s\n' "$sc_out" | sed 's/^/  /'
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  }
  # Run at warning level to report (non-fatal)
  local sc_warn
  sc_warn=$(shellcheck -S warning "$f" 2>&1) || true
  if [ -n "$sc_warn" ]; then
    echo "WARN (shellcheck): $f"
    printf '%s\n' "$sc_warn" | sed 's/^/  /'
  fi
}

validate_file() {
  local f="$1"
  case "$f" in
    *.sh)
      validate_sh "$f"
      run_shellcheck "$f"
      ;;
    *.json)
      validate_json "$f"
      ;;
    *)
      # Unknown extension — skip silently
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Shellcheck availability banner (print once)
# ---------------------------------------------------------------------------
if ! command -v shellcheck > /dev/null 2>&1; then
  echo "shellcheck: not available, skipped"
fi

# ---------------------------------------------------------------------------
# Main: file args or full git-tracked scan
# ---------------------------------------------------------------------------
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    validate_file "$f"
  done
else
  # Full repo scan: all git-tracked *.sh and *.json, excluding bin/ and node_modules/
  while IFS= read -r f; do
    validate_file "$f"
  done < <(git ls-files '*.sh' '*.json' | grep -v '^bin/' | grep -v '^node_modules/')
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Summary: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  SKIP=$SKIP_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
