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
# Check: plans-marker-anchoring — markers count ONLY in a table status cell.
#
# Regression guard for v1.3.6. The vendored Go binary counted cc:* as unanchored
# substrings, so one prose sentence ("... moved to the archive (all cc:done)")
# inflated cc_done from 9 to 10 in .claude/state/plans-state.json. The fixture
# below carries that sentence plus a legend table, a fenced block, an HTML comment
# and a description cell quoting a marker; every one of them must be ignored.
# ---------------------------------------------------------------------------
check_plans_marker_anchoring() {
  local counter="scripts/lib/plans-markers.awk"
  local fixture="tests/fixtures/plans-prose-marker-inflation.md"
  local mixed="tests/fixtures/plans-mixed-markers.md"
  local got

  if [ ! -f "$counter" ]; then
    echo "FAIL: plans-marker-anchoring — $counter missing"
    return
  fi
  if [ ! -f "$fixture" ] || [ ! -f "$mixed" ]; then
    echo "SKIP: plans-marker-anchoring — fixtures missing"
    return
  fi

  # 9 table rows say done, 6 say todo; the prose/legend/fence/comment markers must
  # not be counted. An unanchored counter reports done=10 on this fixture.
  got="$(awk -f "$counter" "$fixture" 2> /dev/null)"
  if [ "$got" != "6 0 9 0 0 0" ]; then
    echo "FAIL: plans-marker-anchoring — $fixture counted as '$got', expected '6 0 9 0 0 0'"
    return
  fi

  # Cross-dialect fixture: 7 table rows (2 todo, 2 wip, 2 done, 1 blocked). Its
  # checklist lines and prose sentence are not table rows and must not be counted.
  got="$(awk -f "$counter" "$mixed" 2> /dev/null)"
  if [ "$got" != "2 2 2 1 0 0" ]; then
    echo "FAIL: plans-marker-anchoring — $mixed counted as '$got', expected '2 2 2 1 0 0'"
    return
  fi

  # The guard is only meaningful while the fixture still contains the trap.
  if ! grep -q '(all cc:done)' "$fixture" 2> /dev/null; then
    echo "FAIL: plans-marker-anchoring — $fixture lost its prose marker; the guard proves nothing"
    return
  fi

  echo "PASS: plans-marker-anchoring"
}

# ---------------------------------------------------------------------------
# Check: plans-watcher-handler — the PostToolUse hook dispatches to the anchored
# script, not to the vendored binary subcommand whose counter cannot be fixed here.
# ---------------------------------------------------------------------------
check_plans_watcher_handler() {
  local handler="scripts/hook-handlers/plans-watcher.sh"

  if [ ! -x "$handler" ]; then
    echo "FAIL: plans-watcher-handler — $handler missing or not executable"
    return
  fi
  if grep -q 'hook plans-watcher' hooks/hooks.json 2> /dev/null; then
    echo "FAIL: plans-watcher-handler — hooks.json still dispatches to the binary subcommand"
    return
  fi
  if ! grep -q 'hook-handlers/plans-watcher.sh' hooks/hooks.json 2> /dev/null; then
    echo "FAIL: plans-watcher-handler — hooks.json does not reference $handler"
    return
  fi

  echo "PASS: plans-watcher-handler"
}

# ---------------------------------------------------------------------------
# Check: progress-snapshot-rows — the snapshot sees every task row.
#
# Its former single regex pinned the table to five columns and demanded a bare
# marker in the status cell, so "cc:done (2026-07-14: measured on hw)" dropped the
# whole row: a nine-done Plans.md was reported as done=1.
# ---------------------------------------------------------------------------
check_progress_snapshot_rows() {
  local script="scripts/progress-snapshot.sh"
  local fixture="tests/fixtures/plans-prose-marker-inflation.md"
  local out got

  if [ ! -f "$script" ]; then
    echo "FAIL: progress-snapshot-rows — $script missing"
    return
  fi
  if [ ! -f "$fixture" ]; then
    echo "SKIP: progress-snapshot-rows — fixture missing"
    return
  fi
  if ! command -v python3 > /dev/null 2>&1; then
    echo "SKIP: progress-snapshot-rows — python3 unavailable"
    return
  fi

  out="$(bash "$script" --plans "$fixture" --project guard 2> /dev/null)"
  got="$(printf '%s' "$out" | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("%d %d %d %d" % (d["_todo_count"], d["_wip_count"], d["_done_count"], d["_blocked_count"]))' 2> /dev/null)"

  if [ "$got" != "6 0 9 0" ]; then
    echo "FAIL: progress-snapshot-rows — counted '$got', expected '6 0 9 0'"
    return
  fi

  echo "PASS: progress-snapshot-rows"
}

# ---------------------------------------------------------------------------
# Check: wip-guard-loop-breaker — the Stop guard can always be escaped.
#
# The guard used to rely solely on `stop_hook_active`, a field the HOST supplies.
# A host that omits it (observed with some third-party clients) left the guard
# emitting decision:block on every turn with no exit, so the session could never
# end. Two properties are pinned here:
#
#   1. Repeated stop payloads WITHOUT stop_hook_active must stop blocking.
#   2. A session that does not own the WIP is never blocked at all.
# ---------------------------------------------------------------------------
check_wip_guard_loop_breaker() {
  local guard="scripts/hook-handlers/wip-guard.sh"
  local tmp out i blocks

  if [ ! -x "$guard" ]; then
    echo "FAIL: wip-guard-loop-breaker — $guard missing or not executable"
    return
  fi

  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "SKIP: wip-guard-loop-breaker — mktemp unavailable"
    return
  }
  printf '| ID | Task | Status |\n|---|---|---|\n| T1 | x | cc:wip |\n' > "$tmp/Plans.md"

  # 1. Four turns with no host loop flag: at most the first may block.
  blocks=0
  for i in 1 2 3 4; do
    out="$(printf '{"session_id":"guard-loop"}' |
      CLAUDE_PROJECT_DIR="$tmp" bash "$guard" stop 2> /dev/null)"
    case "$out" in
      *'"decision":"block"'*) blocks=$((blocks + 1)) ;;
    esac
  done
  if [ "$blocks" -gt 1 ]; then
    rm -rf "$tmp"
    echo "FAIL: wip-guard-loop-breaker — blocked $blocks/4 turns without stop_hook_active; the guard can trap a session"
    return
  fi

  # 2. A recorded owner confines the block to that one session.
  mkdir -p "$tmp/.claude/state/wip-guard"
  printf '{"session_id":"owner-sess"}\n' > "$tmp/.claude/state/wip-guard/owner.json"
  rm -f "$tmp/.claude/state/wip-guard/"*.last-block
  out="$(printf '{"session_id":"visitor-sess"}' |
    CLAUDE_PROJECT_DIR="$tmp" bash "$guard" stop 2> /dev/null)"
  rm -rf "$tmp"
  case "$out" in
    *'"decision":"block"'*)
      echo "FAIL: wip-guard-loop-breaker — blocked a session that does not own the WIP"
      return
      ;;
  esac

  echo "PASS: wip-guard-loop-breaker"
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
run_check "plans-marker-anchoring" check_plans_marker_anchoring
run_check "plans-watcher-handler" check_plans_watcher_handler
run_check "progress-snapshot-rows" check_progress_snapshot_rows
run_check "wip-guard-loop-breaker" check_wip_guard_loop_breaker

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Summary: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  SKIP=$SKIP_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
