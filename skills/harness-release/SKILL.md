---
name: harness-release
description: "Generic release automation for projects using Keep a Changelog + GitHub. Single confirmation gate then end-to-end automation: bump detection, CHANGELOG promotion, PR/main merge, tag, GitHub Release. Trigger: release, version bump, publish. Do NOT load for: implementation, review, planning, setup."
kind: workflow
purpose: "Release projects through changelog, version, PR/main merge, tag, and GitHub Release gates"
trigger: "release, version bump, publish"
shape: workflow
role: orchestrator
pair: harness-review
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion", "Skill"]
argument-hint: "[patch|minor|major|--dry-run]"
context: fork
effort: high
user-invocable: true
---

# Harness Release (Generic)

Generic release automation skill for **any project** using Keep a Changelog + GitHub.

**Design principle**: Single confirmation gate. The user reviews and approves the full plan exactly once. After approval, the process runs uninterrupted: file rewrites → commit → branch push → PR create/update → merge into default branch → tag on default branch → GitHub Release.

**Definition of release complete**: A release is not complete merely by creating a tag and GitHub Release. Completion means the target work and release bump are merged into the default branch (usually `main`), the release tag points to a commit reachable from the default branch, and the GitHub Release is published against that tag.

> **Literal invocation note**: The entry point for this skill is a literal command such as `harness-release`, `/release`, `/release patch`, or `/release --dry-run`.

## Bare invocation contract

if $ARGUMENTS == "":
  → Interpret as "commit all work so far and release, completing through PR/main merge"
  → Only proceed automatically to Step 0 (Review Gate) if the target work can be determined unambiguously
  → If the target is unclear or no review state exists, show options via AskUserQuestion before proceeding

On the first response of a bare invocation, always output the following literal marker:

`RELEASE_AUTOSTART: target=<work-summary>, base_ref=<ref>, mode=<patch|minor|major|auto>`

Prohibited behaviors: "task is unclear", "waiting for instructions", "no tasks", "waiting for further instructions".

<!-- The block above is the AUTO-START CONTRACT. Complies with skill-editing.md "within first 3 lines" rule and patterns.md P27 three-part solution (machine-readable condition + prohibited literal + AUTOSTART marker) -->

### Output Contract (P35: "appears frozen" UX mitigation)

