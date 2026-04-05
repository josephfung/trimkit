#!/bin/bash
# install.sh — Bootstrap TrimKit into ~/.claude
#   1. Symlinks hooks, agents, and skills into ~/.claude/
#   2. Installs Claude Code plugins listed in plugins/plugins.txt
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_MANIFEST="$SCRIPT_DIR/plugins/plugins.txt"

# Track actions for summary
installed=()
skipped=()
warned=()

# symlink_files <src_dir> <dst_dir>
# Symlinks each file in src_dir into dst_dir.
symlink_files() {
  local src_dir="$1"
  local dst_dir="$2"

  mkdir -p "$dst_dir"

  for src in "$src_dir"/*; do
    [ -f "$src" ] || continue
    local name dst
    name="$(basename "$src")"
    dst="$dst_dir/$name"

    if [ -L "$dst" ]; then
      local current_target
      current_target="$(readlink "$dst")"
      if [ "$current_target" = "$src" ]; then
        skipped+=("$name (already linked)")
        continue
      fi
    fi

    if [ -e "$dst" ]; then
      warned+=("$name (exists at $dst, not overwriting)")
      continue
    fi

    ln -sf "$src" "$dst"
    installed+=("$name")
  done
}

# symlink_dirs <src_dir> <dst_dir>
# Symlinks each subdirectory in src_dir into dst_dir. Used for skills, where
# each skill is a directory containing SKILL.md rather than a flat file.
symlink_dirs() {
  local src_dir="$1"
  local dst_dir="$2"

  mkdir -p "$dst_dir"

  for src in "$src_dir"/*/; do
    [ -d "$src" ] || continue
    local name dst
    name="$(basename "$src")"
    dst="$dst_dir/$name"

    # Strip trailing slash for readlink comparison
    src="${src%/}"

    if [ -L "$dst" ]; then
      local current_target
      current_target="$(readlink "$dst")"
      if [ "$current_target" = "$src" ]; then
        skipped+=("$name/ (already linked)")
        continue
      fi
    fi

    if [ -e "$dst" ]; then
      warned+=("$name/ (exists at $dst, not overwriting)")
      continue
    fi

    ln -sf "$src" "$dst"
    installed+=("$name/")
  done
}

symlink_files "$SCRIPT_DIR/hooks"   "$HOME/.claude/hooks"
symlink_files "$SCRIPT_DIR/agents"  "$HOME/.claude/agents"
symlink_dirs  "$SCRIPT_DIR/skills"  "$HOME/.claude/skills"

# ---------------------------------------------------------------------------
# Plugins
# ---------------------------------------------------------------------------

plugins_installed=()
plugins_skipped=()
plugins_failed=()

install_plugins() {
  # Require the claude CLI
  if ! command -v claude &>/dev/null; then
    echo ""
    echo "⚠ claude CLI not found — skipping plugin installation."
    echo "  Install Claude Code, then re-run install.sh to install plugins."
    return
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    # Strip inline comments, then trim whitespace
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip blank lines
    [ -z "$line" ] && continue

    # Run install; treat "already installed" output as a skip, not a failure
    output="$(claude plugin install "$line" 2>&1)" && status=0 || status=$?

    if [ $status -eq 0 ]; then
      # The CLI prints something like "Plugin already installed" when it's a no-op
      if echo "$output" | grep -qi "already install"; then
        plugins_skipped+=("$line")
      else
        plugins_installed+=("$line")
      fi
    else
      plugins_failed+=("$line")
    fi
  done < "$PLUGINS_MANIFEST"
}

install_plugins

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

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

if [ ${#plugins_installed[@]} -gt 0 ]; then
  echo ""
  echo "Plugins installed:"
  for f in "${plugins_installed[@]}"; do echo "  ✓ $f"; done
fi

if [ ${#plugins_skipped[@]} -gt 0 ]; then
  echo ""
  echo "Plugins already installed:"
  for f in "${plugins_skipped[@]}"; do echo "  - $f"; done
fi

if [ ${#plugins_failed[@]} -gt 0 ]; then
  echo ""
  echo "Plugin install failures:"
  for f in "${plugins_failed[@]}"; do echo "  ✗ $f"; done
fi

echo ""
echo "Note: To wire hooks into Claude Code, merge the config from"
echo "  $SCRIPT_DIR/settings/hooks.json"
echo "into your ~/.claude/settings.json"
echo ""
echo "Note: To use the sysops agent, create your deployment registry at"
echo "  ~/.claude/sysops/deployments.json"
echo "See $SCRIPT_DIR/sysops/deployments.example.json for the format."
