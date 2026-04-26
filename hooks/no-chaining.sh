#!/bin/bash
# no-chaining.sh — PreToolUse hook that blocks command chaining
#
# Blocks Bash commands containing &&, ||, or | (pipes) outside of quoted strings.
# Semicolons are intentionally excluded — they're ambiguous due to shell syntax
# (for/do/done, if/then/fi, etc.).
#
# Pipe checks are ASYMMETRIC:
#   - Source (left-most segment): safe read-only util OR safe npm command
#   - Sinks (all subsequent segments): safe read-only utils only
# This lets "npm test | tail -60" through while still blocking "npm test | bash".
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

# Check if an 'npm' segment is safe to use as a pipe SOURCE.
#
# Safe non-run subcommands: test, t, ls, list, audit, outdated, view, info
# Safe run scripts: test, lint, check, typecheck, type-check, build, compile
#   (plus colon-namespaced variants like test:unit, lint:ci)
#
# Handles --prefix <path> and other value-consuming flags before the subcommand.
npm_segment_safe() {
  local segment="$1"

  # Must start with npm
  [[ "$segment" =~ ^npm([[:space:]]|$) ]] || return 1

  # Tokenize into a bash array (splits on whitespace)
  local tokens
  read -ra tokens <<< "$segment"

  local i=1  # start after 'npm'
  local subcommand="" script=""

  # npm flags that consume the next token as their value
  # (incomplete list — covers the common ones)
  local token
  while [ $i -lt ${#tokens[@]} ]; do
    token="${tokens[$i]}"
    case "$token" in
      --prefix|--loglevel|--workspace|-w|--tag|--otp|--registry|--userconfig)
        # Skip flag and its value argument
        i=$((i + 2))
        continue
        ;;
      -*)
        # Boolean flag — skip
        i=$((i + 1))
        continue
        ;;
    esac
    # First non-flag token is the subcommand
    subcommand="$token"
    i=$((i + 1))
    break
  done

  # Safe subcommands that don't need further inspection
  case "$subcommand" in
    test|t|ls|list|audit|outdated|view|info)
      return 0
      ;;
    run)
      # Fall through to check the script name
      ;;
    *)
      return 1
      ;;
  esac

  # For 'run', find the script name (first non-flag token after 'run')
  while [ $i -lt ${#tokens[@]} ]; do
    token="${tokens[$i]}"
    if [[ "$token" == -* ]]; then
      i=$((i + 1))
      continue
    fi
    script="$token"
    break
  done

  # Safe script names, with optional colon namespace (e.g. test:unit, lint:ci)
  [[ "$script" =~ ^(test|lint|check|typecheck|type-check|build|compile)(:[a-zA-Z0-9_-]+)?$ ]]
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
    elif ! printf '%s' "$trimmed" | grep -qE '^(awk|basename|cat|cut|date|dirname|echo|egrep|fgrep|find|grep|head|jq|ls|printf|sed|sort|tail|tr|uniq|wc)([[:space:]]|$)'; then
      return 1
    fi
  done <<< "$segments"
  return 0
}

# Emit a block response with the original commands split and numbered, so the
# agent can run them as separate Bash calls without re-parsing the original.
# Usage: block_with_hint <reason-prefix> <delimiter-regex> <original-command>
#
# Uses "continue":true so that Claude Code rejects the command but keeps the
# agent loop running — Claude can read the hint and retry with separate calls.
# "continue":false would terminate the session entirely, which is too disruptive.
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
  printf '%s\n' "{\"continue\":true,\"stopReason\":$(printf '%s' "$msg" | jq -Rs .)}"
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
  # Split into segments on |
  all_pipe_segments=$(printf '%s' "$no_double_pipe" | tr '|' '\n')

  # ASYMMETRIC check:
  #   Source (first segment): may be a safe read-only util OR a safe npm command.
  #   Sinks (remaining segments): must be safe read-only utils only.
  # This allows "npm test | tail -60" while blocking "npm test | bash".
  source_segment=$(printf '%s' "$all_pipe_segments" | head -n 1 | sed 's/^[[:space:]]*//')
  sink_segments=$(printf '%s' "$all_pipe_segments" | tail -n +2)

  source_ok=0
  if all_segments_safe "$source_segment"; then
    source_ok=1
  elif npm_segment_safe "$source_segment"; then
    source_ok=1
  fi

  sinks_ok=1
  if ! all_segments_safe "$sink_segments"; then
    sinks_ok=0
  fi

  if [ "$source_ok" -eq 0 ] || [ "$sinks_ok" -eq 0 ]; then
    block_with_hint "Pipe chaining (|) is not allowed." '|' "$command"
    exit 0
  fi
fi