The **last line** of output when the skill concludes must include the P35 footer, and the footer must be written in the same language as the body prose (language resolution follows existing language rules; the footer contract does not redefine language). This is an explicit instruction (patterns.md P35) addressing the UX problem where the user perceives the process as "frozen" when output is displayed via `<local-command-stdout>`. The intent is language-independent, so the literal varies by language (#208):

- en: `↑Claude will summarize this result. Press Enter to continue, or send a new prompt for a different instruction.`
- Other languages: output one line with the same meaning in the same language as the body.

### Language

User-facing prose follows the explicit session or project language.
If no language is configured, use English. Use Japanese only when
`i18n.language: ja`, `CLAUDE_CODE_HARNESS_LANG=ja`, or an explicit session
instruction requests Japanese output.
Machine-readable values stay English.

When only `harness-release` / `/release` is entered, treat it as meaning
**"commit all work so far and release, completing through PR/main merge"**.
The older phrasing **"commit and release all work so far"** carries the same intent, but the completion condition must always include PR/main merge.
Do not stop with "no tasks" or "waiting for instructions".

In a bare release, execute the **Review Gate** and **Work Commit Gate** before the normal release preflight.

1. Check `git status --porcelain` and `git log @{upstream}..HEAD` / `main..HEAD` to identify the target "work so far"
2. Check `.claude/state/review-result.json` and `.claude/state/review-approved.json` to confirm whether the target work has an `APPROVE`d review
3. If no approved review is found, ask via `AskUserQuestion`
4. If the user chooses "start with review", launch `harness-review` and do not proceed to release until the result is `APPROVE`
5. If `harness-review` returns `REQUEST_CHANGES`, hold the release and fix with `harness-work`, then re-run `harness-review`. Loop until `APPROVE`
6. After `harness-review` returns `APPROVE`, create the work commit from the working tree
7. Once the working tree is clean, proceed to the normal release preflight / confirmation gate / PR merge / tag / GitHub Release

### Review Gate AskUserQuestion

If `harness-release` cannot confirm review approval, do not release by assumption.
Show the following Ask:

```text
question: "harness-release will commit all work so far and release, but no APPROVE review was found for this work. How would you like to proceed?"
options:
  - label: "Start with review (Recommended)"
    description: "Run harness-review; only proceed to commit/release if the result is APPROVE."
  - label: "release dry-run"
    description: "Show the release plan and missing gates without modifying any files."
  - label: "Abort"
    description: "Stop without running review or release."
```

If the user chooses "Start with review", launch `harness-review` within the same session.
Target determination for `harness-review` follows `harness-review`'s own bare review contract.
If the review result is `APPROVE`, return to the `harness-release` Work Commit Gate.
If the review result is `REQUEST_CHANGES`, hold the release, fix with `harness-work`, then re-run `harness-review`.
This fix-then-re-review loop continues until `APPROVE`.

Return control to the user only in these cases:

1. The fix requires a decision that only the user can make — specification, Plans.md, API, permission, migration, billing, etc. — and `AskUserQuestion` is needed
2. Multiple fix approaches exist and the choice affects user value or compatibility
3. The user chose `release dry-run` or `Abort` in the Ask

`REQUEST_CHANGES` alone must not be the final stopping reason.

### Work Commit Gate

In a bare release, if the working tree has uncommitted changes, create a reviewed work commit separately from the release version bump commit.

```bash
git status --short
git diff --stat
git add <reviewed files>
git commit -m "<type>: <summary>"
```

Generate the commit message concisely from the review summary, Plans.md task, or branch name.
If the message cannot be determined, show 2–3 candidate commit messages via `AskUserQuestion`.
After creating the work commit, verify or update `commit_hash` in `.claude/state/review-result.json`, then proceed to release preflight.

After entering the normal release preflight, continue to treat a dirty working tree as a failure.
Do not proceed to version bump / tag / GitHub Release with a dirty tree.

## Quick Reference

```bash
/release              # Review gate → commit → PR/main merge → release all work so far
/release patch        # Explicitly specify patch bump
/release minor        # Explicitly specify minor bump
/release major        # Explicitly specify major bump
/release --dry-run    # Show plan only; do not execute
```

## Prerequisites

Projects using this skill must satisfy the following:

1. `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/) format
2. An `[Unreleased]` section exists
3. The project has one of the following version files:
   - `VERSION` (standalone file)
   - `package.json` (npm)
   - `pyproject.toml` (Python, `[project]` or `[tool.poetry]`)
   - `Cargo.toml` (Rust, `[package]`)
4. `gh` CLI is installed and authenticated
5. git remote `origin` points to GitHub
6. For Claude Code plugin projects, the `claude` CLI supports `plugin tag`

If any of these are not satisfied, Preflight will detect and abort.

`prUrlTemplate`-based multi-host review URLs are recognized as a future candidate, but
the release automation in this skill continues to use `gh` CLI and GitHub remote as the primary path.
Automatic retrieval of owner / branch / release asset / CI metadata differs significantly per host,
so Phase 56.2.3 limits this to docs-only.

## Single-Gate Flow

```
[Bare release only: work review/commit pre-stage]
  ↓
  0. Review Gate (if no review approval: AskUserQuestion → harness-review)
  0.5 Work Commit Gate (commit reviewed work separately from the release bump)
  ↓
[Pre-Gate: information gathering only; no files modified]
  ↓
  1. Preflight (working tree clean / CHANGELOG / gh checks, etc.)
  2. Auto-detect version file
  3. Read current version
  4. Claude plugin tag preflight (plugin projects only)
  5. Parse [Unreleased] content → estimate bump level
  6. Calculate new version
  7. Draft CHANGELOG diff (in memory)
  8. Draft GitHub Release notes (in memory)

★━━━━━━ Single Confirmation Gate ━━━━━━★
  Present the full plan to the user exactly once:
    - Detected version file
    - Current version → new version
    - Bump decision reason (e.g. "minor because [Unreleased] contains ### Added")
    - CHANGELOG change preview
    - GitHub Release notes draft
    - List of files to commit
    - Final actions (branch push + PR merge + tag + release publish)

  User response:
    "yes"              → Proceed to Post-Gate
    "<revision>"       → Regenerate draft per instructions, re-confirm
    "cancel/no"        → Exit without doing anything
★━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━★
  ↓
[Post-Gate: runs uninterrupted after approval]

  9. Rewrite version file
  10. Rewrite CHANGELOG.md ([Unreleased] → [X.Y.Z] promotion + compare link)
  11. git add + commit
  12. Push release branch
  13. Create/update PR
  14. Merge into default branch
  15. Fetch/checkout default branch and confirm the release commit is reachable
  16. Claude plugin tag validation + tag (plugin projects only)
  17. Semver tag for GitHub Release (only for projects that need it)
  18. git push origin <default-branch> --tags
  19. gh release create vX.Y.Z
  20. Completion report
```

## Pre-Gate Details

### 1. Preflight

```bash
# Required tools
command -v gh >/dev/null || { echo "gh CLI not found"; exit 1; }
command -v python3 >/dev/null || { echo "python3 is required"; exit 1; }

# working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "Uncommitted changes in working tree"; exit 1;
fi

# CHANGELOG
[ -f CHANGELOG.md ] || { echo "CHANGELOG.md not found"; exit 1; }
grep -q "^## \[Unreleased\]" CHANGELOG.md || { echo "[Unreleased] section not found"; exit 1; }

# plugin/mirror projects
scripts/release-preflight.sh
```

This working tree clean check is the gate for the normal release preflight.
In a bare release where you want to commit "work so far", complete the Review Gate and Work Commit Gate before this check.
Do not abort and stop solely because of an unreviewed dirty tree.

`scripts/release-preflight.sh` also detects mirror drift in `opencode/`, `skills-codex/`, and `codex/.codex/skills/` before creating the tag. If `node scripts/build-opencode.js` produces a diff, the release is halted; commit that diff before proceeding to the tag.

### 2. Version File Auto-Detection

Search in the following priority order. The first match is authoritative:

```python
# Python snippet to run inline
import os, json, re
import tomllib  # Python 3.11+

def detect_version_file():
    if os.path.exists("VERSION"):
        with open("VERSION") as f:
            return ("VERSION", f.read().strip(), None)
    if os.path.exists("package.json"):
        with open("package.json") as f:
            data = json.load(f)
        return ("package.json", data["version"], None)
    if os.path.exists("pyproject.toml"):
        with open("pyproject.toml", "rb") as f:
            data = tomllib.load(f)
        if "project" in data:
            return ("pyproject.toml", data["project"]["version"], "[project]")
        if "tool" in data and "poetry" in data["tool"]:
            return ("pyproject.toml", data["tool"]["poetry"]["version"], "[tool.poetry]")
    if os.path.exists("Cargo.toml"):
        with open("Cargo.toml", "rb") as f:
            data = tomllib.load(f)
        return ("Cargo.toml", data["package"]["version"], "[package]")
    raise RuntimeError("No supported version file found")
```

Details: [version-files.md](${CLAUDE_SKILL_DIR}/references/version-files.md)

### 3. Claude Plugin Tag Preflight

For projects that have `.claude-plugin/plugin.json`, a Claude plugin release tag is created in addition to the normal GitHub Release tag.

In short, before manually assembling `git tag -a`, pass plugin validation through Claude Code itself, then create the `{plugin-name}--v{version}` tag.

In the Pre-Gate, no files are modified; only the following checks are performed.
Version sync is read via a structured parser, not `grep` / `sed`:

```bash
command -v claude >/dev/null || { echo "claude CLI not found"; exit 1; }
claude plugin validate .claude-plugin/plugin.json

HARNESS_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-.}"
python3 "${HARNESS_PLUGIN_ROOT}/scripts/check-release-version-sync.py" --root .

