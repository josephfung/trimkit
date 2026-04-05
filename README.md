# TrimKit

A collection of Claude Code hooks, agents, and skills. Clone it once and symlink everything into your Claude Code setup so every project benefits from the same guardrails and utilities.

## What's included

**Hooks**

| Hook | Description |
|------|-------------|
| `no-chaining.sh` | Blocks `&&` and `\|\|` command chaining in Bash tool calls, forcing each command to be issued as a separate call |

**Agents**

| Agent | Description |
|-------|-------------|
| `sysops` | VPS maintenance agent — checks server health and applies updates across registered deployments |

**Skills**

| Skill | Command | Description |
|-------|---------|-------------|
| `sysops` | `/sysops [args]` | Dispatches to the sysops agent for status checks or maintenance |

## Install

```bash
git clone https://github.com/yourusername/trimkit.git
cd trimkit
./install.sh
```

`install.sh` symlinks hooks, agents, and skills into `~/.claude/`. After that, merge `settings/hooks.json` into `~/.claude/settings.json` to register the hooks with Claude Code.

## Sysops setup

The sysops agent reads your deployment registry from `~/.claude/sysops/deployments.json`. You need to create this file yourself — it contains SSH connection details for your servers and is never committed anywhere.

Copy the example as a starting point:

```bash
mkdir -p ~/.claude/sysops
cp sysops/deployments.example.json ~/.claude/sysops/deployments.json
# edit to match your actual servers
```

Once the registry exists, use `/sysops` from any Claude Code session:

```
/sysops             # health report across all deployments
/sysops status      # same as above
/sysops update Pulse           # apply updates to one server
/sysops update my servers      # apply updates to all servers
```

## Run tests

Install the bats test helpers (one-time):

```bash
git submodule update --init --recursive
```

Run the suite:

```bash
./tests/test_helper/bats-core/bin/bats tests/
```

## Adding hooks

1. Add your shell script to `hooks/`
2. Write tests in `tests/hooks/`
3. Add the corresponding settings snippet to `settings/`

## Adding agents

1. Add your agent definition to `agents/` (a single `.md` file)
2. Document it in this README

## Adding skills

1. Add a directory to `skills/<skill-name>/` containing `SKILL.md`
2. Document it in this README
