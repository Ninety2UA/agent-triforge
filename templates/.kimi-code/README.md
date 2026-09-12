# .kimi-code/ — Triforge-shipped Kimi Code project files

Bootstrapped at session start (only when `kimi` is on PATH), copy-if-absent so
your edits survive:

| File | Purpose | Read by the CLI? |
|---|---|---|
| `config.toml` | Documents the intended settings: telemetry off, default model `kimi-code/k3`, a bash denylist. | **No** — documentation only (see below). |
| `AGENTS.md` | Shared confinement contract + role reminders, rendered into Kimi's system prompt through `${agents_md}`. | Yes. |

There is deliberately **no `agents/` directory** here: the builder and reviewer
definitions stay in the plugin (`kimi-agents/`) and are loaded by absolute path
with `--agent-file` (KTD13 — `.agents/agents/` is shared with agy and is never
populated).

## `config.toml` is documentation only

Kimi Code 0.42.0 reads ONLY the user-tier `~/.kimi-code/config.toml`
(`$KIMI_CODE_HOME/config.toml`); the documented project-local file is
`.kimi-code/local.toml`, which carries only `[workspace]` (`additional_dir`). A
project `.kimi-code/config.toml` is never loaded (watch cycle 2026-09-11, ADR
D-024), so its `telemetry`, `default_model`, and `[[permission.rules]]` are
inert until you copy them into the user file. What actually binds under
Triforge's headless lanes:

- **Telemetry (R25):** `KIMI_DISABLE_TELEMETRY=1`, exported on every headless
  invocation by `scripts/invoke-external.sh` (`invoke_kimi` and the
  `lease_dispatch` `kimi)` case). The CLI honors it in `-p` since 0.41.0 (probe
  KIMI-07). This is the authoritative switch; the config key is a courtesy for
  interactive use once copied to `~/.kimi-code/config.toml`.
- **Model:** `-m "${KIMI_MODEL:-kimi-code/k3}"` on every invocation.
- **Confinement:** the agent definition's `tools` allowlist + the lease
  worktree + the `KIMI_*` env allowlist — never the denylist.

## Roles load natively — `--agent-file` (KIMI-03 PASS)

`kimi --help` (0.42.0) exposes `--agent <name>` and `--agent-file <path>`, and
both work in `-p` mode (probe KIMI-03 flipped FAIL → PASS on 2026-09-11). The
lead passes `--agent-file <plugin-root>/kimi-agents/<role>.md` on every
attempt; each definition opens with `${base_prompt}` (extending Kimi's prompt
rather than replacing it), declares `subagents: []` (no delegation), and ends
with `${skills}` and `${agents_md}`. The July prompt-prefix injection and the
"KIMI-03 fallback" framing are retired. See `kimi-agents/README.md`.

## Reviewer read-only = `tools` allowlist + worktree

`kimi-agents/reviewer.md` lists only Read, Glob, Grep, and Skill, so the shell,
file-writing, editing, URL-fetch, and delegation tools are not loaded for the
reviewer and a mutating call cannot be issued; the lease worktree is the
backstop. Nothing else enforces it: headless `-p` runs in "Never Ask" mode with
no dangerous-command guard (0.41.0), the shell tool is no longer confined to the
workspace (0.40.0), and the project config is not read. Live confirmation that a
write is refused (probe KIMI-08) is PENDING-AUTH — see the exact command in
`kimi-agents/README.md`.

## KIMI-05 — auth is login only, and `kimi doctor` cannot gate it

`kimi doctor` validates **configuration files only** — it PASSES even when
signed out (probe KIMI-02 PASS vs KIMI-05 AUTH-FAIL). A signed-out headless call
fails fast, before any network round-trip, with:

```
error: failed to run prompt: No model configured. Run `kimi` and use /login to sign in ...
```

`invoke_kimi` classifies that output as a **deterministic auth failure** with the
exact fix (`kimi login`, or launch `kimi` and use `/login`) and does **not**
retry-storm. Sign in once with `kimi login` before Kimi build/review lanes can
make live calls; login provisions the managed aliases (`kimi-code/k3`,
`kimi-code/kimi-for-coding`); the older open-platform id is not provisioned and
fails on OAuth hosts. KIMI-05/06/08/09 stay PENDING-AUTH until then (R18: the
sprint never runs `kimi login` for you).

## Skills — native discovery, `--skills-dir` retired

Triforge provisions its skills into `.agents/skills/`, a native project tier
(with `.kimi-code/skills/`); the user tier (`~/.kimi-code/skills/`,
`~/.agents/skills/`) is discovered too. `--skills-dir` is no longer passed —
on 0.42.0 it REPLACES auto-discovery instead of adding to it. Invoke a skill as
`/skill:<name>`.

To customize: edit `AGENTS.md` (shared contract, role reminders) — preserved
once present. Model, telemetry, and permission rules belong in
`~/.kimi-code/config.toml`; `config.toml` here is the reference copy.
