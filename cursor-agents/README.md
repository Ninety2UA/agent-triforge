# cursor-agents/ — Cursor CLI role briefs (injection primary, .cursor/agents/ backstop)

Cursor CLI (binary: `cursor-agent`) has **no headless custom-agent selector** —
re-probed 2026-07-18 (cursor-agent `2026.07.16-*`): `cursor-agent --help` exposes
no `--agent <name>` flag. The `.cursor/agents/` defs Cursor documents are
**delegation triggers** for background subagents, not a way to select a top-level
agent for a one-shot headless (`-p`) run. So, like Kimi (KIMI-03), there is no
native flag to route a role — the role is expressed by **prompt-prefix
injection**.

## The role mechanism — two layers

1. **Prompt-prefix injection (primary).** `scripts/invoke-external.sh`'s
   `invoke_cursor` reads the role brief here (`cursor-agents/<role>.md`), strips
   its YAML frontmatter, and prefixes the brief body onto the task prompt. The
   `lease_dispatch` `cursor)` builder case injects the same brief via the dispatch
   prompt. This is the operative mechanism.
2. **`.cursor/agents/` project defs + root `AGENTS.md`/`CLAUDE.md` (backstop).**
   `templates/.cursor/` and these briefs are bootstrapped to `.cursor/agents/` at
   session start (when `cursor-agent` is installed). They are valid Cursor agent
   defs (Cursor reads `.cursor/agents/`, `.cursor/rules/`, `AGENTS.md`, and
   `CLAUDE.md`), so they document intent and serve as delegation targets even
   though they are not the headless selection path.

These files are **briefs first, native defs second.** Frontmatter
(`name`, `description`, `model`, `readonly`) is real Cursor agent-def format, but
it is stripped before injection; the body is the entire injected payload.

## Read-only reviewer — enforced by `--mode plan`, not `readonly:`

`reviewer.md` sets `readonly: true`, but that frontmatter only binds if Cursor
loads the file as a `.cursor/agents/` delegation target. The **headless** reviewer
path enforces read-only with **`--mode plan`** (CUR-08: a write did not land under
`--mode plan`) — `invoke_cursor` adds `--mode plan` for the reviewer role and
never adds `--force`. `--sandbox` is deliberately **not** used for confinement
(CUR-07: `--sandbox enabled` did not confine — an absolute-path write escaped).
So Cursor's reviewer read-only is `--mode plan` (real) + the `readonly:` def
(belt-and-suspenders) + lease-worktree isolation (backstop).

## Files

| File | Role | Injected as |
|---|---|---|
| `builder.md` | Optional-tier builder | prompt prefix (CURSOR_MODEL default `grok-4.5`; invocation adds `--force`) |
| `reviewer.md` | Read-only cross-reviewer | prompt prefix; invocation adds `--mode plan`; output merged to `ops/REVIEW_CURSOR.md` |

Model pinning (`grok-4.5`, never Auto), `--trust`, the CUR-06 headless-hooks gap,
and version pinning (no semver) are documented in `templates/.cursor/README.md`.
