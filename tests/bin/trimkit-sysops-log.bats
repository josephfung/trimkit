#!/usr/bin/env bats

# tests/bin/trimkit-sysops-log.bats — tests for bin/trimkit-sysops-log

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-sysops-log"
  TMPDIR_CUSTOM="$(mktemp -d)"
  export TRIMKIT_SYSOPS_LOG_DIR="$TMPDIR_CUSTOM"
  export TRIMKIT_SYSOPS_LOG_FILE="$TMPDIR_CUSTOM/audit.jsonl"
}

teardown() {
  rm -rf "$TMPDIR_CUSTOM"
}

SAMPLE='{"session":"s1","project":"myapp","deployment":"Pulse","env":"prod","action":"status_check","containers":{"pulse":"healthy"},"unregistered_containers":[],"notes":""}'

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "creates log directory if it does not exist" {
  rm -rf "$TMPDIR_CUSTOM"
  echo "$SAMPLE" | bash "$SCRIPT"
  [ -d "$TMPDIR_CUSTOM" ]
}

@test "appends one line per call" {
  echo "$SAMPLE" | bash "$SCRIPT"
  count="$(wc -l < "$TRIMKIT_SYSOPS_LOG_FILE" | tr -d ' ')"
  assert_equal "$count" "1"
}

@test "two calls produce two lines" {
  echo "$SAMPLE" | bash "$SCRIPT"
  echo "$SAMPLE" | bash "$SCRIPT"
  count="$(wc -l < "$TRIMKIT_SYSOPS_LOG_FILE" | tr -d ' ')"
  assert_equal "$count" "2"
}

@test "each line is valid JSON" {
  echo "$SAMPLE" | bash "$SCRIPT"
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    for line in f:
        json.loads(line)  # raises ValueError if invalid
"
}

@test "injects ts field in ISO 8601 UTC format" {
  echo "$SAMPLE" | bash "$SCRIPT"
  python3 -c "
import json, re
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    obj = json.loads(f.read().strip())
assert 'ts' in obj, 'ts field missing'
assert re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$', obj['ts']), f'bad ts format: {obj[\"ts\"]}'
"
}

@test "preserves all input fields" {
  input='{"session":"abc","project":"curia","deployment":"MyApp","env":"prod","action":"maintenance","packages_upgraded":5,"reboot_performed":true,"reboot_duration_s":30,"containers":{"myapp":"healthy"},"unregistered_containers":["redis-tmp"],"notes":"all good"}'
  echo "$input" | bash "$SCRIPT"
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    obj = json.loads(f.read().strip())
assert obj['session'] == 'abc'
assert obj['deployment'] == 'MyApp'
assert obj['packages_upgraded'] == 5
assert obj['reboot_performed'] == True
assert obj['reboot_duration_s'] == 30
assert obj['unregistered_containers'] == ['redis-tmp']
assert obj['notes'] == 'all good'
"
}

@test "concurrent writes all produce valid JSONL lines" {
  for i in 1 2 3 4 5; do
    echo "{\"session\":\"s${i}\",\"project\":\"p\",\"deployment\":\"D\",\"env\":\"prod\",\"action\":\"status_check\",\"containers\":{},\"unregistered_containers\":[],\"notes\":\"\"}" \
      | bash "$SCRIPT" &
  done
  wait
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    lines = [l for l in f if l.strip()]
assert len(lines) == 5, f'expected 5 lines, got {len(lines)}'
for line in lines:
    json.loads(line)
"
}

@test "exits 0 on success" {
  run bash -c "echo '$SAMPLE' | bash '$SCRIPT'"
  assert_success
}
