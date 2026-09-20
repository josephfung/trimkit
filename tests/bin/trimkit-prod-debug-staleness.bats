#!/usr/bin/env bats

# tests/bin/trimkit-prod-debug-staleness.bats — tests for bin/trimkit-prod-debug-staleness

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-prod-debug-staleness"

  ROOT="$(mktemp -d)"
  mkdir -p "$ROOT/.claude/prod-debug" "$ROOT/migrations"
  echo '{"migrations":{"glob":"migrations/*.sql"}}' > "$ROOT/.claude/prod-debug/config.json"
  touch "$ROOT/migrations/001_init.sql" "$ROOT/migrations/068_tasks.sql"
}

teardown() {
  rm -rf "$ROOT"
}

write_schema() {
  printf '# DB Schema\n<!-- Last bootstrapped: 2026-06-30 from 68 migrations -->\n%s\n' "$1" \
    > "$ROOT/.claude/prod-debug/schema.md"
}

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "exits 2 with usage on missing argument" {
  run bash "$SCRIPT"
  assert_failure 2
  assert_output --partial 'Usage:'
}

@test "exits 2 when config.json is missing" {
  rm "$ROOT/.claude/prod-debug/config.json"
  run bash "$SCRIPT" "$ROOT"
  assert_failure 2
  assert_output --partial 'cannot read'
}

@test "silent and exit 0 when marker matches newest migration" {
  write_schema '<!-- prod-debug:last-migration: 068_tasks.sql -->'
  run bash "$SCRIPT" "$ROOT"
  assert_success
  assert_output ""
}

@test "warns naming both versions when newer migrations exist" {
  write_schema '<!-- prod-debug:last-migration: 068_tasks.sql -->'
  touch "$ROOT/migrations/085_contact_anchored_kg_identity.sql"
  run bash "$SCRIPT" "$ROOT"
  assert_failure 1
  assert_output --partial 'schema.md is stale (068_tasks.sql vs 085_contact_anchored_kg_identity.sql)'
  assert_output --partial '/prod-debug bootstrap'
}

@test "uses natural sort so 100 is newer than 99" {
  rm "$ROOT"/migrations/*.sql
  touch "$ROOT/migrations/99_a.sql" "$ROOT/migrations/100_b.sql"
  write_schema '<!-- prod-debug:last-migration: 99_a.sql -->'
  run bash "$SCRIPT" "$ROOT"
  assert_failure 1
  assert_output --partial '(99_a.sql vs 100_b.sql)'
}

@test "not stale when schema was built from a newer checkout" {
  write_schema '<!-- prod-debug:last-migration: 070_future.sql -->'
  run bash "$SCRIPT" "$ROOT"
  assert_success
  assert_output ""
}

@test "warns when schema.md has no marker" {
  write_schema ''
  run bash "$SCRIPT" "$ROOT"
  assert_failure 1
  assert_output --partial 'no last-migration marker'
  assert_output --partial '068_tasks.sql'
}

@test "warns when schema.md is missing" {
  run bash "$SCRIPT" "$ROOT"
  assert_failure 1
  assert_output --partial 'schema.md not found'
}

@test "warns when the glob matches nothing" {
  rm "$ROOT"/migrations/*.sql
  write_schema '<!-- prod-debug:last-migration: 068_tasks.sql -->'
  run bash "$SCRIPT" "$ROOT"
  assert_failure 1
  assert_output --partial 'No migrations match'
}

@test "silent when config has no migrations glob" {
  echo '{"containers":{"composeFiles":[]}}' > "$ROOT/.claude/prod-debug/config.json"
  run bash "$SCRIPT" "$ROOT"
  assert_success
  assert_output ""
}

@test "exits 2 when migrations has the wrong shape" {
  echo '{"migrations":"migrations/*.sql"}' > "$ROOT/.claude/prod-debug/config.json"
  run bash "$SCRIPT" "$ROOT"
  assert_failure 2
  assert_output --partial "'migrations' object"
}

@test "exits 2 when glob is not a string" {
  echo '{"migrations":{"glob":["migrations/*.sql"]}}' > "$ROOT/.claude/prod-debug/config.json"
  run bash "$SCRIPT" "$ROOT"
  assert_failure 2
  assert_output --partial 'must be a string'
}

@test "exits 2 when schema.md is not valid UTF-8" {
  printf '\xff\xfe<!-- prod-debug:last-migration: 068_tasks.sql -->\n' > "$ROOT/.claude/prod-debug/schema.md"
  run bash "$SCRIPT" "$ROOT"
  assert_failure 2
  assert_output --partial 'cannot read'
}
