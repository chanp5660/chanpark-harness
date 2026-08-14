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
  if [ "$got" != "todo=6 wip=0 done=9 blocked=0 dropped=0 pm_requested=0 pm_approved=0 unknown=0" ]; then
    echo "FAIL: plans-marker-anchoring — $fixture counted as '$got'"
    return
  fi

  # Cross-dialect fixture: 10 table rows (2 todo, 2 wip, 2 done, 1 blocked, 2 dropped,
  # 1 unknown). Its checklist lines and prose sentence are not table rows and must not
  # be counted.
  got="$(awk -f "$counter" "$mixed" 2> /dev/null)"
  if [ "$got" != "todo=2 wip=2 done=2 blocked=1 dropped=2 pm_requested=0 pm_approved=0 unknown=1" ]; then
    echo "FAIL: plans-marker-anchoring — $mixed counted as '$got'"
    return
  fi

  # The guard is only meaningful while the fixture still contains the traps: the
  # original archive sentence, and its cc:dropped equivalent.
  if ! grep -q '(all cc:done)' "$fixture" 2> /dev/null; then
    echo "FAIL: plans-marker-anchoring — $fixture lost its prose marker; the guard proves nothing"
    return
  fi
  if ! grep -q 'retired as cc:dropped' "$fixture" 2> /dev/null; then
    echo "FAIL: plans-marker-anchoring — $fixture lost its cc:dropped prose trap"
    return
  fi

  echo "PASS: plans-marker-anchoring"
}

