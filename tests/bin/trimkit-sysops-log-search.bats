#!/usr/bin/env bats

# tests/bin/trimkit-sysops-log-search.bats — tests for bin/trimkit-sysops-log-search

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-sysops-log-search"
  TMPDIR_CUSTOM="$(mktemp -d)"
  export TRIMKIT_SYSOPS_LOG_DIR="$TMPDIR_CUSTOM"
  export TRIMKIT_SYSOPS_LOG_FILE="$TMPDIR_CUSTOM/audit.jsonl"
}

teardown() {
  rm -rf "$TMPDIR_CUSTOM"
}

# Write an audit entry directly to the file (bypassing trimkit-sysops-log).
write_entry() {
  printf '%s\n' "$1" >> "$TRIMKIT_SYSOPS_LOG_FILE"
}

# Sample audit entries — minimal set of fields for testing
ENTRY_STATUS='{"ts":"2026-04-10T10:00:00Z","session":"sess-1","project":"curia","deployment":"Pulse","env":"prod","action":"status_check","containers":{"pulse":"healthy","caddy":"healthy"},"unregistered_containers":[],"notes":""}'
ENTRY_MAINT='{"ts":"2026-04-11T12:00:00Z","session":"sess-2","project":"curia","deployment":"Pulse","env":"prod","action":"maintenance","packages_upgraded":5,"reboot_performed":true,"reboot_duration_s":42,"containers":{"pulse":"healthy","caddy":"unhealthy"},"unregistered_containers":["redis-temp"],"notes":"caddy needed manual restart"}'
ENTRY_CURIA='{"ts":"2026-04-12T08:00:00Z","session":"sess-3","project":"curia","deployment":"Curia","env":"prod","action":"status_check","containers":{"postgres":"healthy"},"unregistered_containers":[],"notes":""}'

# ── Basic functionality ─────────────────────────────────────────────────────

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "exits 0 with no output when log file does not exist" {
  run bash "$SCRIPT"
  assert_success
  assert_output ""
}

@test "outputs all entries as JSONL when no filter given" {
  write_entry "$ENTRY_STATUS"
  write_entry "$ENTRY_MAINT"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT"
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "3"
}

