# Release Notes Format

Rules for converting a CHANGELOG `## [X.Y.Z]` section into GitHub Release notes.

## Language

- **GitHub Release notes: English** (standard for public repositories)
- **CHANGELOG.md: Japanese** (when the project's primary language is Japanese)

If the CHANGELOG is written in Japanese, translation to English is required when creating the GitHub Release.
The skill calls Claude to generate a draft, which is then confirmed with the user at the Confirmation Gate.

## Required Elements

```markdown
## What's Changed

**<1-line value summary>**

### Before / After

| Before | After |
|--------|-------|
| <previous UX> | <new UX> |

---

### Added
- <item>

### Changed
- <item>

### Fixed
- <item>

---

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

## How to Generate Each Element

### "What's Changed" Summary

Extract from the `### Theme` line in the CHANGELOG `[X.Y.Z]` section.
If absent, summarize in one sentence from the first item of Added/Changed/Fixed.

### Before / After Table

Extract from "before / after" descriptions in the CHANGELOG.
If absent, infer from the following:
- Fixed item → `"<bug description>"` vs `"Fixed"`
- Added item → `"<feature> was unavailable"` vs `"now available"`
- Changed item → `"<old behavior>"` vs `"<new behavior>"`

### Added / Changed / Fixed

Translate and copy the applicable CHANGELOG sections directly.

### Footer

Fixed: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`

## GitHub Release Creation Command

```bash
gh release create "v$NEW_VERSION" \
  --title "v$NEW_VERSION - <1-line summary>" \
  --notes "$(cat <<'EOF'
<release notes body>
EOF
)"
```

## Draft Confirmation

At the Confirmation Gate, present the following:

```
GitHub Release Preview:
━━━━━━━━━━━━━━━━━━━━━━
Title: v4.0.4 - Fix CI validation gap
Body (first 20 lines):

  ## What's Changed

  **Fixed a gap in validate-plugin.sh ...**
  ...

(Full body: 45 lines)
━━━━━━━━━━━━━━━━━━━━━━
```

If the user provides a revision instruction such as "revise: ...", regenerate the draft.

## Validation

Before running `gh release create`, check that the Release Notes satisfy the following:

1. `## What's Changed` section exists
2. A **bold summary** line exists
3. `### Before / After` table exists
4. Footer `Generated with [Claude Code]` exists

If any check fails, return to the gate and prompt a fix.

## Consolidating Multiple Changes

If the CHANGELOG `[X.Y.Z]` section contains two or more features:

- Title: represent with the most important one (or "Multiple fixes and improvements")
- Body: split each feature with `### N. <feature name>` and translate

Releasing multiple versions on the same day is not recommended (see versioning.md). Consolidate into a batch release instead.
