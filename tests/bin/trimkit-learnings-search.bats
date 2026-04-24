#!/usr/bin/env bats

# tests/bin/trimkit-learnings-search.bats — tests for bin/trimkit-learnings-search

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-learnings-search"
  TMPDIR_CUSTOM="$(mktemp -d)"
  export TRIMKIT_SYSOPS_LEARNINGS_DIR="$TMPDIR_CUSTOM"
  export TRIMKIT_SYSOPS_LEARNINGS_FILE="$TMPDIR_CUSTOM/learnings.jsonl"
}

teardown() {
  rm -rf "$TMPDIR_CUSTOM"
}

# Write a learning entry directly to the file (bypassing trimkit-learnings-log
# so these tests don't depend on the other script).
write_entry() {
  printf '%s\n' "$1" >> "$TRIMKIT_SYSOPS_LEARNINGS_FILE"
}

ENTRY_PULSE_A='{"ts":"2026-04-10T10:00:00Z","deployment":"Pulse","key":"caddy-restart","type":"quirk","insight":"Caddy needs restart after upgrade.","confidence":0.9,"source":"observed"}'
ENTRY_PULSE_B='{"ts":"2026-04-11T10:00:00Z","deployment":"Pulse","key":"caddy-restart","type":"quirk","insight":"Caddy restart confirmed again.","confidence":0.95,"source":"observed"}'
ENTRY_CURIA='{"ts":"2026-04-10T11:00:00Z","deployment":"Curia","key":"postgres-slow-start","type":"quirk","insight":"Postgres takes ~30s to accept connections after reboot.","confidence":0.8,"source":"observed"}'

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "exits 0 with no output when learnings file does not exist" {
  run bash "$SCRIPT"
  assert_success
  assert_output ""
}

@test "outputs all entries when no filter given" {
  write_entry "$ENTRY_PULSE_A"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT"
  assert_success
  # Two distinct keys → two output lines
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "2"
}

@test "deduplicates by key — latest entry wins" {
  # Write the same key twice; second entry should supersede the first
  write_entry "$ENTRY_PULSE_A"
  write_entry "$ENTRY_PULSE_B"
  run bash "$SCRIPT"
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "1"
  # The surviving entry should have the later insight
  assert_output --partial "Caddy restart confirmed again."
}

@test "dedup preserves entries with distinct keys" {
  write_entry "$ENTRY_PULSE_A"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT"
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "2"
}

@test "filters by deployment (case-insensitive)" {
  write_entry "$ENTRY_PULSE_A"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT" --deployment Pulse
  assert_success
  assert_output --partial "caddy-restart"
  # Curia entry must not appear
  refute_output --partial "postgres-slow-start"
}

@test "deployment filter is case-insensitive" {
  write_entry "$ENTRY_PULSE_A"
  run bash "$SCRIPT" --deployment pulse
  assert_success
  assert_output --partial "caddy-restart"
}

@test "returns no output when deployment filter matches nothing" {
  write_entry "$ENTRY_PULSE_A"
  run bash "$SCRIPT" --deployment Nonexistent
  assert_success
  assert_output ""
}

@test "each output line is valid JSON" {
  write_entry "$ENTRY_PULSE_A"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT"
  assert_success
  echo "$output" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if line:
        json.loads(line)
"
}

@test "exits 1 with error on unknown argument" {
  run bash "$SCRIPT" --unknown-flag
  assert_failure
  assert_output --partial "error: unknown argument"
}

@test "exits 0 on empty learnings file" {
  touch "$TRIMKIT_SYSOPS_LEARNINGS_FILE"
  run bash "$SCRIPT"
  assert_success
  assert_output ""
}

@test "skips blank lines in the learnings file" {
  printf '\n' >> "$TRIMKIT_SYSOPS_LEARNINGS_FILE"
  write_entry "$ENTRY_PULSE_A"
  printf '\n' >> "$TRIMKIT_SYSOPS_LEARNINGS_FILE"
  run bash "$SCRIPT"
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "1"
}
