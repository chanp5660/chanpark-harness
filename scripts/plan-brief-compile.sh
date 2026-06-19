#!/bin/bash
# scripts/plan-brief-compile.sh
# Phase 65.1.3 - Plan Brief context compilation logic
#
# Usage:
#   plan-brief-compile.sh --query <text> --project <name> [--mem-results <path>]
#                         [--understanding <text>] [--out -|<path>]
#
# Role:
#   Build plan-brief-context.v1 schema-compliant JSON from the user request and
#   the harness-mem search results. confidence is the sum of these 3 components:
#     (1) cc:done rate of similar past plans       ... max 40 points
#     (2) numeric-requirement coverage of DoD/request ... max 30 points
#     (3) significance of related D/P counts          ... max 30 points
#   Record the literal numbers behind each component in confidence_evidence (string[]).
#
# Input schema of mem search results (the JSON file pointed to by --mem-results):
#   {
#     "decisions":     [{"id": "D22", "title": "...", "relevance": "..."}, ...],
#     "patterns":      [{"id": "P5",  "title": "...", "relevance": "..."}, ...],
#     "plans_archive": [{"phase": "Phase 41", "archive_path": "...",
#                         "outcome": "cc:done|cc:WIP|cc:TODO|skipped",
#                         "relevance": "..."}, ...]
#   }
# If --mem-results is omitted, all are treated as empty arrays (confidence uses only DoD / D-P components).
#
# Output: plan-brief-context.v1 JSON to stdout (or to the file given by --out)
# Exit code: 0=success, 2=usage error, 3=invalid input

set -euo pipefail

usage() {
  cat <<USAGE >&2
Usage: $0 --query <text> --project <name> [--mem-results <path>]
          [--understanding <text>] [--out -|<path>]

Arguments:
  --query <text>              Body of the user request (required)
  --project <name>            Project name (required, basename of toplevel)
  --mem-results <path>        JSON file of harness-mem search results (optional)
  --understanding <text>      Claude's understanding (optional, default: "(not started yet)")
  --out -|<path>              Output target (- = stdout, default: stdout)

Output: plan-brief-context.v1 schema-compliant JSON
USAGE
  exit 2
}

QUERY=""
PROJECT=""
MEM_RESULTS=""
UNDERSTANDING="(not started yet)"
OUT="-"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --query)         QUERY="${2:-}";         shift 2 ;;
    --project)       PROJECT="${2:-}";       shift 2 ;;
    --mem-results)   MEM_RESULTS="${2:-}";   shift 2 ;;
    --understanding) UNDERSTANDING="${2:-}"; shift 2 ;;
    --out)           OUT="${2:-}";           shift 2 ;;
    -h|--help)       usage ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$QUERY" || -z "$PROJECT" ]]; then
  echo "ERROR: --query and --project are required" >&2
  usage
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found" >&2
  exit 3
fi

# ---- Normalize mem results (empty arrays if omitted) ----

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/plan-brief-compile.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
NORM_MEM="$TMP_DIR/mem.json"

