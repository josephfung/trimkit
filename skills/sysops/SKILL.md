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
corrupt_count = 0
try:
    with open(log_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                corrupt_count += 1
                continue
            if deployment_filter and obj.get('deployment', '').lower() != deployment_filter.lower():
                continue
            entries.append(obj)
except PermissionError:
    print(f'Error: cannot read audit log at {log_file} (permission denied).')
    sys.exit(1)
except OSError as e:
    print(f'Error: cannot read audit log: {e}')
    sys.exit(1)

entries = entries[-limit:]

if not entries:
    msg = 'No entries found'
    if deployment_filter:
        msg += f' for deployment {deployment_filter!r}'
    print(msg + '.')
    if corrupt_count:
        print(f'Warning: {corrupt_count} corrupt line(s) skipped in audit log.')
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
        parts = [n + (' ✓' if s == 'healthy' else ' ✗') for n, s in containers.items()]
        print('  Containers: ' + '  '.join(parts))

    unregistered = e.get('unregistered_containers', [])
    unreg_str = '  '.join(u + ' ⚠' for u in unregistered) if unregistered else 'none'
    print(f'  Unregistered: {unreg_str}')

    notes = e.get('notes', '')
    if notes:
        print(f'  Notes: {notes}')
    print()

if corrupt_count:
    print(f'Warning: {corrupt_count} corrupt line(s) skipped in audit log.')
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
