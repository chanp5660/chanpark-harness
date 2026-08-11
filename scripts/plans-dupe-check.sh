#!/usr/bin/env bash
# scripts/plans-dupe-check.sh
# Duplicate-candidate report for a proposed plan item. Advisory. Never blocks.
#
# Usage:
#   plans-dupe-check.sh <new-description> [corpus-file ...]
#   plans-dupe-check.sh --root <dir> [--threshold 0.4] <new-description> [file ...]
#
# With no corpus files, it compares against BOTH default sinks:
#   <root>/Plans.md            — the Task cell of every table row with a status marker
#   <root>/Plans-backlog.md    — every live bullet under "## Captured"
#
# Comparing both is the whole point. `harness-plan` routes new items to the backlog by
# default, so the backlog is where near-duplicates actually accumulate; a dedupe that
# only reads Plans.md never looks at the file it is supposed to protect.
#
# Output (stdout), one line per candidate, highest score first:
#
#   0.53  Plans-backlog.md:41  Rewrite the sweep to work per row instead of per file
#
# Exit status: 0 when no candidate reaches the threshold, 1 when at least one does.
# Callers MUST NOT treat 1 as an error. It exists so a script can branch on "there is
# something to show"; the skill contract is to print the candidates and continue.
#
# Why advisory (docs/design/plans-redesign.md §2.4)
# ------------------------------------------------
# A PreToolUse hook that refuses the write fails closed and cannot be recovered from
# mid-flow — this repository already has that scar, where one `cc:wip-paused` row locked
# every session out of ever stopping. A duplicate row fails open and is cheap: you see
# it, or the next sweep offers one of the pair as a drop candidate.
#
# Metric and threshold
# --------------------
# Jaccard similarity over the unique word sets, after lowercasing, removing
# `[tdd:*]` / `[P]` tags and code spans, and reducing everything else to
# [a-z0-9]+ tokens. No stopword list: the threshold below was derived on the raw word
# sets, and quietly changing the tokenizer would invalidate it.
#
#   observed maximum real pairwise similarity in this corpus  = 0.21
#   pairs above 0.20 out of 190                               = 0
#   threshold = 2 x the observed noise ceiling                = 0.4
#
# So 0.4 yields zero false positives on everything measured. It is a ceiling-derived
# bound, not a fitted value, and it is overridable with --threshold.

set -uo pipefail

ROOT=""
THRESHOLD=""
QUERY=""
FILES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --root)      ROOT="${2:-}"; shift 2 ;;
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,45p' "$0" >&2; exit 0 ;;
    --)          shift; break ;;
    -*)          echo "plans-dupe-check: unknown option: $1" >&2; exit 0 ;;
    *)           if [ -z "$QUERY" ]; then QUERY="$1"; else FILES+=("$1"); fi; shift ;;
  esac
done
while [ $# -gt 0 ]; do
  if [ -z "$QUERY" ]; then QUERY="$1"; else FILES+=("$1"); fi; shift
done

if [ -z "$QUERY" ]; then
  echo "plans-dupe-check: usage: plans-dupe-check.sh <new-description> [file ...]" >&2
  exit 0
fi

ROOT="${ROOT:-${CLAUDE_PROJECT_DIR:-$PWD}}"
[ -n "$THRESHOLD" ] || THRESHOLD="0.4"
case "$THRESHOLD" in
  ''|*[!0-9.]*) THRESHOLD="0.4" ;;
esac

if [ "${#FILES[@]}" -eq 0 ]; then
  [ -f "$ROOT/Plans.md" ]         && FILES+=("$ROOT/Plans.md")
  [ -f "$ROOT/Plans-backlog.md" ] && FILES+=("$ROOT/Plans-backlog.md")
fi
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "plans-dupe-check: no corpus (looked for $ROOT/Plans.md and $ROOT/Plans-backlog.md)"
  exit 0
fi

