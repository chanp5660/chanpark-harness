# Verification 6.1 — P7 remaining-English rebuild (v4.16.4 + P1–P7)

Date: 2026-07-08. Verified artifact: `out2/harness-linux-amd64` (go1.25.5, CGO_ENABLED=0,
`-buildvcs=false -ldflags "-s -w -X main.version=4.16.4"`). Built from worktree commit
`50837d5b` ("P7: translate remaining user-facing JP display strings to English", parent
`cae6813d` = P1–P6 boundary, base `c220671e` = v4.16.4) via an isolated `git checkout-index`
snapshot (`out2/build-src/`), so later uncommitted worktree edits cannot leak into the build.
Old binary reference: `/data/chanp5660/chanpark-harness/bin/harness-linux-amd64` (read-only).
Raw logs: `out2/v61/`.

## Artifacts (all mode 0755, version stamp `4.16.4 (Hokage)`)

| File | Size |
|------|------|
| harness-linux-amd64 | 11,604,152 B (ELF x86-64) |
| harness-darwin-amd64 | 11,822,144 B (Mach-O x86_64) |
| harness-darwin-arm64 | 11,208,018 B (Mach-O arm64, DYLDLINK|PIE) |
| harness-windows-amd64.exe | 11,924,992 B (PE32+) |

All four contain the new English strings (`grep -ac 'Fix proposal applied'` = 1 each).
`go test ./...` on the exact build snapshot: **14/14 packages ok, 0 FAIL** (assertions for
intentionally changed strings updated in 6 test files; no test weakened or skipped).

## (a) V8-redo — CJK sweep of the binary: DISPLAY = 0 — PASS

- Total raw CJK chars: **7,918** (was 9,236 on the P1–P6 binary; old repo binary 13,628).
  Composition (full sequence dump `out2/v61/v8-cjk-seqs.txt`, 3,949 uniq sequences):
  Go/x-text unicode normalization tables (random kanji runs, `株式会社`,
  `平成昭和大正明治…`, the katakana units blob `令和アパートアルファ…` — present in every
  Go binary, never emitted) + the PRESERVE-category literals below.
- **Display-category hits: 0.** All 114 JP fragments from the P7 translation rule set
  byte-searched in the binary → 0 present (`out2/v61/v8-display-zero.log`). PROVENANCE
  regression greps `が実行予定|が実装中|がタスクを完了しました|から依頼` = 0; also
  `セッションサマリー|生成完了|反映しました|レビュー承認状態|拒否されました|ブロードキャスト` = 0.
- Preserved literals still present, each mapping to a PROVENANCE category
  (`out2/v61/v8-preserved.log`):
  - **A. marker aliases**: `cc:完了`=2, `pm:依頼中`=2, `pm:確認済`=2, `cursor:依頼中`=2
  - **B. locale=ja branch**: `重要な決定や学習事項…`=1, `…行です（上限…`=3 (auto_cleanup ja args)
  - **C. matcher keywords/regexes**: `個人`/`単独`/`チーム`/`探索`/`触って確認`/`手順固定`
    (AskUserQuestion normalizer), `定義参照診断変更修正実装追加削除移動関数変数`
    (detectIntent keyword pool), `デザイン`/`見た目品質`/`意匠`/`質感`/`画面`/`レイアウト`/
    `セキュリティ`/`権限`/`マイグレーション`/`検証コマンド`/`探索モード`/`探索的`/`定型`/
    `決め打ち`/`依存` (sprint_contract regexes)
  - **E. read-compat**: `アーカイブ`=3 (`📦 アーカイブ`/`## アーカイブ` section detectors)
  - **D. NER/POS `固有名詞`**: 0 in binary — exists only in `scripts/` (out of Go scope);
    `マーカー凡例` likewise appears only in a Go comment, so absent from the binary. Both
    vacuously preserved.
  - Note: yes/no normalizer literals `はい`/`いいえ`/`承認`/`却下` do not appear as contiguous
    rodata bytes because the compiler inlines short string comparisons as immediates; the
    *behavior* is preserved and covered by the passing `parseFixProposalAction` table tests
    (`fix_proposal_injector_test.go` cases `はい`→approve, `却下`→reject).

