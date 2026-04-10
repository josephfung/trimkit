#!/usr/bin/env bats

# tests/install/claude-md.bats — tests for CLAUDE.md injection in install.sh

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  INSTALL="$REPO_ROOT/install.sh"
  CONTENT_SRC="$REPO_ROOT/settings/claude-md.md"

  # Run install in an isolated HOME so we never touch the real ~/.claude/CLAUDE.md
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "$FAKE_HOME/.claude"

  # Suppress plugin install by providing a mock claude that does nothing
  MOCK_BIN="$(mktemp -d)"
  cat > "$MOCK_BIN/claude" <<'EOF'
#!/bin/bash
echo "already installed"
EOF
  chmod +x "$MOCK_BIN/claude"

  export HOME="$FAKE_HOME"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$FAKE_HOME" "$MOCK_BIN"
}

# ---------------------------------------------------------------------------
# Content source file
# ---------------------------------------------------------------------------

@test "settings/claude-md.md exists in the repo" {
  [ -f "$CONTENT_SRC" ]
}

@test "settings/claude-md.md is non-empty" {
  [ -s "$CONTENT_SRC" ]
}

# ---------------------------------------------------------------------------
# Fresh install — CLAUDE.md does not exist yet
# ---------------------------------------------------------------------------

@test "fresh install creates ~/.claude/CLAUDE.md" {
  run bash "$INSTALL"
  assert_success
  [ -f "$FAKE_HOME/.claude/CLAUDE.md" ]
}

@test "fresh install writes BEGIN/END delimiters" {
  bash "$INSTALL"
  grep -qF '<!-- BEGIN TRIMKIT -->' "$FAKE_HOME/.claude/CLAUDE.md"
  grep -qF '<!-- END TRIMKIT -->'   "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "fresh install writes content from settings/claude-md.md inside the block" {
  bash "$INSTALL"
  # The block should contain at least the first non-empty line of the source file
  first_line=$(grep -v '^[[:space:]]*$' "$CONTENT_SRC" | head -n 1)
  grep -qF "$first_line" "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "fresh install reports CLAUDE.md injected in summary" {
  run bash "$INSTALL"
  assert_output --partial 'CLAUDE.md'
}

# ---------------------------------------------------------------------------
# Idempotent re-run — block already present
# ---------------------------------------------------------------------------

@test "re-run replaces existing trimkit block, not duplicates it" {
  # First install
  bash "$INSTALL"

  # Second install
  bash "$INSTALL"

  # Should still have exactly one BEGIN delimiter
  count=$(grep -cF '<!-- BEGIN TRIMKIT -->' "$FAKE_HOME/.claude/CLAUDE.md")
  [ "$count" -eq 1 ]
}

@test "re-run preserves content outside the trimkit block" {
  # Pre-populate CLAUDE.md with user content above and below
  cat > "$FAKE_HOME/.claude/CLAUDE.md" <<'EOF'
# My personal instructions

Do not use semicolons.

EOF

  bash "$INSTALL"

  # User content should still be present
  grep -qF 'Do not use semicolons.' "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "re-run updates block content when source file changes" {
  # First install
  bash "$INSTALL"

  # Simulate source file update by temporarily writing a unique marker
  original=$(cat "$CONTENT_SRC")
  printf '%s\n\nUNIQUE_UPDATE_MARKER_XYZ\n' "$original" > "$CONTENT_SRC"

  bash "$INSTALL"

  # Restore source
  printf '%s\n' "$original" > "$CONTENT_SRC"

  grep -qF 'UNIQUE_UPDATE_MARKER_XYZ' "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "re-run reports CLAUDE.md updated in summary" {
  bash "$INSTALL"
  run bash "$INSTALL"
  assert_output --partial 'CLAUDE.md'
}

# ---------------------------------------------------------------------------
# --upgrade flag
# ---------------------------------------------------------------------------

@test "--upgrade also injects CLAUDE.md" {
  run bash "$INSTALL" --upgrade
  assert_success
  [ -f "$FAKE_HOME/.claude/CLAUDE.md" ]
  grep -qF '<!-- BEGIN TRIMKIT -->' "$FAKE_HOME/.claude/CLAUDE.md"
}
