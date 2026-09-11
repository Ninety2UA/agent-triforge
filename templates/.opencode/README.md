# .opencode/ — Triforge-shipped OpenCode project config

`opencode.json` declares the **OpenRouter provider expectation** (the shipped
default model is `openrouter/z-ai/glm-5.3`, preloaded in models.dev — the
`provider.models` entry is an expectation marker, not a requirement) and a
**minimal bash denylist** (`rm -rf`, `git push`, `sudo`) as defense-in-depth for
interactive/direct `opencode` use in this project. Connect the provider once
with `opencode auth login` (or export `OPENROUTER_API_KEY`) before OpenCode
build/review lanes can make live calls.

## OC-06 caveat — deny under `--auto` is an open watch; the adapter stays off `--auto`

OpenCode's docs and source (`permission/index.ts`: an explicit deny raises
before any approval ask) say an explicit `deny` rule is **still enforced under
`--auto`** — auto mode only changes what would otherwise ask. The probe harness
disagrees: OC-06 on 1.18.30 (2026-09-11) still recorded the denied command
executing under `opencode run --auto`, and two lead re-probes (one with a
project rule, one with `OPENCODE_PERMISSION`) hung to timeout — inconclusive.
Until the rewritten OC-06 passes twice, the posture is unchanged (ADR D-033):

- **Triforge never passes `--auto`.** `invoke_opencode` composes
  `opencode run --format json -m <model> [--agent <name>] "<prompt>"` and
  nothing more — see `scripts/invoke-external.sh`.
- **`OPENCODE_PERMISSION` is injected on every dispatch** as defense-in-depth:
  a JSON value in the same shape as this file's `permission` block, carrying
  the same deny rules (`rm -rf`, `git push`, `sudo`), so the rules ride with
  the process even when a project has customized or removed `opencode.json`.
- **Reviewer read-only safety is the agent-definition permission map, not this
  file and not a CLI flag.** `opencode-agents/reviewer.md` ships
  `mode: subagent` with `permission: { edit: deny, bash: deny, webfetch: deny }`.
  That map — enforced without `--auto` — is what keeps the cross-reviewer from
  mutating the tree. The denies in `opencode.json` are documentation of intent
  plus a guard for interactive sessions; do not rely on them under automation.
- **Builder confinement is the lease worktree + the per-adapter environment
  allowlist (R35)**, not `opencode.json` denies. The builder pool runs each
  build with `cwd` set to an isolated git worktree under `_adapter_env opencode`
  (which allowlists only `OPENROUTER_API_KEY`), so a build cannot escape its
  worktree or read another provider's credentials regardless of these rules.

## Skills and commands

OpenCode discovers skills from `.agents/skills/` (Triforge's provisioned copy),
`.opencode/skill(s)/`, and `.claude/skills/`; `/<name>` in a prompt triggers the
native `skill` tool (probe OC-07). Commands live in `.opencode/command/*.md`
(the plural `commands/` also loads) and run headless with
`opencode run --command <name>`. Triforge's slash commands are lead-only, so
none is ported here.

To customize: edit `opencode.json` (models, providers, permissions) — it is
copied to `.opencode/opencode.json` at session start only if absent, so your
edits are preserved. Agent definitions live in `.opencode/agents/` (bootstrapped
from the plugin's `opencode-agents/`). Forward risk: OpenCode V2 (plural config
keys, ordered `permissions`) will change this file's shape when it ships — an
open watch.
