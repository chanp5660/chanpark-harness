# Dead-code disposition report — scripts/ + unreachable skills

- **Repo**: /data/chanp5660/chanpark-harness @ master (78b87488, clean)
- **Date**: 2026-07-03 · Task 4.1 (retry) · strictly read-only analysis
- **Scope**: all 158 tracked `scripts/**/*.{sh,py,js}` files, 8 tracked non-script extras under `scripts/`, and the 9 non-invocable skills.

## 1. Method

Reference counting by basename across all live surfaces, resolved one transitive level, with manual verification of every surprising result (referencing line inspected).

```bash
# inventory
git ls-files scripts | grep -E '\.(sh|py|js)$'          # 158 files; 1 duplicate basename: progress-snapshot.sh

# inbound refs per script: live surfaces | other scripts | docs
for f in $(cat files.txt); do b=$(basename $f)
  c=$(grep -rl --exclude-dir=.git -F "$b" hooks/ monitors/ skills/ agents/ templates/ hud/ harness.toml .claude-plugin/ | wc -l)
  s=$(grep -rl -F "$b" scripts/ | grep -v "^$f$" | wc -l)
  d=$(grep -rl -F "$b" README.md PROVENANCE.md CLAUDE.md docs/ | wc -l)
  echo "$f|$c|$s|$d"; done

# Go-binary refs (only hits printed)
for f in $(cat files.txt); do grep -qa -F "$(basename $f)" bin/harness-linux-amd64 && echo "BIN:$f"; done

# hook/monitor ground truth
grep -o 'scripts/[a-zA-Z0-9_/.-]*\.\(sh\|py\|js\)' hooks/hooks.json monitors/monitors.json | sort -u
```

