#!/bin/bash
# plans-format-migrate.sh
# Migrates the old Plans.md format to the new format

set -uo pipefail

PLANS_FILE="${1:-Plans.md}"
DRY_RUN="${2:-false}"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}Plans.md format migration${NC}"
echo "=========================================="
echo ""

# If Plans.md does not exist
if [ ! -f "$PLANS_FILE" ]; then
  echo -e "${RED}Error: $PLANS_FILE not found${NC}"
  exit 1
fi

# Create backup
BACKUP_DIR=".claude-code-harness/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$PLANS_FILE" "$BACKUP_DIR/Plans.md.backup"
echo -e "${GREEN}✓${NC} Backup created: $BACKUP_DIR/Plans.md.backup"

# Change count
CHANGES=0

# 1. cursor:WIP → pm:requested (implementation done → waiting for PM review)
if grep -qE 'cursor:WIP' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Detected cursor:WIP"
  if [ "$DRY_RUN" = "false" ]; then
    sed -i '' 's/cursor:WIP/pm:requested/g' "$PLANS_FILE" 2>/dev/null || \
    sed -i 's/cursor:WIP/pm:requested/g' "$PLANS_FILE"
    echo -e "  ${GREEN}✓${NC} Converted cursor:WIP → pm:requested"
  else
    echo -e "  [DRY RUN] Will convert cursor:WIP → pm:requested"
  fi
  ((CHANGES++))
fi

# 2. cursor:完了 → pm:approved
if grep -qE 'cursor:完了' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Detected cursor:完了"
  if [ "$DRY_RUN" = "false" ]; then
    sed -i '' 's/cursor:完了/pm:approved/g' "$PLANS_FILE" 2>/dev/null || \
    sed -i 's/cursor:完了/pm:approved/g' "$PLANS_FILE"
    echo -e "  ${GREEN}✓${NC} Converted cursor:完了 → pm:approved"
  else
    echo -e "  [DRY RUN] Will convert cursor:完了 → pm:approved"
  fi
  ((CHANGES++))
fi

# 3. cc:cancelled / cc:canceled → cc:dropped (status cells only; see step 4 for why
#    a whole-line substitution is never safe here)
for VARIANT in cc:cancelled cc:canceled; do
  if grep -qiE "$VARIANT" "$PLANS_FILE" 2>/dev/null; then
    echo -e "${YELLOW}→${NC} Detected $VARIANT"
    if [ "$DRY_RUN" = "false" ]; then
      VARIANT="$VARIANT" awk '
        { line = $0
          t = line; sub(/^[[:space:]]+/, "", t)
          if (substr(t,1,3) == "```") { f = !f; print line; next }
          if (f || substr(t,1,4) == "<!--" || line !~ /^[[:space:]]*\|/) { print line; next }
          n = split(line, c, "|")
          for (i = n; i >= 1; i--) { v = c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                                     if (v != "") { last = i; break } }
          v = c[last]
          if (tolower(v) ~ ENVIRON["VARIANT"]) {
            sub(/cc:[Cc]ancell?ed/, "cc:dropped", c[last])
            out = c[1]
            for (i = 2; i <= n; i++) out = out "|" c[i]
            line = out
          }
          print line }' "$PLANS_FILE" > "$PLANS_FILE.tmp" && mv "$PLANS_FILE.tmp" "$PLANS_FILE"
      echo -e "  ${GREEN}✓${NC} Converted $VARIANT → cc:dropped (status cells only)"
    else
      echo -e "  [DRY RUN] Will convert $VARIANT → cc:dropped in status cells"
    fi
    ((CHANGES++))
  fi
done

