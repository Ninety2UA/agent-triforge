# CLAUDE.md

This file provides guidance to Claude Code when working with code in this project. It works with the **Agent Triforge** plugin.

## Project overview

This project uses the multi-agent coordination framework where Claude Code serves as the **lead agent**, orchestrating Gemini CLI, Codex CLI, and specialized Claude subagents through a hybrid file-based + bash-invocation + native-subagent protocol.

## Architecture

### Multi-agent system

- **Claude Code (Opus)** — lead agent: plans work, builds features, coordinates all agents, merges review feedback
- **Claude specialized agents** — 18 focused subagents provided by the plugin: plan validation, review synthesis, security, performance, etc.
- **Claude agent teams** — multi-instance collaboration for complex builds (5+ interdependent tasks)
- **Gemini CLI** — analyst + reviewer: Phase 0 codebase scans (1M token context), architecture reviews, documentation
- **Codex CLI** — tester + logic reviewer: writes/runs tests, security audits, infrastructure tasks

Claude invokes Gemini via `gemini -p "..."` and Codex via `codex exec "..."` as background bash processes. Skills are injected into external agents via `$(cat ${CLAUDE_PLUGIN_ROOT}/skills/SKILL_NAME/SKILL.md)`. Reviews run in parallel (Gemini + Codex + Claude subagents simultaneously), never sequentially.

### Shared file protocol (`ops/` directory)

| File | Purpose | Owner |
|---|---|---|
| `TASKS.md` | Work queue with status tracking | Claude generates and maintains |
| `MEMORY.md` | Architectural decisions, patterns, gotchas, interface proposals | All agents append |
| `CHANGELOG.md` | Audit trail with agent attribution | All agents append |
| `CONTRACTS.md` | Shared TypeScript interface definitions | Claude modifies, Gemini discovers |
| `ARCHITECTURE.md` | System design document | Gemini writes during Phase 0 |
| `GOALS.md` | High-level product goals | Manual |
| `CONVENTIONS.md` | Code style and standards | Gemini discovers, Claude maintains |
| `STATE.md` | Session continuity — current phase, progress, next actions | Claude writes on pause/wrap |
| `solutions/` | Documented solved problems for institutional knowledge | Claude writes |
| `decisions/` | Architecture decision records (ADRs) | Claude writes |

### Execution phases

0. **Codebase analysis** — Gemini scans full repo with codebase-mapping skill
1. **Pre-plan** — learnings-researcher agent searches institutional knowledge
1. **Planning** — Claude decomposes goal with shadow path tracing, error maps, interface context extraction
1.5. **Plan validation** — plan-checker agent validates TASKS.md (max 3 iterations)
2. **Build** — Wave orchestration via subagents (< 5 tasks) or agent teams (5+ tasks)
3. **Parallel review** — Gemini + Codex + Claude specialized agents simultaneously
4. **Process reviews** — findings-synthesizer agent merges with confidence tiering
5. **Test** — Codex with TDD skill, test-gap-analyzer identifies coverage gaps
6. **Wrap up** — Knowledge compounding, verification checklist, completion promise, session continuity

### Assignment heuristic

- **Produces code?** → Claude (subagents or agent team for parallel work)
- **Evaluates existing code?** → Gemini + Codex + Claude specialized agents in parallel
- **Runs/executes something?** → Codex
- **Produces documentation?** → Gemini
- **Touches shared interfaces?** → Claude implements → Gemini reviews → Codex tests

### Key constraints

- CONTRACTS.md is never modified directly during review — changes must be proposed in MEMORY.md first
- Neither Gemini nor Codex may modify source code; they only write to their designated `ops/` files
- Maximum 3 review cycles per sprint before escalating to user
- Risk scoring: halt subagent at risk >20% or file changes >50
- Completion requires `<promise>DONE</promise>` after verification checklist passes

### Quality gates

1. Plan validated before build (plan-checker agent)
2. Failing test before implementation (TDD skill)
3. Root cause analysis before fixes (systematic-debugging skill)
4. Verification evidence before completion (verification-before-completion skill)
5. Code review before shipping (parallel review, max 3 cycles)

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

### Git trailer conventions

Commits include structured trailers for decision context:

| Trailer | When to use |
|---|---|
| `Constraint:` | What forced this approach (always include on non-trivial commits) |
| `Rejected:` | Alternative considered and why it was dropped |
| `Confidence:` | high/medium/low — certainty level (always include) |
| `Scope-risk:` | What could break outside changed files |
| `Not-tested:` | Known test coverage gaps |

## Prerequisites

All three CLIs must be installed and working in non-interactive mode:
```bash
gemini -p "Respond with only: READY"
codex exec "Respond with only: READY"
```
