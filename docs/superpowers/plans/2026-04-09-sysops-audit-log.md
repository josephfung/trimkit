# Sysops Audit Log Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persistent JSONL audit trail of every sysops invocation to `~/.claude/sysops/audit.jsonl`, readable via `/sysops log [deployment]`.

**Architecture:** A new shell script (`bin/trimkit-sysops-log`) handles JSONL appending by reading JSON from stdin, injecting a `ts` field, and appending to the log file. The sysops agent calls it via temp-file redirect at the end of each status check and maintenance run. The sysops skill handles `/sysops log` directly (no subagent delegation) using an inline Python3 formatter.

**Tech Stack:** Bash, Python 3 (already required by `install.sh`)

---

## File Map

| Action   | Path                                          | Responsibility                              |
|----------|-----------------------------------------------|---------------------------------------------|
| Create   | `bin/trimkit-sysops-log`                      | Atomic JSONL appender (stdin → log file)    |
| Create   | `tests/bin/trimkit-sysops-log.bats`           | Bats unit tests for the script              |
| Create   | `sysops/README.md`                            | Log schema + `/sysops log` documentation   |
| Modify   | `install.sh`                                  | Symlink `bin/` to `~/.trimkit/bin/`; PATH note |
| Modify   | `agents/sysops.md`                            | Session UUID, project capture, log calls    |
| Modify   | `skills/sysops/SKILL.md`                      | Route `/sysops log` directly                |

---

## Task 1: bin/trimkit-sysops-log (TDD)

**Files:**
- Create: `tests/bin/trimkit-sysops-log.bats`
- Create: `bin/trimkit-sysops-log`

### No-chaining constraint

The hook at `hooks/no-chaining.sh` blocks pipes (`|`) unless both sides are safe read-only commands. `trimkit-sysops-log` is not in the allowlist, so `echo '...' | trimkit-sysops-log` is blocked in Claude Code. The agent works around this by writing JSON to a temp file (`>` redirect, allowed), then redirecting that file into the script (`< /tmp/file`, also allowed), in separate Bash calls.

The script itself reads from stdin, so both workflows work:
```bash
# Agent workflow (3 Bash calls):
python3 -c "..." > /tmp/trimkit-sysops-entry.json   # call 1
trimkit-sysops-log < /tmp/trimkit-sysops-entry.json  # call 2
rm /tmp/trimkit-sysops-entry.json                     # call 3

# Direct invocation (no hook constraints):
echo '{"deployment":"Pulse",...}' | trimkit-sysops-log
```

---

- [ ] **Step 1.1: Create the test file**

```bash
mkdir -p tests/bin
```

Create `tests/bin/trimkit-sysops-log.bats`:

