<p align="center">
  <img src="docs/images/hero-banner.svg" alt="Multi-Agent Framework — Hybrid coordination for Claude Code, Gemini CLI, and Codex CLI" width="100%">
</p>

<p align="center">
  <strong>Hybrid multi-agent coordination where Claude Code orchestrates Gemini CLI, Codex CLI, and specialized subagents through file-based protocols, portable skills, and parallel review swarms.</strong>
</p>

<p align="center">
  <a href="#what-is-this">Overview</a> ·
  <a href="#project-structure">Structure</a> ·
  <a href="#sprint-lifecycle">Lifecycle</a> ·
  <a href="#parallel-review-architecture">Review Swarm</a> ·
  <a href="#quality-gates">Quality Gates</a> ·
  <a href="#getting-started">Quick Start</a> ·
  <a href="#commands-reference">Commands</a> ·
  <a href="#skills-reference">Skills</a> ·
  <a href="#agents-reference">Agents</a> ·
  <a href="#context-management">Context</a> ·
  <a href="#how-it-compares">Compare</a> ·
  <a href="#faq">FAQ</a>
</p>

---

## What is this?

A production-grade framework that turns Claude Code into a **lead agent** coordinating multiple AI systems. Instead of using one model for everything, this framework assigns each model to what it does best:

