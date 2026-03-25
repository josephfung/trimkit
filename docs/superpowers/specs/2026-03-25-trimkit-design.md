# TrimKit — Claude Code Toolkit

## Purpose

A shareable, testable repository of Claude Code hooks, skills, and settings snippets. Designed as a reference repo that people clone and browse, with an install script for those who want to symlink hooks into their local `~/.claude/` setup.

## Repo Structure

```
TrimKit/
├── hooks/
│   └── no-chaining.sh          # PreToolUse hook: blocks command chaining
├── settings/
│   └── hooks.json              # Reference snippet for wiring hooks into settings.json
├── skills/                     # Future skills (empty for now)
├── tests/
│   ├── test_helper/            # bats-core as git submodule
│   └── hooks/
│       └── no-chaining.bats   # Tests for no-chaining hook
├── install.sh                  # Symlinks hooks/ into ~/.claude/hooks/
├── .github/
│   └── workflows/
│       └── test.yml            # CI: run bats tests on push/PR
├── .gitignore
└── README.md
```

## Components

### hooks/no-chaining.sh

Existing PreToolUse hook that blocks Bash command chaining. Reads JSON from stdin (Claude Code hook protocol), strips quoted strings, then checks for `&&`, `||`, and `|` outside of quotes. Returns `{"continue":false,"stopReason":"..."}` to block, or exits silently to allow.

Known limitations (documented in the script):
- Quote stripping is naive (no escaped/nested quotes)
- Won't catch chaining inside `$()` or backtick subshells
- Blocks legitimate single-command pipes (e.g., `git log | head`)
- Semicolons intentionally excluded due to shell syntax ambiguity

### settings/hooks.json

A reference JSON snippet showing the PreToolUse hook configuration users need to merge into their `~/.claude/settings.json`. Not auto-installed — the install script prints a reminder pointing at this file.

### tests/hooks/no-chaining.bats

bats-core test suite covering:
- Blocks `&&` chaining
- Blocks `||` chaining
- Blocks pipe `|`
- Allows simple commands (no output)
- Allows `&&` inside double quotes
- Allows `&&` inside single quotes
- Allows `2>&1` redirects
- Allows empty/missing command gracefully

### install.sh

Simple symlink installer:
- Creates `~/.claude/hooks/` if needed
- Symlinks each file in `hooks/` into `~/.claude/hooks/`
- Skips files already symlinked to the correct target
- Warns (doesn't overwrite) if a non-symlink file already exists
- Prints summary of actions
- No uninstall — manual `rm` for now

### CI (.github/workflows/test.yml)

- Triggers on push and PR
- Checks out repo with submodules (for bats-core)
- Installs jq
- Runs `bats tests/`

## Testing

- bats-core installed as a git submodule in `tests/test_helper/`
- Each test pipes synthetic JSON into the hook script and asserts on output + exit code
- Dependencies: bash, jq (both available on GitHub Actions runners)

## Future Growth

- More hooks in `hooks/`, tests in `tests/hooks/`
- Skills in `skills/`
- Additional settings snippets in `settings/`
- Install script may evolve to handle skills and settings
- Could become a Claude Code plugin/marketplace package eventually
