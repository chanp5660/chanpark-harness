#!/bin/bash
# Verify this repository keeps branch settings aligned with CCH's review gate policy.

set -euo pipefail

JSON_FILE=""
REPO_SLUG="${HARNESS_BRANCH_PROTECTION_REPO:-}"
# BRANCH is derived automatically when neither the env var nor --branch is given.
# Derivation order (live mode only): gh api repos/<slug> .default_branch
#   → git symbolic-ref refs/remotes/origin/HEAD → "main".
# --json PATH (fixture mode) bypasses all derivation and must stay hermetic.
BRANCH="${HARNESS_BRANCH_PROTECTION_BRANCH:-}"
BRANCH_EXPLICIT=0
if [ -n "${HARNESS_BRANCH_PROTECTION_BRANCH:-}" ]; then
  BRANCH_EXPLICIT=1
fi
REQUIRED_CONTEXTS=(actionlint validate test-go)

usage() {
  cat <<'EOF'
Usage: scripts/check-cch-branch-protection-policy.sh [--json PATH] [--repo OWNER/REPO] [--branch NAME]

Checks:
  - required_pull_request_reviews matches the CCH review gate contract
  - required status checks are strict and include actionlint, validate, test-go
  - force pushes and branch deletion are disabled

Without --json, the script reads live GitHub branch protection via gh api.
The target branch is derived automatically when --branch and
HARNESS_BRANCH_PROTECTION_BRANCH are both unset: first from
"gh api repos/<slug>" .default_branch, then from
git symbolic-ref refs/remotes/origin/HEAD, then falls back to "main".

Exit codes:
  0  all policy checks passed
  1  one or more checks failed (or gh/jq unavailable)
  2  usage error
  3  branch exists but has no protection rules configured (visible warning, not hard fail)
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      JSON_FILE="${2:-}"
      [ -n "$JSON_FILE" ] || { echo "error: --json requires a path" >&2; exit 2; }
      shift 2
      ;;
    --repo)
      REPO_SLUG="${2:-}"
      [ -n "$REPO_SLUG" ] || { echo "error: --repo requires OWNER/REPO" >&2; exit 2; }
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      [ -n "$BRANCH" ] || { echo "error: --branch requires a branch name" >&2; exit 2; }
      BRANCH_EXPLICIT=1
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is required for branch protection policy validation" >&2
    exit 1
  fi
}

derive_repo_slug() {
  local remote
  remote="$(git config --get remote.origin.url 2>/dev/null || true)"
  case "$remote" in
    git@github.com:*.git)
      printf '%s\n' "${remote#git@github.com:}" | sed 's/\.git$//'
      ;;
    git@github.com:*)
      printf '%s\n' "${remote#git@github.com:}"
      ;;
    https://github.com/*.git)
      printf '%s\n' "${remote#https://github.com/}" | sed 's/\.git$//'
      ;;
    https://github.com/*)
      printf '%s\n' "${remote#https://github.com/}"
      ;;
    *)
      return 1
      ;;
  esac
}

# Derive the repository default branch.
# Priority: gh api repos/<slug> .default_branch (most accurate)
#           → git symbolic-ref refs/remotes/origin/HEAD
#           → "main" (last resort)
# Only called in live mode (never when --json is used).
derive_default_branch() {
  local slug="${1:-}"

  # 1. Ask GitHub directly when slug and gh are available.
  if [ -n "$slug" ] && command -v gh >/dev/null 2>&1; then
    local db
    db="$(gh api "repos/$slug" --jq .default_branch 2>/dev/null || true)"
    if [ -n "$db" ]; then
      printf '%s\n' "$db"
      return
    fi
  fi

  # 2. Git's own remote HEAD tracking ref.
  local ref
  ref="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$ref" ]; then
    printf '%s\n' "${ref#origin/}"
    return
  fi

  # 3. Conservative fallback.
  printf 'main\n'
}

