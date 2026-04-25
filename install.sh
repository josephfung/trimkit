#!/bin/bash
# install.sh — Bootstrap TrimKit into ~/.claude and ~/.trimkit
#   1. Symlinks hooks, agents, and skills into ~/.claude/
#   2. Symlinks bin scripts into ~/.trimkit/bin/
#   3. Installs Claude Code plugins listed in plugins/plugins.txt
#
# Usage: install.sh [--upgrade]
#   --upgrade  Replace existing real files/dirs with symlinks (backs up first).
#              Use this after a TrimKit update to ensure managed files stay
#              in sync. Symlinks are never replaced — they already auto-update.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_MANIFEST="$SCRIPT_DIR/plugins/plugins.txt"

# Parse flags
UPGRADE=false
for arg in "$@"; do
  case "$arg" in
    --upgrade) UPGRADE=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# Track actions for summary
installed=()
skipped=()
warned=()
upgraded=()

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
      if [ "$UPGRADE" = true ]; then
        local bak="${dst}.bak"
        # Preflight: refuse to upgrade if the source no longer exists — would
        # destroy the existing file and leave a dangling symlink in its place.
        if [ ! -e "$src" ]; then
          warned+=("$name (source missing in TrimKit, not upgraded)")
          continue
        fi
        # Don't silently overwrite a prior backup — the user may need it.
        if [ -e "$bak" ]; then
          warned+=("$name (${name}.bak already exists — delete it first, then re-run --upgrade)")
          continue
        fi
        # Three-step atomic-ish replace: back up, remove, link.
        # Each step is guarded so a failure stops early rather than leaving
        # $dst in a half-deleted state.
        if ! cp "$dst" "$bak"; then
          warned+=("$name (backup failed, not upgraded)")
          continue
        fi
        if ! rm -f "$dst"; then
          warned+=("$name (remove failed, not upgraded — backup at $bak)")
          continue
        fi
        if ! ln -sf "$src" "$dst"; then
          # $dst is now gone. Best-effort restore from backup.
          if mv "$bak" "$dst" 2>/dev/null; then
            warned+=("$name (symlink failed, original restored from backup)")
          else
            warned+=("$name (symlink failed AND restore failed — recover manually: mv \"$bak\" \"$dst\")")
          fi
          continue
        fi
        upgraded+=("$name (backed up to $bak)")
      else
        warned+=("$name (exists at $dst, not overwriting — re-run with --upgrade to replace)")
      fi
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
      if [ "$UPGRADE" = true ]; then
        local bak="${dst}.bak"
        # Preflight: refuse to upgrade if the source no longer exists.
        if [ ! -e "$src" ]; then
          warned+=("$name/ (source missing in TrimKit, not upgraded)")
          continue
        fi
        # Don't silently overwrite a prior backup.
        if [ -e "$bak" ]; then
          warned+=("$name/ (${name}.bak already exists — delete it first, then re-run --upgrade)")
          continue
        fi
        # Three-step atomic-ish replace: back up, remove, link.
        if ! cp -r "$dst" "$bak"; then
          warned+=("$name/ (backup failed, not upgraded)")
          continue
        fi
        if ! rm -rf "$dst"; then
          warned+=("$name/ (remove failed, not upgraded — backup at $bak)")
          continue
        fi
        if ! ln -sf "$src" "$dst"; then
          if mv "$bak" "$dst" 2>/dev/null; then
            warned+=("$name/ (symlink failed, original restored from backup)")
          else
            warned+=("$name/ (symlink failed AND restore failed — recover manually: mv \"$bak\" \"$dst\")")
          fi
          continue
        fi
        upgraded+=("$name/ (backed up to $bak)")
      else
        warned+=("$name/ (exists at $dst, not overwriting — re-run with --upgrade to replace)")
      fi
      continue
    fi

    ln -sf "$src" "$dst"
    installed+=("$name/")
  done
}

symlink_files "$SCRIPT_DIR/hooks"   "$HOME/.claude/hooks"
symlink_files "$SCRIPT_DIR/agents"  "$HOME/.claude/agents"
symlink_dirs  "$SCRIPT_DIR/skills"  "$HOME/.claude/skills"

