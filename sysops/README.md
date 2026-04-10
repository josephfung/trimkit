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
