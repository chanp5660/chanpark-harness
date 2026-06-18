# Skill Routing Rules (Reference)

Reference document for routing rules between skills.

> **SSOT location**: The `description` field of each skill is the SSOT for routing.
> This file is a reference providing detailed explanations and examples; actual routing depends on each skill's description.
>
> **Important**: The description of each skill and the "Do NOT Load For" table in the body must match exactly.

## Codex-Related Routing

### harness-review (includes Codex review functionality)

**Purpose**: Provides second-opinion reviews via Codex CLI (`codex exec`) (integrated from `codex-review` in v3)

**Trigger keywords** (quoted from description):
- "review", "code review", "plan review"
- "scope analysis", "security", "performance"
- "quality checks", "PRs", "diffs"
- "/harness-review"

**Exclusion keywords** (quoted from description):
- "implementation", "new features", "bug fixes"
- "setup", "release"

### harness-work --codex (includes Codex implementation functionality)

**Purpose**: Uses Codex as the implementation engine (integrated in v3)

**Trigger keywords**:
- "implement", "execute", "/work"
- "breezing", "team run"
- "--codex", "--parallel"

**Exclusion keywords** (quoted from description):
- "planning", "code review", "release"
- "setup", "initialization"

**Usage**: Run with `/harness-work --codex`

## Routing Decision Flow (Reference)

> This section explains the internal behavior of Claude Code and does not define additional keywords.
> Actual routing is determined solely by the keywords specified in each skill's description.

```
User input
    │
    ├── Matches trigger keyword in description → load the matching skill
    ├── Matches exclusion keyword in description → exclude the matching skill
    └── Neither → normal skill matching
```

## Priority Rules (Reference)

Priority when a keyword matches multiple skills:

1. **Exclusions take highest priority**: Skills that match an exclusion keyword are never loaded
2. **More specific keywords take priority**: exact match > partial match

> **Note**: "Context-based judgment" is not used as it introduces ambiguity. Routing is determined decisively by the keywords in the description.

## Update Rules

1. **description = SSOT**: The `description` field of each skill is the authoritative definition for routing
2. **Consistency with body**: The "Do NOT Load For" table in each skill must match the description exactly
3. **Role of this file**: A reference for detailed explanations and decision flows (not the SSOT)
4. **Maintain complete lists**: Do not use generic expressions (e.g., "all X-related"); enumerate specific keywords explicitly
