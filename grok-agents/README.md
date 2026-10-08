# grok-agents/ — Grok Build role briefs (prompt-prefix injection)

Grok Build's `--agent <name|path>` flag (binary `grok`, xAI) selects an agent
profile, so Triforge expresses a role the way it does for Cursor and OpenCode.
`invoke_grok` and the lease lane's dispatch read the brief here
(`grok-agents/<role>.md`), strip its YAML frontmatter, and put the body in
front of the task prompt. Grok takes three roles: builder, reviewer and
analyst. A roster that names it as a tester or documenter fails to load. A
lease takes its class from its role: a builder lease runs in the edit class
with `builder.md`, and a reviewer or analyst lease in the read class with
`reviewer.md` (SELF-25). `invoke_grok` runs the read class only.

## What enforces each role

The brief states the rules; grok's own permission engine and sandbox enforce
them. `_grok_argv` in `scripts/lib/grok.sh` composes every grok command line:

| Class | Roles | Allowed tools | Sandbox |
|---|---|---|---|
| edit | builder, in a lease only | Read, Grep, Edit, Write, Bash | `triforge-edit`, written into the worktree's `.grok/sandbox.toml`: `workspace` (writes to the working directory, `~/.grok` and the temp directories) plus a deny on the `~/.grok` paths a later grok run loads (see below) |
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
`enabled = false` covers each MCP server grok finds, the user's own
`~/.grok/config.toml` servers included, and each one in the project's
`.mcp.json`. A server the project's own file declares gets no entry, because
it already replaces a user server of the same name. The lists come from
`grok inspect --json`.
If it fails, times out or leaves out a list, grok does not run. A lease uses
its lease worktree. Outside a lease, `invoke_grok` runs a reviewer or analyst
in a scratch checkout of HEAD and removes it afterwards, also on an interrupt.
Before the checkout goes, anything grok or its `grok inspect` left running
(a hook, an LSP server) is stopped, at the timeout too. If something can't be
stopped, the checkout stays and the error names it.
That checkout is a new repository that borrows the lead's objects, and git
reads no config but its own while making it. So no filter or hook named in
the lead's `.git/config` runs, and the lead's `.git` gets no worktree entry.
Before each attempt, the retry included, `invoke_grok` checks the roster's
consent and role rules (rc 5 for a member the roster has declined since) and
runs the integrity check that `lease_create` runs (rc 44).
The file is never merged. A project's own file keeps its lines and gets the
tables after them, but only if Python's `tomllib` parses the result with every
plugin disabled and every server shadowed. Otherwise grok does not run at all:
lease_create makes no lease, and `invoke_grok` returns 69. Row GRK-06 opens a
session in both kinds of worktree with no prompt and checks that no plugin
command is offered and no MCP server starts. Every grok run's tool shell keeps
only the names the lease boundary passes (an `env -i` start and a
`GROK_CONFIG` overlay with `include_only`), so the settings `env` block stays
out of it.

## What the project supplies

Every grok run turns folder trust off (`GROK_FOLDER_TRUST=0`) so that it
loads the skills provisioned into a fresh worktree. That also loads what the
project supplies, and on grok 1.0.34 three of these ran code as soon as a
session opened, before any prompt: a hook in `.grok/hooks/`, a server in
`.grok/lsp.json`, and an MCP server declared in the project's own
`.grok/config.toml`. A reviewer or analyst therefore does not start in a
worktree that holds any of these, or a plugin under `.grok/plugins/` or
`.claude/plugins/`, or a hook, LSP server or plugin that `grok inspect` reports
from inside the worktree: `lease_create` refuses the lease, `lease_dispatch`
checks again, and `invoke_grok` returns 69. The error names the file. The rest stays inert in the read class (each checked with a marker
file):

- Claude Code and Cursor project hooks, and Cursor's MCP servers, are off with
  their `GROK_CLAUDE_*` and `GROK_CURSOR_*` switches.
- A `.mcp.json` server is shadowed like any other.
- Grok reads no hooks from a project `config.toml`.
- Agent definitions only run as subagents, and grok runs with
  `--no-subagents`.
- Skills are prompt text, and the read class has no shell to run their
  scripts.
