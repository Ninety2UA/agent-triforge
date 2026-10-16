[← Agent Triforge](../README.md#documentation)

# Workflow

Every goal goes through the same phases, and each phase has a lead workflow.

## Sprint Pipeline (`at-ship`)

Run [`at-ship`](../skills/at-ship/SKILL.md) (`/at-ship <goal>` under a Claude Code lead, `$agent-triforge:at-ship <goal>` in a Codex prompt) to run every phase autonomously, or run each phase's lead workflow yourself. `at-build` promotes the integration branch once, after its last wave, and writes the commit it started from as a `Build base:` line in `ops/TASKS.md`; `at-review` reviews from that commit, so a review run on its own after a build still covers the whole build.

<p align="center">
  <img src="images/sprint-lifecycle.png" alt="The sprint phases, Analyze, Plan, Build, Review, Test and Wrap, each with its lead workflow; at-ship runs them all." width="90%">
</p>

| Phase | What happens | Agents | Lead workflow |
|:---|:---|:---|:---|
| 0, Analyze | Full-repo scan: architecture, patterns, contracts, debt | Antigravity CLI + [`codebase-mapping`](../skills/codebase-mapping/SKILL.md) | [`at-plan`](../skills/at-plan/SKILL.md) |
| Pre-plan | Search institutional knowledge for relevant past solutions | [`learnings-researcher`](../personas/learnings-researcher.md) | [`at-plan`](../skills/at-plan/SKILL.md) |
| 1, Plan | Decompose the goal into tasks with shadow paths and error maps, grouped into waves | Lead + [`writing-plans`](../skills/writing-plans/SKILL.md) | [`at-plan`](../skills/at-plan/SKILL.md) |
| 1.1, Ambiguity | Surface the 3 most critical unverified assumptions and ask you to confirm or correct them | Lead | [`at-plan`](../skills/at-plan/SKILL.md), [`at-ship`](../skills/at-ship/SKILL.md) |
| 1.5, Validate | Validate assignments, dependencies, scope and shadow paths, up to 3 rounds | [`plan-checker`](../personas/plan-checker.md) | [`at-plan`](../skills/at-plan/SKILL.md) |
| 2, Build | Wave orchestration over leased builders, with integration verification between waves | Leased builders, or the [`team-lead`](../personas/team-lead.md) persona | [`at-build`](../skills/at-build/SKILL.md) |
| 3 and 4, Review | Five lanes at once (Antigravity, Codex, `security-sentinel`, `performance-oracle`, `code-simplicity-reviewer`), then synthesis with confidence tiers; up to 3 cycles | Antigravity + Codex + three [review personas](personas.md#review-specialists-6) | [`at-review`](../skills/at-review/SKILL.md) |
| 5, Test | Gap analysis, tests written failing first, up to 3 fix cycles, then escalation to you | Codex CLI ([`test_writer`](../codex-agents/agents.toml)) | [`at-test`](../skills/at-test/SKILL.md) |
| 6, Wrap | Document solutions, archive reviews, verify, write STATE.md, create `ops/.sprint-complete` last | Lead + [`knowledge-compounding`](../skills/knowledge-compounding/SKILL.md) | [`at-wrap`](../skills/at-wrap/SKILL.md) |

## Planning Pipeline (`at-plan`)

[`at-plan`](../skills/at-plan/SKILL.md) analyzes the full codebase with Antigravity's 1M-token context, searches institutional knowledge, decomposes the goal with shadow paths and error maps, asks you to confirm the riskiest assumptions, and then validates the plan with [`plan-checker`](../personas/plan-checker.md). It writes `ops/TASKS.md` with its `Ceremony:` line.

<p align="center">
  <img src="images/planning-flow.png" alt="Planning with at-plan: knowledge search and codebase analysis, then the plan, your check of its riskiest assumptions and plan-checker's validation, ending in ops/TASKS.md." width="90%">
</p>

## Test Pipeline (`at-test`)

[`test-gap-analyzer`](../personas/test-gap-analyzer.md) finds the untested code paths, then the roster's tester (Codex by default) writes and runs the tests in its sandbox, starting each one with a failing test. `ops/TEST_RESULTS.md` quotes the red run and the green run. Failures go through up to 3 fix cycles, and what still fails after that is escalated to you.

<p align="center">
  <img src="images/testing-flow.png" alt="The test pipeline: gap analysis, Codex writing each test to fail first, red-green-refactor, and up to 3 fix cycles before escalation." width="90%">
</p>

## Debugging (`at-debug`)

[`at-debug`](../skills/at-debug/SKILL.md) reproduces the bug first, finds the root cause with evidence, and only then fixes it. A report it can't reproduce goes back to you with a request for details, and a bug that is already fixed is reported with the fixing commit. A circuit breaker limits the attempts. After two failed fixes the agent stops and re-checks the assumption behind them; after a third failure on the same error it stops and writes an escalation report (the error signature, what was tried, a suggested next step).

<p align="center">
  <img src="images/debug-flow.png" alt="Debugging with at-debug: reproduce, diagnose, fix the root cause and verify, plus the early stops and the circuit breaker." width="90%">
</p>

## Quality Gates

Five gates hold at every stage:

<p align="center">
  <img src="images/quality-gates.png" alt="The five quality gates, each with what enforces it: a validated plan, a failing test first, a root cause, fresh evidence and a code review." width="90%">
</p>

| Gate | Enforced by | Rule |
|---|---|---|
| 1, Plan validated | [`plan-checker`](../personas/plan-checker.md) persona | No build without a validated plan (max 3 iterations) |
| 2, Failing test first | [`at-test`](../skills/at-test/SKILL.md) workflow, Codex [`test_writer`](../codex-agents/agents.toml) | No production code without a failing test |
| 3, Root cause first | [`at-debug`](../skills/at-debug/SKILL.md) workflow, Codex [`debugger`](../codex-agents/agents.toml) | No fix without diagnosis |
| 4, Evidence first | [`verification-before-completion`](../skills/verification-before-completion/SKILL.md) skill | No "done" without proof |
| 5, Review first | [`at-review`](../skills/at-review/SKILL.md) workflow, which merges findings with the [`review-synthesis`](../skills/review-synthesis/SKILL.md) skill | No merge without code review (max 3 cycles) |

## Lead workflows reference

The 17 lead workflows are skills under [`skills/at-*/`](../skills/) that only the lead runs. Type `/at-<name>` under a Claude Code lead or `$agent-triforge:at-<name>` inside a Codex prompt. They stay in the lead's plugin install and are never copied into `.agents/skills/` or a lease worktree (KTD12). Each `SKILL.md` states the workflow's goal, its done condition and the direction it fails safe; the detail is in its `references/` folder. In 3.x these were slash commands without the prefix (`/ship`, `/setup`); see [Upgrading from 3.x](upgrading.md).

| Lead workflow | Claude Code · Codex | Arguments | What it does |
|---|---|---|---|
| [`at-ship`](../skills/at-ship/SKILL.md) | `/at-ship` · `$agent-triforge:at-ship` | `<goal> [--convergence fast\|standard\|deep] [--team]` | Fully autonomous sprint: analyze, plan, build, review, test, wrap; prints a copyable completion line (the `/goal` gate under Claude Code) at the start and creates `ops/.sprint-complete` last. `fast` = P1 only, `deep` = P1 + P2 + P3 below 3; `--team` for 5+ or interdependent tasks. |
| [`at-coordinate`](../skills/at-coordinate/SKILL.md) | `/at-coordinate` · `$agent-triforge:at-coordinate` | `<goal>` | The plain Phase 0 to 6 sprint cycle that [`scripts/coordinate.sh`](../scripts/coordinate.sh) drives across fresh sessions; same pipeline as `at-ship` without convergence or team flags. |
| [`at-plan`](../skills/at-plan/SKILL.md) | `/at-plan` · `$agent-triforge:at-plan` | `[goal]` | Phases 0 → 1.5: codebase analysis, knowledge search, shadow paths, waves, the three-assumption ambiguity check, [`plan-checker`](../personas/plan-checker.md) validation. Writes `ops/TASKS.md` with its `Ceremony:` line. |
| [`at-build`](../skills/at-build/SKILL.md) | `/at-build` · `$agent-triforge:at-build` | `[--team] [--wave N]` | Phase 2: [wave orchestration](../skills/wave-orchestration/SKILL.md) over leased builder-pool tasks, cross-review by a pinned reviewer, one squash commit per task, `integration-verifier` per wave, the `[promotion]` gate. |
| [`at-review`](../skills/at-review/SKILL.md) | `/at-review` · `$agent-triforge:at-review` | `[--full] [--security] [--perf] [--simple] [--conventions]` | Phases 3 and 4: parallel roster lanes plus the selected specialists, [synthesis](../personas/findings-synthesizer.md), P1/P2 fixes, `## Review dispositions — Cycle N` in `ops/TASKS.md`; escalates after 3 cycles. |
| [`at-test`](../skills/at-test/SKILL.md) | `/at-test` · `$agent-triforge:at-test` | `[--gaps-only] [scope]` | Phase 5: [gap analysis](../personas/test-gap-analyzer.md), tests from the roster tester with the failing run first, results in `ops/TEST_RESULTS.md`, up to 3 fix cycles, then escalation to you. `--gaps-only` stops after the report. |
| [`at-wrap`](../skills/at-wrap/SKILL.md) | `/at-wrap` · `$agent-triforge:at-wrap` | (none) | Phase 6: [compound knowledge](../skills/knowledge-compounding/SKILL.md), update the `ops/` files, archive review files to `ops/archive/<today>/`, write [`STATE.md`](../ops/STATE.md), print the sprint summary with its rulings, create the completion marker last. |
| [`at-quick`](../skills/at-quick/SKILL.md) | `/at-quick` · `$agent-triforge:at-quick` | `[change description]` | A change touching fewer than 3 files with no shared interface or protected path: TDD, self-review, no swarm; hands off to `at-review --security` / `--perf` when a lens needs it. |
| [`at-debug`](../skills/at-debug/SKILL.md) | `/at-debug` · `$agent-triforge:at-debug` | `[bug description or error message]` | Reproduce, root-cause with evidence, fix, find sibling instances, record in `ops/MEMORY.md` and `ops/CHANGELOG.md`; after two failed fixes it re-checks the assumption, and a third failure on the same error ends in an escalation report. |
| [`at-setup`](../skills/at-setup/SKILL.md) | `/at-setup` · `$agent-triforge:at-setup` | `[lead\|opencode\|kimi\|cursor\|devin\|grok\|roles]` | Guided project setup: lead chosen, core trio live, Codex trust detected, roles kept, customized or restored, each optional CLI enrolled or declined, instruction files checked and changed only on a yes, egress listed; closes with the status table and a verdict. Idempotent. |
| [`at-deep-research`](../skills/at-deep-research/SKILL.md) | `/at-deep-research` · `$agent-triforge:at-deep-research` | `[topic or goal]` | Five parallel research lenses plus [`research-synthesizer`](../personas/research-synthesizer.md), every endpoint a recorded primary source; writes `ops/RESEARCH_ANTIGRAVITY.md` and hands off to `at-plan`. |
| [`at-analyze`](../skills/at-analyze/SKILL.md) | `/at-analyze` · `$agent-triforge:at-analyze` | `[github-url or local-path]` | Read-only judgment of an external repo or resource: extractable patterns, prompt-engineering insights, verdict matrix, ranked recommendations. Nothing written. |
| [`at-status`](../skills/at-status/SKILL.md) | `/at-status` · `$agent-triforge:at-status` | (none) | One report from `ops/`, git and the review files: phase, task counts, blockers, recent activity, pending reviews, uncommitted changes, available workflows. Writes nothing. |
| [`at-pause`](../skills/at-pause/SKILL.md) | `/at-pause` · `$agent-triforge:at-pause` | (none) | Write the [`STATE.md`](../ops/STATE.md) checkpoint a later session resumes from, and nothing else. |
| [`at-resume`](../skills/at-resume/SKILL.md) | `/at-resume` · `$agent-triforge:at-resume` | (none) | Restore [`STATE.md`](../ops/STATE.md), re-prove the baseline when HEAD moved, summarize, continue the recorded phase. |
| [`at-compound`](../skills/at-compound/SKILL.md) | `/at-compound` · `$agent-triforge:at-compound` | `[solution \| decision] <description>` | Record a solved problem in [`ops/solutions/`](../ops/solutions/) or a decision in [`ops/decisions/`](../ops/decisions/) when it clears the counterfactual bar; otherwise one line saying why nothing was written. |
| [`at-resolve-pr`](../skills/at-resolve-pr/SKILL.md) | `/at-resolve-pr` · `$agent-triforge:at-resolve-pr` | `<PR number or URL>` | Work through GitHub PR review comments via [`pr-comment-resolver`](../personas/pr-comment-resolver.md): implement, answer or defer each, run the tests, update `ops/CHANGELOG.md`. |
