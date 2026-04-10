# Changelog

All notable changes to TrimKit are documented here.

## [0.5.0] - Unreleased

### Hooks
- `no-chaining` — blocks `&&`/`||` chaining in Bash tool calls; allowlist covers safe read-only commands and npm scripts

### Agents & Skills
- `sysops` agent + `/sysops` skill — VPS health checks and updates across registered deployments
- `prod-debug` skill — pre-loads DB schema and container registry for production debugging sessions
- Sysops audit log — `/sysops log` command; appends session/project-stamped entries to a JSONL file

### Installer
- Plugin bootstrapping via `plugins/plugins.txt`
- `--upgrade` flag to replace existing real files with symlinks (backs up originals)
- Hooks auto-merged into `~/.claude/settings.json` on install
- CLAUDE.md injection — writes TrimKit hook compatibility tips into `~/.claude/CLAUDE.md`
- Misc quality-of-life: interactive PATH prompt, improved install summary output
