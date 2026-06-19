# PROVENANCE — upstream tracking

This file is the single source of truth for **where each component came from** and
**how far upstream we have reconciled**. `chanpark-harness` is a *transform-merge* of two
upstreams (rebrand + English localization + spec modernization); there is **no git ancestry**
linking us to them, so updates are pulled by reading upstream diffs and re-applying the
transforms by hand. This file is what makes that repeatable.

## Upstreams

| key | repo | role | fetch remote |
|-----|------|------|--------------|
| harness | https://github.com/Chachamaru127/claude-code-harness | base — wins on conflict | `harness-upstream` |
| omc | https://github.com/yeachan-heo/oh-my-claudecode | gap-filler — selected consults/skills | `omc-upstream` |

Remotes are **fetch-only** (push URL set to `DISABLED`). They are not merged — they exist
only so `git fetch` + `git log` can show what changed since the last reconcile.

```bash
git remote add harness-upstream https://github.com/Chachamaru127/claude-code-harness.git
git remote add omc-upstream     https://github.com/yeachan-heo/oh-my-claudecode.git
git remote set-url --push harness-upstream DISABLED
git remote set-url --push omc-upstream     DISABLED
# do NOT pull upstream tags into our local tag namespace (we only keep v1.0.x)
git config remote.harness-upstream.tagOpt --no-tags
git config remote.omc-upstream.tagOpt     --no-tags
```

## Reconcile markers

`baseline` = the upstream commit our current files were last reconciled against. Diff the
next update from here, then bump it.

| upstream | baseline SHA | tag | recorded |
|----------|--------------|-----|----------|
| harness | `c2dbd939c2eb338e18db03079ee2d240d363e1fd` | v4.15.0 | 2026-06-19 |
| omc | `50f6ff05eb5d9ebed66f05d8c4580c0b119f37af` | v4.14.7 | 2026-06-19 |

> ⚠️ **Honest caveat for the first sync.** These SHAs are the upstream HEAD *observed on
> 2026-06-19*, not a verified reconcile point — the original manual port predates them and
> may already lag behind v4.15.0 / v4.14.7. Treat the next sync as a one-time **catch-up
> review**: diff the full range and decide per file. After that, these markers are accurate
> and each later sync is a small incremental diff.

## Component → upstream map

Used to scope `git log <baseline>..<remote>/HEAD -- <paths>` so you only review files you
actually ported.

### From harness (base)
- `bin/` — pre-built Go binaries + shim (upstream `go/` source)
- `harness.toml`, `.claude-code-harness.config.*`, `claude-code-harness.config.*`
- `hooks/hooks.json`
- `monitors/monitors.json` — `harness-session-monitor` (auto-armed, `when: always`); SSOT is
  the file, not `plugin.json` (upstream deliberately removed the `monitors` manifest block)
- `agents/`: `worker.md`, `reviewer.md`, `advisor.md`
- `skills/`: `harness-*`, `session*`, `memory`, `maintenance`, `hud`, `principles`,
  `routing-rules.md`, `workflow-guide`, `vibecoder-guide`
- `output-styles/`, `templates/`, `scripts/` (some retain upstream JP comments)

### From omc (gap-filler)
- `agents/`: `architect.md`, `analyst.md`, `debugger.md`, `document-specialist.md`,
  `explore.md`, `git-master.md`, `qa-tester.md`, `security-reviewer.md`,
  `test-engineer.md`, `writer.md`
- `skills/`: `ai-slop-cleaner`, `breezing`, `ci`, `deep-interview`, `skill`, `skillify`,
  `trace`, `agent-browser`, `ui`, and other non-`harness-*` gap skills

> Some files are blended (e.g. a harness skill with omc ideas grafted in). When a file's
> origin is ambiguous, check both upstreams' diffs before porting.

## Update procedure (lightweight manual)

1. **Fetch**: `git fetch harness-upstream && git fetch omc-upstream`
2. **Scope the diff** per upstream, restricted to the paths above:
   ```bash
   git log --oneline <baseline>..harness-upstream/HEAD -- bin/ harness.toml hooks/ \
     agents/worker.md agents/reviewer.md agents/advisor.md skills/harness-* ...
   ```
   No hits in your paths → nothing to do; just bump the SHA marker.
