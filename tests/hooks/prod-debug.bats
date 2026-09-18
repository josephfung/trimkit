#!/usr/bin/env bats

# tests/hooks/prod-debug.bats — tests for hooks/prod-debug.sh
#
# Fixture layout mirrors a multi-repo workspace:
#
#   $WS/.claude/prod-debug/config.json   globs point into repos/app/
#   $WS/repos/app/                        main git checkout
#   $WS/worktrees/app-feat/               linked worktree of repos/app

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'

  HOOK="$BATS_TEST_DIRNAME/../../hooks/prod-debug.sh"

  # realpath so paths match what the hook prints (macOS /var -> /private/var)
  WS="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$(mktemp -d)")"
  MAIN="$WS/repos/app"
  WT="$WS/worktrees/app-feat"

  mkdir -p "$WS/.claude/prod-debug" "$MAIN/src/db/migrations"
  cat > "$WS/.claude/prod-debug/config.json" <<'JSON'
{
  "migrations": { "glob": "repos/app/src/db/migrations/*.sql" },
  "containers": { "composeFiles": ["repos/app/docker-compose.yml"] }
}
JSON

  echo "CREATE TABLE a (id int);" > "$MAIN/src/db/migrations/001_init.sql"
  echo "services: {}" > "$MAIN/docker-compose.yml"

  git -C "$MAIN" init -q -b main
  git -C "$MAIN" add -A
  git -C "$MAIN" -c user.name=t -c user.email=t@t commit -q -m init
  git -C "$MAIN" worktree add -q "$WT" -b feat
}

teardown() {
  rm -rf "$WS"
}

# Feed the hook a PostToolUse payload for a Write to $1
run_hook() {
  run bash "$HOOK" <<< "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$1\"}}"
}

@test "migration written in main checkout triggers schema update" {
  echo "ALTER TABLE a ADD COLUMN b int;" > "$MAIN/src/db/migrations/002_b.sql"
  run_hook "$MAIN/src/db/migrations/002_b.sql"
  assert_success
  assert_output --partial "[prod-debug] Migration written: repos/app/src/db/migrations/002_b.sql"
  assert_output --partial "$WS/.claude/prod-debug/schema.md"
}

@test "migration written in a linked worktree triggers schema update" {
  echo "ALTER TABLE a ADD COLUMN c int;" > "$WT/src/db/migrations/002_c.sql"
  run_hook "$WT/src/db/migrations/002_c.sql"
  assert_success
  # Names the file actually written, so Claude reads the right one
  assert_output --partial "[prod-debug] Migration written: worktrees/app-feat/src/db/migrations/002_c.sql"
  assert_output --partial "$WS/.claude/prod-debug/schema.md"
}

@test "migration in a worktree outside the workspace triggers schema update" {
  OUTSIDE="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$(mktemp -d)")"
  git -C "$MAIN" worktree add -q "$OUTSIDE/app-other" -b other
  echo "SELECT 1;" > "$OUTSIDE/app-other/src/db/migrations/003_x.sql"
  run_hook "$OUTSIDE/app-other/src/db/migrations/003_x.sql"
  rm -rf "$OUTSIDE"
  assert_success
  assert_output --partial "[prod-debug] Migration written: $OUTSIDE/app-other/src/db/migrations/003_x.sql"
  assert_output --partial "$WS/.claude/prod-debug/schema.md"
}

@test "compose file edited in a linked worktree triggers containers update" {
  echo "services: {web: {}}" > "$WT/docker-compose.yml"
  run_hook "$WT/docker-compose.yml"
  assert_success
  assert_output --partial "[prod-debug] Compose file written: worktrees/app-feat/docker-compose.yml"
  assert_output --partial "containers.md"
}

@test "compose file edited in main checkout triggers containers update" {
  run_hook "$MAIN/docker-compose.yml"
  assert_success
  assert_output --partial "[prod-debug] Compose file written: repos/app/docker-compose.yml"
}

@test "unrelated file in a worktree is ignored" {
  echo "x" > "$WT/src/db/notes.txt"
  run_hook "$WT/src/db/notes.txt"
  assert_success
  assert_output ""
}

@test "glob '*' does not match nested directories in a worktree" {
  mkdir -p "$WT/src/db/migrations/sub"
  echo "x" > "$WT/src/db/migrations/sub/004.sql"
  run_hook "$WT/src/db/migrations/sub/004.sql"
  assert_success
  assert_output ""
}

@test "file outside any prod-debug project is ignored" {
  OTHER="$(mktemp -d)"
  echo "x" > "$OTHER/001.sql"
  run_hook "$OTHER/001.sql"
  rm -rf "$OTHER"
  assert_success
  assert_output ""
}

@test "non-git project with a relative glob still works" {
  PLAIN="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$(mktemp -d)")"
  mkdir -p "$PLAIN/.claude/prod-debug" "$PLAIN/db"
  echo '{"migrations":{"glob":"db/*.sql"}}' > "$PLAIN/.claude/prod-debug/config.json"
  echo "x" > "$PLAIN/db/001.sql"
  run_hook "$PLAIN/db/001.sql"
  rm -rf "$PLAIN"
  assert_success
  assert_output --partial "[prod-debug] Migration written: db/001.sql"
}

@test "missing file_path exits silently" {
  run bash "$HOOK" <<< '{"tool_name":"Write","tool_input":{}}'
  assert_success
  assert_output ""
}

@test "unparseable config.json is reported rather than silently ignored" {
  echo '{bad' > "$WS/.claude/prod-debug/config.json"
  run_hook "$MAIN/src/db/migrations/001_init.sql"
  assert_success
  assert_output --partial "Could not parse $WS/.claude/prod-debug/config.json"
}
