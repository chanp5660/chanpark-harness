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
| `.claude-plugin/plugin.json` | Manifest (modern spec: `displayName`, `defaultEnabled`, explicit component paths, no `mcpServers`) |
| `.claude-plugin/marketplace.json` | Self-marketplace catalog entry |
| `.claude-plugin/settings.json` | Permission allowlist/denylist shipped with the plugin |
| `agents/` | 13 agents (harness `worker`/`reviewer`/`advisor` + 10 OMC consults) |
| `skills/` | 30 skills (`harness-*`, sessions, memory, guides, `hud`, OMC gap skills) |
| `hooks/hooks.json` | Automation hooks; exec the Go binary, no-op if absent |
| `bin/` | `harness` shim + pre-built Go binaries (4 platforms) |
| `hud/statusline.sh` | Portable HUD renderer (bash + jq) |
| `harness.toml` | Config SoT read by the binary |
| `templates/` | Scaffolding templates used by `harness-setup` |
| `output-styles/` | `harness-ops` output style |
| `scripts/` | Bash/Python helpers (binary fallbacks); some retain upstream Japanese comments |

## Canonical workflow (what the plugin promotes)

Plan → Work → Review, tracked in a root `Plans.md` with English status markers
**`cc:todo` / `cc:wip` / `cc:done` / `cc:blocked`** and PM markers `pm:requested` /
`pm:approved`. Skills: `harness-plan`, `harness-work`, `harness-review`, `harness-sync`.
The ported OMC agents are read-only/consult helpers for the gaps (architecture, requirements,
debugging, security, docs, tests, search, git, writing, interactive QA).

## Invariants — do not break these

- **Plugin name `chanpark-harness`** appears in `hooks/hooks.json` root-detection grep and
  in marketplace/cache fallback paths. If you rename the plugin, update those literals too.
  The Go binary does **not** re-validate the plugin name, but `harness.toml` and the
  `.claude-code-harness.config.*` filenames are read by the binary — keep those names.
- **Status markers are English** and matched by the binary case-insensitively
  (`cc:todo|wip|done|blocked`). The bash scripts read uppercase/legacy aliases too; the
  canonical written form is lowercase English.
- **Agent frontmatter**: full model IDs (`claude-opus-4-8`, `claude-sonnet-4-6`,
  `claude-haiku-4-5`), `effort`, and `disallowedTools` (read-only consults disallow
  `Write, Edit, Agent`; others disallow `Agent`). No `permissionMode`/`mcpServers`/`hooks`
  in plugin-shipped agents (security restriction).
- **English only** for user-facing content (agents/skills/output-styles/templates).
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
