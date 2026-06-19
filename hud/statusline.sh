#!/usr/bin/env bash
# chanpark-harness HUD — Claude Code statusLine renderer.
#
# Portable, self-contained (bash + jq; no Node build, unlike OMC's HUD).
# Reads the Claude Code status JSON on stdin and prints 1-2 status lines.
#
# Presets (passed as $1, default "focused"):
#   minimal  — one line: model · context% · tasks
#   focused  — two lines: model/git/cwd  +  ctx%/5h/7d limits/lines/tasks(+WIP)
#   full     — focused plus repo name, elapsed time, and a todo/wip/done task breakdown
#
# Wire it via the /chanpark-harness:hud skill, or manually in settings.json:
#   { "statusLine": { "type": "command",
#       "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hud/statusline.sh\" focused" } }

set -uo pipefail

PRESET="${1:-${CHANPARK_HUD_PRESET:-focused}}"
INPUT="$(cat)"

# --- Colors ---
CYAN=$'\033[36m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'
MAGENTA=$'\033[35m'; DIM=$'\033[2m'; RESET=$'\033[0m'
# Color grammar: warm threshold colors (green/yellow/red) signal attention/danger
# (usage %, behind-upstream) ONLY; DIM is reference metadata; CYAN is identity.

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
# Subscription rate limits (Claude.ai Pro/Max only; present after the first API
# response — absent fields stay empty so the segments self-omit).
FIVE_PCT="$(_get '.rate_limits.five_hour.used_percentage' | cut -d. -f1)"
FIVE_RESET="$(_get '.rate_limits.five_hour.resets_at' | cut -d. -f1)"
SEVEN_PCT="$(_get '.rate_limits.seven_day.used_percentage' | cut -d. -f1)"
SEVEN_RESET="$(_get '.rate_limits.seven_day.resets_at' | cut -d. -f1)"
DURATION_MS="$(_get '.cost.total_duration_ms')"; DURATION_MS="${DURATION_MS:-0}"
LINES_ADD="$(_get '.cost.total_lines_added')";   LINES_ADD="${LINES_ADD:-0}"
LINES_DEL="$(_get '.cost.total_lines_removed')"; LINES_DEL="${LINES_DEL:-0}"
STYLE="$(_get '.output_style.name')"
AGENT_NAME="$(_get '.agent.name')"
WT_NAME="$(_get '.worktree.name')"
CUR_DIR="$(_get '.workspace.current_dir')"; [ -z "$CUR_DIR" ] && CUR_DIR="$(_get '.cwd')"
PROJ_DIR="$(_get '.workspace.project_dir')"

# --- Git (cached 5s to avoid spawning git on every keystroke) ---
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
REPO_NAME="$(basename "$REPO_ROOT" 2>/dev/null)"
CACHE_FILE="${CHANPARK_HUD_GIT_CACHE:-/tmp/chanpark-hud-git-cache}"
_cache_mtime() { stat -c %Y "$CACHE_FILE" 2>/dev/null || stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0; }
if [ ! -f "$CACHE_FILE" ] || [ $(( $(date +%s) - $(_cache_mtime) )) -gt 5 ]; then
    if git rev-parse --git-dir >/dev/null 2>&1; then
        _br="$(git branch --show-current 2>/dev/null)"
        _sha="$(git rev-parse --short HEAD 2>/dev/null)"
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
        printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$_br" "$_staged" "$_mod" "$_ahead" "$_behind" "$_unt" "$_stash" "$_sha" > "$CACHE_FILE"
    else
        echo "|||||||" > "$CACHE_FILE"
    fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED AHEAD BEHIND UNTRACKED STASH SHA < "$CACHE_FILE"
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

# --- Usage % → threshold color (shared by ctx and the rate-limit segments) ---
_pct_color() { local p="${1:-0}"
    if [ "$p" -ge 90 ] 2>/dev/null; then printf '%s' "$RED"
    elif [ "$p" -ge 70 ] 2>/dev/null; then printf '%s' "$YELLOW"
    else printf '%s' "$GREEN"; fi; }
CTX_COLOR="$(_pct_color "$PCT")"

# --- Reset countdown: epoch-seconds $1 → "Xd Yh" / "Xh Ym" / "Xm" (else "now") ---
_fmt_reset() {
    local target="$1" now diff d h m
    [ -z "$target" ] && return 0
    now="$(date +%s)"; diff=$((target - now))
    [ "$diff" -le 0 ] && { printf 'now'; return 0; }
    d=$((diff / 86400)); h=$(((diff % 86400) / 3600)); m=$(((diff % 3600) / 60))
    if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
    else printf '%dm' "$m"; fi; }

MINS=$((DURATION_MS / 60000)); SECS=$(((DURATION_MS % 60000) / 1000))

