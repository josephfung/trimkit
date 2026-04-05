#!/usr/bin/env bats

# tests/install/plugins.bats — tests for plugins/plugins.txt and install.sh plugin logic

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  REPO_ROOT="$BATS_TEST_DIRNAME/../.."
  MANIFEST="$REPO_ROOT/plugins/plugins.txt"
  INSTALL="$REPO_ROOT/install.sh"
}

# ---------------------------------------------------------------------------
# Manifest format
# ---------------------------------------------------------------------------

@test "plugins/plugins.txt exists" {
  [ -f "$MANIFEST" ]
}

@test "plugins/plugins.txt has at least one plugin entry" {
  # Count non-blank, non-comment lines
  count=$(grep -cvE '^\s*(#|$)' "$MANIFEST")
  [ "$count" -gt 0 ]
}

@test "all plugin entries match name@marketplace format" {
  while IFS= read -r line; do
    # Strip inline comments and whitespace
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [ -z "$line" ] && continue

    # Must be word@word (alphanumerics, hyphens, underscores)
    if ! echo "$line" | grep -qE '^[a-zA-Z0-9_-]+@[a-zA-Z0-9_-]+$'; then
      echo "Invalid plugin entry: '$line'"
      return 1
    fi
  done < "$MANIFEST"
}

# ---------------------------------------------------------------------------
# install.sh plugin behaviour — claude CLI present
# ---------------------------------------------------------------------------

@test "install.sh calls claude plugin install for each plugin entry" {
  # Create a temp dir with a mock claude that records invocations
  tmpdir="$(mktemp -d)"
  invocations_file="$tmpdir/invocations"

  # Mock claude: record args, exit 0. Uses INVOCATIONS_FILE from the environment.
  cat > "$tmpdir/claude" <<'EOF'
#!/bin/bash
echo "$@" >> "$INVOCATIONS_FILE"
EOF
  chmod +x "$tmpdir/claude"

  # Count expected plugin entries from manifest
  expected=$(grep -cvE '^\s*(#|$)' "$MANIFEST")

  # Use `env` so INVOCATIONS_FILE is visible inside the mock script
  run env INVOCATIONS_FILE="$invocations_file" PATH="$tmpdir:$PATH" bash "$INSTALL"

  # Each entry should produce one "plugin install <name>" invocation
  actual=0
  [ -f "$invocations_file" ] && actual=$(wc -l < "$invocations_file" | tr -d ' ')

  rm -rf "$tmpdir"

  assert_equal "$actual" "$expected"
}

@test "install.sh passes correct plugin name to claude plugin install" {
  tmpdir="$(mktemp -d)"
  invocations_file="$tmpdir/invocations"

  cat > "$tmpdir/claude" <<'EOF'
#!/bin/bash
echo "$@" >> "$INVOCATIONS_FILE"
EOF
  chmod +x "$tmpdir/claude"

  run env INVOCATIONS_FILE="$invocations_file" PATH="$tmpdir:$PATH" bash "$INSTALL"

  # Every recorded invocation should start with "plugin install"
  if [ -f "$invocations_file" ]; then
    while IFS= read -r call; do
      if ! echo "$call" | grep -q '^plugin install '; then
        rm -rf "$tmpdir"
        echo "Unexpected claude invocation: '$call'"
        return 1
      fi
    done < "$invocations_file"
  else
    rm -rf "$tmpdir"
    echo "No invocations recorded — mock claude was never called"
    return 1
  fi

  rm -rf "$tmpdir"
}

@test "install.sh reports installed plugins in summary" {
  tmpdir="$(mktemp -d)"

  # Mock claude: print nothing (simulate fresh install, no "already installed")
  cat > "$tmpdir/claude" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "$tmpdir/claude"

  PATH="$tmpdir:$PATH" run bash "$INSTALL"

  rm -rf "$tmpdir"

  assert_output --partial 'Plugins installed:'
}

# ---------------------------------------------------------------------------
# install.sh plugin behaviour — claude CLI absent
# ---------------------------------------------------------------------------

@test "install.sh warns and continues when claude CLI is not on PATH" {
  # Run with an empty PATH so claude is definitely not found
  run env -i HOME="$HOME" PATH="/usr/bin:/bin" bash "$INSTALL"

  assert_output --partial 'claude CLI not found'
  # install.sh should still exit successfully (hooks section runs fine)
  assert_success
}