```bash
#!/usr/bin/env bats

# tests/bin/trimkit-sysops-log.bats — tests for bin/trimkit-sysops-log

setup() {
  load '../test_helper/bats-support/load'
  load '../test_helper/bats-assert/load'
  SCRIPT="$BATS_TEST_DIRNAME/../../bin/trimkit-sysops-log"
  TMPDIR_CUSTOM="$(mktemp -d)"
  export TRIMKIT_SYSOPS_LOG_DIR="$TMPDIR_CUSTOM"
  export TRIMKIT_SYSOPS_LOG_FILE="$TMPDIR_CUSTOM/audit.jsonl"
}

teardown() {
  rm -rf "$TMPDIR_CUSTOM"
}

SAMPLE='{"session":"s1","project":"myapp","deployment":"Pulse","env":"prod","action":"status_check","containers":{"pulse":"healthy"},"unregistered_containers":[],"notes":""}'

@test "script exists and is executable" {
  [ -x "$SCRIPT" ]
}

@test "creates log directory if it does not exist" {
  rm -rf "$TMPDIR_CUSTOM"
  echo "$SAMPLE" | bash "$SCRIPT"
  [ -d "$TMPDIR_CUSTOM" ]
}

@test "appends one line per call" {
  echo "$SAMPLE" | bash "$SCRIPT"
  count="$(wc -l < "$TRIMKIT_SYSOPS_LOG_FILE" | tr -d ' ')"
  assert_equal "$count" "1"
}

@test "two calls produce two lines" {
  echo "$SAMPLE" | bash "$SCRIPT"
  echo "$SAMPLE" | bash "$SCRIPT"
  count="$(wc -l < "$TRIMKIT_SYSOPS_LOG_FILE" | tr -d ' ')"
  assert_equal "$count" "2"
}

@test "each line is valid JSON" {
  echo "$SAMPLE" | bash "$SCRIPT"
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    for line in f:
        json.loads(line)  # raises ValueError if invalid
"
}

@test "injects ts field in ISO 8601 UTC format" {
  echo "$SAMPLE" | bash "$SCRIPT"
  python3 -c "
import json, re
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    obj = json.loads(f.read().strip())
assert 'ts' in obj, 'ts field missing'
assert re.match(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$', obj['ts']), f'bad ts format: {obj[\"ts\"]}'
"
}

@test "preserves all input fields" {
  input='{"session":"abc","project":"curia","deployment":"MyApp","env":"prod","action":"maintenance","packages_upgraded":5,"reboot_performed":true,"reboot_duration_s":30,"containers":{"myapp":"healthy"},"unregistered_containers":["redis-tmp"],"notes":"all good"}'
  echo "$input" | bash "$SCRIPT"
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    obj = json.loads(f.read().strip())
assert obj['session'] == 'abc'
assert obj['deployment'] == 'MyApp'
assert obj['packages_upgraded'] == 5
assert obj['reboot_performed'] == True
assert obj['reboot_duration_s'] == 30
assert obj['unregistered_containers'] == ['redis-tmp']
assert obj['notes'] == 'all good'
"
}

@test "concurrent writes all produce valid JSONL lines" {
  for i in 1 2 3 4 5; do
    echo "{\"session\":\"s${i}\",\"project\":\"p\",\"deployment\":\"D\",\"env\":\"prod\",\"action\":\"status_check\",\"containers\":{},\"unregistered_containers\":[],\"notes\":\"\"}" \
      | bash "$SCRIPT" &
  done
  wait
  python3 -c "
import json
with open('$TRIMKIT_SYSOPS_LOG_FILE') as f:
    lines = [l for l in f if l.strip()]
assert len(lines) == 5, f'expected 5 lines, got {len(lines)}'
for line in lines:
    json.loads(line)
"
}

@test "exits 0 on success" {
  run bash -c "echo '$SAMPLE' | bash '$SCRIPT'"
  assert_success
}
```

- [ ] **Step 1.2: Run tests and confirm they fail**

```bash
npm --prefix /Users/josephfung/Projects/trimkit-sysops-audit-log run test -- tests/bin/trimkit-sysops-log.bats
```

Expected: All tests fail — `SCRIPT` doesn't exist yet. If there's no npm test runner, run directly:

```bash
./tests/test_helper/bats-core/bin/bats tests/bin/trimkit-sysops-log.bats
```

Expected failure output should include "No such file or directory" or similar.

- [ ] **Step 1.3: Create `bin/trimkit-sysops-log`**

```bash
mkdir -p bin
```

Create `bin/trimkit-sysops-log`:

