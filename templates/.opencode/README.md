# .opencode/ — Triforge-shipped OpenCode project config

`opencode.json` declares the **OpenRouter provider expectation** (the shipped
default model is `openrouter/z-ai/glm-5.2`) and a **minimal bash denylist**
(`rm -rf`, `git push`, `sudo`) as defense-in-depth for interactive/direct
`opencode` use in this project. Connect the provider once with
`opencode auth login` (or export `OPENROUTER_API_KEY`) before OpenCode build/
review lanes can make live calls.

## OC-06 caveat — denies do NOT survive `--auto`

A probe (OC-06, 2026-07-17, opencode 1.18.3) proved that a `deny` rule in
`opencode.json` is **bypassed** when `opencode run` is passed `--auto` (the
denied command executed anyway). Consequences, baked into the adapter:

- **Triforge never passes `--auto` in the review lane.** `invoke_opencode`
  composes `opencode run --format json -m <model> [--agent <name>] "<prompt>"`
  and nothing more — see `scripts/invoke-external.sh`.
- **Reviewer read-only safety is the agent-definition permission map, not this
  file and not a CLI flag.** `opencode-agents/reviewer.md` ships
  `mode: subagent` with `permission: { edit: deny, bash: deny, webfetch: deny }`.
  That map — enforced without `--auto` — is what keeps the cross-reviewer from
  mutating the tree. The denies in `opencode.json` are documentation of intent
  plus a guard for non-`--auto` interactive sessions; do not rely on them under
  automation.
- **Builder confinement is the lease worktree + the per-adapter environment
  allowlist (R35)**, not `opencode.json` denies. The builder pool runs each
  build with `cwd` set to an isolated git worktree under `_adapter_env opencode`
  (which allowlists only `OPENROUTER_API_KEY`), so a build cannot escape its
  worktree or read another provider's credentials regardless of these rules.

To customize: edit `opencode.json` (models, providers, permissions) — it is
copied to `.opencode/opencode.json` at session start only if absent, so your
edits are preserved. Agent definitions live in `.opencode/agents/` (bootstrapped
from the plugin's `opencode-agents/`).
