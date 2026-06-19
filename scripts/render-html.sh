#!/usr/bin/env bash
# scripts/render-html.sh
# Phase 65.1.1 - HTML template renderer (mustache-style) + data binding via jq
#
# Usage:
#   render-html.sh --template <name> --data <json_path|-> --out <output_path>
#
# Syntax:
#   {{var}}                       … reference a top-level scalar of data
#   {{#section}}...{{/section}}   … iterate over data[section] (array); inside the
#                                   block, {{key}} references a field of the item
#
# The canonical input JSON is the html-render-input.v1 schema (kind / project /
# generated_at / sections), but the MVP uses soft validation that "accepts any
# parseable JSON". Fields not in the template are ignored, and fields in the
# template missing from data expand to empty strings (jq fallback via // "").
#
# Template location: templates/html/<name>.html.template
# The output HTML opens standalone (no server, no JS framework); CSS is assumed inline.
# Templates use the Claude Harness brand
# (off-white #FAFAFA / near-black #0F0F0F / harness-orange #F58A4A).

set -euo pipefail

# awk returns byte offsets, but bash's ${var:offset:length} is locale-dependent and
# counts a UTF-8 multi-byte sequence as one character. To align the two, pin to byte
# units (LC_ALL=C). The output HTML only copies the byte stream verbatim, so UTF-8
# is preserved correctly.
export LC_ALL=C

usage() {
  cat <<USAGE >&2
Usage: $0 --template <name> --data <json_path|-> --out <output_path>

Arguments:
  --template <name>       template basename (without the .html.template extension)
                          reads templates/html/<name>.html.template
  --data <json_path|->    JSON data file (- reads from stdin)
  --out <output_path>     destination of the output HTML
USAGE
  exit 2
}

TEMPLATE_NAME=""
DATA_PATH=""
OUT_PATH=""
WITH_REDACTION="false"
CLIENT_DICT_PATH=""
AUDIT_GROUP=""
AUDIT_MEMBERS=""
AUDIT_QUERY_HASH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)         TEMPLATE_NAME="${2:-}"; shift 2 ;;
    --data)             DATA_PATH="${2:-}";     shift 2 ;;
    --out)              OUT_PATH="${2:-}";      shift 2 ;;
    --with-redaction)   WITH_REDACTION="true";  shift 1 ;;
    --client-dict)      CLIENT_DICT_PATH="${2:-}"; shift 2 ;;
    --audit-group)      AUDIT_GROUP="${2:-}";   shift 2 ;;
    --audit-members)    AUDIT_MEMBERS="${2:-}"; shift 2 ;;
    --audit-query-hash) AUDIT_QUERY_HASH="${2:-}"; shift 2 ;;
    -h|--help)          usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$TEMPLATE_NAME" || -z "$DATA_PATH" || -z "$OUT_PATH" ]]; then
  echo "ERROR: one of --template / --data / --out is not specified" >&2
  usage
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq not found. Please install jq." >&2
  exit 5
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_PATH="$PLUGIN_ROOT/templates/html/${TEMPLATE_NAME}.html.template"

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "ERROR: template not found: $TEMPLATE_PATH" >&2
  exit 3
fi

# Save JSON data to a normalized file (- means stdin, otherwise that file)
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/render-html.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
DATA_FILE="$TMP_DIR/data.json"

if [[ "$DATA_PATH" == "-" ]]; then
  cat > "$DATA_FILE"
else
  if [[ ! -f "$DATA_PATH" ]]; then
    echo "ERROR: data file not found: $DATA_PATH" >&2
    exit 3
  fi
  cp "$DATA_PATH" "$DATA_FILE"
fi

if ! jq -e '.' "$DATA_FILE" >/dev/null 2>&1; then
  echo "ERROR: invalid JSON in data file (jq failed to parse)" >&2
  exit 4
fi

# --- internal functions ---

