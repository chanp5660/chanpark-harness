---
name: harness-setup
description: "HAR: Project init, tool setup, agent config, memory setup, skill mirror sync. Trigger: setup, init, new project, CI/Codex setup, harness-mem, mirror. Do NOT load for: implementation, review, release, planning."
kind: workflow
purpose: "Initialize and repair Harness project configuration"
trigger: "setup, init, new project, CI/Codex setup, harness-mem, mirror"
shape: workflow
role: generator
pair: harness-sync
owner: harness-core
since: "2026-05-05"
allowed-tools: ["Read", "Write", "Edit", "Grep", "Glob", "Bash"]
argument-hint: "[init|ci|codex|harness-mem|mirrors|agents|localize]"
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
| `/harness-setup codex` | Install and configure Codex CLI |
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

> **Codex plugin workflows**:
> Do not dual-manage Codex `/goal` and `Plans.md`.
> Plugin-bundled hooks are opt-in, external agent imports require explicit ownership,
> MultiAgentV2 / `agents.max_threads = 8` should be treated as an upper limit,
> and sticky environments / app-server artifacts should default to safe defaults.
> For Codex `0.130.0` stable: `codex remote-control`, large thread pagination,
> selected-environment `view_image`, live app-server config refresh,
> accurate turn diffs, plugin details bundled hooks, and sharing discoverability controls are
> covered in `docs/codex-plugin-workflows-policy.md` as the authoritative source.
> See `docs/codex-plugin-workflows-policy.md` for details.

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

`harness sync` propagates changes from the SSOT in skills/ to each mirror
(codex/.codex/skills/, opencode/skills/). Always run this after init.

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

### codex — Codex CLI Configuration

```bash
# Verify installation (Codex CLI is Node.js-based; separate from Harness itself)
which codex || npm install -g @openai/codex

# Verify timeout command (macOS)
TIMEOUT=$(command -v timeout || command -v gtimeout || echo "")
# On macOS: brew install coreutils
```

> **Note**: The Harness v4.0 core (`harness` command) is a Go binary that does not require Node.js.
> Codex CLI (`codex` command) is a separate tool that still requires Node.js.

### Codex provider / model metadata policy (0.123.0+ / 0.130.0)

The provider / model guidance for Codex `0.123.0`+ and the Bedrock `aws login` guidance for Codex `0.130.0` stable are
covered in `docs/codex-provider-setup-policy.md` as the authoritative source.

Key points:

- When using Bedrock, use the Codex built-in provider `amazon-bedrock`.
- Place the AWS profile in the user / project Codex config under `[model_providers.amazon-bedrock.aws]`.
- AWS console-login credentials from `aws login` profiles are treated as AWS-side profile material.
- Harness does not write AWS credentials, console-login cache, or provider endpoints.
- Harness distributed Codex config does not fix `model = "gpt-5.4"` as the setup default.
- Harness distributed Codex config does not fix `model_provider = "amazon-bedrock"` as the setup default either.
- `gpt-5.4` is treated as current model metadata in Codex itself; do not leave old references like `gpt-5.2-codex` as recommended samples.
- Do not mix the Claude Code-side `CLAUDE_CODE_USE_BEDROCK` / `ANTHROPIC_DEFAULT_*` / `modelOverrides` guidance with Codex's `model_provider = "amazon-bedrock"`.

Only users / projects that use Bedrock need to add the following as required:

```toml
model_provider = "amazon-bedrock"

[model_providers.amazon-bedrock.aws]
profile = "codex-bedrock"
```

For Claude Code-side provider / MCP / telemetry guidance, refer to
`docs/claude-code-setup-mcp-telemetry-provider.md`.
In particular, `ANTHROPIC_BEDROCK_SERVICE_TIER` should only be used in provider environments
for Bedrock users and must not be included in Harness plugin defaults / templates / shared project settings.

### Codex app-server / plugin workflow policy (0.130.0)