# Track installed count before bin so we can detect fresh bin installs below.
_installed_before_bin=${#installed[@]}
symlink_files "$SCRIPT_DIR/bin"     "$HOME/.trimkit/bin"

# ---------------------------------------------------------------------------
# Install directory record (used by trimkit-update-check to find package.json)
# ---------------------------------------------------------------------------

# Write the absolute path of this trimkit clone to ~/.trimkit/install-dir so
# trimkit-update-check can locate the local package.json without resolving
# symlinks (which is not portable across macOS and Linux).
printf '%s\n' "$SCRIPT_DIR" > "$HOME/.trimkit/install-dir.tmp" \
  && mv "$HOME/.trimkit/install-dir.tmp" "$HOME/.trimkit/install-dir" \
  || echo "Warning: could not write ~/.trimkit/install-dir — update checks will be skipped" >&2

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
# Hooks merge
# ---------------------------------------------------------------------------

hooks_merged=()
hooks_skipped=()
hooks_failed=()

merge_hooks() {
  local src="$SCRIPT_DIR/settings/hooks.json"
  local dst="$HOME/.claude/settings.json"

  if [ ! -f "$src" ]; then
    return
  fi

  # Ensure destination exists with at least an empty object
  if [ ! -f "$dst" ]; then
    echo "{}" > "$dst"
  fi

  # Use Python to merge hooks without duplicates.
  # For each hook event type (PreToolUse, etc.) and each matcher entry in the
  # source, find or create the matching entry in the destination, then add any
  # hook commands that are not already present (matched by "command" field).
  merge_result="$(python3 - "$src" "$dst" <<'PYEOF'
import sys, json, copy

src_path, dst_path = sys.argv[1], sys.argv[2]

with open(src_path) as f:
    src = json.load(f)
with open(dst_path) as f:
    dst = json.load(f)

src_hooks = src.get("hooks", {})
dst_hooks = dst.setdefault("hooks", {})

added = []
skipped = []

for event_type, src_entries in src_hooks.items():
    dst_entries = dst_hooks.setdefault(event_type, [])

    for src_entry in src_entries:
        matcher = src_entry.get("matcher", "")

        # Find existing destination entry with same matcher
        dst_entry = next((e for e in dst_entries if e.get("matcher") == matcher), None)
        if dst_entry is None:
            dst_entry = {"matcher": matcher, "hooks": []}
            dst_entries.append(dst_entry)

        dst_cmds = {h.get("command") for h in dst_entry.get("hooks", [])}

        for hook in src_entry.get("hooks", []):
            cmd = hook.get("command")
            if cmd in dst_cmds:
                skipped.append(cmd)
            else:
                dst_entry.setdefault("hooks", []).append(copy.deepcopy(hook))
                dst_cmds.add(cmd)
                added.append(cmd)

with open(dst_path, "w") as f:
    json.dump(dst, f, indent=2)
    f.write("\n")

# Report results on stdout for the shell to parse
for cmd in added:
    print("ADDED:" + cmd)
for cmd in skipped:
    print("SKIPPED:" + cmd)
PYEOF
  )" || { hooks_failed+=("settings/hooks.json (python error)"); return; }

  while IFS= read -r line; do
    case "$line" in
      ADDED:*)   hooks_merged+=("${line#ADDED:}") ;;
      SKIPPED:*) hooks_skipped+=("${line#SKIPPED:}") ;;
    esac
  done <<< "$merge_result"
}

merge_hooks

# ---------------------------------------------------------------------------
# CLAUDE.md injection
# ---------------------------------------------------------------------------

claude_md_result=""   # "injected", "updated", or "failed:<reason>"

inject_claude_md() {
  local src="$SCRIPT_DIR/settings/claude-md.md"
  local dst="$HOME/.claude/CLAUDE.md"
  local begin='<!-- BEGIN TRIMKIT -->'
  local end='<!-- END TRIMKIT -->'

  if [ ! -f "$src" ]; then
    claude_md_result="failed:settings/claude-md.md not found"
    return
  fi

  # Create CLAUDE.md if it doesn't exist yet
  if [ ! -f "$dst" ]; then
    if ! mkdir -p "$(dirname "$dst")"; then
      claude_md_result="failed:could not create directory $(dirname "$dst")"
      return
    fi
    if ! touch "$dst"; then
      claude_md_result="failed:could not create $dst"
      return
    fi
  fi

  if grep -qF "$begin" "$dst" 2>/dev/null; then
    # Block exists — replace the region between delimiters (inclusive) with
    # the new block using Python, preserving everything outside.
    python3 - "$dst" "$begin" "$end" "$src" <<'PYEOF'
import sys

dst_path, begin, end, src_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

with open(dst_path) as f:
    lines = f.readlines()
with open(src_path) as f:
    new_content = f.read()

# Find the begin/end line indices
start_idx = end_idx = None
for i, line in enumerate(lines):
    if begin in line and start_idx is None:
        start_idx = i
    if end in line and start_idx is not None and end_idx is None:
        end_idx = i

if start_idx is None or end_idx is None:
    missing = "BEGIN" if start_idx is None else "END"
    print(f"error: could not find {missing} delimiter in {dst_path}", file=sys.stderr)
    sys.exit(1)

block = begin + '\n' + new_content.rstrip('\n') + '\n' + end + '\n'
result = lines[:start_idx] + [block] + lines[end_idx + 1:]

with open(dst_path, 'w') as f:
    f.writelines(result)
PYEOF
    # shellcheck disable=SC2181 — $? check needed: heredoc exit status can't use ||
    if [ $? -ne 0 ]; then
      claude_md_result="failed:python error updating ~/.claude/CLAUDE.md"
      return
    fi
    claude_md_result="updated"
  else
    # No block yet — append to end of file, with a blank line separator
    {
      # Ensure file ends with a newline before appending
      [ -s "$dst" ] && printf '\n'
      printf '%s\n' "$begin"
      cat "$src"
      printf '%s\n' "$end"
    } >> "$dst" || { claude_md_result="failed:could not write to $dst"; return; }
    claude_md_result="injected"
  fi
}