## (b) Regression of the original 8 checks — 8/8 PASS

1. **Lowercase counting** — sandbox Plans.md with `cc:todo/wip/done/blocked`, `cc:WIP`,
   `cc:完了`, `pm:requested/approved` → `hook session-init` (exit 0):
   `todo 1 / wip 2 / done 2 / blocked 1 / pm-requested 1` (case-insensitive + alias both
   counted). `out2/v61/r1-session-init.json`.
2. **Legend English** — same output: `依頼中|確認済` = 0, any-CJK = 0, legend row
   `` pm:requested` | Requested by PM | Used in 2-agent workflow | `` present.
3. **Sync-safe** — `harness sync` on a fresh repo copy (exit 0): mtime diff shows exactly
   `.claude-plugin/plugin.json` + `.claude-plugin/settings.json` written, **no hooks.json**.
   plugin.json name/version/displayName/defaultEnabled/skills/outputStyles/description/
   keywords all preserved; settings.json byte-identical. Only `author` regenerated from
   `harness.toml [project.author]` (email→url) — the pre-existing SSOT caveat already
   documented in 3.3/repo-edits.md, not a P7 regression.
4. **CI advice** — `ci-cd-fixer` = 0; `chanpark-harness:debugger` = 3.
5. **setup-codex** — `setup-codex.sh` = 0; `setup-opencode.sh` = 0.
6. **TDD English** — live-triggered on a `cc:wip` sandbox + Write of src/main.go:
   `"TDD is enabled by default. Write the test first when possible."` present, 0 CJK, exit 0.
7. **--help identical** — byte-identical to current repo binary `--help` (diff empty), both exit 0.
8. **Hook subcommands** — 9 subcommands with `'{}'` stdin all exit 0 with sane JSON/no-op:
   session-init, memory-bridge, log-toolname, pre-tool (safe-fallback approve),
   stop-evaluator (`[StopSession] 2 WIP task(s) remain…` — English, lowercase counting),
   auto-cleanup (silent), tdd-check, post-compact, plans-watcher. `out2/v61/r8-hooks.log`.

## (c) locale=ja spot check — PASS (preserved behavior)

`hook auto-cleanup` on a 30-line Plans.md with `PLANS_MAX_LINES=10`:
- `CLAUDE_CODE_HARNESS_LANG=ja` → JP warning served (`…が 30 行です（上限: 10行）…`), exit 0.
- default (en) → `Warning: Plans.md has 30 lines (limit: 10)…`, 0 CJK, exit 0.
(The binary resolves locale via config `i18n.language` / `CLAUDE_CODE_HARNESS_LANG`;
`HARNESS_LOCALE` is not an input in this version.)

## Patches

- `out2/binary-rebuild.patch` — combined P1–P7, `git diff c220671e..50837d5b`;
  `git apply --check` against pristine v4.16.4 clean.
- `out2/p7-remaining-english.patch` — standalone P7, `git diff cae6813d..50837d5b`
  (24 files: 21 source + 6 test files overlap-adjusted; 90 replacement rules, 0 mismatches).

## Notes

- Classification of all remaining in-string JP: `out2/p7-classification.md`
  (TRANSLATE: 96 lines/21 files; PRESERVE: 43 lines — A:9, B:6, C:26, E:2, D:0).
- JP comments (2,389 lines, never compiled into the binary) were left as-is: a comment
  translation pass was started via subagents but dropped per coordinator instruction
  (optional). Any uncommitted comment edits in the worktree are NOT in commit `50837d5b`,
  the binaries, or the patches.

## Verdict

| Check | Result |
|-------|--------|
| v8 display JP in binary | PASS (0) |
| lowercase | PASS |
| legend | PASS |
| sync_safe | PASS (known author SSOT caveat only) |
| ci_advice | PASS |
| codex_refs | PASS |
| tdd_english | PASS |
| dispatch_same (--help) | PASS |
| hook subcommands | PASS (9/9 exit 0) |
| ja locale preserved | PASS |
| go test | PASS (14/14 pkgs) |
