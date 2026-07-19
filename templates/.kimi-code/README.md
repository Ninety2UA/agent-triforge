# .kimi-code/ — Triforge-shipped Kimi Code project config

Bootstrapped at session start (only when `kimi` is on PATH), copy-if-absent so
your edits survive:

| File | Purpose |
|---|---|
| `config.toml` | Disables telemetry (R25), pins the default model (`kimi-k3`), ships a minimal bash denylist. Validated by `kimi doctor`. |
| `AGENTS.md` | Project role sections (builder/reviewer) Kimi merges into its system prompt — the KIMI-03 fallback for a CLI with no native agents. |

There is deliberately **no `agents/` directory** here: Kimi Code has no
custom-agent CLI surface (see `kimi-agents/README.md`).

## KIMI-03 — no native agents

`kimi --help` (0.15.0) exposes no `--agent` / `--agent-file` flag (those are
legacy `kimi-cli` only). Roles are therefore expressed by **prompt-prefix
injection** from the plugin's `kimi-agents/` briefs, backed by the role sections
in `AGENTS.md`. `invoke_kimi` and the `lease_dispatch` `kimi)` case both inject;
neither passes a native agent flag (there isn't one).

## KIMI-05 — auth is API-key / login only, and `kimi doctor` cannot gate it

`kimi doctor` validates **configuration files only** — it PASSES even when signed
out (probe KIMI-02 PASS vs KIMI-05 AUTH-FAIL). So it can never confirm login. A
signed-out headless call fails fast, before any network round-trip, with:

```
error: failed to run prompt: No model configured. Run `kimi` and use /login to sign in ...
```

`invoke_kimi` classifies that output as a **deterministic auth failure** with the
exact fix (`kimi login`, or launch `kimi` and use `/login`) and does **not**
retry-storm. Sign in once with `kimi login` before Kimi build/review lanes can
make live calls.

## Telemetry (R25)

Disabled in two layers: `telemetry = false` in `config.toml` **and**
`KIMI_DISABLE_TELEMETRY=1` exported on every headless invocation by
`scripts/invoke-external.sh`. The env var is the authoritative kill switch the
CLI honors (probe KIMI-07); the config key guards interactive/direct use.

## Confinement — honest about what enforces it

- **Builder confinement is the lease worktree + the per-adapter environment
  allowlist (R35)**, not these config denies. The builder pool runs each build
  with `cwd` set to an isolated git worktree under `_adapter_env kimi` (which
  allowlists only `KIMI_*`), so a build cannot escape its worktree or read
  another provider's credentials regardless of these rules.
- **Reviewer read-only is prompt-level + worktree isolation**, NOT a CLI-enforced
  permission map. Kimi exposes no per-tool deny map to an injected brief and
  headless `-p` uses the `auto` policy (no `--sandbox`). This is honestly weaker
  than `opencode-agents/reviewer.md`'s `edit/bash: deny` map — the worktree is
  the backstop. See `kimi-agents/reviewer.md`.
- The `[[permission.rules]]` denies in `config.toml` (`rm -rf`, `git push`,
  `sudo`) are **documentation of intent + a guard for interactive/direct
  sessions**; do not rely on them under headless automation.

To customize: edit `config.toml` (model, telemetry, permission rules) or
`AGENTS.md` (role sections) — both are preserved once present.
