# CLAUDE.md

This file provides guidance to Claude Code when working with code in this project. It works with the **Agent Triforge** plugin.

> **Note**: This is the simplified per-project version of the framework's documentation. For the full architecture, security model, agent invocation patterns, version compatibility, and reliability patterns, see the canonical `.claude/CLAUDE.md` in the Agent Triforge plugin repo.

## Project overview

This project uses the multi-agent coordination framework where Claude Code serves as the **lead agent**, orchestrating Antigravity CLI (binary: `agy`), Codex CLI, and specialized Claude subagents through a hybrid file-based + bash-invocation + native-subagent protocol.

## Architecture

### Multi-agent system

- **Claude Code (lead)** — plans work, builds features, coordinates all agents, merges review feedback. Runs Fable 5 at `max` effort when the host has it; otherwise latest Opus at `max`
- **Claude specialized agents** — 19 focused subagents provided by the plugin: plan validation, review synthesis, security, performance, continuous review, etc. Shipped frontmatter floors at `opus`: team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) ship `effort: max`; the other 15 ship `effort: xhigh`. When the plugin's capability probe record shows Fable 5 PASS on the host (row CC-02), the lead spawns team-lead and the trio with a model override to `fable` (the Agent tool's `model` parameter)
- **Claude agent teams** — multi-instance collaboration for complex builds (5+ interdependent tasks)
- **Antigravity CLI (`agy`)** — analyst + reviewer: Phase 0 codebase scans (Gemini 3.1 Pro (High), 1M token context), architecture reviews, documentation
- **Codex CLI** — tester + logic reviewer: writes/runs tests, security audits, infrastructure tasks

**Builder pool.** All six supported CLIs — the core trio (Claude, Antigravity, Codex) plus any enrolled optional member (OpenCode, Kimi, Cursor) — are eligible builders; `ops/roster.toml` assigns each role (builder | reviewer | tester | analyst | documenter). The single-writer rule is retired: safety is per-task leases + worktree isolation + mandatory cross-review by a pinned non-author reviewer, not write-restriction. The role bullets above are the shipped default posture (Claude leads builds, Codex reviews and tests, Antigravity analyzes and documents), which `ops/roster.toml` can override.

For narrow, rubric-following runtime tasks the lead/team-lead may step down one tier at a time:

Downgrade ladder for narrow runtime tasks: `fable`+`max` (lead + never-downgrade tier when available; otherwise latest `opus` at `max` — the model steps down, the effort does not) → `opus` (4.8) + `xhigh` → `opus`+`high` → `sonnet` (5) + `high`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.

Claude invokes Antigravity and Codex through the unified helper `${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh` (which handles model pinning, fail-closed timeout enforcement, failure classification, and native-agent routing with a prompt-prefix injection fallback). Reviews run in parallel (Antigravity + Codex + Claude subagents simultaneously), never sequentially.

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
| `roster.toml` | Role→CLI/model/effort assignment with validated fallback chains | User edits; session-start bootstraps; enrollment appends `[members.*]` |
| `REVIEW_ANTIGRAVITY.md` | Antigravity's review output (temporary) | Antigravity writes, Claude reads |
| `REVIEW_CODEX.md` | Codex's review output (temporary) | Codex writes, Claude reads |
| `RESEARCH_ANTIGRAVITY.md` | Antigravity targeted-research output (temporary) | Antigravity writes, Claude reads |
| `TEST_RESULTS.md` | Test results (temporary) | Codex writes, Claude reads |
| `.sprint-complete` | Runtime completion marker — created only after the verification checklist passes; `scripts/coordinate.sh` detects sprint completion by its existence (gitignored, never committed) | Claude creates at Phase 6 wrap |

### Execution phases

0. **Codebase analysis** — Antigravity scans full repo with codebase-mapping skill
1a. **Pre-plan** — learnings-researcher agent searches institutional knowledge
1b. **Planning** — Claude decomposes goal with shadow path tracing, error maps, interface context extraction
1.1. **Ambiguity resolution** — Validate critical assumptions before building
1.5. **Plan validation** — plan-checker agent validates TASKS.md (max 3 iterations)
2. **Build** — Wave orchestration via subagents (< 5 tasks) or agent teams (5+ tasks)
3. **Parallel review** — Antigravity + Codex + Claude specialized agents simultaneously
4. **Process reviews** — findings-synthesizer agent merges with confidence tiering
5. **Test** — Codex with TDD skill, test-gap-analyzer identifies coverage gaps
6. **Wrap up** — Knowledge compounding, verification checklist, completion sentinel (`ops/.sprint-complete`), session continuity

### Assignment heuristic

Assignment comes from `ops/roster.toml` (`resolve_role <role>`); the defaults below are the shipped posture, not a write-restriction — any roster member can be assigned as builder, and every build merges only after cross-review.

- **Produces code?** → builder role (default Claude; roster-assignable to any member), built under a lease and cross-reviewed before merge
- **Evaluates existing code?** → reviewer role + Claude specialized agents in parallel (default Codex + Antigravity)
- **Runs/executes something?** → tester role (default Codex)
- **Produces documentation?** → documenter role (default Antigravity)
- **Touches shared interfaces?** → builder implements under a lease → pinned non-author reviewer cross-reviews → tester validates

### Key constraints

