#!/usr/bin/env bash
# no-chaining.test.sh — test suite for no-chaining.sh
#
# Tests the PreToolUse hook that blocks command chaining.
# Run with: bash no-chaining.test.sh
#
# Exit code: 0 if all tests pass, 1 if any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$SCRIPT_DIR/no-chaining.sh"

passed=0
failed=0

# ========== Helpers ==========

# Run the hook with the given command string. Captures stdout.
run_hook() {
  local cmd="$1"
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$cmd" | jq -Rs .)" \
    | bash "$HOOK"
}

# Assert that the hook ALLOWS the command (no output, exit 0).
assert_allowed() {
  local desc="$1" cmd="$2"
  local output
  output=$(run_hook "$cmd")
  if [ -z "$output" ]; then
    printf 'PASS  %s\n' "$desc"
    passed=$((passed + 1))
  else
    printf 'FAIL  %s\n      expected: allowed\n      got:      %s\n' "$desc" "$output"
    failed=$((failed + 1))
  fi
}

# Assert that the hook BLOCKS the command (output contains "continue":false).
assert_blocked() {
  local desc="$1" cmd="$2"
  local output
  output=$(run_hook "$cmd")
  if printf '%s' "$output" | grep -qF '"continue":false'; then
    printf 'PASS  %s\n' "$desc"
    passed=$((passed + 1))
  else
    printf 'FAIL  %s\n      expected: blocked\n      got:      %s\n' "$desc" "${output:-<empty>}"
    failed=$((failed + 1))
  fi
}

# ========== && chaining — always blocked ==========

assert_blocked "blocks && chaining" \
  "npm install && npm test"

assert_blocked "blocks && even with safe commands" \
  "git status && git log"

assert_blocked "blocks && in middle of command" \
  "echo foo && echo bar"

# ========== || chaining ==========

assert_blocked "blocks || with unsafe command" \
  "npm install || echo failed"

assert_allowed "allows || between safe read-only commands" \
  "git status || echo nothing"

# ========== Pipes: existing safe read-only utils ==========

assert_allowed "allows pipe between safe read-only utils" \
  "git log --oneline | grep feat"

assert_allowed "allows multi-segment safe pipe" \
  "git log --oneline | grep feat | head -10"

assert_blocked "blocks pipe when source is unsafe (node)" \
  "node script.js | tail -20"

assert_blocked "blocks pipe when source is unsafe (bash)" \
  "bash script.sh | tail -20"

assert_blocked "blocks pipe when sink is unsafe" \
  "git log | xargs rm"

# ========== npm as pipe source: safe subcommands ==========

assert_allowed "allows: npm test | tail" \
  "npm test | tail -60"

assert_allowed "allows: npm t (alias) | tail" \
  "npm t | tail -60"

assert_allowed "allows: npm test | grep" \
  "npm test | grep PASS"

assert_allowed "allows: npm --prefix /path test | tail" \
  "npm --prefix /Users/josephfung/Projects/myapp test | tail -60"

assert_allowed "allows: npm --prefix /path test | grep" \
  "npm --prefix /Users/josephfung/Projects/myapp test | grep PASS"

assert_allowed "allows: npm --prefix /path t | tail" \
  "npm --prefix /Users/josephfung/Projects/myapp t | tail -60"

assert_allowed "allows: npm ls | grep" \
  "npm ls | grep react"

assert_allowed "allows: npm list | grep" \
  "npm list | grep react"

assert_allowed "allows: npm audit | grep" \
  "npm audit | grep high"

assert_allowed "allows: npm outdated | grep" \
  "npm outdated | grep wanted"

assert_allowed "allows: npm view react | grep" \
  "npm view react | grep version"

assert_allowed "allows: npm info react | grep" \
  "npm info react | grep version"

# ========== npm run: safe script names ==========

assert_allowed "allows: npm run test | tail" \
  "npm run test | tail -60"

assert_allowed "allows: npm run lint | grep" \
  "npm run lint | grep error"

assert_allowed "allows: npm run typecheck | tail" \
  "npm run typecheck | tail -40"

assert_allowed "allows: npm run type-check | tail" \
  "npm run type-check | tail -40"

assert_allowed "allows: npm run check | tail" \
  "npm run check | tail -40"

assert_allowed "allows: npm run build | tail" \
  "npm run build | tail -60"

assert_allowed "allows: npm run compile | tail" \
  "npm run compile | tail -60"

assert_allowed "allows: npm run test:unit | tail" \
  "npm run test:unit | tail -60"

assert_allowed "allows: npm run lint:fix applied to tail" \
  "npm run lint:ci | grep error"

assert_allowed "allows: npm --prefix /path run test | tail" \
  "npm --prefix /Users/josephfung/Projects/myapp run test | tail -60"

assert_allowed "allows: npm --prefix /path run lint | grep" \
  "npm --prefix /Users/josephfung/Projects/myapp run lint | grep error"

# ========== npm as pipe source: unsafe subcommands ==========

assert_blocked "blocks: npm install | tail" \
  "npm install | tail -60"

assert_blocked "blocks: npm uninstall | tail" \
  "npm uninstall react | tail -20"

assert_blocked "blocks: npm publish | grep" \
  "npm publish | grep done"

assert_blocked "blocks: npm update | tail" \
  "npm update | tail -60"

assert_blocked "blocks: npm ci | tail" \
  "npm ci | tail -60"

assert_blocked "blocks: npm run deploy | tail" \
  "npm run deploy | tail -20"

assert_blocked "blocks: npm run release | tail" \
  "npm run release | tail -20"

assert_blocked "blocks: npm --prefix /path install | tail" \
  "npm --prefix /path install | tail -60"

assert_blocked "blocks: npm --prefix /path run deploy | tail" \
  "npm --prefix /path run deploy | tail -20"

# ========== npm as pipe source: safe source, unsafe sink ==========

assert_blocked "blocks: npm test piped to xargs" \
  "npm test | xargs rm"

assert_blocked "blocks: npm test piped to bash" \
  "npm test | bash"

# ========== Summary ==========

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
