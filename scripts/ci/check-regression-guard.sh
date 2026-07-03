#!/usr/bin/env bash
# scripts/ci/check-regression-guard.sh
# Named-check regression guard for chanpark-harness plugin invariants.
#
# Each check emits:
#   PASS: <id>
#   FAIL: <id> — <detail>
#   SKIP: <id> — <reason>
#
# Exit: 0 if no FAIL; 1 if any FAIL.
#
# To add a new check: define a function check_<name>() and call run_check <id> check_<name>.

set -eu

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0

# ---------------------------------------------------------------------------
# Runner helper
# ---------------------------------------------------------------------------
run_check() {
  local id="$1"
  local fn="$2"
  local result
  result=$("$fn" 2>&1) || true
  case "$result" in
    PASS*)
      echo "$result"
      PASS_COUNT=$((PASS_COUNT + 1))
      ;;
    SKIP*)
      echo "$result"
      SKIP_COUNT=$((SKIP_COUNT + 1))
      ;;
    FAIL*)
      echo "$result"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
    *)
      # Unexpected output — treat as FAIL
      echo "FAIL: $id — unexpected check output: $result"
      FAIL_COUNT=$((FAIL_COUNT + 1))
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Check: identity
# harness.toml [project] name AND version must equal plugin.json name/version.
# EXPECTED TO FAIL at current HEAD (claude-code-harness/4.16.0 vs chanpark-harness/1.2.2).
# ---------------------------------------------------------------------------
check_identity() {
  local toml_file=".claude-plugin/../harness.toml"
  local plugin_file=".claude-plugin/plugin.json"

  if [ ! -f "$toml_file" ]; then
    toml_file="harness.toml"
  fi

  if [ ! -f "$toml_file" ] || [ ! -f "$plugin_file" ]; then
    echo "FAIL: identity — required files not found (harness.toml or .claude-plugin/plugin.json)"
    return
  fi

  # Parse harness.toml [project] section with grep/sed (no external toml tool)
  local toml_name toml_version in_project
  toml_name=""
  toml_version=""
  in_project=0
  while IFS= read -r line; do
    case "$line" in
      "[project]")
        in_project=1
        ;;
      "["*)
        if [ "$in_project" = "1" ]; then
          in_project=0
        fi
        ;;
      *)
        if [ "$in_project" = "1" ]; then
          case "$line" in
            name\ =\ *)
              toml_name=$(printf '%s' "$line" | sed 's/^name *= *"\(.*\)"/\1/' | sed 's/^name *= *\(.*\)/\1/')
              ;;
            version\ =\ *)
              toml_version=$(printf '%s' "$line" | sed 's/^version *= *"\(.*\)"/\1/' | sed 's/^version *= *\(.*\)/\1/')
              ;;
          esac
        fi
        ;;
    esac
  done < "$toml_file"

  # Parse plugin.json name and version with jq
  local plugin_name plugin_version
  if ! command -v jq > /dev/null 2>&1; then
    echo "SKIP: identity — jq not available"
    return
  fi
  plugin_name=$(jq -r '.name // empty' "$plugin_file" 2>/dev/null)
  plugin_version=$(jq -r '.version // empty' "$plugin_file" 2>/dev/null)

  if [ -z "$toml_name" ] || [ -z "$toml_version" ]; then
    echo "FAIL: identity — could not parse harness.toml [project] name/version"
    return
  fi
  if [ -z "$plugin_name" ] || [ -z "$plugin_version" ]; then
    echo "FAIL: identity — could not parse plugin.json name/version"
    return
  fi

  if [ "$toml_name" = "$plugin_name" ] && [ "$toml_version" = "$plugin_version" ]; then
    echo "PASS: identity"
  else
    echo "FAIL: identity — harness.toml has name=$toml_name version=$toml_version but plugin.json has name=$plugin_name version=$plugin_version"
  fi
}

# ---------------------------------------------------------------------------
# Check: grep-path
# Zero occurrences of /usr/bin/grep in hooks/hooks.json + monitors/monitors.json.
# EXPECTED TO FAIL at current HEAD (66 occurrences).
# ---------------------------------------------------------------------------
check_grep_path() {
  local hooks_file="hooks/hooks.json"
  local monitors_file="monitors/monitors.json"
  local count=0
  local missing=""

  if [ ! -f "$hooks_file" ]; then
    missing="$hooks_file"
  fi
  if [ ! -f "$monitors_file" ]; then
    if [ -n "$missing" ]; then
      missing="$missing, $monitors_file"
    else
      missing="$monitors_file"
    fi
  fi
  if [ -n "$missing" ]; then
    echo "FAIL: grep-path — file(s) not found: $missing"
    return
  fi

  count=$(grep -c '/usr/bin/grep' "$hooks_file" "$monitors_file" 2>/dev/null | awk -F: '{sum+=$2} END{print sum}' || echo 0)

  if [ "$count" = "0" ]; then
    echo "PASS: grep-path"
  else
    echo "FAIL: grep-path — $count occurrences of /usr/bin/grep found in hooks/hooks.json and monitors/monitors.json"
  fi
}

