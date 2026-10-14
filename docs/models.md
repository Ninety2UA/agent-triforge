[← Agent Triforge](../README.md#documentation)

# Model and effort

Each role's CLI, model and effort come from `ops/roster.toml`. A field you leave unset inherits the shipped default (the role table in `scripts/lib/roster.sh` and the CLI registry in `scripts/lib/registry.sh`), so deleting the file is safe. `at-setup`'s role step edits it for you (`at-setup roles` jumps straight there), and a hand edit is checked when the roster loads.

<p align="center">
  <img src="images/roster.png" alt="ops/roster.toml: the lead, the five roles with their shipped CLI, model, effort and fallbacks, the required core trio and the optional members." width="90%">
</p>

| Role | CLI | Model | Effort | Fallbacks |
|---|---|---|---|---|
| builder | Claude | Claude Code's own default (the roster's `model` is empty) | `max` | Codex → Antigravity |
| reviewer | Codex | `gpt-6-astra` | `xhigh` | Antigravity → Claude |
| tester | Codex | `gpt-6-astra` | `xhigh` | Claude |
| analyst | Antigravity | `Gemini 3.8 Flash (High)` | `high` | Claude |
| documenter | Antigravity | `Gemini 3.8 Flash (High)` | `high` | Claude |

How each CLI takes its model and effort:

- Antigravity always gets an explicit `--model`, because its own default is a (Medium) variant. The shipped pin is the newest Gemini at its highest thinking level, Pro or Flash (D-022). The suffix is agy's effort control, so a role's `effort` maps into it: `low` to (Low), `medium` to (Medium), `high`, `xhigh` and `max` to (High).
- To run the Pro line, set a role's `model` to `"Gemini 3.1 Pro (High)"` (or `(Low)`; 3.1 Pro has no Medium tier). It stays the documented one-line opt-in.
- The July 2026 plan's never-Flash rule (AE2) is superseded by D-022; if you work from that plan, read the September ADR (`ops/decisions/2026-09-11-cli-deprecation-watch.md`).
- Codex runs `gpt-6-astra` at `xhigh` (D-021). A role can pick another Codex model, such as `gpt-6.1-sol`, which answered on Codex 0.160.0 and was refused on 0.155.1.
- Cursor runs a suffixed Grok id, `cursor-grok-4.6-xhigh`, never the Auto router. Its effort is the id's suffix (`low`, `medium`, `high`, `xhigh`).
- The claude builder lane runs Claude Code's own default model at `max` effort. Claude personas and sub-agents follow the ladder below.
- The optional members' pins are OpenCode `openrouter/z-ai/glm-5.3`, Kimi `kimi-code/k3`, Devin `swe-1-6-slow` and Grok Build `grok-4.7` (its effort rides in `--effort`).
- A role that sets only `effort` keeps its default CLI and model. Roster model overrides reach each CLI through its registry `model_env`.

The lead takes its model and effort from the `[lead]` table (`cli`, `model`, `effort`). Left out, a Codex lead runs `gpt-6-astra` at `xhigh`, and a Claude Code lead runs your session's model and effort setting. `coordinate.sh` and the launch line `at-setup` prints add them as flags.

Claude personas and sub-agents step down one ladder for narrow runtime tasks: Fable 5.1 at `max` for the lead and the never-downgrade tier (the latest Opus at `max` where Fable isn't available), then Opus 5.5 at `xhigh` (Claude Code ≥ 2.1.280), Opus 5.5 at `high`, and Sonnet 5.5 at `high`. `security-sentinel`, `plan-checker` and `findings-synthesizer` are never downgraded. Each persona's starting tier is in [`personas/manifest.toml`](../personas/manifest.toml). The ladder has one definition, `TRIFORGE_MODEL_LADDER` in [`scripts/lib/registry.sh`](../scripts/lib/registry.sh); `triforge_ladder` prints it, and `validate-versions.sh` fails when another file restates it.

## Assignment heuristic

Roles come from `ops/roster.toml` (`resolve_role <role>`). The defaults below are the shipped posture and restrict no one: any member can be the builder, and every build merges only after cross-review.

| Question | Role (default; roster-assignable) |
|---|---|
| Produces code? | builder role: default Claude, assignable to any member; built under a lease and cross-reviewed before merge |
| Evaluates existing code? | reviewer role ([Codex](https://github.com/openai/codex) + [Antigravity](https://antigravity.google/cli)) + [review personas](personas.md#review-specialists-6) in parallel |
| Runs/executes something? | tester role (default [Codex CLI](https://github.com/openai/codex)) |
| Produces documentation? | documenter role (default [Antigravity CLI](https://antigravity.google/cli)) |
| Touches shared interfaces? | builder implements under a lease → pinned non-author reviewer cross-reviews → tester validates |
| Ambiguous? | the lead takes it as builder, flags for parallel review |
