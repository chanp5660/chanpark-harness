# chanpark-harness — Install Guide

How to install the plugin and the one external dependency the HUD needs (`jq`). Ubuntu/macOS
are usually one-and-done; **Windows needs a few extra checks**, captured below so you don't
have to rediscover them.

> This file is also an installation playbook for assistants/agents doing the setup: follow the
> platform checklist in order before touching the plugin.

---

## Prerequisites at a glance

| Need | Required for | Ubuntu/Debian | macOS | Windows |
|------|--------------|---------------|-------|---------|
| `git` | cloning / marketplace | `apt install git` | `brew install git` | Git for Windows (ships Git Bash) |
| `bash` | HUD status line | built-in | built-in | **Git Bash** (from Git for Windows) |
| `jq`  | HUD status line | `apt install jq` | `brew install jq` | see [Windows jq](#windows-jq) |

The plugin itself needs no Node/Go build — the harness Go binary is pre-committed in `bin/`.
The only runtime dependency you must install yourself is **`jq`**, and only if you want the
full HUD. Without `jq` the HUD degrades to a model-only line; everything else still works.

---

## 1. Install the plugin

This repo is itself a single-plugin marketplace.

```text
# 1. Add this repo as a marketplace
/plugin marketplace add chanp5660/chanpark-harness

# 2. Install the plugin
/plugin install chanpark-harness@chanpark-harness-marketplace

# 3. Reload so the new skills/agents/hooks become active in this session
/reload-plugins

# 4. (optional) scaffold harness files into your project
/chanpark-harness:harness-setup
```

> The command is `/reload-plugins` (hyphen). It reloads plugin manifests, skills, agents, and
> hooks without restarting the session, so commands like `/chanpark-harness:harness-plan`
> become available immediately.

---

## 2. Install `jq` (for the HUD)

### Ubuntu / Debian

```bash
sudo apt update && sudo apt install -y jq
jq --version    # verify
```

### macOS

```bash
brew install jq
jq --version    # verify
```

### Windows {#windows-jq}

On Windows the HUD runs under **Git Bash** (installed with Git for Windows), and `jq` must be
reachable from that Bash shell's `PATH`. This is the part that trips people up — follow the
order below.

**Step 1 — pick ONE installer.** In order of preference:

```powershell
# Option A: winget (built into Windows 10/11, no admin needed for user scope)
winget install jqlang.jq

# Option B: Chocolatey (requires choco already installed + an admin shell)
choco install jq

# Option C: Scoop (user-scope, no admin)
scoop install jq
```

If none are available, do a **manual install**: download `jq-windows-amd64.exe` from
<https://github.com/jqlang/jq/releases>, rename it to `jq.exe`, put it in a folder such as
`C:\Users\<you>\bin`, and add that folder to your PATH (Step 3).

**Step 2 — open a NEW terminal.** PATH changes only apply to shells started *after* the
install. Close and reopen your terminal (and Git Bash / Claude Code) before testing.

**Step 3 — verify it's on PATH, including inside Git Bash:**

```powershell
# In PowerShell:
jq --version
where.exe jq          # shows the resolved path; empty = not on PATH
```

```bash
# In Git Bash (this is the environment the HUD actually uses):
jq --version
which jq
```

If `jq --version` works in PowerShell but **not** in Git Bash, the install location isn't on
the PATH that Git Bash inherits. Fixes, simplest first:

- Restart Git Bash (and Claude Code) so it re-reads the system PATH.
- Confirm the install dir is on the **system/user PATH** (winget user-scope installs to
  `%LOCALAPPDATA%\Microsoft\WinGet\Links`, which is normally added automatically — restarting
  the shell usually resolves it).
- As a last resort, copy `jq.exe` into a directory already on PATH (e.g. Git's
  `C:\Program Files\Git\usr\bin`), or add the dir to PATH via
  *System Properties → Environment Variables → Path*.

**Windows install checklist (do these in order):**

1. Is Git for Windows installed? (`bash --version` in a terminal) — required for the HUD.
2. Install `jq` with exactly one of winget/choco/scoop (don't mix).
3. Open a **new** terminal after installing.
4. `jq --version` works in **PowerShell**.
5. `jq --version` works in **Git Bash** ← the one that actually matters for the HUD.
6. Only then run `/chanpark-harness:hud setup`.

---

## 3. Enable the HUD

Once `jq` is verified:

```text
/chanpark-harness:hud setup     # install + wire the status line (focused preset)
/chanpark-harness:hud status    # report current config / confirm it's active
```

See **[USAGE.md](USAGE.md)** and the README HUD section for what each segment means and the
other presets (`minimal` / `focused` / `full`).

---

## 4. Update the plugin

Bump-and-pull: pull the latest commit (or bump the `version` in
`.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` and re-run
`/plugin marketplace update`). With `version` pinned, Claude Code only updates when the version
changes. After updating, run `/reload-plugins`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| HUD shows only `[Model] (install jq for the full HUD)` | `jq` not found on PATH — see [Windows jq](#windows-jq) / install for your OS |
| New `/chanpark-harness:*` commands don't appear | Run `/reload-plugins` (or restart the session) |
| `jq` works in PowerShell but HUD still bare on Windows | `jq` not on Git Bash's PATH — restart Git Bash, or copy `jq.exe` into `C:\Program Files\Git\usr\bin` |
| Plugin binary "no-ops" | Unsupported platform — only linux-amd64, darwin-amd64, darwin-arm64, windows-amd64 ship pre-built; rebuild from upstream `go/` for others |
