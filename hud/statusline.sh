#!/usr/bin/env bash
# chanpark-harness HUD — Claude Code statusLine renderer.
#
# Portable, self-contained (bash + jq; no Node build, unlike OMC's HUD).
# Reads the Claude Code status JSON on stdin and prints 1-2 status lines.
#
# Presets (passed as $1, default "focused"):
#   minimal  — one line: model · context% · tasks
#   focused  — two lines: model/mode/git  +  context-bar/cost/time/tasks
#   full     — focused plus repo name and a todo/wip/done task breakdown
#
# Wire it via the /chanpark-harness:hud skill, or manually in settings.json:
#   { "statusLine": { "type": "command",
#       "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hud/statusline.sh\" focused" } }

set -uo pipefail

PRESET="${1:-${CHANPARK_HUD_PRESET:-focused}}"
INPUT="$(cat)"

# --- Colors ---
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
DIM=$'\033[2m'; RESET=$'\033[0m'

# --- jq fallback: without jq, emit a minimal model-only line and exit cleanly ---
if ! command -v jq >/dev/null 2>&1; then
    MODEL="$(printf '%s' "$INPUT" | grep -o '"display_name":[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
    printf '%s[%s]%s %s(install jq for the full HUD)%s\n' "$CYAN" "${MODEL:-Claude}" "$RESET" "$DIM" "$RESET"
    exit 0
fi

_get() { printf '%s' "$INPUT" | jq -r "$1 // empty" 2>/dev/null; }

MODEL="$(_get '.model.display_name')";        MODEL="${MODEL:-?}"
PCT="$(_get '.context_window.used_percentage' | cut -d. -f1)"; PCT="${PCT:-0}"
COST="$(_get '.cost.total_cost_usd')";        COST="${COST:-0}"
DURATION_MS="$(_get '.cost.total_duration_ms')"; DURATION_MS="${DURATION_MS:-0}"
STYLE="$(_get '.output_style.name')"
AGENT_NAME="$(_get '.agent.name')"
WT_NAME="$(_get '.worktree.name')"
EFFORT_LEVEL="$(_get '.effort.level')"
THINK="$(printf '%s' "$INPUT" | jq -r 'if .thinking.enabled==true then "on" elif .thinking.enabled==false then "off" else "" end' 2>/dev/null)"

# --- Git (cached 5s to avoid spawning git on every keystroke) ---
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_NAME="$(basename "$REPO_ROOT" 2>/dev/null)"
CACHE_FILE="${CHANPARK_HUD_GIT_CACHE:-/tmp/chanpark-hud-git-cache}"
_cache_mtime() { stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0; }
if [ ! -f "$CACHE_FILE" ] || [ $(( $(date +%s) - $(_cache_mtime) )) -gt 5 ]; then
    if git rev-parse --git-dir >/dev/null 2>&1; then
        printf '%s|%s|%s\n' \
            "$(git branch --show-current 2>/dev/null)" \
            "$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')" \
            "$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')" > "$CACHE_FILE"
    else
        echo "||" > "$CACHE_FILE"
    fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED < "$CACHE_FILE"
STAGED="${STAGED:-0}"; MODIFIED="${MODIFIED:-0}"

# --- Plans.md task counts (harness plan-work-review state) ---
TODO=0; WIP=0; DONE=0; TOTAL=0
PLANS=""
for p in "$REPO_ROOT/Plans.md" "$PWD/Plans.md"; do [ -f "$p" ] && PLANS="$p" && break; done
if [ -n "$PLANS" ]; then
    _cnt() { grep -oiE "cc:$1" "$PLANS" 2>/dev/null | wc -l | tr -d ' '; }
    TODO="$(_cnt todo)"; WIP="$(_cnt wip)"; DONE="$(_cnt done)"
    TOTAL=$((TODO + WIP + DONE))
fi

# --- Context bar color by threshold ---
if [ "$PCT" -ge 90 ]; then BAR_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then BAR_COLOR="$YELLOW"
else BAR_COLOR="$GREEN"; fi
BAR_WIDTH=10
FILLED=$((PCT * BAR_WIDTH / 100)); [ "$FILLED" -gt "$BAR_WIDTH" ] && FILLED=$BAR_WIDTH
EMPTY=$((BAR_WIDTH - FILLED))
BAR=""
[ "$FILLED" -gt 0 ] && BAR=$(printf "%${FILLED}s" | tr ' ' '#')
[ "$EMPTY" -gt 0 ] && BAR="${BAR}$(printf "%${EMPTY}s" | tr ' ' '.')"

COST_FMT="$(printf '$%.2f' "$COST" 2>/dev/null || echo "\$$COST")"
MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

tasks_badge() {  # $1: style "short" | "full"
    [ "$TOTAL" -eq 0 ] && return 0
    if [ "$1" = "full" ]; then
        printf '%stasks%s todo:%s wip:%s done:%s/%s' "$DIM" "$RESET" "$TODO" "$WIP" "$DONE" "$TOTAL"
    else
        printf '%stasks%s %s/%s' "$DIM" "$RESET" "$DONE" "$TOTAL"
    fi
}

case "$PRESET" in
  minimal)
    LINE="${CYAN}[$MODEL]${RESET} ${BAR_COLOR}${PCT}%${RESET}"
    TB="$(tasks_badge short)"; [ -n "$TB" ] && LINE="${LINE} | ${TB}"
    printf '%b\n' "$LINE"
    ;;
  full|focused)
    # Line 1: model + mode flags + repo/branch + agent/worktree
    LINE1="${CYAN}[$MODEL]${RESET}"
    MODE=""
    [ -n "$EFFORT_LEVEL" ] && MODE="${MODE} effort:${EFFORT_LEVEL}"
    [ -n "$THINK" ] && MODE="${MODE} think:${THINK}"
    [ -n "$MODE" ] && LINE1="${LINE1} ${DIM}${MODE# }${RESET}"
    [ "$PRESET" = "full" ] && [ -n "$REPO_NAME" ] && LINE1="${LINE1} ${DIM}repo:${REPO_NAME}${RESET}"
    if [ -n "$BRANCH" ]; then
        GS=""
        [ "${STAGED:-0}" -gt 0 ] && GS="${GREEN}+${STAGED}${RESET}"
        [ "${MODIFIED:-0}" -gt 0 ] && GS="${GS}${YELLOW}~${MODIFIED}${RESET}"
        LINE1="${LINE1} ${CYAN}${BRANCH}${RESET} ${GS}"
    fi
    [ -n "$AGENT_NAME" ] && LINE1="${LINE1} ${DIM}agent:${AGENT_NAME}${RESET}"
    [ -n "$WT_NAME" ] && LINE1="${LINE1} ${DIM}wt:${WT_NAME}${RESET}"

    # Line 2: context bar + cost + time + tasks + style
    LINE2="${BAR_COLOR}${BAR}${RESET} ${PCT}% | ${YELLOW}${COST_FMT}${RESET} | ${MINS}m${SECS}s"
    if [ "$PRESET" = "full" ]; then TB="$(tasks_badge full)"; else TB="$(tasks_badge short)"; fi
    [ -n "$TB" ] && LINE2="${LINE2} | ${TB}"
    [ -n "$STYLE" ] && [ "$STYLE" != "default" ] && LINE2="${LINE2} ${DIM}[${STYLE}]${RESET}"

    printf '%b\n' "$LINE1"
    printf '%b\n' "$LINE2"
    ;;
  *)
    printf '%b\n' "${CYAN}[$MODEL]${RESET} ${DIM}(unknown HUD preset '$PRESET'; use minimal|focused|full)${RESET}"
    ;;
esac