# ---------------------------------------------------------------------------
# Check: plans-status-cell-entity — no status cell may carry an HTML entity.
#
# The mirror image of the inflation bug, and the one that had zero coverage.
# Commit 598f4a11 neutralised markers QUOTED IN DESCRIPTION CELLS by rewriting
# `cc:` -> `cc&#58;` across the whole line, which also hit the STATUS cell on every
# row whose description happened to quote a marker. Four rows of the real Plans.md
# ended up reading `cc&#58;done`: renders as a normal `cc:done` in any viewer, and is
# completely invisible to the counter. A 20-row all-done ledger reported done=16.
#
# The repair belongs in the escaping step, never in the counter — teaching the counter
# to decode &#58; would also decode the marker legend, which is escaped on purpose.
# ---------------------------------------------------------------------------
check_plans_status_cell_entity() {
  local counter="scripts/lib/plans-markers.awk"
  local fixture="tests/fixtures/plans-status-cell-entity.md"
  local got bad

  if [ ! -f "$counter" ]; then
    echo "FAIL: plans-status-cell-entity — $counter missing"
    return
  fi
  if [ ! -f "$fixture" ]; then
    echo "SKIP: plans-status-cell-entity — fixture missing"
    return
  fi

  # 1. The fixture's escaped DESCRIPTION cells must not stop its clean status cells
  #    from counting. Every row is seen; nothing deflates.
  got="$(awk -f "$counter" "$fixture" 2> /dev/null)"
  if [ "$got" != "todo=1 wip=1 done=3 blocked=1 dropped=1 pm_requested=0 pm_approved=0 unknown=0" ]; then
    echo "FAIL: plans-status-cell-entity — $fixture counted as '$got'"
    return
  fi

  # 2. The fixture must keep the trap: description cells that quote an escaped marker.
  if ! grep -q 'cc&#58;' "$fixture" 2> /dev/null; then
    echo "FAIL: plans-status-cell-entity — $fixture lost its escaped markers; the guard proves nothing"
    return
  fi

  # 3. The invariant itself, on every tracked Plans file: a STATUS cell (last non-empty
  #    cell of a table row) may never contain an HTML entity. Description cells may.
  for f in Plans.md Plans-backlog.md tests/fixtures/plans-*.md; do
    [ -f "$f" ] || continue
    bad="$(awk -v file="$f" '
      { t=$0; sub(/^[[:space:]]+/,"",t)
        if (substr(t,1,3)=="```") { fence=!fence; next }
        if (fence || substr(t,1,4)=="<!--") next
        if ($0 !~ /^[[:space:]]*\|/) next
        n=split($0, c, "|"); s=""
        for (i=n; i>=1; i--) { v=c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
                               if (v!="") { s=v; break } }
        if (s ~ /&#[0-9]+;/ || s ~ /&[a-zA-Z]+;/) printf "%s:%d:%s\n", file, NR, s
      }' "$f" 2> /dev/null)"
    if [ -n "$bad" ]; then
      echo "FAIL: plans-status-cell-entity — HTML entity in a status cell: $(printf '%s' "$bad" | head -3 | tr '\n' ' ')"
      return
    fi
  done

  echo "PASS: plans-status-cell-entity"
}

# ---------------------------------------------------------------------------
# Check: plans-marker-vocabulary — the closed vocabulary is closed, and no state
# is absorbed by another.
#
# Measured failure this pins (docs/design/plans-redesign.md §1.4): with a bare prefix
# match, an invented state was counted as its parent —
#   cc:wip-paused    -> wip     (and it armed the Stop guard: session trapped)
#   cc:done-reverted -> done
# and a state with no shared prefix vanished from EVERY bucket AND from the
# denominator, so the total silently shrank. A corrupted denominator is worse than a
# wrong bucket, because nothing looks wrong.
#
# Also pins the two things the vocabulary decision rests on:
#   - cc:dropped is TERMINAL and stays in the denominator;
#   - cc:cancelled / cc:canceled are input aliases, so the UK/US spelling split
#     (the real drift risk in a hand-edited file with many parsers) cannot lose a row.
# ---------------------------------------------------------------------------
check_plans_marker_vocabulary() {
  local counter="scripts/lib/plans-markers.awk"
  local loader="scripts/lib/plans-counts.sh"
  local tmp got

  if [ ! -f "$counter" ] || [ ! -f "$loader" ]; then
    echo "FAIL: plans-marker-vocabulary — $counter or $loader missing"
    return
  fi
  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "SKIP: plans-marker-vocabulary — mktemp unavailable"
    return
  }

  # 1. Absorption: a longer word starting with a known marker is NOT that marker.
  printf '| ID | T | Status |\n|---|---|---|\n| 1.1 | a | cc:wip-paused |\n| 1.2 | b | cc:done-reverted |\n| 1.3 | c | cc:todo_later |\n' > "$tmp/absorb.md"
  got="$(awk -f "$counter" "$tmp/absorb.md" 2> /dev/null)"
  if [ "$got" != "todo=0 wip=0 done=0 blocked=0 dropped=0 pm_requested=0 pm_approved=0 unknown=3" ]; then
    rm -rf "$tmp"
    echo "FAIL: plans-marker-vocabulary — invented states absorbed by their parent bucket: '$got'"
    return
  fi

  # 2. Unknown markers stay in sight, and the denominator keeps all three rows.
  printf '| ID | T | Status |\n|---|---|---|\n| 1.1 | a | cc:done |\n| 1.2 | b | cc:frobnicated |\n| 1.3 | c | cc:todo |\n' > "$tmp/unknown.md"
  got="$(awk -f "$counter" "$tmp/unknown.md" 2> /dev/null)"
  if [ "$got" != "todo=1 wip=0 done=1 blocked=0 dropped=0 pm_requested=0 pm_approved=0 unknown=1" ]; then
    rm -rf "$tmp"
    echo "FAIL: plans-marker-vocabulary — unknown marker not reported: '$got'"
    return
  fi

  # 3. Trailing notes still parse — the boundary rule must not break real rows.
  printf '| ID | T | Status |\n|---|---|---|\n| 1.1 | a | cc:done [a1b2c3d] |\n| 1.2 | b | cc:done (2026-06-17: rewrote section 4) |\n| 1.3 | c | cc:dropped — superseded |\n' > "$tmp/notes.md"
  got="$(awk -f "$counter" "$tmp/notes.md" 2> /dev/null)"
  if [ "$got" != "todo=0 wip=0 done=2 blocked=0 dropped=1 pm_requested=0 pm_approved=0 unknown=0" ]; then
    rm -rf "$tmp"
    echo "FAIL: plans-marker-vocabulary — a trailing note broke marker recognition: '$got'"
    return
  fi

  # 4. Spelling aliases: cancelled/canceled both normalise to dropped.
  printf '| ID | T | Status |\n|---|---|---|\n| 1.1 | a | cc:dropped |\n| 1.2 | b | cc:cancelled |\n| 1.3 | c | cc:canceled |\n' > "$tmp/alias.md"
  got="$(awk -f "$counter" "$tmp/alias.md" 2> /dev/null)"
  if [ "$got" != "todo=0 wip=0 done=0 blocked=0 dropped=3 pm_requested=0 pm_approved=0 unknown=0" ]; then
    rm -rf "$tmp"
    echo "FAIL: plans-marker-vocabulary — cancelled/canceled do not normalise to dropped: '$got'"
    return
  fi

  # 5. terminal-complete semantics through the shared loader: dropped is terminal, it
  #    stays in the denominator, and blocked is in the denominator too.
  printf '| ID | T | Status |\n|---|---|---|\n| 1.1 | a | cc:done |\n| 1.2 | b | cc:dropped |\n| 1.3 | c | cc:blocked |\n| 1.4 | d | cc:todo |\n' > "$tmp/semantics.md"
  (
    # shellcheck source=../lib/plans-counts.sh
    . "$loader"
    plans_counts_load "$tmp/semantics.md" || exit 1
    [ "$PLANS_TERMINAL" = "2" ] || { echo "terminal=$PLANS_TERMINAL want 2"; exit 1; }
    [ "$PLANS_ACTIVE" = "2" ]   || { echo "active=$PLANS_ACTIVE want 2"; exit 1; }
    [ "$PLANS_TOTAL" = "4" ]    || { echo "total=$PLANS_TOTAL want 4"; exit 1; }
    [ "$PLANS_PCT" = "50" ]     || { echo "pct=$PLANS_PCT want 50"; exit 1; }
  ) > "$tmp/sem.out" 2>&1
  if [ -s "$tmp/sem.out" ]; then
    got="$(cat "$tmp/sem.out")"
    rm -rf "$tmp"
    echo "FAIL: plans-marker-vocabulary — terminal-complete semantics wrong: $got"
    return
  fi

  rm -rf "$tmp"
  echo "PASS: plans-marker-vocabulary"
}