claude plugin tag .claude-plugin --dry-run
```

`${HARNESS_PLUGIN_ROOT}/scripts/check-release-version-sync.py` reads all existing release surfaces and determines the canonical version in the order `VERSION > package.json > .claude-plugin/plugin.json > .codex-plugin/plugin.json`.
If any of the following have a mismatch or are missing, the process does not proceed to tag / release:

- `VERSION`
- `.version` in `package.json`
- `.version` in `.claude-plugin/plugin.json`
- `.version` in `.codex-plugin/plugin.json`
- `.metadata.version` in `.claude-plugin/marketplace.json`
- `.plugins[].version` in `.claude-plugin/marketplace.json` (each plugin entry in the array)

On mismatch, display which surface differs from canonical, or which field is missing / invalid.
For machine processing or CI, use `--json`:

```bash
python3 "${HARNESS_PLUGIN_ROOT}/scripts/check-release-version-sync.py" --root . --json
```

This check prevents three classes of accidents:

- Cutting a tag while `VERSION` and `.claude-plugin/plugin.json` versions are out of sync
- Advancing the release workflow while `package.json` / marketplace entry versions are stale
- Skipping plugin manifest / marketplace entry validation and hitting failures later during plugin install / update

`--dry-run` shows the tag name that `claude plugin tag` will create and the equivalent `git tag -a` / push command. Include the command shown here in the Confirmation Gate plan.

### 4. Automatic Bump Estimation

Parse the headings directly under `[Unreleased]` to determine bump level:

| Headings in [Unreleased] | Estimated bump |
|------------------------|-----------|
| Contains `### Breaking Changes` or `### Removed` | **major** |
| Contains `### Added` (no Removed/Breaking) | **minor** |
| Only `### Fixed` / `### Changed` / `### Security` | **patch** |
| Empty section | **error: nothing to release** |

