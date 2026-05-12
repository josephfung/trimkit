# TrimKit Hook Compatibility

## Always pull before branching

Before creating a worktree, branch, or starting any feature work, pull the
latest from the remote main branch first:

```bash
git pull --ff-only origin main
```

Branching from stale code leads to unnecessary rebases and merge conflicts.
Do this every time — no exceptions.

## No-chaining hook

TrimKit installs a `no-chaining` hook that blocks `&&`, `||`, and unsafe pipes
in Bash tool calls. Use the patterns below to avoid triggering it.

## Use built-in tools instead of shell utilities

**Never use `cat`, `head`, `tail`, `sed`, or `awk` to read file contents.**
Use the `Read` tool instead — it supports `offset` (starting line) and `limit`
(number of lines) for reading specific ranges:

```
# Wrong — triggers permission prompts and bypasses built-in tools:
sed -n '335,340p' /path/to/file.ts
cat /path/to/file.ts | head -20
head -50 /path/to/file.ts

# Right — use the Read tool:
Read(file_path="/path/to/file.ts", offset=335, limit=6)
```

Similarly, use `Grep` instead of `grep`/`rg`, `Glob` instead of `find`/`ls`,
and `Edit` instead of `sed`/`awk` for modifications. The built-in tools are
faster, don't require permission approvals, and give better user visibility.

## Running commands in a specific directory

**Never use `cd /path && command`** — the `&&` will be blocked by the hook, and
`cd` does not persist between Bash tool calls anyway. Use the built-in flag for
each tool:

```bash
# Wrong — blocked by the hook:
cd /path/to/dir && npm list nylas | head -5
cd /path/to/dir && git status
cd /path/to/dir && pnpm test

# Right — use --prefix or -C:
npm --prefix /path/to/dir list nylas | head -5
pnpm --prefix /path/to/dir test
git -C /path/to/dir status
```

All three package managers support `--prefix`:

```bash
# npm:
npm --prefix /path/to/dir install
npm --prefix /path/to/dir run test

# pnpm:
pnpm --prefix /path/to/dir install
pnpm --prefix /path/to/dir run test

# git:
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

Additionally allowed as a pipe **source only**:

- `npm test`, `npm t`, `npm ls`, `npm list`, `npm audit`, `npm outdated`,
  `npm view`, `npm info`, and `npm run <script>` where the script name is
  `test`, `lint`, `check`, `typecheck`, `type-check`, `build`, or `compile`
  (colon-namespaced variants like `test:unit` also work).
- `npx <binary>` where the binary is `vitest`, `jest`, `mocha`, `tsc`,
  `eslint`, `prettier`, `biome`, or `oxlint`.

Both `npm --prefix <path>` and `npx --prefix <path>` are supported.

**Never use `xargs` in pipes** — it is not on the allowlist and will be blocked.
Use the Grep tool or pass file lists explicitly instead.

```bash
# Allowed:
npm test | tail -60
npm run lint | grep error
npx vitest run tests/unit/foo.test.ts | tail -30
npx --prefix /path/to/project jest --verbose | grep PASS
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

## Creating or editing issues

When creating or editing issues in any tracker (GitHub Issues, GitLab Issues,
Jira, Linear, Azure DevOps, etc.):

1. **Apply pre-existing labels** — query the tracker for its current labels,
   tags, or categories and apply every applicable one. Never leave an issue
   uncategorized and never invent new labels without asking.
2. **Include acceptance criteria** — every issue must list specific, testable
   conditions that define when the work is done.