The app-server / plugin workflow guidance for Codex `0.130.0` stable (`rust-v0.130.0`, published `2026-05-08T23:09:55Z`) is
covered in `docs/codex-plugin-workflows-policy.md` as the authoritative source.

Key points:

- `codex remote-control` is the explicit launch entrypoint for a headless remotely controllable app-server. Harness setup does not write remote-control defaults to config.
- App-server clients can page large threads. Check the required page range for long loop / Breezing transcripts.
- `view_image` can resolve files via selected environments in a multi-environment session. Include environment / workdir in artifact reports.
- Live app-server threads pick up config changes without restart. However, treat changes to secrets / provider / hook policies with diff and verification.
- Turn diffs stay accurate across `apply_patch` including partial failures. Confirm final state with `git diff` and tests.
- Plugin details now show bundled hooks. Review bundled hooks before install / share, and keep Harness bundled hooks opt-in.
- Plugin sharing exposes link metadata and discoverability controls. Review scope and metadata as a release surface.
- Configurable OpenTelemetry trace metadata is limited to debugging / triage assistance; do not include personal data, customer data, or secrets.
- Built-in MCPs as first-class runtime servers are treated as a Codex runtime-owned surface; do not mix plugin-provided MCP ownership.
- `CODEX_HOME` environments TOML provider is a user-level environment source. Report the selected environment; fix write turns to one primary environment.
- Do not rely on skills list extra roots; explicitly use Harness mirror install or `[[skills.config]]` path-based loading.

### Codex MCP diagnostics / plugin loading (0.123.0+)

The MCP diagnostics / plugin MCP loading guidance for Codex `0.123.0`+ is
covered in `docs/codex-mcp-diagnostics.md` as the authoritative source.

Key points:

- In the Codex TUI, normally use `/mcp` for a lightweight check of server status only.
- Use `/mcp verbose` only when an MCP server is not visible, resources are not listed, or resource templates cannot be read.
- With `/mcp verbose`, check diagnostics / resources / resource templates.
- Assume `.mcp.json` inside a plugin can accept both the `mcpServers` format and the top-level server map format.
- For new plugins, prefer the `mcpServers` format for easier sharing.
- If an existing plugin uses the top-level server map format, leverage Codex's improved loading and avoid unnecessary rewrites.
- Do not mix with Claude Code-side `claude mcp ...`, `.claude/mcp.json`, or hook `type: "mcp_tool"` guidance.

`mcpServers` format:

```json
{
  "mcpServers": {
    "docs": {
      "command": "node",
      "args": ["server.js"]
    }
  }
}
```

Top-level server map format:

```json
{
  "docs": {
    "command": "node",
    "args": ["server.js"]
  }
}
```

### Codex sandbox / execution policy (0.123.0+)

The `remote_sandbox_config` and `codex exec` shared flags guidance for Codex `0.123.0`+ is
covered in `docs/codex-sandbox-execution-policy.md` as the authoritative source.

Key points:

- `remote_sandbox_config` is documented as a host-specific sandbox policy in `requirements.toml`.
- Determine `allowed_sandbox_modes` by comparing per-remote-environment settings such as remote devbox / ephemeral CI runner / shared host.
- Host matching is a convenient classification but not strong device authentication. Avoid broad wildcards in high-risk environments.
- Do not write organization-specific `remote_sandbox_config` into the Harness distributed `codex/.codex/config.toml`.
- Since Codex `0.123.0`, `codex exec` inherits root-level shared flags; do not add duplicate `--approval-policy` / `--sandbox` pairs in the wrapper.
- `scripts/codex-companion.sh task --write` appends `--sandbox workspace-write` to convert the Harness "write task" intent into exec-local form; it is not duplicating root shared flags.
- The `--full-auto` flag in `scripts/codex/codex-exec-wrapper.sh` is retained in 53.2.4. If changing it, add a separate task with regression tests for approval / sandbox behavior.

