# Planning Quality Contract — harness-plan Standard Flow

`harness-plan` does not directly convert user-provided information into a work table.
For plan creation or significant task additions, it filters through the latest information, existing specs, memory, and multi-perspective discussion via TeamAgent / sub-agents,
and converts only the elements that should be incorporated into this product into Plans.md task contracts.

This is not a standalone subcommand. It is the standard quality gate for `create` and high-impact `add` operations.

## Step 0: Applicability Decision

Use this quality contract when any of the following apply:

- Creating a new plan with `create`
- Adding tasks via `add` that affect product behavior / APIs / data models / permissions / billing / external integrations / distribution surfaces
- User provides external products, competitors, specs, improvement proposals, or comparison materials
- There is a potential conflict with existing specs, Plans.md, memory, or past decisions
- User requested "maximum firepower", "thorough comparison", "neutral scoring", or "regression prevention"
- Not a one-off or trivial task — affects multiple tasks / multiple files / multiple sessions / product behavior / APIs / data models / permissions / billing / external integrations / distribution surfaces / security

For `create` and product-impacting `add`, read root `spec.md` every time.
Only fall back to existing project spec / `docs/spec/00-project-spec.md` when the consumer repo has no root `spec.md`.
Output must always include either `Spec delta` or `Spec skip reason`.
This is the co-required planning output contract; precedence remains `spec.md > sub-spec > Plans.md`.

Non-trivial planning requires TeamAgent or sub-agent verification as a prerequisite.
When the Task tool is available, always run independent perspectives.
When unavailable, explicitly state `sub-agent not used` and evaluate the same perspectives separately.
Output must always include `team_validation_mode`.

| mode | When to use |
|------|-------------|
| `not_required_lightweight` | Lightweight tasks: typo / format / README / CHANGELOG / marker update / status sync |
| `native` | Used TeamAgent or equivalent runtime-native multi-perspective verification |
| `subagent` | Used Task sub-agents per perspective |
| `manual-pass` | Runtime where Task is unavailable; evaluated same perspectives separately |
| `unavailable` | Cannot verify. Must not mark non-trivial work as Required |

The following may be treated lightly:

- `update` for marker-only changes
- `sync` for status reconciliation only
- typo / format / README / CHANGELOG only
- Narrow changes where existing specs and tests already fix the correct answer

## Step 1: Input Decomposition

Break down the user-provided information into the following 4 categories:

| Category | Examples |
|----------|---------|
| Subject to evaluate | External products, competitor features, spec proposals, design approaches, operational plans |
| User's intent | What they want to improve, what they want to avoid |
| Uncertain facts | Recency, pricing, APIs, constraints, competitive landscape, existing repo state |
| Evidence needed for adoption decision | Official docs, actual measurements, existing specs, memory, test results |

Do not stop to ask questions when there are unknowns. Evaluate the reasonably assumed intent first; only present "decision branches" when judgment is truly split.

## Step 2: Retrieve Latest Information

Use WebSearch when external facts are involved. Priority order:

1. Official documentation, official blog, release notes, GitHub repo
2. Standards, papers, technical sources close to primary information
3. Reliable comparison articles, case studies, issues / discussions

Verify important facts with 2 or more sources when possible.
When there are contradictions, clarify which points conflict and explicitly state the impact on the adoption decision.

If WebSearch is unavailable or the network fails, handle as follows:

- `Latest info: unverified`
- Provide a provisional assessment based on local evidence only
- Explicitly note "Web verification still needed here" in the final output

## Step 3: Verify Local Authoritative Sources

Any proposal to incorporate into the product must be cross-checked against existing authoritative sources.

Minimum required checks:

```bash
cat Plans.md
rg -n "related-keyword" README.md README_ja.md CLAUDE.md docs skills scripts tests
rg -n "\"(lint|format)\"|eslint|prettier|biome|oxlint|dprint|ruff|black|isort|gofmt|go vet|cargo fmt|cargo clippy" package.json pyproject.toml go.mod Cargo.toml Makefile .github/workflows scripts docs 2>/dev/null
find docs -maxdepth 3 -type f | sort
git status --short --branch
```

Review perspectives:

