[← Agent Triforge](../README.md#documentation)

# Upgrading from 3.x

- Each 3.x slash command is now a lead workflow with an `at-` prefix: `/setup` became `/at-setup`, `/ship` became `/at-ship`, and so on for the whole set (`$agent-triforge:at-setup`, `$agent-triforge:at-ship` in a Codex prompt). The plugin no longer ships a `commands/` directory. The [command map](#command-map) below pairs each one with its new name, and the [Lead workflows reference](workflows.md#lead-workflows-reference) describes every workflow.
- Triforge 4 ships no `CLAUDE.md`. The project's instruction file is its root `AGENTS.md`, which Claude Code reads from 2.1.277, and only while no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` sits in the project or above it. If your project kept a `CLAUDE.md` from the 3.x template, add an import line to it (`@AGENTS.md` in a root `CLAUDE.md`, `@../AGENTS.md` in `.claude/CLAUDE.md`), or replace its Triforge content with the pointer block from [`templates/AGENTS.md`](../templates/AGENTS.md). Session start prints a warning naming the exact line on every session until you do; it never edits the file.
- The `test-driven-development` and `systematic-debugging` skills are gone. Their rules now sit inline in `at-test`, `at-quick`, `at-debug` and the Codex `test_writer` and `debugger` agents.
- If your project's `.codex/hooks.json` is still the unchanged 3.x copy, the first 4.0 session replaces it with the empty 4.0 template and prints a notice naming the file. The 3.x hook appended a line to `ops/CHANGELOG.md` from every Codex session, lease workers included; attribution now comes from the lease ledger. Session start leaves a copy you edited alone ([decision record](../ops/decisions/2026-10-04-codex-hook-trust-bypass-retired.md)).
- The 19 agents are now personas: prompt files in [`personas/`](../personas/) with no frontmatter. Their tools, model tier and turn budget live in [`personas/manifest.toml`](../personas/manifest.toml). The plugin ships no `agents/` directory, so Claude Code's agent list no longer shows them. The workflows run them through `dispatch_persona` under either lead. PR comment resolution now runs as a lease and lands as one reviewed commit on the PR branch.
- On resume, `lease_heartbeat_check` now collects the builders that finished while no lead was watching and adopts the ones still running; builders run detached in 4.0 and outlive the lead's turn. In 3.x it printed `run: lease_collect <task>` and left the collect to you.
- Triforge now sets up the project in the repository's top directory, the nearest one above that holds `.git`, wherever the session starts. A project that 3.x bootstrapped in a subdirectory of a larger repository keeps its `<subdir>/ops/`, and the first 4.0 session creates a new skeleton at the top. The lease ledger and the `[lead]` table already live in the top-level `ops/`, so move your other `ops/` files there and delete the subdirectory copy. Until you move it, session start and `at-setup` warn about the subdirectory's `ops/roster.toml` each time they run from that subdirectory or below it, and on the run that creates the top-level skeleton.

## Command map

A 3.x command also ran in its namespaced form, `/agent-triforge:<name>`. From a shell, put the Codex form in single quotes so the shell leaves the `$` alone: `codex exec '$agent-triforge:at-ship <goal>'`.

| 3.x command | 4.0 under Claude Code | 4.0 in a Codex prompt |
|---|---|---|
| `/analyze` | `/at-analyze` | `$agent-triforge:at-analyze` |
| `/build` | `/at-build` | `$agent-triforge:at-build` |
| `/compound` | `/at-compound` | `$agent-triforge:at-compound` |
| `/coordinate` | `/at-coordinate` | `$agent-triforge:at-coordinate` |
| `/debug` | `/at-debug` | `$agent-triforge:at-debug` |
| `/deep-research` | `/at-deep-research` | `$agent-triforge:at-deep-research` |
| `/pause` | `/at-pause` | `$agent-triforge:at-pause` |
| `/plan` | `/at-plan` | `$agent-triforge:at-plan` |
| `/quick` | `/at-quick` | `$agent-triforge:at-quick` |
| `/resolve-pr` | `/at-resolve-pr` | `$agent-triforge:at-resolve-pr` |
| `/resume` | `/at-resume` | `$agent-triforge:at-resume` |
| `/review` | `/at-review` | `$agent-triforge:at-review` |
| `/setup` | `/at-setup` | `$agent-triforge:at-setup` |
| `/ship` | `/at-ship` | `$agent-triforge:at-ship` |
| `/status` | `/at-status` | `$agent-triforge:at-status` |
| `/test` | `/at-test` | `$agent-triforge:at-test` |
| `/wrap` | `/at-wrap` | `$agent-triforge:at-wrap` |

## Rolling back to 3.3.3

Settle every open lease while 4.0 is still installed. A 4.0 builder runs detached, and 3.3.3's heartbeat check can't match the start time 4.0 records for it, so 3.3.3 would take a builder that is still running for dead and remove its worktree. Run `lease_wait` until it prints no `still building:` line (`lease_stop <task>` stops a builder you don't want to wait for), then merge each lease or reclaim it with `lease_reclaim`. 3.3.3 can't merge a lease whose pinned reviewer is Devin or Grok Build, and it doesn't read the approvals recorded with `lease_approve`.

Then reinstall 3.3.3 from a checkout of its tag:

```bash
git clone --branch v3.3.3 https://github.com/Ninety2UA/agent-triforge.git agent-triforge-3.3.3
claude plugin uninstall agent-triforge@agent-triforge
claude plugin marketplace remove agent-triforge
claude plugin marketplace add ./agent-triforge-3.3.3
claude plugin install agent-triforge@agent-triforge
```

If you installed at project scope, pass the same `--scope` to `uninstall` and `install`. 3.3.3 has no Codex lead, so also remove a Codex install with `codex plugin remove agent-triforge@agent-triforge`. To return to the current release later, remove the local marketplace and add the GitHub URL again.

Last, check what 4.0 left in each project:

- `ops/roster.toml`: 3.3.3 ignores the `[lead]` table and always leads from Claude Code. It rejects `[members.devin]` and `[members.grok]` as unknown members, and that error stops every role from resolving, so delete both tables and take `devin` and `grok` out of every role and fallback chain.
- The instruction file: 3.3.3's session start looks only for `CLAUDE.md` and `.claude/CLAUDE.md`. When it finds neither, it prints a `cp` line for its `templates/CLAUDE.md`, and once that file exists Claude Code stops reading `AGENTS.md`. The pointer block in your `AGENTS.md` names the 4.0 `at-` workflows, which 3.3.3 doesn't have. Restore the project's 3.x `CLAUDE.md` from git history or run the printed copy line, and move anything you still need from `AGENTS.md` into it.
- `personas/`: nothing to undo. Personas live in the plugin, not in your project, and 3.3.3 brings back its 19 subagents in `agents/`.
- `.codex/hooks.json`: if 4.0 replaced it with the empty template, 3.3.3 keeps the empty file, because it copies its template only where none exists. Delete the file and the next session restores the 3.x hook, which logs every Codex session to `ops/CHANGELOG.md`.
- `.agents/skills/`: nothing to do. 3.3.3's session start sees the version change, adds `test-driven-development` and `systematic-debugging` back, and replaces only the copies that still match their recorded digest.
- `ops/` itself: 3.3.3 sets up the project in the directory where the session starts, so start Claude Code in the repository's top directory, where 4.0 keeps `ops/`.
