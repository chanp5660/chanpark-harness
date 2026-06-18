# Cursor Review (--cursor) — second-opinion only

A lean mode that runs cursor (composer-2.5-fast) as a **second-opinion** alongside harness-review.
Triggered equivalently when `--cursor` is explicitly specified or when the resolver returns `cursor` (e.g., `HARNESS_IMPL_BACKEND=cursor` / user-scope default ON).

## Invariant Rules

- **cursor does not become the primary reviewer**. The Opus reviewer always runs alongside, and the primary verdict is taken from Opus. cursor output is stored as advisory in `dual_review.cursor_verdict`.
- Rationale: the invariant rule in `harness-work` that "the backend that performed the implementation must not review its own output" (avoid a configuration where code written by the cursor backend is reviewed by the cursor backend).
- cursor is a read-only delegate, so worktree isolation / Lead diff review / cherry-pick / `worker-report.v1` are **not needed**.
- The default-ON determination must always be made via the result of `bash "${HARNESS_PLUGIN_ROOT}/scripts/resolve-impl-backend.sh" --role reviewer`, not by directly reading the `HARNESS_IMPL_BACKEND` env var, to avoid missing project `env.local` / user-scope default / call-site default.

## Mandatory Banner Before Delegation

Before launching the cursor delegate, always output exactly the following literal line:

```
⚠️ cursor review (read-only): model=composer-2.5-fast / R01-R13 are not applied inside cursor-agent / output is untrusted until Lead evaluation
```

## Delegation Command (read-only, no workspace needed)

```bash
HARNESS_PLUGIN_ROOT="${HARNESS_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
if [ -z "$HARNESS_PLUGIN_ROOT" ] && [ -n "${CLAUDE_SKILL_DIR:-}" ]; then
  probe="$(cd "${CLAUDE_SKILL_DIR}" && pwd)"
  while [ "$probe" != "/" ] && [ ! -d "$probe/scripts" ]; do
    probe="$(cd "$probe/.." && pwd)"
  done
  [ -d "$probe/scripts" ] && HARNESS_PLUGIN_ROOT="$probe"
fi
bash "${HARNESS_PLUGIN_ROOT}/scripts/cursor-companion.sh" task "<review prompt>"
```

- **Never** add `--write` (cursor-companion.sh defaults to `--mode ask` = hard read-only stop when `--write` is not specified)
- **Never** add `--workspace` (in read mode, the companion guard does not fire, making it optional and unnecessary)
- **Never** add `--force` / `--yolo` (Cursor officially states "Never use")

Example review prompt structure:

```
Diff review (base_ref={BASE_REF}, head=HEAD):

<key points of git diff or branch range>

Perspectives:
- Spec deviations / out-of-scope changes
- Regression risk in existing tests
- Secret / credential leakage
- Changes to protected paths (settings*, .eslintrc*, tsconfig*.json)

Return verdict as one of APPROVE / REQUEST_CHANGES / NEEDS_INFO.
```

## Trust Boundary (must be maintained even in read mode)

| Item | Content | Location |
|---|---|---|
| Secret blocking | Exclude `.env` / `*.pem` / `*.key` / `.ssh` / `.aws` / `.git` in `.cursorignore` | repo root |
| Egress allowlist | Add `*.cursor.sh` to `sandbox.network.allowedDomains` in `~/.claude/settings.json` | user settings |
| Filesystem allowlist | Add `~/.cursor` to `sandbox.filesystem.allowWrite` in the same file | user settings |
| permissions.json | `terminalAllowlist` / `mcpAllowlist` in `~/.cursor/permissions.json` (best-effort, not a security boundary) | user config |

Cursor officially states: "Allowlists are best-effort convenience. They are not a security guarantee." These 4 points **must be maintained even in read mode**, but do not over-rely on them. The effective boundary is Lead's verdict.

## Verdict Mapping

Store cursor output in `dual_review` with the following schema extension (see `references/dual-review.md`):

```json
{
  "claude_verdict": "APPROVE | REQUEST_CHANGES | NEEDS_INFO",
  "codex_verdict": "approve | needs-attention | unavailable | timeout",
  "cursor_verdict": "APPROVE | REQUEST_CHANGES | NEEDS_INFO | unavailable | timeout",
  "cursor_divergence_notes": "string?"
}
```

- `cursor_verdict` is an **optional field**. It is added only when `--dual` / `--cursor` is specified.
- `cursor_divergence_notes`: Filled in by Lead when Claude/Codex/Cursor verdicts diverge.
- Existing consumers (HTML render / harness-accept, etc.) treat it as optional and do not break the parser.

## Verdict Integration Rules

The primary verdict (Opus reviewer) takes highest priority. cursor / codex are **advisory**:

| Opus | Codex | Cursor | Final verdict |
|---|---|---|---|
| APPROVE | approve | APPROVE | APPROVE (all three agree, highest confidence) |
| APPROVE | approve | REQUEST_CHANGES | APPROVE + cursor_divergence_notes (Opus takes priority; cursor's finding is recorded as an improvement point for the next PR) |
| REQUEST_CHANGES | * | * | REQUEST_CHANGES (if Opus is REQUEST, immediately REQUEST) |
| APPROVE | needs-attention | * | Run TeamAgent Debate (`--team-debate`) |

## Irreversible Guard

Suggested edits from cursor must be **verified in real code before accepting or rejecting** (same contract as the Advisory rule in `codex-closeout.md`). Even if cursor says "this line should be deleted," Lead confirms the diff context and impact before deciding. cursor alone must not trigger commit / push.

## Related

- `.claude/rules/cursor-cli-only.md` — Cursor backend governance + Read mode delegation
- `references/dual-review.md` — Acceptance bar integration for dual / triple review
- `references/governance.md` — Overall review acceptance bar
- `skills/cursor-ask/SKILL.md` — General-purpose read-only delegate (for questions and investigations beyond review)