# ---------------------------------------------------------------------------
# Check: plans-counts-loader — every consumer reads the ONE loader.
#
# The vocabulary used to be re-implemented in at least nine places, and they had
# already drifted apart from each other (pm:reviewed, pm:pending and pm:confirmed were
# all being grepped for by shipped skills; none of the three is a name this system has
# ever written). Pinning the loader keeps the next state a one-file change.
#
# Also pins the labelled output format. The counter used to print six bare integers
# that callers read POSITIONALLY, so adding a seventh column would have shifted every
# field — plans-watcher.sh would have written "0 0" into a JSON number and produced a
# malformed plans-state.json.
# ---------------------------------------------------------------------------
check_plans_counts_loader() {
  local counter="scripts/lib/plans-markers.awk"
  local loader="scripts/lib/plans-counts.sh"
  local f out

  if [ ! -f "$loader" ]; then
    echo "FAIL: plans-counts-loader — $loader missing"
    return
  fi

  # 1. Labelled ABI, not positional.
  out="$(printf '| ID | T | Status |\n|---|---|---|\n| 1.1 | a | cc:done |\n' > /tmp/plans-abi-$$.md &&
    awk -f "$counter" /tmp/plans-abi-$$.md 2> /dev/null; rm -f /tmp/plans-abi-$$.md)"
  case "$out" in
    todo=*\ wip=*\ done=*\ blocked=*\ dropped=*\ pm_requested=*\ pm_approved=*\ unknown=*) ;;
    *)
      echo "FAIL: plans-counts-loader — counter output is not the labelled ABI: '$out'"
      return
      ;;
  esac

  # 2. No consumer may re-derive counts by running the awk program itself. Comment
  #    lines are excluded: these files explain WHY they go through the loader, and
  #    naming the counter in that explanation is correct, not a violation.
  for f in hud/statusline.sh scripts/hook-handlers/plans-watcher.sh scripts/hook-handlers/session-monitor.sh; do
    [ -f "$f" ] || continue
    if ! grep -q 'plans-counts.sh' "$f" 2> /dev/null; then
      echo "FAIL: plans-counts-loader — $f does not use scripts/lib/plans-counts.sh"
      return
    fi
    if grep -vE '^[[:space:]]*#' "$f" | grep -q 'plans-markers.awk' 2> /dev/null; then
      echo "FAIL: plans-counts-loader — $f still parses plans-markers.awk directly; go through the loader"
      return
    fi
  done

  # 3. The HUD's grep fallback implemented the pre-v1.3.6 unanchored rule with zero CI
  #    coverage: a statusline copied out of the plugin tree reported inflated counts
  #    with total confidence. Showing nothing is strictly better.
  if grep -q '_cell()' hud/statusline.sh 2> /dev/null; then
    echo "FAIL: plans-counts-loader — hud/statusline.sh resurrected the unanchored grep fallback"
    return
  fi

  echo "PASS: plans-counts-loader"
}

# ---------------------------------------------------------------------------
# Check: wip-guard-anchoring — only a real cc:wip arms the Stop guard.
#
# Measured (docs/design/plans-redesign.md §1.4): one row reading `cc:wip-paused` — a
# state explicitly meaning NOT in progress — made wip-guard emit decision:block, and
# the guard is what stands between a session and ending. An unanchored substring match
# in a Stop hook fails CLOSED and traps the user, which is the worst failure direction
# available to this code.
#
# Both dialects are pinned, because they had separate bugs: the table dialect used a
# substring match, and the checklist dialect's /cc:[A-Za-z]+/ truncated at the hyphen,
# turning "cc:wip-paused" back into "cc:wip".
# ---------------------------------------------------------------------------
check_wip_guard_anchoring() {
  local guard="scripts/hook-handlers/wip-guard.sh"
  local tmp out

  if [ ! -x "$guard" ]; then
    echo "FAIL: wip-guard-anchoring — $guard missing or not executable"
    return
  fi
  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "SKIP: wip-guard-anchoring — mktemp unavailable"
    return
  }

  _guard_out() {  # $1 = Plans.md body
    printf '%s' "$1" > "$tmp/Plans.md"
    rm -rf "$tmp/.claude"
    printf '{"session_id":"anchor-test"}' |
      CLAUDE_PROJECT_DIR="$tmp" bash "$guard" stop 2> /dev/null
  }

  # 1. Table dialect: cc:wip-paused is not cc:wip and must NOT block.
  out="$(_guard_out '| ID | Task | Status |
|---|---|---|
| T1 | paused work | cc:wip-paused |
')"
  case "$out" in
    *'"decision":"block"'*)
      rm -rf "$tmp"
      echo "FAIL: wip-guard-anchoring — cc:wip-paused blocked Stop; a non-WIP row can trap the session"
      return
      ;;
  esac

  # 2. Checklist dialect: same row shape, the hyphen-truncation bug.
  out="$(_guard_out '- [ ] Paused work `cc:wip-paused`
')"
  case "$out" in
    *'"decision":"block"'*)
      rm -rf "$tmp"
      echo "FAIL: wip-guard-anchoring — checklist cc:wip-paused blocked Stop (hyphen truncation)"
      return
      ;;
  esac

  # 3. Terminal states never arm the guard — dropping a task must release Stop exactly
  #    like finishing it, or "decide not to do this" is not a usable exit.
  out="$(_guard_out '| ID | Task | Status |
