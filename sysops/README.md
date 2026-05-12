# Sysops

Configuration and documentation for the `sysops` agent and skill.

## Deployment registry

The sysops agent reads `~/.claude/sysops/deployments.json` at startup. See `deployments.example.json` for the format.

## Audit log

Every `/sysops status` or `/sysops update` invocation writes a structured entry to `~/.claude/sysops/audit.jsonl`. The file is append-only — entries are never modified or deleted. Log-viewing commands (`/sysops log`) do not generate log entries.

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

## trimkit-sysops-log-search

`bin/trimkit-sysops-log-search` reads the audit log, optionally filters by deployment, limits to the most recent N entries, and outputs the results. Used by the `/sysops log` slash command.

```bash
trimkit-sysops-log-search                                # last 10 entries (JSONL)
trimkit-sysops-log-search --deployment Pulse             # filter to Pulse
trimkit-sysops-log-search --last 25                      # last 25 entries
trimkit-sysops-log-search --human                        # human-readable output
trimkit-sysops-log-search --human --deployment Pulse --last 5
```

Environment overrides for testing:
- `TRIMKIT_SYSOPS_LOG_DIR` — override the log directory
- `TRIMKIT_SYSOPS_LOG_FILE` — override the log file path

## Learnings

The sysops agent writes a learning entry whenever it discovers something worth persisting for future sessions — server quirks, known-safe containers, procedure deviations, and similar deployment-specific context. Learnings are deduplicated by `(deployment, key)`: the latest entry for a given pair supersedes earlier ones. History is preserved in the file (append-only); only the latest entry per pair is surfaced at read time.

### Learnings location

```text
~/.claude/sysops/learnings.jsonl
```

### Schema

Each line is a JSON object:

| Field        | Type              | Description                                                        |
|--------------|-------------------|--------------------------------------------------------------------|
| `ts`         | string (ISO 8601) | UTC timestamp when the entry was written                           |
| `deployment` | string            | Deployment name (e.g. `Pulse`)                                     |
| `key`        | string            | Stable kebab-case identifier for this learning (dedup key)         |
| `type`       | string            | `quirk`, `known-safe`, `procedure`, or `warning`                   |
| `insight`    | string            | Human-readable description of what was learned                     |
| `confidence` | number (0.0–1.0)  | How confident the agent is; low-confidence entries are tentative   |
| `source`     | string            | How the learning was discovered (e.g. `observed`, `inferred`)      |

### Example entry

```json
{"ts":"2026-04-10T12:00:00Z","deployment":"Pulse","key":"caddy-restart-required-after-upgrade","type":"quirk","insight":"Caddy container requires manual restart after apt upgrade — it does not auto-recover.","confidence":0.9,"source":"observed"}
```

## Viewing learnings

Use the `/sysops learnings` slash command:

```bash
/sysops learnings                # all stored learnings (deduplicated)
/sysops learnings Pulse          # learnings for Pulse only
```

## trimkit-learnings-log

`bin/trimkit-learnings-log` appends a learning entry to the learnings store. It reads JSON from stdin, injects `ts`, and appends to the file. It is installed to `~/.trimkit/bin/` by `install.sh`.

Environment overrides for testing:
- `TRIMKIT_SYSOPS_LEARNINGS_DIR` — override the learnings directory
- `TRIMKIT_SYSOPS_LEARNINGS_FILE` — override the learnings file path

## trimkit-learnings-search

`bin/trimkit-learnings-search` reads the learnings store, deduplicates by `(deployment, key)` pair (latest entry per pair wins), optionally filters by deployment, and outputs surviving entries. Used by the `/sysops learnings` slash command.

```bash
trimkit-learnings-search                              # all learnings (JSONL)
trimkit-learnings-search --deployment Pulse            # Pulse learnings only
trimkit-learnings-search --human                       # human-readable output
trimkit-learnings-search --human --deployment Pulse    # filtered, human-readable
```

Environment overrides for testing:
- `TRIMKIT_SYSOPS_LEARNINGS_DIR` — override the learnings directory
- `TRIMKIT_SYSOPS_LEARNINGS_FILE` — override the learnings file path
