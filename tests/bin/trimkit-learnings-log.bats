#!/usr/bin/env bats

# tests/bin/trimkit-learnings-log.bats — tests for bin/trimkit-learnings-log

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-learnings-log"
  TMPDIR_CUSTOM="$(mktemp -d)"
  export TRIMKIT_SYSOPS_LEARNINGS_DIR="$TMPDIR_CUSTOM"
  export TRIMKIT_SYSOPS_LEARNINGS_FILE="$TMPDIR_CUSTOM/learnings.jsonl"
}

teardown() {
  rm -rf "$TMPDIR_CUSTOM"
}

SAMPLE='{"deployment":"Pulse","key":"caddy-restart-required-after-upgrade","type":"quirk","insight":"Caddy container requires manual restart after apt upgrade.","confidence":0.9,"source":"observed"}'

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
  count="$(wc -l < "$TRIMKIT_SYSOPS_LEARNINGS_FILE" | tr -d ' ')"
  assert_equal "$count" "1"
}

@test "two calls produce two lines" {
  echo "$SAMPLE" | bash "$SCRIPT"
  echo "$SAMPLE" | bash "$SCRIPT"
  count="$(wc -l < "$TRIMKIT_SYSOPS_LEARNINGS_FILE" | tr -d ' ')"
  assert_equal "$count" "2"
}

@test "each line is valid JSON" {
  echo "$SAMPLE" | bash "$SCRIPT"
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LEARNINGS_FILE') as f:
    for line in f:
        json.loads(line)  # raises ValueError if invalid
"
}

@test "injects ts field in ISO 8601 UTC format" {
  echo "$SAMPLE" | bash "$SCRIPT"
  python3 -c "
import json, re
with open('$TRIMKIT_SYSOPS_LEARNINGS_FILE') as f:
    obj = json.loads(f.read().strip())
assert 'ts' in obj, 'ts field missing'
assert re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$', obj['ts']), f'bad ts format: {obj[\"ts\"]}'
"
}

@test "preserves all input fields" {
  input='{"deployment":"Pulse","key":"caddy-restart-required-after-upgrade","type":"quirk","insight":"Caddy needs restart.","confidence":0.9,"source":"observed"}'
  echo "$input" | bash "$SCRIPT"
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LEARNINGS_FILE') as f:
    obj = json.loads(f.read().strip())
assert obj['deployment'] == 'Pulse'
assert obj['key'] == 'caddy-restart-required-after-upgrade'
assert obj['type'] == 'quirk'
assert obj['insight'] == 'Caddy needs restart.'
assert obj['confidence'] == 0.9
assert obj['source'] == 'observed'
"
}

@test "exits 1 with error message when stdin is empty" {
  run bash -c "echo '' | bash '$SCRIPT'"
  assert_failure
  assert_output --partial "error: no JSON received on stdin"
}

@test "exits 0 on success" {
  run bash -c "echo '$SAMPLE' | bash '$SCRIPT'"
  assert_success
}

@test "exits 1 with error message when key field is missing" {
  run bash -c "echo '{\"deployment\":\"Pulse\",\"type\":\"quirk\",\"insight\":\"x\",\"confidence\":0.9,\"source\":\"observed\"}' | bash '$SCRIPT'"
  assert_failure
  assert_output --partial "error:"
}

@test "exits 1 with error message when key field is empty string" {
  run bash -c "echo '{\"deployment\":\"Pulse\",\"key\":\"\",\"type\":\"quirk\",\"insight\":\"x\",\"confidence\":0.9,\"source\":\"observed\"}' | bash '$SCRIPT'"
  assert_failure
  assert_output --partial "error:"
}

@test "concurrent writes all produce valid JSONL lines" {
  for i in 1 2 3 4 5; do
    echo "{\"deployment\":\"Pulse\",\"key\":\"key-${i}\",\"type\":\"quirk\",\"insight\":\"learning ${i}\",\"confidence\":0.8,\"source\":\"observed\"}" \
      | bash "$SCRIPT" &
  done
  wait
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LEARNINGS_FILE') as f:
    lines = [l for l in f if l.strip()]
assert len(lines) == 5, f'expected 5 lines, got {len(lines)}'
for line in lines:
    json.loads(line)
"
}