- **[Claude Code](https://docs.anthropic.com/en/docs/claude-code) (Opus)** builds features and orchestrates the entire workflow
- **[Gemini CLI](https://github.com/google-gemini/gemini-cli)** performs full-codebase analysis using its 1M token context window
- **[Codex CLI](https://github.com/openai/codex)** runs tests, security audits, and infrastructure tasks in sandboxed environments
- **Claude specialized agents** provide deep expertise in [security](.claude/agents/security-sentinel.md), [performance](.claude/agents/performance-oracle.md), [architecture](.claude/agents/architecture-strategist.md), and more

Every interaction between agents follows a structured protocol. Work is tracked in shared markdown files. Reviews run in parallel. Knowledge compounds across sessions.

> *Each sprint should make the next sprint easier — not harder.*

The framework achieves this through **institutional knowledge compounding**: every non-trivial problem solved gets documented in [`ops/solutions/`](ops/solutions/), every architectural decision in [`ops/decisions/`](ops/decisions/), and a [`learnings-researcher`](.claude/agents/learnings-researcher.md) agent automatically searches these before planning new work.

<p align="center">
  <img src="docs/images/knowledge-loop.svg" alt="Knowledge compounding loop — solve, compound, search, plan, repeat" width="80%">
</p>

---

## Project structure

```
your-project/
├── CLAUDE.md                    Master orchestration protocol (Claude reads this)
├── GEMINI.md                    Gemini CLI protocol
├── CODEX.md                     Codex CLI protocol
│
├── .claude/
│   ├── agents/                  18 specialized agent definitions
│   │   ├── plan-checker.md          Validates task plans before build
│   │   ├── findings-synthesizer.md  Merges review outputs
│   │   ├── security-sentinel.md     OWASP, auth, vulnerability scanning
│   │   ├── performance-oracle.md    N+1, O(n²), memory, scalability
│   │   ├── team-lead.md            Orchestrates agent team workers
│   │   └── ...                      14 more specialized agents
│   ├── skills/                  12 portable workflow modules
│   │   ├── writing-plans/           Task decomposition with shadow paths
│   │   ├── wave-orchestration/      Dependency-grouped parallel execution
│   │   ├── test-driven-development/ RED-GREEN-REFACTOR cycle
│   │   ├── review-synthesis/        Multi-reviewer findings merge
│   │   └── ...                      8 more skill modules
│   ├── commands/                16 slash commands
│   │   ├── ship.md                  Fully autonomous end-to-end sprint
│   │   ├── plan.md                  Codebase analysis + planning
│   │   ├── review.md               Parallel review swarm
│   │   └── ...                      13 more commands
│   └── hooks/                   3 lifecycle hooks
│       ├── ship-loop.sh             Blocks premature exit during sprints
│       ├── context-monitor.sh       Warns on analysis paralysis
│       └── session-start.sh         Session initialization
│
├── ops/                         Shared coordination files
│   ├── TASKS.md                     Work queue with status tracking
│   ├── MEMORY.md                    Decisions, patterns, gotchas
│   ├── CHANGELOG.md                 Audit trail with agent attribution
│   ├── STATE.md                     Session continuity checkpoint
│   ├── solutions/                   Documented solved problems
│   ├── decisions/                   Architecture decision records
│   └── archive/                     Archived review + test files
│
├── scripts/
│   └── coordinate.sh            Outer loop for context exhaustion recovery
│
└── docs/
    └── multi-agent-framework.md Full framework specification
```

### Shared file protocol

All agents coordinate through markdown files in [`ops/`](ops/). This is the source of truth:

| File | Purpose | Owner |
|---|---|---|
| `TASKS.md` | Work queue with `[ ]`/`[x]` status tracking | Claude generates, all agents read |
| [`MEMORY.md`](ops/MEMORY.md) | Architectural decisions, patterns, interface proposals | All agents append |
| [`CHANGELOG.md`](ops/CHANGELOG.md) | Audit trail with `[agent-name]` attribution | All agents append |
| [`STATE.md`](ops/STATE.md) | Session continuity — current phase, progress, next actions | Claude writes on pause/wrap |
| [`solutions/`](ops/solutions/) | Documented solved problems for institutional knowledge | Claude writes via [`/compound`](.claude/commands/compound.md) |
| [`decisions/`](ops/decisions/) | Architecture decision records (ADRs) | Claude writes via [`/compound`](.claude/commands/compound.md) |

---

## Sprint lifecycle

Every goal flows through a structured lifecycle. Each phase has dedicated [commands](#commands-reference), [skills](#skills-reference), and [agents](#agents-reference).

<p align="center">
  <img src="docs/images/sprint-lifecycle.svg" alt="Sprint lifecycle — Phase 0 Analyze through Phase 6 Ship with review loop" width="95%">
</p>

| Phase | What happens | Agent(s) | Command |
|:---|:---|:---|:---|
| **0 — Analyze** | Full-repo scan: architecture, patterns, contracts, debt | Gemini CLI + [`codebase-mapping`](.claude/skills/codebase-mapping/SKILL.md) | [`/plan`](.claude/commands/plan.md) |
| **Pre-Plan** | Search institutional knowledge for relevant past solutions | [`learnings-researcher`](.claude/agents/learnings-researcher.md) | [`/plan`](.claude/commands/plan.md) |
| **1 — Plan** | Decompose goal into tasks with shadow paths and error maps | Claude + [`writing-plans`](.claude/skills/writing-plans/SKILL.md) | [`/plan`](.claude/commands/plan.md) |
| **1.5 — Validate** | Validate assignments, dependencies, scope, shadow paths | [`plan-checker`](.claude/agents/plan-checker.md) | [`/plan`](.claude/commands/plan.md) |
| **2 — Build** | Wave orchestration with integration verification between waves | Claude subagents or [`team-lead`](.claude/agents/team-lead.md) | [`/build`](.claude/commands/build.md) |
| **3–4 — Review** | Up to 8 parallel reviewers, synthesized with confidence tiering | Gemini + Codex + [review agents](#review-specialists-6) | [`/review`](.claude/commands/review.md) |
| **5 — Test** | TDD test writing, gap analysis, fix cycle until green | Codex CLI + [`test-driven-development`](.claude/skills/test-driven-development/SKILL.md) | [`/test`](.claude/commands/test.md) |
| **6 — Ship** | Document solutions, archive reviews, write STATE.md | Claude + [`knowledge-compounding`](.claude/skills/knowledge-compounding/SKILL.md) | [`/wrap`](.claude/commands/wrap.md) |

---

## Four coordination modes

| Mode | Mechanism | When to use |
|---|---|---|
| **File-based** | Shared markdown in [`ops/`](ops/) | Persistent state across sessions, audit trails |
| **Direct invocation** | `gemini -p` / `codex exec` via bash | Real-time external agent delegation |
| **Native subagents** | Claude's Agent tool with [`.claude/agents/`](.claude/agents/) definitions | Parallel focused tasks, review swarms |
| **Agent teams** | Multi-Claude with shared task lists ([`team-lead`](.claude/agents/team-lead.md)) | Complex builds with 5+ interdependent tasks |

### Portable skill injection

Skills are model-agnostic markdown files that ANY agent can consume. This decouples *what methodology to use* from *which model executes it*:

```bash
# Claude uses skills natively (via commands and agent definitions)

# Gemini receives skills via prompt injection
gemini -p "$(cat .claude/skills/codebase-mapping/SKILL.md) Analyze the full codebase..."

# Codex receives skills the same way
codex exec "$(cat .claude/skills/test-driven-development/SKILL.md) Write tests for..."
```

### Assignment heuristic

| Question | Agent |
|---|---|
| Produces code? | Claude (subagents or [agent team](.claude/agents/team-lead.md) for parallel work) |
| Evaluates existing code? | [Gemini](https://github.com/google-gemini/gemini-cli) + [Codex](https://github.com/openai/codex) + [Claude review agents](#review-specialists-6) in parallel |
| Runs/executes something? | [Codex CLI](https://github.com/openai/codex) |
| Produces documentation? | [Gemini CLI](https://github.com/google-gemini/gemini-cli) |
| Touches shared interfaces? | Claude implements → Gemini reviews → Codex tests |
| Ambiguous? | Claude takes it, flags for parallel review |

---

## Parallel review architecture

The framework's most sophisticated mechanism. Up to 8 reviewers analyze the same code simultaneously through different lenses, then a [`findings-synthesizer`](.claude/agents/findings-synthesizer.md) merges, deduplicates, and priority-ranks all findings.

<p align="center">
  <img src="docs/images/review-swarm.svg" alt="Review swarm — 7 parallel reviewers feeding into findings-synthesizer" width="95%">
</p>

### Confidence tiering

Every finding gets a confidence score to prevent wasting time on phantom issues:

| Tier | Criteria | Rule |
|---|---|---|
| **HIGH** | Verified in codebase via grep/read. Deterministic. | Can be any priority |
| **MEDIUM** | Pattern-aggregated detection. Some false positive risk. | Can be any priority |
| **LOW** | Requires intent verification. Heuristic-only. | **Can NEVER be P1** |

### Suppressions

Each reviewer has a "Do Not Flag" list to reduce noise — readability-aiding redundancy, documented thresholds, sufficient test assertions, consistency-only style changes, and issues already addressed in the current diff. See individual [agent definitions](.claude/agents/) for each reviewer's suppressions list.

---

## Quality gates

Five non-negotiable checkpoints enforced at every stage:

<p align="center">
  <img src="docs/images/quality-gates.svg" alt="Five quality gates — plan validated, failing test first, root cause first, evidence first, review first" width="95%">
</p>

| Gate | Enforced by | Rule |
|---|---|---|
| **1 — Plan validated** | [`plan-checker`](.claude/agents/plan-checker.md) agent | No build without validated plan (max 3 iterations) |
| **2 — Failing test first** | [`test-driven-development`](.claude/skills/test-driven-development/SKILL.md) skill | No production code without a failing test |
| **3 — Root cause first** | [`systematic-debugging`](.claude/skills/systematic-debugging/SKILL.md) skill | No fix without diagnosis |
| **4 — Evidence first** | [`verification-before-completion`](.claude/skills/verification-before-completion/SKILL.md) skill | No "done" without proof |
| **5 — Review first** | [`review-synthesis`](.claude/skills/review-synthesis/SKILL.md) skill | No merge without code review (max 3 cycles) |

---

## Getting started

### Prerequisites

All three CLIs must be installed and authenticated:

```bash
# Claude Code (you're probably already here)
claude --version

# Gemini CLI — https://github.com/google-gemini/gemini-cli
gemini -p "Respond with only: READY"

# Codex CLI — https://github.com/openai/codex
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
# Only the AI configuration — skills, agents, commands, hooks
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

### Typical session flow

**Supervised (human in the loop):**

```bash
claude
> /plan add user authentication         # Phase 0-1.5: analyze, research, plan, validate
> /build                                 # Phase 2: wave orchestration
> /review                                # Phase 3-4: parallel review + synthesis
> /test                                  # Phase 5: Codex TDD
> /compound JWT session handling         # Document solution for future sprints
> /wrap                                  # Phase 6: compound knowledge, write STATE.md
```

**Autonomous (fire and forget):**

```bash
# Inside Claude — single session, won't stop until done
claude
> /ship add user authentication with JWT refresh tokens

# From terminal — with context-exhaustion recovery
./scripts/coordinate.sh "add user authentication" --max 5 --team
```

---

## Commands reference

### Full pipeline

| Command | What it does |
|---|---|
| [**`/ship <goal>`**](.claude/commands/ship.md) | Fully autonomous end-to-end sprint with inner loop guard. Won't stop until done. |
| [**`/coordinate <goal>`**](.claude/commands/coordinate.md) | Same phases but without the exit guard — you can stop and resume manually. |

### Phase-specific

| Command | Phase | What it does |
|---|---|---|
| [**`/plan <goal>`**](.claude/commands/plan.md) | 0 → 1.5 | Analyze codebase, plan with shadow paths, validate via [`plan-checker`](.claude/agents/plan-checker.md) |
| [**`/build`**](.claude/commands/build.md) | 2 | [Wave orchestration](.claude/skills/wave-orchestration/SKILL.md) build. `--team` for [agent team](.claude/agents/team-lead.md) mode. |
| [**`/review`**](.claude/commands/review.md) | 3 → 4 | Parallel review + [synthesis](.claude/agents/findings-synthesizer.md). `--full` for all 8 reviewers. |
| [**`/test`**](.claude/commands/test.md) | 5 | [Gap analysis](.claude/agents/test-gap-analyzer.md) + [Codex](https://github.com/openai/codex) TDD. `--gaps-only` to just identify gaps. |
| [**`/wrap`**](.claude/commands/wrap.md) | 6 | [Compound knowledge](.claude/skills/knowledge-compounding/SKILL.md), archive reviews, write [`STATE.md`](ops/STATE.md). |

### Lightweight workflows

| Command | What it does |
|---|---|
| [**`/quick <change>`**](.claude/commands/quick.md) | For changes touching < 3 files. Skips heavy machinery. |
| [**`/debug <bug>`**](.claude/commands/debug.md) | Structured [debugging](.claude/skills/systematic-debugging/SKILL.md): reproduce, diagnose, fix with root cause analysis. |

### Research and operations

| Command | What it does |
|---|---|
| [**`/deep-research <topic>`**](.claude/commands/deep-research.md) | Launch 5 parallel research agents + [`research-synthesizer`](.claude/agents/research-synthesizer.md). |
| [**`/analyze <url>`**](.claude/commands/analyze.md) | Deep compatibility analysis of an external repo. |
| [**`/status`**](.claude/commands/status.md) | Sprint overview: phase, tasks, blockers, available commands. |
| [**`/pause`**](.claude/commands/pause.md) | Quick checkpoint to [`STATE.md`](ops/STATE.md). |
| [**`/resume`**](.claude/commands/resume.md) | Continue from [`STATE.md`](ops/STATE.md) checkpoint. |
| [**`/compound`**](.claude/commands/compound.md) | Document a solved problem to [`ops/solutions/`](ops/solutions/) or decision to [`ops/decisions/`](ops/decisions/). |
| [**`/resolve-pr <PR#>`**](.claude/commands/resolve-pr.md) | Read GitHub PR comments and implement requested changes via [`pr-comment-resolver`](.claude/agents/pr-comment-resolver.md). |

---

## Skills reference

12 portable, model-agnostic workflow modules that any agent can consume. Skills are injected into external agents via `$(cat .claude/skills/SKILL/SKILL.md)`.

| Skill | Primary consumer | What it teaches the agent |
|---|---|---|
| [**`codebase-mapping`**](.claude/skills/codebase-mapping/SKILL.md) | [Gemini](https://github.com/google-gemini/gemini-cli) (Phase 0) | Full-repo analysis: structure, data flow, patterns, debt |
| [**`writing-plans`**](.claude/skills/writing-plans/SKILL.md) | Claude (Phase 1) | Task decomposition with shadow paths, error maps, interface context |
| [**`shadow-path-tracing`**](.claude/skills/shadow-path-tracing/SKILL.md) | Claude (Phase 1) | Enumerate every failure path alongside the happy path |
| [**`wave-orchestration`**](.claude/skills/wave-orchestration/SKILL.md) | Claude (Phase 2) | Dependency-grouped parallel execution with integration checks |
| [**`test-driven-development`**](.claude/skills/test-driven-development/SKILL.md) | [Codex](https://github.com/openai/codex) (Phase 5) | RED-GREEN-REFACTOR: no production code without failing test |
| [**`systematic-debugging`**](.claude/skills/systematic-debugging/SKILL.md) | Codex, Claude | Error taxonomy, assumption tracking, bisection, root cause |
| [**`iterative-refinement`**](.claude/skills/iterative-refinement/SKILL.md) | Claude (Phase 4) | Review-fix-review loops with convergence modes |
| [**`review-synthesis`**](.claude/skills/review-synthesis/SKILL.md) | Claude (Phase 4) | Merge multi-reviewer findings with confidence tiering |
| [**`verification-before-completion`**](.claude/skills/verification-before-completion/SKILL.md) | All agents | Evidence-based completion checklist |
| [**`knowledge-compounding`**](.claude/skills/knowledge-compounding/SKILL.md) | Claude (Phase 6) | Document solutions to [`ops/solutions/`](ops/solutions/) for future sprints |
| [**`session-continuity`**](.claude/skills/session-continuity/SKILL.md) | Claude | Save and resume via [`STATE.md`](ops/STATE.md) across sessions |
| [**`scope-cutting`**](.claude/skills/scope-cutting/SKILL.md) | Claude | Systematically cut scope by unblocking value and risk |

---

## Agents reference

18 agents in [`.claude/agents/`](.claude/agents/) with restricted tools and focused expertise. Each runs in its own context window.

### Core workflow (6)

| Agent | Phase | What it does |
|---|---|---|
| [**`plan-checker`**](.claude/agents/plan-checker.md) | 1.5 | Validates task plans for completeness, assignments, dependencies |
| [**`findings-synthesizer`**](.claude/agents/findings-synthesizer.md) | 4 | Merges review outputs with deduplication and confidence tiering |
| [**`integration-verifier`**](.claude/agents/integration-verifier.md) | 2 | Runs build, tests, lint between waves |
| [**`learnings-researcher`**](.claude/agents/learnings-researcher.md) | Pre-1 | Searches [`ops/solutions/`](ops/solutions/) and [`ops/decisions/`](ops/decisions/) for relevant patterns |
| [**`team-lead`**](.claude/agents/team-lead.md) | 2 | Orchestrates agent team workers with file ownership and quality gates |
| [**`research-synthesizer`**](.claude/agents/research-synthesizer.md) | 0 | Merges parallel research outputs into unified analysis |

### Review specialists (6)

| Agent | Lens | What it catches |
|---|---|---|
| [**`security-sentinel`**](.claude/agents/security-sentinel.md) | Security | SQL injection, XSS, auth bypass, data exposure, OWASP |
| [**`performance-oracle`**](.claude/agents/performance-oracle.md) | Performance | O(n²) loops, N+1 queries, memory leaks, scalability |
| [**`code-simplicity-reviewer`**](.claude/agents/code-simplicity-reviewer.md) | Complexity | Over-engineering, YAGNI violations, unnecessary abstraction |
| [**`convention-enforcer`**](.claude/agents/convention-enforcer.md) | Conventions | Naming, file organization, code style consistency |
| [**`architecture-strategist`**](.claude/agents/architecture-strategist.md) | Structure | SOLID principles, coupling/cohesion, module boundaries |
| [**`test-gap-analyzer`**](.claude/agents/test-gap-analyzer.md) | Coverage | Untested code paths, missing edge cases, weak assertions |

### Research and verification (6)

| Agent | What it does |
|---|---|
| [**`best-practices-researcher`**](.claude/agents/best-practices-researcher.md) | Industry-wide patterns, anti-patterns, tradeoff analysis |
| [**`framework-docs-researcher`**](.claude/agents/framework-docs-researcher.md) | Current documentation for specific frameworks and libraries |
| [**`git-history-analyzer`**](.claude/agents/git-history-analyzer.md) | Code evolution and architectural decisions via git history |
| [**`bug-reproduction-validator`**](.claude/agents/bug-reproduction-validator.md) | Validates bugs are reproducible before fixes begin |
| [**`deployment-verifier`**](.claude/agents/deployment-verifier.md) | Post-deployment health checks, smoke tests, error monitoring |
| [**`pr-comment-resolver`**](.claude/agents/pr-comment-resolver.md) | Reads GitHub PR review comments and implements changes |

---

## Context management

### Dual-loop context exhaustion recovery

Two defense mechanisms prevent long sprints from dying to context limits:

| Layer | Mechanism | Guards against |
|---|---|---|
| **Inner loop** | [`ship-loop.sh`](.claude/hooks/ship-loop.sh) Stop hook — blocks exit, re-feeds prompt (max 5x) | Claude giving up mid-pipeline |
| **Outer loop** | [`scripts/coordinate.sh`](scripts/coordinate.sh) — spawns fresh sessions with clean context | Context window filling up |
| **Analysis paralysis** | [`context-monitor.sh`](.claude/hooks/context-monitor.sh) — warns at 8+ consecutive reads without writes | Reading without producing |
| **Risk scoring** | Per-subagent risk accumulation — halt at >20% or 50+ file changes | Runaway subagents |

```bash
# Full autonomous sprint with context recovery
./scripts/coordinate.sh "Build the authentication module" --max 5 --convergence deep --team
```

### Key constraints

- `TASKS.md` is never modified directly during review — changes must be proposed in [`MEMORY.md`](ops/MEMORY.md) first
- Neither [Gemini](https://github.com/google-gemini/gemini-cli) nor [Codex](https://github.com/openai/codex) may modify source code; they only write to their designated `ops/` files
- Parallel reviews are safe because agents write to separate files
- Maximum 3 review cycles per sprint before escalating to user
- Phase 0 can be skipped for small bug fixes, same-session continuations, or unchanged codebases (use [`/quick`](.claude/commands/quick.md))
- Completion requires `<promise>DONE</promise>` after [verification checklist](.claude/skills/verification-before-completion/SKILL.md) passes

---

## How it compares

This framework was informed by analyzing the [Claude Code Blueprint](https://github.com/Ninety2UA/claude-code-blueprint) and selectively adopting patterns that complement our heterogeneous multi-model architecture.

| Dimension | [Claude Code Blueprint](https://github.com/Ninety2UA/claude-code-blueprint) | This framework |
|---|---|---|
| **Agent model** | Homogeneous (Claude-only) | Heterogeneous (Claude + Gemini + Codex) |
| **Review agents** | 6 Claude subagents | 8 reviewers (2 external + 6 Claude subagents) |
| **Codebase analysis** | Claude subagent | [Gemini CLI](https://github.com/google-gemini/gemini-cli) (1M token context) |
| **Test execution** | Claude subagent | [Codex CLI](https://github.com/openai/codex) (sandboxed execution) |
| **Coordination** | Native subagents + git | File protocol + bash + subagents + teams |
| **Skills** | Claude-only | Portable across all 3 CLIs via [injection](#portable-skill-injection) |
| **Dependencies** | Zero (markdown only) | Three CLIs (Claude + Gemini + Codex) |

<details>
<summary><strong>What we adopted from Blueprint</strong></summary>

Confidence tiering, suppressions lists, review synthesis, wave orchestration, quality gates, institutional knowledge compounding, dual-loop context management, risk scoring, completion promise pattern, shadow path tracing, session continuity.
</details>

<details>
<summary><strong>What we added beyond Blueprint</strong></summary>

Multi-model coordination, portable skill injection into external agents, agent teams as a build mode, Gemini Phase 0 analysis with 1M token context, Codex sandboxed testing, file-based coordination protocol for cross-model state sharing.
</details>

---

## When NOT to use this framework

| Situation | What to do instead |
|---|---|
| Trivial task (< 30 minutes) | Just use Claude Code directly, or [`/quick`](.claude/commands/quick.md) |
| Pure exploration / brainstorming | Single agent conversation |
| Tight deadline, no tests needed | Claude Code solo, skip review + test |
| Non-code deliverables | [Gemini CLI](https://github.com/google-gemini/gemini-cli) solo with its large context |

---

## FAQ

<details>
<summary><strong>Can I use this with an existing project?</strong></summary>

Yes. Use Option 2 or Option 3 from <a href="#installation">Installation</a> to copy just the components you need. The framework is additive — it doesn't modify your existing code.
</details>

<details>
<summary><strong>Do I need all three CLIs?</strong></summary>

No. The framework degrades gracefully. Without Gemini, Phase 0 is skipped. Without Codex, testing is handled by Claude. You lose the multi-model benefits but everything still works.
</details>

<details>
<summary><strong>Do I need all the skills?</strong></summary>

No. Skills activate contextually. If you never use TDD, the <a href=".claude/skills/test-driven-development/SKILL.md">test-driven-development</a> skill won't activate. You can delete any skill directory you don't want.
</details>

<details>
<summary><strong>How do agents differ from skills?</strong></summary>

<strong>Skills</strong> are instructions that guide an agent's behavior — methodology documents. <strong>Agents</strong> are separate subprocesses dispatched via the Agent tool, each with their own context window. Skills can be injected into any agent (including external ones like Gemini and Codex).
</details>

<details>
<summary><strong>What are Agent Teams?</strong></summary>

<a href=".claude/agents/team-lead.md">Agent Teams</a> spawn multiple Claude Code instances that collaborate through a shared task list and messaging. Unlike review swarms (read-only analysis), Agent Teams are peers that divide file ownership and coordinate builds. Enable with <code>CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"</code> in settings.json.
</details>

<details>
<summary><strong>Do small bug fixes need the full pipeline?</strong></summary>

No. Use <a href=".claude/commands/quick.md"><code>/quick</code></a> for changes touching fewer than 3 files. It skips Phase 0, plan validation, and the full review swarm.
</details>

<details>
<summary><strong>How does context exhaustion recovery work?</strong></summary>

Two layers. <strong>Inside</strong> a session, <a href=".claude/hooks/ship-loop.sh"><code>ship-loop.sh</code></a> blocks premature exit — if Claude tries to stop before completion, the hook re-injects the prompt (max 5 retries). <strong>Outside</strong> a session, <a href="scripts/coordinate.sh"><code>coordinate.sh</code></a> spawns fresh Claude processes with clean 200K context windows, with state persisting via git.
</details>

<details>
<summary><strong>What is knowledge compounding?</strong></summary>

After solving a non-trivial problem, <a href=".claude/commands/compound.md"><code>/compound</code></a> saves it as a structured document in <a href="ops/solutions/"><code>ops/solutions/</code></a>. Future <a href=".claude/commands/plan.md"><code>/plan</code></a> and <a href=".claude/commands/deep-research.md"><code>/deep-research</code></a> commands automatically search this directory before starting new work — so every sprint gets smarter.
</details>

---

## License

MIT

---

<p align="center">
  <sub>Built for teams that believe AI-assisted development should get better with every sprint.</sub>
</p>

<p align="center">
  <a href="docs/multi-agent-framework.md">Full Documentation</a> ·
  <a href="CLAUDE.md">CLAUDE.md</a> ·
  <a href="https://github.com/google-gemini/gemini-cli">Gemini CLI</a> ·
  <a href="https://github.com/openai/codex">Codex CLI</a>
</p>
