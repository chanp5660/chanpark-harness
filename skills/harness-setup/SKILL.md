---
name: harness-setup
description: "HAR: Project init, tool setup, agent config, memory setup, skill mirror sync. Trigger: setup, init, new project, CI setup, harness-mem, mirror. Do NOT load for: implementation, review, release, planning."
kind: workflow
purpose: "Initialize and repair Harness project configuration"
trigger: "setup, init, new project, CI setup, harness-mem, mirror"
shape: workflow
role: generator
pair: harness-sync
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Write", "Edit", "Grep", "Glob", "Bash"]
argument-hint: "[init|ci|harness-mem|mirrors|agents|localize]"
user-invocable: true
effort: medium
---

# Harness Setup

The unified setup skill for Harness.
Consolidates the following legacy skills:

- `setup` — unified setup hub
- `harness-init` — project initialization
- `harness-update` — Harness updates
- `maintenance` — file organization and cleanup

## Quick Reference

| Subcommand | Action |
|------------|--------|
| `/harness-setup init` | Initialize a new project (CLAUDE.md + Plans.md + hooks + sync + doctor) |
| `/harness-setup ci` | Configure CI/CD pipeline |
| `/harness-setup harness-mem` | Integrate harness-mem and configure memory |
| `/harness-setup mirrors` | Update the skills/ → public mirror bundle |
| `/harness-setup agents` | Configure agents/ agents |
| `/harness-setup localize` | Localize CLAUDE.md rules |

> **Built-in slash discovery (CC 2.1.108+)**:
> Built-in slash commands like `/init` are also discoverable.
> Use `/harness-setup init` only when Harness-specific bootstrapping is required.

> **Claude Code setup guidance (CC 2.1.120+)**:
> MCP `alwaysLoad`, `${CLAUDE_EFFORT}`, `claude plugin prune`, `claude project purge`,
> `ANTHROPIC_BEDROCK_SERVICE_TIER`, `claude_code.skill_activated.invocation_trigger`,
> Windows PowerShell primary shell, and deferred tools for forked skills / subagents are
> covered in `docs/claude-code-setup-mcp-telemetry-provider.md` as the authoritative source.

## Subcommand Details

### init — Project Initialization

Introduces Harness into a new project.

**Generated files**:
```
project/
├── CLAUDE.md            # project configuration
├── Plans.md             # task management (empty template)
├── .claude/
│   ├── settings.json    # Claude Code settings
│   └── hooks.json       # hook configuration (Go binary)
└── hooks/
    ├── pre-tool.sh      # thin shim (→ core/src/index.ts)
    └── post-tool.sh     # thin shim (→ core/src/index.ts)
```

**Flow**:
1. Detect project type (Node.js/Python/Go/Rust/other)
2. Generate a minimal CLAUDE.md
3. Generate a Plans.md template
4. Place hooks.json
5. **Go binary verification**: Run `harness version` to confirm the binary is available (Node.js is not required since v4.0)
6. **Plugin file sync**: Run `harness sync` to sync files under `.claude-plugin/` to the latest. If `harness.toml` is missing and sync fails, run `harness init` first (recovery path for projects bootstrapped before the Setup hook was introduced)
7. **Health check**: Run `harness doctor` to pass all check items. If issues are found, present remediation steps.
8. **HUD status line (optional)**: Offer to enable the chanpark-harness HUD by running `/chanpark-harness:hud setup`. Mention it is optional and writes the user's global `~/.claude/settings.json` `statusLine`, so only proceed with the user's consent (skip if they already use a custom status line). A SessionStart nudge also surfaces this suggestion until a status line is configured.

### Go Binary Verification

```bash
# Verify binary existence and functionality
harness version
# Example: harness v4.0.0 (go1.22.0, darwin/arm64)
```

Since v4.0, the Harness core engine has migrated to a Go binary.
Node.js is not required. The binary uses `bin/harness` (or `harness` on PATH).

### Plugin File Sync

```bash
# Sync files under .claude-plugin/ to the latest
harness sync

# Preview sync changes only (no modifications)
harness sync --dry-run
```

`harness sync` propagates changes from the SSOT in skills/ to the mirror bundle. Always run this after init.

### Health Check

```bash
# Run all check items
harness doctor
```

`harness doctor` verifies the following:

| Check item | Description |
|------------|-------------|
| Binary | Whether `harness version` returns successfully |
| Plugin configuration | Whether `.claude-plugin/plugin.json` format is correct |
| Hooks placement | Whether hooks exist at the correct paths |
| Mirror sync | Whether skills/ and mirrors are in sync |
| CLAUDE.md | Whether required sections exist |