- Does it contradict existing product promises?
- Does it contradict existing skill role / trigger / allowed-tools?
- Does it conflict with incomplete tasks in Plans.md?
- Does it affect distribution mirrors, i18n?
- If a spec authoritative source exists, should it be updated before Plans.md?
- Are root `spec.md` product contract and Plans.md task contract kept separate?
- For plans with source code changes, is there a lint / formatter baseline? If not, is a setup task needed before implementation?

## Step 4: Memory Check

When harness-mem, harness-recall, or local memory files are available, check past decisions with relevant keywords.
When searchable, scope to the current project / repo. Cross-project search is only used when the user explicitly requests it.
This step is a reinvention-prevention check and must not be skipped for non-trivial planning.

Examples of what to check:

- harness-mem / harness-recall search results
- `.claude/agent-memory/`
- `.claude/state/memory-bridge-events.jsonl`
- Whether `.harness-mem/` exists
- Prior decisions recorded in repo docs / Plans.md

Notes:

- Do not assume you can read the harness-mem DB directly
- If harness-mem is not set up, unhealthy, or unsearchable, explicitly state "memory not checked"
- Memory is weaker than the current repo state. When old memory conflicts with git / docs, prioritize the current repo state
- Do not assert absent for things not visible in memory or search. `not_observed != absent`

## Step 5: Sub-agent Discussion

For non-trivial planning, assume TeamAgent or Task sub-agents are required.
When the Task tool is available, run at least 3 independent perspectives. Instruct each agent to work "read-only", "evidence-based", and "conclusion-first".
Only explicitly skip this step for one-off, trivial tasks.
Product / Strategy, Architecture / Implementation, Security / Abuse, QA / Regression, and Skeptic are perspective names, not agent_type names.
Pass them as perspectives to available TeamAgent / Task sub-agents.
Do not demand arbitrary agent spawning.

Standard roles:

| Role | Purpose |
|------|---------|
| Product / Strategy | Evaluate adoption value, differentiation, user value, opportunity cost |
| Architecture / Implementation | Evaluate implementation feasibility, alignment with existing design, maintenance burden |
| Security / Abuse | Evaluate permissions, secrets, prompt injection, supply chain, external transmission risks |
| QA / Regression | Evaluate regression, testing, distribution mirrors, compatibility, whether it actually works |
| Skeptic | Attack reasons not to adopt, over-investment, and ambiguous premises |

What each agent output must include:

- Adopt / Conditional adopt / Reject
- Rationale
- Largest risk
- What else to verify
- Conflicts with existing specs or memory
- DoDs to reflect in test / smoke / CI / review / release gates

How to synthesize the discussion:

1. Extract points of agreement
2. Retain points of disagreement
3. Provide your own judgment
4. Classify as Required / Recommended / Optional / Reject

When sub-agents are unavailable, explicitly evaluate the same 5 perspectives separately on your own and write `sub-agent not used`.

## Step 5.5: Implementation Plan Verification Gate

Do not mark an implementation plan as Required until all 5 of the following are satisfied:

| Gate | What to check | If it fails |
|------|--------------|-------------|
| Spec / Plans Fit | Does not contradict the order of root `spec.md`, sub-spec, `Plans.md` | Output `Spec delta` first or Reject |
| Memory / Wheel Check | No similar decisions or existing tasks in harness-mem / harness-recall / repo memory | Reuse existing proposal, only task-ify the delta |
| Product Fit | Directly tied to product purpose and primary user workflow | Escape to docs / external workflow / Optional |
| Security Fit | Does not weaken permissions, secrets, external transmission, dependency, or branch/release gates | spike / security task / Reject |
| Quality Baseline Fit | For source code changes, can quality be Yes/No evaluated with lint / formatter / CI commands | Add setup task first, or leave a formatter_baseline skip reason |
| Works In Practice | Can test / smoke / CI / review / release closeout be Yes/No evaluated | Rewrite the DoD |

This gate is a "pre-process to reduce rework," not a sentiment review.
A failing gate must always be reflected in Plans.md DoDs, Depends, or `[needs-spike]`.
Quality Baseline Fit is not an excuse to carelessly add formatters or linters.
For plans that include source code changes with no baseline set, place a setup task before implementation tasks.
The setup task DoD must include 3 elements: config, package script / CI command, and validation command.
Do not install packages during planning. Installation is performed by harness-work as a setup task.
Broad bulk reformatting should only be performed when the user explicitly requests it or it falls within the setup task scope.
Security Fit does not require actually reading secrets.
If reading `.env`, tokens, private keys, or customer data would become necessary, stop it as a Risk Gate.
Verify using surfaces that do not read secret values: existing guardrails, config shapes, audit evidence, tests, GitHub / CI metadata.

