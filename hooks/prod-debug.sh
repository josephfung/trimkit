#!/bin/bash
# prod-debug.sh — PostToolUse hook that detects migration and compose file writes
# and instructs Claude to update the corresponding prod-debug data files.
#
# Fires after Write or Edit tool calls. Silently exits if:
#   - The written file is not in a prod-debug-enabled project
#   - The file doesn't match any watched pattern
#
# When a match is found, prints a plain-text instruction to stdout. Claude Code
# includes PostToolUse hook stdout in the model's context, so Claude sees it and
# acts on it inline.
#
# Worktree support: config.json globs are written relative to the project root
# and usually point into a main checkout (e.g. repos/curia/src/db/migrations/*.sql).
# Under a worktree workflow, the file is actually written to a linked worktree
# (e.g. worktrees/curia-feat/src/db/migrations/086_x.sql) and only reaches the
# main checkout later via `git pull`, which never triggers this hook. So when the
# written file lives in a linked git worktree, we also test the equivalent path
# inside that repo's main checkout against the watched patterns.

set -euo pipefail

# Read the tool result JSON from stdin
INPUT="$(cat)"

# Extract file_path from tool_input (works for both Write and Edit)
FILE_PATH="$(printf '%s' "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d.get('tool_input', {}).get('file_path', ''))
" 2>/dev/null || true)"

[ -z "$FILE_PATH" ] && exit 0

# Resolve to absolute path
FILE_PATH="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$FILE_PATH" 2>/dev/null || true)"
[ -z "$FILE_PATH" ] && exit 0

# Walk up from the file's directory looking for .claude/prod-debug/config.json.
# The directory doesn't need to exist — for a worktree-translated path the file
# may not have reached the main checkout yet — we only test for the config file.
find_project_root() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.claude/prod-debug/config.json" ]; then
      printf '%s' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

# If FILE_PATH is inside a linked git worktree, print the equivalent path inside
# the repo's main checkout. Prints nothing for main checkouts, bare repos, or
# non-git paths.
main_checkout_equivalent() {
  local file="$1"
  local dir toplevel common_dir main_root
  dir="$(dirname "$file")"
  [ -d "$dir" ] || return 0

  toplevel="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || return 0
  # --git-common-dir is the shared .git dir; for a linked worktree it points at
  # the main checkout's .git rather than .git/worktrees/<name>.
  # --path-format needs git >= 2.31; on older git this fails and worktree
  # matching is skipped (direct matching still works).
  common_dir="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 0
  [ "$(basename "$common_dir")" = ".git" ] || return 0  # bare repo: no main checkout

  toplevel="$(python3 -c "import os,sys; print(os.path.realpath(sys.argv[1]))" "$toplevel")"
  main_root="$(python3 -c "import os,sys; print(os.path.realpath(os.path.dirname(sys.argv[1])))" "$common_dir")"

  # Same toplevel means we're already in the main checkout — nothing to translate.
  [ "$toplevel" = "$main_root" ] && return 0

  case "$file" in
    "$toplevel"/*) printf '%s/%s' "$main_root" "${file#"$toplevel"/}" ;;
  esac
}

# Check CANDIDATE (a path that may or may not exist) against the watched patterns
# of the prod-debug project it belongs to. On match, prints the instruction —
# naming ORIGINAL (the file Claude actually wrote) — and returns 0.
check_candidate() {
  local candidate="$1" original="$2"
  local project_root config migration_glob compose_files matched rel_path

  project_root="$(find_project_root "$(dirname "$candidate")")" || return 1
  config="$project_root/.claude/prod-debug/config.json"

  # A config that exists but won't parse would otherwise make every read below
  # come back empty, and the hook would go silent. Say so once and stop.
  if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$config" 2>/dev/null; then
    printf '\n[prod-debug] Could not parse %s, so schema/containers auto-sync is disabled until it is fixed.\n' "$config"
    return 0
  fi

  # Show a project-relative path when the written file is under the project
  # root; otherwise (e.g. a worktree outside it) the absolute path.
  rel_path="${original#"$project_root"/}"

  # Read migration glob from config
  migration_glob="$(python3 -c "
import sys, json
with open(sys.argv[1]) as f:
  d = json.load(f)
print(d.get('migrations', {}).get('glob', ''))
" "$config" 2>/dev/null || true)"

  if [ -n "$migration_glob" ]; then
    # Two ways to match:
    #   1. glob.glob against the filesystem (the original behaviour — follows
    #      symlinked directories because results are realpath'd)
    #   2. a pure pattern match, needed for worktree-translated candidates that
    #      don't exist on disk yet. Matched segment-by-segment so '*' never
    #      crosses '/', with '**' matching zero or more whole segments.
    matched="$(python3 -c "
import sys, glob, os, fnmatch
root, pattern_rel, target = sys.argv[1], sys.argv[2], sys.argv[3]
pattern = os.path.join(root, pattern_rel)

if target in [os.path.realpath(m) for m in glob.glob(pattern, recursive=True)]:
  print('yes'); sys.exit(0)

def match(parts, pats):
  if not pats:
    return not parts
  if pats[0] == '**':
    return any(match(parts[i:], pats[1:]) for i in range(len(parts) + 1))
  return bool(parts) and fnmatch.fnmatchcase(parts[0], pats[0]) and match(parts[1:], pats[1:])

norm = lambda p: os.path.normpath(p).split(os.sep)
if match(norm(target), norm(pattern)):
  print('yes')
" "$project_root" "$migration_glob" "$candidate" 2>/dev/null || true)"

    if [ "$matched" = "yes" ]; then
      printf '\n[prod-debug] Migration written: %s\n' "$rel_path"
      printf 'Please update %s/.claude/prod-debug/schema.md to reflect the changes in this migration, and bump its last-migration marker if this is the newest migration.\n' "$project_root"
      return 0
    fi
  fi

  # Read compose file paths from config (newline-separated)
  compose_files="$(python3 -c "
import sys, json, os
with open(sys.argv[1]) as f:
  d = json.load(f)
root = sys.argv[2]
files = d.get('containers', {}).get('composeFiles', [])
for f in files:
  print(os.path.realpath(os.path.join(root, f)))
" "$config" "$project_root" 2>/dev/null || true)"

  if [ -n "$compose_files" ]; then
    local compose_file
    while IFS= read -r compose_file; do
      [ -z "$compose_file" ] && continue
      if [ "$candidate" = "$compose_file" ]; then
        printf '\n[prod-debug] Compose file written: %s\n' "$rel_path"
        printf 'Please update %s/.claude/prod-debug/containers.md to reflect any service changes in this file.\n' "$project_root"
        return 0
      fi
    done <<< "$compose_files"
  fi

  return 1
}

# Direct match first (unchanged behaviour for non-worktree projects), then the
# main-checkout equivalent if the file was written inside a linked worktree.
check_candidate "$FILE_PATH" "$FILE_PATH" && exit 0

MAIN_EQUIV="$(main_checkout_equivalent "$FILE_PATH")"
if [ -n "$MAIN_EQUIV" ]; then
  check_candidate "$MAIN_EQUIV" "$FILE_PATH" && exit 0
fi

exit 0
