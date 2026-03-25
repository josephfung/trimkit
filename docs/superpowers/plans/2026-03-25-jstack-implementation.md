# jstack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Set up the jstack repo with the no-chaining hook, bats tests, install script, settings snippet, CI, and README.

**Architecture:** Flat repo mirroring `~/.claude/` structure. Hooks are bash scripts tested with bats-core (git submodule). Install script symlinks hooks into `~/.claude/hooks/`.

**Tech Stack:** Bash, jq, bats-core, GitHub Actions

---

### Task 1: Add bats-core as git submodule

**Files:**
- Create: `tests/test_helper/bats-core` (submodule)
- Create: `tests/test_helper/bats-support` (submodule)
- Create: `tests/test_helper/bats-assert` (submodule)

bats-assert provides cleaner assertions (`assert_output`, `assert_success`) and depends on bats-support.

- [ ] **Step 1: Add bats-core submodule**

```bash
git -C /Users/josephfung/Projects/jstack submodule add https://github.com/bats-core/bats-core.git tests/test_helper/bats-core
```

- [ ] **Step 2: Add bats-support submodule**

```bash
git -C /Users/josephfung/Projects/jstack submodule add https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
```

- [ ] **Step 3: Add bats-assert submodule**

```bash
git -C /Users/josephfung/Projects/jstack submodule add https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
```

- [ ] **Step 4: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add .gitmodules tests/test_helper/
git -C /Users/josephfung/Projects/jstack commit -m "chore: add bats-core, bats-support, bats-assert as submodules"
```

---

### Task 2: Move no-chaining.sh into the repo

**Files:**
- Create: `hooks/no-chaining.sh` (copy from `~/.claude/hooks/no-chaining.sh`)

The existing `~/.claude/hooks/no-chaining.sh` gets copied into the repo. We don't update the symlink yet — that happens when we test install.sh in Task 6.

- [ ] **Step 1: Copy the hook into the repo**

```bash
cp /Users/josephfung/.claude/hooks/no-chaining.sh /Users/josephfung/Projects/jstack/hooks/no-chaining.sh
```

- [ ] **Step 2: Ensure it's executable**

```bash
chmod +x /Users/josephfung/Projects/jstack/hooks/no-chaining.sh
```

- [ ] **Step 3: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add hooks/no-chaining.sh
git -C /Users/josephfung/Projects/jstack commit -m "feat: add no-chaining hook"
```

---

### Task 3: Write bats tests for no-chaining.sh

**Files:**
- Create: `tests/hooks/no-chaining.bats`

- [ ] **Step 1: Write the test file**

```bash
#!/usr/bin/env bats

# tests/hooks/no-chaining.bats — tests for hooks/no-chaining.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  HOOK="$BATS_TEST_DIRNAME/../../hooks/no-chaining.sh"
}

# --- Should block ---

@test "blocks && chaining" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"cd /tmp && git status\"}}" | "$1"' -- "$HOOK"
  assert_success
  assert_output --partial '"continue":false'
  assert_output --partial '&&'
}

@test "blocks || chaining" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git pull || echo failed\"}}" | "$1"' -- "$HOOK"
  assert_success
  assert_output --partial '"continue":false'
  assert_output --partial '||'
}

@test "blocks pipe" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git log --oneline | head -5\"}}" | "$1"' -- "$HOOK"
  assert_success
  assert_output --partial '"continue":false'
  assert_output --partial 'Pipe'
}

# --- Should allow ---

@test "allows simple command" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git status\"}}" | "$1"' -- "$HOOK"
  assert_success
  assert_output ''
}

@test "allows && inside double quotes" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"git commit -m \\\"foo && bar\\\"\"}}" | "$1"' -- "$HOOK"
  assert_success
  assert_output ''
}

@test "allows && inside single quotes" {
  run bash -c "echo '{\"tool_input\":{\"command\":\"echo '\\''one && two'\\''\"}}' | \"\$1\"" -- "$HOOK"
  assert_success
  assert_output ''
}

@test "allows 2>&1 redirect" {
  run bash -c 'echo "{\"tool_input\":{\"command\":\"pnpm install 2>&1\"}}" | "$1"' -- "$HOOK"
  assert_success
  assert_output ''
}

@test "allows empty command gracefully" {
  run bash -c 'echo "{\"tool_input\":{}}" | "$1"' -- "$HOOK"
  assert_success
  assert_output ''
}

@test "allows missing tool_input gracefully" {
  run bash -c 'echo "{}" | "$1"' -- "$HOOK"
  assert_success
  assert_output ''
}
```

- [ ] **Step 2: Run the tests**

```bash
/Users/josephfung/Projects/jstack/tests/test_helper/bats-core/bin/bats /Users/josephfung/Projects/jstack/tests/hooks/no-chaining.bats
```

Expected: All tests pass.

- [ ] **Step 3: Fix any failing tests and re-run**

Iterate until all tests pass.