|---|---|---|
| T1 | retired | cc:dropped |
| T2 | shipped | cc:done |
')"
  case "$out" in
    *'"decision":"block"'*)
      rm -rf "$tmp"
      echo "FAIL: wip-guard-anchoring — a terminal row (cc:dropped / cc:done) blocked Stop"
      return
      ;;
  esac

  # 4. The guard must still do its job: a real cc:wip blocks.
  out="$(_guard_out '| ID | Task | Status |
|---|---|---|
| T1 | real work | cc:wip |
')"
  case "$out" in
    *'"decision":"block"'*) ;;
    *)
      rm -rf "$tmp"
      echo "FAIL: wip-guard-anchoring — a real cc:wip row did NOT block; the guard is inert"
      return
      ;;
  esac

  rm -rf "$tmp"
  echo "PASS: wip-guard-anchoring"
}

# ---------------------------------------------------------------------------
# Check: plans-backlog-inert — Plans-backlog.md contributes to no count, anywhere.
#
# The backlog is separated by a FILE BOUNDARY rather than a section heading, because a
# heading is not a filter: every parser scans the whole file, and a "## Backlog"
# section would land straight in the counts, the denominator and the HUD. That is
# literally the v1.3.6 bug one level up.
#
# The second layer is that backlog entries carry no cc: markers at all, so even a
# counter pointed at the file by mistake returns zero. Convention would not survive;
# absence of markers is physics.
# ---------------------------------------------------------------------------
check_plans_backlog_inert() {
  local counter="scripts/lib/plans-markers.awk"
  local backlog="Plans-backlog.md"
  local got hits

  if [ ! -f "$backlog" ]; then
    echo "SKIP: plans-backlog-inert — no Plans-backlog.md in this checkout"
    return
  fi
  if [ ! -f "$counter" ]; then
    echo "FAIL: plans-backlog-inert — $counter missing"
    return
  fi

  # 1. Point the canonical counter straight at it: everything must be zero.
  got="$(awk -f "$counter" "$backlog" 2> /dev/null)"
  if [ "$got" != "todo=0 wip=0 done=0 blocked=0 dropped=0 pm_requested=0 pm_approved=0 unknown=0" ]; then
    echo "FAIL: plans-backlog-inert — $backlog produced counts: '$got'"
    return
  fi

  # 2. No marker may appear in a table row of the backlog at all. Prose that names the
  #    markers while explaining the rule is fine and expected.
  hits="$(awk '
    { t=$0; sub(/^[[:space:]]+/,"",t)
      if (substr(t,1,3)=="```") { f=!f; next }
      if (f) next
      if ($0 ~ /^[[:space:]]*\|/ && tolower($0) ~ /cc:(todo|wip|done|blocked|dropped)/) print NR": "$0 }
  ' "$backlog" 2> /dev/null)"
  if [ -n "$hits" ]; then
    echo "FAIL: plans-backlog-inert — marker in a backlog table row: $(printf '%s' "$hits" | head -2 | tr '\n' ' ')"
    return
  fi

  # 3. No counter may have learned to read the backlog or the archive.
  for f in hud/statusline.sh scripts/hook-handlers/wip-guard.sh scripts/progress-snapshot.sh \
    scripts/lib/plans-counts.sh scripts/lib/plans-markers.awk; do
    [ -f "$f" ] || continue
    if grep -nE '^[^#]*(Plans-backlog\.md|memory/archive)' "$f" 2> /dev/null |
      grep -vq '^$'; then
      echo "FAIL: plans-backlog-inert — $f references the backlog or archive outside a comment"
      return
    fi
  done

  # 4. plans-watcher.sh is checked BEHAVIOURALLY rather than textually. Its budget
  #    advisory legitimately names both destinations in the remedy it prints ("capture
  #    new work in Plans-backlog.md", "move terminal rows to .claude/memory/archive/"),
  #    and a grep cannot tell a printed sentence from an opened file. The invariant that
  #    actually matters is stronger and directly testable: whatever the backlog contains,
  #    including a full table of markers pasted in by mistake, it must not move a single
  #    number the handler writes.
  local tmp state done_n
  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "PASS: plans-backlog-inert (behavioural sub-check skipped: mktemp unavailable)"
    return
  }
  printf '| ID | Task | Status |\n|---|---|---|\n| T1 | only real task | cc:todo |\n' > "$tmp/Plans.md"
  {
    printf '| ID | Task | Status |\n|---|---|---|\n'
    printf '| B1 | pasted into the wrong file | cc:done |\n'
    printf '| B2 | pasted into the wrong file | cc:done |\n'
    printf '| B3 | pasted into the wrong file | pm:approved |\n'
  } > "$tmp/Plans-backlog.md"
  printf '{"cwd":"%s","tool_input":{"file_path":"%s/Plans.md"},"session_id":"inert"}' "$tmp" "$tmp" |
    bash scripts/hook-handlers/plans-watcher.sh > /dev/null 2>&1
  state="$tmp/.claude/state/plans-state.json"
  if [ -f "$state" ]; then
    done_n="$(grep -o '"cc_done"[[:space:]]*:[[:space:]]*[0-9]\+' "$state" | grep -o '[0-9]\+$')"
    if [ "${done_n:-0}" != "0" ]; then
      rm -rf "$tmp"
      echo "FAIL: plans-backlog-inert — plans-watcher counted ${done_n} done row(s) that exist only in Plans-backlog.md"
      return
    fi
  fi
  rm -rf "$tmp"

  echo "PASS: plans-backlog-inert"
}

