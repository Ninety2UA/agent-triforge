# grok-agents/ — Grok Build role briefs (prompt-prefix injection)

Grok Build's `--agent <name|path>` flag (binary `grok`, xAI) selects an agent
profile, so Triforge expresses a role the way it does for Cursor and OpenCode.
`invoke_grok` and the lease lane's builder dispatch read the brief here
(`grok-agents/<role>.md`), strip its YAML frontmatter, and put the body in
front of the task prompt.

## What enforces each role

The brief states the rules; grok's own permission engine and sandbox enforce
them. `_grok_argv` in `scripts/lib/grok.sh` composes every grok command line:

| Class | Roles | Allowed tools | Sandbox |
|---|---|---|---|
| edit | builder, tester, documenter | Read, Grep, Edit, Write, Bash | `workspace`: writes to the working directory, `~/.grok` and the temp directories |
| read | reviewer, analyst | Read, Grep (plus grok's built-in read-only shell commands) | `read-only`: writes to `~/.grok` and the temp directories |

Both classes run `--permission-mode dontAsk`, so grok denies anything not
allowed, MCP tools and web search included. Both carry the same deny list
(`git push` in its `-c`/`-C` forms, recursive `rm`, `sudo`, `doas`). A deny
rule matches a command's prefix or whole text, so it does not see a push inside
a script; the no-push git config the lease boundary sets refuses those (probe
row GRK-09).

## Isolation from Claude Code and Cursor configuration

By default grok reads Claude Code's and Cursor's skills, rules, CLAUDE.md, MCP
servers and hooks. Every run sets `GROK_CLAUDE_*_ENABLED=0` and
`GROK_CURSOR_*_ENABLED=0` (row GRK-04 checks the result with `grok inspect`).
Row GRK-06 records two things those switches do not reach. Claude Code
plugins under `~/.claude/plugins` stay loaded, and the session still offers
their skills and commands (`codex:review` among them). And grok copies the
`env` block of `~/.claude/settings.json` into its tool shell. A lease worker's tool
shell keeps only the names the lease boundary passes (a `GROK_CONFIG` overlay
with `include_only`), so that block stays out of it.

## Files

| File | Role | Injected as |
|---|---|---|
| `builder.md` | Optional-tier builder | prompt prefix (edit class) |
| `reviewer.md` | Read-only cross-reviewer | prompt prefix (read class); output merged to `ops/REVIEW_GROK.md` |

A role without a brief here (tester, analyst, documenter) runs the raw prompt
in its class; `invoke_grok` prints a warning naming the briefs that exist.