Requirements example:

```toml
allowed_sandbox_modes = ["read-only"]

[[remote_sandbox_config]]
hostname_patterns = ["devbox-*.corp.example.com"]
allowed_sandbox_modes = ["read-only", "workspace-write"]
```

**Usage pattern** (via official plugin):
```bash
bash scripts/codex-companion.sh task --write "task content"
# or via stdin
cat /tmp/prompt.md | bash scripts/codex-companion.sh task --write
```

## Cursor Implementation Backend Setup (brain: Opus / body: composer)

Steps for using Cursor as an implementation (worker) backend for Harness.
The review / advisor role is fixed to Opus and does not switch to the Cursor backend (Role scope in `.claude/rules/cursor-cli-only.md`).

### 1. AI-executable (persisting the backend selection)

Use `set-impl-backend.sh` to persist the backend. Harness / AI can execute this step.

```bash
# Project scope (write to this project's env.local)
bash "${HARNESS_PLUGIN_ROOT}/scripts/set-impl-backend.sh" cursor

# User scope (shared across all projects: ${HOME}/.config/claude-harness/impl-backend.env)
bash "${HARNESS_PLUGIN_ROOT}/scripts/set-impl-backend.sh" --user cursor

# Display and verify the currently resolved backend
bash "${HARNESS_PLUGIN_ROOT}/scripts/set-impl-backend.sh" --show
```

Resolution priority: project env.local takes precedence over user scope.

### 2. User-manual (AI cannot edit; protected path + sandbox)

The following 3 files cannot be edited by Harness / AI because of `Edit/Write(.claude/settings*)` deny and self-audit guards,
and because `~/.cursor/*` is outside the plugin write scope. The user must configure them manually in a terminal / editor.

- **`~/.cursor/permissions.json`**: Add `terminalAllowlist` / `mcpAllowlist`.
  Use the `~/.cursor/permissions.json` template in `.claude/rules/cursor-cli-only.md`.
  Do not use `--force` / Run Everything (`--yolo`) (officially "Never use" per Cursor docs).
- **`.cursorignore`**: List secrets (`.env`, `*.pem`, `*.key`, `.ssh`, `.aws`, `.git`).
  Use the `.cursorignore` template in `.claude/rules/cursor-cli-only.md`.
- **`~/.claude/settings.json` sandbox (2 items)**: (1) Add `*.cursor.sh` to `network.allowedDomains`,
  (2) Add `~/.cursor` to the official key **`sandbox.filesystem.allowWrite`** (cursor-agent writes state
  to `~/.cursor/projects/...` and `~/.cursor/cli-config.json.tmp` at runtime; without this permission it
  fails with `EPERM`). ⚠️ **The key name is `allowWrite`**: using the name `write` causes it to be
  ignored as an unknown key and the setting has no effect (confirmed empirically). `~/` is expanded
  by the sandbox (as in the official example `["~/.kube"]`).
  With both items in place, execution is possible without per-run sandbox disabling.
  Follow the jq merge recipe in `docs/sandbox-allowlist-recipe.md` and
  the "Sandbox Requirements" section in `.claude/rules/cursor-cli-only.md`.
  Takes effect after a full CC restart.

### 3. Boundaries (cursor remains a candidate)

The Cursor backend has candidate status. Safety is guaranteed not by Cursor's allowlist
(best-effort, bypassable) but by **isolated execution in a worktree with a dedicated `.git` +
diff review by Lead + cherry-pick into the main branch**.
Cursor-agent output is treated as untrusted until reviewed by Lead. See `.claude/rules/cursor-cli-only.md` for details.

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
- `codex/.codex/skills/`
- `opencode/skills/`

### agents — Agent Configuration

Configure the 3-agent setup under agents/.

```
agents/
├── worker.md      # implementation agent (task-worker + codex-implementer + error-recovery)
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
