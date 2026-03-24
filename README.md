<p align="center">
  <img src="docs/images/hero-banner.svg" alt="Multi-Agent Framework — Hybrid coordination for Claude Code, Gemini CLI, and Codex CLI" width="100%">
</p>

<p align="center">
  <strong>Hybrid multi-agent coordination where Claude Code orchestrates Gemini CLI, Codex CLI, and specialized subagents through file-based protocols, portable skills, and parallel review swarms.</strong>
</p>

<p align="center">
  <a href="#what-is-this">Overview</a> ·
  <a href="#sprint-lifecycle">Lifecycle</a> ·
  <a href="#parallel-review-architecture">Review Swarm</a> ·
  <a href="#quality-gates">Quality Gates</a> ·
  <a href="#getting-started">Quick Start</a> ·
  <a href="#commands">Commands</a> ·
  <a href="#skills">Skills</a> ·
  <a href="#agents">Agents</a> ·
  <a href="#context-management">Context Management</a>
</p>

---

## What is this?

A production-grade framework that turns Claude Code into a **lead agent** coordinating multiple AI systems. Instead of using one model for everything, this framework assigns each model to what it does best:

- **Claude Code (Opus)** builds features and orchestrates the entire workflow
- **Gemini CLI** performs full-codebase analysis using its 1M token context window
- **Codex CLI** runs tests, security audits, and infrastructure tasks in sandboxed environments
- **Claude specialized agents** provide deep expertise in security, performance, architecture, and more

Every interaction between agents follows a structured protocol. Work is tracked in shared markdown files. Reviews run in parallel. Knowledge compounds across sessions.

> *Each sprint should make the next sprint easier — not harder.*

The framework achieves this through **institutional knowledge compounding**: every non-trivial problem solved gets documented in `ops/solutions/`, every architectural decision in `ops/decisions/`, and a `learnings-researcher` agent automatically searches these before planning new work.

<p align="center">
  <img src="docs/images/knowledge-loop.svg" alt="Knowledge compounding loop — solve, compound, search, plan, repeat" width="80%">
</p>

---

## Sprint lifecycle

Every goal flows through a structured lifecycle. Each phase has dedicated commands, skills, and agents.

<p align="center">
  <img src="docs/images/sprint-lifecycle.svg" alt="Sprint lifecycle — Phase 0 Analyze through Phase 6 Ship with review loop" width="95%">
</p>

| Phase | Agent(s) | Command | What happens |
|---|---|---|---|
| **0 — Analyze** | Gemini + `codebase-mapping` skill | `/plan` | Full-repo scan: architecture, patterns, contracts, debt |
| **Pre-Plan** | `learnings-researcher` agent | `/plan`, `/deep-research` | Search institutional knowledge for relevant past solutions |
| **1 — Plan** | Claude + `writing-plans` skill | `/plan` | Decompose goal into tasks with shadow paths, error maps, wave grouping |
| **1.5 — Validate** | `plan-checker` agent | `/plan` | Validate assignments, dependencies, scope, shadow path coverage |
| **2 — Build** | Claude subagents or agent teams | `/build` | Wave orchestration with integration verification between waves |
| **3–4 — Review** | Gemini + Codex + Claude review agents | `/review` | Up to 8 parallel reviewers, findings synthesized with confidence tiering |
| **5 — Test** | Codex + `test-driven-development` skill | `/test` | TDD test writing, gap analysis, fix cycle until green |
| **6 — Ship** | Claude + `knowledge-compounding` skill | `/wrap` | Document solutions, archive reviews, write STATE.md |

---

## Parallel review architecture

The framework's most sophisticated mechanism. Up to 8 reviewers analyze the same code simultaneously through different lenses, then a synthesizer merges, deduplicates, and priority-ranks all findings.

<p align="center">
  <img src="docs/images/review-swarm.svg" alt="Review swarm — 8 parallel reviewers feeding into findings-synthesizer" width="95%">
</p>

### Confidence tiering

Every finding gets a confidence score to prevent wasting time on phantom issues:

