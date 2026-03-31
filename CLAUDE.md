# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this plugin repository.

## Project overview

This is a **Claude Code plugin** providing a multi-agent coordination framework where Claude Code serves as the **lead agent**, orchestrating Gemini CLI, Codex CLI, and specialized Claude subagents through a hybrid file-based + bash-invocation + native-subagent protocol. The framework is defined in `docs/multi-agent-framework.md`.

Install: `claude plugin add https://github.com/Ninety2UA/multi-agent-framework`

## Architecture

### Multi-agent system

- **Claude Code (Opus)** — lead agent: plans work, builds features, coordinates all agents, merges review feedback
- **Claude specialized agents** — 18 focused subagents (`agents/`): plan validation, review synthesis, security, performance, etc.
- **Claude agent teams** — multi-instance collaboration for complex builds (5+ interdependent tasks)
- **Gemini CLI** — analyst + reviewer: Phase 0 codebase scans (1M token context), architecture reviews, documentation
- **Codex CLI** — tester + logic reviewer: writes/runs tests, security audits, infrastructure tasks

Claude invokes Gemini via `gemini -p "..."` and Codex via `codex exec "..."` as background bash processes. Skills are injected into external agents via `$(cat ${CLAUDE_PLUGIN_ROOT}/skills/SKILL_NAME/SKILL.md)`. Reviews run in parallel (Gemini + Codex + Claude subagents simultaneously), never sequentially.

### Four coordination modes