# --- Extract the comparison corpus: "<file>:<line>\t<description>" ------------------
# Plans.md contributes the Task cell of rows whose LAST non-empty cell is a status
# marker — the same anchored rule the canonical counter uses, so the legend table and
# the format examples cannot enter the corpus.
# Plans-backlog.md contributes live "## Captured" bullets; struck-through (declined)
# bullets are resolved and are excluded, or a declined idea would keep flagging its
# own successor forever.
extract() {
  local f="$1" base
  base="$(basename "$f")"
  awk -v src="$base" '
    { t = $0; sub(/^[[:space:]]+/, "", t)
      if (substr(t,1,3) == "```") { fence = !fence; next }
      if (fence) next
      if (substr(t,1,4) == "<!--") next

      # --- table row (active/terminal task) ---
      if (t ~ /^\|/) {
        n = split($0, c, "|")
        s = ""; last = 0
        for (i = n; i >= 1; i--) { v = c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                                   if (v != "") { s = tolower(v); last = i; break } }
        sub(/^cursor:/, "", s); sub(/^cc:/, "", s)
        ok = 0
        if (s ~ /^(todo|wip|done|blocked|dropped)([^a-z0-9_-]|$)/) ok = 1
        if (!ok) next
        # second non-empty cell = Task, in both the 5-column and 3-column dialects
        seen = 0; desc = ""
        for (i = 1; i < last; i++) { v = c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                                     if (v == "") continue
                                     seen++
                                     if (seen == 2) { desc = v; break } }
        if (desc == "") next
        printf "%s:%d\t%s\n", src, NR, desc
        next
      }

      # --- backlog bullet ---
      if (t ~ /^## +Captured/) { cap = 1; next }
      if (t ~ /^## /)          { cap = 0; next }
      if (!cap) next
      if (t !~ /^[-*][[:space:]]+/) next
      body = t; sub(/^[-*][[:space:]]+/, "", body)
      if (body ~ /^~~/) next
      sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]*(—|-)?[[:space:]]*/, "", body)
      if (body == "") next
      printf "%s:%d\t%s\n", src, NR, body
    }
  ' "$f" 2>/dev/null
}

CORPUS=""
for f in "${FILES[@]}"; do
  [ -f "$f" ] && [ -r "$f" ] || continue
  CORPUS="${CORPUS}$(extract "$f")
"
done
CORPUS="$(printf '%s' "$CORPUS" | grep . )"

if [ -z "$CORPUS" ]; then
  echo "plans-dupe-check: no comparable items yet — nothing to compare '$QUERY' against"
  exit 0
fi

# --- Score --------------------------------------------------------------------------
HITS="$(printf '%s\n' "$CORPUS" | awk -F'\t' -v q="$QUERY" -v thr="$THRESHOLD" '
  function tokens(s, out,   i, n, w, k) {
    s = tolower(s)
    gsub(/`[^`]*`/, " ", s)             # code spans carry no topical content
    gsub(/\[tdd:[^]]*\]/, " ", s)       # measured boilerplate, per the design
    gsub(/\[p\]/, " ", s)
    gsub(/[^a-z0-9]+/, " ", s)
    n = split(s, w, " ")
    k = 0
    for (i = 1; i <= n; i++) if (w[i] != "") { if (!(w[i] in out)) { out[w[i]] = 1; k++ } }
    return k
  }
  BEGIN { qn = tokens(q, Q); if (qn == 0) exit 0 }
  {
    delete C
    cn = tokens($2, C)
    if (cn == 0) next
    inter = 0
    for (w in Q) if (w in C) inter++
    union = qn + cn - inter
    if (union == 0) next
    score = inter / union
    if (score + 1e-9 < thr) next
    printf "%.2f\t%s\t%s\n", score, $1, $2
  }
' | sort -rn)"

TOTAL="$(printf '%s\n' "$CORPUS" | grep -c .)"

if [ -z "$HITS" ]; then
  printf 'plans-dupe-check: no candidates >= %s (compared against %s item(s) in %s)\n' \
    "$THRESHOLD" "$TOTAL" "$(printf '%s ' "${FILES[@]##*/}" | sed 's/ $//')"
  exit 0
fi

printf 'plans-dupe-check: %s possible duplicate(s) >= %s for: %s\n' \
  "$(printf '%s\n' "$HITS" | grep -c .)" "$THRESHOLD" "$QUERY"
printf '%s\n' "$HITS" | awk -F'\t' '{ printf "  %s  %-24s %s\n", $1, $2, $3 }'
printf 'ADVISORY ONLY — show these, then continue. Never refuse the write.\n'
exit 1