- A `.grok/sandbox.toml` cannot redefine the built-in `read-only` profile.

A builder keeps every project surface, since it already has a full shell in
its lease worktree.

## What the user's grok configuration supplies

Grok also starts the user's own hooks, LSP servers and MCP servers in every
session, before any permission applies: hooks in `~/.grok/hooks/*.json` or a
config layer's `[hooks]` table, LSP servers in `~/.grok/lsp.json`, and the
MCP servers of the user's config. Grok has no switch that turns a user hook or
LSP server off for one project.

- User-level grok hooks and settings run in a reviewer or analyst session, as
  they do when the user runs grok. Triforge treats only the project under
  review as untrusted input. One NOTE line on stderr names each of them with
  its file: a hook or LSP server that `grok inspect` reports, and an
  auth-provider command, `ui.notifications.hooks`, a `[hooks]` table or a
  requirements-layer MCP server in a user config layer. The layers are
  `config.toml`, `managed_config.toml` and `requirements.toml` in
  `$GROK_HOME`, and the last two in `/etc/grok`. The line goes to
  `lease_create`'s stderr, to the builder log at each dispatch, and to
  `invoke_grok`'s stderr.
- The provisioned config still shadows every user MCP server, as it does the
  others. A requirements-layer server outranks the shadow and starts, and the
  NOTE names it. MCP tool calls are denied in every class.
- A hook or LSP server that comes from a user plugin stays off, since the
  provisioned config disables the plugin.
- A user config layer that doesn't parse is refused, because nothing shows
  what it would start. The error names the file.
- Project-level hooks, LSP servers, plugins and MCP servers are still refused
  in the read class (see above).
- A builder keeps the user's surfaces, but its sandbox profile stops it from
  planting new ones for a later run. `triforge-edit` is grok's `workspace`
  profile plus a kernel deny, for reads and writes, on `~/.grok/lsp.json`,
  `AGENTS.md` and `disabled-hooks`; on the `plugins`, `installed-plugins`,
  `marketplace-cache`, `skills`, `agents`, `personas`, `commands`,
  `workflows`, `rules` and `memory` directories; on the grok binary (`bin/`,
  `downloads/`); on `vendor/`, which holds the ripgrep behind the Grep tool;
  and on `bundled/`. `workspace` already keeps `config.toml`,
  `managed_config.toml`, `requirements.toml`, `sandbox.toml`,
  `trusted_folders.toml`, `hooks/` and `hooks-paths` unwritable. `auth.json`,
  `sessions/` and `logs/` stay writable for the login refresh and the
  transcripts. `lease_dispatch` writes the profile again before every run, and
  row GRK-12 checks it from a scratch `GROK_HOME` without a model call.

A machine with a terminal app's agent-status hook in `~/.grok/hooks/`, such
as Orca's `orca-status.json`, runs that hook in grok reviews too, and the
NOTE names it. The check runs when a reviewer or analyst lease is made, again
before each of its dispatches, and before each `invoke_grok` attempt.
at-setup runs the same check before it offers grok either role and shows the
user the NOTE. A worker on another CLI with no OS sandbox can still write to
`~/.grok`. A hook it plants there runs in the next grok review and shows up in
the NOTE; a new MCP server there is shadowed. Nothing names a plant that
`grok inspect` and the config layers don't show, such as a `~/.grok/AGENTS.md`
or a replaced `~/.grok/bin/grok`. AGENTS.md names that residual for any worker
with a shell and no OS sandbox.

## Files

| File | Role | Injected as |
|---|---|---|
| `builder.md` | Optional-tier builder | prompt prefix (edit class, a builder lease) |
| `reviewer.md` | Read-only cross-reviewer | prompt prefix (read class); also an analyst lease; output merged to `ops/REVIEW_GROK.md` |

Outside a lease, `dispatch_role` gives a reviewer or an analyst whose agent
name has no brief here `reviewer.md` instead (at-review names its core lanes
`logic_reviewer` and `architecture-reviewer`), so the answer ends with the
`Status:` line at-review promotes on. A direct `invoke_grok` call with such a
name runs the raw prompt in the read class and prints a warning naming the
briefs that exist.