```bash
#!/usr/bin/env bash
# trimkit-sysops-log — Append a sysops audit entry to the persistent JSONL log.
#
# Reads a JSON object from stdin, injects a "ts" field (current UTC timestamp),
# and appends the entry as a single line to the audit log.
#
# The single printf write is atomic on Linux/macOS for payloads under PIPE_BUF
# (~4KB), which comfortably covers the audit entry schema.
#
# Environment overrides (for testing):
#   TRIMKIT_SYSOPS_LOG_DIR   override log directory   (default: ~/.claude/sysops)
#   TRIMKIT_SYSOPS_LOG_FILE  override log file path   (default: $LOG_DIR/audit.jsonl)
#
# Usage:
#   echo '{"session":"...","deployment":"Pulse",...}' | trimkit-sysops-log
set -euo pipefail

LOG_DIR="${TRIMKIT_SYSOPS_LOG_DIR:-${HOME}/.claude/sysops}"
LOG_FILE="${TRIMKIT_SYSOPS_LOG_FILE:-${LOG_DIR}/audit.jsonl}"

# Read JSON from stdin
json="$(cat)"

# Current UTC timestamp
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Inject ts via python3 (already required by install.sh)
entry="$(python3 -c "
import json, sys
obj = json.loads(sys.argv[1])
obj['ts'] = sys.argv[2]
print(json.dumps(obj, separators=(',', ':')))
" "$json" "$ts")"

# Create log directory if needed
mkdir -p "$LOG_DIR"

# Append — atomic for single-line writes under PIPE_BUF
printf '%s\n' "$entry" >> "$LOG_FILE"
```

- [ ] **Step 1.4: Make the script executable**

```bash
chmod +x bin/trimkit-sysops-log
```

- [ ] **Step 1.5: Run tests and confirm they pass**

```bash
./tests/test_helper/bats-core/bin/bats tests/bin/trimkit-sysops-log.bats
```

Expected: All 8 tests pass.

- [ ] **Step 1.6: Commit**

```bash
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log add bin/trimkit-sysops-log tests/bin/trimkit-sysops-log.bats
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log commit -m "feat: add trimkit-sysops-log JSONL appender script with tests"
```

---

## Task 2: install.sh — bin/ symlink support

**Files:**
- Modify: `install.sh`

The script currently symlinks `hooks/`, `agents/`, and `skills/`. Add `bin/` to `~/.trimkit/bin/` using the existing `symlink_files` helper. Also add a one-time PATH note when bin scripts are freshly installed.

- [ ] **Step 2.1: Add bin symlink call after the existing symlink calls**

In `install.sh`, find the block:
```bash
symlink_files "$SCRIPT_DIR/hooks"   "$HOME/.claude/hooks"
symlink_files "$SCRIPT_DIR/agents"  "$HOME/.claude/agents"
symlink_dirs  "$SCRIPT_DIR/skills"  "$HOME/.claude/skills"
```

Add immediately after:
```bash
symlink_files "$SCRIPT_DIR/bin"     "$HOME/.trimkit/bin"
```

- [ ] **Step 2.2: Add PATH note in the summary section**

In `install.sh`, find the block that shows the sysops deployment note (near the end):
```bash
if [ ! -f "$HOME/.claude/sysops/deployments.json" ]; then
```

Add immediately before it:

```bash
# Show bin PATH note on first install of any bin script
bin_just_installed=false
for f in "${installed[@]+"${installed[@]}"}"; do
  [[ "$f" == trimkit-* ]] && bin_just_installed=true && break
done
if [ "$bin_just_installed" = true ]; then
  if ! echo "$PATH" | grep -qF "$HOME/.trimkit/bin"; then
    echo ""
    echo "Note: ~/.trimkit/bin is not on your PATH."
    echo "  Add this to your shell profile (~/.zshrc or ~/.bashrc):"
    echo "    export PATH=\"\$HOME/.trimkit/bin:\$PATH\""
  fi
fi
```

- [ ] **Step 2.3: Run install.sh to confirm bin/ is handled (dry-run check)**

```bash
bash /Users/josephfung/Projects/trimkit-sysops-audit-log/install.sh 2>&1 | grep -E "(trimkit-sysops-log|\.trimkit/bin|PATH)"
```

Expected: Output contains either "trimkit-sysops-log" in installed/skipped list, and optionally the PATH note.

- [ ] **Step 2.4: Commit**

```bash
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log add install.sh
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log commit -m "feat: install bin/ scripts to ~/.trimkit/bin on install"
```

---

## Task 3: agents/sysops.md — session UUID, project, log calls

**Files:**
- Modify: `agents/sysops.md`

Three additions:
1. Session UUID + project capture in Setup
2. Audit log call at end of status check per deployment
3. Audit log call as new step 6 in maintenance

