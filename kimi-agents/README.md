# kimi-agents/ — Kimi Code role briefs (injection only)

Kimi Code (binary: `kimi`) has **no custom-agent CLI surface** — probe KIMI-03
(kimi 0.15.0, 2026-07-18): the `--agent` / `--agent-file` flags are **legacy
`kimi-cli` only** and do not exist in `kimi-code`'s `--help`. There is therefore
no native/project agent tier to load from (unlike OpenCode's `--agent <name>`
against `.opencode/agents/`).

## The KIMI-03 fallback — two layers

Triforge expresses the `builder` and `reviewer` roles for Kimi **without a native
agent flag**, exactly like `invoke_antigravity`'s injection mode:

1. **Prompt-prefix injection (primary).** `scripts/invoke-external.sh`'s
   `invoke_kimi` reads the role brief here (`kimi-agents/<role>.md`), strips its
   YAML frontmatter, and prefixes the brief body onto the task prompt. The
   `lease_dispatch` `kimi)` builder case injects the same brief via the
   dispatch prompt. This is the operative mechanism.
2. **Project `AGENTS.md` role sections (fallback).** `templates/.kimi-code/AGENTS.md`
   (bootstrapped to `.kimi-code/AGENTS.md` at session start when `kimi` is
   installed) carries builder/reviewer role sections. Kimi merges every
   applicable `AGENTS.md` into its system prompt (deeper directories win), so the
   roles survive even a raw call that skips injection.

These files are **briefs, not native agent definitions.** Frontmatter (`name`,
`description`) is metadata only — it is stripped before injection; the body is
the entire payload.

## Read-only reviewer — weaker than OpenCode's map

`reviewer.md` instructs read-only behavior, but Kimi exposes **no per-tool
permission map** to an injected brief and headless `kimi -p` runs under Kimi's
`auto` policy (no `--sandbox`). So Kimi's reviewer read-only is
**prompt-level + lease-worktree isolation** (R35 / `_adapter_env` KIMI_*
allowlist) — honestly weaker than `opencode-agents/reviewer.md`'s
`permission: { edit: deny, bash: deny }` map. The worktree isolation is the real
backstop; the prompt instruction is the first line.

## Files

| File | Role | Injected as |
|---|---|---|
| `builder.md` | Optional-tier builder | prompt prefix (KIMI_MODEL default `kimi-k3`) |
| `reviewer.md` | Read-only cross-reviewer | prompt prefix; output merged to `ops/REVIEW_KIMI.md` |

Config, telemetry, and the auth (KIMI-05) story live in
`templates/.kimi-code/README.md`.
