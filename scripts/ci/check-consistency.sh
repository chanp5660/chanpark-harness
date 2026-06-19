#!/bin/bash
# check-consistency.sh
# Plugin consistency check
#
# Usage: ./scripts/ci/check-consistency.sh
# Exit codes:
#   0 - All checks passed
#   1 - Inconsistencies found

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ERRORS=0

echo "🔍 claude-code-harness consistency check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ================================
# 1. Check template files exist
# ================================
echo ""
echo "📁 [1/14] Checking template files exist..."

REQUIRED_TEMPLATES=(
  "templates/AGENTS.md.template"
  "templates/CLAUDE.md.template"
  "templates/Plans.md.template"
  "templates/locales/ja/AGENTS.md.template"
  "templates/locales/ja/CLAUDE.md.template"
  "templates/locales/ja/Plans.md.template"
  "templates/locales/ja/.claude-code-harness.config.yaml.template"
  "templates/.claude-code-harness-version.template"
  "templates/.claude-code-harness.config.yaml.template"
  "templates/cursor/commands/start-session.md"
  "templates/cursor/commands/project-overview.md"
  "templates/cursor/commands/plan-with-cc.md"
  "templates/cursor/commands/handoff-to-claude.md"
  "templates/cursor/commands/review-cc-work.md"
  "templates/claude/settings.security.json.template"
  "templates/claude/settings.local.json.template"
  "templates/rules/workflow.md.template"
  "templates/rules/coding-standards.md.template"
  "templates/rules/plans-management.md.template"
  "templates/rules/testing.md.template"
  "templates/rules/ui-debugging-agent-browser.md.template"
)

for template in "${REQUIRED_TEMPLATES[@]}"; do
  if [ ! -f "$PLUGIN_ROOT/$template" ]; then
    echo "  ❌ Missing: $template"
    ERRORS=$((ERRORS + 1))
  else
    echo "  ✅ $template"
  fi
done

# ================================
# 2. Command <-> skill consistency
# ================================
echo ""
echo "🔗 [2/14] Command <-> skill reference consistency..."

# Whether the templates referenced by commands exist
check_command_references() {
  local cmd_file="$1"
  local cmd_name=$(basename "$cmd_file" .md)

  # Extract template references
  local refs=$(grep -oE 'templates/[a-zA-Z0-9/_.-]+' "$cmd_file" 2>/dev/null || true)

  for ref in $refs; do
    if [ ! -e "$PLUGIN_ROOT/$ref" ] && [ ! -e "$PLUGIN_ROOT/${ref}.template" ]; then
      echo "  ❌ $cmd_name: reference target does not exist: $ref"
      ERRORS=$((ERRORS + 1))
    fi
  done
}

