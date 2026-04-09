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

# Walk up from the file's directory looking for .claude/prod-debug/config.json
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

PROJECT_ROOT="$(find_project_root "$(dirname "$FILE_PATH")")" || exit 0

CONFIG="$PROJECT_ROOT/.claude/prod-debug/config.json"

# Read migration glob from config
MIGRATION_GLOB="$(python3 -c "
import sys, json
with open(sys.argv[1]) as f:
  d = json.load(f)
print(d.get('migrations', {}).get('glob', ''))
" "$CONFIG" 2>/dev/null || true)"

# Read compose file paths from config (newline-separated)
COMPOSE_FILES="$(python3 -c "
import sys, json, os
with open(sys.argv[1]) as f:
  d = json.load(f)
root = sys.argv[2]
files = d.get('containers', {}).get('composeFiles', [])
for f in files:
  print(os.path.realpath(os.path.join(root, f)))
" "$CONFIG" "$PROJECT_ROOT" 2>/dev/null || true)"

# Check migration match using glob pattern
if [ -n "$MIGRATION_GLOB" ]; then
  # Resolve glob relative to project root and check if FILE_PATH matches
  MATCHED="$(python3 -c "
import sys, glob, os
pattern = os.path.join(sys.argv[1], sys.argv[2])
target = sys.argv[3]
matches = glob.glob(pattern)
if target in [os.path.realpath(m) for m in matches]:
  print('yes')
" "$PROJECT_ROOT" "$MIGRATION_GLOB" "$FILE_PATH" 2>/dev/null || true)"

  if [ "$MATCHED" = "yes" ]; then
    REL_PATH="${FILE_PATH#$PROJECT_ROOT/}"
    printf '\n[prod-debug] Migration written: %s\n' "$REL_PATH"
    printf 'Please update %s/.claude/prod-debug/schema.md to reflect the changes in this migration.\n' "$PROJECT_ROOT"
    exit 0
  fi
fi

# Check compose file match
if [ -n "$COMPOSE_FILES" ]; then
  while IFS= read -r COMPOSE_FILE; do
    [ -z "$COMPOSE_FILE" ] && continue
    if [ "$FILE_PATH" = "$COMPOSE_FILE" ]; then
      REL_PATH="${FILE_PATH#$PROJECT_ROOT/}"
      printf '\n[prod-debug] Compose file written: %s\n' "$REL_PATH"
      printf 'Please update %s/.claude/prod-debug/containers.md to reflect any service changes in this file.\n' "$PROJECT_ROOT"
      exit 0
    fi
  done <<< "$COMPOSE_FILES"
fi

exit 0