If issues are detected, remediation commands are presented.

### ci — CI/CD Configuration

Configures GitHub Actions workflows.

```yaml
# Example .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci && npm test
```

### harness-mem — Memory Configuration

Configure Unified Harness Memory.

```bash
# Create memory directories
mkdir -p .claude/agent-memory/chanpark-harness-worker
mkdir -p .claude/agent-memory/chanpark-harness-reviewer

# Place MEMORY.md template
cat > .claude/agent-memory/chanpark-harness-worker/MEMORY.md << 'EOF'
# Worker Agent Memory

## Project Context
[Project overview]

## Patterns
[Learned patterns]
EOF
```

### mirrors — Public Skill Bundle Sync

On Windows with `core.symlinks=false`, repository symlinks become regular files and `harness-*` skills may disappear from the command list. The public bundle is synced as a real-directory mirror.

```bash
./scripts/sync-skill-mirrors.sh
./scripts/sync-skill-mirrors.sh --check
```

Update targets:

- `skills/`

### agents — Agent Configuration

Configure the agents/ setup.

```
agents/
├── worker.md      # implementation agent (task-worker + error-recovery)
└── reviewer.md    # review agent (code-reviewer + plan-critic)
```

### localize — Rule Localization

Adapt the rules under `.claude/rules/` to the current project.

```bash
# Check the list of rules
ls .claude/rules/

# Add project-specific rules
cat >> .claude/rules/project-rules.md << 'EOF'
# Project-Specific Rules
[Project-specific rules]
EOF
```

## Plugin Installation (v2.1.71+ Marketplace)

Marketplace stability was significantly improved in v2.1.71.
The plugin / managed settings policy for Claude Code 2.1.117–2.1.118+ is
covered in `docs/plugin-managed-settings-policy.md` as the authoritative source.

### Recommended Installation Method

```bash
# Pin a version with @ref format (recommended)
claude plugin install owner/repo@v4.0.0

# Latest version
claude plugin install owner/repo
```

The `owner/repo@vX.X.X` format is recommended. With the `@ref` parser fix, tags, branches, and commit hashes are all resolved accurately.

### Updates

```bash
claude plugin update owner/repo
```

The merge conflict during updates was fixed in v2.1.71, enabling stable updates.

### Other Improvements

- MCP server deduplication: automatic prevention of duplicate registration of the same MCP server
- `/plugin uninstall` uses `settings.local.json`: accurately reflected in user-local settings

### Managed marketplace / dependency policy (v2.1.117+)

When controlling the plugin marketplace for enterprise use, use Claude Code's native managed settings.
Harness does not layer its own marketplace resolver or dependency resolver on top.

| Item | Purpose | Harness handling |
|------|---------|------------------|
| `extraKnownMarketplaces` | Guide and register recommended marketplaces for the team | Prefer this for normal onboarding |
| `blockedMarketplaces` | Block specific marketplace sources | Managed settings only; do not include in normal user defaults |
| `strictKnownMarketplaces` | Allow only permitted marketplace sources | Managed settings only; do not include in normal user defaults |
| plugin dependency auto-resolve | Auto install / missing dependency hints for `dependencies` | Delegate to Claude Code core; do not add a Harness-specific resolver |
| plugin `themes/` directory | Plugin distributes a theme | Future task. Harness does not bundle themes |

`DISABLE_AUTOUPDATER` stops automatic updates.
`DISABLE_UPDATES` also stops manual `claude update`, making it suitable for enterprise fixed-version operations.
Neither is included in Harness project defaults; organizations that need them should configure via managed settings or device management.

If a dependency is missing, first check Claude Code's `/plugin` Errors, `/doctor`, and `claude plugin list --json`.
If the cause is an unregistered marketplace, register with `/plugin marketplace add` or `claude plugin marketplace add` and let the core auto-resolve handle it.

## Maintenance — File Organization

Periodic maintenance tasks:

| Task | Command |
|------|---------|
| Delete old logs | `find .claude/logs -mtime +30 -delete` |
| Compress Plans.md | Move completed tasks to an archive section |
| Delete old traces | `tail -1000 .claude/state/agent-trace.jsonl > /tmp/trace && mv /tmp/trace .claude/state/agent-trace.jsonl` |

## Related Skills

- `harness-plan` — Create a project plan after setup
- `harness-work` — Execute tasks after setup
- `harness-review` — Review setup configuration