for cmd in "$PLUGIN_ROOT/commands"/*.md; do
  check_command_references "$cmd"
done
echo "  ✅ Command reference check complete"

# ================================
# 3. Version number consistency
# ================================
echo ""
echo "🏷️ [3/14] Version number consistency..."

VERSION_FILE="$PLUGIN_ROOT/VERSION"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

if [ -f "$VERSION_FILE" ] && [ -f "$PLUGIN_JSON" ]; then
  FILE_VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')
  JSON_VERSION=$(grep '"version"' "$PLUGIN_JSON" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

  if [ "$FILE_VERSION" != "$JSON_VERSION" ]; then
    echo "  ❌ Version mismatch: VERSION=$FILE_VERSION, plugin.json=$JSON_VERSION"
    ERRORS=$((ERRORS + 1))
  else
    echo "  ✅ VERSION and plugin.json match: $FILE_VERSION"
  fi
fi

LATEST_RELEASE_URL="https://github.com/Chachamaru127/claude-code-harness/releases/latest"
LATEST_RELEASE_BADGE="https://img.shields.io/github/v/release/Chachamaru127/claude-code-harness?display_name=tag&sort=semver"

# ================================
# 4. Expected file layout of skill definitions
# ================================
echo ""
echo "📋 [4/14] Expected file layout of skill definitions..."

# 2agent settings are merged into harness-setup
# Check that skills/harness-setup/SKILL.md exists
SETUP_SKILL="$PLUGIN_ROOT/skills/harness-setup/SKILL.md"
if [ -f "$SETUP_SKILL" ]; then
  echo "  ✅ skills/harness-setup/SKILL.md exists (includes 2agent settings)"
else
  echo "  ❌ skills/harness-setup/SKILL.md not found"
  ERRORS=$((ERRORS + 1))
fi

# ================================
# 5. Hooks configuration consistency
# ================================
echo ""
echo "🪝 [5/14] Hooks configuration consistency..."

HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ]; then
  # Check script references inside hooks.json
  SCRIPT_REFS=$(grep -oE '\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[a-zA-Z0-9_./-]+' "$HOOKS_JSON" 2>/dev/null || true)

  for ref in $SCRIPT_REFS; do
    script_name=$(echo "$ref" | sed 's|\${CLAUDE_PLUGIN_ROOT}/scripts/||')
    if [ ! -f "$PLUGIN_ROOT/scripts/$script_name" ]; then
      echo "  ❌ hooks.json: script does not exist: scripts/$script_name"
      ERRORS=$((ERRORS + 1))
    else
      echo "  ✅ scripts/$script_name"
    fi
  done
fi

# ================================
# 6. Regression check for /start-task removal
# ================================
echo ""
echo "🚫 [6/14] Regression check for /start-task removal..."

# Operational-path files (exclude history such as CHANGELOG)
START_TASK_TARGETS=(
  "commands/"
  "skills/"
  "workflows/"
  "profiles/"
  "templates/"
  "scripts/"
  "DEVELOPMENT_FLOW_GUIDE.md"
  "IMPLEMENTATION_GUIDE.md"
  "README.md"
)

START_TASK_FOUND=0
for target in "${START_TASK_TARGETS[@]}"; do
  if [ -e "$PLUGIN_ROOT/$target" ]; then
    # Search for /start-task references (exclude history/explanatory context)
    # Exclusion patterns (Japanese kept for matching): 削除/廃止/Removed (history),
    # 相当/統合/従来/吸収 (migration notes), 改善/使い分け (CHANGELOG)
    REFS=$(grep -rn "/start-task" "$PLUGIN_ROOT/$target" 2>/dev/null \
      | grep -v "削除" | grep -v "廃止" | grep -v "Removed" \
      | grep -v "相当" | grep -v "統合" | grep -v "従来" | grep -v "吸収" \
      | grep -v "改善" | grep -v "使い分け" | grep -v "CHANGELOG" \
      | grep -v "check-consistency.sh" \
      || true)
    if [ -n "$REFS" ]; then
      echo "  ❌ /start-task references remain: $target"
      sed -n '1,3p' <<<"$REFS" | sed 's/^/      /'
      START_TASK_FOUND=$((START_TASK_FOUND + 1))
    fi
  fi
done

if [ $START_TASK_FOUND -eq 0 ]; then
  echo "  ✅ No /start-task references (operational paths)"
else
  ERRORS=$((ERRORS + START_TASK_FOUND))
fi

# ================================
# 7. Regression check for docs/ normalization
# ================================
echo ""
echo "📁 [7/14] Regression check for docs/ normalization..."

# Check for root references to proposal.md / priority_matrix.md
DOCS_TARGETS=(
  "commands/"
  "skills/"
)

DOCS_ISSUES=0
for target in "${DOCS_TARGETS[@]}"; do
  if [ -d "$PLUGIN_ROOT/$target" ]; then
    # Search for references to proposal.md / technical-spec.md / priority_matrix.md at the root
    # Detect those without the docs/ prefix
    REFS=$(grep -rn "proposal.md\|technical-spec.md\|priority_matrix.md" "$PLUGIN_ROOT/$target" 2>/dev/null | grep -v "docs/" | grep -v "\.template" || true)
    if [ -n "$REFS" ]; then
      echo "  ❌ References without the docs/ prefix: $target"
      sed -n '1,3p' <<<"$REFS" | sed 's/^/      /'
      DOCS_ISSUES=$((DOCS_ISSUES + 1))
    fi
  fi
done

if [ $DOCS_ISSUES -eq 0 ]; then
  echo "  ✅ docs/ normalization OK"
else
  ERRORS=$((ERRORS + DOCS_ISSUES))
fi

# ================================
# 8. Regression check for bypassPermissions baseline operation
# ================================
echo ""
echo "🔓 [8/14] Regression check for bypassPermissions baseline operation..."

BYPASS_ISSUES=0

# Check 1: disableBypassPermissionsMode has not returned to templates
SECURITY_TEMPLATE="$PLUGIN_ROOT/templates/claude/settings.security.json.template"
if [ -f "$SECURITY_TEMPLATE" ]; then
  if grep -q "disableBypassPermissionsMode" "$SECURITY_TEMPLATE"; then
    echo "  ❌ disableBypassPermissionsMode remains in settings.security.json.template"
    echo "      Since bypassPermissions baseline operation is assumed, remove this setting"
    BYPASS_ISSUES=$((BYPASS_ISSUES + 1))
  else
    echo "  ✅ No disableBypassPermissionsMode"
  fi
fi

# Check 2: the permissions.ask section does not contain Edit / Write
# NOTE: Edit/Write in the deny section is valid as defense-in-depth. Check ask only
if [ -f "$SECURITY_TEMPLATE" ]; then
  # Extract only the ask section and search for Edit/Write
  ASK_EDIT_WRITE=$(sed -n '/"ask"/,/\]/p' "$SECURITY_TEMPLATE" | grep -E '"(Edit|Write|MultiEdit)' || true)
  if [ -n "$ASK_EDIT_WRITE" ]; then
    echo "  ❌ ask in settings.security.json.template contains Edit/Write"
    echo "      Since bypassPermissions baseline operation is assumed, do not put Edit/Write in ask"
    BYPASS_ISSUES=$((BYPASS_ISSUES + 1))
  else
    echo "  ✅ No Edit/Write in ask"
  fi
fi

# Check 2.5: regression check for Bash permission syntax (prefix requires :*)
if [ -f "$SECURITY_TEMPLATE" ]; then
  # Portable regex: use [(] / [*] instead of escaping to avoid BSD grep issues.
  if grep -nEq 'Bash[(][^)]*[^:][*]' "$SECURITY_TEMPLATE"; then
    echo "  ❌ settings.security.json.template contains invalid Bash permission syntax"
    echo "      Use :* for prefix matching (e.g. Bash(git status:*))"
    grep -nE 'Bash[(][^)]*[^:][*]' "$SECURITY_TEMPLATE" | sed -n '1,3p' | sed 's/^/      /'
    BYPASS_ISSUES=$((BYPASS_ISSUES + 1))
  else
    echo "  ✅ Bash permission syntax OK (:*)"
  fi
fi

# Check 3: settings.local.json.template exists and defaultMode is a documented permission mode
# NOTE: the shipped default keeps bypassPermissions; Auto Mode is treated as a follow-up rollout for the teammate execution path
LOCAL_TEMPLATE="$PLUGIN_ROOT/templates/claude/settings.local.json.template"
if [ -f "$LOCAL_TEMPLATE" ]; then
  if grep -q '"defaultMode"[[:space:]]*:[[:space:]]*"bypassPermissions"' "$LOCAL_TEMPLATE"; then
    mode_val=$(grep '"defaultMode"' "$LOCAL_TEMPLATE" | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
    echo "  ✅ settings.local.json.template: defaultMode=${mode_val}"
  else
    echo "  ❌ settings.local.json.template is missing defaultMode=bypassPermissions"
    BYPASS_ISSUES=$((BYPASS_ISSUES + 1))
  fi
else
  echo "  ❌ settings.local.json.template does not exist"
  BYPASS_ISSUES=$((BYPASS_ISSUES + 1))
fi

# Check 4: the managed sandbox precedence key is for managed settings only.
# Mixing it into the regularly distributed harness.toml / plugin settings / templates
# makes the responsibility ambiguous against Claude Code's own managed settings precedence.
MANAGED_SANDBOX_KEY_RE='allowManagedDomainsOnly|allowManagedReadPathsOnly'
MANAGED_SANDBOX_DEFAULT_TARGETS=(
  "$PLUGIN_ROOT/harness.toml"
  "$PLUGIN_ROOT/.claude-plugin/settings.json"
  "$PLUGIN_ROOT/templates/claude/settings.security.json.template"
  "$PLUGIN_ROOT/templates/sandbox-settings.json.template"
)
MANAGED_SANDBOX_ISSUES=0
for target in "${MANAGED_SANDBOX_DEFAULT_TARGETS[@]}"; do
  if [ ! -f "$target" ]; then
    continue
  fi
  FOUND_KEYS=$(grep -nE "$MANAGED_SANDBOX_KEY_RE" "$target" || true)
  if [ -n "$FOUND_KEYS" ]; then
    echo "  ❌ Do not put the managed sandbox key in a regular template/default: ${target#$PLUGIN_ROOT/}"
    sed -n '1,3p' <<<"$FOUND_KEYS" | sed 's/^/      /'
    MANAGED_SANDBOX_ISSUES=$((MANAGED_SANDBOX_ISSUES + 1))
  fi
done

if [ $MANAGED_SANDBOX_ISSUES -eq 0 ]; then
  echo "  ✅ Managed sandbox key is kept separate, for managed settings only"
else
  BYPASS_ISSUES=$((BYPASS_ISSUES + MANAGED_SANDBOX_ISSUES))
fi

if [ $BYPASS_ISSUES -eq 0 ]; then
  echo "  ✅ bypassPermissions baseline operation OK"
else
  ERRORS=$((ERRORS + BYPASS_ISSUES))
fi

# ================================
# 9. Regression check for ccp-* skill removal
# ================================
echo ""
echo "🚫 [9/14] Regression check for ccp-* skill removal..."

CCP_ISSUES=0

# Check 1: skills' name: does not contain ccp-
CCP_NAMES=$(grep -rn "^name: ccp-" "$PLUGIN_ROOT/skills/" 2>/dev/null || true)
if [ -n "$CCP_NAMES" ]; then
  echo "  ❌ name: ccp-* remains in skills"
  sed -n '1,3p' <<<"$CCP_NAMES" | sed 's/^/      /'
  CCP_ISSUES=$((CCP_ISSUES + 1))
else
  echo "  ✅ No name: ccp-* in skills"
fi

# Check 2: workflows' skill: does not contain ccp-
CCP_WORKFLOWS=$(grep -rn "skill: ccp-" "$PLUGIN_ROOT/workflows/" 2>/dev/null || true)
if [ -n "$CCP_WORKFLOWS" ]; then
  echo "  ❌ skill: ccp-* remains in workflows"
  sed -n '1,3p' <<<"$CCP_WORKFLOWS" | sed 's/^/      /'
  CCP_ISSUES=$((CCP_ISSUES + 1))
else
  echo "  ✅ No skill: ccp-* in workflows"
fi

# Check 3: no ccp-* directories remain
CCP_DIRS=$(find "$PLUGIN_ROOT/skills" -type d -name "ccp-*" 2>/dev/null || true)
if [ -n "$CCP_DIRS" ]; then
  echo "  ❌ ccp-* directories remain"
  sed -n '1,3p' <<<"$CCP_DIRS" | sed 's/^/      /'
  CCP_ISSUES=$((CCP_ISSUES + 1))
else
  echo "  ✅ No ccp-* directories"
fi

if [ $CCP_ISSUES -eq 0 ]; then
  echo "  ✅ ccp-* skill removal OK"
else
  ERRORS=$((ERRORS + CCP_ISSUES))
fi

# ================================
# 10. Skill mirror check
# ================================
echo ""
echo "📦 [10/14] Skill mirror check..."

SKILLS_DIR="$PLUGIN_ROOT/skills"
CODEX_SKILLS_DIR="$PLUGIN_ROOT/skills-codex"
CODEX_MIRROR="$PLUGIN_ROOT/codex/.codex/skills"
OPENCODE_MIRROR="$PLUGIN_ROOT/opencode/skills"
MIRROR_ISSUES=0

# Mirror check for core skills (5-verb harness- prefix + aux)
# SSOT: skills/ -> mirror targets: codex/.codex/skills/, opencode/skills/
# NOTE: the mirror side adds disable-model-invocation: true (suppresses auto-invocation)
#       this difference is intentional, so exclude it during comparison
HARNESS_SKILLS="harness-plan harness-work harness-review harness-release harness-setup harness-sync harness-loop"

resolved_ssot_dir() {
  local mirror_name="$1"
  local skill="$2"
  if [ "$mirror_name" = "codex" ] && [ -d "$CODEX_SKILLS_DIR/$skill" ]; then
    printf '%s\n' "$CODEX_SKILLS_DIR/$skill"
    return 0
  fi
  printf '%s\n' "$SKILLS_DIR/$skill"
}

# Mirror comparison helper: diff per file, excluding the disable-model-invocation line
# The mirror-specific setting (auto-invocation suppression) is an intentional difference, so allow it
diff_mirror() {
  local src_dir="$1"
  local mirror_dir="$2"

  # Compare the file list (verify the file layout matches)
  local src_files mirror_files
  src_files="$(cd "$src_dir" && find . -type f | sort)"
  mirror_files="$(cd "$mirror_dir" && find . -type f | sort)"
  if [ "$src_files" != "$mirror_files" ]; then
    return 1
  fi

  # Compare each file individually (excluding only the disable-model-invocation line)
  local f compared=0
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! diff -q \
      <(grep -v '^disable-model-invocation:' "$src_dir/$f") \
      <(grep -v '^disable-model-invocation:' "$mirror_dir/$f") \
      >/dev/null 2>&1; then
      return 1
    fi
    compared=$((compared + 1))
  done <<< "$src_files"

  # Fail safe if no file comparison was performed at all
  [ "$compared" -gt 0 ]
}

for skill in $HARNESS_SKILLS; do
  src="$(resolved_ssot_dir codex "$skill")"
  if [ ! -d "$src" ]; then
    echo "  ❌ $(basename "$(dirname "$src")")/$skill does not exist (SSOT missing)"
    MIRROR_ISSUES=$((MIRROR_ISSUES + 1))
    continue
  fi

  for mirror_name in codex; do
    case "$mirror_name" in
      codex) mirror_root="$CODEX_MIRROR" ;;
    esac

    if [ ! -d "$mirror_root" ]; then
      continue
    fi

    mirror_path="$mirror_root/$skill"
    if [ ! -d "$mirror_path" ]; then
      echo "  ❌ $mirror_name: $skill does not exist as a directory"
      MIRROR_ISSUES=$((MIRROR_ISSUES + 1))
      continue
    fi

    if [ -L "$mirror_path" ]; then
      echo "  ❌ $mirror_name: $skill is still a symlink"
      MIRROR_ISSUES=$((MIRROR_ISSUES + 1))
      continue
    fi

    mirror_src="$(resolved_ssot_dir "$mirror_name" "$skill")"
    if [ ! -d "$mirror_src" ]; then
      echo "  ❌ $mirror_name: SSOT not found (${mirror_src})"
      MIRROR_ISSUES=$((MIRROR_ISSUES + 1))
      continue
    fi

    if diff_mirror "$mirror_src" "$mirror_path"; then
      echo "  ✅ $mirror_name: $skill mirror is in sync"
    else
      echo "  ❌ $mirror_name: $skill mirror does not match SSOT"
      MIRROR_ISSUES=$((MIRROR_ISSUES + 1))
    fi
  done
done

if [ -d "$OPENCODE_MIRROR" ]; then
  if node "$PLUGIN_ROOT/scripts/validate-opencode.js" >/dev/null 2>&1; then
    echo "  ✅ opencode: generated skill mirror is valid"
  else
    echo "  ❌ opencode: generated skill mirror validation failed"
    MIRROR_ISSUES=$((MIRROR_ISSUES + 1))
  fi
fi

if [ $MIRROR_ISSUES -gt 0 ]; then
  ERRORS=$((ERRORS + MIRROR_ISSUES))
fi

# The breezing alias is codex mirror only.
# If a Codex-native version exists in skills-codex/, treat that as the SSOT.
BREEZING_SRC="$SKILLS_DIR/breezing"
if [ -d "$CODEX_SKILLS_DIR/breezing" ]; then
  BREEZING_SRC="$CODEX_SKILLS_DIR/breezing"
fi

if [ -d "$BREEZING_SRC" ]; then
  BREEZING_CODEX="$CODEX_MIRROR/breezing"
  if [ ! -d "$BREEZING_CODEX" ]; then
    echo "  ❌ codex: breezing does not exist as a directory"
    ERRORS=$((ERRORS + 1))
  elif [ -L "$BREEZING_CODEX" ]; then
    echo "  ❌ codex: breezing is still a symlink"
    ERRORS=$((ERRORS + 1))
  elif diff_mirror "$BREEZING_SRC" "$BREEZING_CODEX"; then
    echo "  ✅ codex: breezing mirror is in sync"
  else
    echo "  ❌ codex: breezing mirror does not match SSOT"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  ❌ breezing SSOT not found (skills/ or skills-codex/)"
  ERRORS=$((ERRORS + 1))
fi

FULL_MIRROR_LOG="$(mktemp "${TMPDIR:-/tmp}/harness-skill-mirrors.XXXXXX")"
if bash "$PLUGIN_ROOT/scripts/sync-skill-mirrors.sh" --check >"$FULL_MIRROR_LOG" 2>&1; then
  echo "  ✅ all shipped skill mirrors are in sync"
else
  echo "  ❌ full skill mirror check failed"
  sed 's/^/      /' "$FULL_MIRROR_LOG" | tail -80
  ERRORS=$((ERRORS + 1))
fi
rm -f "$FULL_MIRROR_LOG"

# ================================
# 10.5 Skill orchestration design contract
# ================================
echo ""
echo "🧭 [10.5/14] Skill orchestration design contract..."

SKILL_DESIGN_LOG="$(mktemp "${TMPDIR:-/tmp}/harness-skill-design.XXXXXX")"
if bash "$PLUGIN_ROOT/tests/test-skill-design-contract.sh" >"$SKILL_DESIGN_LOG" 2>&1; then
  echo "  ✅ core skill design metadata is consistent"
else
  echo "  ❌ core skill design metadata check failed"
  sed 's/^/      /' "$SKILL_DESIGN_LOG" | tail -80
  ERRORS=$((ERRORS + 1))
fi
rm -f "$SKILL_DESIGN_LOG"

# ================================
# 10.6 Weak-supervision contract tests
# ================================
echo ""
echo "🧪 [10.6/14] Weak-supervision contract tests..."

WEAK_SUPERVISION_LOG="$(mktemp "${TMPDIR:-/tmp}/harness-weak-supervision.XXXXXX")"
if bash "$PLUGIN_ROOT/tests/test-weak-supervision-report.sh" >"$WEAK_SUPERVISION_LOG" 2>&1; then
  echo "  ✅ weak-supervision report/schema fixtures pass"
else
  echo "  ❌ weak-supervision report/schema fixture check failed"
  sed 's/^/      /' "$WEAK_SUPERVISION_LOG" | tail -80
  ERRORS=$((ERRORS + 1))
fi
rm -f "$WEAK_SUPERVISION_LOG"

# ================================
# 11. CHANGELOG format verification
# ================================
echo ""
echo "📝 [11/14] CHANGELOG format verification..."

CHANGELOG_ISSUES=0

for changelog in "$PLUGIN_ROOT/CHANGELOG.md" "$PLUGIN_ROOT/CHANGELOG_ja.md"; do
  if [ ! -f "$changelog" ]; then
    continue
  fi

  cl_name=$(basename "$changelog")

  # Check 1: Keep a Changelog header (## [x.y.z] - YYYY-MM-DD format)
  BAD_DATES=$(grep -nE '^\#\# \[[0-9]' "$changelog" | grep -vE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -v "Unreleased" || true)
  if [ -n "$BAD_DATES" ]; then
    echo "  ❌ $cl_name: entry with a non-ISO-8601 date"
    sed -n '1,3p' <<<"$BAD_DATES" | sed 's/^/      /'
    CHANGELOG_ISSUES=$((CHANGELOG_ISSUES + 1))
  fi

  # Check 2: non-standard section headings (other than the 6 types in Keep a Changelog 1.1.0)
  # NOTE: the grep pattern keeps Japanese (あなたにとって) to match the localized CHANGELOG heading
  NON_STANDARD=$(grep -nE '^\#\#\# ' "$changelog" \
    | grep -viE '(Added|Changed|Deprecated|Removed|Fixed|Security|What.*Changed|あなたにとって)' \
    | grep -viE '(Internal|Breaking|Migration|Summary|Before)' \
    || true)
  if [ -n "$NON_STANDARD" ]; then
    echo "  ⚠️ $cl_name: non-standard section heading (review recommended)"
    sed -n '1,3p' <<<"$NON_STANDARD" | sed 's/^/      /'
    # Warning only (not treated as an error)
  fi

  # Check 3: whether an [Unreleased] section exists
  if ! grep -q '^\#\# \[Unreleased\]' "$changelog"; then
    echo "  ❌ $cl_name: missing [Unreleased] section"
    CHANGELOG_ISSUES=$((CHANGELOG_ISSUES + 1))
  fi
done

if [ $CHANGELOG_ISSUES -eq 0 ]; then
  echo "  ✅ CHANGELOG format OK"
else
  ERRORS=$((ERRORS + CHANGELOG_ISSUES))
fi

# ================================
# 12. README claim drift check
# ================================
echo ""
echo "📚 [12/14] README claim drift check..."

README_ISSUES=0
README_EN="$PLUGIN_ROOT/README.md"
README_JA="$PLUGIN_ROOT/README_ja.md"
SCOPE_DOC="$PLUGIN_ROOT/docs/distribution-scope.md"
RUBRIC_DOC="$PLUGIN_ROOT/docs/benchmark-rubric.md"
POSITIONING_DOC="$PLUGIN_ROOT/docs/positioning-notes.md"
WORK_ALL_DOC="$PLUGIN_ROOT/docs/evidence/work-all.md"

check_fixed_string() {
  local file_path="$1"
  local needle="$2"
  local label="$3"

  if [ ! -f "$file_path" ]; then
    echo "  ❌ ${label}: file does not exist: $file_path"
    README_ISSUES=$((README_ISSUES + 1))
    return
  fi

  if grep -qF "$needle" "$file_path"; then
    echo "  ✅ ${label}"
  else
    echo "  ❌ ${label}: required string not found"
    README_ISSUES=$((README_ISSUES + 1))
  fi
}

check_absent_string() {
  local file_path="$1"
  local needle="$2"
  local label="$3"

  if [ ! -f "$file_path" ]; then
    echo "  ❌ ${label}: file does not exist: $file_path"
    README_ISSUES=$((README_ISSUES + 1))
    return
  fi

  if grep -qF "$needle" "$file_path"; then
    echo "  ❌ ${label}: a stale claim remains"
    README_ISSUES=$((README_ISSUES + 1))
  else
    echo "  ✅ ${label}"
  fi
}

check_exists() {
  local file_path="$1"
  local label="$2"

  if [ -f "$file_path" ]; then
    echo "  ✅ ${label}"
  else
    echo "  ❌ ${label}: file does not exist"
    README_ISSUES=$((README_ISSUES + 1))
  fi
}

check_fixed_string "$README_EN" "$LATEST_RELEASE_URL" "README.md latest release link"
check_fixed_string "$README_JA" "$LATEST_RELEASE_URL" "README_ja.md latest release link"
check_fixed_string "$README_EN" "$LATEST_RELEASE_BADGE" "README.md latest release badge"
check_fixed_string "$README_JA" "$LATEST_RELEASE_BADGE" "README_ja.md latest release badge"

check_exists "$SCOPE_DOC" "distribution-scope.md"
check_exists "$RUBRIC_DOC" "benchmark-rubric.md"
check_exists "$POSITIONING_DOC" "positioning-notes.md"
check_exists "$WORK_ALL_DOC" "work-all evidence doc"

check_fixed_string "$README_EN" "docs/CLAUDE_CODE_COMPATIBILITY.md" "README.md compatibility doc link"
check_fixed_string "$README_EN" "docs/CURSOR_INTEGRATION.md" "README.md cursor doc link"
check_fixed_string "$README_EN" "docs/evidence/work-all.md" "README.md work-all evidence link"
check_fixed_string "$README_EN" "docs/distribution-scope.md" "README.md distribution scope link"
check_fixed_string "$README_EN" "5 verb skills" "README.md 5 verb skills message"
check_fixed_string "$README_EN" "Go-native guardrail engine" "README.md Go-native guardrail engine message"
check_absent_string "$README_EN" "Production-ready code." "README.md stale production-ready wording"

check_fixed_string "$README_JA" "docs/CLAUDE_CODE_COMPATIBILITY.md" "README_ja.md compatibility doc link"
check_fixed_string "$README_JA" "docs/CURSOR_INTEGRATION.md" "README_ja.md cursor doc link"
check_fixed_string "$README_JA" "docs/evidence/work-all.md" "README_ja.md work-all evidence link"
check_fixed_string "$README_JA" "docs/distribution-scope.md" "README_ja.md distribution scope link"
check_fixed_string "$README_JA" "5動詞スキル" "README_ja.md 5-verb skills message"
check_fixed_string "$README_JA" "Go ネイティブガードレールエンジン" "README_ja.md Go-native guardrail engine message"
check_absent_string "$README_JA" "本番品質のコード。" "README_ja.md stale production-ready wording"

check_fixed_string "$SCOPE_DOC" '| `commands/` | Compatibility-retained |' "distribution-scope commands classification"
check_fixed_string "$SCOPE_DOC" '| `mcp-server/` | Development-only and distribution-excluded |' "distribution-scope mcp-server classification"
check_fixed_string "$RUBRIC_DOC" "| Static evidence |" "benchmark-rubric static evidence"
check_fixed_string "$RUBRIC_DOC" "| Executed evidence |" "benchmark-rubric executed evidence"
check_fixed_string "$POSITIONING_DOC" "runtime enforcement" "positioning-notes runtime enforcement"

if [ $README_ISSUES -eq 0 ]; then
  echo "  ✅ README claim drift check OK"
else
  ERRORS=$((ERRORS + README_ISSUES))
fi

# ================================
# 13. EN/JA visual sync check
# ================================
echo ""
echo "🎨 [13/14] EN/JA visual sync check..."

VISUAL_EN_DIR="$PLUGIN_ROOT/assets/readme-visuals-en/generated"
VISUAL_JA_DIR="$PLUGIN_ROOT/assets/readme-visuals-ja/generated"
VISUAL_ISSUES=0

if [ -d "$VISUAL_EN_DIR" ] && [ -d "$VISUAL_JA_DIR" ]; then
  # Verify that files present in EN also exist in JA and have matching viewBox sizes
  for en_svg in "$VISUAL_EN_DIR"/*.svg; do
    [ ! -f "$en_svg" ] && continue
    svg_name=$(basename "$en_svg")
    ja_svg="$VISUAL_JA_DIR/$svg_name"

    if [ ! -f "$ja_svg" ]; then
      echo "  ❌ JA version missing: $svg_name"
      VISUAL_ISSUES=$((VISUAL_ISSUES + 1))
      continue
    fi

    # Compare viewBox height (detect large structural divergence)
    en_viewbox=$(grep -o 'viewBox="[^"]*"' "$en_svg" | head -1)
    ja_viewbox=$(grep -o 'viewBox="[^"]*"' "$ja_svg" | head -1)
    if [ "$en_viewbox" != "$ja_viewbox" ]; then
      echo "  ⚠️ viewBox mismatch: $svg_name (EN: $en_viewbox / JA: $ja_viewbox)"
      # Warning only (height differences allowed since Japanese char widths differ)
    fi

    # Compare the number of table rows (rough check via the count of <rect y=)
    en_rows=$(grep -c '<rect y=' "$en_svg" 2>/dev/null || echo 0)
    ja_rows=$(grep -c '<rect y=' "$ja_svg" 2>/dev/null || echo 0)
    if [ "$en_rows" != "$ja_rows" ]; then
      echo "  ❌ Row count mismatch: $svg_name (EN: ${en_rows} rows / JA: ${ja_rows} rows)"
      VISUAL_ISSUES=$((VISUAL_ISSUES + 1))
    else
      echo "  ✅ $svg_name (${en_rows} rows)"
    fi
  done
else
  echo "  ⚠️ EN/JA visual directories not found (skipping)"
fi

if [ $VISUAL_ISSUES -gt 0 ]; then
  ERRORS=$((ERRORS + VISUAL_ISSUES))
fi

# ================================
# 14. i18n regression gate
# ================================
echo ""
echo "🌐 [14/14] i18n regression gate..."

I18N_ISSUES=0

run_i18n_gate() {
  local label="$1"
  shift

  local log_file
  log_file="$(mktemp "${TMPDIR:-/tmp}/harness-i18n-gate.XXXXXX")"

  if "$@" >"$log_file" 2>&1; then
    echo "  ✅ $label"
  else
    echo "  ❌ $label"
    sed 's/^/      /' "$log_file" | tail -80
    I18N_ISSUES=$((I18N_ISSUES + 1))
  fi

  rm -f "$log_file"
}

run_i18n_gate "translation metadata" \
  bash "$PLUGIN_ROOT/scripts/i18n/check-translations.sh"
run_i18n_gate "English default config/schema surfaces" \
  bash "$PLUGIN_ROOT/tests/test-i18n-default-language.sh"
run_i18n_gate "skill frontmatter bilingual metadata" \
  bash "$PLUGIN_ROOT/tests/test-i18n-skill-frontmatter.sh"
run_i18n_gate "locale roundtrip idempotency" \
  bash "$PLUGIN_ROOT/tests/test-i18n-locale-roundtrip.sh"
run_i18n_gate "setup language rendering" \
  bash "$PLUGIN_ROOT/tests/test-setup-language-rendering.sh"
run_i18n_gate "Japanese UX opt-in surfaces" \
  bash "$PLUGIN_ROOT/tests/test-i18n-japanese-ux-regression.sh"

if [ $I18N_ISSUES -eq 0 ]; then
  echo "  ✅ i18n regression gate OK"
else
  ERRORS=$((ERRORS + I18N_ISSUES))
fi

# ================================
# Result summary
# ================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ERRORS -eq 0 ]; then
  echo "✅ All checks passed"
  exit 0
else
  echo "❌ $ERRORS problems found"
  exit 1
fi