Classification rules:
- **LIVE-direct** — invoked/instructed from hooks.json, the Go binary, or a reachable skill/agent/template/hud file (referencing line verified for every non-obvious case).
- **LIVE-transitive** — referenced only by LIVE scripts (sourced/exec'd), resolved one level.
- **QUESTIONABLE** — referenced only in prose, or only from orphaned/unreachable docs.
- **DEAD** — zero inbound refs, or inbound refs only from other DEAD scripts.

Ground truth confirmed: `hooks/hooks.json` invokes exactly 4 scripts (`hook-handlers/{hud-onboarding-nudge,memory-session-start,posttool-progress-regen}.sh`, `userprompt-inject-policy.sh`); `monitors/monitors.json` invokes only the binary (`harness hook session-monitor`), no scripts. Binary embeds 5 real script names: `check-residue.sh`, `ci/check-consistency.sh`, `session-relay-watch.sh`, `sync-plugin-cache.sh`, `template-tracker.sh` (a 6th hit, `evidence/common.sh`, is a **false positive** — the Go symbol `net/http/internal/httpcommon.sh...`). The binary also references `setup-codex.sh` / `setup-opencode.sh`, which **do not exist in the repo** (pre-existing gap, unchanged by this cleanup).

## 2. Table A — scripts/ verdicts (158 files)

**Totals: 44 LIVE-direct · 15 LIVE-transitive · 2 QUESTIONABLE · 97 DEAD (17,087 lines)**

### LIVE-direct (44)

| Script | Evidence (first referrer) |
|---|---|
| hook-handlers/hud-onboarding-nudge.sh | hooks/hooks.json |
| hook-handlers/memory-session-start.sh | hooks/hooks.json |
| hook-handlers/posttool-progress-regen.sh | hooks/hooks.json |
| userprompt-inject-policy.sh | hooks/hooks.json |
| check-residue.sh | binary (embedded name) |
| session-relay-watch.sh | binary |
| sync-plugin-cache.sh | binary |
| template-tracker.sh | binary |
| ci/check-consistency.sh | binary + skills/harness-work/SKILL.md, agents/worker.md |
| accept-past-issues.sh | skills/harness-accept/SKILL.md (`bash scripts/accept-past-issues.sh ...`) |
| accept-record-decision.sh | skills/harness-accept/SKILL.md |
| auto-checkpoint.sh | skills/harness-work/SKILL.md |
| browser-review-runner.sh | skills/harness-work/SKILL.md |
| build-review-few-shot-bank.sh | agents/reviewer.md |
| check-release-version-sync.py | skills/harness-release/SKILL.md (`python3 ...` invocation) |
| claude-longrun.sh | skills/harness-plan/references/create.md + SKILL.md (documented helper) |
| config-utils.sh | agents/worker.md |
| detect-review-plateau.sh | skills/harness-loop/SKILL.md |
| enable-1h-cache.sh | skills/harness-loop + breezing SKILL.md |
| enrich-sprint-contract.sh | skills/harness-work/SKILL.md + harness-loop |
| ensure-sprint-contract-ready.sh | skills/harness-work + harness-loop SKILL.md |
| generate-browser-review-artifact.sh | skills/harness-work/SKILL.md |
| generate-skill-manifest.sh | skills/harness-plan/SKILL.md |
| generate-sprint-contract.js | skills/harness-plan + harness-loop SKILL.md |
| hook-handlers/elicitation-handler.sh | agents/worker.md |
| hook-handlers/task-completed.sh | skills/breezing/SKILL.md |
| load-cross-project-groups.sh | skills/harness-plan-brief + harness-accept SKILL.md |
| log-tdd-red.sh | skills/harness-work/SKILL.md |
| plan-brief-compile.sh | skills/harness-plan-brief/SKILL.md |
| plan-brief-open.sh | skills/harness-progress + harness-plan-brief SKILL.md |
| plan-brief-record-decision.sh | skills/harness-plan-brief/SKILL.md |
| plan-registry.sh | skills/harness-plan + harness-sync SKILL.md |
| plans-format-migrate.sh | agents/worker.md |
| plans-issue-bridge.sh | skills/harness-plan (SKILL.md + references/create.md) |
| progress-snapshot.sh | skills/harness-progress/SKILL.md (`bash scripts/progress-snapshot.sh`) |
| record-review-calibration.sh | agents/reviewer.md |
| release-preflight.sh | skills/harness-release/SKILL.md |
| render-html.sh | 6 referrers (harness-plan-brief, harness-progress, ...) |
| review-ai-residuals.sh | skills/harness-review + harness-work references/review-loop.md |
| review-weak-supervision-report.sh | skills/harness-review (SKILL.md + references/code-review.md) |
| run-contract-review-checks.sh | skills/harness-work/SKILL.md + harness-loop |
| session-control.sh | skills/session/references/session-control.md (linked from live session SKILL.md:67) |
| sync-skill-mirrors.sh | skills/harness-setup/SKILL.md (`./scripts/sync-skill-mirrors.sh`) |
| write-review-result.sh | skills/harness-work (SKILL.md + references/review-loop.md) |

### LIVE-transitive (15) — keep because a LIVE script sources/invokes them

| Script | Kept alive by |
|---|---|
| path-utils.sh | elicitation-handler.sh, log-tdd-red.sh, task-completed.sh (+21 dead referrers) |
| lib/harness-mem-bridge.sh | hook-handlers/memory-session-start.sh (live hook) |
| lib/relay-store.sh | session-relay-watch.sh (binary-live) |
| session-relay-send.sh | session-relay-watch.sh |
| hook-handlers/webhook-notify.sh | hook-handlers/task-completed.sh |
| lib/terminal-notify.sh | hook-handlers/webhook-notify.sh |
| frontmatter-utils.sh | template-tracker.sh (binary-live) |
| i18n/check-translations.sh | ci/check-consistency.sh (binary-live) |
| check-cch-branch-protection-policy.sh | release-preflight.sh |
| diagnose-harness-skill-duplication.sh | release-preflight.sh |
| model-routing.sh | release-preflight.sh |
| cross-project-audit-log.sh | render-html.sh |
| final-scan-redaction.py | render-html.sh |
| redact-by-dictionary.sh | render-html.sh |
| redact-by-ner.sh | render-html.sh |

### QUESTIONABLE (2) — keep for now, needs a decision

| Script | Situation | Proposed action |
|---|---|---|
| auto-cleanup-hook.sh | 4 refs, all prose/config: skills/maintenance describes it as "The PostToolUse hook", but hooks.json never wires it; templates/hooks/auto-cleanup-hook.sh is an orphaned template copy (nothing installs templates/hooks/) | Either wire it into hooks.json or delete script + template + fix skills/maintenance/SKILL.md:41 and references/cleanup.md |
| session-state.sh | Only refs are skills/{session,session-state}/references/state-transition.md; session/references/state-transition.md is itself orphaned (not linked from session SKILL.md or session-control.md), session-state skill is unreachable | Delete together with the session-state skill and both state-transition.md copies, or link state-transition.md from the live session skill |

### DEAD (97 files, 17,087 lines) — delete candidates

Every file below has zero inbound references from any live surface, or is referenced only by other DEAD scripts (closed dead cluster). Grouped by family; nuances noted.

| Group | Files | Evidence / note |
|---|---|---|
| Unwired hook handlers (24) | hook-handlers/: breezing-signal-injector, ci-status-checker, config-change, elicitation-result, fix-proposal-injector, instructions-loaded, memory-bridge, memory-codex-notify, memory-post-tool-use, memory-stop, memory-user-prompt, notification-handler, permission-denied-handler, post-compact, post-tool-failure, posttool-output-normalize, pre-compact-save.js, runtime-reactive, session-env-setup, stop-failure, stop-session-evaluator, teammate-idle, worktree-create, worktree-remove | Not in hooks.json. **memory-bridge.sh + the 4 memory-* handlers + runtime-reactive.sh appear in sync-plugin-cache.sh's file-copy manifest (lines 161-167) — copy-only, never executed** (the binary implements memory-bridge dispatch natively: `memory-bridge: %s dispatched` string, no `.sh` exec). auto-checkpoint.sh mentions memory-bridge.sh only in a comment (line 18). **Deleting them requires removing the entries from sync-plugin-cache.sh's list** or the cache sync will fail on missing files. |
| Dead session stack (11) | session-{auto-broadcast, broadcast, cleanup, inbox-check, init, list, monitor, register, resume, summary}.sh + reenter-worktree.sh | Closed cluster: session-resume.sh's only live-surface mention is a **comment** in userprompt-inject-policy.sh:340. Everything else references only each other. (session-control.sh and session-relay-{send,watch}.sh are LIVE — different stack.) |
| PreToolUse/PostToolUse/Stop shims (12) | posttooluse-{clear-pending, commit-cleanup, log-toolname, quality-pack, security-review, tampering-detector}.sh, pretooluse-{browser-guide, guard, inbox-check}.sh, stop-{check-pending, cleanup-check, plans-reminder}.sh | 0 refs each; upstream hook wiring was dropped in the transform. |
| ci/ (6) | check-baseline, check-checklist-sync, check-regression-guard, check-template-registry, check-version-bump, diagnose-and-fix | Only inter-referenced by dead ci/diagnose-and-fix.sh. **check-template-registry.sh confirmed NOT wired anywhere (0 refs)** — the "wired by task 5.3" hypothesis is false as of HEAD. check-consistency.sh is LIVE (binary) and stays. |
| evidence/ (5) | common, run-work-all-{case, failure, smoke, success} | Closed cluster; entry point run-work-all-smoke.sh has 0 inbound refs. Binary hit on `common.sh` was a Go-symbol false positive. |
| Telemetry/usage (6) | record-usage.js, usage-tracker.sh, userprompt-track-command.sh, skill-trigger-telemetry.sh, generate-agent-telemetry.js, emit-agent-trace.js | record-usage.js's 4 referrers are all dead. |
| Setup/install (6) | setup-hook.sh, setup-existing-project.sh, quick-install.sh, install-git-hooks.sh, analyze-project.sh, localize-rules.sh | analyze-project.sh referenced only by dead setup-existing-project.sh / localize-rules.sh. |
| Plans/TDD/progress leftovers (8) | plans-watcher.sh, plans-format-check.sh, todo-sync.sh, tdd-order-check.sh, progress-detect-drift.sh, progress-past-judgments.sh, track-changes.sh, calculate-effort.sh | plans-watcher.sh: single **prose** mention (skills/harness-loop/references/flow.md:117, a conditional "If plans-watcher.sh protects..."); recommend rewording that line on deletion. |
| Test/CI helpers (5) | auto-test-runner.sh, detect-test-framework.sh, show-failures.sh, subagent-tracker.sh, validate-release-notes.sh | 0 refs. |
| lib/ + hooks/ + i18n/ (5) | lib/progress-snapshot.sh, lib/relay-notify.sh, lib/run-harness-subcommand.js, hooks/evaluate_subagent_output.sh, i18n/set-locale.sh | lib/progress-snapshot.sh is a **basename collision** with the live top-level progress-snapshot.sh; its only referrers are dead session-init/resume.sh. i18n/check-translations.sh stays (LIVE via binary's check-consistency.sh). |
| Misc (9) | check-simple-mode.sh, fix-symlinks.sh, sync-version.sh, session-monitor.sh*, statusline-harness.sh, permission-request.sh, skill-child-reminder.sh, generate-x-article-image.sh, build-weak-supervision-cues.sh, collect-cleanup-context.sh | *session-monitor.sh counted in session stack above. sync-version.sh also has a known broken bump path (see memory); superseded by manual bumps. statusline-harness.sh superseded by hud/statusline.sh. |

Non-script extras under scripts/ (not in the 158 count):

| File(s) | Verdict |
|---|---|
| scripts/sandbox-test/ (README.md, greeting.ts, greeting.test.ts — 142 lines) | DEAD, delete (0 refs; leftover fixture) |
| scripts/lib/codex-hardening-contract.txt (9 lines) | DEAD, delete (0 refs anywhere) |
| scripts/lib/{advisor-response, agent-trace, elicitation-event, weak-supervision-report} schema JSONs | **KEEP** — not loaded by filename, but they document contracts (`advisor-response.v1`, agent-trace, elicitation-event, weak-supervision-report) actively used by live agents/skills/scripts |

## 3. Table B — the 9 non-invocable skills

All 9 confirmed `user-invocable: false` + `disable-model-invocation: true` (unreachable via Skill tool by both user and model). 23 tracked files, 2,904 lines total.

| Skill (files) | Inbound refs found | Proposed disposition | Consumer impact |
|---|---|---|---|
| session-init (1) | File-linked from live skills/session/SKILL.md:65; prose in templates/rules/{skills-gate:137, memory-integration:31}.md.template | **Move** SKILL.md content into skills/session/references/, update the 3 links | Content is genuinely consumed as a document; deleting without relinking breaks the session skill's table |
| session-memory (1) | File-linked from live skills/session/SKILL.md:66 (agents/reviewer.md:156 hit is a false positive — "in-memory array") | **Move** into skills/session/references/, update link | Same as above |
| session-control (2) | skills/session/references/session-control.md already mirrors its content; prose list session/SKILL.md:186; harness-loop/SKILL.md:260 prose | **Delete** dir (content already duplicated in live session skill) | None if mirror kept |
| session-state (2) | Prose only (session/SKILL.md:187, harness-loop/references/flow.md:179); its references/state-transition.md is mirrored at skills/session/references/state-transition.md but that mirror is orphaned (linked from nowhere) | **Delete** dir; decide fate of scripts/session-state.sh + both state-transition.md copies at the same time (see QUESTIONABLE) | Low; prose lists need a one-line edit |
| ui (5) | README.md:24 lists it; templates/rules/skills-gate.md.template:28 **instructs invoking "ui" via the Skill tool — which would fail** with current flags | **Fix flags** (make model-invocable) OR delete + edit README + skills-gate template. Flag fix is the smaller diff and honors shipped instructions | skills-gate template ships broken guidance today either way until fixed |
| agent-browser (3) | README.md, templates/rules/ui-debugging-agent-browser.md.template, template-registry.json, harness-work/SKILL.md:460 — all refer to the **agent-browser CLI**, not the skill | **Delete** skill dir (CLI docs live in the template); drop the skill from README list | None — verified no reference targets the skill itself |
| principles (5) | PROVENANCE.md only; carries local references/vibecoder-guide.md copy | **Delete** dir | None (PROVENANCE is historical record, not a consumer) |
| vibecoder-guide (1) | PROVENANCE.md; skills/principles/references/vibecoder-guide.md is a **copy**, so principles does not depend on this dir | **Delete** dir | None |
| workflow-guide (3) | PROVENANCE.md only | **Delete** dir | None |

## 4. Summary and risk notes

- **Script delete candidates: 97 files, 17,087 lines** (+ 4 extras: sandbox-test/ 3 files 142 lines, codex-hardening-contract.txt 9 lines → **101 files, ~17,238 lines**).
- **Skill delete candidates: 6 dirs** (session-control, session-state, agent-browser, principles, vibecoder-guide, workflow-guide — 12 files, ~1,700 lines), **2 moves** (session-init, session-memory into skills/session/references/), **1 flag decision** (ui).
- Keep: 44 LIVE-direct + 15 LIVE-transitive scripts, 4 schema JSONs, 2 QUESTIONABLE pending decision.

Risks / ordering (shadow references first):
1. **sync-plugin-cache.sh copy manifest** (lines ~161-167) lists 6 files proposed for deletion (memory-bridge, memory-user-prompt, memory-post-tool-use, memory-stop, memory-codex-notify, runtime-reactive). Edit the manifest in the same commit as the deletions, or cache sync breaks.
2. **skills/harness-loop/references/flow.md:117** mentions plans-watcher.sh — reword when deleting.
3. **skills/maintenance/SKILL.md:41** + references/cleanup.md + templates/.claude-code-harness.config.yaml.template describe auto-cleanup-hook.sh — resolve the QUESTIONABLE decision before touching.
4. **path-utils.sh** stays but loses 21 of 24 referrers; no action needed.
5. Binary-referenced-but-missing setup-codex.sh / setup-opencode.sh: pre-existing gap; nothing in the delete set makes it worse.
6. Deleting session-init/session-memory skill dirs without moving content breaks live skills/session/SKILL.md links (65-66) — do the move, not a plain delete.
7. README.md:23-24 and PROVENANCE.md list several of the 9 skills — update README in the same change; PROVENANCE should record the pruning per repo convention.

## 5. Appendix — exact removal commands (for Lead review, NOT executed)

```bash
# extras
git rm -r scripts/sandbox-test
git rm scripts/lib/codex-hardening-contract.txt

# skills (delete-safe six)
git rm -r skills/session-control skills/session-state skills/agent-browser \
          skills/principles skills/vibecoder-guide skills/workflow-guide

# 97 dead scripts
git rm \
  scripts/analyze-project.sh \
  scripts/auto-test-runner.sh \
  scripts/build-weak-supervision-cues.sh \
  scripts/calculate-effort.sh \
  scripts/check-simple-mode.sh \
  scripts/ci/check-baseline.sh \
  scripts/ci/check-checklist-sync.sh \
  scripts/ci/check-regression-guard.sh \
  scripts/ci/check-template-registry.sh \
  scripts/ci/check-version-bump.sh \
  scripts/ci/diagnose-and-fix.sh \
  scripts/collect-cleanup-context.sh \
  scripts/detect-test-framework.sh \
  scripts/emit-agent-trace.js \
  scripts/evidence/common.sh \
  scripts/evidence/run-work-all-case.sh \
  scripts/evidence/run-work-all-failure.sh \
  scripts/evidence/run-work-all-smoke.sh \
  scripts/evidence/run-work-all-success.sh \
  scripts/fix-symlinks.sh \
  scripts/generate-agent-telemetry.js \
  scripts/generate-x-article-image.sh \
  scripts/hook-handlers/breezing-signal-injector.sh \
  scripts/hook-handlers/ci-status-checker.sh \
  scripts/hook-handlers/config-change.sh \
  scripts/hook-handlers/elicitation-result.sh \
  scripts/hook-handlers/fix-proposal-injector.sh \
  scripts/hook-handlers/instructions-loaded.sh \
  scripts/hook-handlers/memory-bridge.sh \
  scripts/hook-handlers/memory-codex-notify.sh \
  scripts/hook-handlers/memory-post-tool-use.sh \
  scripts/hook-handlers/memory-stop.sh \
  scripts/hook-handlers/memory-user-prompt.sh \
  scripts/hook-handlers/notification-handler.sh \
  scripts/hook-handlers/permission-denied-handler.sh \
  scripts/hook-handlers/post-compact.sh \
  scripts/hook-handlers/post-tool-failure.sh \
  scripts/hook-handlers/posttool-output-normalize.sh \
  scripts/hook-handlers/pre-compact-save.js \
  scripts/hook-handlers/runtime-reactive.sh \
  scripts/hook-handlers/session-env-setup.sh \
  scripts/hook-handlers/stop-failure.sh \
  scripts/hook-handlers/stop-session-evaluator.sh \
  scripts/hook-handlers/teammate-idle.sh \
  scripts/hook-handlers/worktree-create.sh \
  scripts/hook-handlers/worktree-remove.sh \
  scripts/hooks/evaluate_subagent_output.sh \
  scripts/i18n/set-locale.sh \
  scripts/install-git-hooks.sh \
  scripts/lib/progress-snapshot.sh \
  scripts/lib/relay-notify.sh \
  scripts/lib/run-harness-subcommand.js \
  scripts/localize-rules.sh \
  scripts/permission-request.sh \
  scripts/plans-format-check.sh \
  scripts/plans-watcher.sh \
  scripts/posttooluse-clear-pending.sh \
  scripts/posttooluse-commit-cleanup.sh \
  scripts/posttooluse-log-toolname.sh \
  scripts/posttooluse-quality-pack.sh \
  scripts/posttooluse-security-review.sh \
  scripts/posttooluse-tampering-detector.sh \
  scripts/pretooluse-browser-guide.sh \
  scripts/pretooluse-guard.sh \
  scripts/pretooluse-inbox-check.sh \
  scripts/progress-detect-drift.sh \
  scripts/progress-past-judgments.sh \
  scripts/quick-install.sh \
  scripts/record-usage.js \
  scripts/reenter-worktree.sh \
  scripts/session-auto-broadcast.sh \
  scripts/session-broadcast.sh \
  scripts/session-cleanup.sh \
  scripts/session-inbox-check.sh \
  scripts/session-init.sh \
  scripts/session-list.sh \
  scripts/session-monitor.sh \
  scripts/session-register.sh \
  scripts/session-resume.sh \
  scripts/session-summary.sh \
  scripts/setup-existing-project.sh \
  scripts/setup-hook.sh \
  scripts/show-failures.sh \
  scripts/skill-child-reminder.sh \
  scripts/skill-trigger-telemetry.sh \
  scripts/statusline-harness.sh \
  scripts/stop-check-pending.sh \
  scripts/stop-cleanup-check.sh \
  scripts/stop-plans-reminder.sh \
  scripts/subagent-tracker.sh \
  scripts/sync-version.sh \
  scripts/tdd-order-check.sh \
  scripts/todo-sync.sh \
  scripts/track-changes.sh \
  scripts/usage-tracker.sh \
  scripts/userprompt-track-command.sh \
  scripts/validate-release-notes.sh

```
