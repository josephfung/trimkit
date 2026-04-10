# Sysops Audit Log — Design Spec

**Date:** 2026-04-09
**Issue:** josephfung/trimkit#4
**Branch:** feat/sysops-audit-log

## Goal

Extend the sysops agent to write a persistent, append-only audit trail of every invocation to `~/.claude/sysops/audit.jsonl`. Each entry records what was done, to which server, from which project, and when — making the history queryable across sessions.

## Motivation

VPS maintenance mistakes are hard to diagnose after the fact. A persistent audit trail gives a timeline of every status check and maintenance run, what state the server was in, and what actions were taken. Useful for incident response, compliance, and general peace of mind.

## Architecture

Four components:

1. **`bin/trimkit-sysops-log`** — shell script, atomic JSONL appender
2. **`agents/sysops.md`** — updated to call the script at the end of each status check and maintenance run
3. **`skills/sysops/SKILL.md`** — updated to handle `/sysops log [deployment]` directly (no subagent)
4. **`sysops/README.md`** — documents the log format and `/sysops log` command

## Component Details

### 1. `bin/trimkit-sysops-log`

A shell script that:
- Reads a JSON object from stdin
- Injects `ts` (current UTC timestamp via `date -u +%Y-%m-%dT%H:%M:%SZ`)
- Creates `~/.claude/sysops/` if it doesn't exist
- Appends the entry to `~/.claude/sysops/audit.jsonl` via `printf '%s\n' "$json" >> file`, which is atomic on Linux/macOS for single-line writes under ~4KB (pipe buffer limit — well within our schema size)

The script does not generate `session` or `project` — those are provided by the caller (the agent).

Interface:
```bash
echo '{"session":"...","project":"curia","deployment":"Pulse",...}' | trimkit-sysops-log
```

The install script (`install.sh`) already puts trimkit binaries in `~/.trimkit/bin/` and adds that to PATH, so the agent calls `trimkit-sysops-log` directly.

### 2. Agent updates (`agents/sysops.md`)

Two additions:

**At invocation start**, generate a session UUID and capture the project name:
```bash
SESSION=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid)
PROJECT=$(basename "$PWD")
```

**At the end of each deployment's status check or maintenance**, construct a JSON object from collected data and pipe to the log script. The agent already collects all fields during its run — this step formalises the write.

For status checks, logged fields: `session`, `project`, `deployment`, `env`, `action: "status_check"`, `containers` (map of name→status), `unregistered_containers` (array), `notes`.

For maintenance runs, all of the above plus: `packages_upgraded` (int), `reboot_performed` (bool), `reboot_duration_s` (int or null).

### 3. Skill update (`skills/sysops/SKILL.md`)

If the argument starts with `log`, handle it directly rather than delegating to the subagent. Detect with: `[[ "$arg" == log* ]]`. Add this check before the existing subagent delegation:

- `/sysops log` → pretty-print the last 10 entries from `~/.claude/sysops/audit.jsonl`
- `/sysops log <deployment>` → filter to that deployment, last 10 entries
- `/sysops log <deployment> --last <N>` → last N entries for that deployment

Handled directly in the skill (read + format with bash), not delegated to the sysops subagent. This keeps the agent invocation reserved for actual server operations.

Output format (one block per entry, most recent last):
```
2026-04-09T12:00:00Z  Pulse [prod]  status_check  (project: curia)
  Containers: pulse ✓  pulse-web ✓  pulse-caddy ✓
  Unregistered: redis-temp ⚠
  Notes: redis-temp flagged as unregistered, user chose to investigate

2026-04-09T13:30:00Z  Pulse [prod]  maintenance  (project: curia)
  Packages upgraded: 11 · Reboot: yes (45s)
  Containers: pulse ✓  pulse-web ✓  pulse-caddy ✓
  Unregistered: none
```

### 4. `sysops/README.md`

Documents:
- Log file location: `~/.claude/sysops/audit.jsonl`
- Full JSON schema with field descriptions
- Append-only guarantee (the script never reads or modifies existing entries)
- `/sysops log` command syntax and example output

## Log Schema

```json
{
  "ts": "2026-04-09T12:00:00Z",
  "session": "a1b2c3d4-...",
  "project": "curia",
  "deployment": "Pulse",
  "env": "prod",
  "action": "status_check | maintenance",
  "packages_upgraded": 11,
  "reboot_performed": true,
  "reboot_duration_s": 45,
  "containers": {
    "pulse": "healthy",
    "pulse-web": "healthy",
    "pulse-caddy": "healthy"
  },
  "unregistered_containers": ["redis-temp"],
  "notes": "redis-temp flagged as unregistered, user chose to investigate"
}
```

Fields present in all entries: `ts`, `session`, `project`, `deployment`, `env`, `action`, `containers`, `unregistered_containers`, `notes`.

Fields only present in `maintenance` entries: `packages_upgraded`, `reboot_performed`, `reboot_duration_s`.

`notes` is a free-text string summarising anything notable (failures, user decisions, warnings). Empty string if nothing to note.

## Error Handling

- If `trimkit-sysops-log` is not on PATH (trimkit not installed), the agent skips logging and notes it in the output — this is non-fatal.
- If the JSON write fails for any reason, the agent proceeds normally; audit logging is best-effort and must not block maintenance operations.

## Testing

- A bats test verifying `trimkit-sysops-log` correctly appends entries and that the output is valid JSONL
- A bats test verifying atomicity: concurrent writes don't corrupt the file
- Agent and skill logic is tested indirectly via the existing sysops test patterns (if any exist)