3. **Port changed files**, re-applying the transforms (see below). Base (harness) wins on
   conflict with omc.
4. **Re-localize**: detect any new Japanese content that slipped in —
   `grep -rlP '[\x{3040}-\x{30ff}\x{4e00}-\x{9fff}]' agents skills output-styles templates`
   must come back empty (scripts/ is allowed to retain JP comments).
5. **Health checks** (from CLAUDE.md):
   ```bash
   CLAUDE_PLUGIN_ROOT="$PWD" ./bin/harness doctor
   CLAUDE_PLUGIN_ROOT="$PWD" ./bin/harness validate
   ```
6. **Bump markers** in this file to the new HEAD SHAs + tags + date.
7. Commit. Bump plugin `version` only if user-facing behavior changed.

## Transforms to re-apply on every port

| transform | rule | mechanizable? |
|-----------|------|---------------|
| rebrand | `oh-my-claudecode` / `claude-code-harness` → `chanpark-harness` in user-facing paths/literals (keep the invariants in CLAUDE.md — hooks grep, marketplace/cache paths, binary-read filenames) | yes (sed) |
| status markers | keep English lowercase `cc:todo\|wip\|done\|blocked`, `pm:requested\|approved` | yes |
| agent frontmatter | full model IDs, `effort`, `disallowedTools`; no `permissionMode`/`mcpServers`/`hooks` | check, not auto |
| localization | JP → EN for all user-facing content, **including the compiled Go binary** (see note) | **no — needs human judgment** |

### Binary localization note (added 2026-06-19)

`bin/harness-*` had Japanese baked in (status labels like `が実行予定`/`が実装中`, notifications,
error prose) because the upstream `go/` source is Japanese. The committed binaries were rebuilt
from a JP→EN-localized copy of upstream `go/` (fetched at `harness-upstream` HEAD
`4a0961e4`). Likewise `scripts/` (the binary's bash fallbacks) were localized in place.

To redo this on a future reconcile:
1. `git archive harness-upstream/HEAD go/ | tar -x -C <workdir>` (Go source is **not** kept in
   this repo — `no Go build` portability rule means only the binary is committed).
2. Translate JP **comments + user-facing strings** in `*.go` and `scripts/*`. **Preserve** these
   Japanese literals — they are matched, not displayed: marker aliases (`cc:完了`/`pm:依頼中`/
   `pm:確認済`/`cursor:*`), `locale=="ja"` i18n branches, input-matching keyword lists
   (`detectIntent`, yes/no normalizers `はい`/`いいえ`/`承認`/`却下`), NER/POS tags (`固有名詞`),
   and read-compat header patterns (`## マーカー凡例|## Marker Legend`).
3. Reconcile any `*_test.go` assertions that expected the old strings (update expected English;
   never weaken/skip assertions).
4. Rebuild 4 platforms with `CGO_ENABLED=0` (modernc sqlite is pure-Go) from `./cmd/harness`:
   `linux/amd64`, `darwin/amd64`, `darwin/arm64`, `windows/amd64` (`.exe`); copy over `bin/`,
   keep `bin/harness` shim untouched, `chmod 0755`.
5. Verify: `grep -aoP '(が実行予定|が実装中|がタスクを完了しました|から依頼)' bin/harness-linux-amd64`
   should be empty; one residual `が更新されました` is expected (a `locale=="ja"` branch in
   `runtime_reactive.go`, served only when `HARNESS_LOCALE=ja` — English is the default).

## Claude Code (host CLI) spec drift

The host CLI is **not** a file-merge upstream — it changes the *plugin spec* (manifest schema,
hooks format, agent frontmatter fields, skill format). It can break the plugin silently.
Handling: when a new Claude Code version ships, run the health checks (`harness doctor`,
`harness validate`) — they are the spec-compatibility tripwire. No SHA marker needed.

## New plugins / components

Policy: **decide case by case.** Default instinct is to install standalone plugins as-is
rather than absorb them here (absorption adds localization + rebrand + maintenance cost).
Only fold a component into this repo when it fills a plan-work-review workflow gap *and*
benefits from unified naming / model routing enough to justify the transform cost.