- [ ] **Step 4: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add tests/hooks/no-chaining.bats
git -C /Users/josephfung/Projects/jstack commit -m "test: add bats tests for no-chaining hook"
```

---

### Task 4: Write settings snippet

**Files:**
- Create: `settings/hooks.json`

- [ ] **Step 1: Write the settings snippet**

This is a reference file showing what users need to merge into their `~/.claude/settings.json`. It contains just the relevant hook config block — not a full settings file.

```json
{
  "_comment": "Merge this into your ~/.claude/settings.json under hooks.PreToolUse",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/no-chaining.sh",
            "statusMessage": "Checking for command chaining..."
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate it's valid JSON**

```bash
jq . /Users/josephfung/Projects/jstack/settings/hooks.json
```

Expected: Pretty-printed JSON, exit 0.

- [ ] **Step 3: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add settings/hooks.json
git -C /Users/josephfung/Projects/jstack commit -m "docs: add settings snippet for hook wiring"
```

---

### Task 5: Write .gitignore

**Files:**
- Create: `.gitignore`

- [ ] **Step 1: Write .gitignore**

```
.DS_Store
*.swp
*.swo
```

- [ ] **Step 2: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add .gitignore
git -C /Users/josephfung/Projects/jstack commit -m "chore: add .gitignore"
```

---

### Task 6: Write install.sh

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Write the install script**

```bash
#!/bin/bash
# install.sh — Symlink jstack hooks into ~/.claude/hooks/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/hooks"
HOOKS_DST="$HOME/.claude/hooks"

# Track actions for summary
installed=()
skipped=()
warned=()

mkdir -p "$HOOKS_DST"

for hook in "$HOOKS_SRC"/*; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook")"
  dst="$HOOKS_DST/$name"

  if [ -L "$dst" ]; then
    # It's a symlink — check if it points to us
    current_target="$(readlink "$dst")"
    if [ "$current_target" = "$hook" ]; then
      skipped+=("$name (already linked)")
      continue
    fi
  fi

  if [ -e "$dst" ]; then
    # File exists and isn't a symlink to us
    warned+=("$name (exists at $dst, not overwriting)")
    continue
  fi

  ln -sf "$hook" "$dst"
  installed+=("$name")
done

# Summary
echo ""
echo "=== jstack install ==="

if [ ${#installed[@]} -gt 0 ]; then
  echo ""
  echo "Installed:"
  for f in "${installed[@]}"; do echo "  ✓ $f"; done
fi

if [ ${#skipped[@]} -gt 0 ]; then
  echo ""
  echo "Skipped:"
  for f in "${skipped[@]}"; do echo "  - $f"; done
fi

if [ ${#warned[@]} -gt 0 ]; then
  echo ""
  echo "Warnings:"
  for f in "${warned[@]}"; do echo "  ⚠ $f"; done
fi

echo ""
echo "Note: To wire hooks into Claude Code, merge the config from"
echo "  $SCRIPT_DIR/settings/hooks.json"
echo "into your ~/.claude/settings.json"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x /Users/josephfung/Projects/jstack/install.sh
```

- [ ] **Step 3: Test the install script**

Run it. Since `~/.claude/hooks/no-chaining.sh` already exists as a regular file (not a symlink), it should warn and not overwrite.

```bash
/Users/josephfung/Projects/jstack/install.sh
```

Expected output includes a warning for `no-chaining.sh`.

- [ ] **Step 4: Replace the existing hook with the symlink**

Remove the standalone file and re-run install to create the symlink:

```bash
rm /Users/josephfung/.claude/hooks/no-chaining.sh
/Users/josephfung/Projects/jstack/install.sh
```

Expected: `no-chaining.sh` shows as installed.

- [ ] **Step 5: Verify the symlink works**

```bash
echo '{"tool_input":{"command":"cd /tmp && ls"}}' | /Users/josephfung/.claude/hooks/no-chaining.sh
```

Expected: `{"continue":false,"stopReason":"Command chaining detected..."}` — confirming the symlink points to the repo copy.

- [ ] **Step 6: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add install.sh
git -C /Users/josephfung/Projects/jstack commit -m "feat: add install script for symlinking hooks"
```

---

### Task 7: Write CI workflow

**Files:**
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Install jq
        run: sudo apt-get install -y jq

      - name: Run tests
        run: ./tests/test_helper/bats-core/bin/bats tests/
```

- [ ] **Step 2: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add .github/workflows/test.yml
git -C /Users/josephfung/Projects/jstack commit -m "ci: add GitHub Actions workflow for bats tests"
```

---

### Task 8: Write README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

Cover: what jstack is, what's included, how to install, how to run tests, how to add hooks to settings.json. Keep it short.

- [ ] **Step 2: Commit**

```bash
git -C /Users/josephfung/Projects/jstack add README.md
git -C /Users/josephfung/Projects/jstack commit -m "docs: add README"
```

---

### Task 9: Create GitHub repo and push

- [ ] **Step 1: Create private repo on GitHub**

```bash
gh repo create jstack --private --source=/Users/josephfung/Projects/jstack --push
```

- [ ] **Step 2: Verify CI started**

```bash
gh run list --repo josephfung/jstack --limit 1
```

Expected: A workflow run in progress or completed.

- [ ] **Step 3: Report repo URL and CI status**