# Returns position info for the "first {{#tag}}...{{/tag}} found" in the template.
# Output: "<open_offset> <open_len> <block_len> <tag_name>" or empty string (if not found).
#   open_offset … 0-based byte offset where {{#tag}} starts
#   open_len    … length of "{{#tag}}" itself
#   block_len   … length of the block between {{#tag}} and {{/tag}}
#   tag_name    … tag identifier
find_first_section() {
  local content="$1"
  printf '%s' "$content" | awk '
    # BSD awk interprets RS="\0" as empty (= paragraph mode) and drops the leading
    # newline, so use a sentinel string that never appears in the input as RS
    # (effectively one record up to EOF).
    BEGIN { RS = "__RENDER_HTML_AWK_RS_SENTINEL_NEVER_OCCURS__"; }
    {
      if (match($0, /\{\{#[a-zA-Z_][a-zA-Z_0-9]*\}\}/)) {
        open_start = RSTART
        open_len = RLENGTH
        tag = substr($0, RSTART + 3, RLENGTH - 5)
        rest = substr($0, RSTART + RLENGTH)
        close_marker = "{{/" tag "}}"
        cp = index(rest, close_marker)
        if (cp > 0) {
          printf "%d %d %d %s", open_start - 1, open_len, cp - 1, tag
        }
      }
    }
  '
}

# Returns position info for the "first {{var}} found" in the template.
# Output: "<offset> <length> <var_name>" or empty string.
find_first_var() {
  local content="$1"
  printf '%s' "$content" | awk '
    # BSD awk interprets RS="\0" as empty (= paragraph mode) and drops the leading
    # newline, so use a sentinel string that never appears in the input as RS
    # (effectively one record up to EOF).
    BEGIN { RS = "__RENDER_HTML_AWK_RS_SENTINEL_NEVER_OCCURS__"; }
    {
      if (match($0, /\{\{[a-zA-Z_][a-zA-Z_0-9]*\}\}/)) {
        printf "%d %d %s", RSTART - 1, RLENGTH, substr($0, RSTART + 2, RLENGTH - 4)
      }
    }
  '
}

# Get a top-level var from data_file as a string (empty string if absent)
lookup_top_var() {
  local var="$1"
  jq -r --arg k "$var" '.[$k] // "" | tostring' "$DATA_FILE"
}

# Get a var as a string from an item (JSON) within a section
lookup_item_var() {
  local item_json="$1"
  local var="$2"
  printf '%s' "$item_json" | jq -r --arg k "$var" '.[$k] // "" | tostring'
}

# Escape sentinel to prevent double expansion. By replacing a `{` from a data value
# with SENTINEL, even if that value contains `{{...}}` it won't match either the
# stage-1 or stage-2 awk pattern. After all expansion completes, SENTINEL is turned
# back into `{` to restore the original text.
#
# A 3-byte sequence (SOH + STX + ETX) is used to keep the probability of it pre-existing
# in a data value practically zero.
# A 1-byte sentinel is avoided because, when the JSON contains it, the final
# restoration could mis-convert.
SENTINEL_OPEN_BRACE=$'\x01\x02\x03'

escape_val_for_embed() {
  # Replace `{` in a data value with SENTINEL (prevents double expansion)
  local v="$1"
  printf '%s' "${v//\{/$SENTINEL_OPEN_BRACE}"
}

# Render a block for one item: replace each {{var}} in the block with item.var.
render_block_with_item() {
  local block="$1"
  local item_json="$2"

  local rendered="$block"
  while :; do
    local info
    info="$(find_first_var "$rendered")"
    [[ -z "$info" ]] && break

    local off len var
    off="$(echo "$info" | awk '{print $1}')"
    len="$(echo "$info" | awk '{print $2}')"
    var="$(echo "$info" | awk '{print $3}')"

    local val val_safe
    val="$(lookup_item_var "$item_json" "$var")"
    val_safe="$(escape_val_for_embed "$val")"

    rendered="${rendered:0:off}${val_safe}${rendered:$((off + len))}"
  done

  printf '%s' "$rendered"
}

# --- stage 1: expand section blocks ---
TEMPLATE_CONTENT="$(cat "$TEMPLATE_PATH")"

while :; do
  info="$(find_first_section "$TEMPLATE_CONTENT")"
  [[ -z "$info" ]] && break

  open_off="$(echo "$info" | awk '{print $1}')"
  open_len="$(echo "$info" | awk '{print $2}')"
  block_len="$(echo "$info" | awk '{print $3}')"
  tag_name="$(echo "$info" | awk '{print $4}')"

  prefix="${TEMPLATE_CONTENT:0:open_off}"
  block="${TEMPLATE_CONTENT:$((open_off + open_len)):block_len}"
  # 5 is the fixed 5 chars of the close marker `{{/<tag>}}` excluding the tag (`{{/` + `}}`)
  suffix_off=$((open_off + open_len + block_len + ${#tag_name} + 5))
  suffix="${TEMPLATE_CONTENT:$suffix_off}"

  # If data[tag_name] is not an array (or missing), treat it as an empty array
  items_count="$(jq -r --arg t "$tag_name" '
    if (.[$t] | type) == "array" then (.[$t] | length) else 0 end
  ' "$DATA_FILE")"

  rendered_section=""
  if [[ "$items_count" -gt 0 ]]; then
    for ((i = 0; i < items_count; i++)); do
      item_json="$(jq -c --arg t "$tag_name" --argjson i "$i" '.[$t][$i]' "$DATA_FILE")"
      rendered_block="$(render_block_with_item "$block" "$item_json")"
      rendered_section="${rendered_section}${rendered_block}"
    done
  fi

  TEMPLATE_CONTENT="${prefix}${rendered_section}${suffix}"
done

# --- stage 2: expand top-level {{var}} (escape {{...}} within val to prevent re-expansion) ---
while :; do
  info="$(find_first_var "$TEMPLATE_CONTENT")"
  [[ -z "$info" ]] && break

  off="$(echo "$info" | awk '{print $1}')"
  len="$(echo "$info" | awk '{print $2}')"
  var="$(echo "$info" | awk '{print $3}')"

  val="$(lookup_top_var "$var")"
  val_safe="$(escape_val_for_embed "$val")"

  TEMPLATE_CONTENT="${TEMPLATE_CONTENT:0:off}${val_safe}${TEMPLATE_CONTENT:$((off + len))}"
done

# All expansion done — restore SENTINEL to `{` to recover the original text.
# In bash 3.2's `${var//SEARCH/REPLACE}`, writing `\{` in the replacement inserts a
# literal backslash, so pass the literal `{` via a variable.
LITERAL_OPEN_BRACE="{"
TEMPLATE_CONTENT="${TEMPLATE_CONTENT//$SENTINEL_OPEN_BRACE/$LITERAL_OPEN_BRACE}"

# --- Layer 2/3 Redaction (Phase 65.3.4 / D43) + Phase 65.3.6 audit ---
# When --with-redaction is enabled, run 3 stages in order just before HTML output:
#   Layer 2a: redact-by-dictionary.sh (literal proper nouns)
#   Layer 2b: redact-by-ner.sh (Japanese tokenizer)
#   Layer 3 : final scan (detect runs of 5+ consecutive katakana as residue)
# If Layer 3 detects something, **do not write the HTML and exit 1**, outputting the
# detected token to stderr.
# Phase 65.3.6: when --audit-group is specified, append to the audit log + show a
# redaction summary at the end of the HTML.
DICT_COUNT=0
NER_COUNT=0
PASSED_FINAL_SCAN="true"
if [[ "$WITH_REDACTION" == "true" ]]; then
  REDACTION_LOG="$TMP_DIR/redaction.log"
  : > "$REDACTION_LOG"
  DICT_LOG="$TMP_DIR/dict.log"
  NER_LOG="$TMP_DIR/ner.log"

  # Layer 2a: dict (use --client-dict if specified, otherwise the default SSOT)
  if [[ -n "$CLIENT_DICT_PATH" ]]; then
    TEMPLATE_CONTENT="$(printf '%s' "$TEMPLATE_CONTENT" | bash "$SCRIPT_DIR/redact-by-dictionary.sh" --stdin --dict "$CLIENT_DICT_PATH" 2>"$DICT_LOG" || true)"
  else
    TEMPLATE_CONTENT="$(printf '%s' "$TEMPLATE_CONTENT" | bash "$SCRIPT_DIR/redact-by-dictionary.sh" --stdin 2>"$DICT_LOG" || true)"
  fi
  cat "$DICT_LOG" >> "$REDACTION_LOG"

  # parse "redacted: N tokens" from dict stderr
  if grep -q "redacted:" "$DICT_LOG" 2>/dev/null; then
    DICT_COUNT="$(awk '/redacted:/ {print $2}' "$DICT_LOG" | head -1)"
    DICT_COUNT="${DICT_COUNT:-0}"
  fi

  # Layer 2b: NER
  TEMPLATE_CONTENT="$(printf '%s' "$TEMPLATE_CONTENT" | bash "$SCRIPT_DIR/redact-by-ner.sh" --stdin 2>"$NER_LOG" || true)"
  cat "$NER_LOG" >> "$REDACTION_LOG"

  # parse "redacted: N entities" from NER stderr
  if grep -q "redacted:" "$NER_LOG" 2>/dev/null; then
    NER_COUNT="$(awk '/redacted:/ {print $2}' "$NER_LOG" | head -1)"
    NER_COUNT="${NER_COUNT:-0}"
  fi

  # Layer 3: final scan
  set +e
  printf '%s' "$TEMPLATE_CONTENT" | python3 "$SCRIPT_DIR/final-scan-redaction.py"
  FINAL_SCAN_EXIT=$?
  set -e

  if [[ $FINAL_SCAN_EXIT -ne 0 ]]; then
    PASSED_FINAL_SCAN="false"
    # Record "failed" in the audit log before aborting (handles the
    # "final scan failure" case in Plans.md DoD e)
    if [[ -n "$AUDIT_GROUP" && -n "$AUDIT_QUERY_HASH" ]]; then
      bash "$SCRIPT_DIR/cross-project-audit-log.sh" \
        --group "$AUDIT_GROUP" \
        --members "${AUDIT_MEMBERS:-}" \
        --query-hash "$AUDIT_QUERY_HASH" \
        --dict-count "$DICT_COUNT" \
        --ner-count "$NER_COUNT" \
        --passed-final-scan "false" 2>>"$REDACTION_LOG" || true
    fi
    echo "ERROR: Layer 3 final scan detected residue (HTML generation aborted)" >&2
    exit 1
  fi

  # --- Show a redaction summary at the end of the HTML (Plans.md §65.3.6 DoD d) ---
  # Insert the footer just before </body>. If there is no </body>, append at the end.
  AUDIT_FOOTER="<div class=\"audit-summary\" style=\"margin-top:2em;padding:0.6em 0.8em;border-top:1px solid #ccc;font-size:0.85em;color:#666;\">redacted: dict ${DICT_COUNT} + NER ${NER_COUNT}</div>"
  # bash parameter substitution: only the first '/' in the pattern is the separator,
  # the rest are literal. '<\/body>' in the replacement becomes a literal "<\/body>",
  # so always write '</body>' (no backslash).
  if printf '%s' "$TEMPLATE_CONTENT" | grep -q "</body>"; then
    BODY_CLOSE_TAG="</body>"
    TEMPLATE_CONTENT="${TEMPLATE_CONTENT/${BODY_CLOSE_TAG}/${AUDIT_FOOTER}${BODY_CLOSE_TAG}}"
  else
    TEMPLATE_CONTENT="${TEMPLATE_CONTENT}${AUDIT_FOOTER}"
  fi

  # --- audit log append (only when --audit-group is specified) ---
  if [[ -n "$AUDIT_GROUP" && -n "$AUDIT_QUERY_HASH" ]]; then
    bash "$SCRIPT_DIR/cross-project-audit-log.sh" \
      --group "$AUDIT_GROUP" \
      --members "${AUDIT_MEMBERS:-}" \
      --query-hash "$AUDIT_QUERY_HASH" \
      --dict-count "$DICT_COUNT" \
      --ner-count "$NER_COUNT" \
      --passed-final-scan "$PASSED_FINAL_SCAN" 2>>"$REDACTION_LOG" || true
  fi
fi

# --- output ---
OUT_DIR="$(dirname "$OUT_PATH")"
mkdir -p "$OUT_DIR"
printf '%s' "$TEMPLATE_CONTENT" > "$OUT_PATH"

# Ensure a trailing newline (keep the template's if present, otherwise add one line for cleaner diffs)
if [[ "${TEMPLATE_CONTENT: -1}" != $'\n' ]]; then
  printf '\n' >> "$OUT_PATH"
fi

exit 0