if [[ -n "$MEM_RESULTS" ]]; then
  if [[ ! -f "$MEM_RESULTS" ]]; then
    echo "ERROR: --mem-results file not found: $MEM_RESULTS" >&2
    exit 3
  fi
  if ! jq -e '.' "$MEM_RESULTS" >/dev/null 2>&1; then
    echo "ERROR: --mem-results is not valid JSON: $MEM_RESULTS" >&2
    exit 3
  fi
  jq '{
    decisions:     (.decisions     // []),
    patterns:      (.patterns      // []),
    plans_archive: (.plans_archive // [])
  }' "$MEM_RESULTS" > "$NORM_MEM"
else
  echo '{"decisions":[],"patterns":[],"plans_archive":[]}' > "$NORM_MEM"
fi

# ---- Component (1): cc:done rate of similar past plans (max 40 points) ----
# Note: ".outcome == \"cc:完了\"" preserves the legacy marker value for
# backward-compatible reading of archived plan outcomes.

PAST_TOTAL="$(jq '.plans_archive | length' "$NORM_MEM")"
PAST_DONE="$(jq '[.plans_archive[] | select(.outcome == "cc:完了")] | length' "$NORM_MEM")"

if [[ "$PAST_TOTAL" -eq 0 ]]; then
  SCORE_PAST=0
  EVIDENCE_PAST="Similar past plans: 0 (insufficient signal)"
else
  # Round 40 * (PAST_DONE / PAST_TOTAL)
  SCORE_PAST=$(awk -v d="$PAST_DONE" -v t="$PAST_TOTAL" 'BEGIN { printf "%.0f", 40.0 * d / t }')
  RATE=$(awk -v d="$PAST_DONE" -v t="$PAST_TOTAL" 'BEGIN { printf "%.0f", 100.0 * d / t }')
  EVIDENCE_PAST="${PAST_DONE} of ${PAST_TOTAL} similar past plans (${RATE}%) are cc:done"
fi

# ---- Component (2): numeric-requirement coverage of DoD/request (max 30 points) ----

# Split the request into sentences on "." (full-width period) and "\n", then test
# whether each sentence contains a digit.
# `tr` corrupts the UTF-8 full-width period into raw bytes under LC_ALL=C, so we
# aggregate Unicode-safely with the required jq dependency.

SENTENCE_STATS_JSON="$(jq -n --arg q "$QUERY" '
  ($q
   | gsub("。|\\n"; "\n")
   | split("\n")
   | map(gsub("^[[:space:]]+|[[:space:]]+$"; ""))
   | map(select(length > 0))) as $sentences
  | {
      total: ($sentences | length),
      with_num: ($sentences | map(select(test("[0-9]"))) | length)
    }
')"
NUM_SENTENCES_TOTAL="$(printf '%s\n' "$SENTENCE_STATS_JSON" | jq -r '.total')"
NUM_SENTENCES_WITH_NUM="$(printf '%s\n' "$SENTENCE_STATS_JSON" | jq -r '.with_num')"

if [[ "$NUM_SENTENCES_TOTAL" -eq 0 ]]; then
  SCORE_DOD=0
  EVIDENCE_DOD="request is empty (no DoD signal)"
else
  SCORE_DOD=$(awk -v n="$NUM_SENTENCES_WITH_NUM" -v t="$NUM_SENTENCES_TOTAL" 'BEGIN { printf "%.0f", 30.0 * n / t }')
  RATE_DOD=$(awk -v n="$NUM_SENTENCES_WITH_NUM" -v t="$NUM_SENTENCES_TOTAL" 'BEGIN { printf "%.0f", 100.0 * n / t }')
  EVIDENCE_DOD="${NUM_SENTENCES_WITH_NUM} of ${NUM_SENTENCES_TOTAL} request sentences (${RATE_DOD}%) contain numeric requirements"
fi

# ---- Component (3): significance of related D/P counts (max 30 points) ----

DECISIONS_COUNT="$(jq '.decisions | length' "$NORM_MEM")"
PATTERNS_COUNT="$(jq '.patterns | length' "$NORM_MEM")"
DP_TOTAL=$((DECISIONS_COUNT + PATTERNS_COUNT))

if   [[ "$DP_TOTAL" -ge 6 ]]; then SCORE_DP=30
elif [[ "$DP_TOTAL" -ge 3 ]]; then SCORE_DP=20
elif [[ "$DP_TOTAL" -ge 1 ]]; then SCORE_DP=10
else                               SCORE_DP=0
fi
EVIDENCE_DP="Related D ${DECISIONS_COUNT} + P ${PATTERNS_COUNT} = ${DP_TOTAL} (contributes ${SCORE_DP} pt)"

# ---- confidence total (clamped to 0-100) ----

CONFIDENCE=$((SCORE_PAST + SCORE_DOD + SCORE_DP))
[[ "$CONFIDENCE" -gt 100 ]] && CONFIDENCE=100
[[ "$CONFIDENCE" -lt 0 ]]   && CONFIDENCE=0

# ---- Build output JSON ----

GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Get each section as a normalized array
RELATED_DECISIONS_JSON="$(jq '[.decisions[] | {id: (.id // ""), title: (.title // ""), relevance: (.relevance // "")}]' "$NORM_MEM")"
SIMILAR_PAST_PLANS_JSON="$(jq '[.plans_archive[] | {archive_path: (.archive_path // ""), phase: (.phase // ""), outcome: (.outcome // "unknown"), relevance: (.relevance // "")}]' "$NORM_MEM")"

# confidence_evidence_items is a derived field for template rendering
EVIDENCE_ITEMS_JSON="$(jq -nc \
  --arg p "$EVIDENCE_PAST" \
  --arg d "$EVIDENCE_DOD" \
  --arg r "$EVIDENCE_DP" \
  '[{text: $p}, {text: $d}, {text: $r}]')"

CONTEXT_JSON="$(jq -n \
  --arg req "$QUERY" \
  --arg proj "$PROJECT" \
  --arg ts "$GENERATED_AT" \
  --arg understanding "$UNDERSTANDING" \
  --arg ev_past "$EVIDENCE_PAST" \
  --arg ev_dod "$EVIDENCE_DOD" \
  --arg ev_dp "$EVIDENCE_DP" \
  --argjson conf "$CONFIDENCE" \
  --argjson rd "$RELATED_DECISIONS_JSON" \
  --argjson sp "$SIMILAR_PAST_PLANS_JSON" \
  --argjson ev_items "$EVIDENCE_ITEMS_JSON" \
  '{
    schema: "plan-brief-context.v1",
    user_request: $req,
    my_understanding: $understanding,
    options: [],
    risks: [],
    acceptance_criteria: [],
    confidence: $conf,
    confidence_evidence: [$ev_past, $ev_dod, $ev_dp],
    related_decisions: $rd,
    similar_past_plans: $sp,
    project: $proj,
    generated_at: $ts,
    confidence_evidence_items: $ev_items
  }')"

if [[ "$OUT" == "-" || -z "$OUT" ]]; then
  printf '%s\n' "$CONTEXT_JSON"
else
  printf '%s\n' "$CONTEXT_JSON" > "$OUT"
fi
