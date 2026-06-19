#!/usr/bin/env bash
# enable-1h-cache.sh
# Append ENABLE_PROMPT_CACHING_1H=1 to env.local (idempotent).
# Script to opt in to the CC v2.1.108+ 1-hour prompt cache for long Harness sessions.
#
# Usage:
#   bash scripts/enable-1h-cache.sh
#
# Effect:
#   - Append ENABLE_PROMPT_CACHING_1H=1 to env.local in the project root
#   - Do nothing if it is already set (idempotent)
#   - Create env.local if it does not exist
#
# Selection criteria:
#   - Choose the 1h cache if the session is expected to exceed 30 minutes
#   - For short exchanges under 30 minutes, the default 5-minute cache is enough
#
# Notes:
#   - Do not commit env.local to the repository (recommend adding to .gitignore)
#   - Does not change global settings; applies only to this project's sessions

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$(cd "$(dirname "$0")/.." && pwd)")"
ENV_LOCAL="${REPO_ROOT}/env.local"
KEY="ENABLE_PROMPT_CACHING_1H"
VALUE="1"
# Use `export KEY=VALUE` so that `source env.local` propagates the variable
# to subprocesses (claude). Without `export`, `source env.local` only sets a
# shell-local variable and the spawned `claude` process never sees it.
ENTRY="export ${KEY}=${VALUE}"

# Check whether an active config line already exists (ignore comment lines)
if grep -qE "^export ${KEY}=${VALUE}$" "${ENV_LOCAL}" 2>/dev/null; then
  echo "[enable-1h-cache] ${ENTRY} is already set in ${ENV_LOCAL} (no change)."
  exit 0
fi

# If the same key exists with a different value, warn and exit without overwriting
if grep -qE "^(export )?${KEY}=" "${ENV_LOCAL}" 2>/dev/null; then
  existing_val=$(grep -E "^(export )?${KEY}=" "${ENV_LOCAL}" | tail -1)
  echo "[enable-1h-cache] Warning: an existing setting '${existing_val}' is present in ${ENV_LOCAL}." >&2
  echo "[enable-1h-cache] Please review it manually and re-run." >&2
  exit 1
fi

# Append to env.local (create the file if it does not exist)
{
  echo ""
  echo "# CC v2.1.108+ 1-hour prompt cache (recommended for sessions over 30 minutes)"
  echo "${ENTRY}"
} >> "${ENV_LOCAL}"

echo "[enable-1h-cache] Appended ${ENTRY} to ${ENV_LOCAL}."
echo "[enable-1h-cache] It takes effect from the next long session (over 30 minutes)."