| Tier | Criteria | Rule |
|---|---|---|
| **HIGH** | Verified in codebase via grep/read. Deterministic. | Can be any priority |
| **MEDIUM** | Pattern-aggregated detection. Some false positive risk. | Can be any priority |
| **LOW** | Requires intent verification. Heuristic-only. | **Can NEVER be P1** |

### Suppressions

Each reviewer has a "Do Not Flag" list to reduce noise — readability-aiding redundancy, documented thresholds, sufficient test assertions, consistency-only style changes, and issues already addressed in the current diff.

---

## Quality gates

Five non-negotiable checkpoints enforced at every stage:

<p align="center">
  <img src="docs/images/quality-gates.svg" alt="Five quality gates — plan validated, failing test first, root cause first, evidence first, review first" width="95%">
</p>

---

## Four coordination modes

| Mode | Mechanism | When to use |
|---|---|---|
| **File-based** | Shared markdown files in `ops/` | Persistent state across sessions, audit trails |
| **Direct invocation** | `gemini -p` / `codex exec` via bash | Real-time external agent delegation |
| **Native subagents** | Claude's Agent tool with `.claude/agents/` definitions | Parallel focused tasks, review swarms |
| **Agent teams** | Multi-Claude instances with shared task lists | Complex builds with 5+ interdependent tasks |

### Portable skill injection

Skills are model-agnostic markdown files that ANY agent can consume:

```bash
# Claude uses skills natively
# Gemini receives skills via prompt injection
gemini -p "$(cat .claude/skills/codebase-mapping/SKILL.md) Analyze the full codebase..."

# Codex receives skills the same way
codex exec "$(cat .claude/skills/test-driven-development/SKILL.md) Write tests for..."
```

This decouples *what methodology to use* from *which model executes it*.

---

## Context management

### Dual-loop context exhaustion recovery

Two defense mechanisms prevent long sprints from dying to context limits:

| Layer | Mechanism | Guards against |
|---|---|---|
| **Inner loop** | `ship-loop.sh` Stop hook — blocks exit, re-feeds prompt (max 5x) | Claude giving up mid-pipeline |
| **Outer loop** | `scripts/coordinate.sh` — spawns fresh sessions with clean context | Context window filling up |
| **Analysis paralysis** | `context-monitor.sh` — warns at 8+ consecutive reads without writes | Reading without producing |
| **Risk scoring** | Per-subagent risk accumulation — halt at >20% or 50+ file changes | Runaway subagents |

```bash
# Full autonomous sprint with context recovery
./scripts/coordinate.sh "Build the authentication module" --max 5 --convergence deep --team
```

---

## Getting started

### Prerequisites

All three CLIs must be installed and authenticated:

```bash
# Claude Code (you're probably already here)
claude --version

# Gemini CLI
gemini -p "Respond with only: READY"

# Codex CLI
codex exec "Respond with only: READY"
```

### Installation

**Option 1 — Clone the framework:**

```bash
git clone https://github.com/Ninety2UA/multi-agent-framework.git
cd multi-agent-framework
```

**Option 2 — Add to an existing project:**

```bash
cp -r multi-agent-framework/.claude/ your-project/.claude/
cp -r multi-agent-framework/ops/ your-project/ops/
cp -r multi-agent-framework/scripts/ your-project/scripts/
cp multi-agent-framework/CLAUDE.md your-project/CLAUDE.md
```

**Option 3 — Claude-only (minimal):**

```bash
cp -r multi-agent-framework/.claude/ your-project/.claude/
```

### Configuration

Add to `.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "hooks": {
    "SessionStart": [
      { "command": ".claude/hooks/session-start.sh", "timeout": 5000 }
    ],
    "Stop": [
      { "command": ".claude/hooks/ship-loop.sh", "timeout": 10000 }
    ],
    "PostToolUse": [
      { "command": ".claude/hooks/context-monitor.sh", "timeout": 5000 }
    ]
  }
}
```

### Verify installation

