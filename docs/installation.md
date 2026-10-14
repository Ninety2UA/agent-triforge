[← Agent Triforge](../README.md#documentation)

# Install and update

What each CLI needs, the install steps for a Claude Code or a Codex lead, the portable skills for Devin and Pi, and how to check and update an install.

## Prerequisites

You need the core trio installed and logged in, Python 3, and on macOS GNU coreutils. The commands below are the READY probes [`at-setup`](../skills/at-setup/SKILL.md) runs for you; run them yourself to check a CLI before you install the plugin. Floors and tested versions are under [Compatibility](compatibility.md).

Core trio:

```bash
# Claude Code ≥ 2.1.277 — the first build that reads a root AGENTS.md (D-037);
# 2.1.267 first honored `effort:` frontmatter on pinned-default models and the
# `fable` alias resolves to Fable 5.1 from 2.1.257
claude --version

# Antigravity CLI ≥ 1.1.27 — https://antigravity.google/cli (run `agy` once interactively to log in)
agy --model "Gemini 3.8 Flash (High)" -p "Respond with only: READY"   # pin the model — agy's own default is a (Medium) variant

# Codex CLI ≥ 0.153.0 (gpt-6-astra's minimal client version) — https://github.com/openai/codex
codex exec "Respond with only: READY"

# Python 3 (used by hook handlers for JSON parsing)
python3 --version

# GNU timeout (on macOS: brew install coreutils, which provides gtimeout); without one
# the helper refuses to call an external CLI (rc 96) and session start warns
command -v timeout || command -v gtimeout
```

Optional tier. You can add these later through `at-setup` to use them as builders or reviewers; an absent one is skipped cleanly in every roster fallback chain:

```bash
# OpenCode ≥ 1.18.20 — needs the OpenRouter provider connected (OPENROUTER_API_KEY or `opencode auth login`)
opencode run --format json -m openrouter/z-ai/glm-5.3 "Respond with only: READY"

# Kimi Code ≥ 0.33.0 — OAuth device-code or API key (`kimi login`)
kimi -p "Respond with only: READY"

# Cursor (date-versioned) — pin the suffixed Grok id, never the Auto router (`cursor-agent login`);
# the binary is `cursor-agent` (legacy symlink) or `agent` (primary since 2026.09.10)
cursor-agent -p --trust --model cursor-grok-4.6-xhigh "Respond with only: READY"

# Devin CLI ≥ 3000.10.31 (`devin auth login`) — a reviewer and analyst; at-setup asks for your
# consent before enrolling it, and it builds only after a separate opt-in
devin --model swe-1-6-slow --respect-workspace-trust false -p "Respond with only: READY"

# Grok Build ≥ 1.0.34 (builder, reviewer or analyst) — `grok login` (`grok login --device-code` without a browser) or XAI_API_KEY
grok --model grok-4.7 --output-format json -p "Respond with only: READY"
```

## Installation

1. Check the [prerequisites](#prerequisites) above.

2. Install the plugin into the CLI that leads.

   Claude Code leads:

   ```bash
   # Register the repository as a single-plugin marketplace once (it ships .claude-plugin/marketplace.json)
   claude plugin marketplace add https://github.com/Ninety2UA/agent-triforge

   # User scope (available in all your projects)
   claude plugin install agent-triforge@agent-triforge

   # Or project scope (shared with team via .claude/settings.json)
   claude plugin install agent-triforge@agent-triforge --scope project
   ```

   Codex leads. Codex reads the same `.claude-plugin/` manifests:

   ```bash
   codex plugin marketplace add Ninety2UA/agent-triforge
   codex plugin add agent-triforge@agent-triforge
   ```

   Claude Code registers the hooks, the env vars in `settings.json` and the skills (the 10 portable skills and the 17 lead workflows) on its own. Codex registers the skills and the hooks, and runs the hooks only after you trust them in Codex; `at-setup` checks that and names the step. Nothing else needs configuring by hand.

3. Codex leads: trust the project. Since Codex 0.147.0, `codex exec` reads a project's own `.codex/` files (`config.toml`, `hooks.json`, `.rules`) only in a trusted project. Add this entry to `~/.codex/config.toml` yourself, with the project's absolute path:

   ```toml
   [projects."/absolute/path/to/your-project"]
   trust_level = "trusted"
   ```

   `at-setup` checks for the entry and prints it, with the path filled in, when it is missing. Triforge never writes your user-level config. Without the entry the root `AGENTS.md` still loads, but Codex skips the project's `.codex/` files; a project you mark `untrusted` loses the root `AGENTS.md` as well. [`templates/.codex/config.toml`](../templates/.codex/config.toml) is the project file that entry unlocks.

4. Start the lead (`claude` or `codex`) in your project. The first session bootstraps the project's `ops/` directory ([Automatic project bootstrapping](project-layout.md#automatic-project-bootstrapping)).

5. Run `/at-setup` (`$agent-triforge:at-setup` in a Codex prompt). After checking that the core trio is live (it names the fix for any CLI that isn't), it asks which CLI leads the project, Claude Code or Codex. For Codex it shows the project trust entry, the hook trust and the full-access launch line, which you type yourself. Role assignment comes next: keep the shipped defaults (recommended) or change any role's CLI, model and effort. You then enroll each optional CLI with a model you choose, or decline it. Setup lists the instruction files in the project and the directories above it. It offers to add the pointer block from [`templates/AGENTS.md`](../templates/AGENTS.md) to the project's root `AGENTS.md` (Triforge ships no `CLAUDE.md`), and when a `CLAUDE.md` would hide `AGENTS.md` from Claude Code, it also offers the `@AGENTS.md` import line. It changes a file only after you say yes. Before it writes the lead, it lists which providers receive your code. It is idempotent, so you can rerun it any time.

## Portable skills in Devin and Pi

Devin CLI and Pi can install the 10 portable skills straight from this repository. They get the skills only: no lead workflow (`at-*`), hook or agent. One of them, `wave-orchestration`, calls Triforge's lease helpers, which come only with the Triforge plugin. Without the plugin its wave rules still work as a manual method, but no lease, pinned review or integrity check runs. Installing the skills does not enroll the CLI, because `ops/roster.toml` assigns roles only to the CLIs in [the builder pool](team-work.md#the-builder-pool).

| Harness | Install | Manifest | Invoke |
|---|---|---|---|
| Devin CLI | `devin plugins install Ninety2UA/agent-triforge#skills` (from a clone: `devin plugins install --local ./agent-triforge/skills`) | [`skills/.devin-plugin/plugin.json`](../skills/.devin-plugin/plugin.json), plugin root `skills/` | `/agent-triforge:<name>` |
| Pi | `pi install git:github.com/Ninety2UA/agent-triforge` (`-l` writes the project's `.pi/settings.json` instead of `~/.pi/agent/settings.json`) | [`package.json`](../package.json), the `pi.skills` list | `/skill:<name>` |

Run `devin auth login` before any `devin plugins` command. Install the Devin plugin from `#skills`, not from the repository root: at the root, Devin falls back to `.claude-plugin/plugin.json` and also loads the 17 lead workflows, this repository's `AGENTS.md` as an always-on rule, and the Claude Code hooks.

## Verify installation

Start Claude Code in a project. The session-start banner lists the lead workflows, and `/at-status` prints the sprint report:

```bash
claude

# You should see:
# "Multi-agent framework ready."
# "Lead workflows (/at-<name> here, $agent-triforge:at-<name> in a Codex prompt): at-setup at-ship at-plan ..."

/at-status
```

Under a Codex lead the banner appears once you have trusted the plugin's hooks. `$agent-triforge:at-status` prints the same report either way, because every `at-` workflow runs the project bootstrap itself.

## Update

| Install route | How to update |
|---|---|
| Claude Code plugin | `claude plugin marketplace update agent-triforge`, then `claude plugin update agent-triforge`. Start a new Claude Code session to load the new version. |
| Codex plugin | `codex plugin marketplace upgrade agent-triforge`, then `codex plugin add agent-triforge@agent-triforge`, which installs the version the refreshed marketplace carries. When an update changes a hook, Codex asks you to review the hooks again (`/hooks`). |

```bash
# Claude Code leads
claude plugin marketplace update agent-triforge
claude plugin update agent-triforge

# Codex leads
codex plugin marketplace upgrade agent-triforge
codex plugin add agent-triforge@agent-triforge
```

Each project picks up the new version at its next session: session start refreshes the portable skills in `.agents/skills/` when the plugin version changes, and keeps any copy you edited ([Portable skills across the eight CLIs](skills.md#portable-skills-across-the-eight-clis)). Before you move to a new major version, read its notes in [Release history](../README.md#recent-changes); from 3.x, read [Upgrading from 3.x](upgrading.md).