# B3: lines changed this session (only when nonzero)
lines_badge() {
    [ "${LINES_ADD:-0}" = "0" ] && [ "${LINES_DEL:-0}" = "0" ] && return 0
    printf '%s+%s%s/%s-%s%s' "$GREEN" "$LINES_ADD" "$RESET" "$RED" "$LINES_DEL" "$RESET"
}

# B4: git ahead/behind/untracked/stash (only nonzero parts).
# Color grammar: only `behind` is a warm warning (red, actionable — you're stale);
# ahead/untracked/stash are reference metadata → dim.
git_extra() {
    local out=""
    [ "${AHEAD:-0}" -gt 0 ] 2>/dev/null && out="${out} ${DIM}^${AHEAD}${RESET}"
    [ "${BEHIND:-0}" -gt 0 ] 2>/dev/null && out="${out} ${RED}v${BEHIND}${RESET}"
    [ "${UNTRACKED:-0}" -gt 0 ] 2>/dev/null && out="${out} ${DIM}?${UNTRACKED}${RESET}"
    [ "${STASH:-0}" -gt 0 ] 2>/dev/null && out="${out} ${DIM}*${STASH}${RESET}"
    printf '%s' "$out"
}

tasks_badge() {  # $1: "short" | "full" (counts only; WIP title appended by caller)
    [ "$TOTAL" -eq 0 ] && return 0
    # WIP>1 is a smell in a serialized plan->work->review loop → warn in yellow
    local wipc="$WIP"; local many=0
    [ "${WIP:-0}" -gt 1 ] 2>/dev/null && { wipc="${YELLOW}${WIP}${RESET}"; many=1; }
    if [ "$1" = "full" ]; then
        printf '%stasks%s todo:%s wip:%s done:%s/%s' "$DIM" "$RESET" "$TODO" "$wipc" "$DONE" "$TOTAL"
    elif [ "$many" -eq 1 ]; then
        printf '%stasks%s wip:%s %s/%s' "$DIM" "$RESET" "$wipc" "$DONE" "$TOTAL"
    else
        printf '%stasks%s %s/%s' "$DIM" "$RESET" "$DONE" "$TOTAL"
    fi
}
wip_badge() { [ -n "$WIP_TITLE" ] && printf ' %s>%s %s' "$CYAN" "$RESET" "$WIP_TITLE"; }

# Subscription rate-limit segment: "<label>:NN% (reset)". Omitted entirely when the
# percentage is absent (non-subscriber, or before the session's first API response).
rate_badge() {  # $1 label, $2 pct, $3 resets_at(epoch)
    [ -z "$2" ] && return 0
    local c reset; c="$(_pct_color "$2")"; reset="$(_fmt_reset "$3")"
    if [ -n "$reset" ]; then printf '%s:%s%s%%%s (%s)' "$1" "$c" "$2" "$RESET" "$reset"
    else printf '%s:%s%s%%%s' "$1" "$c" "$2" "$RESET"; fi
}
limits_badge() {  # both windows, separated by " | "; whichever is present
    local five seven out
    five="$(rate_badge 5h "$FIVE_PCT" "$FIVE_RESET")"
    seven="$(rate_badge 7d "$SEVEN_PCT" "$SEVEN_RESET")"
    out="$five"
    [ -n "$seven" ] && { [ -n "$out" ] && out="${out} | ${seven}" || out="$seven"; }
    printf '%s' "$out"
}

# Current working subdir, dimmed: project_dir-relative, $HOME→~. Omitted at project root.
cwd_badge() {
    [ -z "$CUR_DIR" ] && return 0
    local p="$CUR_DIR"
    if [ -n "$PROJ_DIR" ] && [ "$CUR_DIR" = "$PROJ_DIR" ]; then return 0; fi
    if [ -n "$PROJ_DIR" ] && [ "${CUR_DIR#"$PROJ_DIR"/}" != "$CUR_DIR" ]; then
        p="${CUR_DIR#"$PROJ_DIR"/}"
    else
        p="${CUR_DIR/#$HOME/\~}"
    fi
    printf '%s%s%s' "$DIM" "$p" "$RESET"
}

