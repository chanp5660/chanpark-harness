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
| harness | `c220671ec53e9bb298b6f2a473950024caee78a9` | v4.16.4 | 2026-07-07 |
| omc | `590fb988931d34a12604be0ca4215c818079018e` | v4.15.4 | 2026-07-18 |

> ⚠️ **Honest caveat, updated 2026-07-18.** The harness baseline is a **verified
> reconcile point for `go/` (the built binaries) only** — see "Binary rebuild" below. The
> md/script components remain the original manual port and were never re-reconciled;
> treat their next sync as the one-time **catch-up review** (diff the full range, decide
> per file). The omc baseline was bumped to `590fb988` (v4.15.4, 2026-07-18): the
> **specifically ported agents and skills** had zero commits in the 50f6ff05..590fb988
> range (verified by path-restricted `git log`). **Non-ported omc skills did change** in
> that range; those are outside our scope and were not reviewed.

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
- `skills/`: `harness-*`, `session`, `memory`, `maintenance`, `breezing`, `ci`, `ui`,
  `routing-rules.md`
  - *Removed 2026-07-07 (dead-code pruning)*: `principles`, `workflow-guide`,
    `vibecoder-guide`, `session-control`, `session-state` — absent from this repo;
    do not scope these paths in reconcile diffs
- `output-styles/`, `templates/`, `scripts/` (some retain upstream JP comments)

### From omc (gap-filler)
- `agents/`: `architect.md`, `analyst.md`, `debugger.md`, `document-specialist.md`,
  `explore.md`, `git-master.md`, `qa-tester.md`, `security-reviewer.md`,
  `test-engineer.md`, `writer.md`
- `skills/`: `ai-slop-cleaner`, `deep-interview`, `skill`, `skillify`, `trace`
  - *Removed 2026-07-07 (dead-code pruning)*: `agent-browser` — absent from this repo

### Locally authored (no upstream source)
- `skills/hud`, `hud/statusline.sh` — written in commit `bdb0621e` (2026-06-18) as a
  portable bash+jq replacement for omc's Node-bound HUD (`dist/hud/index.js`). Absent
  from harness baseline `c220671e`; our implementation is unrelated to omc's version.
  Do not diff either upstream for this path.

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

## bin/ binary accretion in git history

The portability rule ("no Node/Go build required") means the 4 pre-built Go binaries
(`harness-linux-amd64`, `harness-darwin-amd64`, `harness-darwin-arm64`,
`harness-windows-amd64.exe`) must be committed into `bin/`. Each release replaces all four.
Because successive builds are highly similar, git delta-compresses them, so the **incremental
pack cost per release is far smaller than the ~66 MB raw size** would suggest.

**History cleanup performed 2026-06-24 (option: periodic history pruning).**
The pre-1.2.1 `bin/` binary blobs were stripped from git history with
`git filter-repo --invert-paths --path bin/` scoped to our own refs
(`refs/heads/master` + tags `v1.0.0`…`v1.2.1`; the `harness-upstream` / `omc-upstream`
fetch mirrors were deliberately left untouched). The current platform binaries were then
re-committed at the `v1.2.1` tip, so the **plain-checkout invariant is preserved** — a fresh
checkout of `master`/`v1.2.1` still contains working `bin/` binaries with no build step.

Consequences (one-time, accepted):
- All commit SHAs on `master` and all 8 tags were rewritten and force-pushed.
- **Older tags (`v1.0.0`…`v1.2.0`) no longer carry in-tree binaries** — only the current
  release tip does. Checking out a historical tag will not yield a runnable binary.
- Local `.git` dropped 173 MB → 145 MB (the ~28 MB reclaimed was the real delta-compressed
  cost of the historical binaries; most of the remaining 145 MB is the upstream fetch mirrors,
  which are a separate, out-of-scope bloat source — removable with `git remote remove
  harness-upstream omc-upstream` if reconcile mirrors are not currently needed).
- Remote (GitHub) reclamation is eventual/server-side after the force-push.

Mitigations considered and **not** adopted (LFS breaks the plain-checkout invariant;
release-asset download breaks air-gapped use):