- [ ] **Step 3.1: Add session UUID and project capture to the Setup section**

In `agents/sysops.md`, find the Setup section ending with:
```
If the file is missing, tell the user to create it at `~/.claude/sysops/deployments.json` using the example at `https://github.com/josephfung/trimkit/blob/main/sysops/deployments.example.json`.
```

Add immediately after:

````markdown
Then generate a session identifier and capture the current project name — both are included in every audit log entry:

```bash
SESSION=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
PROJECT=$(basename "$PWD")
```
````

- [ ] **Step 3.2: Add audit log subsection to the Status check section**

In `agents/sysops.md`, find the end of the status check section — the example output block ending with:
```
  Containers (unregistered): none
```

Add immediately after the closing code block:

````markdown
### Audit log (status check)

After presenting the report for each deployment, write an audit log entry. Run these three commands in sequence (separate Bash calls — no pipes or chaining):

**Call 1** — build the JSON entry (substitute actual collected values for the placeholders):
```bash
python3 -c "
import json, sys
print(json.dumps({
    'session':                sys.argv[1],
    'project':                sys.argv[2],
    'deployment':             sys.argv[3],
    'env':                    sys.argv[4],
    'action':                 'status_check',
    'containers':             json.loads(sys.argv[5]),
    'unregistered_containers': json.loads(sys.argv[6]),
    'notes':                  sys.argv[7]
}))
" \
  "$SESSION" \
  "$PROJECT" \
  "<deployment name, e.g. Pulse>" \
  "<deployment env, e.g. prod>" \
  '<containers JSON object, e.g. {"pulse":"healthy","pulse-web":"healthy"}>' \
  '<unregistered containers JSON array, e.g. ["redis-temp"] or []>' \
  "<notable findings or empty string>" \
  > /tmp/trimkit-sysops-entry.json
```

**Call 2** — append to the audit log:
```bash
if command -v trimkit-sysops-log > /dev/null 2>&1; then trimkit-sysops-log < /tmp/trimkit-sysops-entry.json; fi
```

**Call 3** — clean up:
```bash
rm -f /tmp/trimkit-sysops-entry.json
```

If `trimkit-sysops-log` is not found (trimkit not installed), skip logging and note it in the report output: `(audit log skipped — trimkit-sysops-log not on PATH)`. Non-fatal; must not block the report.
````

- [ ] **Step 3.3: Add step 6 (audit log) to the Maintenance section**

In `agents/sysops.md`, find step 5 of the Maintenance section:
```
### 5. Log to memory
```

Add immediately after its closing content (the memory entry format block):

````markdown
### 6. Write audit log entry

After completing maintenance on a deployment (success or failure), write an audit entry. Run these three commands in sequence:

**Call 1** — build the JSON entry (substitute actual collected values; use `0` for `packages_upgraded` on failure, `"no"` for `reboot_performed` if skipped, `"null"` for `reboot_duration_s` if no reboot):
```bash
python3 -c "
import json, sys
entry = {
    'session':                 sys.argv[1],
    'project':                 sys.argv[2],
    'deployment':              sys.argv[3],
    'env':                     sys.argv[4],
    'action':                  'maintenance',
    'packages_upgraded':       int(sys.argv[5]),
    'reboot_performed':        sys.argv[6] == 'yes',
    'reboot_duration_s':       int(sys.argv[7]) if sys.argv[7] != 'null' else None,
    'containers':              json.loads(sys.argv[8]),
    'unregistered_containers': json.loads(sys.argv[9]),
    'notes':                   sys.argv[10]
}
print(json.dumps(entry))
" \
  "$SESSION" \
  "$PROJECT" \
  "<deployment name>" \
  "<deployment env>" \
  "<packages upgraded count, e.g. 11>" \
  "<yes or no>" \
  "<reboot duration in seconds, or null>" \
  '<containers JSON object, e.g. {"pulse":"healthy"}>' \
  '<unregistered containers JSON array, e.g. []>' \
  "<any failures or issues, or empty string>" \
  > /tmp/trimkit-sysops-entry.json
