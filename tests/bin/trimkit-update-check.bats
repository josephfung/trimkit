#!/usr/bin/env bats

# tests/bin/trimkit-update-check.bats — tests for bin/trimkit-update-check

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-update-check"

  FAKE_HOME="$(mktemp -d)"
  FAKE_STATE_DIR="$FAKE_HOME/update-check"
  FAKE_INSTALL_DIR="$FAKE_HOME/trimkit"
  MOCK_BIN="$(mktemp -d)"
  MOCK_CURL_CALLS="$FAKE_HOME/curl-calls"
  MOCK_REMOTE_JSON="$FAKE_HOME/remote.json"

  # Local install: version 0.5.0
  mkdir -p "$FAKE_INSTALL_DIR"
  printf '{"name":"trimkit","version":"0.5.0"}\n' > "$FAKE_INSTALL_DIR/package.json"

  # Remote: same version by default (no update available)
  printf '{"name":"trimkit","version":"0.5.0"}\n' > "$MOCK_REMOTE_JSON"

  # Call-count file — starts empty; mock curl appends one line per call
  touch "$MOCK_CURL_CALLS"

  # Mock curl — outputs $MOCK_CURL_RESPONSE, records each call, honours $MOCK_CURL_EXIT
  cat > "$MOCK_BIN/curl" <<'MOCKCURL'
#!/bin/bash
printf '1\n' >> "${MOCK_CURL_CALLS}"
if [ "${MOCK_CURL_EXIT:-0}" != "0" ]; then
  exit "${MOCK_CURL_EXIT}"
fi
cat "${MOCK_CURL_RESPONSE}"
MOCKCURL
  chmod +x "$MOCK_BIN/curl"

  export PATH="$MOCK_BIN:$PATH"
  export TRIMKIT_UPDATE_STATE_DIR="$FAKE_STATE_DIR"
  export TRIMKIT_UPDATE_INSTALL_DIR="$FAKE_INSTALL_DIR"
  export TRIMKIT_UPDATE_REMOTE_URL="https://fake.example.com/package.json"
  export TRIMKIT_UPDATE_TTL="86400"
  export TRIMKIT_UPDATE_SNOOZE_DAYS="7"
  export MOCK_CURL_CALLS
  export MOCK_CURL_RESPONSE="$MOCK_REMOTE_JSON"
  unset MOCK_CURL_EXIT
}

teardown() {
  rm -rf "$FAKE_HOME" "$MOCK_BIN"
}

# ---------------------------------------------------------------------------
# Basic contract
# ---------------------------------------------------------------------------

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "always exits 0" {
  run bash "$SCRIPT"
  assert_success
}

# ---------------------------------------------------------------------------
# Install-dir detection
# ---------------------------------------------------------------------------

@test "silent when TRIMKIT_UPDATE_INSTALL_DIR is unset and no install-dir file" {
  unset TRIMKIT_UPDATE_INSTALL_DIR
  run bash "$SCRIPT"
  assert_success
  assert_output ''
}

# ---------------------------------------------------------------------------
# Version comparison
# ---------------------------------------------------------------------------

@test "silent when remote version equals local" {
  # Default setup: both 0.5.0
  run bash "$SCRIPT"
  assert_success
  assert_output ''
}

@test "prints notice when remote is newer" {
  printf '{"name":"trimkit","version":"1.0.0"}\n' > "$MOCK_REMOTE_JSON"
  run bash "$SCRIPT"
  assert_success
  assert_output --partial 'trimkit v1.0.0 is available'
  assert_output --partial 'you have v0.5.0'
}

@test "notice includes update command and actual install dir" {
  printf '{"name":"trimkit","version":"1.0.0"}\n' > "$MOCK_REMOTE_JSON"
  run bash "$SCRIPT"
  assert_output --partial 'git pull'
  assert_output --partial 'install.sh'
  assert_output --partial "$FAKE_INSTALL_DIR"
}

@test "silent when remote is older than local" {
  printf '{"name":"trimkit","version":"0.4.0"}\n' > "$MOCK_REMOTE_JSON"
  run bash "$SCRIPT"
  assert_success
  assert_output ''
}

# ---------------------------------------------------------------------------
# TTL cache
# ---------------------------------------------------------------------------

@test "does not call curl when last-checked is within TTL" {
  # Pre-populate cache with current timestamp and a cached version
  mkdir -p "$FAKE_STATE_DIR"
  python3 -c "
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
" > "$FAKE_STATE_DIR/last-checked"
  printf '0.5.0\n' > "$FAKE_STATE_DIR/latest-version"

  run bash "$SCRIPT"
  assert_success

  assert_equal "$(wc -l < "$MOCK_CURL_CALLS" | tr -d ' ')" "0"
}

@test "calls curl when last-checked is absent (first run)" {
  run bash "$SCRIPT"
  assert_success
  assert_equal "$(wc -l < "$MOCK_CURL_CALLS" | tr -d ' ')" "1"
}