```bash
claude

# Check available commands
/status

# You should see:
# "Multi-agent framework ready."
# "Commands: /ship /plan /build /review /test /debug /quick ..."
```

---

## Commands

### Full pipeline

| Command | What it does |
|---|---|
| **`/ship <goal>`** | Fully autonomous end-to-end sprint with inner loop guard. Won't stop until done. |
| **`/coordinate <goal>`** | Same phases but without the exit guard — you can stop and resume manually. |

### Phase-specific

| Command | Phase | What it does |
|---|---|---|
| **`/plan <goal>`** | 0 → 1.5 | Analyze codebase, plan with shadow paths, validate via plan-checker |
| **`/build [--team]`** | 2 | Wave orchestration build. `--team` for agent team mode. |
| **`/review [--full]`** | 3 → 4 | Parallel review + synthesis. `--full` for all 8 reviewers. |
| **`/test [scope]`** | 5 | Gap analysis + Codex TDD. `--gaps-only` to just identify gaps. |
| **`/wrap`** | 6 | Compound knowledge, archive reviews, write STATE.md. |

### Lightweight workflows

| Command | What it does |
|---|---|
| **`/quick <change>`** | For changes touching < 3 files. Skips heavy machinery. |
| **`/debug <bug>`** | Structured debugging: reproduce, diagnose, fix with root cause analysis. |

### Research and operations

| Command | What it does |
|---|---|
| **`/deep-research <topic>`** | Launch 5 parallel research agents + synthesizer. |
| **`/analyze <url>`** | Deep compatibility analysis of an external repo. |
| **`/status`** | Sprint overview: phase, tasks, blockers, available commands. |
| **`/pause`** | Quick checkpoint to STATE.md. |
| **`/resume`** | Continue from STATE.md checkpoint. |
| **`/compound`** | Document a solved problem or architectural decision. |
| **`/resolve-pr <PR#>`** | Read GitHub PR comments and implement requested changes. |

---

## Skills

12 portable, model-agnostic workflow modules that any agent can consume:

| Skill | Primary consumer | What it teaches the agent |
|---|---|---|
| **`codebase-mapping`** | Gemini (Phase 0) | Full-repo analysis: structure, data flow, patterns, debt |
| **`writing-plans`** | Claude (Phase 1) | Task decomposition with shadow paths, error maps, interface context |
| **`shadow-path-tracing`** | Claude (Phase 1) | Enumerate every failure path alongside the happy path |
| **`wave-orchestration`** | Claude (Phase 2) | Dependency-grouped parallel execution with integration checks |
| **`test-driven-development`** | Codex (Phase 5) | RED-GREEN-REFACTOR: no production code without failing test |
| **`systematic-debugging`** | Codex, Claude | Error taxonomy, assumption tracking, bisection, root cause |
| **`iterative-refinement`** | Claude (Phase 4) | Review-fix-review loops with convergence modes |
| **`review-synthesis`** | Claude (Phase 4) | Merge multi-reviewer findings with confidence tiering |
| **`verification-before-completion`** | All agents | Evidence-based completion checklist |
| **`knowledge-compounding`** | Claude (Phase 6) | Document solutions to `ops/solutions/` for future sprints |
| **`session-continuity`** | Claude | Save and resume via STATE.md across sessions |
| **`scope-cutting`** | Claude | Systematically cut scope by unblocking value and risk |

---

## Agents

### Core workflow (6)

| Agent | Phase | What it does |
|---|---|---|
| **`plan-checker`** | 1.5 | Validates task plans for completeness, assignments, dependencies |
| **`findings-synthesizer`** | 4 | Merges review outputs with deduplication and confidence tiering |
| **`integration-verifier`** | 2 | Runs build, tests, lint between waves |
| **`learnings-researcher`** | Pre-1 | Searches `ops/solutions/` and `ops/decisions/` for relevant patterns |
| **`team-lead`** | 2 | Orchestrates agent team workers with file ownership and quality gates |
| **`research-synthesizer`** | 0 | Merges parallel research outputs into unified analysis |

