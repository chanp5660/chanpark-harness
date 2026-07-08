# P7 classification — remaining in-string Japanese literals (post P1–P6 tree)

Source: `grep -rn '[぀-ヿ一-鿿]' go --include='*.go' | grep -v _test`, refined to
lines where JP occurs inside code (not `//` comments): **139 lines / 24 files**
(full dump: `out2/code-jp-lines.txt`). Comment-only JP lines (2,389) never reach
the binary; comments were additionally translated in touched files only.

## PRESERVE — 43 literals-lines, by PROVENANCE category

### A. Marker alias literals (matched, never displayed) — 9 lines
- internal/session/init.go:187,189 (`cc:完了`, `pm:依頼中`, `cursor:依頼中`)
- internal/session/monitor.go:285,286 (same aliases)
- internal/session/summary.go:235 (`pm:依頼中`, `cursor:依頼中`)
- internal/hookhandler/plans_watcher.go:344,347,349 (`pm:依頼中`, `cursor:依頼中`, `cc:完了`, `pm:確認済`, `cursor:確認済`)
- internal/hookhandler/sprint_contract.go:135 `headingStatusRe` (marker aliases inside regex)

### B. locale=="ja" i18n branches (served only when locale resolves to ja via
`localizedHarnessMessage(locale, en, ja)`; default is en) — 6 lines
- internal/hookhandler/auto_cleanup_hook.go:140,156,158,160,177,191 (ja args of
  checkPlans/checkSessionLog/checkClaudeMd warnings)
- Note: runtime_reactive.go / tdd_order_check.go ja args were already made
  English-mirroring by P1–P6; auto_cleanup keeps genuine ja variants →
  used for the ja-locale spot check (env `CLAUDE_CODE_HARNESS_LANG=ja`).

### C. Input-matching keyword lists / regexes (match user or plan text) — 26 lines
- internal/hookhandler/ask_user_question_normalizer.go:33,34,40,44,45,49
  (`askQuestionCanonicalValues` JP keys → canonical EN values)
- internal/hookhandler/fix_proposal_injector.go:192,194 (yes/no normalizer
  `はい`/`承認`/`いいえ`/`却下`)
- internal/hookhandler/userprompt_inject_policy.go:116,117,118 (`detectIntent`
  semanticKeywords)
- internal/hookhandler/sprint_contract.go:115,118,119,120,122,123,130,131,132,136
  (profile/risk/mode/depends regexes containing JP alternatives; `検証コマンド`
  in runtimeProfileRe at 120 kept — matcher, plus 121,124-129 lines are pure EN)

### D. NER/POS tags (`固有名詞`) — 0 lines (no longer present in Go string
literals; only in scripts/ which are out of P7 scope)

### E. Read-compat header patterns — 2 lines
- internal/hookhandler/auto_cleanup_hook.go:223,224 (`📦 アーカイブ` / `## アーカイブ`
  section detectors in containsArchiveSection; English `Archive` alternative
  already matched on the following line)

Sanity: all five PROVENANCE preserve categories accounted for (D vacuously).

## TRANSLATE — 96 lines / 21 files (user-facing display strings)

- internal/session/summary.go:403,407,409,411 — session-end summary block
- internal/lifecycle/tracker.go:74,88,113,128,140,146,154,162,179,196 — error prose
- internal/event/permission_denied.go:131,132 — [PermissionDenied] notification
- internal/hookhandler/permission_denied_handler.go:135 — same message
- internal/hookhandler/auto_test_runner.go:557,560,563 (bilingual → EN-only),583
- internal/hookhandler/browser_guide.go:11–24 — agentBrowserContext const
- internal/hookhandler/file_lease_hook.go:121 — lease deny reason
- internal/hookhandler/fix_proposal_injector.go:67,75,97,108,122,126,130,139,348–356
- internal/hookhandler/inbox_check.go:60,462,469,477,503 — disclaimer + entries
- internal/hookhandler/posttooluse_commit_cleanup.go:136,143 — [Commit Guard]
- internal/hookhandler/posttooluse_quality_pack.go:235,241,243,246,256,260,264,266,269,288
- internal/hookhandler/session_auto_broadcast.go:206,245
- internal/hookhandler/setup_hook.go:145,177,193,210,212,221,236,262,291,315,333,347,352
- internal/hookhandler/stop_failure.go:139 — [StopFailure] 429 message
- internal/hookhandler/task_completed.go:189 — Progress line
- internal/hookhandler/task_completed_escalation.go:146–158,191–204,225,242,245
- internal/hookhandler/todo_sync.go:104,201
- internal/hookhandler/userprompt_inject_policy.go:254–257,364

Test assertions expecting the old JP strings updated to the new English
(never weakened/skipped).
