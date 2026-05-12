# Changelog

All notable changes to TrimKit are documented here.

## [0.5.1] - Unreleased

### Sysops learnings
- Per-deployment learnings persistence — the sysops agent writes a structured entry to `~/.claude/sysops/learnings.jsonl` whenever it discovers a server quirk, known-safe container, procedure deviation, or other deployment-specific context worth remembering
- `trimkit-learnings-log` — bin script that appends a learning entry to the store; reads JSON from stdin, injects `ts`, validates required fields and type enum, and writes atomically
- `trimkit-learnings-search` — bin script that reads the store, deduplicates by `(deployment, key)` pair (latest entry per pair wins), filters by deployment, and outputs JSONL or formatted text (`--human`)
- `trimkit-sysops-log-search` — bin script extracted from SKILL.md that reads `audit.jsonl`, filters by deployment and entry count (`--last N`), and outputs JSONL or formatted text (`--human`)
- `/sysops learnings` sub-command — view stored learnings for all deployments or a specific one
- SKILL.md refactored from ~170 lines of inline Python to a ~30-line routing layer that delegates to the bin scripts

### CLAUDE.md guidance
- Pull before branching — injected instruction to run `git pull --ff-only` before creating worktrees or branches
- Issue tracker hygiene — injected instructions to apply pre-existing labels and include acceptance criteria when creating or editing issues

## [0.5.0]

### Hooks
- `no-chaining` — blocks `&&`/`||` chaining in Bash tool calls; allowlist covers safe read-only commands and npm scripts

### Agents & Skills
- `sysops` agent + `/sysops` skill — VPS health checks and updates across registered deployments
- `prod-debug` skill — pre-loads DB schema and container registry for production debugging sessions
- Sysops audit log — `/sysops log` command; appends session/project-stamped entries to a JSONL file

### Update check
- Periodic update notifications — TTL-cached (24h) check against `main` branch on GitHub; silent when up-to-date or on fetch failure; auto-snoozes per-version for 7 days after notifying
- `trimkit-update-check` — bin script called as a `UserPromptSubmit` hook on each Claude Code session
- `trimkit-update-snooze` — bin script that writes snooze state; also callable manually

### Installer
- Plugin bootstrapping via `plugins/plugins.txt`
- `--upgrade` flag to replace existing real files with symlinks (backs up originals)
- Hooks auto-merged into `~/.claude/settings.json` on install
- CLAUDE.md injection — writes TrimKit hook compatibility tips into `~/.claude/CLAUDE.md`
- Misc quality-of-life: interactive PATH prompt, improved install summary output
- Writes `~/.trimkit/install-dir` so `trimkit-update-check` can locate the local `package.json`
