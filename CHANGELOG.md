# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.6] - 2026-07-27

Marker counting is now anchored to the table status cell everywhere.

> **Counts will change on upgrade.** Any project whose `Plans.md` mentions a marker in
> prose, in the marker legend, in a fenced example or in an HTML comment will report a
> *lower* number after this release — that is the fix, not a regression. Re-read
> `.claude/state/plans-state.json` before comparing it against a pre-1.3.6 snapshot.

### Fixed

- **`cc:*` markers were counted anywhere in `Plans.md`, not just in a status cell.** The
  vendored Go binary's `hook plans-watcher` matched the markers as unanchored,
  case-insensitive substrings, so a single archive sentence —
  `Phase 22~26 moved to Plans-archive-2026-07-27.md (all cc:done)` — counted as a tenth
  finished task and `.claude/state/plans-state.json` reported `cc_done: 10` for a nine-row
  table. Measured on a real project: `cc_done` 10 -> 9, `cc_todo` 6 (unchanged).

  There is no Go source in this repo — `bin/harness-*` is vendored from upstream — so the
  counter could not be corrected in place. `scripts/hook-handlers/plans-watcher.sh` takes
  over the handler instead and `hooks/hooks.json` dispatches to it. Behaviour parity with
  the handler it replaces was measured, not assumed: same trigger condition
  (`<cwd>/Plans.md` only), same delta rules (`pm:requested` growth outranks `cc:done`
  growth, everything else is recorded silently), same `pm-notification.md` /
  `cursor-notification.md` output, same JSON envelope. Opt out with
  `HARNESS_DISABLE_PLANS_WATCHER=1`.

  **Still unfixed, and unfixable without the Go source**: `harness hook session-init` and
  `harness hook session-monitor` print their own `Plans.md: todo N / wip N / done N` summary
  from the same unanchored counter. Those lines are injected context only — nothing reads
  them back — but they will disagree with `plans-state.json` on a file with prose markers.

- **`hud/statusline.sh` counted the marker legend as open work.** Its anchor required the
  marker to follow a pipe, which a legend row (`| cc:todo | To do | ... |`) satisfies with
  its *first* cell. It now reads the same counter as the hook.

- **`scripts/progress-snapshot.sh` dropped most finished tasks — the same disagreement in
  the opposite direction.** Its single row regex pinned the table to exactly five columns
  and required the status cell to be a bare marker (plus an optional `[hash]`), so both a
  six-column table and the very common `cc:done (2026-07-14: measured on hw)` note failed
  to match and the row vanished from the snapshot entirely. The same real project reported
  `done: 1` against nine finished tasks; it now reports 9. Rows are split on `|` and the
  status is the last non-empty cell, and fenced blocks and HTML comments are skipped.
  **Progress percentages in the harness-progress HTML will move accordingly** (that project:
  14% → 60%).

### Added

- `scripts/lib/plans-markers.awk` — the canonical marker counter, shared by the
  plans-watcher hook, the HUD and CI. Emits `todo wip done blocked pm_requested pm_approved`.
  A marker counts only when the last non-empty cell of a table row starts with it; code
  spans are stripped inside that cell, and fenced blocks, HTML comments and non-table lines
  are skipped. `cursor:*` and the legacy Japanese marker forms remain readable as aliases.
- `check-regression-guard.sh` checks `plans-marker-anchoring` (fixture-driven: a nine-row
  table plus every false-positive shape must count as `6 0 9 0 0 0`), `plans-watcher-handler`
  (hooks.json must not fall back to the binary subcommand) and `progress-snapshot-rows`
  (the snapshot must see all nine rows).
- `tests/fixtures/plans-prose-marker-inflation.md` — reproduces the incident above.

### Notes

- The v1.3.5 CI step *"Plans.md quotes no live marker tokens outside status columns"*, which
  forced marker mentions to be escaped as `cc&#58;todo`, was the workaround for this bug. It
  is left in place: it is now belt-and-braces rather than load-bearing.

## [1.3.5] - 2026-07-18

Follow-ups from an audit of this plugin against its two upstreams, the Claude Code
2.1.214 plugin spec, and internal dead weight.

### Added

- `.github/workflows/checks.yml`. There was no `.github/` at all, which is why the broken
  verification gate below went unnoticed for months. It runs the checks that actually pass
  here and adds two guards: one asserting the `bin/harness` shim really dispatches (it exits
  0 with empty stdout when no platform binary is present, which would otherwise fake a pass),
  and one failing the build when `Plans.md` quotes a marker outside a status column.
  `check-consistency.sh` is ratcheted at its known count of 44 rather than required, since
  its remaining assertions target upstream-only assets.