# ---------------------------------------------------------------------------
# Check: sync-no-dup
# .claude-plugin/hooks.json must not exist (legacy duplicate; bin/harness sync can resurrect it).
# Expected PASS.
# ---------------------------------------------------------------------------
check_sync_no_dup() {
  if [ -f ".claude-plugin/hooks.json" ]; then
    echo "FAIL: sync-no-dup — .claude-plugin/hooks.json exists (legacy duplicate; remove it and do not run 'bin/harness sync')"
  else
    echo "PASS: sync-no-dup"
  fi
}

# ---------------------------------------------------------------------------
# Check: english-only
# No CJK characters in agents/ skills/ output-styles/ templates/.
# Portability: try grep -rlP; fall back to python3; SKIP if neither available.
# Expected PASS.
# ---------------------------------------------------------------------------
check_english_only() {
  local dirs="agents skills output-styles templates"
  local result=""

  # Check which directories exist
  local existing_dirs=""
  for d in $dirs; do
    if [ -d "$d" ]; then
      existing_dirs="$existing_dirs $d"
    fi
  done
  existing_dirs="${existing_dirs# }"

  if [ -z "$existing_dirs" ]; then
    echo "SKIP: english-only — none of the target directories exist"
    return
  fi

  # Try grep -P (GNU grep with PCRE)
  if grep --version 2>/dev/null | grep -q 'GNU\|PCRE'; then
    if grep -rlP '[\x{3040}-\x{30ff}\x{4e00}-\x{9fff}]' $existing_dirs > /tmp/cjk-found.txt 2>/dev/null; then
      result=$(cat /tmp/cjk-found.txt)
      rm -f /tmp/cjk-found.txt
      echo "FAIL: english-only — CJK characters found in: $result"
      return
    fi
    rm -f /tmp/cjk-found.txt
    echo "PASS: english-only"
    return
  fi

  # Fallback: try python3
  if command -v python3 > /dev/null 2>&1; then
    local py_result
    py_result=$(python3 - $existing_dirs <<'PYEOF'
import sys, os, re

CJK_RE = re.compile(r'[぀-ヿ一-鿿]')
found = []
for d in sys.argv[1:]:
    for root, dirs, files in os.walk(d):
        for fname in files:
            fpath = os.path.join(root, fname)
            try:
                with open(fpath, encoding='utf-8', errors='replace') as fh:
                    if CJK_RE.search(fh.read()):
                        found.append(fpath)
            except OSError:
                pass
for f in found:
    print(f)
PYEOF
)
    if [ -n "$py_result" ]; then
      echo "FAIL: english-only — CJK characters found in: $py_result"
    else
      echo "PASS: english-only"
    fi
    return
  fi

  echo "SKIP: english-only — no PCRE grep or python3"
}

# ---------------------------------------------------------------------------
# Check: marker-style — no mixed-case marker write form in shipped content
# (pattern split to avoid self-match)
# ---------------------------------------------------------------------------
check_marker_style() {
  local pat matches
  pat='cc:D''one'
  matches=$(grep -rn "$pat" skills templates scripts --exclude="check-regression-guard.sh" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "FAIL: marker-style — mixed-case marker found: $(echo "$matches" | head -3)"
  else
    echo "PASS: marker-style"
  fi
}

# ---------------------------------------------------------------------------
# Check: template-registry — templates/ dir and template-registry.json consistent
# ---------------------------------------------------------------------------
check_template_registry() {
  if [ ! -f scripts/ci/check-template-registry.sh ]; then
    echo "SKIP: template-registry — checker script missing"
    return
  fi
  if bash scripts/ci/check-template-registry.sh > /dev/null 2>&1; then
    echo "PASS: template-registry"
  else
    echo "FAIL: template-registry — scripts/ci/check-template-registry.sh exited non-zero"
  fi
}

# ---------------------------------------------------------------------------
# Run all checks
# ---------------------------------------------------------------------------
run_check "identity"   check_identity
run_check "grep-path"  check_grep_path
run_check "sync-no-dup" check_sync_no_dup
run_check "english-only" check_english_only
run_check "marker-style" check_marker_style
run_check "template-registry" check_template_registry

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Summary: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  SKIP=$SKIP_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