### Review specialists (6)

| Agent | Lens | What it catches |
|---|---|---|
| **`security-sentinel`** | Security | SQL injection, XSS, auth bypass, data exposure, OWASP |
| **`performance-oracle`** | Performance | O(n^2) loops, N+1 queries, memory leaks, scalability |
| **`code-simplicity-reviewer`** | Complexity | Over-engineering, YAGNI violations, unnecessary abstraction |
| **`convention-enforcer`** | Conventions | Naming, file organization, code style consistency |
| **`architecture-strategist`** | Structure | SOLID principles, coupling/cohesion, module boundaries |
| **`test-gap-analyzer`** | Coverage | Untested code paths, missing edge cases, weak assertions |

### Research and verification (6)

| Agent | What it does |
|---|---|
| **`best-practices-researcher`** | Industry-wide patterns, anti-patterns, tradeoff analysis |
| **`framework-docs-researcher`** | Current documentation for specific frameworks and libraries |
| **`git-history-analyzer`** | Code evolution and architectural decisions via git history |
| **`bug-reproduction-validator`** | Validates bugs are reproducible before fixes begin |
| **`deployment-verifier`** | Post-deployment health checks, smoke tests, error monitoring |
| **`pr-comment-resolver`** | Reads GitHub PR review comments and implements changes |

---

## Project structure

```
.claude/
├── agents/           18 specialized agent definitions
├── commands/         16 slash commands
├── skills/           12 portable skill modules
└── hooks/            3 lifecycle hooks

ops/
├── TASKS.md          Work queue with status tracking
├── MEMORY.md         Decisions, patterns, gotchas
├── CHANGELOG.md      Audit trail with attribution
├── CONTRACTS.md      Shared interface definitions
├── ARCHITECTURE.md   System design (Gemini writes)
├── STATE.md          Session continuity
├── solutions/        Documented solved problems
├── decisions/        Architecture decision records
└── archive/          Archived review + test files

scripts/
└── coordinate.sh     Outer loop for context exhaustion recovery
```

---

## How it compares

This framework was informed by analyzing the [Claude Code Blueprint](https://github.com/Ninety2UA/claude-code-blueprint) and selectively adopting patterns that complement our heterogeneous multi-model architecture.

| Dimension | Claude Code Blueprint | This framework |
|---|---|---|
| **Agent model** | Homogeneous (Claude-only) | Heterogeneous (Claude + Gemini + Codex) |
| **Review agents** | 6 Claude subagents | 8 reviewers (2 external + 6 Claude subagents) |
| **Codebase analysis** | Claude subagent | Gemini CLI (1M token context) |
| **Test execution** | Claude subagent | Codex CLI (sandboxed execution) |
| **Coordination** | Native subagents + git | File protocol + bash + subagents + teams |
| **Skills** | Claude-only | Portable across all 3 CLIs via injection |
| **Dependencies** | Zero (markdown only) | Three CLIs (Claude + Gemini + Codex) |

> **What we adopted:** Confidence tiering, suppressions lists, review synthesis, wave orchestration, quality gates, institutional knowledge compounding, dual-loop context management, risk scoring, completion promise pattern, shadow path tracing, session continuity.

> **What we added:** Multi-model coordination, portable skill injection into external agents, agent teams as a build mode, Gemini Phase 0 analysis, Codex sandboxed testing.

---

## When NOT to use this framework

| Situation | What to do instead |
|---|---|
| Trivial task (< 30 minutes) | Just use Claude Code directly |
| Pure exploration / brainstorming | Single agent conversation |
| Tight deadline, no tests needed | Claude Code solo, skip review + test |
| Non-code deliverables | Gemini solo with its large context |

---

## License

MIT

---

<p align="center">
  <sub>Built for teams that believe AI-assisted development should get better with every sprint.</sub>
</p>

<p align="center">
  <a href="docs/multi-agent-framework.md">Full Documentation</a> ·
  <a href="CLAUDE.md">CLAUDE.md</a>
</p>
