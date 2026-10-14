[← Agent Triforge](../README.md#documentation)

# Project layout and customization

The files the plugin ships, the `ops/` directory it sets up in your project, and the settings you can change.

## Project structure

The plugin provides personas, skills and hooks. Your project gets an `ops/` directory for state:

```
agent-triforge/                     (plugin — installed automatically)
├── .claude-plugin/plugin.json        Plugin manifest
├── package.json                      Pi package manifest: the portable skills only
├── personas/                         19 persona prompts plus manifest.toml (tools, model tier, turns)
├── skills/                           27 skills in one tree
│   ├── .devin-plugin/plugin.json       Devin plugin manifest (plugin root skills/): the portable skills only
│   ├── <name>/SKILL.md                 10 portable skills, copied to .agents/skills/ and lease worktrees
│   │   └── references/                 where a skill is split (wave-orchestration, verification-before-completion)
│   └── at-<name>/                      17 lead workflows (/at-<name> in Claude Code, $agent-triforge:at-<name> in a Codex prompt); never copied
│       ├── SKILL.md                      the router: goal, done condition, safe failure, invocation
│       ├── references/                   the detail the router points to
│       ├── scripts/locate-triforge.sh    finds the plugin root from either lead
│       └── agents/openai.yaml            Codex skill metadata
├── hooks/
│   ├── hooks.json                    Hook registration
│   └── handlers/                     4 lifecycle hook scripts, plus monitors.py (the monitors' state and classifier)
├── settings.json                     Default env vars
├── AGENTS.md                         The plugin's own instructions: checks, conventions, confinement, human-only actions
├── templates/                        Project bootstrapping templates (AGENTS.md pointer block, ops/ skeleton, per-CLI files)
├── scripts/coordinate.sh            Outer loop for context recovery
└── scripts/validate-*.sh            Release gates: skill structure; version lockstep + ladder one-definition + stale-pin sweep

your-project/                       (your repo — bootstrapped on first session)
├── AGENTS.md                         Your instruction file, with Triforge's pointer block (templates/AGENTS.md)
├── ops/                              Shared coordination files
│   ├── AGENTS.md                       Master operating protocol for all agents
│   ├── GOALS.md                        High-level product goals
│   ├── MEMORY.md                       Decisions, patterns, gotchas
│   ├── CHANGELOG.md                    Audit trail with agent attribution
│   ├── STATE.md                        Session continuity checkpoint
│   ├── solutions/                      Documented solved problems
│   ├── decisions/                      Architecture decision records
│   └── archive/                        Archived review + test files
└── src/                              Your source code
```

## Automatic project bootstrapping

Triforge sets up a project through one helper, `triforge_bootstrap` (`scripts/lib/bootstrap.sh`). The `session-start.sh` hook runs it at the start of every session, and `at-setup`, `at-build` and `at-review` run it too, so a project led from Codex is set up before you trust the plugin's hooks. Each run only fills in what is missing. It works in the repository's top directory, the nearest one above that holds `.git`, so a run from a subdirectory sets up the repository. It refuses to set up your home directory or any directory that contains it, and the roster writers and the lease helpers refuse such a project too. It:

- Creates `ops/solutions/`, `ops/decisions/` and `ops/archive/`, copies the skeleton `MEMORY.md`, `CHANGELOG.md`, `AGENTS.md` and `GOALS.md` from the plugin templates into `ops/`, and adds `ops/roster.toml`
- Copies the 10 portable skills into `.agents/skills/` and each CLI's project files (`.codex/` always; `.opencode/`, `.kimi-code/` and `.cursor/` for the CLIs you have installed)
- Writes `.agents/triforge-plugin-root.local`, a per-user file naming the plugin's install path, which the `at-` skills read when the lead does not export one. If no ignore rule covers the file, Triforge adds one to `.agents/.gitignore` so git never tracks it. If git tracks `.agents/.gitignore`, Triforge leaves it alone and prints the line to add instead

The hook also keeps its session state in `.claude/` (it writes nothing through a `.claude` that is a symlink) and prints a `cp` command for Triforge's pointer block when the project has no root `AGENTS.md`.

Your project's own instruction file is its root `AGENTS.md`. Add the marked pointer block from [`templates/AGENTS.md`](../templates/AGENTS.md) to it yourself, or let `at-setup` add it after you say yes; session start never writes into an existing `AGENTS.md`. The plugin ships no `CLAUDE.md`, because a `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in or above the project stops Claude Code from reading `AGENTS.md`.

## Shared file protocol

All agents coordinate through markdown files in [`ops/`](../ops/), the source of truth:

| File | Purpose | Owner |
|---|---|---|
| `TASKS.md` (runtime) | Work queue with `[ ]`/`[x]` status tracking | The lead generates, all agents read |
| [`AGENTS.md`](../templates/ops/AGENTS.md) | Master operating protocol read by all agents | Manual |
| [`GOALS.md`](../templates/ops/GOALS.md) | High-level product goals for sprint planning | Manual |
| [`MEMORY.md`](../ops/MEMORY.md) | Architectural decisions, patterns, interface proposals | All agents append |
| [`CHANGELOG.md`](../ops/CHANGELOG.md) | Audit trail with `[agent-name]` attribution | All agents append |
| [`STATE.md`](../ops/STATE.md) | Session continuity: current phase, progress, next actions | The lead writes on pause/wrap |
| [`solutions/`](../ops/solutions/) | Documented solved problems for institutional knowledge | The lead writes via [`at-compound`](../skills/at-compound/SKILL.md) |
| [`decisions/`](../ops/decisions/) | Architecture decision records (ADRs) | The lead writes via [`at-compound`](../skills/at-compound/SKILL.md) |

## Customization

| To change | Do this |
|---|---|
| A role's CLI, model or effort | Run `at-setup roles` to keep, customize or restore the shipped defaults with validated writes, or edit `[roles.<role>]` in `ops/roster.toml`. [Model and effort](models.md) lists the pins and the opt-ins. |
| Which optional CLIs take part | Run `at-setup` (or `at-setup opencode`, `kimi`, `cursor`, `devin`, `grok`) to enroll or decline each. `enabled = false` under `[members.<cli>]` removes a member from every role and fallback chain, and setting it back to `true` restores it. The core trio can't be disabled. |
| Devin's role | Devin joins only with your consent on record, and reviews and analyzes by default. It builds only after a separate opt-in: `opt_in = ["builder"]` in `[members.devin]`. |
| Which CLI leads | Run `at-setup lead`. The switch refuses while leases are open; `--force` hands them to the new lead without spending a requeue. |
| Whether promotion waits for you | Set `require_user_approval = true` under `[promotion]` in `ops/roster.toml`, and the lead pauses at the end of each wave for your approval before promoting to `main`. A diff that touches a protected path needs that approval regardless. |
| A portable skill | Copy it to a directory with a different name under `.agents/skills/`. Triforge refreshes only its own unchanged copies, so an edited copy under a shipped name is kept with a notice but no longer updated. You can delete any skill directory you don't want. |
| Your project's instructions | Edit the project's root `AGENTS.md`. Keep Triforge's marked pointer block from [`templates/AGENTS.md`](../templates/AGENTS.md) in it. |
| Agent-team builds | Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"` in Claude Code's `settings.json` ([What are Agent Teams?](../README.md#faq)). |
