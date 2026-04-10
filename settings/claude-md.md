# TrimKit Hook Compatibility

TrimKit installs a `no-chaining` hook that blocks `&&`, `||`, and unsafe pipes
in Bash tool calls. Use the patterns below to avoid triggering it.

## Running commands in a specific directory

Never chain with `&&` — the hook blocks it. Use the built-in flag instead:

```bash
# npm — use --prefix:
npm --prefix /path/to/dir install
npm --prefix /path/to/dir run test
npm --prefix /path/to/dir run build

# git — use -C:
git -C /path/to/dir status
git -C /path/to/dir add file.ts
git -C /path/to/dir commit -m "message"
```

## Pipes

Pipes are allowed when the source is a safe read-only command or a safe npm
command, and every downstream segment is a safe read-only filter.

Safe pipe sources: `git` (read-only subcommands), `npm test`, `npm run <safe-script>`,
and standard read-only utils (`cat`, `grep`, `find`, `ls`, `sed`, `awk`, etc.).

Safe pipe sinks: `grep`, `head`, `tail`, `sed`, `awk`, `sort`, `uniq`, `wc`,
`cut`, `tr`, `jq`, and other standard read-only filters.

**Never use `xargs` in pipes** — it is not on the allowlist and will be blocked.
Use the Grep tool or pass file lists explicitly instead.

```bash
# Allowed:
npm test | tail -60
npm run lint | grep error
git log --oneline | grep feat
find . -name "*.ts" | grep src

# Blocked — use the Grep tool instead:
find . -name "*.ts" | xargs grep "pattern"
```

## Semicolons are allowed

Semicolons are not blocked and can be used to sequence commands:

```bash
WORKTREE=/path/to/wt MAIN=/path/to/main; for item in .env; do ln -sf "$MAIN/$item" "$WORKTREE/$item"; fi
```
