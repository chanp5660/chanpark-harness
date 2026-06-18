---
name: hud
description: "Configure the chanpark-harness HUD status line (model, context %, cost, git, Plans.md task counts). Triggers: hud, hud setup, hud minimal, hud focused, hud full, hud status, statusline, status line."
argument-hint: "[setup|minimal|focused|full|status|off]"
disable-model-invocation: true
allowed-tools: ["Read", "Edit", "Write", "Bash"]
---

# HUD — chanpark-harness status line

Configures Claude Code's `statusLine` to render the chanpark-harness HUD: model, mode
(effort/thinking), git branch + diff counts + ahead/behind/untracked/stash, context-window
bar, session cost, lines changed this session (`+added/-removed`), elapsed time, and
Plans.md task counts (`cc:todo`/`cc:wip`/`cc:done`, counted from table status cells) plus
the active WIP task title.

The renderer is a self-contained `bash` + `jq` script (`hud/statusline.sh`) — **no Node
build required** (unlike upstream OMC's HUD). If `jq` is missing it degrades to a
minimal model-only line instead of breaking the status line.

| Command | Action |
|---------|--------|
| `/hud` or `/hud status` | Report current HUD/statusLine configuration |
| `/hud setup` | Install the HUD renderer and wire `statusLine` (preset: focused) |
| `/hud minimal` | One-line HUD: model · context% · tasks |
| `/hud focused` | Two-line HUD (default): model/mode/git + bar/cost/time/tasks |
| `/hud full` | Two-line HUD plus repo name and todo/wip/done breakdown |
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
minimal:  [Opus 4.8] 67% | tasks 1/4
focused:  [Opus 4.8] effort:high think:on  main +2~1 ^1 ?3
          ######....  67% | $1.23 | +120/-30 | 3m5s | tasks 1/4 > implement login flow
full:     [Opus 4.8] effort:high think:on repo:myproject  main +2~1 ^1 ?3
          ######....  67% | $1.23 | +120/-30 | 3m5s | tasks todo:2 wip:1 done:1/4 > implement login flow
```

Line-1 git: `+staged ~modified` files, then `^ahead v behind ?untracked *stash` (only nonzero).
Line-2: context bar + `%`, session `$cost`, `+lines/-lines` this session, elapsed, task
counts, and `> <active WIP task title>` from Plans.md (truncated). `agent:`/`wt:` appear on
line 1 only inside a subagent / git worktree.
