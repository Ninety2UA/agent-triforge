---
title: "Lead choice: Claude Code or Codex orchestrates, every other CLI works"
type: requirements
status: ready-for-planning
date: 2026-09-27
evidence:
  - ops/research/2026-09-27-cli-updates.md
  - ops/decisions/2026-09-27-cli-deprecation-watch.md
  - ops/research/2026-09-27-repo-mining.md
  - ops/research/2026-09-27-factsheet-grok-devin-pi-hermes.md
  - ops/research/2026-09-probe-record.md
---

# Lead choice: requirements

## Goal

Today Claude Code is always Triforge's lead. After this work, a user who installs Triforge picks the lead, Claude Code or Codex, and assigns every other CLI to worker roles. Claude (Fable or Opus) can then be a worker under a Codex lead. The same skills, instructions and safety rules apply whichever CLI leads.

The evidence files above are on the `docs/watch-cycle-2026-09-27` branch (PR #10) until it merges. The small fixes that couldn't wait are in `docs/plans/2026-09-27-hotfix-v3-3-2-plan.md` and are out of scope here.

## Decisions already made (by the user)

- **KD1.** The lead is `claude` or `codex`, chosen in `/setup` and changeable later. Antigravity is worker-only: headless hooks are unreliable (AGY-08 flip-flops across releases) and permissions are enforced only at the user tier.
- **KD2.** Triforge ships **only `AGENTS.md`**: no `CLAUDE.md` in this repo, in the plugin, or in the user-project template. The Claude Code floor rises to **2.1.277**, the first build that reads AGENTS.md (D-037, D-038).
- **KD3.** Every skill follows the Agent Skills spec (`agentskills/agentskills`) and compound-engineering's conventions. Commands and agents become skills (R10–R14).
- **KD4.** Context audit first: instruction files get cut down before any lead-choice work, following Anthropic's "new rules of context engineering" post and Addy Osmani's "Audit your agent files".
- **KD5.** Rules that must always hold are enforced by scripts, hooks or permissions, never by prose alone.
- **KD6.** Add **Grok Build** and **Devin CLI** as optional workers, offered in `/setup` like OpenCode, Kimi and Cursor, and changeable later.
- **KD7.** The Codex pin stays `gpt-6-astra` at `xhigh`. OpenAI's lower starting-effort guidance is recorded only (D-044).
- **KD8.** `plugin-dev` (Anthropic's plugin toolkit, installed locally) is the reference for hooks, manifests and validation. agentskills plus compound-engineering govern how skills are written.

## Requirements

### Lead and roster

- **R1.** `ops/roster.toml` gains a `[lead]` table (`cli = "claude" | "codex"`, plus model and effort). `roster_write_role` and load validation reject any other lead value. Code branches on what the lead can do, never on "is it Codex" (G18).
- **R2.** The CLI that isn't the lead is an ordinary worker, eligible for every role, under the same lease, cross-review and merge rules as the others.
- **R3.** A new **`claude -p` worker lane**: a leased headless Claude builder or reviewer with its own `_adapter_env` allowlist, a typed `Status:` report, and a model from the roster (`fable` / `opus`). The Fable spawn-time override and the downgrade ladder apply only when Claude leads.
  - Known gap: SELF-06f FAILs, because `claude -p` from a lease worktree under `env -i` didn't find the plugin's skills.
  - Unknown: whether `claude -p` loads AGENTS.md. Both need probe rows.
- **R4.** A **Codex lead** runs with `-s danger-full-access -c approval_policy="never" -c background_terminal_max_timeout=900000` (D-047). Under `workspace-write`, Codex can't write `.git` or `$HOME`, so `codex exec` workers never start.
  - Confinement under a Codex lead is therefore Triforge's scripts plus lease worktrees only. The docs and `/setup` must state this plainly.
  - Subagents inherit the parent's sandbox, and approvals fail in non-interactive runs.
- **R5.** Protected-path review under a Codex lead: the user, or Claude as a required reviewer. A protected change is never reviewed by Codex alone. The plan confirms the rule.
- **R6.** The lease ledger, merge, promotion and attribution stay lead-owned and work identically under either lead.

### `/setup`

- **R7.** `/setup` detects which CLI it's running in and offers the lead choice first (default: the current CLI), then role assignment, then optional-member enrollment.
  - Every choice can be changed later by re-running `/setup`, or with `/setup roles`, or a new `/setup lead`.
  - It works as `/setup` in Claude Code and `$setup` in Codex.
- **R8.** Choosing Codex as lead checks the prerequisites and shows the `danger-full-access` consequence (R4). The prerequisites are: the user-tier project trust entry exists, and the AGENTS.md size is under Codex's cap.
- **R9.** If a user project already has its own `CLAUDE.md`, Claude Code won't read Triforge's `AGENTS.md`. `/setup` detects this and offers to add an `@AGENTS.md` line, asking first, since the file is the user's.

### Instruction files

- **R10.** One root `AGENTS.md` holds the lead-neutral protocol: roster, leases, cross-review, promotion, protected paths, and non-obvious gotchas (bash 3.2, hook stdout never starting with `{`, `grep -c … || true`).
  - **Budget:** ≤ 200 lines. It must also stay under Codex's 32 KiB combined `project_doc_max_bytes` cap, which truncates silently mid-file (the repo-watch suggests ≤ 16 KiB). A validator fails the build if either is exceeded.
  - Everything else moves into skill `references/` loaded on demand.
- **R11.** `.claude/CLAUDE.md` (413 lines, 57 KB) and `templates/CLAUDE.md` are replaced. A **rule inventory** maps every rule in the old files to where it now lives, either the enforcing script/hook/permission or the skill reference that holds it. No rule is dropped silently (CE-14 / AS-18).
- **R12.** Correct the Codex trust wording: project AGENTS.md is skipped only when trust is explicitly `untrusted` (D-045).

### Skills (commands and agents included)

- **R13.** One `skills/` tree.
  - The 17 commands become skills. Workflows with side effects (`setup`, `ship`, `build`, `wrap`, `coordinate`, …) set `disable-model-invocation: true`, and argument syntax moves to `argument-hint`.
  - `commands/*.md` either go away or become thin wrappers (OS-1 / OP-3). Codex drops converted commands over 4,000 bytes, which is 8 of today's 17.
- **R14.** The 19 agents become persona prompt files inside the skills that dispatch them (`references/agents/` or `references/personas/`), with no frontmatter. The dispatching skill chooses the model, tools and effort.
  - The enforcement that frontmatter gives today has to survive the move, mechanically: read-only tool sets for reviewers, and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) held at the top tier. The plan decides how, for example restricted subagent types, sandboxes or scripts.
- **R15.** Spec conformance:
  - `name`/`description` limits, optional `license`/`compatibility`/`metadata`/`allowed-tools`, and `scripts/` `references/` `assets/` where they fit;
  - SKILL.md body ≤ 8 KB and under 5,000 tokens, with references one level deep;
  - descriptions short and trigger-first, with "not for — use X" pointers between siblings;
  - no CLI-specific tool names in skill bodies.

  `wave-orchestration` (22 KB) and `verification-before-completion` (10 KB) get split.
- **R16.** Skills are self-contained: they reference only files inside their own folder, and use no `${CLAUDE_PLUGIN_ROOT}` without a fallback. Bundled scripts run through the model-filled `SKILL_DIR` anchor. This means the helper scripts (`scripts/invoke-external.sh` + `scripts/lib/*.sh`) need a path that works from either lead.
- **R17.** Skill prose states the goal, the done condition, the safe failure direction and the facts the agent can't work out, not step-by-step procedures (compound-engineering's standard). A repo-local skill-authoring skill carries these rules (CE-16).
- **R18.** Prune generic skills that current models don't need, such as `test-driven-development`, `systematic-debugging` and `verification-before-completion`, after a removal test. Keep what's specific to Triforge.
- **R19.** `validate-skills.sh` enforces the repo-watch's 26-check conformance list (report §3) with one fixture per rule, runs `skills-ref validate`, and covers `commands/` and `agents/` for as long as they exist.