# 4. Repair HTML entities in STATUS cells — never anywhere else.
#
# This is the exact defect that commit 598f4a11 introduced: it neutralised markers
# QUOTED IN DESCRIPTION CELLS by substituting cc: -> cc&#58; across the WHOLE LINE, so
# on every row whose description happened to quote a marker it also hit the status cell.
# The result renders as a normal cc:done in any viewer and counts as nothing at all —
# four rows of this repo's own Plans.md went silently uncounted for a month.
#
# Description-cell escapes are INTENTIONAL (they keep a quoted marker out of the count)
# and are preserved. Only the last non-empty cell is decoded.
if awk '
  { t=$0; sub(/^[[:space:]]+/,"",t)
    if (substr(t,1,3)=="```") { f=!f; next }
    if (f || substr(t,1,4)=="<!--" || $0 !~ /^[[:space:]]*\|/) next
    n=split($0,c,"|"); s=""
    for (i=n;i>=1;i--) { v=c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v); if (v!="") { s=v; break } }
    if (s ~ /&#58;/) { found=1 } }
  END { exit(found?0:1) }' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Detected HTML-escaped markers in status cells (silent undercount)"
  if [ "$DRY_RUN" = "false" ]; then
    awk '
      { line = $0
        t = line; sub(/^[[:space:]]+/, "", t)
        if (substr(t,1,3) == "```") { f = !f; print line; next }
        if (f || substr(t,1,4) == "<!--" || line !~ /^[[:space:]]*\|/) { print line; next }
        n = split(line, c, "|")
        for (i = n; i >= 1; i--) { v = c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
                                   if (v != "") { last = i; break } }
        gsub(/&#58;/, ":", c[last])
        out = c[1]
        for (i = 2; i <= n; i++) out = out "|" c[i]
        print out }' "$PLANS_FILE" > "$PLANS_FILE.tmp" && mv "$PLANS_FILE.tmp" "$PLANS_FILE"
    echo -e "  ${GREEN}✓${NC} Decoded &#58; in status cells (description cells left escaped)"
  else
    echo -e "  [DRY RUN] Will decode &#58; in status cells only"
  fi
  ((CHANGES++))
fi

# 5. Three-file layout: create the backlog companion if it is missing.
#    Physical separation, not a "## Backlog" heading — a heading is not a filter, every
#    parser scans the whole file, and backlog rows would land in the counts and the HUD.
PLANS_DIR="$(dirname "$PLANS_FILE")"
if [ ! -f "$PLANS_DIR/Plans-backlog.md" ]; then
  echo -e "${YELLOW}→${NC} Plans-backlog.md is missing"
  if [ "$DRY_RUN" = "false" ]; then
    cat > "$PLANS_DIR/Plans-backlog.md" <<'BACKLOG'
# Plans-backlog.md — unscheduled capture

**No `cc:` markers in this file. Ever.** Every counter recognises a task by its marker,
so a file with no markers returns zero from all of them even if one is pointed here by
mistake. Do not add a `cc:backlog` state — it would put the backlog straight back into
the progress numbers and undo the reason this file is separate.

Plain bullets with a capture date. Promotion into Plans.md is a manual rewrite as a full
table row; the friction is deliberate.

---

## Captured

<!-- Append below. Newest last. -->

(nothing yet)
BACKLOG
    echo -e "  ${GREEN}✓${NC} Created $PLANS_DIR/Plans-backlog.md"
  else
    echo -e "  [DRY RUN] Will create $PLANS_DIR/Plans-backlog.md"
  fi
  ((CHANGES++))
fi

# 6. Check whether the marker legend section needs updating
if ! grep -qE '## Marker Legend' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Marker legend section is missing"
  echo -e "  ${YELLOW}!${NC} Adding it manually is recommended"
elif ! grep -q 'cc:dropped' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Marker legend does not mention cc:dropped"
  echo -e "  ${YELLOW}!${NC} Copy the legend from templates/Plans.md.template"
fi

# Show result
echo ""
echo "=========================================="
if [ $CHANGES -gt 0 ]; then
  if [ "$DRY_RUN" = "false" ]; then
    echo -e "${GREEN}✓ Migration complete: $CHANGES change(s)${NC}"
    echo ""
    echo "Please review the changes:"
    echo "  git diff $PLANS_FILE"
  else
    echo -e "${YELLOW}DRY RUN: $CHANGES change(s) planned${NC}"
    echo ""
    echo "To actually convert:"
    echo "  ./scripts/plans-format-migrate.sh $PLANS_FILE false"
  fi
else
  echo -e "${GREEN}✓ No changes needed. Format is up to date.${NC}"
fi
