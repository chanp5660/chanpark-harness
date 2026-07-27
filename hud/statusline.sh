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

# --- Single jq pass: extract all 14 fields at once (avoids 14 process spawns per render) ---
# Uses SOH (U+0001, --arg sep) as field separator: unlike tab, SOH is a non-whitespace
# IFS character so bash read preserves empty fields. Tab collapses consecutive separators
# and would swallow empty fields (e.g. worktree.name=""); SOH never appears in names/paths.
# Optional numeric rate-limit fields: "" when absent (field missing or null in JSON).
_jq_soh="$(printf '%s' "$INPUT" | jq -r --arg sep $'\001' '[
  (.model.display_name // ""),
  ((.context_window.used_percentage // 0) | floor | tostring),
  (if .rate_limits.five_hour.used_percentage != null then (.rate_limits.five_hour.used_percentage | floor | tostring) else "" end),
  (if .rate_limits.five_hour.resets_at != null then (.rate_limits.five_hour.resets_at | floor | tostring) else "" end),
  (if .rate_limits.seven_day.used_percentage != null then (.rate_limits.seven_day.used_percentage | floor | tostring) else "" end),
  (if .rate_limits.seven_day.resets_at != null then (.rate_limits.seven_day.resets_at | floor | tostring) else "" end),
  ((.cost.total_duration_ms // 0) | tostring),
  ((.cost.total_lines_added // 0) | tostring),
  ((.cost.total_lines_removed // 0) | tostring),
  (.output_style.name // ""),
  (.agent.name // ""),
  (.worktree.name // ""),
  (.workspace.current_dir // .cwd // ""),
  (.workspace.project_dir // "")
] | join($sep)' 2>/dev/null)"
# Subscription rate limits (Claude.ai Pro/Max only; present after the first API
# response — absent fields stay empty so the segments self-omit).
IFS=$'\001' read -r MODEL PCT FIVE_PCT FIVE_RESET SEVEN_PCT SEVEN_RESET DURATION_MS LINES_ADD LINES_DEL STYLE AGENT_NAME WT_NAME CUR_DIR PROJ_DIR <<< "$_jq_soh" || true
MODEL="${MODEL:-?}"; PCT="${PCT:-0}"
DURATION_MS="${DURATION_MS:-0}"; LINES_ADD="${LINES_ADD:-0}"; LINES_DEL="${LINES_DEL:-0}"

# --- Git (cached 5s to avoid spawning git on every keystroke) ---
# REPO_ROOT/REPO_NAME are computed inside the cache-miss block so git rev-parse
# --show-toplevel is NOT spawned on cache-hit renders. REPO_NAME is persisted in
# the cache file as the 9th field.
# Cache is namespaced per-user in a private directory (mode 0700) to prevent
# cross-user git-state leaks and symlink-clobbering attacks on shared hosts.
# CHANPARK_HUD_GIT_CACHE override is honoured only when the parent directory is
# owned by the current user; otherwise the default path is used with a stderr note.
_CHANPARK_HUD_CACHE_DIR="${XDG_RUNTIME_DIR:-/tmp}/chanpark-hud-$(id -u)"
mkdir -p "$_CHANPARK_HUD_CACHE_DIR" && chmod 700 "$_CHANPARK_HUD_CACHE_DIR" 2>/dev/null || true
_CHANPARK_HUD_CACHE_DEFAULT="${_CHANPARK_HUD_CACHE_DIR}/git-cache"
if [ -n "${CHANPARK_HUD_GIT_CACHE:-}" ]; then
    _override_parent="$(dirname "$CHANPARK_HUD_GIT_CACHE")"
    if [ -O "$_override_parent" ]; then
        CACHE_FILE="$CHANPARK_HUD_GIT_CACHE"
    else
        printf 'chanpark-hud: CHANPARK_HUD_GIT_CACHE parent dir not owned by current user; using default cache\n' >&2
        CACHE_FILE="$_CHANPARK_HUD_CACHE_DEFAULT"
    fi
else
    CACHE_FILE="$_CHANPARK_HUD_CACHE_DEFAULT"
fi
_cache_mtime() {
    local ts=""
    ts="$(stat -c %Y "$CACHE_FILE" 2>/dev/null || true)"
    if [ -n "$ts" ] && printf '%s' "$ts" | grep -Eq '^[0-9]+$'; then printf '%s' "$ts"; return 0; fi
    ts="$(stat -f %m "$CACHE_FILE" 2>/dev/null || true)"
    if [ -n "$ts" ] && printf '%s' "$ts" | grep -Eq '^[0-9]+$'; then printf '%s' "$ts"; return 0; fi
    printf '0'
}
if [ ! -f "$CACHE_FILE" ] || [ $(( $(date +%s) - $(_cache_mtime) )) -gt 5 ]; then
    # Atomic write: write to temp file in the same dir then mv, so a concurrent
    # reader never sees a partial cache file and mv defeats symlink-follow attacks.
    _cache_write() {
        local _tmp
        _tmp="$(mktemp "$(dirname "$CACHE_FILE")/git-cache.XXXXXX" 2>/dev/null)" || return 1
        printf '%s\n' "$1" > "$_tmp" && mv -f "$_tmp" "$CACHE_FILE" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    }
    export GIT_OPTIONAL_LOCKS=0
    _rn=""
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
        _rt="$(git rev-parse --show-toplevel 2>/dev/null)"; _rn="$(basename "$_rt" 2>/dev/null)"
        _cache_write "${_br}|${_staged}|${_mod}|${_ahead}|${_behind}|${_unt}|${_stash}|${_sha}|${_rn}" || true
    else
        _rn="$(basename "${PROJ_DIR:-$PWD}" 2>/dev/null)"
        _cache_write "||||||||${_rn}" || true
    fi
fi
IFS='|' read -r BRANCH STAGED MODIFIED AHEAD BEHIND UNTRACKED STASH SHA REPO_NAME < "$CACHE_FILE" || true
BRANCH="${BRANCH:-}"; SHA="${SHA:-}"; REPO_NAME="${REPO_NAME:-}"
STAGED="${STAGED:-0}"; MODIFIED="${MODIFIED:-0}"; AHEAD="${AHEAD:-0}"; BEHIND="${BEHIND:-0}"; UNTRACKED="${UNTRACKED:-0}"; STASH="${STASH:-0}"

# --- Plans.md task counts (A2: count only markdown status-column cells, not prose/legend) ---
# The counting rule lives in scripts/lib/plans-markers.awk so the HUD, the plans-watcher
# hook and the CI guard cannot drift apart. The former inline rule ("marker immediately
# after a pipe") also matched a legend row whose FIRST cell is the marker; the canonical
# rule looks at the status cell (last non-empty) only. The grep fallback below keeps the
# HUD self-contained when the statusline is copied out of the plugin tree.
TODO=0; WIP=0; DONE=0; TOTAL=0; WIP_TITLE=""
PLANS=""
for p in "${PROJ_DIR:+$PROJ_DIR/Plans.md}" "$PWD/Plans.md"; do [ -f "$p" ] && PLANS="$p" && break; done
if [ -n "$PLANS" ]; then
    _hud_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    _counter="$_hud_dir/../scripts/lib/plans-markers.awk"
    if [ -r "$_counter" ]; then
        read -r TODO WIP DONE _ _ _ <<< "$(awk -f "$_counter" "$PLANS" 2>/dev/null)"
    else
        _cell() { grep -oiE "\|[[:space:]]*cc:$1\b" "$PLANS" 2>/dev/null | wc -l | tr -d ' '; }
        TODO="$(_cell todo)"; WIP="$(_cell wip)"; DONE="$(_cell done)"
    fi
    TODO="${TODO:-0}"; WIP="${WIP:-0}"; DONE="${DONE:-0}"
    TOTAL=$((TODO + WIP + DONE))
    # A1: active WIP task title (2nd data column of the first cc:wip row)
    if [ "$WIP" -gt 0 ]; then
        WIP_TITLE="$(awk '
            { t=$0; sub(/^[[:space:]]+/,"",t)
              if (substr(t,1,3)=="```") { f=!f; next }
              if (f || substr(t,1,4)=="<!--" || $0 !~ /^[[:space:]]*\|/) next
              n=split($0, c, "|"); s=""
              for (i=n; i>=1; i--) { v=c[i]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
                                     if (v!="") { gsub(/`[^`]*`/,"",v); s=tolower(v); break } }
              sub(/^cursor:/,"cc:",s)
              if (s ~ /^cc:wip/) { t=c[3]; gsub(/^[ \t]+|[ \t]+$/,"",t); print t; exit } }
        ' "$PLANS" 2>/dev/null)"
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
    printf '%s\n' "$LINE"
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
        printf '%s\n' "${LINE1} ${DIM}|${RESET} ${FULL2}"
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
        printf '%s\n' "$LINE1"
        printf '%s\n' "$LINE2"
    fi
    ;;
  *)
    printf '%s\n' "${CYAN}[$MODEL]${RESET} ${DIM}(unknown HUD preset '$PRESET'; use minimal|focused|full)${RESET}"
    ;;
esac
