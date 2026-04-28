# TrimKit Hook Compatibility

## Always pull before branching

Before creating a worktree, branch, or starting any feature work, pull the
latest from the remote main branch first:

```bash
git pull origin main
```

Branching from stale code leads to unnecessary rebases and merge conflicts.
Do this every time — no exceptions.

## No-chaining hook

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

The full allowlist for pipe sources and sinks:
`awk`, `basename`, `cat`, `cut`, `date`, `dirname`, `echo`, `egrep`, `fgrep`,
`find`, `grep`, `head`, `jq`, `ls`, `printf`, `sed`, `sort`, `tail`, `tr`,
`uniq`, `wc` — plus `git` (read-only subcommands: `branch`, `diff`, `log`,
`ls-files`, `rev-parse`, `show`, `status`).

Additionally allowed as a pipe **source only**: `npm test`, `npm t`, `npm ls`,
`npm list`, `npm audit`, `npm outdated`, `npm view`, `npm info`, and
`npm run <script>` where the script name is `test`, `lint`, `check`,
`typecheck`, `type-check`, `build`, or `compile` (colon-namespaced variants
like `test:unit` also work). The `--prefix <path>` flag is supported.

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