```

**Call 2** — append to the audit log:
```bash
if command -v trimkit-sysops-log > /dev/null 2>&1; then trimkit-sysops-log < /tmp/trimkit-sysops-entry.json; fi
```

If the `if` branch does not execute (trimkit not installed), include `(audit log skipped — trimkit-sysops-log not on PATH)` in the maintenance report for that deployment.

**Call 3** — clean up:
```bash
rm -f /tmp/trimkit-sysops-entry.json
```
````

- [ ] **Step 3.4: Commit**

```bash
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log add agents/sysops.md
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log commit -m "feat: add session UUID, project capture, and audit log calls to sysops agent"
```

---

## Task 4: skills/sysops/SKILL.md — /sysops log routing

**Files:**
- Modify: `skills/sysops/SKILL.md`

Add a `log` branch that handles the command directly (reading and formatting the log file) before the existing subagent delegation.

- [ ] **Step 4.1: Replace SKILL.md content**

Replace the entire content of `skills/sysops/SKILL.md` with:

````markdown
---
name: sysops
description: Invoke the sysops subagent for VPS maintenance. Use when the user runs /sysops with an optional argument like "status", "update Pulse", or "update my servers".
---

# Sysops

If the argument starts with `log`, handle it directly — do NOT delegate to the sysops subagent.

## /sysops log

Parse the argument:
- `/sysops log` → show last 10 entries across all deployments
- `/sysops log <Deployment>` → show last 10 entries for that deployment (case-insensitive match)
- `/sysops log <Deployment> --last <N>` → show last N entries for that deployment

Run this command, substituting `DEPLOYMENT_FILTER` (empty string `""` if no deployment was given) and `LIMIT` (default `10`):

```bash
DEPLOYMENT_FILTER="<filter or empty string>" LIMIT=<N> python3 -c "
import json, os, sys

log_file = os.path.expanduser('~/.claude/sysops/audit.jsonl')
deployment_filter = os.environ.get('DEPLOYMENT_FILTER', '')
limit = int(os.environ.get('LIMIT', '10'))

if not os.path.exists(log_file):
    print('No audit log found at ~/.claude/sysops/audit.jsonl')
    print('Logs are written after each /sysops status or /sysops update run.')
    sys.exit(0)

