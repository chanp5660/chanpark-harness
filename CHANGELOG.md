# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/chanp5660/chanpark-harness/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/chanp5660/chanpark-harness/compare/v1.2.1...v1.3.0
[1.2.2]: https://github.com/chanp5660/chanpark-harness/compare/v1.2.1...78b87488
