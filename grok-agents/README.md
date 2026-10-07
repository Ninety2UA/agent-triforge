# grok-agents/ — Grok Build role briefs (prompt-prefix injection)

Grok Build's `--agent <name|path>` flag (binary `grok`, xAI) selects an agent
profile, so Triforge expresses a role the way it does for Cursor and OpenCode.
`invoke_grok` and the lease lane's dispatch read the brief here
(`grok-agents/<role>.md`), strip its YAML frontmatter, and put the body in
front of the task prompt. A lease takes its class from its role: a builder,
tester or documenter lease runs in the edit class with `builder.md`, and a
reviewer or analyst lease in the read class with `reviewer.md` (SELF-25).

## What enforces each role

The brief states the rules; grok's own permission engine and sandbox enforce
them. `_grok_argv` in `scripts/lib/grok.sh` composes every grok command line:

| Class | Roles | Allowed tools | Sandbox |
|---|---|---|---|
| edit | builder, tester, documenter | Read, Grep, Edit, Write, Bash | `workspace`: writes to the working directory, `~/.grok` and the temp directories |
| read | reviewer, analyst | Read, Grep; Edit, Write and Bash denied, so no shell at all | `read-only`: writes to `~/.grok` and the temp directories |

Both classes run `--permission-mode dontAsk`, which denies what no rule
allows. Grok also imports allow rules from Claude Code's settings files
(`~/.claude/settings*.json` and the project's `.claude/settings*.json`), and
a deny rule beats any allow. So the read class denies Edit, Write and Bash
outright, and both classes deny every MCP tool. Both carry the same deny list
too (`git push` in its `-c`/`-C` forms, recursive `rm`, `sudo`, `doas`). A deny
rule matches a command's prefix or whole text, so it does not see a push inside
a script; the no-push git config the lease boundary sets refuses those (probe
row GRK-09).

## Isolation from Claude Code and Cursor configuration

By default grok reads Claude Code's and Cursor's skills, rules, CLAUDE.md, MCP
servers and hooks. Every run sets `GROK_CLAUDE_*_ENABLED=0` and
`GROK_CURSOR_*_ENABLED=0` (row GRK-04 checks the result with `grok inspect`).
Those switches do not reach three things:

- Claude Code plugins under `~/.claude/plugins`. They stay loaded, and the
  session offers their skills and commands (`codex:review` among them).
- The `~/.claude.json` MCP servers. Run with Claude Code's own environment, a
  session started them even though `grok inspect` reported them as off.
- The `env` block of `~/.claude/settings.json`, which grok copies into its
  tool shell.

Only config-file keys reach the first two, so a grok worker runs from a
worktree with its own `.grok/config.toml`. Its `[plugins] disabled` list names
every plugin grok finds, and an `[mcp_servers.<name>]` entry with
`enabled = false` covers each MCP server outside grok's own config. A lease
uses its lease worktree. Outside a lease, `invoke_grok` runs a reviewer or
analyst in a scratch worktree of HEAD and removes it afterwards. The file is
never merged. A project's own file keeps its lines and gets the tables after
them, but only if Python's `tomllib` parses the result with every plugin
disabled and every server shadowed. Otherwise grok does not run at all:
lease_create makes no lease, and `invoke_grok` returns 69. Row GRK-06 opens a session in both
kinds of worktree with no prompt and checks that no plugin command is offered
and no MCP server starts. Every grok run's tool shell keeps only the names the
lease boundary passes (an `env -i` start and a `GROK_CONFIG` overlay with
`include_only`), so the settings `env` block stays out of it.

A tester or documenter outside a lease edits the lead's checkout, so it runs
there. Triforge writes nothing into that checkout, so the plugins load for it:
their skills and commands are offered and their hooks run, their MCP tools are
denied, and `--no-subagents` drops their agents.

## Files

| File | Role | Injected as |
|---|---|---|
| `builder.md` | Optional-tier builder | prompt prefix (edit class); also a tester or documenter lease |
| `reviewer.md` | Read-only cross-reviewer | prompt prefix (read class); also an analyst lease; output merged to `ops/REVIEW_GROK.md` |

Outside a lease, a role without a brief here (tester, analyst, documenter)
runs the raw prompt in its class; `invoke_grok` prints a warning naming the
briefs that exist.
