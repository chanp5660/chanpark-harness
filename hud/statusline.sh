#!/usr/bin/env bash
# chanpark-harness HUD — Claude Code statusLine renderer.
#
# Portable, self-contained (bash + jq; no Node build, unlike OMC's HUD).
# Reads the Claude Code status JSON on stdin and prints 1-2 status lines.
#
# Presets (passed as $1, default "focused"):
#   minimal  — one line: model · context% · tasks
#   focused  — two lines: model/mode/git  +  context-bar/cost/lines/time/tasks(+WIP)
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

# truncate $1 to $2 chars, appending "..." when cut (D10: keep the line from overflowing)
_trunc() { local s="$1" n="$2"; if [ "${#s}" -gt "$n" ]; then printf '%s...' "${s:0:$((n-3))}"; else printf '%s' "$s"; fi; }

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
LINES_ADD="$(_get '.cost.total_lines_added')";   LINES_ADD="${LINES_ADD:-0}"
LINES_DEL="$(_get '.cost.total_lines_removed')"; LINES_DEL="${LINES_DEL:-0}"
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
        _br="$(git branch --show-current 2>/dev/null)"
        _staged="$(git diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')"
        _mod="$(git diff --numstat 2>/dev/null | wc -l | tr -d ' ')"
        _unt="$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"
        _stash="$(git stash list 2>/dev/null | wc -l | tr -d ' ')"
        _ahead=0; _behind=0
        if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
            _ab="$(git rev-list --left-right --count '@{u}...HEAD' 2>/dev/null)"   # "<behind>\t<ahead>"
            _behind="$(printf '%s' "$_ab" | awk '{print $1+0}')"
            _ahead="$(printf '%s' "$_ab" | awk '{print $2+0}')"
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$_br" "$_staged" "$_mod" "$_ahead" "$_behind" "$_unt" "$_stash" > "$CACHE_FILE"
    else
        echo "||||||" > "$CACHE_FILE"
    fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED AHEAD BEHIND UNTRACKED STASH < "$CACHE_FILE"
STAGED="${STAGED:-0}"; MODIFIED="${MODIFIED:-0}"; AHEAD="${AHEAD:-0}"; BEHIND="${BEHIND:-0}"; UNTRACKED="${UNTRACKED:-0}"; STASH="${STASH:-0}"

# --- Plans.md task counts (A2: count only markdown status-column cells, not prose/legend) ---
TODO=0; WIP=0; DONE=0; TOTAL=0; WIP_TITLE=""
PLANS=""
for p in "$REPO_ROOT/Plans.md" "$PWD/Plans.md"; do [ -f "$p" ] && PLANS="$p" && break; done
if [ -n "$PLANS" ]; then
    _cell() { grep -oiE "\|[[:space:]]*cc:$1\b" "$PLANS" 2>/dev/null | wc -l | tr -d ' '; }
    TODO="$(_cell todo)"; WIP="$(_cell wip)"; DONE="$(_cell done)"
    TOTAL=$((TODO + WIP + DONE))
    # A1: active WIP task title (2nd data column of the first cc:wip row)
    if [ "$WIP" -gt 0 ]; then
        _row="$(grep -iE "\|[[:space:]]*cc:wip\b" "$PLANS" 2>/dev/null | head -1)"
        WIP_TITLE="$(printf '%s' "$_row" | awk -F'|' '{t=$3; gsub(/^[ \t]+|[ \t]+$/,"",t); print t}')"
        WIP_TITLE="$(_trunc "$WIP_TITLE" 30)"
    fi
fi

# --- Context usage % color by threshold (no bar; just the number) ---
if [ "$PCT" -ge 90 ]; then CTX_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then CTX_COLOR="$YELLOW"
else CTX_COLOR="$GREEN"; fi

COST_FMT="$(printf '$%.2f' "$COST" 2>/dev/null || echo "\$$COST")"
MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

# B3: lines changed this session (only when nonzero)
lines_badge() {
    [ "${LINES_ADD:-0}" = "0" ] && [ "${LINES_DEL:-0}" = "0" ] && return 0
    printf '%s+%s%s/%s-%s%s' "$GREEN" "$LINES_ADD" "$RESET" "$RED" "$LINES_DEL" "$RESET"
}

# B4: git ahead/behind/untracked/stash (only nonzero parts)
git_extra() {
    local out=""
    [ "${AHEAD:-0}" -gt 0 ] 2>/dev/null && out="${out} ${GREEN}^${AHEAD}${RESET}"
    [ "${BEHIND:-0}" -gt 0 ] 2>/dev/null && out="${out} ${RED}v${BEHIND}${RESET}"
    [ "${UNTRACKED:-0}" -gt 0 ] 2>/dev/null && out="${out} ${DIM}?${UNTRACKED}${RESET}"
    [ "${STASH:-0}" -gt 0 ] 2>/dev/null && out="${out} ${DIM}*${STASH}${RESET}"
    printf '%s' "$out"
}

tasks_badge() {  # $1: "short" | "full" (counts only; WIP title appended by caller)
    [ "$TOTAL" -eq 0 ] && return 0
    if [ "$1" = "full" ]; then
        printf '%stasks%s todo:%s wip:%s done:%s/%s' "$DIM" "$RESET" "$TODO" "$WIP" "$DONE" "$TOTAL"
    else
        printf '%stasks%s %s/%s' "$DIM" "$RESET" "$DONE" "$TOTAL"
    fi
}
wip_badge() { [ -n "$WIP_TITLE" ] && printf ' %s>%s %s' "$CYAN" "$RESET" "$WIP_TITLE"; }

case "$PRESET" in
  minimal)
    LINE="${CYAN}[$MODEL]${RESET} ctx:${CTX_COLOR}${PCT}%${RESET}"
    TB="$(tasks_badge short)"; [ -n "$TB" ] && LINE="${LINE} | ${TB}"
    printf '%b\n' "$LINE"
    ;;
  full|focused)
    # Line 1: model + mode flags + repo/branch + git-extra + agent/worktree
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
        LINE1="${LINE1} ${CYAN}$(_trunc "$BRANCH" 30)${RESET} ${GS}$(git_extra)"
    fi
    [ -n "$AGENT_NAME" ] && LINE1="${LINE1} ${DIM}agent:${AGENT_NAME}${RESET}"
    [ -n "$WT_NAME" ] && LINE1="${LINE1} ${DIM}wt:${WT_NAME}${RESET}"

    # Line 2: context bar + cost + lines + time + tasks(+WIP) + style
    LINE2="ctx:${CTX_COLOR}${PCT}%${RESET} | ${YELLOW}${COST_FMT}${RESET}"
    LB="$(lines_badge)"; [ -n "$LB" ] && LINE2="${LINE2} | ${LB}"
    LINE2="${LINE2} | ${MINS}m${SECS}s"
    if [ "$PRESET" = "full" ]; then TB="$(tasks_badge full)"; else TB="$(tasks_badge short)"; fi
    [ -n "$TB" ] && LINE2="${LINE2} | ${TB}$(wip_badge)"
    [ -n "$STYLE" ] && [ "$STYLE" != "default" ] && LINE2="${LINE2} ${DIM}[${STYLE}]${RESET}"

    printf '%b\n' "$LINE1"
    printf '%b\n' "$LINE2"
    ;;
  *)
    printf '%b\n' "${CYAN}[$MODEL]${RESET} ${DIM}(unknown HUD preset '$PRESET'; use minimal|focused|full)${RESET}"
    ;;
esac
