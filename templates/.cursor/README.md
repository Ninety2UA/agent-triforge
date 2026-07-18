# .cursor/ — Triforge-shipped Cursor CLI project config

Bootstrapped at session start (only when `cursor-agent` is on PATH), copy-if-absent
so your edits survive:

| Path | Purpose |
|---|---|
| `.cursor/agents/builder.md`, `.cursor/agents/reviewer.md` | Cursor agent defs (from the plugin's `cursor-agents/`) — delegation targets + documentation. The **headless** role path is prompt-prefix injection (see below), not selection of these defs. |
| `.cursor/README.md` | This file. |

There is deliberately **no permission/sandbox config** here: Cursor's headless
behavior is driven by CLI flags (`--trust`, `--force`, `--mode plan`, `--model`),
and its `--sandbox` does not confine (CUR-07 below), so there is no config-tier
confinement to ship.

## No headless `--agent` selector — injection, like Kimi

`cursor-agent --help` (re-probed 2026-07-18, `2026.07.16-*`) has **no
`--agent <name>` flag**. The `.cursor/agents/` defs are delegation triggers for
background subagents, not a headless top-level selector. Triforge therefore
expresses the `builder`/`reviewer` roles by **prompt-prefix injection** from the
plugin's `cursor-agents/` briefs (`scripts/invoke-external.sh`'s `invoke_cursor`
and the `lease_dispatch` `cursor)` case both inject). See `cursor-agents/README.md`.

## `--trust` is mandatory headless (CUR-04)

A non-TTY `cursor-agent -p` run blocks on the workspace-trust prompt unless
`--trust` is passed. Triforge passes `--trust` on every headless invocation. It
bypasses only the trust prompt — it is not an "allow everything" switch.

## Grok 4.5 pinned — NEVER the Auto router (CUR-03 / CUR-05)

The shipped default is `grok-4.5`, explicitly pinned with `--model` on every call.
Auto is never used: ledger attribution needs a **named** model, and Auto resolves
nondeterministically. Override with `CURSOR_MODEL` (roster) — the leading
alternative is `composer-2.5` (Composer 2.5). `cursor-agent --list-models` feeds
the `/setup` enrollment options and validates the pinned default.

## Reviewer read-only is `--mode plan` — NOT `--sandbox` (CUR-07 / CUR-08)

- **CUR-08 PASS:** under `--mode plan`, a write did **not** land — a real
  read-only mode. The reviewer role adds `--mode plan` and never `--force`.
- **CUR-07 FAIL:** `--sandbox enabled` did **not** confine — an absolute-path
  write escaped the workspace. So `--sandbox` is not a confinement mechanism.
  **Builder confinement is the lease worktree + the `_adapter_env cursor`
  environment allowlist (R35)**, which allowlists only `CURSOR_API_KEY`; a build
  cannot escape its worktree or read another provider's credentials regardless of
  sandbox flags.

## Headless hooks do NOT fire — attribution is lead-side (CUR-06)

CUR-06 (re-probed) FAILED: Cursor's headless hook events
(`beforeShellExecution` / `afterFileEdit` / `stop`) did **not** fire under
`cursor-agent -p`. Triforge therefore ships **no** `afterFileEdit` attribution
hook — builder attribution is recorded **lead-side from the lease ledger** (U9),
which covers it regardless of hook support. Same class of gap as Codex `exec`
hooks.

## Version pinning — no semver (CUR-01, R26)

Cursor publishes **no semver**; `cursor-agent --version` returns a date-based
build id (e.g. `2026.07.16-899851b`) and the CLI auto-updates by default (drift
risk). Session start captures `cursor-agent --version` into
`.claude/roster-detected.local.md` so the running build id is recorded (R26).
Re-check it after an auto-update.