@test "each output line is valid JSON" {
  write_entry "$ENTRY_STATUS"
  write_entry "$ENTRY_MAINT"
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

# ── --deployment filter ─────────────────────────────────────────────────────

@test "filters by deployment" {
  write_entry "$ENTRY_STATUS"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT" --deployment Pulse
  assert_success
  assert_output --partial "Pulse"
  refute_output --partial "Curia"
}

@test "deployment filter is case-insensitive" {
  write_entry "$ENTRY_STATUS"
  run bash "$SCRIPT" --deployment pulse
  assert_success
  assert_output --partial "Pulse"
}

@test "returns no output when deployment filter matches nothing" {
  write_entry "$ENTRY_STATUS"
  run bash "$SCRIPT" --deployment Nonexistent
  assert_success
  assert_output ""
}

# ── --last limit ────────────────────────────────────────────────────────────

@test "default limit is 10 entries" {
  # Write 12 entries; should only get last 10
  for i in $(seq 1 12); do
    write_entry "{\"ts\":\"2026-04-${i}T00:00:00Z\",\"session\":\"s-$i\",\"project\":\"p\",\"deployment\":\"D\",\"env\":\"prod\",\"action\":\"status_check\",\"containers\":{},\"unregistered_containers\":[],\"notes\":\"entry $i\"}"
  done
  run bash "$SCRIPT"
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "10"
  # First two entries (1, 2) should be trimmed; entry 3 should be present
  assert_output --partial "entry 3"
  refute_output --partial "entry 1\""
}

@test "--last limits output to N entries" {
  write_entry "$ENTRY_STATUS"
  write_entry "$ENTRY_MAINT"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT" --last 2
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "2"
}

@test "--last with --deployment filters first then limits" {
  write_entry "$ENTRY_STATUS"
  write_entry "$ENTRY_MAINT"
  write_entry "$ENTRY_CURIA"
  # Only 2 Pulse entries exist; --last 1 should give the most recent one
  run bash "$SCRIPT" --deployment Pulse --last 1
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "1"
  assert_output --partial "maintenance"
}

# ── Error handling ──────────────────────────────────────────────────────────

@test "exits 1 on unknown argument" {
  run bash "$SCRIPT" --unknown
  assert_failure
  assert_output --partial "error: unknown argument"
}

@test "exits 1 when --deployment given without value" {
  run bash "$SCRIPT" --deployment
  assert_failure
  assert_output --partial "error:"
}

@test "exits 1 when --deployment given an empty string" {
  run bash "$SCRIPT" --deployment ""
  assert_failure
  assert_output --partial "error:"
}

@test "exits 1 when --last given without value" {
  run bash "$SCRIPT" --last
  assert_failure
  assert_output --partial "error:"
}

@test "exits 1 when --last given a non-integer" {
  run bash "$SCRIPT" --last abc
  assert_failure
  assert_output --partial "error:"
  assert_output --partial "positive integer"
}

@test "exits 1 when --last given zero" {
  run bash "$SCRIPT" --last 0
  assert_failure
  assert_output --partial "error:"
}

@test "exits 1 when --last given negative number" {
  run bash "$SCRIPT" --last -5
  assert_failure
  assert_output --partial "error:"
}

# ── Corrupt lines ───────────────────────────────────────────────────────────

@test "corrupt JSONL lines are skipped and valid entries still appear" {
  printf 'this is not json\n' >> "$TRIMKIT_SYSOPS_LOG_FILE"
  write_entry "$ENTRY_STATUS"
  run bash "$SCRIPT"
  assert_success
  assert_output --partial "status_check"
}

@test "corrupt JSONL lines emit a warning on stderr" {
  printf 'not json\n' >> "$TRIMKIT_SYSOPS_LOG_FILE"
  run bash "$SCRIPT" 2>&1
  assert_success
  assert_output --partial "warning"
}

@test "exits 0 on empty log file" {
  touch "$TRIMKIT_SYSOPS_LOG_FILE"
  run bash "$SCRIPT"
  assert_success
  assert_output ""
}

@test "skips blank lines in the log file" {
  printf '\n' >> "$TRIMKIT_SYSOPS_LOG_FILE"
  write_entry "$ENTRY_STATUS"
  printf '\n' >> "$TRIMKIT_SYSOPS_LOG_FILE"
  run bash "$SCRIPT"
  assert_success
  line_count="$(echo "$output" | grep -c .)"
  assert_equal "$line_count" "1"
}

# ── --human flag ────────────────────────────────────────────────────────────

@test "--human shows formatted output for status check" {
  write_entry "$ENTRY_STATUS"
  run bash "$SCRIPT" --human
  assert_success
  assert_output --partial "Pulse [prod]"
  assert_output --partial "status_check"
  assert_output --partial "Containers:"
  assert_output --partial "Unregistered: none"
}

@test "--human shows maintenance details" {
  write_entry "$ENTRY_MAINT"
  run bash "$SCRIPT" --human
  assert_success
  assert_output --partial "maintenance"
  assert_output --partial "Packages upgraded: 5"
  assert_output --partial "Reboot: yes (42s)"
  assert_output --partial "redis-temp"
  assert_output --partial "Notes: caddy needed manual restart"
}

@test "--human with --deployment filters correctly" {
  write_entry "$ENTRY_STATUS"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT" --human --deployment Curia
  assert_success
  assert_output --partial "Curia"
  refute_output --partial "Pulse"
}

@test "--human shows 'No audit log found' when file does not exist" {
  run bash "$SCRIPT" --human
  assert_success
  assert_output --partial "No audit log found"
}

@test "--human shows 'No entries found' when deployment matches nothing" {
  write_entry "$ENTRY_STATUS"
  run bash "$SCRIPT" --human --deployment Nonexistent
  assert_success
  assert_output --partial "No entries found"
  assert_output --partial "Nonexistent"
}

@test "--human with corrupt lines shows warning" {
  printf 'not json\n' >> "$TRIMKIT_SYSOPS_LOG_FILE"
  write_entry "$ENTRY_STATUS"
  run bash "$SCRIPT" --human 2>&1
  assert_success
  assert_output --partial "warning"
  assert_output --partial "Pulse"
}

@test "--human on empty file shows 'No entries found'" {
  touch "$TRIMKIT_SYSOPS_LOG_FILE"
  run bash "$SCRIPT" --human
  assert_success
  assert_output --partial "No entries found"
}

@test "--human respects --last limit" {
  write_entry "$ENTRY_STATUS"
  write_entry "$ENTRY_MAINT"
  write_entry "$ENTRY_CURIA"
  run bash "$SCRIPT" --human --last 1
  assert_success
  # Only the last entry (Curia) should appear
  assert_output --partial "Curia"
  refute_output --partial "maintenance"
}
