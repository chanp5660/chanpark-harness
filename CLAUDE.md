# CLAUDE.md — chanpark-harness plugin

Guidance for Claude Code when working **on this plugin repository**. (For how the plugin
behaves once installed, the skills and agents themselves are the source of truth.)

## What this repo is

A Claude Code plugin merging **claude-code-harness** (base, wins on conflict) and selected
**oh-my-claudecode** agents/skills (gap-fillers), rebranded to `chanpark-harness`,
localized to English, and modernized to the current plugin spec. It is a single-plugin
marketplace (`.claude-plugin/marketplace.json`, plugin `source: "./"`).

Portability rule: **everything must work from a plain `git` checkout — no Node/Go build.**
The only compiled artifact is the committed harness Go binary in `bin/`.

## Layout

| Path | Role |
|------|------|
| `.claude-plugin/plugin.json` | Manifest (modern spec: `displayName`, `defaultEnabled`, explicit skills/outputStyles paths; agents/hooks/monitors auto-discovered, no `mcpServers`) |
| `.claude-plugin/marketplace.json` | Self-marketplace catalog entry |
| `.claude-plugin/settings.json` | Permission allowlist/denylist shipped with the plugin |
| `agents/` | 13 agents (harness `worker`/`reviewer`/`advisor` + 10 OMC consults) |
| `skills/` | 22 skills (`harness-*`, `session`, `memory`, `maintenance`, `ui`, plus OMC gap skills) |
| `hooks/hooks.json` | Automation hooks; exec the Go binary, no-op if absent |
| `monitors/monitors.json` | Auto-armed `harness-session-monitor` (`when: always`) running `harness hook session-monitor` — emits the "Session Start - Project State" block (Plans.md drift, harness-mem health, advisor/reviewer state) |
| `bin/` | `harness` shim + pre-built Go binaries (4 platforms) |
| `hud/statusline.sh` | Portable HUD renderer (bash + jq) |
| `harness.toml` | Config SoT read by the binary |
| `templates/` | Scaffolding templates used by `harness-setup` |
| `output-styles/` | `harness-ops` output style |
| `scripts/` | Live helpers invoked directly by hooks (4 scripts), by the Go binary (sync-plugin-cache.sh, template-tracker.sh, check-residue.sh, ci/check-consistency.sh, session-relay-watch.sh), and by skills/agents (~44). Some retain upstream Japanese comments. |

## Canonical workflow (what the plugin promotes)

Plan → Work → Review, tracked in a root `Plans.md` with English status markers
**`cc:todo` / `cc:wip` / `cc:done` / `cc:blocked`** and PM markers `pm:requested` /
`pm:approved`. Skills: `harness-plan`, `harness-work`, `harness-review`, `harness-sync`.
The ported OMC agents are read-only/consult helpers for the gaps (architecture, requirements,
debugging, security, docs, tests, search, git, writing, interactive QA).

> **`HAR:` description prefix**: intentionally present only on the 5 canonical-loop skills
> (`harness-plan`, `harness-work`, `harness-review`, `harness-sync`, `harness-setup`).
> The auxiliary `harness-*` skills (`harness-accept`, `harness-loop`, `harness-plan-brief`,
> `harness-progress`, `harness-release`) omit the prefix by design — the split is documented
> intent, not drift.

## Invariants — do not break these

- **Plugin name `chanpark-harness`** appears in `hooks/hooks.json` root-detection grep and
  in marketplace/cache fallback paths. If you rename the plugin, update those literals too.
  The Go binary does **not** re-validate the plugin name, but `harness.toml` and the
  `.claude-code-harness.config.*` filenames are read by the binary — keep those names.
- **Status markers are English**; canonical written form is lowercase
  (`cc:todo`/`cc:wip`/`cc:done`/`cc:blocked`) and PM markers `pm:requested`/`pm:approved`.
  **Matching precision (post-rebuild 2026-07-07)**: all binary counter paths match
  case-insensitively and count all four canonical markers; `cc:完了` and
  `pm:依頼中`/`pm:確認済`/`cursor:*` remain counted as legacy aliases. The bash scripts
  read uppercase/legacy aliases too.
- **Agent frontmatter**: full model IDs (`claude-opus-4-8`, `claude-sonnet-4-6`,
  `claude-haiku-4-5`), `effort`, and `disallowedTools` (read-only consults disallow
  `Write, Edit, Agent`; others disallow `Agent`). No `permissionMode`/`mcpServers`/`hooks`
  in plugin-shipped agents (security restriction).
- **English only** for user-facing content (agents/skills/output-styles/templates); the
  grep health check enforces this for those paths. The rebuilt binaries emit English on all
  session-init/plans-watcher/monitor/TDD/CI surfaces; JP literals remain only as legacy
  marker-counting aliases and in untargeted upstream handlers (see
  `docs/patches/binary-rebuild/verification-3.3.md` V8 for the inventory).
- **`bin/harness sync` is safe post-rebuild (2026-07-07)**: it writes only
  `.claude-plugin/plugin.json` and `.claude-plugin/settings.json`, preserves unknown
  plugin.json fields (`displayName`, `defaultEnabled`), and never creates
  `.claude-plugin/hooks.json`. It OWNS and regenerates name/version/description/author/
  homepage/repository/license/keywords/skills/outputStyles from `harness.toml [project]` —
  keep that section aligned with the curated plugin.json.
- Keep `bin/harness-*` executable (mode 0755) and marked binary in `.gitattributes`.

## Health checks

```bash
CLAUDE_PLUGIN_ROOT="$PWD" ./bin/harness doctor      # config + hooks + manifest sanity
CLAUDE_PLUGIN_ROOT="$PWD" ./bin/harness validate    # validate all SKILL.md files
grep -rlP '[\x{3040}-\x{30ff}\x{4e00}-\x{9fff}]' agents skills output-styles templates  # must be empty
```

## Provenance / license

MIT. Derived from claude-code-harness (Chachamaru) and oh-my-claudecode (Yeachan Heo),
both MIT. See `LICENSE`.

## Upstream updates

This repo is a transform-merge of the two upstreams (rebrand + EN localization + spec
modernization) with **no git ancestry** to them. To pull upstream changes, follow the
reconcile procedure and component→upstream map in **`PROVENANCE.md`** — it records the
fetch-only remotes (`harness-upstream`, `omc-upstream`), the baseline SHA markers to diff
from, and the transforms to re-apply.
