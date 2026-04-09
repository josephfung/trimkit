---
name: prod-debug
description: Production debugging skill. Pre-loads DB schema, container registry, and prod environment facts from .claude/prod-debug/ in the current project root. Use when the user invokes /prod-debug or /prod-debug bootstrap.
---

# prod-debug

## Invocation

Two modes:

- `/prod-debug` — load context and enter debugging mode
- `/prod-debug bootstrap` — (re)build schema.md and containers.md from source files

---

## On `/prod-debug`

### Step 1: Find project root

Determine the project root — use the current working directory, or if inside a git repo, use `git rev-parse --show-toplevel`.

### Step 2: Check for data directory

Check whether `.claude/prod-debug/config.json` exists at the project root.

- If **missing**: tell the user that prod-debug is not set up for this project yet, and suggest running `/prod-debug bootstrap` after creating `.claude/prod-debug/config.json`.
- If **present**: continue to Step 3.

### Step 3: Load context files

Read all three data files using the Read tool:

1. `{project_root}/.claude/prod-debug/schema.md`
2. `{project_root}/.claude/prod-debug/containers.md`
3. `{project_root}/.claude/prod-debug/prod-env.md`

If any file is missing, note it and proceed with what's available.

### Step 4: Announce

Report a brief summary:
```
Prod-debug loaded.
  Schema: {N} tables
  Containers: {M} services
  Env: {hostname or domain from prod-env.md}
Ready — ask me to query the DB, inspect logs, or diagnose an issue.
```

### Step 5: Enter debugging mode

Use the loaded context to assist with:

**DB queries** — Build SQL using the pre-loaded schema. No `\d` or `INFORMATION_SCHEMA` queries needed — the schema is already in context. For queries on remote prod, prefix with the SSH + docker exec command from prod-env.md.

**Container operations** — Use container names and commands from containers.md. Common patterns:
- View logs: `docker logs {service} --tail 100 -f`
- Shell in: `docker exec -it {service} sh` (or bash)
- Restart: `docker restart {service}`

**SSH to prod** — Use the SSH alias/command from prod-env.md. Remote docker commands are typically run via `ssh {alias} docker ...`

**Stale schema** — If the user mentions a table or column that isn't in schema.md, flag it and suggest running `/prod-debug bootstrap` to rebuild from migrations.

---

## On `/prod-debug bootstrap`

This rebuilds the data files from source. Run when setting up a new project or when schema.md/containers.md have drifted.

### Step 1: Read config

Read `{project_root}/.claude/prod-debug/config.json`. It has this shape:

```json
{
  "migrations": {
    "glob": "src/db/migrations/*.sql"
  },
  "containers": {
    "composeFiles": [
      "docker-compose.yml",
      "../path/to/compose.production.yaml"
    ]
  }
}
```

### Step 2: Build schema.md

1. Find all migration files matching `migrations.glob` (resolved from project root)
2. Read them **in filename order** (they are numbered, so lexicographic = chronological)
3. Parse each migration to extract DDL: `CREATE TABLE`, `ALTER TABLE ADD COLUMN`, `ALTER TABLE DROP COLUMN`, `CREATE INDEX`, `CREATE EXTENSION`
4. Build a cumulative schema — start from empty, apply each migration in sequence
5. Write the result to `{project_root}/.claude/prod-debug/schema.md`

**Output format for schema.md:**

```markdown
# DB Schema
<!-- Last bootstrapped: {ISO date} from {N} migrations -->

## Extensions
- pgvector
- pgAudit

## TABLE: {table_name}
| Column | Type | Constraints | Notes |
|--------|------|-------------|-------|
| id | UUID | PRIMARY KEY | |
| ... | | | |

**Indexes:**
- {index_name} ON ({columns}) [{UNIQUE}]

---
```

One section per table, ordered by first appearance in migrations.

### Step 3: Build containers.md

1. Read each file in `containers.composeFiles` (resolved from project root)
2. Parse service definitions: service name, image or build context, ports, key environment variables, healthcheck
3. Write to `{project_root}/.claude/prod-debug/containers.md`

**Output format for containers.md:**

```markdown
# Container Registry
<!-- Last bootstrapped: {ISO date} -->

## {service_name}

- **Image/Build:** {image or Dockerfile path}
- **Ports:** {host:container mappings}
- **Key env vars:** {comma-separated list of var names, not values}
- **Healthcheck:** {healthcheck command or "none"}

**Commands:**
- Logs: `docker logs {service_name} --tail 100 -f`
- Shell: `docker exec -it {service_name} sh`
- Restart: `docker restart {service_name}`

---
```

### Step 4: Check prod-env.md

If `prod-env.md` does not exist, print a reminder:

```
Bootstrap complete. One more step:
  Create .claude/prod-debug/prod-env.md with your production environment facts.
  This file is written by hand — it captures things not in any config file:
  SSH alias, domain, VPS specs, key env var names, etc.

  Template:
  # Prod Environment
  - SSH: ssh <alias> (port <port>)
  - Domain: https://<domain>
  - Health check: curl https://<domain>/api/health
  - VPS: <provider>, <region>, <instance type>
  - DB connect: docker exec -it <postgres-container> psql -U $DB_USER -d <dbname>
  - Key env vars: <list var names>
```

---

## Hook integration

When the `prod-debug.sh` PostToolUse hook fires after a migration or compose file is written, it prints an update instruction to stdout. You will see it as context in the same response. Act on it immediately:

- **Migration update instruction** → read the new migration file and apply the delta to `schema.md` (add new table or columns, note dropped columns)
- **Compose update instruction** → re-read the relevant compose file and update the affected service entry in `containers.md`

Do these updates inline without waiting to be asked — the point is that schema.md stays in sync automatically.
