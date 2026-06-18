# Version File Detection & Update

Details on detecting and updating the four types of version files handled by this skill.

## Priority Order

```
VERSION  >  package.json  >  pyproject.toml  >  Cargo.toml
```

If multiple files exist in a project, the one with the highest priority is authoritative.
Normally only one of these is expected to exist.

## Detection and Reading

### VERSION (standalone file)

```bash
cat VERSION | tr -d '\n'
```

One line only, semantic version (`x.y.z`).

### package.json (npm)

```python
import json
with open("package.json") as f:
    data = json.load(f)
current_version = data["version"]
```

Top-level `"version": "x.y.z"`.

### pyproject.toml (Python)

Supports both PEP 621 (`[project]`) and Poetry (`[tool.poetry]`):

```python
import tomllib
with open("pyproject.toml", "rb") as f:
    data = tomllib.load(f)

if "project" in data and "version" in data["project"]:
    current_version = data["project"]["version"]
elif "tool" in data and "poetry" in data["tool"]:
    current_version = data["tool"]["poetry"]["version"]
else:
    raise RuntimeError("No version found in pyproject.toml")
```

**Note**: Some `pyproject.toml` configurations use `dynamic = ["version"]` to read the version from a separate file (e.g., `_version.py`). This skill does not support that case; switch to a static version in `pyproject.toml`, or use a `VERSION` file alongside it.

### Cargo.toml (Rust)

```python
import tomllib
with open("Cargo.toml", "rb") as f:
    data = tomllib.load(f)
current_version = data["package"]["version"]
```

## Updating

Updates are performed as "minimal field replacement" to avoid breaking formatting style or comments; regex substitution is recommended:

### VERSION

```bash
echo "$NEW_VERSION" > VERSION
```

### package.json

With `jq`:
```bash
jq --arg v "$NEW_VERSION" '.version = $v' package.json > /tmp/package.json && mv /tmp/package.json package.json
```

Without `jq`, use Python:
```python
import json
with open("package.json", "r") as f:
    data = json.load(f)
data["version"] = NEW_VERSION
with open("package.json", "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
```

### pyproject.toml / Cargo.toml

To avoid breaking TOML formatting style, replace only the first `version = "..."` line via regex:

```python
import re
with open("pyproject.toml", "r") as f:
    content = f.read()

# Replace version within the [project] or [tool.poetry] section
section_pattern = None
if re.search(r"^\[project\]", content, re.M):
    section_pattern = r"(\[project\][^\[]*?version\s*=\s*\")[^\"]+(\")"
elif re.search(r"^\[tool\.poetry\]", content, re.M):
    section_pattern = r"(\[tool\.poetry\][^\[]*?version\s*=\s*\")[^\"]+(\")"

new_content = re.sub(
    section_pattern,
    rf"\g<1>{NEW_VERSION}\g<2>",
    content,
    count=1,
    flags=re.S,
)
with open("pyproject.toml", "w") as f:
    f.write(new_content)
```

Cargo.toml follows the same pattern (within the `[package]` section):

```python
section_pattern = r"(\[package\][^\[]*?version\s*=\s*\")[^\"]+(\")"
```

## Handling Sub-packages

Monorepos with multiple version files (e.g., npm workspaces) are out of scope for this skill.
The design uses only the root file as authoritative.
To synchronize multiple packages, build a dedicated release orchestrator separately.

## Unsupported Version Formats

The following are not supported. Normalize to SemVer format beforehand:

- `v1.0.0` (leading `v` is not accepted in files; only tags use the `v` prefix)
- `1.0.0-alpha.1` (pre-release suffix is preserved but not bumped)
- `1.0.0+build.1` (build metadata is preserved)
- Calendar versioning (`2024.01`)
