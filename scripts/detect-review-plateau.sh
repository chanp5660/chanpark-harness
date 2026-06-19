#!/bin/bash
# detect-review-plateau.sh
# Detect whether the review-fix loop is stuck and prompt the Lead to pivot (change strategy).
#
# Usage: ./scripts/detect-review-plateau.sh <task_id> [--calibration-file <path>]
#
# Exit codes:
#   0 = PIVOT_NOT_REQUIRED
#   1 = INSUFFICIENT_DATA
#   2 = PIVOT_REQUIRED
#
# Output (stdout):
#   STATUS: PIVOT_REQUIRED | PIVOT_NOT_REQUIRED | INSUFFICIENT_DATA
#   ENTRIES: <N>
#   JACCARD_AVG: <0.XX>  (N>=3 only)
#   REASON: <description>

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 1
fi

# --- Parse arguments ---
TASK_ID=""
CALIBRATION_FILE=".claude/state/review-calibration.jsonl"

_positional=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --calibration-file)
      shift
      CALIBRATION_FILE="${1:-}"
      ;;
    --*)
      # Ignore unknown options
      ;;
    *)
      _positional+=("$1")
      ;;
  esac
  shift
done

if [ "${#_positional[@]}" -ge 1 ]; then
  TASK_ID="${_positional[0]}"
fi

if [ -z "$TASK_ID" ]; then
  echo "Usage: scripts/detect-review-plateau.sh <task_id> [--calibration-file <path>]" >&2
  exit 1
fi

if [ ! -f "$CALIBRATION_FILE" ]; then
  echo "STATUS: INSUFFICIENT_DATA"
  echo "ENTRIES: 0"
  echo "REASON: calibration file not found: $CALIBRATION_FILE"
  exit 1
fi

# --- Extract entries for the same task_id (most recent N) ---
ENTRIES_JSON="$(jq -c --arg tid "$TASK_ID" \
  'select(.task.id == $tid)' \
  "$CALIBRATION_FILE" 2>/dev/null | tail -3)"

ENTRY_COUNT="$(printf '%s\n' "$ENTRIES_JSON" | jq -s 'length' 2>/dev/null || printf '0')"

# Also get total count (the count check uses all entries)
ALL_ENTRIES_JSON="$(jq -c --arg tid "$TASK_ID" \
  'select(.task.id == $tid)' \
  "$CALIBRATION_FILE" 2>/dev/null)"

TOTAL_COUNT="$(printf '%s\n' "$ALL_ENTRIES_JSON" | jq -s 'length' 2>/dev/null || printf '0')"

# --- N < 3: INSUFFICIENT_DATA ---
if [ "$TOTAL_COUNT" -lt 3 ]; then
  echo "STATUS: INSUFFICIENT_DATA"
  echo "ENTRIES: $TOTAL_COUNT"
  echo "REASON: not enough calibration entries (need >= 3, found $TOTAL_COUNT)"
  exit 1
fi

# --- N >= 3: analyze the most recent 3 entries ---

# Function to extract the file set from each entry
# Priority:
#   1. review_result_snapshot.files_changed[]
#   2. first ':'-delimited part of gaps[].location
#   3. empty set if neither is present
extract_files() {
  local entry="$1"
  local files=""

  # 1. review_result_snapshot.files_changed
  files="$(echo "$entry" | jq -r '
    (.review_result_snapshot.files_changed // []) | .[]
  ' 2>/dev/null)"

  if [ -z "$files" ]; then
    # 2. first ':'-delimited part of gaps[].location
    files="$(echo "$entry" | jq -r '
      (.gaps // [])
      | map(select(.location != null and .location != ""))
      | map(.location | split(":")[0])
      | .[]
    ' 2>/dev/null)"
  fi

  echo "$files"
}

# Store the most recent 3 entries in variables
ENTRY1="$(echo "$ENTRIES_JSON" | sed -n '1p')"
ENTRY2="$(echo "$ENTRIES_JSON" | sed -n '2p')"
ENTRY3="$(echo "$ENTRIES_JSON" | sed -n '3p')"

# Extract file sets (deduplicated and sorted)
FILES1="$(extract_files "$ENTRY1" | sort -u)"
FILES2="$(extract_files "$ENTRY2" | sort -u)"
FILES3="$(extract_files "$ENTRY3" | sort -u)"

# Jaccard similarity calculation function
# |A ∩ B| / |A ∪ B|
jaccard() {
  local set_a="$1"
  local set_b="$2"

  # If both are empty, similarity is 1.0 (same empty set)
  if [ -z "$set_a" ] && [ -z "$set_b" ]; then
    echo "1.0"
    return
  fi

  # If only one is empty, similarity is 0.0
  if [ -z "$set_a" ] || [ -z "$set_b" ]; then
    echo "0.0"
    return
  fi

  # Number of common elements (intersection)
  local intersection
  intersection="$(comm -12 \
    <(echo "$set_a" | sort -u) \
    <(echo "$set_b" | sort -u) \
    | wc -l | tr -d ' ')"

  # Union size (union = |A| + |B| - |intersection|)
  local count_a count_b union
  count_a="$(echo "$set_a" | sort -u | wc -l | tr -d ' ')"
  count_b="$(echo "$set_b" | sort -u | wc -l | tr -d ' ')"
  union=$(( count_a + count_b - intersection ))

  if [ "$union" -eq 0 ]; then
    echo "1.0"
    return
  fi

  # Floating-point math (bash is integer-only, so use awk)
  awk "BEGIN { printf \"%.4f\", $intersection / $union }"
}

# Compute Jaccard similarity for the 3 pairs
J12="$(jaccard "$FILES1" "$FILES2")"
J13="$(jaccard "$FILES1" "$FILES3")"
J23="$(jaccard "$FILES2" "$FILES3")"

# Average Jaccard
JACCARD_AVG="$(awk "BEGIN { printf \"%.4f\", ($J12 + $J13 + $J23) / 3 }")"

# Condition (b): average Jaccard across all pairs > 0.7
THRESHOLD="0.7"
IS_PLATEAU="$(awk "BEGIN { print ($JACCARD_AVG > $THRESHOLD) ? \"yes\" : \"no\" }")"

if [ "$IS_PLATEAU" = "yes" ]; then
  echo "STATUS: PIVOT_REQUIRED"
  echo "ENTRIES: $TOTAL_COUNT"
  echo "JACCARD_AVG: $JACCARD_AVG"
  echo "REASON: review iterations >= 3 and file-set similarity (Jaccard avg $JACCARD_AVG) > $THRESHOLD — stuck in same files"
  exit 2
else
  echo "STATUS: PIVOT_NOT_REQUIRED"
  echo "ENTRIES: $TOTAL_COUNT"
  echo "JACCARD_AVG: $JACCARD_AVG"
  echo "REASON: file-set similarity (Jaccard avg $JACCARD_AVG) <= $THRESHOLD — review is making progress"
  exit 0
fi
