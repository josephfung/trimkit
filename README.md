# TrimKit

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange.svg)](https://github.com/josephfung/trimkit)
[![Tests](https://github.com/josephfung/trimkit/actions/workflows/test.yml/badge.svg)](https://github.com/josephfung/trimkit/actions/workflows/test.yml)

A collection of Claude Code hooks, agents, and skills. Clone it once and symlink everything into your Claude Code setup so every project benefits from the same guardrails and utilities.

## What's included

**Hooks**

| Hook | Description |
|------|-------------|
| `no-chaining.sh` | Blocks `&&` and `\|\|` command chaining in Bash tool calls, with an allowlist for safe read-only commands and npm scripts |
| `prod-debug.sh` | Watches migration and compose file writes and prompts Claude to keep prod-debug data files in sync |

**Agents**

| Agent | Description |
|-------|-------------|
| `sysops` | VPS maintenance agent — checks server health and applies updates across registered deployments |

**Skills**

| Skill | Command | Description |
|-------|---------|-------------|
| `sysops` | `/sysops [args]` | Health checks and updates via the sysops agent |
| `prod-debug` | `/prod-debug [args]` | Production debugging with pre-loaded DB schema and container registry |

**Plugins**

`install.sh` also installs a curated set of Claude Code plugins (superpowers, code-review, feature-dev, and more). See [`plugins/plugins.txt`](plugins/plugins.txt) for the full list.

## Install

```bash
git clone https://github.com/josephfung/trimkit.git
cd trimkit
./install.sh
```

The installer:
- Symlinks hooks, agents, and skills into `~/.claude/`
- Merges hook registrations into `~/.claude/settings.json`
- Injects TrimKit hook compatibility tips into `~/.claude/CLAUDE.md`
- Installs plugins via the `claude` CLI (skipped if Claude Code isn't installed yet)

Re-run `./install.sh` at any time to pick up new additions after a `git pull`. Use `./install.sh --upgrade` if you have existing non-symlinked files you want replaced.

## Sysops setup

The sysops agent reads your deployment registry from `~/.claude/sysops/deployments.json`. This file is never committed — it contains SSH connection details for your servers.

Copy the example as a starting point:

```bash
mkdir -p ~/.claude/sysops
cp sysops/deployments.example.json ~/.claude/sysops/deployments.json
# edit to match your actual servers
```

Once the registry exists, use `/sysops` from any Claude Code session:

```
/sysops                        # health report across all deployments
/sysops update Pulse           # apply updates to one server
/sysops update my servers      # apply updates to all servers
/sysops log                    # view recent maintenance history
```

## Run tests

```bash
git submodule update --init --recursive   # one-time setup
./tests/test_helper/bats-core/bin/bats tests/
```
