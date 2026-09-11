# .cursor/ — Triforge-shipped Cursor CLI project config

Bootstrapped at session start (only when `cursor-agent` is on PATH), copy-if-absent
so your edits survive:

| Path | Purpose |
|---|---|
| `.cursor/agents/builder.md`, `.cursor/agents/reviewer.md` | Cursor subagent defs (from the plugin's `cursor-agents/`) — delegation targets + documentation. The **headless** role path is prompt-prefix injection (see below), not selection of these defs. |
| `.cursor/README.md` | This file. |

There is deliberately **no permission/sandbox config** here: Cursor's headless
behavior is driven by CLI flags (`--trust`, `--force`, `--mode plan`, `--model`),
and its `--sandbox` does not confine (CUR-07 below), so there is no config-tier
confinement to ship.

## No headless `--agent` selector — injection

`cursor-agent --help` (re-checked on build 2026.09.10) has **no `--agent <name>`
flag**. The `.cursor/agents/` defs are delegation triggers for background
subagents, not a headless top-level selector. Triforge therefore expresses the
`builder`/`reviewer` roles by **prompt-prefix injection** from the plugin's
`cursor-agents/` briefs (`scripts/invoke-external.sh`'s `invoke_cursor` and the
`lease_dispatch` `cursor)` case both inject). See `cursor-agents/README.md`.

## Binary — `cursor-agent` first, `agent` only when its version matches

Cursor's install script now names `agent` the primary command and keeps
`cursor-agent` as a legacy symlink. Triforge resolves `cursor-agent` first and
falls back to `agent` **only when `agent --version` matches Cursor's
`YYYY.MM.DD-<hex>` format** — an unrelated `~/.grok/bin/agent` shadows Cursor's
symlink on some hosts, so the fallback is guarded (probe CUR-11).

## `--trust` is mandatory headless (CUR-04)

A non-TTY `cursor-agent -p` run blocks on the workspace-trust prompt unless
`--trust` is passed. Triforge passes `--trust` on every headless invocation. It
bypasses only the trust prompt — it is not an "allow everything" switch.

## Grok 4.6 pinned, effort in the suffix — NEVER the Auto router (CUR-03 / CUR-05 / CUR-10)

The shipped default is `cursor-grok-4.6-xhigh`, explicitly pinned with
`--model` on every call. Auto is never used: ledger attribution needs a
**named** model, and Auto resolves nondeterministically. Effort is the model-id
**suffix** (`cursor-grok-4.6-low|medium|high|xhigh`, each also as `-fast`),
so the roster `effort` field is live for Cursor: a bare `grok-4.6` in the
roster plus the roster effort composes the suffixed id at dispatch (low→`-low`,
medium→`-medium`, high→`-high`, xhigh/max→`-xhigh`); an explicit suffixed id
passes through untouched. The documented bracket form `grok-4.6[effort=xhigh]`
was **rejected** headless on build 2026.09.10 (`Cannot use this model`, probe
CUR-10) — an open watch; Triforge never emits it. Override with `CURSOR_MODEL`
(roster) — the leading alternative is `composer-2.5` (Composer 2.5).
`cursor-agent --list-models` feeds the `/setup` enrollment options and
validates the pinned default.

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

CUR-06 (re-probed 2026-09-11) FAILED: Cursor's headless hook events
(`beforeShellExecution` / `afterFileEdit` / `stop`) did **not** fire under
`cursor-agent -p`. Triforge therefore ships **no** `afterFileEdit` attribution
hook — builder attribution is recorded **lead-side from the lease ledger**,
which covers it regardless of hook support.

## Skills and commands (CUR-09)

Cursor reads skills from `.agents/skills/` (Triforge's provisioned copy),
`.cursor/skills/`, `.claude/skills/`, and `.codex/skills/`. `/name` in a `-p`
prompt runs a skill or a `.cursor/commands/*.md` command headless.

## Version pinning — no semver (CUR-01, R26)

Cursor publishes **no semver**; `cursor-agent --version` returns a date-based
build id (`YYYY.MM.DD-<hex>`) and the CLI auto-updates by default (drift risk).
Session start captures the running build id into
`.claude/roster-detected.local.md` (R26). Re-check it after an auto-update.