# ---------------------------------------------------------------------------
# Check: session-monitor-handler — the SessionStart monitor dispatches to the
# anchored script, not to the vendored binary subcommand.
#
# Mirrors check_plans_watcher_handler, for the same reason and with the same failure
# mode: `harness sync` can put the binary subcommand back, and the binary counts
# markers as unanchored substrings. Measured on this repository, `harness hook
# session-init` reports "blocked 1" for a file the canonical counter scores blocked=0 —
# it invents a blocked task that does not exist. Its marker legend is also compiled in
# as a fixed six-row table, and there is no Go source here to teach it cc:dropped.
# ---------------------------------------------------------------------------
check_session_monitor_handler() {
  local handler="scripts/hook-handlers/session-monitor.sh"
  local monitors="monitors/monitors.json"

  if [ ! -f "$handler" ]; then
    echo "FAIL: session-monitor-handler — $handler missing"
    return
  fi
  if [ ! -f "$monitors" ]; then
    echo "FAIL: session-monitor-handler — $monitors missing"
    return
  fi
  # Inspect the COMMAND field only. The description deliberately names the binary
  # subcommand to explain what was replaced and why; that prose must not trip the guard.
  local cmds
  if command -v jq > /dev/null 2>&1; then
    cmds="$(jq -r '.[].command // empty' "$monitors" 2> /dev/null)"
  else
    cmds="$(grep -o '"command"[[:space:]]*:[[:space:]]*"[^"]*"' "$monitors" 2> /dev/null)"
  fi
  if [ -z "$cmds" ]; then
    echo "FAIL: session-monitor-handler — could not read the command field from $monitors"
    return
  fi
  if printf '%s' "$cmds" | grep -q 'hook session-monitor'; then
    echo "FAIL: session-monitor-handler — $monitors still dispatches to the binary subcommand"
    return
  fi
  if ! printf '%s' "$cmds" | grep -q 'hook-handlers/session-monitor.sh'; then
    echo "FAIL: session-monitor-handler — $monitors does not exec $handler"
    return
  fi

  echo "PASS: session-monitor-handler"
}

# ---------------------------------------------------------------------------
# Check: plans-sweep-readonly — the staleness sweep proposes and never writes.
#
# Linear can auto-cancel stale issues safely because it has an activity feed, an undo
# and a UI that surfaces the change. A markdown file has none of the three, so a silent
# rewrite to cc:dropped is invisible until someone reads a diff — and the first time a
# tool retires work behind your back is the last time you leave it enabled.
# ---------------------------------------------------------------------------
check_plans_sweep_readonly() {
  local sweep="scripts/plans-sweep.sh"
  local tmp before after

  if [ ! -f "$sweep" ]; then
    echo "SKIP: plans-sweep-readonly — $sweep not present"
    return
  fi
  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "SKIP: plans-sweep-readonly — mktemp unavailable"
    return
  }

  printf '| ID | Task | Status |\n|---|---|---|\n| T1 | ancient | cc:todo |\n| T2 | shipped | cc:done |\n' > "$tmp/Plans.md"
  printf '## Captured\n\n- 2001-01-01 — an ancient captured idea\n' > "$tmp/Plans-backlog.md"
  before="$(cat "$tmp/Plans.md" "$tmp/Plans-backlog.md")"
  HARNESS_SWEEP_QUIET=0 bash "$sweep" --root "$tmp" --stale-days 0 --archive-days 0 \
    --backlog-stale-days 0 --enable-stale > /dev/null 2>&1
  after="$(cat "$tmp/Plans.md" "$tmp/Plans-backlog.md")"
  rm -rf "$tmp"

  if [ "$before" != "$after" ]; then
    echo "FAIL: plans-sweep-readonly — the sweep modified a plan file; it must only ever propose"
    return
  fi
  echo "PASS: plans-sweep-readonly"
}