### Packaging

- **R20.** One plugin tree serves both leads: Codex falls back to `.claude-plugin/plugin.json` (D-048), so no root `plugin.json`.
  - Open question: whether to add a schema-less `.codex-plugin/plugin.json` too. A `$schema` form truncates skills to 8,000 bytes (OP-1).
  - Codex doesn't load plugin agents, which R14 accounts for.
- **R21.** Guard the hook handlers before anything makes Codex load the plugin's `hooks/hooks.json`, which sits at Codex's default plugin hook path (OP-4).
- **R22.** Skill manifests for other harnesses where they're cheap: Devin and Pi read `.agents/skills/` or `.claude-plugin/plugin.json` already (fact sheet).

### New workers

- **R23.** **Grok Build** (`grok`, xAI) as an optional member. It adds no new provider for R36.
  - Adapter requirements:
    - set `GROK_CLAUDE_*_ENABLED=0` so it doesn't load `~/.claude` config;
    - pin `--model grok-4.7 --effort <e>`;
    - parse its JSON result (`stopReason`, `end` event);
    - use `dontAsk` mode with deny rules.
  - The git no-push backstop remains the real push guard, because its `git push` deny is prefix-only.
  - Probe rows first: exit codes on max-turns and on a denial, `git -C . push` versus the deny rule, hooks under `-p`, the `workspace` sandbox against git in a lease worktree, and races on `~/.grok/auth.json` refresh across parallel leases.
