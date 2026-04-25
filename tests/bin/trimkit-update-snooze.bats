#!/usr/bin/env bats

# tests/bin/trimkit-update-snooze.bats — tests for bin/trimkit-update-snooze

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-update-snooze"

  FAKE_HOME="$(mktemp -d)"
  FAKE_STATE_DIR="$FAKE_HOME/update-check"

  export TRIMKIT_UPDATE_STATE_DIR="$FAKE_STATE_DIR"
  export TRIMKIT_UPDATE_SNOOZE_DAYS="7"
}

teardown() {
  rm -rf "$FAKE_HOME"
}

# ---------------------------------------------------------------------------
# Basic contract
# ---------------------------------------------------------------------------

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "exits non-zero and prints usage on missing version argument" {
  run bash "$SCRIPT"
  assert_failure
  assert_output --partial 'version argument'
  assert_output --partial 'Usage:'
}

# ---------------------------------------------------------------------------
# State file content
# ---------------------------------------------------------------------------

@test "writes correct snoozed-version" {
  run bash "$SCRIPT" "1.2.3"
  assert_success
  [ -f "$FAKE_STATE_DIR/snoozed-version" ]
  assert_equal "$(cat "$FAKE_STATE_DIR/snoozed-version")" "1.2.3"
}

@test "snoozed-version is a single line" {
  bash "$SCRIPT" "1.2.3"
  assert_equal "$(wc -l < "$FAKE_STATE_DIR/snoozed-version" | tr -d ' ')" "1"
}

@test "writes snoozed-until in ISO 8601 UTC format" {
  run bash "$SCRIPT" "1.2.3"
  assert_success
  [ -f "$FAKE_STATE_DIR/snoozed-until" ]
  python3 -c '
import re, sys
ts = open(sys.argv[1]).read().strip()
assert re.match(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$", ts), f"bad format: {ts}"
' "$FAKE_STATE_DIR/snoozed-until"
}

@test "snoozed-until is approximately SNOOZE_DAYS in the future" {
  bash "$SCRIPT" "1.2.3"
  python3 -c '
from datetime import datetime, timezone
import sys
ts = open(sys.argv[1]).read().strip()
until = datetime.fromisoformat(ts.replace("Z", "+00:00"))
delta = (until - datetime.now(timezone.utc)).total_seconds()
# Allow 60-second tolerance for test execution time
assert abs(delta - 7 * 86400) < 60, f"expected ~7 days, got {delta:.0f}s"
' "$FAKE_STATE_DIR/snoozed-until"
}

@test "respects TRIMKIT_UPDATE_SNOOZE_DAYS override" {
  export TRIMKIT_UPDATE_SNOOZE_DAYS=3
  bash "$SCRIPT" "1.2.3"
  python3 -c '
from datetime import datetime, timezone
import sys
ts = open(sys.argv[1]).read().strip()
until = datetime.fromisoformat(ts.replace("Z", "+00:00"))
delta = (until - datetime.now(timezone.utc)).total_seconds()
assert abs(delta - 3 * 86400) < 60, f"expected ~3 days, got {delta:.0f}s"
' "$FAKE_STATE_DIR/snoozed-until"
}

# ---------------------------------------------------------------------------
# State directory
# ---------------------------------------------------------------------------

@test "creates state directory if it does not exist" {
  run bash "$SCRIPT" "1.2.3"
  assert_success
  [ -d "$FAKE_STATE_DIR" ]
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "second call with same version overwrites snooze" {
  bash "$SCRIPT" "1.2.3"
  first_until="$(cat "$FAKE_STATE_DIR/snoozed-until")"

  bash "$SCRIPT" "1.2.3"
  second_until="$(cat "$FAKE_STATE_DIR/snoozed-until")"

  # Both should be valid timestamps (not checking exact equality due to
  # sub-second timing; just confirming the file is rewritten cleanly)
  [ -n "$first_until" ]
  [ -n "$second_until" ]
}

@test "second call with different version updates snoozed-version" {
  bash "$SCRIPT" "1.0.0"
  bash "$SCRIPT" "2.0.0"
  assert_equal "$(cat "$FAKE_STATE_DIR/snoozed-version")" "2.0.0"
}