# ---------------------------------------------------------------------------
# Check: plans-archive-per-row — the T2 archive trigger is a property of the ROW,
# never of the whole file.
#
# The rule it replaced required every row in the file to be terminal. That let ONE
# perpetually-unfinished cc:todo suppress archiving of an arbitrarily large pile of
# finished rows, forever, and nothing else in the design could catch it: the row caps
# count active rows only (there is exactly one), and T1 targets active rows and ships
# off. Reproduced before the fix at 120 cc:done rows plus one cc:todo — 125 lines, and
# the sweep printed "no candidates".
#
# Linear, which this design cites for "archive must be a pure function of state and
# time", applies that per ISSUE: closed issues auto-archive after remaining closed and
# inactive for the period. The row is the thing being archived, so the row is the thing
# the condition is on.
#
# The fixture is many terminal rows plus one active row. If the rule is reverted to the
# file-level form, PLANS_ACTIVE is 1 and the sweep emits nothing — this check FAILs.
# ---------------------------------------------------------------------------
check_plans_archive_per_row() {
  local sweep="scripts/plans-sweep.sh"
  local fixture="tests/fixtures/plans-terminal-pile.md"
  local tmp out

  if [ ! -f "$sweep" ] || [ ! -f "$fixture" ]; then
    echo "FAIL: plans-archive-per-row — $sweep or $fixture missing"
    return
  fi
  if ! command -v git > /dev/null 2>&1; then
    echo "SKIP: plans-archive-per-row — git unavailable, per-row ages come from git blame"
    return
  fi
  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "SKIP: plans-archive-per-row — mktemp unavailable"
    return
  }

  cp "$fixture" "$tmp/Plans.md"
  (
    cd "$tmp" || exit 1
    git init -q . > /dev/null 2>&1
    git config user.email guard@example.invalid
    git config user.name guard
    git add Plans.md > /dev/null 2>&1
    git commit -qm fixture > /dev/null 2>&1
  )
  # --archive-days 0: every row is "at least 0 days old", so the age test cannot be the
  # thing under test here. The only question is whether the presence of the active row
  # suppresses the report.
  out="$(HARNESS_SWEEP_QUIET=0 bash "$sweep" --root "$tmp" --archive-days 0 2>&1)"
  rm -rf "$tmp"

  case "$out" in
    *"no candidates"*)
      echo "FAIL: plans-archive-per-row — one active row suppressed the whole archive report; T2 must be per-row"
      return
      ;;
  esac
  if ! printf '%s' "$out" | grep -q 'T2 archive candidates'; then
    echo "FAIL: plans-archive-per-row — no per-row T2 candidates reported: $(printf '%s' "$out" | head -1)"
    return
  fi
  # Every terminal row must be named, and the active row must not be.
  local missing
  missing=""
  for id in D1 D8 X1 X4; do
    printf '%s' "$out" | grep -qE "^[[:space:]]+$id[[:space:]]" || missing="$missing $id"
  done
  if [ -n "$missing" ]; then
    echo "FAIL: plans-archive-per-row — terminal row(s) not offered for archive:$missing"
    return
  fi
  if printf '%s' "$out" | grep -qE '^[[:space:]]+A1[[:space:]]'; then
    echo "FAIL: plans-archive-per-row — the active row A1 was offered for archive"
    return
  fi

  echo "PASS: plans-archive-per-row"
}

# ---------------------------------------------------------------------------
# Check: plans-line-budget — the active file is held to a line budget, and the budget
# is reachable at the hard row cap.
#
# A row cap does not bound the file. It counts ACTIVE rows only, so terminal rows
# awaiting archive add length without moving the number, and the boilerplate is free.
# Measured on the previous layout: at the hard cap of 30 rows Plans.md came to 93 lines,
# already past one screen, and no surface anywhere said a word.
#
# Three assertions, each pinning a different half of the fix:
#   1. max_lines exists in harness.toml [plans] and is <= 80.
#   2. the repo's own Plans.md is within it (the worked example the design is pinned to).
#   3. the shipped template's boilerplate + hard_cap rows still fits, i.e. the budget is
#      actually reachable rather than being a number that a full plan cannot satisfy.
#      This is what forced the legend out to references/plans-format.md.
# ---------------------------------------------------------------------------
check_plans_line_budget() {
  local toml="harness.toml"
  local plans="Plans.md"
  local tmpl="templates/Plans.md.template"
  local max_lines hard_cap n boiler

  if [ ! -f "$toml" ]; then
    echo "FAIL: plans-line-budget — $toml missing"
    return
  fi
  max_lines="$(grep -E '^[[:space:]]*max_lines[[:space:]]*=' "$toml" 2> /dev/null |
    head -1 | grep -oE '[0-9]+' | head -1)"
  hard_cap="$(grep -E '^[[:space:]]*hard_cap[[:space:]]*=' "$toml" 2> /dev/null |
    head -1 | grep -oE '[0-9]+' | head -1)"
  if [ -z "$max_lines" ]; then
    echo "FAIL: plans-line-budget — no max_lines in $toml [plans]; the active file has no length budget"
    return
  fi
  if [ "$max_lines" -gt 80 ]; then
    echo "FAIL: plans-line-budget — max_lines is $max_lines; the budget must be <= 80 (one screen)"
    return
  fi
  hard_cap="${hard_cap:-30}"

  if [ -f "$plans" ]; then
    n="$(wc -l < "$plans" | tr -d ' ')"
    if [ "$n" -gt "$max_lines" ]; then
      echo "FAIL: plans-line-budget — $plans is $n lines, over the $max_lines-line budget"
      return
    fi
  fi

  # Reachability: template boilerplate (its body minus the one demo row and minus the
  # 4-line template frontmatter, which is stripped at scaffold time) plus a full hard-cap
  # plan must still fit. If it does not, the budget is decorative.
  if [ -f "$tmpl" ]; then
    n="$(wc -l < "$tmpl" | tr -d ' ')"
    boiler=$((n - 4 - 1))
    if [ $((boiler + hard_cap)) -gt "$max_lines" ]; then
      echo "FAIL: plans-line-budget — template boilerplate $boiler + hard cap $hard_cap = $((boiler + hard_cap)) > $max_lines; the budget is unreachable at a full plan"
      return
    fi
  fi

  # The budget has to be REPORTED somewhere, or it is prose.
  local reported=0
  grep -q 'max_lines' scripts/hook-handlers/session-monitor.sh 2> /dev/null && reported=$((reported + 1))
  grep -q 'max_lines' scripts/hook-handlers/plans-watcher.sh 2> /dev/null && reported=$((reported + 1))
  if [ "$reported" -lt 2 ]; then
    echo "FAIL: plans-line-budget — the budget is not reported by both session-monitor.sh and plans-watcher.sh"
    return
  fi

  echo "PASS: plans-line-budget"
}

