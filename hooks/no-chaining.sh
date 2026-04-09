#!/bin/bash
# no-chaining.sh — PreToolUse hook that blocks command chaining
#
# Blocks Bash commands containing &&, ||, or | (pipes) outside of quoted strings.
# Semicolons are intentionally excluded — they're ambiguous due to shell syntax
# (for/do/done, if/then/fi, etc.).
#
# Known limitations:
# - Quote stripping is naive (doesn't handle escaped quotes or nested quotes)
# - Won't catch chaining inside $() or backtick subshells

command=$(jq -r '.tool_input.command // empty')
[ -z "$command" ] && exit 0

# Strip single-quoted and double-quoted strings to avoid false positives
stripped=$(printf '%s' "$command" | sed "s/'[^']*'//g" | sed 's/"[^"]*"//g')

# Check if a 'git' segment uses only safe read-only subcommands.
# Handles optional flags before the subcommand (e.g. git -C /path log ...).
# Each flag group may optionally consume one value token (e.g. -C /path).
git_segment_safe() {
  local segment="$1"
  printf '%s' "$segment" | grep -qE '^git([[:space:]]+-\S+([[:space:]]+\S+)?)*[[:space:]]+(branch|diff|log|ls-files|rev-parse|show|status)([[:space:]]|$)'
}

# Helper: check that every segment in a newline-separated list starts with a safe
# read-only command. Used for both | and || allowlisting.
all_segments_safe() {
  local segments="$1"
  while IFS= read -r segment; do
    local trimmed
    trimmed=$(printf '%s' "$segment" | sed 's/^[[:space:]]*//')
    [ -z "$trimmed" ] && continue
    if printf '%s' "$trimmed" | grep -qE '^git([[:space:]]|$)'; then
      # Git command: only allow safe read-only subcommands
      if ! git_segment_safe "$trimmed"; then
        return 1
      fi
    elif ! printf '%s' "$trimmed" | grep -qE '^(awk|basename|cat|cut|date|dirname|echo|egrep|fgrep|grep|head|jq|ls|printf|sed|sort|tail|tr|uniq|wc)([[:space:]]|$)'; then
      return 1
    fi
  done <<< "$segments"
  return 0
}

# Emit a block response with the original commands split and numbered, so the
# agent can run them as separate Bash calls without re-parsing the original.
# Usage: block_with_hint <reason-prefix> <delimiter-regex> <original-command>
block_with_hint() {
  local prefix="$1" delim="$2" orig="$3"
  local n=1 msg="${prefix} Run each as a separate Bash call:"
  while IFS= read -r seg; do
    seg=$(printf '%s' "$seg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$seg" ] && continue
    msg="${msg}
${n}. ${seg}"
    n=$((n+1))
  done <<< "$(printf '%s' "$orig" | sed "s/[[:space:]]*${delim}[[:space:]]*/\n/g")"
  printf '%s\n' "{\"continue\":false,\"stopReason\":$(printf '%s' "$msg" | jq -Rs .)}"
}

# Check for && — always blocked.
if printf '%s' "$stripped" | grep -qE '&&'; then
  block_with_hint "Command chaining (&&) is not allowed." '&&' "$command"
  exit 0
fi

# Check for || — allow only if EVERY segment is a safe read-only command.
# Unlike pipes, both sides of || execute independently, so we must vet all of them.
if printf '%s' "$stripped" | grep -qF '||'; then
  segments=$(printf '%s' "$stripped" | sed 's/||/\n/g')
  if ! all_segments_safe "$segments"; then
    block_with_hint "Command chaining (||) is not allowed." '||' "$command"
    exit 0
  fi
fi

# Check for pipes: remove || (already handled above), then look for remaining |
# Also exclude redirections like 2>&1 which contain no standalone |
no_double_pipe=$(printf '%s' "$stripped" | sed 's/||//g')
if printf '%s' "$no_double_pipe" | grep -qF '|'; then
  # Allow pipes only if EVERY segment (including the first) is a safe read-only command.
  # This prevents piping output of destructive commands even into safe filters.
  segments=$(printf '%s' "$no_double_pipe" | tr '|' '\n')
  if ! all_segments_safe "$segments"; then
    block_with_hint "Pipe chaining (|) is not allowed." '|' "$command"
    exit 0
  fi
fi