- `skills/harness-review/references/security-profile.md` — the fresh-context isolation and
  findings feedback contract for security review.

### Fixed

- **The Lead Pre-cherry-pick Gate was impossible to satisfy.** It required three commands,
  two of which never existed in this repo (`tests/` holds only `fixtures/`), and
  `agents/worker.md` hardcoded a `→ PASS` evidence string for one of them. Replaced with the
  measured-green set. The same dead reference is fixed in `harness-loop/references/flow.md`.
- **`scripts/ci/check-baseline.sh` failed its own check.** Two of its comments began with
  the analyzer's name followed by a colon, which shellcheck parses as a directive rather than
  prose, raising SC1073/SC1072. The script reported `PASS=76 FAIL=1` against itself and took
  the whole gate down. Latent until CI installed shellcheck, since it is absent locally.
- **`reviewer` lost its issue #172 mitigation** during the original English port (upstream
  190 lines vs. our 175). Without it, security findings flowing into the parent context trip
  the cybersafeguard and the reviewer stalls mid-response. Restored, along with the explicit
  defensive-review scope declaration.
- **`Plans.md` reported permanent phantom work.** The binary's counters match
  `` (?i)`?cc:TODO`? `` as unanchored substrings, so marker names quoted in the legend and in
  task descriptions counted as open tasks — a standing `WIP 1 / TODO 4` and a stale-WIP drift
  warning against a plan with zero open tasks. All five sources were isolated by bisecting
  against `harness hook session-monitor`; the last was a quoted legacy alias, `pm:依頼中`.
- **`harness sync` silently clobbered `plugin.json`.** `harness.toml` and `plugin.json`
  disagreed on the author form, so every sync rewrote the manifest. Alignment had to go the
  URL direction: sync reads only `name`/`url` from `[project.author]` and never emits an
  `email` key, so a curated email cannot survive a sync. Two consecutive syncs are now
  byte-identical.

### Changed

- The published author field is now a GitHub URL rather than an email address, across
  `plugin.json` and both `marketplace.json` surfaces. Commit authorship in git history is
  unaffected.
- Sonnet pins moved to `claude-sonnet-5` (currency — `claude-sonnet-4-6` is still Active with
  no announced retirement).
- `PROVENANCE.md` records the divergence decision: harness upstream is at v5.2.0 (+469
  commits), but the divergence is concentrated in `go/`, and its `sync` still copies
  `hooks.json` into `.claude-plugin/`, still drops unknown manifest fields, and still uses
  uppercase plus Japanese first-class markers. Re-porting would mean re-applying local
  patches P1–P6, so this is held as an intentional fork. The component→upstream map is
  corrected: `breezing`/`ci`/`ui` reattributed to the harness upstream, six ghost entries
  naming deleted files annotated, `hud` marked locally authored, and the omc baseline
  advanced to `590fb988` with a scope-limited caveat.
- `CLAUDE.md` corrections: `.claude-plugin/settings.json` described as the sync-generated
  mirror it is (not plugin-spec settings), the rotting "~44 scripts" figure removed, monitors
  noted as interactive-CLI only, and a caution that `doctor`'s PATH line resolves to the
  installed cache copy by design.

## [1.3.4] - 2026-07-14

### Added

- `bin/harness.cmd` — a Windows shim, so a bare `harness <cmd>` works from cmd.exe and
  PowerShell. `bin/` previously shipped only the extension-less `/bin/sh` shim plus the
  platform `.exe`, and Windows' `PATHEXT` cannot resolve an extension-less file: with `bin/`
  on PATH the command still failed, and `harness doctor` reported `[FAIL] bin/harness in
  PATH`. The new shim mirrors the sh shim, including its contract on a missing binary
  (diagnostic on stderr, empty stdout, `exit 0`, never JSON — so Claude Code hooks read it
  as "no decision"). `.gitattributes` pins `*.cmd` to CRLF, which cmd.exe requires. Closes #2.

### Fixed

- The Windows shim now falls back to `harness-windows-amd64.exe` on ARM64. It resolved
  `harness-windows-arm64.exe`, which is not shipped, and then gave up — even though Windows 11
  on ARM runs the x64 build under emulation. Shipping a native arm64 binary would add ~11MB to
  `bin/` for every user (consumers clone the whole repo), so the fallback buys ARM64 support at
  zero size cost. If an arm64 binary is ever added, the arch check picks it up first.
- The Windows shim propagates the binary's exit code. The dispatch sat inside an
  `if exist (...)` block, and cmd.exe expands `%ERRORLEVEL%` when it *parses* a parenthesized
  block — so `exit /b %ERRORLEVEL%` returned the errorlevel from before the binary ran, not the
  binary's own. Hooks read that exit code to decide whether to act.