If the user explicitly specifies `/release patch|minor|major`, that value takes priority.
Details: [bump-detection.md](${CLAUDE_SKILL_DIR}/references/bump-detection.md)

### 5. CHANGELOG Draft (in Memory)

Calculate the following without writing anything yet:

1. Extract the body of `## [Unreleased]`
2. Construct the result of inserting `## [<new>] - YYYY-MM-DD` between `## [Unreleased]` and `## [<previous>]`
3. Trailing compare links:
   - `[Unreleased]: .../compare/v<prev>...HEAD` → `v<new>...HEAD`
   - Add `[<new>]: .../compare/v<prev>...v<new>`
4. Dynamically extract the repo URL from the existing `[Unreleased]: ` line

### 6. Release Notes Draft (in Memory)

Generate GitHub Release markdown from the content of the `## [<new>]` section:

```markdown
## What's Changed

**<release theme (1 line)>**

### Before / After
<table>

### Added / Changed / Fixed / Removed
<copy of applicable sections>

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

Details: [release-notes.md](${CLAUDE_SKILL_DIR}/references/release-notes.md)

## Confirmation Gate

Once all drafts are ready, present to the user exactly once:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Release Plan: v<old> → v<new> (<bump>)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 Version file: <detected file>
 Bump reason:  <why this level was chosen>

 CHANGELOG changes:
   Detected <N> changes in [Unreleased]
   Confirmed as [<new>] - YYYY-MM-DD
   Compare link added

 GitHub Release notes preview:
   <first 10 lines>
   ...

 Files to modify:
   - <version file>
   - CHANGELOG.md

 Final actions:
   - git commit -m "chore: release v<new>"
   - git push origin <release-branch>
   - gh pr create/update + gh pr merge into <default-branch>
   - git fetch origin <default-branch> && git checkout <default-branch>
   - claude plugin tag .claude-plugin --push --remote origin  # plugin projects only; run on default branch
   - git tag -a v<new>                                        # only if semver tag for GitHub Release is needed; created on default branch
   - git push origin <default-branch> --tags
   - gh release create v<new>

Proceed? [yes / cancel / <revision instructions>]
```

## Post-Gate Details

Execute without interruption after approval. On failure, follow this policy:

| Failure point | Recovery |
|---------|------|
| File rewrite failed | Abort at that point; local tree remains dirty for human judgment |
| Commit failed | Hook rejection, etc. Show the cause to the user and prompt a fix |
| PR create/merge failed | Halt as release incomplete; do not proceed to tag / GitHub Release |
| Plugin tag validation failed | Fix the mismatch in `VERSION` / `.claude-plugin/plugin.json` / marketplace entry; do not proceed to tag creation |
| Push failed | Remote-side issue. Retain local commit/tag |
| `gh release create` failed | Tag is already pushed; the existing release.yml safety net may fire, or run `gh release create` manually |

### PR / Main Merge Gate

After the release commit in the Post-Gate, merge the GitHub PR into the default branch before creating the tag.