entries = []
with open(log_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if deployment_filter and obj.get('deployment', '').lower() != deployment_filter.lower():
            continue
        entries.append(obj)

entries = entries[-limit:]

if not entries:
    msg = 'No entries found'
    if deployment_filter:
        msg += f' for deployment {deployment_filter!r}'
    print(msg + '.')
    sys.exit(0)

for e in entries:
    ts        = e.get('ts', 'unknown')
    dep       = e.get('deployment', 'unknown')
    env       = e.get('env', '?')
    action    = e.get('action', '?')
    project   = e.get('project', '?')
    print(f'{ts}  {dep} [{env}]  {action}  (project: {project})')

    if action == 'maintenance':
        pkgs  = e.get('packages_upgraded', 0)
        reboot = e.get('reboot_performed', False)
        dur   = e.get('reboot_duration_s')
        reboot_str = f'yes ({dur}s)' if reboot and dur else ('yes' if reboot else 'no')
        print(f'  Packages upgraded: {pkgs} · Reboot: {reboot_str}')

    containers = e.get('containers', {})
    if containers:
        parts = [n + (' \u2713' if s == 'healthy' else ' \u2717') for n, s in containers.items()]
        print('  Containers: ' + '  '.join(parts))

    unregistered = e.get('unregistered_containers', [])
    unreg_str = '  '.join(u + ' \u26a0' for u in unregistered) if unregistered else 'none'
    print(f'  Unregistered: {unreg_str}')

    notes = e.get('notes', '')
    if notes:
        print(f'  Notes: {notes}')
    print()
"
```

---

Otherwise, delegate to the `sysops` subagent using the Agent tool.

Pass the user's argument directly as the prompt. If no argument was given, default to a status check across all deployments.

Examples:
- `/sysops` → prompt: "Check the status of all my servers"
- `/sysops status` → prompt: "Check the status of all my servers"
- `/sysops update Pulse` → prompt: "Update Pulse"
- `/sysops update my servers` → prompt: "Update all my servers"

Do not add any preamble or explanation — just invoke the subagent immediately.
````

- [ ] **Step 4.2: Commit**

```bash
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log add skills/sysops/SKILL.md
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log commit -m "feat: add /sysops log routing to sysops skill"
```

---

## Task 5: sysops/README.md — documentation

**Files:**
- Create: `sysops/README.md`

- [ ] **Step 5.1: Create `sysops/README.md`**

```markdown
# Sysops

Configuration and documentation for the `sysops` agent and skill.

## Deployment registry

The sysops agent reads `~/.claude/sysops/deployments.json` at startup. See `deployments.example.json` for the format.

## Audit log

Every sysops invocation writes a structured entry to `~/.claude/sysops/audit.jsonl`. The file is append-only — entries are never modified or deleted.

### Log location

```
~/.claude/sysops/audit.jsonl
```

### Schema

Each line is a JSON object:

| Field                   | Type              | Present when        | Description                                              |
|-------------------------|-------------------|---------------------|----------------------------------------------------------|
| `ts`                    | string (ISO 8601) | always              | UTC timestamp when the entry was written                 |
| `session`               | string (UUID)     | always              | Identifies all entries from a single `/sysops` invocation |
| `project`               | string            | always              | basename of the working directory at invocation time     |
| `deployment`            | string            | always              | Deployment name from `deployments.json`                  |
| `env`                   | string            | always              | Deployment env (e.g. `prod`)                             |
| `action`                | string            | always              | `status_check` or `maintenance`                          |
| `containers`            | object            | always              | Map of container name → `"healthy"` or `"unhealthy"`     |
| `unregistered_containers` | array           | always              | Container names not in the deployment manifest           |
| `notes`                 | string            | always              | Free-text summary of issues; empty string if none        |
| `packages_upgraded`     | integer           | maintenance only    | Number of packages upgraded by `apt`                     |
| `reboot_performed`      | boolean           | maintenance only    | Whether the server was rebooted                          |
| `reboot_duration_s`     | integer or null   | maintenance only    | Seconds until server came back; null if no reboot        |

### Example entry

```json
{"ts":"2026-04-09T12:00:00Z","session":"a1b2c3d4-e5f6-7890-abcd-ef1234567890","project":"curia","deployment":"Pulse","env":"prod","action":"maintenance","packages_upgraded":11,"reboot_performed":true,"reboot_duration_s":45,"containers":{"pulse":"healthy","pulse-web":"healthy","pulse-caddy":"healthy"},"unregistered_containers":["redis-temp"],"notes":"redis-temp flagged as unregistered, user chose to investigate"}
```

## Viewing the audit log

Use the `/sysops log` slash command:

```
/sysops log                    # last 10 entries, all deployments
/sysops log Pulse              # last 10 entries for Pulse
/sysops log Pulse --last 25    # last 25 entries for Pulse
```

## trimkit-sysops-log

`bin/trimkit-sysops-log` is the shell script that performs the actual log write. It reads JSON from stdin, injects `ts`, and appends to the log file. It is installed to `~/.trimkit/bin/` by `install.sh`.

Environment overrides for testing:
- `TRIMKIT_SYSOPS_LOG_DIR` — override the log directory
- `TRIMKIT_SYSOPS_LOG_FILE` — override the log file path
```

- [ ] **Step 5.2: Commit**

```bash
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log add sysops/README.md
git -C /Users/josephfung/Projects/trimkit-sysops-audit-log commit -m "docs: add sysops README with audit log schema and /sysops log usage"
```

---

## Final check

- [ ] **Run the full test suite** to confirm no regressions:

```bash
./tests/test_helper/bats-core/bin/bats tests/
```

Expected: All existing tests pass plus the new `tests/bin/trimkit-sysops-log.bats` tests.
