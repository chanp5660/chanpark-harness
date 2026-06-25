# chanpark-harness

A personal [Claude Code](https://claude.com/claude-code) plugin that merges two upstream
projects into one portable, English-localized harness:

- **[claude-code-harness](https://github.com/Chachamaru127/claude-code-harness)** — the
  base: a plan → work → review contract workflow driven by a pre-built Go binary and
  markdown skills (no build step).
- **[oh-my-claudecode](https://github.com/yeachan-heo/oh-my-claudecode)** — selected
  consult agents and gap-filling skills, ported as plain markdown.

When the two overlapped, **the harness side wins**; oh-my-claudecode only fills gaps the
harness does not cover. Everything ships as markdown + a committed Go binary, so the
plugin works straight from `git` with **no Node/Go build required**.

## What's inside

- **13 agents** — harness core (`worker`, `reviewer`, `advisor`) plus oh-my-claudecode
  consult agents (`architect`, `analyst`, `debugger`, `security-reviewer`,
  `document-specialist`, `test-engineer`, `explore`, `git-master`, `writer`, `qa-tester`).
- **30 skills** — the full harness `harness-*` workflow set (plan, work, review, sync,
  setup, progress, accept, release, loop, plan-brief), `breezing`, `ci`, `maintenance`,
  the `memory`/`session` stacks, guides, plus ported `ai-slop-cleaner`, `agent-browser`,
  `ui`, `deep-interview`, `trace`, `skill`, `skillify`, and a portable `hud` (among others).
- **Automation hooks** (`hooks/hooks.json`) — file-lease, secret scanning, a quality gate,
  a permission allowlist, and session memory wiring. They self-detect the plugin root and
  no-op gracefully if the binary is missing.
- **Pre-built Go binary** (`bin/`) for linux-amd64, darwin-amd64, darwin-arm64,
  windows-amd64. The `bin/harness` shim picks the right one and no-ops if none matches.
- **A portable HUD** status line (`hud/statusline.sh`, bash + jq — no Node build).

## Install

This repo is itself a single-plugin marketplace.

```text
# 1. Add this repo as a marketplace
/plugin marketplace add chanp5660/chanpark-harness

# 2. Install the plugin
/plugin install chanpark-harness@chanpark-harness-marketplace

# 3. Reload so the new skills/agents/hooks become active in this session
/reload-plugins

# 4. (optional) scaffold harness files into your project
/chanpark-harness:harness-setup
```

Skills are namespaced under the plugin, e.g. `/chanpark-harness:harness-plan`,
`/chanpark-harness:harness-work`, `/chanpark-harness:hud`.

> The HUD needs `jq` (and, on Windows, Git Bash). Ubuntu/macOS are one-liners;
> **Windows takes a few extra steps** — see the **[Install guide](docs/INSTALL.md)** for the
> per-platform `jq` setup and a Windows checklist.

### Update

Bump-and-pull: pull the latest commit (or bump the `version` in
`.claude-plugin/plugin.json` + `marketplace.json` and re-run `/plugin marketplace update`).
With `version` pinned, Claude Code only updates when the version changes.

## HUD (status line)

The HUD is a status line that lives at the bottom of Claude Code. Here's what the default
**focused** preset looks like (it merges onto one row when the terminal is wide enough):

```text
[Opus 4.8] master@c876efed +2~3 ^1 ?4
ctx:42% | 5h:18% (3h 12m) | 7d:55% (4d 6h) | +120/-30 | tasks 3/8 > add login ratelimit
```

Reading it left to right:

| Segment | Meaning |
|---------|---------|
| `[Opus 4.8]` | active model |
| `master@c876efed` | git branch @ short SHA |
| `+2~3 ^1 ?4` | 2 staged, 3 modified, 1 ahead of upstream, 4 untracked (`v`=behind, `*`=stash) |
| `ctx:42%` | context window used (green/yellow/red as it fills) |
| `5h:18%` / `7d:55%` | subscription rate limits + reset countdown (Claude.ai Pro/Max only) |
| `+120/-30` | lines added/removed this session |
| `tasks 3/8` | Plans.md: 3 of 8 done (a yellow `wip:N` is added only when more than one task is in progress at once) |
| `> add login ratelimit` | title of the active `cc:wip` task |

Set it up and switch presets with:

```text
/chanpark-harness:hud setup     # install + wire the status line (focused preset)
/chanpark-harness:hud minimal   # one line: model · context% · tasks
/chanpark-harness:hud focused   # default (shown above)
/chanpark-harness:hud full      # adds repo name + elapsed time + todo/wip/done breakdown
/chanpark-harness:hud status    # report current config
/chanpark-harness:hud off       # disable
```

Requires `jq`; without it the HUD falls back to a model-only line. See the
**[Install guide](docs/INSTALL.md)** for `jq` setup (especially on Windows).

## Workflow

The canonical loop is **plan → work → review → sync**, all tracked in one file at the project
root — **`Plans.md`** — where each task carries an English status marker (`cc:todo` →
`cc:wip` → `cc:done`, or `cc:blocked`).

```text
        ┌──────────────────────── feeds back ─────────────────────────┐
        v                                                              │
  harness-plan  ──>  harness-work  ──>  harness-review  ──>  harness-sync
  decide & write     execute tasks      multi-angle review     reconcile +
  Plans.md tasks     (solo→parallel→    before shipping        retrospective
                      team by count)
```

- **plan** — turn an idea into verifiable `Plans.md` tasks (with a DoD per task).
- **work** — implement them; mode auto-scales by count (1 → solo, 2–3 → parallel, 4+ → team).
- **review** — a separate, independent pass; critical/major findings block the merge.
- **sync** — reconcile markers with what actually shipped, then learn from it.

The ported oh-my-claudecode agents are read-only/consult helpers you delegate to for
architecture analysis, requirements clarification, debugging, security review, etc.

**→ See the [Usage guide](docs/USAGE.md) for every command, its subcommands/flags, and
worked examples** (including `harness-loop` for long/overnight runs and `maintenance` for
cleanup).

## Maintaining the plugin

- The harness Go binaries are committed (no build needed). To support a new platform
  (e.g. `linux-arm64`), rebuild from the upstream
  [claude-code-harness](https://github.com/Chachamaru127/claude-code-harness) `go/` source
  and drop the binary into `bin/`.
- All user-facing content (agents, skills, output styles, templates) is English. The
  internal `scripts/` directory still contains some Japanese comments inherited from
  upstream; these are internal helpers and not surfaced during normal use.
- `harness.toml` is the configuration source of truth read by the binary. Run
  `bin/harness doctor` and `bin/harness validate` to check health.

## Provenance

Derived from claude-code-harness (Chachamaru, MIT) and oh-my-claudecode (Yeachan Heo, MIT),
rebranded to `chanpark-harness`, localized to English, and modernized to the current Claude
Code plugin specification. See [LICENSE](LICENSE).