```bash
release_branch="$(git branch --show-current)"
default_branch="${HARNESS_RELEASE_DEFAULT_BRANCH:-main}"

git push -u origin "$release_branch"
gh pr create --base "$default_branch" --head "$release_branch" --title "chore: release v<new>" --body "<release summary>"
gh pr merge --merge --delete-branch=false

git fetch origin "$default_branch" --tags
git checkout "$default_branch"
git pull --ff-only origin "$default_branch"
git merge-base --is-ancestor "<release-commit>" "origin/$default_branch"
```

If a PR already exists, do not create a new one; update the existing PR body and merge it. If the repository policy requires squash merge, confirm that the content of the release bump (version files + CHANGELOG + source commits) is present in the default branch rather than verifying by release commit hash.

Tags are created against the HEAD of the default branch or a commit reachable from the default branch, only after this gate is complete. Do not create a GitHub Release with a tag pointing to a commit that exists only on the release branch.

### Claude Plugin Project Tag Creation

For projects with `.claude-plugin/plugin.json`, after PR/main merge, confirm version sync once more on the default branch before creating the plugin tag:

```bash
HARNESS_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-.}"
python3 "${HARNESS_PLUGIN_ROOT}/scripts/check-release-version-sync.py" --root .

claude plugin tag .claude-plugin --dry-run
claude plugin tag .claude-plugin --push --remote origin
```

The tag created by `claude plugin tag` follows the format `{plugin-name}--v{version}`. For projects where an existing GitHub Release workflow assumes a `vX.Y.Z` tag, create `git tag -a v<new>` separately from the plugin tag. Let `claude plugin tag` manage the plugin distribution tag; treat the GitHub Release semver tag as a compatible surface of the release automation.

## `--dry-run` Mode

Execute all Pre-Gate steps and display content up to the Confirmation Gate, but **stop at the gate without proceeding to Post-Gate**.

For Claude plugin projects, even in dry-run mode, run `python3 "${HARNESS_PLUGIN_ROOT}/scripts/check-release-version-sync.py" --root .` and `claude plugin tag .claude-plugin --dry-run`, and display the plugin tag name that would be created and its push target. If any version surface in `VERSION` / `package.json` / `.claude-plugin/plugin.json` / `.codex-plugin/plugin.json` / `.claude-plugin/marketplace.json` is mismatched or missing, halt at dry-run time.

## Environment Variables

Used for per-project adjustments:

| Variable | Description |
|------|------|
| `HARNESS_RELEASE_PROJECT_ROOT` | Repository root (default: `$(pwd)`) |
| `HARNESS_RELEASE_BRANCH` | Branch to push to (default: current branch) |
| `HARNESS_RELEASE_DEFAULT_BRANCH` | Default branch for PR merge target (default: `main`) |
| `HARNESS_RELEASE_HEALTHCHECK_CMD` | Additional command to run during Preflight |
| `HARNESS_RELEASE_SKIP_GH` | Set to `1` to skip GitHub Release creation |

## CHANGELOG Writing Rules

The `[Unreleased]` section must contain at least one of the following subsections:

```markdown
## [Unreleased]

### Added       ← minor
### Changed     ← patch
### Deprecated  ← minor
### Removed     ← major
### Fixed       ← patch
### Security    ← patch
### Breaking Changes  ← major (non-standard in Keep a Changelog but common)
```

This skill parses these headings mechanically. Heading variations such as `### Fix` or `### Bug Fixes` are not recognized. Use the standard KaCL headings.

## Related Skills

- `harness-release-internal` - Additional harness-specific preflight/finalization run when releasing claude-code-harness itself (not distributed)
- `harness-plan` - Plans.md management
- `harness-review` - Code review before release

## Design Philosophy

- **Single gate**: The user makes a judgment call exactly once. Inserting mini-confirmations degrades them into rubber-stamps that lose meaning
- **Draft everything upfront**: No "second-guessing" once Post-Gate begins; all drafts are ready before the gate
- **Main merge is the completion condition**: Release tags / GitHub Releases are created only after merging into the default branch; branch-only releases are treated as incomplete
- **Transparent failures**: On mid-process failure, do not attempt automatic rollback; present the current state to the user and let them decide
- **Project-agnostic**: Does not assume a specific environment for VERSION file format, mirror, residue check, etc. Harness-specific processing is isolated in `harness-release-internal`