- **R24.** **Devin CLI** (`devin`, Cognition) as an optional member.
  - Completion comes from the typed `Status:` line plus the exit code, since Devin has no JSON output. Health checks read `devin auth status` text, which exits 0 even when logged out.
  - Leave `DEVIN_REFUSAL_FALLBACK` unset.
  - The docs say it re-imports the login shell's environment, which would defeat `_adapter_env`. Probe it after `devin auth login`. If confirmed, default Devin to reviewer/analyst roles and allow builder only with an explicit warning in `/setup`.
  - `/setup` discloses the new provider, Cognition, which may train on code by default, and points to the opt-out. Consider `devin acp --agent-type review` for the reviewer role.
- **R25.** The adapter layer is shaped so a future CLI is one adapter file, roster defaults, probe rows, a `/setup` entry and one egress-list line. The PR template's "New CLI adapter" checklist stays the gate.

### Carry-ins from the watch cycle

- **R26.** The model ladder moves to one source that the other files reference, instead of four byte-identical copies checked by md5. Its `opus` rung becomes "Opus 5.5 (≥ 2.1.280)" (D-037).
- **R27.** `/goal` becomes a required completion gate, superseding D-030 (D-041). The `ops/.sprint-complete` sentinel stays the completion signal.
- **R28.** The agy routing default flips to `auto` (D-042). Parse agy's `AGY_ERROR` stderr line on exit 3 (D-043).
- **R29.** Research workers in the watch cycle get a tool set with no write access. Four workers wrote to `/tmp` and one read a `~/.codex` file despite the prose rule.

## Constraints

- Hooks and helpers run under macOS `/bin/bash` 3.2 with `set -euo pipefail`, and hook stdout never starts with `{` (see the current `.claude/CLAUDE.md` "Hook safety" until R11 lands).
- Protected-path rules apply to every PR here: the user or the lead cross-reviews, and never an external CLI alone.
- The core trio can't be disabled, and every fallback chain ends at a core member. Optional members skip silently when absent.
- Before PR 0 cuts anything: run `/doctor` in a session for a baseline, keep removed text in git, and run a removal test (the same fixture task with the old and new instruction sets).

## Out of scope

- Antigravity, OpenCode, Kimi or Cursor as lead.
- The OpenCode V2 port (D-049 defers it; the hotfix only refuses V2).
- Moving the Cursor pin to Grok 4.7 (waits for CUR-12).
- Pi, oh-my-pi and Hermes Agent as workers. Fact-sheet verdicts: Pi gets a skill manifest only (R22), and oh-my-pi and Hermes are skipped.

## Open questions for planning

1. R5: under a Codex lead, is protected-path review by the user only, or by the user or a Claude worker?
2. R14: which mechanism keeps reviewer tool limits and the never-downgrade trio's model pin once agents become persona files?
3. R20: rely on the `.claude-plugin/` fallback alone, or also ship a schema-less `.codex-plugin/plugin.json`?
4. R16: where do the shared helper scripts live so both leads can run them: bundled per skill, or one plugin-root path with a fallback?
5. R3: can `claude -p` inside a lease find the plugin's skills and AGENTS.md (SELF-06f), and what's the fix if not?

## Suggested PR sequence

0. Context audit and AGENTS.md (R10–R12, R18, the rule inventory). Opus 5.5 `medium` for the edits, `high` to verify.
1. Skills conformance and validator (R15–R17, R19). Commands and agents move into skills (R13, R14).
2. Roster `[lead]` and the `claude -p` worker lane (R1–R3, R6).
3. Codex lead: sandbox settings, hook guard, packaging (R4, R5, R20, R21).
4. `/setup` lead choice and enrollment flows (R7–R9).
5. Grok Build and Devin adapters (R23–R25), and skill manifests (R22).
6. Carry-ins (R26–R29), probe rows, and the release.

Plan with Fable 5.1 at `high`. Build each PR with Fable 5.1 at `high` under `/goal`, and review with Opus 5.5 at `high`.
