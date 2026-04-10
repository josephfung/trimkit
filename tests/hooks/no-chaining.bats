#!/usr/bin/env bats

# tests/hooks/no-chaining.bats — tests for hooks/no-chaining.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  HOOK="$BATS_TEST_DIRNAME/../../hooks/no-chaining.sh"
}

@test "blocks && chaining" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"cd /tmp && git status\"}}" | bash "$1"' -- "$HOOK"
  assert_output --partial '"continue":false'
}

@test "blocks || chaining" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git pull || echo failed\"}}" | bash "$1"' -- "$HOOK"
  assert_output --partial '"continue":false'
}

@test "blocks pipe |" {
  # Safe npm source but unsafe sink — blocked regardless of source allowlist
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"npm run build | bash\"}}" | bash "$1"' -- "$HOOK"
  assert_output --partial '"continue":false'
  assert_output --partial 'Pipe'
}

@test "allows safe pipe (read-only git | allowlisted filter)" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git log --oneline | head -5\"}}" | bash "$1"' -- "$HOOK"
  assert_output ''
}

@test "allows safe pipe (npm source | allowlisted filter)" {
  # npm commands are allowed as pipe sources when the sink is a safe read-only util
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"npm test | tail -60\"}}" | bash "$1"' -- "$HOOK"
  assert_output ''
}

@test "allows simple command" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git status\"}}" | bash "$1"' -- "$HOOK"
  assert_output ''
}

@test "allows && inside double quotes" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"git commit -m \\\"foo && bar\\\"\"}}" | bash "$1"' -- "$HOOK"
  assert_output ''
}

@test "allows && inside single quotes" {
  # The JSON value contains single quotes around the && — the hook strips them before checking
  run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git commit -m '\\''one && two'\\''\"}}' | bash \"\$1\"" -- "$HOOK"
  assert_output ''
}

@test "allows 2>&1 redirect" {
  run bash -c 'printf "%s" "{\"tool_input\":{\"command\":\"pnpm install 2>&1\"}}" | bash "$1"' -- "$HOOK"
  assert_output ''
}

@test "allows empty command field" {
  run bash -c 'printf "%s" "{\"tool_input\":{}}" | bash "$1"' -- "$HOOK"
  assert_output ''
}

@test "allows missing tool_input" {
  run bash -c 'printf "%s" "{}" | bash "$1"' -- "$HOOK"
  assert_output ''
}