1. **File-based (persistent):** Shared markdown files in `ops/` are the source of truth
2. **Direct invocation (real-time):** Claude calls Gemini/Codex via bash, captures output
3. **Native subagents (parallel):** Claude's Agent tool for isolated parallel tasks with specialized agent definitions
4. **Agent teams (collaborative):** Multiple Claude instances with shared task lists and messaging (requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`)

### Shared file protocol (`ops/` directory)

| File | Purpose | Owner |
|---|---|---|
| `TASKS.md` | Work queue with status tracking | Claude generates and maintains |
| `MEMORY.md` | Architectural decisions, patterns, gotchas, interface proposals | All agents append |
| `CHANGELOG.md` | Audit trail with agent attribution | All agents append |
| `CONTRACTS.md` | Shared TypeScript interface definitions | Claude modifies, Gemini discovers |
| `ARCHITECTURE.md` | System design document | Gemini writes during Phase 0 |
| `AGENTS.md` | Master operating protocol read by all agents | Manual |
| `GOALS.md` | High-level product goals | Manual |
| `CONVENTIONS.md` | Code style and standards | Gemini discovers, Claude maintains |
| `STATE.md` | Session continuity — current phase, progress, next actions | Claude writes on pause/wrap |
| `solutions/` | Documented solved problems for institutional knowledge | Claude writes |
| `decisions/` | Architecture decision records (ADRs) | Claude writes |
| `REVIEW_GEMINI.md` | Gemini's review output (temporary) | Gemini writes, Claude reads |
| `REVIEW_CODEX.md` | Codex's review output (temporary) | Codex writes, Claude reads |
| `TEST_RESULTS.md` | Test results (temporary) | Codex writes, Claude reads |

### Execution phases

The full lifecycle for a goal:

0. **Codebase analysis** — Gemini scans full repo with codebase-mapping skill
1. **Pre-plan** — learnings-researcher agent searches institutional knowledge
1. **Planning** — Claude decomposes goal with shadow path tracing, error maps, interface context extraction
1.5. **Plan validation** — plan-checker agent validates TASKS.md (max 3 iterations)
2. **Build** — Wave orchestration via subagents (< 5 tasks) or agent teams (5+ tasks)
3. **Parallel review** — Gemini + Codex + Claude specialized agents (security-sentinel, performance-oracle, code-simplicity-reviewer) simultaneously
4. **Process reviews** — findings-synthesizer agent merges with confidence tiering, iterative-refinement skill for fix cycles
5. **Test** — Codex with TDD skill, test-gap-analyzer identifies coverage gaps
6. **Wrap up** — Knowledge compounding, verification checklist, completion promise, session continuity

### Assignment heuristic (quick reference)

- **Produces code?** → Claude (subagents or agent team for parallel work)
- **Evaluates existing code?** → Gemini + Codex + Claude specialized agents in parallel
- **Runs/executes something?** → Codex
- **Produces documentation?** → Gemini
- **Touches shared interfaces?** → Claude implements → Gemini reviews → Codex tests
- **Ambiguous?** → Claude takes it, flags for parallel review

### Key constraints

- CONTRACTS.md is never modified directly during review — changes must be proposed in MEMORY.md first
- Neither Gemini nor Codex may modify source code; they only write to their designated `ops/` files
- Parallel reviews are safe because agents write to separate files
- Maximum 3 review cycles per sprint before escalating to user
- Phase 0 can be skipped for small bug fixes, same-session continuations, or unchanged codebases
- Risk scoring: halt subagent at risk >20% or file changes >50
- Completion requires `<promise>DONE</promise>` after verification checklist passes

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
agents/                   # 18 specialized agent definitions
skills/                   # 12 portable skill files (all agents consume)
commands/                 # 16 slash commands
hooks/
  hooks.json              # Hook registration (uses ${CLAUDE_PLUGIN_ROOT})
  handlers/               # Lifecycle hook scripts
    session-start.sh        Session orientation + ops/ bootstrapping
    ship-loop.sh            Blocks premature exit during sprints
    context-monitor.sh      Warns on analysis paralysis
settings.json             # Default env vars (agent teams)
templates/                # Project bootstrapping templates
  CLAUDE.md                 Template for user projects
  ops/                      Skeleton ops/ files
scripts/
  coordinate.sh           # Outer loop for context exhaustion recovery
ops/                      # This repo's own project state (not part of plugin)
docs/                     # Framework design documentation
```

## Portable skills

Skills are model-agnostic markdown files consumed by ALL agents:

| Skill | Consumer | Purpose |
|---|---|---|
| `codebase-mapping` | Gemini | Full-repo analysis methodology |
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

Inject into external agents: `gemini -p "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/SKILL/SKILL.md) ..."` or `codex exec "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/SKILL/SKILL.md) ..."`

## Specialized agents

18 agents in `agents/` with restricted tools and focused expertise:

**Core workflow:** plan-checker, findings-synthesizer, integration-verifier, learnings-researcher, team-lead, research-synthesizer

**Review enhancement:** security-sentinel, performance-oracle, code-simplicity-reviewer, convention-enforcer, architecture-strategist, test-gap-analyzer

**Research & verification:** framework-docs-researcher, best-practices-researcher, git-history-analyzer, bug-reproduction-validator, deployment-verifier, pr-comment-resolver

## Agent invocation patterns

```bash
# Gemini with skill injection (non-interactive, background)
gemini -p "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/codebase-mapping/SKILL.md) Analyze codebase..." > /tmp/gemini_output.txt 2>&1 &
GEMINI_PID=$!

# Codex with skill injection (non-interactive, background)
codex exec "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/test-driven-development/SKILL.md) Write tests..." > /tmp/codex_output.txt 2>&1 &
CODEX_PID=$!

# Wait for parallel completion
wait $GEMINI_PID $CODEX_PID
```

## Context management

- **Inner loop:** `hooks/handlers/ship-loop.sh` Stop hook blocks premature exit during sprints (max 5 iterations, waits for `<promise>DONE</promise>`)
- **Outer loop:** `scripts/coordinate.sh` spawns fresh sessions on context exhaustion
- **Analysis paralysis:** `hooks/handlers/context-monitor.sh` warns at 8+ consecutive reads without writes
- **Risk scoring:** Subagents halted at risk >20% or 50+ file changes

## Prerequisites

All three CLIs must be installed and working in non-interactive mode:
```bash
gemini -p "Respond with only: READY"
codex exec "Respond with only: READY"
```
