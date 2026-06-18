# Quick / Codex Closeout

## In a nutshell

For small changes: fix the target, verify Codex findings in real code, and stop when clean.

## target selection decision tree

1. working tree is dirty
   - Recommended: uncommitted changes only
   - base: `HEAD`
   - include untracked files
2. PR branch / feature branch has commits
   - Recommended: `upstream..HEAD` or `origin/main..HEAD`
   - If working tree is also dirty, use AskUserQuestion to choose "uncommitted changes only / everything / commits only"
3. clean tree with no branch diff
   - Recommended: most recent 1 commit
   - Use most recent 5 commits if needed
4. user specifies `--base` / `--commit`
   - Explicit specification takes priority

## Advisory rule

Codex findings are advisory.
That is, they are reference opinions, not facts in themselves.

Always do the following:

- Read the flagged location in the real code
- Verify reproducibility with the diff and tests
- Separate into accepted findings / rejected findings
- For rejected findings, write "why not adopted"

## Stop-on-clean

stop-on-clean:
Do not add further reviews just for appearance after a clean result.

Example:

- Codex review: no major issues
- focused tests: pass
- manual spot check: pass

Stop at this point.
Additional heavy review is done only before release, for security-sensitive changes, for spec source of truth changes, or when the user explicitly requests it.

## Helper contract

`scripts/harness-review-closeout.sh` is a helper that fixes the execution plan for lightweight closeout.

Supported inputs:

- `--dry-run`
- `--parallel-tests`
- `--base REF`
- `--commit REF`
- `--uncommitted`
- `--test CMD`
- `--json`

Examples:

```bash
bash scripts/harness-review-closeout.sh --dry-run --uncommitted
bash scripts/harness-review-closeout.sh --base origin/main --parallel-tests --test "bash tests/test-harness-review-governance.sh"
bash scripts/harness-review-closeout.sh --commit HEAD --json
```

When Codex is unavailable:

- Fall back to a full manual pass
- Do not treat failure as success
- Leave `codex_available:false` in the final report

## Final report

Required items:

- review command
- tests
- accepted findings
- rejected findings
- clean result
- fallback reason

Minimum JSON representation:

```json
{
  "schema_version": "harness-review-closeout.v1",
  "target": "working_tree | branch_range | commit",
  "base_ref": "HEAD",
  "review_command": "bash scripts/codex-companion.sh review --base HEAD --json",
  "tests": [],
  "accepted_findings": [],
  "rejected_findings": [],
  "clean_result": true,
  "codex_available": true,
  "fallback": ""
}
```