@test "calls curl when last-checked is stale" {
  mkdir -p "$FAKE_STATE_DIR"
  printf '2000-01-01T00:00:00Z\n' > "$FAKE_STATE_DIR/last-checked"

  run bash "$SCRIPT"
  assert_success
  assert_equal "$(wc -l < "$MOCK_CURL_CALLS" | tr -d ' ')" "1"
}

@test "uses cached latest-version to show notice without calling curl" {
  # TTL is fresh; cached version is newer
  mkdir -p "$FAKE_STATE_DIR"
  python3 -c "
from datetime import datetime, timezone
print(datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
" > "$FAKE_STATE_DIR/last-checked"
  printf '1.0.0\n' > "$FAKE_STATE_DIR/latest-version"

  run bash "$SCRIPT"
  assert_success
  assert_output --partial 'trimkit v1.0.0 is available'
  assert_equal "$(wc -l < "$MOCK_CURL_CALLS" | tr -d ' ')" "0"
}

@test "writes last-checked after fetch" {
  run bash "$SCRIPT"
  assert_success
  [ -f "$FAKE_STATE_DIR/last-checked" ]
  python3 -c "
from datetime import datetime
ts = open('$FAKE_STATE_DIR/last-checked').read().strip()
datetime.fromisoformat(ts.replace('Z', '+00:00'))  # raises if invalid
"
}

# ---------------------------------------------------------------------------
# Fetch failures
# ---------------------------------------------------------------------------

@test "silent and exits 0 on fetch failure" {
  export MOCK_CURL_EXIT=1
  run bash "$SCRIPT"
  assert_success
  assert_output ''
}

@test "updates last-checked even when fetch fails" {
  export MOCK_CURL_EXIT=1
  run bash "$SCRIPT"
  assert_success
  [ -f "$FAKE_STATE_DIR/last-checked" ]
}

# ---------------------------------------------------------------------------
# Snooze
# ---------------------------------------------------------------------------

@test "writes auto-snooze files after showing notice" {
  printf '{"name":"trimkit","version":"1.0.0"}\n' > "$MOCK_REMOTE_JSON"
  run bash "$SCRIPT"
  assert_success
  [ -f "$FAKE_STATE_DIR/snoozed-version" ]
  [ -f "$FAKE_STATE_DIR/snoozed-until" ]
  assert_equal "$(cat "$FAKE_STATE_DIR/snoozed-version")" "1.0.0"
}

@test "silent during active snooze" {
  printf '{"name":"trimkit","version":"1.0.0"}\n' > "$MOCK_REMOTE_JSON"
  mkdir -p "$FAKE_STATE_DIR"
  printf '1.0.0\n' > "$FAKE_STATE_DIR/snoozed-version"
  python3 -c "
from datetime import datetime, timezone, timedelta
until = datetime.now(timezone.utc) + timedelta(days=7)
print(until.strftime('%Y-%m-%dT%H:%M:%SZ'))
" > "$FAKE_STATE_DIR/snoozed-until"

  run bash "$SCRIPT"
  assert_success
  assert_output ''
}

@test "second run is silent after auto-snooze is written" {
  printf '{"name":"trimkit","version":"1.0.0"}\n' > "$MOCK_REMOTE_JSON"

  # First run: notice shown, snooze written
  bash "$SCRIPT"

  # Second run: snoozed — must be silent
  run bash "$SCRIPT"
  assert_success
  assert_output ''
}

@test "shows notice when snooze has expired" {
  printf '{"name":"trimkit","version":"1.0.0"}\n' > "$MOCK_REMOTE_JSON"
  mkdir -p "$FAKE_STATE_DIR"
  printf '1.0.0\n' > "$FAKE_STATE_DIR/snoozed-version"
  printf '2000-01-01T00:00:00Z\n' > "$FAKE_STATE_DIR/snoozed-until"

  run bash "$SCRIPT"
  assert_success
  assert_output --partial 'trimkit v1.0.0 is available'
}

@test "shows notice when a different (older) version is snoozed" {
  printf '{"name":"trimkit","version":"2.0.0"}\n' > "$MOCK_REMOTE_JSON"
  mkdir -p "$FAKE_STATE_DIR"
  # Snoozed for 1.0.0, but remote is now 2.0.0
  printf '1.0.0\n' > "$FAKE_STATE_DIR/snoozed-version"
  python3 -c "
from datetime import datetime, timezone, timedelta
until = datetime.now(timezone.utc) + timedelta(days=7)
print(until.strftime('%Y-%m-%dT%H:%M:%SZ'))
" > "$FAKE_STATE_DIR/snoozed-until"

  run bash "$SCRIPT"
  assert_success
  assert_output --partial 'trimkit v2.0.0 is available'
}

# ---------------------------------------------------------------------------
# State directory
# ---------------------------------------------------------------------------

@test "creates state directory if it does not exist" {
  run bash "$SCRIPT"
  assert_success
  [ -d "$FAKE_STATE_DIR" ]
}