# --- Width-aware line-2 shedding ---
# Claude Code sets $COLUMNS for the statusLine subprocess (v2.1.153+); `tput cols`
# cannot read it from a captured pipe. Over-width lines get hard-truncated, so we'd
# rather shed our own low-priority segments than let the right edge be cut blindly.
# When $COLUMNS is absent (older CC / outside CC), CAP=0 disables shedding (no-op).
_vwidth() { local t; t="$(printf '%s' "$1" | sed $'s/\033\\[[0-9;]*m//g')"; printf '%s' "${#t}"; }
_term_cols() { case "${COLUMNS:-}" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$COLUMNS";; esac; }

case "$PRESET" in
  minimal)
    LINE="${CYAN}[$MODEL]${RESET} ctx:${CTX_COLOR}${PCT}%${RESET}"
    TB="$(tasks_badge short)"; [ -n "$TB" ] && LINE="${LINE} | ${TB}"
    printf '%b\n' "$LINE"
    ;;
  full|focused)
    # Line 1: model + repo/branch@sha + git-extra + agent/worktree + cwd
    LINE1="${CYAN}[$MODEL]${RESET}"
    [ "$PRESET" = "full" ] && [ -n "$REPO_NAME" ] && LINE1="${LINE1} ${DIM}repo:${REPO_NAME}${RESET}"
    if [ -n "$BRANCH" ]; then
        # diff counts are reference metadata → dim (warm colors reserved for warnings)
        GS=""
        [ "${STAGED:-0}" -gt 0 ] && GS="${DIM}+${STAGED}${RESET}"
        [ "${MODIFIED:-0}" -gt 0 ] && GS="${GS}${DIM}~${MODIFIED}${RESET}"
        BR="${CYAN}$(_trunc "$BRANCH" 30)${RESET}"
        [ -n "$SHA" ] && BR="${BR}${DIM}@${SHA}${RESET}"
        LINE1="${LINE1} ${BR} ${GS}$(git_extra)"
    fi
    [ -n "$AGENT_NAME" ] && LINE1="${LINE1} ${DIM}agent:${AGENT_NAME}${RESET}"
    # worktree tinted (not dim) so you never forget you're in a worktree
    [ -n "$WT_NAME" ] && LINE1="${LINE1} ${MAGENTA}wt:${WT_NAME}${RESET}"
    CWD="$(cwd_badge)"; [ -n "$CWD" ] && LINE1="${LINE1} ${CWD}"

    # Line 2: ctx% + subscription limits(5h/7d) + lines + time + tasks(+WIP) + style.
    # ctx/limits are the always-kept core; remaining segments are shed (lowest priority
    # first: time -> style -> lines -> WIP-title -> tasks) to fit $COLUMNS. Elapsed time
    # is full-only — it changes no decision, so focused omits it regardless of width.
    CORE="ctx:${CTX_COLOR}${PCT}%${RESET}"
    RL="$(limits_badge)"; [ -n "$RL" ] && CORE="${CORE} | ${RL}"
    LB="$(lines_badge)"
    TM=""; [ "$PRESET" = "full" ] && TM="${MINS}m${SECS}s"
    if [ "$PRESET" = "full" ]; then TB="$(tasks_badge full)"; else TB="$(tasks_badge short)"; fi
    WB="$(wip_badge)"
    SB=""; [ -n "$STYLE" ] && [ "$STYLE" != "default" ] && SB="${DIM}[${STYLE}]${RESET}"

    # $1..$5: include lines / time / tasks / wip / style (1=yes,0=no). Visual order fixed.
    _line2() {
        local s="$CORE"
        [ "$1" = 1 ] && [ -n "$LB" ] && s="${s} | ${LB}"
        [ "$2" = 1 ] && [ -n "$TM" ] && s="${s} | ${TM}"
        if [ "$3" = 1 ] && [ -n "$TB" ]; then s="${s} | ${TB}"; [ "$4" = 1 ] && s="${s}${WB}"; fi
        [ "$5" = 1 ] && [ -n "$SB" ] && s="${s} ${SB}"
        printf '%s' "$s"
    }
    FULL2="$(_line2 1 1 1 1 1)"
    CAP="$(_term_cols)"

    # Single-line mode: when the terminal is wide enough to hold line 1 + line 2 on one
    # row, merge them (saves a vertical row). Falls back to two rows otherwise. Opt out
    # with CHANPARK_HUD_ONELINE=0. Needs $COLUMNS (CC v2.1.153+); unknown width → two rows.
    if [ "${CHANPARK_HUD_ONELINE:-1}" != "0" ] && [ "$CAP" -gt 0 ] 2>/dev/null \
       && [ $(( $(_vwidth "$LINE1") + 3 + $(_vwidth "$FULL2") )) -le "$CAP" ]; then
        printf '%b\n' "${LINE1} ${DIM}|${RESET} ${FULL2}"
    else
        # Two rows: shed line-2 segments to fit $COLUMNS (lowest priority first:
        # time -> style -> lines -> WIP-title -> tasks; ctx/limits always kept).
        LINE2="$FULL2"
        if [ "$CAP" -gt 0 ] 2>/dev/null; then
            for f in "1 1 1 1 1" "1 0 1 1 1" "1 0 1 1 0" "0 0 1 1 0" "0 0 1 0 0" "0 0 0 0 0"; do
                LINE2="$(_line2 $f)"
                [ "$(_vwidth "$LINE2")" -le "$CAP" ] && break
            done
        fi
        printf '%b\n' "$LINE1"
        printf '%b\n' "$LINE2"
    fi
    ;;
  *)
    printf '%b\n' "${CYAN}[$MODEL]${RESET} ${DIM}(unknown HUD preset '$PRESET'; use minimal|focused|full)${RESET}"
    ;;
esac
