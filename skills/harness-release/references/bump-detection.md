# Bump Level Detection

Logic for estimating the bump level (patch/minor/major) from the content of the `[Unreleased]` section.

## Detection Rules

Scan all `### <category>` headings directly under `[Unreleased]` and determine the level using the following priority:

```
1. Contains "### Breaking Changes"             → major
2. Contains "### Removed"                      → major
3. Contains "### Added" (none of the above)    → minor
4. Contains "### Deprecated" (none of the above) → minor
5. Only "### Fixed" / "### Changed" / "### Security" → patch
6. No subsections (empty)                      → error
```

## Implementation

```python
import re

def detect_bump(changelog_text: str) -> str:
    """Return 'major' | 'minor' | 'patch'. Raises on empty [Unreleased]."""
    # Extract the [Unreleased] section
    m = re.search(
        r"## \[Unreleased\]\s*\n(.*?)(?=\n## \[|\Z)",
        changelog_text,
        re.S,
    )
    if not m:
        raise RuntimeError("[Unreleased] section not found")
    body = m.group(1).strip()
    if not body:
        raise RuntimeError("[Unreleased] is empty. Nothing to release.")

    # Collect headings
    headings = set(re.findall(r"^### (.+?)\s*$", body, re.M))

    if "Breaking Changes" in headings or "Removed" in headings:
        return "major"
    if "Added" in headings or "Deprecated" in headings:
        return "minor"
    if headings & {"Fixed", "Changed", "Security"}:
        return "patch"
    raise RuntimeError(f"No recognized subsections found in [Unreleased]: {headings}")
```

## Why is Deprecated Minor?

Per the Keep a Changelog specification, Deprecated is a notice that something "is scheduled to be Removed in the future."
It has a user impact equivalent to adding or changing functionality, so it is treated as minor.
The actual Removed entry will bump to major at that point.

## User Override

If `/release patch|minor|major` is explicitly specified, skip this auto-detection and use the specified value.
However, if the **target section is empty**, abort even with an override (there is nothing to release).

## Non-Standard Headings Are Not Supported

The following are not recognized:

| Common variant | Correct heading |
|-----------------|-----------|
| `### Features` | `### Added` |
| `### Bug Fixes` / `### Fix` | `### Fixed` |
| `### BREAKING CHANGE` / `### Breaking` | `### Breaking Changes` |
| `### Enhancements` | `### Changed` or `### Added` |

Normalize to KaCL standard headings before calling `/release`.
If unrecognized headings are detected before the gate, emit a warning and prompt the user to fix them.

## Handling pre-release / Build Metadata

If the current version has a pre-release suffix such as `1.0.0-alpha.1`, this skill:

1. Ignores the suffix for bump calculation (`1.0.0-alpha.1` → patch → `1.0.1`)
2. Discards the suffix (does not produce `1.0.1-alpha.1`)

Specifying a bump via override does not change this behavior.
Projects that intentionally want to continue as pre-release are not supported by this skill.

## Handling an Empty [Unreleased]

If `/release` is called with an empty `[Unreleased]`, suggest the following:

- "Nothing to release. Either add `### Fixed` or another section to `[Unreleased]`, or consider the `--empty` flag if you want a maintenance release with no content."

The `--empty` flag is not supported by this skill (empty releases are not created by default).