# ---------------------------------------------------------------------------
# Check: plans-dupe-check — duplicate detection is an executable with a named call site.
#
# It was one prose sentence telling the model to compute Jaccard similarity, with no
# script, no command and no call site — and it compared against Plans.md rows while
# harness-plan's own backlog-by-default rule sends new items to Plans-backlog.md, so the
# one file where duplicates actually accumulate was the one file never compared.
#
# Asserted: the script exists and runs; it finds a near-duplicate of a Plans.md row AND
# of a live backlog bullet; it stays quiet on an unrelated description; it ignores
# declined bullets; and harness-plan names it as a command.
# ---------------------------------------------------------------------------
check_plans_dupe_check() {
  local script="scripts/plans-dupe-check.sh"
  local skill="skills/harness-plan/SKILL.md"
  local tmp out

  if [ ! -f "$script" ]; then
    echo "FAIL: plans-dupe-check — $script missing; the dedupe claim has no executable form"
    return
  fi
  if [ ! -x "$script" ]; then
    echo "FAIL: plans-dupe-check — $script is not executable"
    return
  fi
  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "SKIP: plans-dupe-check — mktemp unavailable"
    return
  }

  {
    printf '| ID | Task | DoD | Depends | Status |\n|----|------|-----|---------|--------|\n'
    printf '| 1.1 | Make the archive sweep work per row instead of per file [tdd:skip:x] | fires | - | cc:todo |\n'
  } > "$tmp/Plans.md"
  {
    printf '# Plans-backlog.md\n\n## Captured\n\n'
    printf -- '- 2026-08-01 — Add a line budget to the active plans file so it fits one screen\n'
    printf -- '- ~~2026-01-01 — Upgrade the continuous integration runner image to a newer ubuntu~~ declined 2026-02-02: done upstream\n'
  } > "$tmp/Plans-backlog.md"

  # 1. near-duplicate of a Plans.md row
  out="$(bash "$script" --root "$tmp" "Rewrite the archive sweep to work per row instead of per file" 2>&1)"
  if ! printf '%s' "$out" | grep -q 'Plans.md:'; then
    rm -rf "$tmp"
    echo "FAIL: plans-dupe-check — missed a near-duplicate of a Plans.md row"
    return
  fi
  # 2. near-duplicate of a LIVE backlog bullet — the corpus the old prose never read
  out="$(bash "$script" --root "$tmp" "Add a line budget to the active plans file so that it fits one screen" 2>&1)"
  if ! printf '%s' "$out" | grep -q 'Plans-backlog.md:'; then
    rm -rf "$tmp"
    echo "FAIL: plans-dupe-check — did not compare against Plans-backlog.md, where new items land by default"
    return
  fi
  # 3. a DECLINED bullet is retired and must not keep flagging its successor
  out="$(bash "$script" --root "$tmp" "Upgrade the continuous integration runner image to a newer ubuntu" 2>&1)"
  if printf '%s' "$out" | grep -q 'Plans-backlog.md:'; then
    rm -rf "$tmp"
    echo "FAIL: plans-dupe-check — matched a declined (struck-through) backlog bullet"
    return
  fi
  # 4. unrelated description stays quiet
  out="$(bash "$script" --root "$tmp" "Rotate the signing key used for release tarballs" 2>&1)"
  if ! printf '%s' "$out" | grep -q 'no candidates'; then
    rm -rf "$tmp"
    echo "FAIL: plans-dupe-check — false positive on an unrelated description: $(printf '%s' "$out" | head -1)"
    return
  fi
  rm -rf "$tmp"

  # 5. the skill must call it by name, or it is a script nobody runs
  if [ -f "$skill" ] && ! grep -q 'plans-dupe-check.sh' "$skill"; then
    echo "FAIL: plans-dupe-check — $skill does not name the script; the check has no call site"
    return
  fi

  echo "PASS: plans-dupe-check"
}