| option | why not chosen |
|--------|----------------|
| **Git LFS for `bin/harness-*`** | requires LFS on every clone/CI; breaks "plain `git clone`" guarantee unless LFS is pre-installed |
| **GitHub Releases + shim download-on-miss** | needs network at first run; breaks air-gapped/offline setups unless an in-tree binary remains anyway |

**Going forward**: re-pruning is a deliberate, force-push-bearing operation — repeat the
scoped `git filter-repo` above (never widen it to the upstream mirrors), keep the current
binaries re-committed at the release tip, and do **not** change `.gitattributes` binary
markings without updating this note.

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

### Declined port — omc `merge-readiness` (2026-07-18)

The omc `skills/merge-readiness/SKILL.md` (added in the 50f6ff05..590fb988 range) requires:
- `src/hooks/merge-readiness/*.ts` (e.g. `mcq.ts`) compiled and served as MCP tools
  (`merge_readiness_start` and at least 3 sibling tools) — violates the no-build portability rule
- State persistence under `.omc/state/` (omc-branded path requiring rebranding)
- `OMC_*` environment variables

Declined 2026-07-18. Revisit if omc ships a build-free variant (pure-markdown skill with
LLM-side scoring, no compiled hook code).

## Dead-code pruning — 2026-07-07 (task 4.2)

Removed ~96 dead upstream scripts and 8 skill directories per analysis in
`docs/reports/dead-code-disposition-2026-07-03.md`:

- **Scripts deleted**: 94 of 97 dead scripts from §5 appendix (97 total minus 3 kept as
  live CI infrastructure: `check-baseline.sh`, `check-regression-guard.sh`,
  `check-template-registry.sh`). Also deleted: `scripts/sandbox-test/` (3 fixture files),
  `scripts/lib/codex-hardening-contract.txt`, and 2 QUESTIONABLE-resolved items
  (`auto-cleanup-hook.sh`, `session-state.sh`). Total removed: ~101 files, ~17,238 lines.
- **Skills removed** (6 dirs): `session-control`, `session-state`, `agent-browser`,
  `principles`, `vibecoder-guide`, `workflow-guide`.
- **Skills moved** (2): `session-init` and `session-memory` SKILL.md content relocated to
  `skills/session/references/` (content was document-consumed by the live session skill).
- **Skills fixed** (1): `ui` — `disable-model-invocation` set to `false` so the skill is
  model-invocable as documented in the skills-gate template.
- Skill count after pruning: 30 → 22.

## Ours-only, upstream-deleted components

The following files we carry are **absent from the harness upstream** at the current
reconcile point. A future reconcile must NOT treat their absence in upstream diffs as a
missing port — they are intentionally kept here.

| file / path | deleted upstream | notes |
|-------------|-----------------|-------|
| `skills/session/` | commit `12311072` (Phase 91.7, 2026-06-06) | actively used skill |
| `scripts/check-residue.sh` | commit `12311072` (same batch) | live CI helper |
| `scripts/session-relay-send.sh` | absent from harness HEAD; present at baseline `c220671e` | live session relay helper |
| `scripts/session-relay-watch.sh` | absent from harness HEAD; present at baseline `c220671e` | live session relay helper |

Do **not** delete these files during a reconcile pass.

## Binary rebuild — harness baseline bump (2026-07-07)

### Baseline update

- **claude-code-harness baseline**: `c2dbd939c2eb338e18db03079ee2d240d363e1fd` (observed 2026-06-19, between v4.15.0 and v4.16.0; previous honest-caveat: unverified reconcile point)
  → **`c220671ec53e9bb298b6f2a473950024caee78a9` (tag `v4.16.4`, 2026-06-28)** — verified reconcile point for the Go binaries: this is the exact ref the committed `bin/harness-*` binaries are built from (plus the local patch set, see below). Divergence absorbed: 30 upstream commits (9 touching `go/`), dominated by upstream security additions (commit-guard audit v4.16.1, runtime-floor egress rules v4.16.2/v4.16.4).

### Finding recorded 2026-07-07: previous binaries came from a lost fork

