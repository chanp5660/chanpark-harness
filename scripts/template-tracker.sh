#!/bin/bash
# template-tracker.sh
# Template tracking: manage the update state of generated files
#
# Features:
# - init: initialize generated-files.json (record the state of existing files)
# - check: check for template updates and show files that need updating
# - status: show detailed state of each file
#
# Usage:
#   template-tracker.sh init   - initialize
#   template-tracker.sh check  - check for updates (for SessionStart, JSON output)
#   template-tracker.sh status - detailed view (human-readable)
#
# Note (v2.5.30+):
# - Frontmatter-based tracking takes priority (_harness_version, _harness_template)
# - generated-files.json is the fallback (to be deprecated in the future)
# - Newly generated files are version-managed via frontmatter

set -euo pipefail

# Get the script directory and the plugin root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load the frontmatter utilities
# shellcheck source=frontmatter-utils.sh
if [ ! -f "$SCRIPT_DIR/frontmatter-utils.sh" ]; then
  echo "Error: frontmatter-utils.sh not found. Please reinstall the plugin." >&2
  exit 1
fi
source "$SCRIPT_DIR/frontmatter-utils.sh"

# Constants
REGISTRY_FILE="$PLUGIN_ROOT/templates/template-registry.json"
STATE_DIR=".claude/state"
GENERATED_FILES="$STATE_DIR/generated-files.json"
VERSION_FILE="$PLUGIN_ROOT/VERSION"

# Get the current plugin version
get_plugin_version() {
  cat "$VERSION_FILE" 2>/dev/null || echo "unknown"
}

# Get the SHA256 hash of a file
get_file_hash() {
  local file="$1"
  if [ -f "$file" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum "$file" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "$file" | cut -d' ' -f1
    else
      # Fallback: md5
      md5sum "$file" 2>/dev/null | cut -d' ' -f1 || md5 -q "$file" 2>/dev/null || echo "no-hash"
    fi
  else
    echo ""
  fi
}

# Load generated-files.json
load_generated_files() {
  if [ -f "$GENERATED_FILES" ]; then
    cat "$GENERATED_FILES"
  else
    echo '{}'
  fi
}

# Save generated-files.json
save_generated_files() {
  local content="$1"
  mkdir -p "$STATE_DIR"
  echo "$content" > "$GENERATED_FILES"
}

# Get the list of tracked=true templates from template-registry.json
get_tracked_templates() {
  if [ ! -f "$REGISTRY_FILE" ]; then
    echo "[]"
    return
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -r '.templates | to_entries | map(select(.value.tracked == true)) | .[].key' "$REGISTRY_FILE" 2>/dev/null
  else
    # When jq is missing, only the basic templates
    echo "CLAUDE.md.template"
    echo "AGENTS.md.template"
    echo "Plans.md.template"
  fi
}

# Get the output path of a template
get_output_path() {
  local template="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".templates[\"$template\"].output // \"\"" "$REGISTRY_FILE" 2>/dev/null
  else
    # Basic mapping when jq is missing
    case "$template" in
      "CLAUDE.md.template") echo "CLAUDE.md" ;;
      "AGENTS.md.template") echo "AGENTS.md" ;;
      "Plans.md.template") echo "Plans.md" ;;
      *) echo "" ;;
    esac
  fi
}

