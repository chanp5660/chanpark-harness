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

# 1. cursor:WIP → pm:依頼中 (interpreted as "waiting for PM review")
# Note: cursor:WIP usually means "PM (Cursor) is reviewing"
# In the new format this corresponds to pm:依頼中 (implementation done → waiting for PM review)
if grep -qE 'cursor:WIP' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Detected cursor:WIP"
  if [ "$DRY_RUN" = "false" ]; then
    sed -i '' 's/cursor:WIP/pm:依頼中/g' "$PLANS_FILE" 2>/dev/null || \
    sed -i 's/cursor:WIP/pm:依頼中/g' "$PLANS_FILE"
    echo -e "  ${GREEN}✓${NC} Converted cursor:WIP → pm:依頼中"
  else
    echo -e "  [DRY RUN] Will convert cursor:WIP → pm:依頼中"
  fi
  ((CHANGES++))
fi

# 2. cursor:完了 → pm:確認済
if grep -qE 'cursor:完了' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Detected cursor:完了"
  if [ "$DRY_RUN" = "false" ]; then
    sed -i '' 's/cursor:完了/pm:確認済/g' "$PLANS_FILE" 2>/dev/null || \
    sed -i 's/cursor:完了/pm:確認済/g' "$PLANS_FILE"
    echo -e "  ${GREEN}✓${NC} Converted cursor:完了 → pm:確認済"
  else
    echo -e "  [DRY RUN] Will convert cursor:完了 → pm:確認済"
  fi
  ((CHANGES++))
fi

# 3. Check whether the marker legend section needs updating
if ! grep -qE '## マーカー凡例|## Marker Legend' "$PLANS_FILE" 2>/dev/null; then
  echo -e "${YELLOW}→${NC} Marker legend section is missing"
  echo -e "  ${YELLOW}!${NC} Adding it manually is recommended"
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