inject_claude_md

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

if [ ${#upgraded[@]} -gt 0 ]; then
  echo ""
  echo "Upgraded (replaced with symlinks):"
  for f in "${upgraded[@]}"; do echo "  ↑ $f"; done
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

if [ ${#hooks_merged[@]} -gt 0 ]; then
  echo ""
  echo "Hooks merged into ~/.claude/settings.json:"
  for f in "${hooks_merged[@]}"; do echo "  ✓ $f"; done
fi

if [ ${#hooks_skipped[@]} -gt 0 ]; then
  echo ""
  echo "Hooks already present (skipped):"
  for f in "${hooks_skipped[@]}"; do echo "  - $f"; done
fi

if [ ${#hooks_failed[@]} -gt 0 ]; then
  echo ""
  echo "Hook merge failures:"
  for f in "${hooks_failed[@]}"; do echo "  ✗ $f"; done
fi

case "$claude_md_result" in
  injected) echo ""; echo "CLAUDE.md: injected TrimKit block into ~/.claude/CLAUDE.md" ;;
  updated)  echo ""; echo "CLAUDE.md: updated TrimKit block in ~/.claude/CLAUDE.md" ;;
  failed:*) echo "" >&2; echo "CLAUDE.md: error — ${claude_md_result#failed:}" >&2; exit 1 ;;
esac

# Offer to add ~/.trimkit/bin to PATH when any bin script was freshly installed.
# Uses a count captured before the bin symlink_files call to scope detection
# to bin/ only, avoiding false positives from hooks/agents with similar names.
if [ "${#installed[@]}" -gt "$_installed_before_bin" ]; then
  if ! echo "$PATH" | grep -qF "$HOME/.trimkit/bin"; then
    echo ""
    echo "Note: ~/.trimkit/bin is not on your PATH."

    # Detect the most likely shell profile to modify.
    if [ -f "$HOME/.zshrc" ]; then
      _shell_profile="$HOME/.zshrc"
    elif [ -f "$HOME/.bashrc" ]; then
      _shell_profile="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      _shell_profile="$HOME/.bash_profile"
    else
      _shell_profile=""
    fi

    # _manual_path_instructions is a helper to avoid repeating the fallback text.
    _manual_path_instructions() {
      echo "  Add this to your shell profile manually:"
      echo "    export PATH=\"\$HOME/.trimkit/bin:\$PATH\""
    }

    # Only prompt interactively when /dev/tty is accessible. Non-interactive
    # installs (curl | bash, CI, Docker) fail to open /dev/tty, which would
    # abort the script under set -euo pipefail. We test first with a subshell
    # open so the abort can't propagate.
    if [ -n "$_shell_profile" ] && </dev/tty true 2>/dev/null; then
      # Show which profile was detected so the user can say no if it's wrong.
      printf "  Detected shell profile: %s\n" "$_shell_profile"
      printf "  Add PATH export now? [Y/n] "
      read -r _path_answer </dev/tty || _path_answer="n"
      case "${_path_answer:-Y}" in
        [Yy]*)
          # Idempotency: skip if the profile already references trimkit/bin
          # (e.g. from a previous install in a shell that hasn't sourced the file yet).
          if grep -qF '.trimkit/bin' "$_shell_profile" 2>/dev/null; then
            echo "  $_shell_profile already has ~/.trimkit/bin — run 'source $_shell_profile' or open a new terminal."
          elif printf '\nexport PATH="$HOME/.trimkit/bin:$PATH"\n' >> "$_shell_profile"; then
            echo "  Added. Run 'source $_shell_profile' or open a new terminal to apply."
          else
            echo "  ERROR: Could not write to $_shell_profile (check permissions)." >&2
            _manual_path_instructions
          fi
          ;;
        *)
          echo "  Skipped."
          _manual_path_instructions
          ;;
      esac
    else
      # No TTY (piped/CI install) or no recognizable shell profile — print manual instructions.
      _manual_path_instructions
    fi
  fi
fi

if [ ! -f "$HOME/.claude/sysops/deployments.json" ]; then
  echo ""
  echo "Note: To use the sysops agent, create your deployment registry at"
  echo "  ~/.claude/sysops/deployments.json"
  echo "See $SCRIPT_DIR/sysops/deployments.example.json for the format."
fi

# Show prod-debug setup note only on fresh install (not on every re-run)
prod_debug_just_installed=false
for f in "${installed[@]+"${installed[@]}"}"; do
  [ "$f" = "prod-debug/" ] && prod_debug_just_installed=true && break
done
if [ "$prod_debug_just_installed" = true ]; then
  echo ""
  echo "Note: prod-debug was installed. To set it up for a project:"
  echo "  1. Create .claude/prod-debug/config.json in your project root"
  echo "     (see $SCRIPT_DIR/skills/prod-debug/SKILL.md for the format)"
  echo "  2. Run /prod-debug bootstrap in Claude Code to build the schema"
  echo "     and container registry from your migrations and compose files"
  echo "  3. Write .claude/prod-debug/prod-env.md by hand with SSH alias,"
  echo "     domain, VPS details, and key env var names"
fi