- CONTRACTS.md is never modified directly during review — changes must be proposed in MEMORY.md first
- Every implementation task — lead-authored included — is built under a per-task lease and merges only after cross-review by a pinned non-author reviewer; no agent self-merges. The single-writer rule is retired — any roster member is an eligible builder; safety is leases + worktree isolation + cross-review, not write-restriction
- Maximum 3 review cycles per task before escalating to user
- Risk scoring: halt subagent at risk >20% or file changes >50
- Completion requires creating the `ops/.sprint-complete` runtime marker, only after the verification checklist passes (never earlier)

### Quality gates

1. Plan validated before build (plan-checker agent)
2. Failing test before implementation (TDD skill)
3. Root cause analysis before fixes (systematic-debugging skill)
4. Verification evidence before completion (verification-before-completion skill)
5. Code review before shipping (parallel review, max 3 cycles)
6. Scope cutting when overwhelmed (scope-cutting skill)

## Reliability patterns

- **Forced reflection on retry** — agents must self-diagnose before retrying failed work
- **Same-error kill criteria** — 3 identical error fingerprints kills the executor and reassigns to a fresh agent
- **Continuous reviewer** — dedicated per-task reviewer in team builds (1:3-4 ratio with builders)
- **Per-task reflection** — automatic MEMORY.md entries when tasks took >3 retries, had test failures, or modified >5 files
- **Provenance tracking** — solutions and decisions include sprint ID, task ID, agent, evidence files, and related decisions

## Context management

- **Completion gating:** sprints are gated by a `/goal` checklist (`scripts/coordinate.sh` leads each session prompt with it; `/ship` and `/coordinate` print a copyable `/goal` line); completion is signaled by creating `ops/.sprint-complete` after the verification checklist passes
- **Outer loop (`/coordinate`):** Spawns fresh sessions on context exhaustion with progress tracking; detects completion via the `ops/.sprint-complete` sentinel
- **Analysis paralysis detection:** Warns at 8+ consecutive reads without writes
- **Risk scoring:** Subagents halted at risk >20% or 50+ file changes

## Portable skills

13 model-agnostic methodology skills available to all agents:

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
| `watch-cycle` | Claude | CLI/repo watch methodology (research → gap table → adopt/defer ADR) |

## Specialized agents

19 agents with restricted tools and focused expertise:

**Core workflow:** plan-checker, findings-synthesizer, integration-verifier, learnings-researcher, team-lead, research-synthesizer, continuous-reviewer

**Review enhancement:** security-sentinel, performance-oracle, code-simplicity-reviewer, convention-enforcer, architecture-strategist, test-gap-analyzer

**Research & verification:** framework-docs-researcher, best-practices-researcher, git-history-analyzer, bug-reproduction-validator, deployment-verifier, pr-comment-resolver

## Agent invocation patterns

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# TMPDIR-scoped, PID+timestamped paths avoid collisions across concurrent runs.
AGY_OUT="${TMPDIR:-/tmp}/antigravity_output_$$_$(date +%s).txt"
CODEX_OUT="${TMPDIR:-/tmp}/codex_output_$$_$(date +%s).txt"

# Antigravity codebase-analyst (runs in background)
invoke_antigravity "codebase-analyst" \
  "Analyze the full codebase. Write findings to ops/ARCHITECTURE.md." \
  "$AGY_OUT" 600 &
AGY_PID=$!

# Codex test_writer (runs in background)
invoke_codex "test_writer" \
  "Write tests for changed files." \
  "$CODEX_OUT" 900 &
CODEX_PID=$!

# Per-PID wait — a silent failure in either helper leaves the downstream
# ops/REVIEW_*.md or ops/TEST_RESULTS.md empty and looks like "no findings".
AGY_RC=0; CODEX_RC=0
wait $AGY_PID || AGY_RC=$?
wait $CODEX_PID  || CODEX_RC=$?
[ $AGY_RC -ne 0 ] || [ $CODEX_RC -ne 0 ] && { echo "helper failed — antigravity=$AGY_RC codex=$CODEX_RC" >&2; exit 1; }
```

The helper auto-detects native agent support. If `agy agents` lists the requested agent (from installed agy plugins), it routes natively via `--agent`; otherwise it injects the agent body from the plugin's `antigravity-agents/agents/` templates as a prompt prefix (the operative mode on agy 1.1.4, which doesn't surface plugin agents headless yet). Codex agents load from `.codex/agents/agents.toml`.

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

**Run `/setup`** — the guided path from a fresh install to a working roster (gates the core trio live, enrolls or declines each optional CLI with a chosen model, then offers role assignment: accept the shipped defaults or customize any role's CLI · model · effort; `/setup roles` jumps straight to that step). Idempotent and re-runnable. The probes below are what it automates.

**Core trio (required)** — installed and answering a headless READY probe:
```bash
claude --version                                                   # Claude Code ≥ 2.1.212
agy --model "Gemini 3.1 Pro (High)" -p "Respond with only: READY"  # Antigravity ≥ 1.1.3 — always pin the model (agy defaults to a Flash variant)
codex exec "Respond with only: READY"                              # Codex ≥ 0.144.0
```

**Optional tier** (enroll via `/setup`; each is skipped cleanly in every roster fallback chain when absent):
```bash
opencode run --format json -m openrouter/z-ai/glm-5.2 "Respond with only: READY"  # OpenCode ≥ 1.18 (OpenRouter provider connected)
kimi -p "Respond with only: READY"                                                # Kimi Code ≥ 0.15 (OAuth device-code or API key)
cursor-agent -p --trust --model grok-4.5 "Respond with only: READY"               # Cursor (date-versioned; pin grok-4.5, never the Auto router)
```

Python 3 is also required (used by hook handlers for JSON parsing):
```bash
python3 --version
```