load_json() {
  # Fixture mode: read the file directly; never touch the network or derive branch.
  if [ -n "$JSON_FILE" ]; then
    cat "$JSON_FILE"
    return
  fi

  # Resolve the repo slug (needed both for branch derivation and the API call).
  if [ -z "$REPO_SLUG" ]; then
    REPO_SLUG="$(derive_repo_slug || true)"
  fi
  if [ -z "$REPO_SLUG" ]; then
    echo "FAIL: could not derive GitHub owner/repo from origin remote" >&2
    exit 1
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "FAIL: gh CLI is required for live branch protection validation" >&2
    exit 1
  fi

  # Resolve the target branch if not set explicitly.
  if [ "$BRANCH_EXPLICIT" -eq 0 ]; then
    BRANCH="$(derive_default_branch "$REPO_SLUG")"
  fi

  # First confirm the branch itself exists.  This lets us distinguish two 404 cases that
  # the protection endpoint alone cannot tell apart:
  #   • branch not found / inaccessible → real failure (exit 1)
  #   • branch exists but no rules configured → visible skip (exit 3)
  # GitHub's protection API returns 404 "Not Found" for BOTH situations, so a branch-level
  # pre-check is the only reliable way to separate them.
  local branch_check_output
  if ! branch_check_output="$(gh api "repos/${REPO_SLUG}/branches/${BRANCH}" 2>&1)"; then
    printf 'FAIL: branch '\''%s'\'' not found or inaccessible: %s\n' "$BRANCH" "$branch_check_output" >&2
    exit 1
  fi

  # Branch exists — now fetch protection data.
  # A 404 here means "no protection rules configured" (the branch itself is confirmed above).
  local gh_output
  if ! gh_output="$(gh api "repos/${REPO_SLUG}/branches/${BRANCH}/protection" 2>&1)"; then
    printf 'SKIP: branch '\''%s'\'' has no protection rules configured\n' "$BRANCH" >&2
    exit 3
  fi

  printf '%s\n' "$gh_output"
}

# Invoke load_json without letting a non-zero subshell exit abort the script.
# Exit codes 1 and 3 from load_json are re-raised after the subshell returns.
load_json_exit=0
json="$(load_json)" || load_json_exit=$?
if [ "$load_json_exit" -ne 0 ]; then
  exit "$load_json_exit"
fi

require_jq

failures=0

fail_check() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

pass_check() {
  echo "PASS: $1"
}

if jq -e '.required_pull_request_reviews == null' >/dev/null <<<"$json"; then
  pass_check "required_pull_request_reviews is null"
else
  fail_check "required_pull_request_reviews must match the CCH review gate contract"
fi

if jq -e '.required_status_checks.strict == true' >/dev/null <<<"$json"; then
  pass_check "required status checks are strict"
else
  fail_check "required_status_checks.strict must be true"
fi

for context in "${REQUIRED_CONTEXTS[@]}"; do
  if jq -e --arg context "$context" '
    [
      (.required_status_checks.contexts // [])[],
      (.required_status_checks.checks // [])[].context
    ] | index($context) != null
  ' >/dev/null <<<"$json"; then
    pass_check "required status check includes ${context}"
  else
    fail_check "required status checks must include ${context}"
  fi
done

if jq -e 'def enabled: if type == "object" then (.enabled // false) else (. // false) end; (.allow_force_pushes | enabled) == false' >/dev/null <<<"$json"; then
  pass_check "force pushes are disabled"
else
  fail_check "allow_force_pushes must be disabled"
fi

if jq -e 'def enabled: if type == "object" then (.enabled // false) else (. // false) end; (.allow_deletions | enabled) == false' >/dev/null <<<"$json"; then
  pass_check "branch deletion is disabled"
else
  fail_check "allow_deletions must be disabled"
fi

if [ "$failures" -gt 0 ]; then
  exit 1
fi

echo "CCH branch protection policy: ok"