# Get the version of a template
get_template_version() {
  local template="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -r ".templates[\"$template\"].templateVersion // \"unknown\"" "$REGISTRY_FILE" 2>/dev/null
  else
    echo "unknown"
  fi
}

# Initialize: record the state of existing files
cmd_init() {
  local plugin_version
  plugin_version=$(get_plugin_version)

  local result='{"lastCheckedPluginVersion":"'"$plugin_version"'","files":{}}'

  while IFS= read -r template; do
    [ -z "$template" ] && continue

    local output_path
    output_path=$(get_output_path "$template")
    [ -z "$output_path" ] && continue

    if [ -f "$output_path" ]; then
      local file_hash
      file_hash=$(get_file_hash "$output_path")

      # Record existing files as templateVersion: "unknown"
      if command -v jq >/dev/null 2>&1; then
        result=$(echo "$result" | jq --arg path "$output_path" --arg hash "$file_hash" \
          '.files[$path] = {"templateVersion": "unknown", "fileHash": $hash, "recordedAt": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}')
      fi
    fi
  done < <(get_tracked_templates)

  save_generated_files "$result"
  echo "Initialized generated files. Recorded $(echo "$result" | jq '.files | length') file(s)."
}

# Check: detect files that need updating (JSON output)
cmd_check() {
  local generated
  generated=$(load_generated_files)

  local plugin_version
  plugin_version=$(get_plugin_version)

  local last_checked
  if command -v jq >/dev/null 2>&1; then
    last_checked=$(echo "$generated" | jq -r '.lastCheckedPluginVersion // "unknown"')
  else
    last_checked="unknown"
  fi

  # Skip if the plugin version has not changed
  if [ "$last_checked" = "$plugin_version" ]; then
    echo '{"needsCheck": false, "reason": "Plugin version unchanged"}'
    return
  fi

  local updates_needed=()
  local updates_details='[]'
  local installs_details='[]'

  while IFS= read -r template; do
    [ -z "$template" ] && continue

    local output_path
    output_path=$(get_output_path "$template")
    [ -z "$output_path" ] && continue

    local template_version
    template_version=$(get_template_version "$template")

    # Report as needsInstall when the file does not exist
    if [ ! -f "$output_path" ]; then
      if command -v jq >/dev/null 2>&1; then
        installs_details=$(echo "$installs_details" | jq --arg path "$output_path" \
          --arg version "$template_version" \
          '. + [{"path": $path, "version": $version}]')
      fi
      continue
    fi

    local recorded_version="unknown"
    local recorded_hash=""
    local current_hash
    current_hash=$(get_file_hash "$output_path")

    # Phase B: get the version, preferring frontmatter
    local frontmatter_version
    frontmatter_version=$(get_file_version "$output_path" "$GENERATED_FILES")

    if [ -n "$frontmatter_version" ] && [ "$frontmatter_version" != "unknown" ]; then
      recorded_version="$frontmatter_version"
    elif command -v jq >/dev/null 2>&1; then
      # Fallback: get from generated-files.json
      recorded_version=$(echo "$generated" | jq -r ".files[\"$output_path\"].templateVersion // \"unknown\"")
    fi

    if command -v jq >/dev/null 2>&1; then
      recorded_hash=$(echo "$generated" | jq -r ".files[\"$output_path\"].fileHash // \"\"")
    fi

    # Version comparison (unknown is always treated as outdated)
    local needs_update=false
    if [ "$recorded_version" = "unknown" ]; then
      needs_update=true
    elif [ "$recorded_version" != "$template_version" ]; then
      needs_update=true
    fi

    if [ "$needs_update" = true ]; then
      local is_localized=false
      if [ -n "$recorded_hash" ] && [ "$recorded_hash" != "$current_hash" ]; then
        is_localized=true
      fi

      if command -v jq >/dev/null 2>&1; then
        updates_details=$(echo "$updates_details" | jq --arg path "$output_path" \
          --arg from "$recorded_version" --arg to "$template_version" \
          --argjson localized "$is_localized" \
          '. + [{"path": $path, "from": $from, "to": $to, "localized": $localized}]')
      fi
    fi
  done < <(get_tracked_templates)

  local updates_count=0
  local installs_count=0
  if command -v jq >/dev/null 2>&1; then
    updates_count=$(echo "$updates_details" | jq 'length')
    installs_count=$(echo "$installs_details" | jq 'length')
  fi

  # Update lastCheckedPluginVersion
  if command -v jq >/dev/null 2>&1; then
    generated=$(echo "$generated" | jq --arg v "$plugin_version" '.lastCheckedPluginVersion = $v')
    save_generated_files "$generated"
  fi

  local total_count=$((updates_count + installs_count))

  if [ "$total_count" -gt 0 ]; then
    if command -v jq >/dev/null 2>&1; then
      echo "{\"needsCheck\": true, \"updatesCount\": $updates_count, \"installsCount\": $installs_count, \"updates\": $updates_details, \"installs\": $installs_details}"
    else
      echo "{\"needsCheck\": true, \"updatesCount\": $updates_count, \"installsCount\": $installs_count}"
    fi
  else
    echo '{"needsCheck": false, "reason": "All files up to date"}'
  fi
}

# Status: human-readable detailed view
cmd_status() {
  local generated
  generated=$(load_generated_files)

  local plugin_version
  plugin_version=$(get_plugin_version)

  echo "=== Template tracking status ==="
  echo ""
  echo "Plugin version: $plugin_version"

  if command -v jq >/dev/null 2>&1; then
    local last_checked
    last_checked=$(echo "$generated" | jq -r '.lastCheckedPluginVersion // "Not checked"')
    echo "Last checked: $last_checked"
  fi
  echo ""

  printf "%-40s %-12s %-12s %-10s %s\n" "File" "Recorded" "Latest" "Status" "Source"
  printf "%-40s %-12s %-12s %-10s %s\n" "--------" "------" "------" "----" "------"

  while IFS= read -r template; do
    [ -z "$template" ] && continue

    local output_path
    output_path=$(get_output_path "$template")
    [ -z "$output_path" ] && continue

    local template_version
    template_version=$(get_template_version "$template")

    if [ ! -f "$output_path" ]; then
      printf "%-40s %-12s %-12s %-10s\n" "$output_path" "-" "$template_version" "Not generated"
      continue
    fi

    local recorded_version="unknown"
    local recorded_hash=""
    local current_hash
    current_hash=$(get_file_hash "$output_path")

    # Phase B: get the version, preferring frontmatter
    local frontmatter_version
    frontmatter_version=$(get_file_version "$output_path" "$GENERATED_FILES")

    if [ -n "$frontmatter_version" ] && [ "$frontmatter_version" != "unknown" ]; then
      recorded_version="$frontmatter_version"
    elif command -v jq >/dev/null 2>&1; then
      # Fallback: get from generated-files.json
      recorded_version=$(echo "$generated" | jq -r ".files[\"$output_path\"].templateVersion // \"unknown\"")
    fi

    if command -v jq >/dev/null 2>&1; then
      recorded_hash=$(echo "$generated" | jq -r ".files[\"$output_path\"].fileHash // \"\"")
    fi

    local status="Up to date"
    local version_source=""

    # Record the version source for display
    if has_frontmatter "$output_path" 2>/dev/null; then
      version_source="[FM]"
    else
      version_source="[GF]"
    fi

    if [ "$recorded_version" = "unknown" ]; then
      status="Needs review"
    elif [ "$recorded_version" != "$template_version" ]; then
      if [ -n "$recorded_hash" ] && [ "$recorded_hash" != "$current_hash" ]; then
        status="Merge needed"
      else
        status="Overwritable"
      fi
    fi

    printf "%-40s %-12s %-12s %-10s %s\n" "$output_path" "$recorded_version" "$template_version" "$status" "$version_source"
  done < <(get_tracked_templates)

  echo ""
  echo "Legend:"
  echo "  Up to date   : no update needed"
  echo "  Overwritable : no localization, can be updated by overwriting"
  echo "  Merge needed : localized, a merge is required"
  echo "  Needs review : version unknown, review recommended"
  echo ""
  echo "Source:"
  echo "  [FM] : taken from frontmatter (preferred)"
  echo "  [GF] : taken from generated-files.json (fallback)"
}

# Update a file with the latest template (also updates the record)
cmd_record() {
  local file_path="$1"

  if [ -z "$file_path" ]; then
    echo "Usage: template-tracker.sh record <file_path>"
    exit 1
  fi

  if [ ! -f "$file_path" ]; then
    echo "Error: file not found: $file_path"
    exit 1
  fi

  # Find the matching template in template-registry.json
  local template_version=""
  while IFS= read -r template; do
    [ -z "$template" ] && continue

    local output_path
    output_path=$(get_output_path "$template")

    if [ "$output_path" = "$file_path" ]; then
      template_version=$(get_template_version "$template")
      break
    fi
  done < <(get_tracked_templates)

  if [ -z "$template_version" ]; then
    echo "Error: template not found: $file_path"
    exit 1
  fi

  local file_hash
  file_hash=$(get_file_hash "$file_path")

  local generated
  generated=$(load_generated_files)

  if command -v jq >/dev/null 2>&1; then
    generated=$(echo "$generated" | jq --arg path "$file_path" \
      --arg version "$template_version" --arg hash "$file_hash" \
      '.files[$path] = {"templateVersion": $version, "fileHash": $hash, "recordedAt": (now | strftime("%Y-%m-%dT%H:%M:%SZ"))}')
    save_generated_files "$generated"
    echo "Recorded: $file_path (version: $template_version)"
  else
    echo "Error: this operation requires jq"
    exit 1
  fi
}

# Main
case "${1:-}" in
  init)
    cmd_init
    ;;
  check)
    cmd_check
    ;;
  status)
    cmd_status
    ;;
  record)
    cmd_record "$2"
    ;;
  *)
    echo "Usage: template-tracker.sh {init|check|status|record <file>}"
    echo ""
    echo "Commands:"
    echo "  init   - initialize generated-files.json with the current file state"
    echo "  check  - check for template updates (JSON output for SessionStart)"
    echo "  status - show detailed status (human-readable)"
    echo "  record - record the current state of a file"
    exit 1
    ;;
esac
