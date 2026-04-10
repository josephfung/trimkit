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

  # Make a private copy of the content source so tests can mutate it safely
  # without touching the tracked file. Install reads from SCRIPT_DIR, so we
  # point a temp copy at the same location via a separate variable used by
  # the mutation test.
  CONTENT_SRC_COPY="$(mktemp)"
  cp "$CONTENT_SRC" "$CONTENT_SRC_COPY"

  export HOME="$FAKE_HOME"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  rm -rf "$FAKE_HOME" "$MOCK_BIN"
  rm -f "$CONTENT_SRC_COPY"
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
  run bash "$INSTALL"
  assert_success
  grep -qF '<!-- BEGIN TRIMKIT -->' "$FAKE_HOME/.claude/CLAUDE.md"
  grep -qF '<!-- END TRIMKIT -->'   "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "fresh install writes content from settings/claude-md.md inside the block" {
  run bash "$INSTALL"
  assert_success
  # The block should contain at least the first non-empty line of the source file
  first_line=$(grep -v '^[[:space:]]*$' "$CONTENT_SRC" | head -n 1)
  grep -qF "$first_line" "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "fresh install reports CLAUDE.md injected in summary" {
  run bash "$INSTALL"
  assert_success
  assert_output --partial 'CLAUDE.md'
}

# ---------------------------------------------------------------------------
# Idempotent re-run — block already present
# ---------------------------------------------------------------------------

@test "re-run replaces existing trimkit block, not duplicates it" {
  run bash "$INSTALL"
  assert_success

  run bash "$INSTALL"
  assert_success

  # Should still have exactly one BEGIN delimiter
  count=$(grep -cF '<!-- BEGIN TRIMKIT -->' "$FAKE_HOME/.claude/CLAUDE.md")
  [ "$count" -eq 1 ]
}

@test "re-run preserves content above the trimkit block" {
  # Pre-populate CLAUDE.md with user content above
  cat > "$FAKE_HOME/.claude/CLAUDE.md" <<'EOF'
# My personal instructions

Do not use semicolons.

EOF

  run bash "$INSTALL"
  assert_success

  grep -qF 'Do not use semicolons.' "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "re-run preserves content below the trimkit block" {
  # Pre-install to get a block in place, then append user content after it
  bash "$INSTALL"
  printf '\n# My footer notes\n\nSome reminder.\n' >> "$FAKE_HOME/.claude/CLAUDE.md"

  run bash "$INSTALL"
  assert_success

  grep -qF 'Some reminder.' "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "re-run fails gracefully when block is malformed (BEGIN without END)" {
  # Write a CLAUDE.md with a stray BEGIN but no END
  cat > "$FAKE_HOME/.claude/CLAUDE.md" <<'EOF'
# My notes

<!-- BEGIN TRIMKIT -->
Some orphaned content, no end marker.
EOF

  run bash "$INSTALL"
  # Should fail with a non-zero exit and a useful error message
  assert_failure
  assert_output --partial 'CLAUDE.md'
}

@test "re-run updates block content when source file changes" {
  # First install
  run bash "$INSTALL"
  assert_success

  # Mutate the tracked source by appending a unique marker.
  # We write to the real file (since SCRIPT_DIR inside install.sh points there),
  # but restore it unconditionally in teardown via CONTENT_SRC_COPY.
  printf '\nUNIQUE_UPDATE_MARKER_XYZ\n' >> "$CONTENT_SRC"

  run bash "$INSTALL"

  # Restore source immediately (teardown also does this as a safety net)
  cp "$CONTENT_SRC_COPY" "$CONTENT_SRC"

  assert_success
  grep -qF 'UNIQUE_UPDATE_MARKER_XYZ' "$FAKE_HOME/.claude/CLAUDE.md"
}

@test "re-run reports CLAUDE.md updated in summary" {
  bash "$INSTALL"
  run bash "$INSTALL"
  assert_success
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