## [1.3.3] - 2026-07-14

### Fixed

- **`wip-guard.sh` no longer blocks the Stop hook forever.** The guard introduced in 1.3.2
  was written against the *table* dialect of `Plans.md` and broke the *checklist* dialect —
  the one `templates/Plans.md.template` itself emits. Three defects, all user-visible:
  - It stripped inline code spans from the whole line before matching, which destroyed the
    marker in `- [ ] Task \`cc:wip\``. Genuinely in-progress tasks went undetected.
  - It counted HTML comment lines (`<!-- cc:wip ... -->`) as WIP tasks. Since
    `templates/Plans.md.template` ships such a comment, **every project scaffolded from the
    template blocked its Stop hook out of the box**, reporting a phantom task by line number.
  - It ignored `stop_hook_active` in the Stop payload, so once it blocked it re-blocked on
    every retry — an unbreakable loop with no way out short of disabling the guard.

  Detection is now dialect-aware: HTML comments and fenced code blocks are skipped; table
  rows read the status from the last non-empty cell (code spans stripped per-cell, so a
  description quoting a marker cannot shadow the real status); checklist items keep their
  code spans and take the **last** `cc:` marker on the line as the status. `stop_hook_active:
  true` now allows immediately, breaking the loop.
- WIP task lists in the block/warn message are joined correctly. `paste -sd ', '` treats its
  argument as a *rotating* delimiter list under POSIX, so three tasks rendered as `a,b c`.
  Lists are now comma-separated, and a truncated list says how many more were omitted rather
  than silently showing the first 20.
- `check-cch-branch-protection-policy.sh` no longer fails on every repository whose default
  branch is not `main`. The branch is derived (`gh api .default_branch` → `origin/HEAD` →
  `main`), and "branch not found" (a real error, exit 1) is now distinguished from "branch
  has no protection rules configured" (exit 3), which `release-preflight.sh` reports as a
  warning instead of a hard failure. Previously `set -euo pipefail` aborted on the `gh` 404
  before any check ran, so the failure carried no diagnostic at all.

## [1.3.2] - 2026-07-14

### Fixed

- Stop / PreCompact WIP guard no longer fails on projects without a `Plans.md`. The two
  haiku `agent` hooks (`Stop[0].hooks[3]`, `PreCompact[0].hooks[2]`) never defined a
  file-absent branch, so the model improvised per run — either a bogus "cannot verify"
  block, or a silent fail-open that would also mask a genuinely moved/unreadable
  `Plans.md`. Both are replaced by the deterministic `scripts/hook-handlers/wip-guard.sh`,
  which handles four explicit paths: file absent → silent allow (project does not use
  harness planning; not an error), file unreadable → block with "WIP status unknown",
  file clean → silent allow, WIP present → block (Stop) / warn (PreCompact). The
  harness-loop lock-ownership suppression in PreCompact is preserved.
- WIP detection no longer counts markers quoted inside a task's *description*. The status
  is now read from the table row's status cell (last non-empty column) with inline code
  spans stripped, fixing false "plans drift: WIP=n" reports on plans whose tasks discuss
  the markers themselves.

### Changed

- `Plans.md` lookup order is now explicit: `$HARNESS_PLANS_FILE` → `<project>/Plans.md`
  → `<project>/docs/Plans.md`. Previously undefined.
- Replacing the two `agent` hooks with `command` hooks removes a haiku invocation on
  every session stop and every compaction.
- New opt-out: `HARNESS_DISABLE_WIP_GUARD=1` disables the guard.

## [1.3.1] - 2026-07-08

### Changed

- Binaries rebuilt with patch P7: all remaining user-facing Japanese display strings
  translated to English (96 lines across 21 source files; display-category CJK now 0).
  Preserved by design: legacy marker-alias literals (`cc:完了`, `pm:依頼中`, `cursor:*`),
  `locale=="ja"` i18n branches, and input-matching keyword lists. Inventory and
  verification: `docs/patches/binary-rebuild/{p7-classification,verification-6.1}.md`.

## [1.3.0] - 2026-07-07

Remediation release from a max-effort multi-agent review: 20 tasks across 5 phases
(binary rebuild, dead-code pruning, marker canon, hook portability/security, perf).

### Added

- CI regression infrastructure: `scripts/ci/check-baseline.sh` (bash -n + jq validation
  of all tracked scripts/JSON), marker-style fixtures, and a regression guard wiring
  marker-style and template-registry checks.
- Dead-code and unreachable-skill disposition reports under `docs/reports/`.
- Reproducible binary patch set and verification suite under `docs/patches/binary-rebuild/`.
- HUD onboarding nudge opt-out (`~/.claude/state/chanpark-hud-nudge-off` marker or
  `CHANPARK_HUD_NUDGE_OFF=1`), plus `settings.local.json` / project settings detection.

