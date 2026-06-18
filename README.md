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
  setup, progress, accept, release, loop), `breezing`, `ci`, `maintenance`,
  the `memory`/`session` stacks, guides, plus ported `ai-slop-cleaner`, `deep-interview`,
  `trace`, `skill`, `skillify`, and a portable `hud`.
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

# 3. (optional) scaffold harness files into your project
/chanpark-harness:harness-setup
```

Skills are namespaced under the plugin, e.g. `/chanpark-harness:harness-plan`,
`/chanpark-harness:harness-work`, `/chanpark-harness:hud`.

### Update

Bump-and-pull: pull the latest commit (or bump the `version` in
`.claude-plugin/plugin.json` + `marketplace.json` and re-run `/plugin marketplace update`).
With `version` pinned, Claude Code only updates when the version changes.

## HUD (status line)

```text
/chanpark-harness:hud setup     # install + wire the status line (focused preset)
/chanpark-harness:hud minimal   # one line: model · context% · tasks
/chanpark-harness:hud full      # adds repo name + todo/wip/done breakdown
/chanpark-harness:hud status    # report current config
/chanpark-harness:hud off       # disable
```

Shows model, effort/thinking, git branch + diff counts, a context-window bar, session
cost, elapsed time, and Plans.md task counts. Requires `jq`; without it, it falls back to a
model-only line.

## Workflow

The canonical loop is the harness **plan → work → review** cycle:

```text
/chanpark-harness:harness-plan      # write Plans.md tasks + a spec contract
/chanpark-harness:harness-work      # execute tasks (solo or parallel)
/chanpark-harness:harness-review    # multi-angle review before shipping
/chanpark-harness:harness-sync      # reconcile Plans.md with the implementation
```

The ported oh-my-claudecode agents are read-only/consult helpers you delegate to for
architecture analysis, requirements clarification, debugging, security review, etc.

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
