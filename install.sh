#!/bin/bash
# install.sh — Symlink TrimKit hooks into ~/.claude/hooks/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/hooks"
HOOKS_DST="$HOME/.claude/hooks"

# Track actions for summary
installed=()
skipped=()
warned=()

mkdir -p "$HOOKS_DST"

for hook in "$HOOKS_SRC"/*; do
  [ -f "$hook" ] || continue
  name="$(basename "$hook")"
  dst="$HOOKS_DST/$name"

  if [ -L "$dst" ]; then
    # It's a symlink — check if it points to us
    current_target="$(readlink "$dst")"
    if [ "$current_target" = "$hook" ]; then
      skipped+=("$name (already linked)")
      continue
    fi
  fi

  if [ -e "$dst" ]; then
    # File exists and isn't a symlink to us
    warned+=("$name (exists at $dst, not overwriting)")
    continue
  fi

  ln -sf "$hook" "$dst"
  installed+=("$name")
done

# Summary
echo ""
echo "=== TrimKit install ==="

if [ ${#installed[@]} -gt 0 ]; then
  echo ""
  echo "Installed:"
  for f in "${installed[@]}"; do echo "  ✓ $f"; done
fi

if [ ${#skipped[@]} -gt 0 ]; then
  echo ""
  echo "Skipped:"
  for f in "${skipped[@]}"; do echo "  - $f"; done
fi

if [ ${#warned[@]} -gt 0 ]; then
  echo ""
  echo "Warnings:"
  for f in "${warned[@]}"; do echo "  ⚠ $f"; done
fi

echo ""
echo "Note: To wire hooks into Claude Code, merge the config from"
echo "  $SCRIPT_DIR/settings/hooks.json"
echo "into your ~/.claude/settings.json"
