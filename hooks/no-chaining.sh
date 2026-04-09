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

# Helper: check that every segment in a newline-separated list starts with a safe
# read-only command. Used for both | and || allowlisting.
all_segments_safe() {
  local segments="$1"
  while IFS= read -r segment; do
    local trimmed
    trimmed=$(printf '%s' "$segment" | sed 's/^[[:space:]]*//')
    [ -z "$trimmed" ] && continue
    if ! printf '%s' "$trimmed" | grep -qE '^(tail|head|grep|egrep|fgrep|wc|sort|uniq|cut|awk|sed|tr|cat)([[:space:]]|$)'; then
      return 1
    fi
  done <<< "$segments"
  return 0
}

# Check for &&  — always blocked, no exceptions.
if printf '%s' "$stripped" | grep -qE '&&'; then
  printf '{"continue":false,"stopReason":"Command chaining detected (&&). Run each command as a separate Bash call."}\n'
  exit 0
fi

# Check for || — allow only if EVERY segment is a safe read-only command.
# Unlike pipes, both sides of || execute independently, so we must vet all of them.
if printf '%s' "$stripped" | grep -qF '||'; then
  segments=$(printf '%s' "$stripped" | sed 's/||/\n/g')
  if ! all_segments_safe "$segments"; then
    printf '{"continue":false,"stopReason":"Command chaining detected (||). Run each command as a separate Bash call."}\n'
    exit 0
  fi
fi

# Check for pipes: remove || (already handled above), then look for remaining |
# Also exclude redirections like 2>&1 which contain no standalone |
no_double_pipe=$(printf '%s' "$stripped" | sed 's/||//g')
if printf '%s' "$no_double_pipe" | grep -qF '|'; then
  # Allow pipes if every segment after the first goes to a safe read-only command.
  # The first segment can be anything (its output is just piped, never destructive).
  segments=$(printf '%s' "$no_double_pipe" | tr '|' '\n' | tail -n +2)
  if ! all_segments_safe "$segments"; then
    printf '{"continue":false,"stopReason":"Pipe chaining detected (|). Run each command as a separate Bash call."}\n'
    exit 0
  fi
fi
