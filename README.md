# jstack

A collection of Claude Code hooks, skills, and settings snippets. Clone it once and symlink everything into your Claude Code setup so every project benefits from the same guardrails and utilities.

## What's included

**Hooks**

| Hook | Description |
|------|-------------|
| `no-chaining.sh` | Blocks `&&` and `\|\|` command chaining in Bash tool calls, forcing each command to be issued as a separate call |

## Install

```bash
git clone https://github.com/yourusername/jstack.git
cd jstack
./install.sh
```

`install.sh` symlinks the hooks into the right place. After that, merge `settings/hooks.json` into `~/.claude/settings.json` to register the hooks with Claude Code.

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
