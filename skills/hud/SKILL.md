---
name: hud
description: "Configure the chanpark-harness HUD status line (model, context %, subscription rate limits, git, Plans.md task counts). Triggers: hud, hud setup, hud minimal, hud focused, hud full, hud status, statusline, status line."
argument-hint: "[setup|minimal|focused|full|status|off]"
disable-model-invocation: true
allowed-tools: ["Read", "Edit", "Write", "Bash"]
---

# HUD — chanpark-harness status line

Configures Claude Code's `statusLine` to render the chanpark-harness HUD: model, git
branch + diff counts + ahead/behind/untracked/stash, working subdir, context usage
(`ctx:%`), subscription rate limits (`5h:%`/`7d:%` with reset countdown), lines changed
this session (`+added/-removed`), elapsed time (full preset), and Plans.md task counts
(`cc:todo`/`cc:wip`/`cc:done`, counted from table status cells) plus the active WIP task
title.

The subscription rate-limit segments come straight from Claude Code's statusLine JSON
(`.rate_limits.five_hour`/`.seven_day`) and only appear for Claude.ai (Pro/Max)
subscribers after the session's first API response — they self-omit otherwise.

The renderer is a self-contained `bash` + `jq` script (`hud/statusline.sh`) — **no Node
build required** (unlike upstream OMC's HUD). If `jq` is missing it degrades to a
minimal model-only line instead of breaking the status line.

| Command | Action |
|---------|--------|
| `/hud` or `/hud status` | Report current HUD/statusLine configuration |
| `/hud setup` | Install the HUD renderer and wire `statusLine` (preset: focused) |
| `/hud minimal` | One-line HUD: model · context% · tasks |
| `/hud focused` | Two-line HUD (default): model/git/cwd + ctx%/5h/7d limits/lines/tasks |
| `/hud full` | Two-line HUD plus repo name, elapsed time, and todo/wip/done breakdown |
| `/hud off` | Remove the `statusLine` field (disable the HUD) |

All `~/.claude/...` paths honor `CLAUDE_CONFIG_DIR` when that variable is set.

## Why copy the script out of the plugin

`${CLAUDE_PLUGIN_ROOT}` is reliably set while THIS skill runs, but not necessarily when
Claude Code later renders the status line. So setup copies the renderer to a stable
absolute path under the config dir and points `statusLine` there. This also survives
plugin cache version bumps.

## Setup / preset change (run these steps)

Treat any argument other than `status`/`off` as "ensure installed, then set preset".
Default preset when the argument is `setup` or empty-after-install is `focused`.

**Step 1 — resolve paths and install the renderer** (run in Bash):
```bash
CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
HUD_DIR="$CONFIG_DIR/chanpark-hud"
mkdir -p "$HUD_DIR"
cp "${CLAUDE_PLUGIN_ROOT}/hud/statusline.sh" "$HUD_DIR/statusline.sh"
chmod +x "$HUD_DIR/statusline.sh"
echo "installed: $HUD_DIR/statusline.sh"
```

**Step 2 — set `statusLine` in settings.json.** Read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`
and add/update the `statusLine` field, preserving every other setting. Use `$HOME` (never `~`)
and forward slashes so the path works when Claude Code runs the command via bash.

Choose `<preset>` from the argument (`minimal` | `focused` | `full`; default `focused`):
```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"$HOME/.claude/chanpark-hud/statusline.sh\" <preset>"
  }
}
```
If `CLAUDE_CONFIG_DIR` is set to a non-default location, substitute that absolute path
instead of `$HOME/.claude`.

Use the Edit tool when `settings.json` exists (to preserve other keys); use Write only if
it does not exist yet (then seed it with `{ "statusLine": { ... } }`).

**Step 3 — tell the user to restart Claude Code** (or run `/statusline` reload) for the
change to take effect.

## `/hud status`

Read `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json` and report:
- whether `statusLine.command` points at `chanpark-hud/statusline.sh`,
- the active preset (the trailing argument of the command), and
- whether `$HOME/.claude/chanpark-hud/statusline.sh` exists and is executable.
Also note whether `jq` is installed (`command -v jq`); without it the HUD shows only the model.

## `/hud off`

Remove the `statusLine` key from `settings.json` with the Edit tool (leave the rest intact)
and tell the user to restart Claude Code.

## Preview

```
minimal:  [Opus 4.8] ctx:67% | tasks 1/4
focused:  [Opus 4.8]  main@a1b2c3d +2~1 v1 ?3  pkg/api
          ctx:67% | 5h:38% (2h 13m) | 7d:40% (4d 17h) | +120/-30 | tasks 1/4 > implement login flow
full:     [Opus 4.8] repo:myproject  main@a1b2c3d +2~1 v1 ?3  pkg/api
          ctx:67% | 5h:38% (2h 13m) | 7d:40% (4d 17h) | +120/-30 | 3m5s | tasks todo:2 wip:1 done:1/4 > implement login flow
```

Line-1: model, (repo in `full`), git branch`@shortSHA`, then `+staged ~modified` and
`^ahead vbehind ?untracked *stash` (only nonzero), then the working subdir (project-relative,
omitted at project root). `agent:` and a tinted `wt:` appear here only inside a subagent / git
worktree.
Line-2: context usage `ctx:%`, subscription limits `5h:%`/`7d:%` with reset countdown (omitted for
non-subscribers / before the first API response), `+lines/-lines` this session, elapsed time
(`full` only), task counts (the `wip:` count turns yellow when more than one task is in flight),
and `> <active WIP task title>` from Plans.md (truncated).

**Color grammar**: warm colors mean *attention* only — usage percentages (ctx/5h/7d) by threshold
(green `<70`, yellow `≥70`, red `≥90`), `vbehind` (red), and `wip>1` (yellow). Everything else is
dim reference metadata; cyan is identity (model, branch).

**Width** (needs `$COLUMNS`, exported by Claude Code v2.1.153+):
- **Single-line mode**: when the terminal is wide enough to hold line 1 + line 2 on one row,
  they are merged into a single row (saves a vertical line). Narrower terminals fall back to two
  rows. Set `CHANPARK_HUD_ONELINE=0` to always keep two rows. Unknown width → two rows.
- **Shedding** (two-row mode): line 2 drops its lowest-priority segments (time → output-style →
  lines → WIP title → tasks) to fit the terminal instead of being hard-truncated. `ctx`/`5h`/`7d`
  are always kept.