The previously committed binaries (built 2026-06-19) did **not** correspond to any pristine upstream ref. Feature probing dated them to the v4.16.1 era, but they embedded partially-anglicized strings (e.g. `A new task has been requested by PM (pm:依頼中 / compat: cursor:依頼中).`, `# [claude-code-harness] Session Initialization`) that exist nowhere in upstream history — evidence of an intermediate, partially-localized fork whose source was never committed to this repo. That fork is unrecoverable; the 2026-07-07 rebuild supersedes it with a fully documented, reproducible patch set.

### Binary build recipe (reproducible)

1. Clone upstream `github.com/Chachamaru127/claude-code-harness`, checkout `v4.16.4` (`c220671e`).
2. Apply `docs/patches/binary-rebuild/binary-rebuild.patch` (combined; equivalently the four per-area patches `p1-p2-markers-and-english.patch`, `p3-p6-sync.patch`, `p4-ci-advice.patch`, `p5-migration-report.patch` — each applies independently to the pristine tag).
3. Build (go >= 1.25.0; built with go1.25.5), matching upstream `go/scripts/build-all.sh` semantics:
   `cd go && CGO_ENABLED=0 GOOS=<os> GOARCH=<arch> go build -buildvcs=false -ldflags "-s -w -X main.version=4.16.4" -o ../bin/harness-<os>-<arch>[.exe] ./cmd/harness/`
   for linux/amd64, darwin/amd64, darwin/arm64, windows/amd64.

### Patch set summary (docs/patches/binary-rebuild/)

- **P1** counters: case-insensitive marker matching everywhere; all four canonical lowercase markers (`cc:todo/cc:wip/cc:done/cc:blocked`) counted, `cc:完了` kept as done-alias, `pm:requested`/`pm:approved` primary with JP/`cursor:*` compat aliases.
- **P2** English user-facing strings: session-init legend, plans-watcher summary + pm-notification.md, session-monitor "Session Start - Project State" block, session-log.md content, runtime-reactive messages, TDD gate, stop-evaluator message.
- **P3** `harness sync` no longer generates the `.claude-plugin/hooks.json` duplicate.
- **P4** CI-failure advice: `ci-cd-fixer`/`/breezing` steering replaced with `chanpark-harness:debugger`, English.
- **P5** `scripts/setup-codex.sh` / `scripts/setup-opencode.sh` references neutralized in migration-report advice.
- **P6** (fix beyond the original scope): `harness sync` plugin.json regeneration now preserves unknown manifest fields (`displayName`, `defaultEnabled`, custom keys); sync OWNS exactly `name, version, description, author, homepage, repository, license, keywords, skills, outputStyles`. Upstream at v4.16.4 dropped all unknown fields.
- Upstream test suite: green on the patched tree (assertions updated where strings intentionally changed).

### Upstream reconcile note

Future upstream pulls of `go/` should diff from `c220671e` (v4.16.4) and re-apply the patch set above; re-run the 3.3 verification suite (`docs/…/verification-3.3.md` procedure) after any rebuild.

## Divergence decision — 2026-07-18

The harness upstream is at **v5.2.0** (`harness-upstream/main`, +469 commits from our
baseline `c220671e`). The divergence is heavily concentrated in `go/` (109 commits,
+25,476/−2,699 lines). The md/script surfaces we ported are near-unchanged.

**Why we do not chase upstream:**

- `go/cmd/harness/sync.go:166–167` at v5.2.0 **still copies `hooks/hooks.json` into
  `.claude-plugin/`** — the duplication our patch P3 removed.
- `go/internal/plans/plans.go` at v5.2.0 **still uses uppercase `cc:TODO` and Japanese
  `cc:完了` as first-class primary markers** — the case-sensitivity our patch P1 fixed.
- `go/cmd/harness/sync.go` at v5.2.0 **still drops unknown `plugin.json` fields** such
  as `displayName` and `defaultEnabled` — the preservation our patch P6 added.

Re-porting `go/` at this point would require re-applying all of patches P1–P6. Decision:
**hold as an intentional fork**; port selectively when specific upstream fixes are
relevant; do not chase version parity.