## Step 6: Neutral Scoring Review

Scoring is on a 5-point scale. 5 is strong, 1 is weak.

| Axis | 5 | 3 | 1 |
|------|---|---|---|
| Product Fit | Directly tied to the core of the target product | Convenient but peripheral | Another product or operation would suffice |
| Evidence Strength | Primary sources + actual measurements + existing evidence | Only one side verified | Mostly speculation |
| User Value | Significantly improves decision quality or execution speed | Effective in some workflows | Slim perceived value |
| Implementation Feasibility | Small and localized | Medium-scale but manageable | Large-scale, high maintenance burden |
| Regression Safety | Low risk and testable | Has impact area | Likely to break existing flows |
| Strategic Leverage | Becomes a long-term differentiator | Stops at a convenience feature | One-off |
| Security Safety | Does not weaken permissions or secrets, verifiable | Has caveats | Dangerous permission relaxation or unverified external transmission |
| Works In Practice | Demonstrable with smoke / CI / review | Mostly manual verification | Confirmation of operation is ambiguous |

Correction rules:

- If Evidence Strength is 2 or below, Required is forbidden
- If Regression Safety is 2 or below, place a spike / spec / test first
- If Security Safety is 2 or below, Required is forbidden
- If Works In Practice is 2 or below, rewrite the DoD or fall to spike
- If Quality Baseline Fit is 2 or below and source code changes are included, make formatter_baseline setup task a Required dependency
- If Implementation Feasibility is 2 or below and User Value is 3 or below, lean toward Reject
- If Product Fit is 2 or below, move it out of this product into docs / external workflow

## Step 7: `$easy` Report

The final output does not present the raw difficult evaluation — convert it into a form that enables a decision.

Required structure:

```markdown
In a word:
{{adoption decision in 1 sentence}}

Scoring review:
| Proposal | Score | Decision | Rationale | Unverified |
|----------|-------|----------|-----------|------------|

Proposals to incorporate:
| Priority | Proposal | Reason | Expected outcome |
|----------|----------|--------|-----------------|

Regression check:
- team_validation_mode:
- spec:
- Plans.md:
- harness-mem / memory:
- TeamAgent / sub-agent:
- product fit:
- security:
- works in practice:
- formatter_baseline:
- mirror / distribution:
- test:

Next steps:
1. ...
2. ...
3. ...
```

Style rules:

- Put the conclusion first
- Translate technical terms concisely
- Do not make judgments based on vague praise like "amazing" or "innovative"
- Limit proposals to 1–3. Do not list too many candidates
- Separate facts, speculation, and unverified items

## Step 8: Converting to Plans.md / spec

Convert only the accepted proposals into the task contract.

Order:

1. Read root `spec.md`; if needed, update the product contract first as a `Spec delta`
2. If source code changes are included and lint / formatter baseline is not set, place formatter_baseline setup task as a Required dependency first
3. Add only Required tasks to Plans.md
4. Attach `[needs-spike]` to high-risk proposals
5. Place a verifiable DoD on each task
6. Attach `[tdd:required]` to tasks that require TDD
7. For tasks affecting mirror / i18n / package surfaces, place a separate verification task
8. If spec update is not needed, leave `Spec skip reason` in the task context / sprint contract
9. For non-trivial planning, leave TeamAgent / sub-agent verification results, or `sub-agent not used` fallback and 5-gate results, in the task context
10. Do not mark `team_validation_mode: unavailable` plans as Required. Only allow `not_required_lightweight` for lightweight tasks

`Spec delta` is drafted by the agent. Do not assume the user will write the spec from scratch.
`Spec delta` / `Spec skip reason` are generated by Harness; the consumer only approves or revises them.

Prohibited:

- Creating only implementation tasks when the correct conditions of the spec are still in flux
- Treating regression checks as a "caution" note instead of turning them into tasks
- Creating only implementation tasks while ignoring an absent lint / formatter baseline when source code changes are included
- Omitting `Spec skip reason` for docs-only / mechanical tasks
