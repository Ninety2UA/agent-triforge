# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this plugin repository.

## Project overview

This is a **Claude Code plugin** — **Agent Triforge** — providing a multi-agent coordination framework where Claude Code serves as the **lead agent**, orchestrating Antigravity CLI (binary: `agy`), Codex CLI, and specialized Claude subagents through a hybrid file-based + bash-invocation + native-subagent protocol. The framework is defined in `docs/agent-triforge.md`.

Install: `claude plugin add https://github.com/Ninety2UA/agent-triforge`

## Architecture

### Multi-agent system

- **Claude Code (lead)** — plans work, builds features, coordinates all agents, merges review feedback. Runs Fable 5 at `max` effort when the host has it; otherwise latest Opus at `max`
- **Claude specialized agents** — 19 focused subagents (`agents/`): plan validation, review synthesis, security, performance, etc. Shipped frontmatter floors at `opus` — no shipped file names a model a host may lack: team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) ship `model: opus`, `effort: max`; the other 15 ship `model: opus`, `effort: xhigh`
- **Spawn-time Fable override** — when the current probe record (`ops/research/2026-07-probe-record.md`, row CC-02) shows Fable 5 PASS on the host, the lead spawns team-lead and the never-downgrade trio with a model override to `fable` (the Agent tool's `model` parameter)
- **Claude agent teams** — multi-instance collaboration for complex builds (5+ interdependent tasks)
- **Antigravity CLI (`agy`)** — analyst + reviewer: Phase 0 codebase scans (Gemini 3.1 Pro (High), 1M token context), architecture reviews, documentation
- **Codex CLI** — tester + logic reviewer: writes/runs tests, security audits, infrastructure tasks

For narrow, rubric-following runtime tasks the lead/team-lead may step down one tier at a time:

Downgrade ladder for narrow runtime tasks: `fable`+`max` (lead + never-downgrade tier when available; otherwise latest `opus` at `max` — the model steps down, the effort does not) → `opus` (4.8) + `xhigh` → `opus`+`high` → `sonnet` (5) + `high`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.

Claude invokes Antigravity via `invoke_antigravity` and Codex via `invoke_codex` (from `scripts/invoke-external.sh`) as background bash processes. Skills are embedded in native agent definitions (`antigravity-agents/agents/`, `codex-agents/`); the helper falls back to prompt-prefix injection when native agent routing isn't available. Reviews run in parallel (Antigravity + Codex + Claude subagents simultaneously), never sequentially.

### Four coordination modes

1. **File-based (persistent):** Shared markdown files in `ops/` are the source of truth
2. **Direct invocation (real-time):** Claude calls Antigravity/Codex via bash, captures output
3. **Native subagents (parallel):** Claude's Agent tool for isolated parallel tasks with specialized agent definitions
4. **Agent teams (collaborative):** Multiple Claude instances with shared task lists and messaging (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`)

### Shared file protocol (`ops/` directory)

| File | Purpose | Owner |
|---|---|---|
| `TASKS.md` | Work queue with status tracking | Claude generates and maintains |
| `MEMORY.md` | Architectural decisions, patterns, gotchas, interface proposals | All agents append |
| `CHANGELOG.md` | Audit trail with agent attribution | All agents append |
| `CONTRACTS.md` | Shared TypeScript interface definitions | Claude modifies, Antigravity discovers |
| `ARCHITECTURE.md` | System design document | Antigravity writes during Phase 0 |
| `AGENTS.md` | Master operating protocol read by all agents | Manual |
| `GOALS.md` | High-level product goals | Manual |
| `CONVENTIONS.md` | Code style and standards | Antigravity discovers, Claude maintains |
| `STATE.md` | Session continuity — current phase, progress, next actions | Claude writes on pause/wrap |
| `solutions/` | Documented solved problems for institutional knowledge | Claude writes |
| `decisions/` | Architecture decision records (ADRs) | Claude writes |
| `research/` | Targeted research / gap analyses (CLI deprecations, library evaluations, etc.) | Claude or Antigravity writes |
| `REVIEW_ANTIGRAVITY.md` | Antigravity's review output (temporary) | Antigravity writes, Claude reads |
| `REVIEW_CODEX.md` | Codex's review output (temporary) | Codex writes, Claude reads |
| `RESEARCH_ANTIGRAVITY.md` | Antigravity targeted-research output (temporary) | Antigravity writes, Claude reads |
| `TEST_RESULTS.md` | Test results (temporary) | Codex writes, Claude reads |
| `.sprint-complete` | Runtime completion marker — created only after the verification checklist passes; `scripts/coordinate.sh` detects sprint completion by its existence (gitignored, never committed) | Claude creates at Phase 6 wrap |

### Execution phases

The full lifecycle for a goal:

0. **Codebase analysis** — Antigravity scans full repo with codebase-mapping skill
1a. **Pre-plan** — learnings-researcher agent searches institutional knowledge
1b. **Planning** — Claude decomposes goal with shadow path tracing, error maps, interface context extraction
1.1. **Ambiguity resolution** — Validate critical assumptions before building
1.5. **Plan validation** — plan-checker agent validates TASKS.md (max 3 iterations)
2. **Build** — Wave orchestration via subagents (< 5 tasks) or agent teams (5+ tasks)
3. **Parallel review** — Antigravity + Codex + Claude specialized agents (security-sentinel, performance-oracle, code-simplicity-reviewer) simultaneously
4. **Process reviews** — findings-synthesizer agent merges with confidence tiering, iterative-refinement skill for fix cycles
5. **Test** — Codex with TDD skill, test-gap-analyzer identifies coverage gaps
6. **Wrap up** — Knowledge compounding, verification checklist, completion sentinel (`ops/.sprint-complete`), session continuity

### Assignment heuristic (quick reference)

- **Produces code?** → Claude (subagents or agent team for parallel work)
- **Evaluates existing code?** → Antigravity + Codex + Claude specialized agents in parallel
- **Runs/executes something?** → Codex
- **Produces documentation?** → Antigravity
- **Touches shared interfaces?** → Claude implements → Antigravity reviews → Codex tests
- **Ambiguous?** → Claude takes it, flags for parallel review

### Agent frontmatter fields

Agent definitions in `agents/*.md` support these YAML frontmatter fields (verified against the official docs 2026-07-17):
- `name`, `description` (required) — identity and when-to-use trigger
- `model` — `fable`, `opus`, `sonnet`, `haiku`, a full model ID, or `inherit`. Shipped Triforge agents floor at `opus`; the lead applies the spawn-time `fable` override (see the ladder above)
- `effort` — `low`, `medium`, `high`, `xhigh`, `max` (`max` supported on Fable 5, Sonnet 5, and Opus 4.8/4.7)
- `tools` — allowlist of tools (Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, etc.); `disallowedTools` is the deny-side counterpart
- `maxTurns` — maximum agentic turns before the agent stops
- `initialPrompt` — new: auto-submitted first turn when the agent runs as the main session via `--agent`
- Other top-level fields: `skills`, `memory`, `background`, `isolation` (accepts only `"worktree"`), `color`
- **Plugin restriction:** plugin-shipped agents do not support `permissionMode`, `hooks`, or `mcpServers` (security restriction — those three apply only to user- and project-level agent files); no Triforge agent carries them

Antigravity and Codex agent files use their CLIs' own conventions: Antigravity (`antigravity-agents/agents/*.md`) uses `max_turns`/`timeout_mins` plus display-name model IDs (`"Gemini 3.1 Pro (High)"`) and lowercase tool names (`read_file`, `run_shell_command`); Codex (`codex-agents/agents.toml`) uses `model_reasoning_effort`, `sandbox_mode`, `approval_policy`, and `include_plan_tool`.

### Reliability patterns

- **Forced reflection on retry** — agents must self-diagnose before retrying (wave-orchestration; workflow requeue prepends the reflection questions)
- **Same-error kill criteria** — 3x same error fingerprint = kill executor + reassign to fresh agent
- **Continuous reviewer** — dedicated per-task reviewer in team builds (1:3-4 ratio with builders)
- **Per-task reflection** — conditional MEMORY.md entries when task took >3 retries, had test failures, or modified >5 files
- **Provenance tracking** — solutions/decisions include sprint_id, task_id, agent, evidence_files, related_decisions

### Hook safety

All 4 hook handlers use `set -euo pipefail`. When using `grep -c`, add `|| true` (not `|| echo "0"`) to prevent script termination on zero matches — `grep -c` already prints `0` to stdout before exiting 1, so `|| echo "0"` duplicates the output and produces a multiline `"0\n0"` value that corrupts downstream display and numeric comparisons.

### Key constraints

- CONTRACTS.md is never modified directly during review — changes must be proposed in MEMORY.md first
- Neither Antigravity nor Codex may modify source code; they only write to their designated `ops/` files
- Parallel reviews are safe because agents write to separate files
- Maximum 3 review cycles per sprint before escalating to user
- Phase 0 can be skipped for small bug fixes, same-session continuations, or unchanged codebases
- Risk scoring: halt subagent at risk >20% or file changes >50
- Completion requires creating the `ops/.sprint-complete` runtime marker, only after the verification checklist passes (never earlier)

### Security model

- **Codex `approval_policy = "never"`** on all three agents — the framework is designed for trusted pipelines where user approval would block parallel fan-out. `sandbox_mode` (read-only for `logic_reviewer`, `workspace-write` for `test_writer`/`debugger`) plus the per-agent `tools` allowlist provide the actual isolation. If you deploy to an untrusted environment, change to `approval_policy = "on-request"` in `codex-agents/agents.toml`. The no-agent fallback in `scripts/invoke-external.sh` supplies the same defaults explicitly (`-s workspace-write -c approval_policy="never"`) since Codex v0.128.0 removed the `--full-auto` shorthand.
- **Codex `tools` allowlist** narrows the tool surface beyond sandbox: `logic_reviewer` has no `write`/`bash`; `test_writer`/`debugger` get both (they need to run tests and reproduce bugs). Defense-in-depth pairs with `sandbox_mode`.
- **Antigravity permission guardrails** — `antigravity-agents/permissions.json` documents the shell-command deny rules migrated from the retired Gemini policy engine (`rm -rf`, `git push`, `sudo`); `templates/.antigravity/settings.json` ships them as a mergeable `permissions` block deployed to `.antigravity/settings.json` at session start. Headless enforcement at the project tier is unproven (probe 2026-07-17: no project-tier settings.json lifts agy's headless permission auto-deny, so the tier likely isn't read headless) — the per-agent `tools` allowlist in `antigravity-agents/agents/*.md` is the primary guardrail (e.g., `architecture-reviewer` and `documentation-writer` omit `run_shell_command` entirely).
- **Codex `[agents]` nesting caps** (`max_depth = 2`, `max_threads = 4`) prevent runaway fan-out when `logic_reviewer`/`test_writer` call `spawn_agent` for 5+ file scopes.
- **Codex auto-memory disabled by default** — Triforge ships `templates/.codex/config.toml` with `[memories] use_memories = false` to prevent Codex's v0.129.0 pipeline from writing `~/.codex/memories/{MEMORY.md, skills/, ...}` in parallel with Triforge's `ops/MEMORY.md` and `ops/solutions/`. Users who want Codex memories can remove the block or override in `~/.codex/config.toml`.
- **Antigravity skills interop** — `hooks/handlers/session-start.sh` copies `skills/` to `.agents/skills/` (the Antigravity workspace-skills tier and the cross-CLI agentskills.io path) so agents that discover workspace skills can pick up Triforge's portable skills without per-prompt `$(cat ...)` injection. The retired Gemini hooks example (`templates/.gemini/hooks.example.json`) was removed with the Gemini lane — project-tier hooks do not fire under `agy -p` (probed 2026-07-17).

### Quality gates

1. Plan validated before build (plan-checker agent)
2. Failing test before implementation (TDD skill)
3. Root cause analysis before fixes (systematic-debugging skill)
4. Verification evidence before completion (verification-before-completion skill)
5. Code review before shipping (parallel review, max 3 cycles)

## Plugin structure

```
.claude-plugin/
  plugin.json             # Plugin manifest
agents/                   # 19 Claude specialized agent definitions
antigravity-agents/       # Antigravity CLI agent pack (valid agy plugin)
  plugin.json               agy plugin manifest
  permissions.json          Permission guardrails (migrated deny rules + rationale)
  agents/
    codebase-analyst.md       Phase 0 full-repo analysis
    architecture-reviewer.md  Phase 3 architecture review
    targeted-researcher.md    Deep-research targeted analysis
    documentation-writer.md   Documentation specialist
codex-agents/             # Codex CLI native agent definitions
  agents.toml               logic_reviewer, test_writer, debugger
  review-verdict.schema.json Structured review verdict (--output-schema, logic_reviewer)
skills/                   # 12 portable skill files (all agents consume)
commands/                 # 16 slash commands
hooks/
  hooks.json              # Hook registration (uses ${CLAUDE_PLUGIN_ROOT})
  handlers/               # Lifecycle hook scripts
    session-start.sh        Session orientation + ops/ + agent bootstrapping
    context-monitor.sh      Warns on analysis paralysis
settings.json             # Default env vars (agent teams)
templates/                # Project bootstrapping templates
  CLAUDE.md                 Template for user projects
  ops/                      Skeleton ops/ files
  .antigravity/settings.json Antigravity workspace settings (permission deny rules)
  .codex/config.toml        Codex project config (disables Codex's auto-memory pipeline)
  .codex/hooks.json         Codex PostToolUse hook (CHANGELOG attribution under codex exec)
  .codex/README.md          What the hook enforces, why bypass-trust, how to disable
scripts/
  coordinate.sh           # Outer loop for context exhaustion recovery
  invoke-external.sh      # Unified Antigravity/Codex invocation with feature detection
ops/                      # This repo's own project state (not part of plugin)
docs/                     # Framework design documentation
```

## Portable skills

Skills are model-agnostic markdown files consumed by ALL agents:

| Skill | Consumer | Purpose |
|---|---|---|
| `codebase-mapping` | Antigravity | Full-repo analysis methodology |
| `writing-plans` | Claude | Task decomposition with shadow paths |
| `shadow-path-tracing` | Claude | Enumerate failure paths |
| `wave-orchestration` | Claude | Dependency-grouped parallel execution |
| `test-driven-development` | Codex | RED-GREEN-REFACTOR cycle |
| `systematic-debugging` | Codex, Claude | Error taxonomy, root cause analysis |
| `iterative-refinement` | Claude | Review-fix-review loops with convergence |
| `review-synthesis` | Claude | Merge multi-reviewer findings |
| `verification-before-completion` | All | Evidence-based completion checklist |
| `knowledge-compounding` | Claude | Document solutions and decisions |
| `session-continuity` | Claude | Save/resume across sessions |
| `scope-cutting` | Claude | Systematically cut scope by priority |

Skills consumed by Antigravity/Codex are embedded in their native agent definitions (`antigravity-agents/agents/`, `codex-agents/`). The `invoke-external.sh` helper handles feature detection and falls back to prompt-prefix injection when native agent routing isn't available.

## Specialized agents

19 agents in `agents/` with restricted tools and focused expertise:

**Core workflow:** plan-checker, findings-synthesizer, integration-verifier, learnings-researcher, team-lead, research-synthesizer, continuous-reviewer

**Review enhancement:** security-sentinel, performance-oracle, code-simplicity-reviewer, convention-enforcer, architecture-strategist, test-gap-analyzer

**Research & verification:** framework-docs-researcher, best-practices-researcher, git-history-analyzer, bug-reproduction-validator, deployment-verifier, pr-comment-resolver

## Agent invocation patterns

Commands invoke Antigravity and Codex through the unified helper with feature detection:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Use ${TMPDIR}-scoped, PID+timestamped paths so concurrent runs don't collide.
AGY_OUT="${TMPDIR:-/tmp}/antigravity_output_$$_$(date +%s).txt"
CODEX_OUT="${TMPDIR:-/tmp}/codex_output_$$_$(date +%s).txt"

# Antigravity codebase analysis (uses codebase-analyst agent definition)
invoke_antigravity "codebase-analyst" "Analyze codebase..." "$AGY_OUT" 600 &
AGY_PID=$!

# Codex test writing (uses test_writer agent definition)
invoke_codex "test_writer" "Write tests..." "$CODEX_OUT" 900 &
CODEX_PID=$!

# Per-PID wait — a silent failure in either helper leaves the downstream
# ops/REVIEW_*.md or ops/TEST_RESULTS.md empty and looks like "no findings".
AGY_RC=0; CODEX_RC=0
wait $AGY_PID || AGY_RC=$?
wait $CODEX_PID  || CODEX_RC=$?
[ $AGY_RC -ne 0 ] || [ $CODEX_RC -ne 0 ] && { echo "helper failed — antigravity=$AGY_RC codex=$CODEX_RC" >&2; exit 1; }
```

The helper detects native agent support at runtime. If `agy agents` lists the requested agent (agents come from installed agy plugins; not yet surfaced in headless mode on agy 1.1.3), it routes natively via `--agent`. Otherwise it extracts the agent body from `antigravity-agents/agents/<name>.md` and injects it as a prompt prefix (the operative mode today). Codex agents load from `.codex/agents/agents.toml`.

### External agent definitions

| Definition | CLI | Role |
|---|---|---|
| `antigravity-agents/agents/codebase-analyst.md` | Antigravity | Phase 0 full-repo analysis |
| `antigravity-agents/agents/architecture-reviewer.md` | Antigravity | Phase 3 architecture review |
| `antigravity-agents/agents/targeted-researcher.md` | Antigravity | Deep-research targeted analysis |
| `antigravity-agents/agents/documentation-writer.md` | Antigravity | Documentation generation |
| `codex-agents/agents.toml → logic_reviewer` | Codex | Phase 3 logic + security review |
| `codex-agents/agents.toml → test_writer` | Codex | Phase 5 TDD test writing |
| `codex-agents/agents.toml → debugger` | Codex | Bug investigation |

Claude invokes Antigravity via `invoke_antigravity` and Codex via `invoke_codex` as background bash processes. At session start, Codex definitions are copied to `.codex/agents/` in user projects and the Antigravity agent pack is registered once via `agy plugin install` (injection from the plugin templates covers the gap until agy surfaces plugin agents headless). Reviews run in parallel (Antigravity + Codex + Claude subagents simultaneously), never sequentially.

## Context management

- **Completion gating:** sprints are gated by a `/goal` checklist — `scripts/coordinate.sh` composes it as the leading line of each session prompt; `/ship` and `/coordinate` print a copyable `/goal` line for interactive use (probe CC-03; replaced the retired ship-loop.sh Stop hook)
- **Outer loop:** `scripts/coordinate.sh` spawns fresh sessions on context exhaustion; detects completion via the `ops/.sprint-complete` sentinel (headless-observable, no output parsing)
- **Analysis paralysis:** `hooks/handlers/context-monitor.sh` warns at 8+ consecutive reads without writes
- **Context checkpoint:** `hooks/handlers/pre-compact.sh` auto-snapshots `ops/STATE.md` (current phase + task counts) before Claude Code compacts the window, so a resume after compaction has a fresh anchor
- **Tool-failure threshold:** `hooks/handlers/tool-failure-monitor.sh` tracks consecutive and total tool failures, warning at 5 consecutive or 10 total per session
- **Risk scoring:** Subagents halted at risk >20% or 50+ file changes

## Prerequisites

**Claude Code ≥ 2.1.212** (floor per KTD-13: the session-caps/monitors line; `/goal` gating, dynamic workflows, and worktree isolation all landed earlier):
```bash
claude --version
```

All three CLIs must be installed and working in non-interactive mode:
```bash
agy --model "Gemini 3.1 Pro (High)" -p "Respond with only: READY"   # always pin the model — agy defaults to a Flash variant
codex exec "Respond with only: READY"
```

Python 3 is also required (used by hook handlers for JSON parsing):
```bash
python3 --version
```

On macOS, install GNU `coreutils` so `timeout` enforcement works for Antigravity/Codex invocations (`invoke-external.sh` is fail-closed: without `timeout`/`gtimeout` it refuses to run external invocations at all):
```bash
brew install coreutils
```
`session-start.sh` emits a warning when neither `timeout` nor `gtimeout` is on PATH.

## Compatibility

Tested against **Codex 0.144.4** (2026-07-17) and **Antigravity CLI (agy) 1.1.3** (2026-07-17).

**Minimum supported versions:**
- **Codex ≥ 0.144.0** — `--output-schema` (structured review verdicts), `codex features list` (runtime capability detection); hooks-under-exec verified on 0.144.4. Older versions degrade: `invoke_codex` still runs, but hook enforcement and structured verdicts silently fall back to raw output.
- **Gemini CLI floor removed** — the Gemini lane was replaced by Antigravity (agy ≥ 1.1.3, tested 1.1.3 2026-07-17); legacy Gemini users pin plugin v2.4.3.

**Known-fails / partial support:**
- Codex hooks **fire under `codex exec`** as of 0.144.4 (D-004 reversed — probe CDX-04, 2026-07-17: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Stop` all fired), but only with all three preconditions: nested `hooks.json` shape, project-tier `.codex/hooks.json`, and `--dangerously-bypass-hook-trust` (project trust is not persisted for arbitrary dirs; the flag is the documented automation path, and `invoke_codex` passes it only when the project ships `.codex/hooks.json` and `codex features list` reports `hooks` enabled). See `ops/decisions/2026-07-18-codex-hooks-under-exec.md`.
- Antigravity plugin agents are **not surfaced in headless mode** on agy 1.1.3 (`agy agents` stays empty and `--agent` silently ignores unknown names), so `invoke_antigravity` runs in injection mode; project-tier hooks and project-tier permission allow-rules also do not take effect under `agy -p` (probed 2026-07-17) — the `/review` and `/deep-research` commands compensate by promoting captured output into `ops/` when the agent could not write there directly.

### Release checklist

1. `claude plugin validate --strict .` passes green (warnings are errors) — required gate
2. Doc-consistency greps pass (see Verification Contract in the active plan)
3. Ladder byte-identity holds across `agents/team-lead.md`, `skills/wave-orchestration/SKILL.md`, and this file
4. Version bumped in `.claude-plugin/plugin.json`; README "Recent changes" entry added