# ---------------------------------------------------------------------------
# Check: plans-backlog-lifecycle — the backlog has an exit other than promotion.
#
# Plans-backlog.md is the DEFAULT destination for every new item, and it was declared
# uncapped, never swept, never expired and never cleaned, with promotion as its only
# exit. That is an unbounded file by construction, and it means an idea can only be
# retired by deleting it, leaving no record. Markers are banned in the file, so
# cc:dropped can never reach it — the disposition has to be carried by the text.
#
# Asserted: the sweep reports a stale LIVE bullet by its capture date, skips a DECLINED
# (struck-through) one, and the shipped file plus template document all four
# dispositions.
# ---------------------------------------------------------------------------
check_plans_backlog_lifecycle() {
  local sweep="scripts/plans-sweep.sh"
  local fixture="tests/fixtures/plans-backlog-lifecycle.md"
  local toml="harness.toml"
  local tmp out f

  if [ ! -f "$sweep" ] || [ ! -f "$fixture" ]; then
    echo "FAIL: plans-backlog-lifecycle — $sweep or $fixture missing"
    return
  fi

  # The trigger must be configured ON in the shipped config, not merely implemented.
  # A sweep that defaults to true in the script but false in harness.toml reports
  # nothing in the only project that matters here.
  if [ -f "$toml" ]; then
    if ! grep -qE '^[[:space:]]*backlog_stale_days[[:space:]]*=[[:space:]]*[0-9]+' "$toml"; then
      echo "FAIL: plans-backlog-lifecycle — no backlog_stale_days in $toml [plans]"
      return
    fi
    if ! grep -qE '^[[:space:]]*backlog_sweep_enabled[[:space:]]*=[[:space:]]*true' "$toml"; then
      echo "FAIL: plans-backlog-lifecycle — backlog_sweep_enabled is not true in $toml; the backlog has no age report"
      return
    fi
  fi
  tmp="$(mktemp -d 2> /dev/null)" || {
    echo "SKIP: plans-backlog-lifecycle — mktemp unavailable"
    return
  }
  cp "$fixture" "$tmp/Plans-backlog.md"
  out="$(HARNESS_SWEEP_QUIET=0 bash "$sweep" --root "$tmp" 2>&1)"
  rm -rf "$tmp"

  if ! printf '%s' "$out" | grep -q 'T3 backlog staleness'; then
    echo "FAIL: plans-backlog-lifecycle — no staleness report for the backlog; its only exit is promotion again"
    return
  fi
  if ! printf '%s' "$out" | grep -q '2012-06-15'; then
    echo "FAIL: plans-backlog-lifecycle — the ancient live bullet was not reported"
    return
  fi
  if printf '%s' "$out" | grep -q '2010-02-02'; then
    echo "FAIL: plans-backlog-lifecycle — a declined bullet was reported as stale; declining must retire it"
    return
  fi
  if printf '%s' "$out" | grep -q '2099-01-01'; then
    echo "FAIL: plans-backlog-lifecycle — a future-dated bullet was reported as stale"
    return
  fi

  # The disposition has to be documented where the person writing the bullet will see it.
  for f in Plans-backlog.md templates/Plans-backlog.md.template; do
    [ -f "$f" ] || continue
    if ! grep -qi 'declined' "$f"; then
      echo "FAIL: plans-backlog-lifecycle — $f does not document the declined disposition"
      return
    fi
    if ! grep -qi 'snooze' "$f"; then
      echo "FAIL: plans-backlog-lifecycle — $f does not document all four dispositions"
      return
    fi
  done

  echo "PASS: plans-backlog-lifecycle"
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
print("%d %d %d %d %d %d %d" % (
    d["_todo_count"], d["_wip_count"], d["_done_count"], d["_blocked_count"],
    d["_dropped_count"], d["_total_count"], d["progress_pct"]))' 2> /dev/null)"

  # 6 todo + 9 done = 15 rows, 60% terminal. The snapshot must agree with the canonical
  # counter on the same file, including the denominator.
  if [ "$got" != "6 0 9 0 0 15 60" ]; then
    echo "FAIL: progress-snapshot-rows — counted '$got', expected '6 0 9 0 0 15 60'"
    return
  fi

  # terminal-complete semantics: dropped is in BOTH the numerator and the denominator.
  # done/total instead of terminal/total would report 50% here, which would teach the
  # operator that retiring a task costs progress — and the correct response to that
  # lesson is to never retire anything.
  local tmp
  tmp="$(mktemp -d 2> /dev/null)" || { echo "PASS: progress-snapshot-rows"; return; }
  printf '| ID | T | Status |\n|---|---|---|\n| 1.1 | a | cc:done |\n| 1.2 | b | cc:dropped |\n| 1.3 | c | cc:blocked |\n| 1.4 | d | cc:todo |\n' > "$tmp/p.md"
  got="$(bash "$script" --plans "$tmp/p.md" --project guard 2> /dev/null | python3 -c 'import json,sys
d = json.load(sys.stdin)
print("%d %d %d %d" % (d["_dropped_count"], d["_terminal_count"], d["_total_count"], d["progress_pct"]))' 2> /dev/null)"
  rm -rf "$tmp"
  if [ "$got" != "1 2 4 50" ]; then
    echo "FAIL: progress-snapshot-rows — terminal-complete semantics wrong: got '$got', expected '1 2 4 50'"
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
run_check "plans-status-cell-entity" check_plans_status_cell_entity
run_check "plans-marker-vocabulary" check_plans_marker_vocabulary
run_check "plans-counts-loader" check_plans_counts_loader
run_check "plans-backlog-inert" check_plans_backlog_inert
run_check "plans-watcher-handler" check_plans_watcher_handler
run_check "session-monitor-handler" check_session_monitor_handler
run_check "plans-sweep-readonly" check_plans_sweep_readonly
run_check "plans-archive-per-row" check_plans_archive_per_row
run_check "plans-line-budget" check_plans_line_budget
run_check "plans-dupe-check" check_plans_dupe_check
run_check "plans-backlog-lifecycle" check_plans_backlog_lifecycle
run_check "progress-snapshot-rows" check_progress_snapshot_rows
run_check "wip-guard-loop-breaker" check_wip_guard_loop_breaker
run_check "wip-guard-anchoring" check_wip_guard_anchoring

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Summary: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  SKIP=$SKIP_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0