### Changed

- Rebuilt all 4 platform binaries from patched upstream v4.16.4 (baseline
  `c2dbd939`/v4.15.0 → `c220671e`/v4.16.4): case-insensitive counters for all four
  canonical markers, English-only user-facing strings (session-init legend included),
  `sync` preserves unknown `plugin.json` fields (`displayName`/`defaultEnabled`) and no
  longer creates `.claude-plugin/hooks.json`, ci advice routed to
  `chanpark-harness:debugger`, setup-codex references neutralized.
- Marker write instructions unified to the lowercase canonical set
  (`cc:todo` / `cc:wip` / `cc:done` / `cc:blocked`) across skills, templates, and the
  plan-brief schema; legacy uppercase forms remain readable.
- Hooks: dropped the duplicate PostToolUse haiku review (the deny-capable PreToolUse
  gate is the single review path); narrowed the PostToolUse `*` matcher to
  `Write|Edit|MultiEdit|Bash|Task` so Read/Glob/Grep/WebFetch spawn no hook commands.
- HUD statusline performance: single jq extraction, cache-gated `rev-parse`,
  `GIT_OPTIONAL_LOCKS=0`.
- `harness.toml` `[project]` aligned with the curated `plugin.json`; post-rebuild sync
  gate lifted and CLAUDE.md invariants corrected to empirical behavior.

### Fixed

- Hook preambles use PATH `grep` instead of hardcoded `/usr/bin/grep` (portability
  across hosts without `/usr/bin/grep`).
- HUD git cache: unbound-variable guards and guarded reads under `set -uo pipefail`;
  `printf '%s'` rendering so WIP titles containing escapes no longer split the
  statusline into multiple rows.
- Progress snapshot: parses checklist-format rows and `T001`-style IDs,
  case-insensitive marker matching, `cc:blocked` counted in totals with one alert per
  blocked task.
- `release-preflight.sh` defaults PROJECT_ROOT to the invoking directory per the
  SKILL.md contract (was: plugin checkout).
- Identity drift: `harness.toml` and `sync-plugin-cache.sh` aligned to
  `chanpark-harness`; residual `[claude-code-harness]` branding replaced.
- Dead agent/command/doc references repaired across skills, agents, and templates
  (e.g. `ci-cd-fixer` → `chanpark-harness:debugger`, `/harness-init` →
  `/chanpark-harness:harness-setup`).
- Template registry: all 5 `html/*.html.template` render sources registered
  (`tracked:false`); dead `$schema` pointer removed; registry check now passes 30/30.
- Config: truthful yaml header, contradictory codex mode disabled, dead schema/example
  JSONs dropped.
- `session-state.sh` invalid-transition crash (top-level `local` under `set -e`);
  plan-brief sentence splitting now handles English sentence ends.

### Removed

- 96 dead upstream scripts and fixtures deleted per the disposition report (live CI
  infrastructure retained).
- 6 unreachable skills pruned (`session-control`, `session-state`, `agent-browser`,
  `principles`, `vibecoder-guide`, `workflow-guide`); `session-init` / `session-memory`
  content moved into `skills/session/references/`. Roughly 19.6k lines removed overall.

### Security

- HUD git cache hardened against cross-user symlink clobbering on shared hosts:
  per-user `0700` cache dir under `${XDG_RUNTIME_DIR:-/tmp}`, ownership-validated
  `CHANPARK_HUD_GIT_CACHE` override, atomic `mktemp` + `mv` writes.

## [1.2.2] - 2026-06-25

_Version bump was committed but never tagged or published as a GitHub release;
superseded by 1.3.0._

### Added

- Usage and installation guides; README improvements.

---

Earlier releases (v1.0.0 – v1.2.1) predate this changelog; see the
[GitHub releases](https://github.com/chanp5660/chanpark-harness/releases) and git history.

[Unreleased]: https://github.com/chanp5660/chanpark-harness/compare/v1.3.5...HEAD
[1.3.5]: https://github.com/chanp5660/chanpark-harness/compare/v1.3.4...v1.3.5
[1.3.4]: https://github.com/chanp5660/chanpark-harness/compare/v1.3.3...v1.3.4
[1.3.3]: https://github.com/chanp5660/chanpark-harness/compare/v1.3.2...v1.3.3
[1.3.2]: https://github.com/chanp5660/chanpark-harness/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/chanp5660/chanpark-harness/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/chanp5660/chanpark-harness/compare/v1.2.1...v1.3.0
[1.2.2]: https://github.com/chanp5660/chanpark-harness/compare/v1.2.1...78b87488
