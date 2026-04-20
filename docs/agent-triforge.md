# Multi-agent coordination framework: hybrid pattern

> Claude Code as lead agent with native subagents, agent teams, and external agent delegation to Gemini CLI and Codex CLI

---

## Overview

This framework establishes Claude Code as the lead agent in a multi-agent system. Before any planning begins, Gemini CLI performs a Phase 0 codebase analysis -- ingesting the full repository to produce an up-to-date picture of the architecture, patterns, and contracts. Claude Code then plans work, validates the plan, decomposes goals into tasks, assigns agents using a heuristic matrix, executes its own tasks (parallelized via native subagents or agent teams), and delegates review and testing to Gemini CLI, Codex CLI, and specialized Claude subagents. Reviews run in parallel, never sequentially.

The coordination model is hybrid: file-based shared state (TASKS.md, MEMORY.md, CHANGELOG.md, CONTRACTS.md) provides the persistent context layer, while direct bash invocation provides the real-time orchestration layer. Claude Code owns both.

### Agents and their roles

| Agent | Invocation | Strengths | Primary domain |
|---|---|---|---|
| Claude Code (Opus max) | Native (lead agent) | Complex code generation, multi-file refactors, system design, business logic | Feature implementation, API design, database schemas, orchestration |
| Claude Code subagents (Opus max) | Native Agent tool | Parallel isolated tasks within Claude's domain | Splitting large build tasks into parallel tracks |
| Claude Code agent teams (Opus max) | Native team coordination | Multi-instance collaboration with shared task lists | Complex builds with 5+ interdependent tasks |
| Claude specialized agents (Opus max) | Agent tool with agent definitions | Focused expertise (security, performance, plan validation, etc.) | Review enhancement, research, verification |
| Gemini CLI | `gemini -p "..."` via bash, native subagent definitions in `.gemini/agents/` | Large context window (1M tokens), whole-repo analysis, different model perspective, policy-based tool restrictions | Codebase analysis (Phase 0), code review, documentation, architecture audits |
| Codex CLI | `codex exec "..."` via bash, native agent definitions in `.codex/agents/` | Native test runner, subagent parallelism, sandbox execution, per-agent sandbox modes | Testing, infrastructure, deployment, benchmarking, security review |

### Four coordination modes

1. **File-based layer (persistent):** All agents read and write to shared markdown files in `ops/`. This is the source of truth that persists across sessions, provides audit trails, and enables async coordination.

2. **Direct invocation layer (real-time):** Claude Code calls Gemini and Codex via bash within a single session. Output is captured, parsed, and acted on immediately.

3. **Native subagent layer (parallel):** Claude Code uses its own subagent system (Agent tool) to parallelize build work. Each subagent gets an isolated context window and returns results to the lead agent. Specialized agent definitions (`agents/`) provide focused expertise.

4. **Agent team layer (collaborative):** For complex builds, Claude Code spawns agent teams where multiple Claude instances coordinate via shared task lists, direct messaging, and file ownership rules. Each teammate gets an independent context window. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`.

---

## Shared file protocol

All files live in `ops/` at the repo root. Every agent reads all shared files before acting and writes back after completing work.

| File | Purpose | Owner |
|---|---|---|
| `TASKS.md` | Work queue with status tracking (Active/In Progress/Review/Blocked/Done) | Claude generates and maintains |
| `MEMORY.md` | Architectural decisions, patterns, gotchas, interface proposals | All agents append |
| `CHANGELOG.md` | Audit trail with agent attribution | All agents append |
| `CONTRACTS.md` | Shared TypeScript interface definitions — treated as immutable unless change proposed via MEMORY.md | Claude modifies, Gemini discovers |
| `ARCHITECTURE.md` | System design document | Gemini writes during Phase 0 |
| `AGENTS.md` | Master operating protocol read by all agents | Manual |
| `GOALS.md` | High-level product goals | Manual |
| `CONVENTIONS.md` | Code style and standards | Gemini discovers, Claude maintains |
| `STATE.md` | Session continuity — current phase, progress, next actions | Claude writes on pause/wrap |
| `REVIEW_GEMINI.md` | Gemini's review output (temporary) | Gemini writes, Claude reads |
| `REVIEW_CODEX.md` | Codex's review output (temporary) | Codex writes, Claude reads |
| `TEST_RESULTS.md` | Test results (temporary) | Codex writes, Claude reads |
| `solutions/` | Documented solved problems for institutional knowledge | Claude writes via knowledge-compounding skill |
| `decisions/` | Architecture decision records (ADRs) | Claude writes via knowledge-compounding skill |
| `archive/` | Archived review + test files by date | Claude moves during Phase 6 |

### TASKS.md

The work queue. Claude Code generates and maintains this file.

```markdown
# Sprint: [goal name]
<!-- Generated by Claude Code | [ISO timestamp] -->
<!-- Goal source: GOALS.md#[section] -->

## Active
- [ ] T1: [task description] (Agent: Claude | Gemini | Codex)
      Files: [file paths this task touches]
      Depends: [task IDs or "none"]
      Context: [1-3 lines of what the agent needs to know]
      Types: [relevant interfaces from CONTRACTS.md, embedded directly]
      Priority: [P0 critical | P1 high | P2 medium | P3 low]
      Wave: [wave number for parallel grouping]

## In Progress
<!-- Tasks move here when an agent starts working -->
- [-] T1: [task] (Agent: Claude) [Started: timestamp]

## Review
<!-- Tasks waiting for parallel review -->
- [R] T1: [task] (Reviewers: Gemini + Codex) [Submitted: timestamp]

## Blocked
- [B] T5: [task] (Blocked by: T3 -- awaiting architecture decision)

## Done
- [x] T2: [task] (Agent: Claude) [Completed: timestamp]
      Result: [1-line summary of what was delivered]
```

### MEMORY.md

The shared brain. Architectural decisions, design rationale, patterns discovered, gotchas.

```markdown
# Shared memory

## Decisions
- [2026-03-19] Chose BullMQ over custom queue (Claude)
  Reason: Redis-backed, battle-tested, retry support built in.
  Impact: All queue-related code uses BullMQ patterns.

## Patterns
- Rate limiting: Token bucket pattern with Redis counter.
  See src/utils/rate-limiter.ts for reference implementation.

## Gotchas
- Meta Ad Library returns inconsistent date formats.
  Always parse with dayjs, never raw Date constructor.

## Interface proposals
<!-- Agents propose interface changes here before modifying CONTRACTS.md -->
- [PENDING] Proposal: Add `lastScrapedAt` to AdCreative interface (Claude)
  Reason: Need to track staleness for re-scraping logic.
  Affected agents: Codex (test fixtures), Gemini (docs)
```

### CHANGELOG.md

The audit trail. Every significant change gets logged with attribution.

```markdown
# Changelog

## [2026-03-19]

### Claude Code
- Implemented MetaAdLibrary scraper class (T1)
  Files changed: src/scrapers/meta.ts, src/scrapers/types.ts
  Tests needed: Yes (assigned to Codex as T4)

### Gemini CLI
- Reviewed scraper architecture (T3)
  Issues found: 2 (logged as T7, T8 in TASKS.md)
  Docs updated: ops/api/scrapers.md

### Codex CLI
- Wrote 14 integration tests for scraper (T4)
  Coverage: 87% on src/scrapers/meta.ts
  All tests passing.
```

### CONTRACTS.md

Shared interface definitions. Treated as immutable by all agents unless a change is proposed through MEMORY.md and approved.

```markdown
# Interface contracts

## AdCreative
\`\`\`typescript
interface AdCreative {
  id: string;
  platform: 'meta' | 'google' | 'tiktok';
  advertiserId: string;
  creativeUrl: string;
  firstSeen: string;       // ISO 8601
  lastSeen: string;        // ISO 8601
  spendEstimate?: number;  // USD cents
  impressionEstimate?: number;
  metadata: Record<string, unknown>;
}
\`\`\`

<!-- Add new interfaces below. All agents must conform to these types. -->
<!-- To propose a change, write to MEMORY.md#Interface proposals first. -->
```

### STATE.md

Session continuity file. Written when pausing or wrapping a session.

```markdown
# Session state
<!-- Saved: [ISO timestamp] -->

## Current phase
[Phase 0-6 — which phase was active when session paused]

## Active sprint
[Goal being worked on]

## Task status snapshot
[Copy current TASKS.md status section — what's done, in progress, blocked]

## In-progress work
- [What was being worked on when session paused]
- [File paths with uncommitted changes]
- [Branch name if applicable]

## Context
- [Key decisions made this session]
- [Blockers encountered]
- [Pending questions for user]

## Review cycle state
- Cycle: [N of 3]
- Convergence mode: [fast | standard | deep]
- Outstanding issues: [count by priority]

## Next actions
1. [First thing to do when resuming]
2. [Second thing]
3. [Third thing]
```

---

## Portable skill protocol

Skills are model-agnostic markdown files that encode reusable methodologies. They live in `skills/` and can be consumed by ALL agents:

- **Claude Code:** Uses skills natively via the skill system
- **Gemini CLI:** Skills embedded in native agent definitions (`gemini-agents/*.md`). The `invoke-external.sh` helper handles feature detection and falls back to prompt injection for older CLI versions.
- **Codex CLI:** Skills embedded in native agent definitions (`codex-agents/agents.toml` as `developer_instructions`). The `invoke-external.sh` helper handles feature detection and falls back to prompt injection for older CLI versions.
- **Legacy mode (fallback):** Skills injected via prompt: `gemini -p "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/SKILL_NAME/SKILL.md) Now apply..."`

### Available skills and their primary consumers

| Skill | Primary consumer | Phase | Purpose |
|---|---|---|---|
| `codebase-mapping` | Gemini | Phase 0 | Systematic full-repo analysis methodology |
| `writing-plans` | Claude | Phase 1 | Task decomposition with shadow paths and error maps |
| `shadow-path-tracing` | Claude | Phase 1 | Enumerate failure paths alongside happy paths |
| `wave-orchestration` | Claude | Phase 2 | Dependency-grouped parallel execution |
| `test-driven-development` | Codex | Phase 2, 5 | RED-GREEN-REFACTOR cycle |
| `iterative-refinement` | Claude | Phase 4 | Review-fix-review loop with convergence modes |
| `review-synthesis` | Claude | Phase 4 | Merge and deduplicate multi-reviewer findings |
| `systematic-debugging` | Codex, Claude | Any | Structured debugging with error taxonomy |
| `verification-before-completion` | All | Phase 6 | Evidence-based completion checklist |
| `knowledge-compounding` | Claude | Phase 6 | Document solutions and decisions for future sprints |
| `session-continuity` | Claude | Any | Save and resume work across sessions |
| `scope-cutting` | Claude | Any | Systematically cut scope when overwhelmed |

### External agent definitions

Skills consumed by Gemini and Codex are embedded in their native agent definitions, loaded automatically at session start:

| Agent definition | CLI | Embedded skill | Role |
|---|---|---|---|
| `gemini-agents/codebase-analyst.md` | Gemini | `codebase-mapping` | Phase 0 full-repo analysis |
| `gemini-agents/architecture-reviewer.md` | Gemini | (inline review protocol) | Phase 3 architecture review |
| `gemini-agents/targeted-researcher.md` | Gemini | `codebase-mapping` (subset) | Deep-research targeted analysis |
| `gemini-agents/documentation-writer.md` | Gemini | (inline docs protocol) | Documentation generation |
| `codex-agents/agents.toml → logic_reviewer` | Codex | (inline review protocol) | Phase 3 logic + security review |
| `codex-agents/agents.toml → test_writer` | Codex | `test-driven-development` | Phase 5 TDD test writing |
| `codex-agents/agents.toml → debugger` | Codex | `systematic-debugging` | Bug investigation |

### Invocation via invoke-external.sh

The shared helper `scripts/invoke-external.sh` provides unified invocation with feature detection:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Gemini Phase 0 with codebase-analyst agent
invoke_gemini "codebase-analyst" \
  "Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append)." \
  "${TMPDIR:-/tmp}/gemini_phase0_$$_$(date +%s).txt" 600

# Codex testing with test_writer agent
invoke_codex "test_writer" \
  "Test scope: changed files from ops/TASKS.md. Write results to ops/TEST_RESULTS.md." \
  "${TMPDIR:-/tmp}/codex_test_$$_$(date +%s).txt" 900

# Codex bug investigation with debugger agent
invoke_codex "debugger" \
  "Investigate the bug: [description]. Follow the diagnostic protocol. Write findings to ops/REVIEW_CODEX.md." \
  "${TMPDIR:-/tmp}/codex_debug_$$_$(date +%s).txt" 600
```

**How `invoke_gemini` works:** If `.gemini/agents/<name>.md` exists in the CWD, uses Gemini's `@<name>` mention syntax for native subagent routing. Otherwise falls back to extracting the plugin template's body and injecting it as a prompt prefix. Automatically passes `--policy .gemini/policies.toml` (or the plugin template policy) because Gemini only auto-discovers policies from `~/.gemini/policies/*.toml` (user tier), not the project tier. Retries once with a simplified prompt on failure. Each call logs `mode=native|legacy-injection|raw` and the resolved policy path to stderr.

**How `invoke_codex` works:** Codex has no CLI flag to select a subagent — upstream "subagents" only spawn from within a running Codex session. The helper simulates agent selection by extracting the agent's config from `agents.toml` and passing it as `-m` (model), `-s` (sandbox), `-c approval_policy=` overrides, with `developer_instructions` injected as prompt prefix. Lookup order: project `.codex/agents/agents.toml` first, then plugin template.

### Debugging the subagent layer

- **Gemini:** `gemini agents list` / `gemini agents` — inspect loaded subagent definitions. `gemini -p "@<name> say hi"` is the minimal smoke test for native routing. Check `--policy` is honored via `gemini --policy path/to/policies.toml ...`.
- **Codex:** In an interactive session, `/agent` switches between active agent threads and inspects ongoing ones. In non-interactive mode (`codex exec`), inspect the session transcript captured by `invoke_codex`'s output file.

### Hard constraint: Gemini subagents cannot nest

Per the Gemini CLI docs: *"Subagents cannot call other subagents. If a subagent is granted the `*` tool wildcard, it will still be unable to see or invoke other agents."* Our architecture complies because Claude (the lead) is the only agent that spawns Gemini subagents; no Gemini agent tries to fan out to other Gemini agents. If you need parallel Gemini work, launch multiple top-level `invoke_gemini` calls from Claude's shell in the background (as `/review` already does).

### Why portable skills/hooks instead of Gemini's native subsystems

Gemini CLI ships native `gemini skills {list,install,enable,disable,link,uninstall}` and `gemini hooks {migrate,...}` subsystems. We deliberately do **not** use them:

- **Skills:** Our 12 portable skills in `skills/` are markdown files consumed by all three agents (Claude/Gemini/Codex) via prompt-prefix injection or native definition embedding. Adopting Gemini's native `skills install` registry would make each skill Gemini-specific and fragment the portability story. Revisit only if we need agent-installable skills distributed via git.
- **Hooks:** Our `hooks/handlers/*.sh` are Claude Code lifecycle hooks (SessionStart, Stop, PostToolUse, etc.). Gemini's hooks cover Gemini CLI's own lifecycle, which is a subprocess of a Claude Code session — different layer, different events. `gemini hooks migrate` is one-way (Claude Code → Gemini) and assumes the target environment is Gemini-first, not Claude-first.

---

## Specialized agent definitions

Specialized agents live in `agents/` and provide focused expertise as Claude subagents. They have restricted tool access and preloaded context for their domain.

### Core workflow agents

| Agent | Purpose | Phase | Tools |
|---|---|---|---|
| `plan-checker` | Validates task plans for completeness and feasibility | Phase 1.5 | Read, Grep, Glob |
| `findings-synthesizer` | Merges and deduplicates multi-reviewer findings | Phase 4 | Read, Grep, Glob |
| `integration-verifier` | Checks build/test/lint between waves | Phase 2 | Read, Grep, Glob, Bash |
| `learnings-researcher` | Searches institutional knowledge before planning | Pre-Phase 1 | Read, Grep, Glob |
| `team-lead` | Orchestrates agent team workers for complex builds | Phase 2 | Read, Grep, Glob, Bash |
| `research-synthesizer` | Merges parallel research into unified analysis | Phase 0 | Read, Grep, Glob |

### Review enhancement agents (Claude's review swarm)

These agents run alongside Gemini and Codex to add review depth:

| Agent | Focus | Complements |
|---|---|---|
| `security-sentinel` | OWASP Top 10, injection, auth/authz, data exposure | Codex security review |
| `performance-oracle` | O(n²), N+1 queries, memory leaks, scalability | Neither Gemini nor Codex focuses deeply on this |
| `code-simplicity-reviewer` | Over-engineering, YAGNI, unnecessary abstractions | Gemini readability review |
| `convention-enforcer` | Project-specific naming, structure, patterns | Both reviewers' style checks |
| `test-gap-analyzer` | Untested code paths, missing edge cases | Codex test coverage |

### Research agents

| Agent | Purpose | When to use |
|---|---|---|
| `framework-docs-researcher` | Fetches current docs for frameworks/libraries | Encountering unfamiliar tech |
| `git-history-analyzer` | Traces code evolution via git history | Refactoring, understanding legacy code |
| `bug-reproduction-validator` | Validates bugs are reproducible before fixing | Receiving bug reports |

### Agent invocation examples

```bash
# Plan validation (Claude subagent)
# Spawned automatically in Phase 1.5 — reads TASKS.md, ARCHITECTURE.md, CONTRACTS.md
# Returns: APPROVED or NEEDS_REVISION with specific issues

# Security review (Claude subagent, parallel with Gemini/Codex)
# Add to Phase 3 review alongside external agents for deeper security analysis

# Bug investigation (Claude subagent)
# Spawn before fixing: validates bug is real, identifies root cause
```

---

## Quality gates

Five non-negotiable checkpoints enforced at every stage:

| # | Gate | Phase | Enforcement |
|---|---|---|---|
| 1 | Plan validated before build | Phase 1.5 | plan-checker agent reviews TASKS.md, max 3 iterations |
| 2 | Failing test before implementation (TDD) | Phase 2 | test-driven-development skill injected into build tasks |
| 3 | Root cause analysis before fixes | Any | systematic-debugging skill requires diagnosis before implementation |
| 4 | Verification evidence before completion | Phase 6 | verification-before-completion skill requires checklist |
| 5 | Code review before shipping | Phase 3-4 | Parallel review (Gemini + Codex + Claude subagents), max 3 cycles |

---

## Agent-specific protocol files

### AGENTS.md

The master operating protocol. All agents read this.

```markdown
# Multi-agent operating protocol

## Agents in this repo
1. Claude Code (lead) -- reads CLAUDE.md for specific instructions
2. Gemini CLI -- reads the GEMINI.md protocol embedded in docs/agent-triforge.md for specific instructions
3. Codex CLI -- reads the CODEX.md protocol embedded in docs/agent-triforge.md for specific instructions

## Shared rules
- Before acting: read TASKS.md, MEMORY.md, CHANGELOG.md, CONTRACTS.md
- After acting: update CHANGELOG.md with agent name, timestamp, changes
- Never modify files outside your assigned scope without proposing in MEMORY.md
- Never modify CONTRACTS.md directly -- propose changes in MEMORY.md first
- If you discover a conflict with another agent's work, log it in TASKS.md
- All code must conform to type definitions in CONTRACTS.md
- Attribution is mandatory on every change
```

### CLAUDE.md (lead agent protocol)

```markdown
# Claude Code operating protocol

You are the lead agent in a multi-agent repository. You have three responsibilities:
1. Build features (your primary strength)
2. Coordinate the other agents (Gemini CLI and Codex CLI)
3. Manage specialized subagents and agent teams for complex work

## Phase 0: Codebase analysis (Gemini CLI)

Before planning any work, invoke Gemini CLI with the `codebase-analyst` agent definition to perform a full codebase scan. The agent definition embeds the codebase-mapping methodology and the ops/ file protocol.

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Full codebase analysis (uses codebase-analyst agent definition)
invoke_gemini "codebase-analyst" \
  "Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append)." \
  "${TMPDIR:-/tmp}/gemini_phase0_$$_$(date +%s).txt" 600
```

For parallel fan-out (optional, for large codebases), launch a second Gemini process with a targeted researcher:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Parallel: structural analysis + targeted risk analysis
invoke_gemini "codebase-analyst" \
  "Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append)." \
  "${TMPDIR:-/tmp}/gemini_structure_$$_$(date +%s).txt" 600 &
PID1=$!

invoke_gemini "targeted-researcher" \
  "Analyze dependencies, risks, and technical debt related to: [goal]." \
  "${TMPDIR:-/tmp}/gemini_risks_$$_$(date +%s).txt" 600 &
PID2=$!

wait $PID1 $PID2
```

After Phase 0 completes, read the updated ops/ files. Optionally run the research-synthesizer agent to merge findings if multiple research sources were consulted.

Skip Phase 0 when:
- The codebase has not changed since the last sprint
- You are continuing work within the same session (read STATE.md instead)
- The task is a small bug fix where full analysis is unnecessary

## Pre-planning: Search institutional knowledge

Before planning, run the learnings-researcher agent to search ops/solutions/ and ops/decisions/ for relevant past patterns:

```
Spawn learnings-researcher agent with:
"Search institutional knowledge for patterns relevant to: [goal description]"
```

This prevents re-investigating known issues and repeating rejected approaches.

## Phase 1: Planning

When given a high-level goal:

1. Read these files in order: GOALS.md, ARCHITECTURE.md, CONTRACTS.md, MEMORY.md, TASKS.md
2. Read the learnings-researcher output (if available)
3. Decompose the goal into atomic tasks (each task = 1-2 hours of focused work)
4. Assign each task using the assignment heuristic below
5. **Apply shadow path tracing:** For each non-trivial task, enumerate failure paths (see shadow-path-tracing skill)
6. **Build error/rescue maps:** For tasks with external calls or DB operations, create failure mode tables
7. **Extract interface context:** Embed relevant CONTRACTS.md types directly in task descriptions
8. **Group tasks into waves:** Identify which tasks can run in parallel (see wave-orchestration skill)
9. Write the full task list to ops/TASKS.md

## Phase 1.5: Plan validation

Before building, validate the plan:

1. Spawn the plan-checker agent
2. The plan-checker reviews TASKS.md against ARCHITECTURE.md, CONTRACTS.md, and MEMORY.md
3. If issues found: fix and re-submit (max 3 iterations)
4. Only proceed to Phase 2 when plan-checker returns APPROVED

## Assignment heuristic

Use this matrix to assign tasks. YOU make the assignment decision for every task.

### Quick reference

- **Produces code?** → Claude (subagents or agent team for parallel work)
- **Evaluates existing code?** → Gemini + Codex + Claude specialized agents in parallel
- **Runs/executes something?** → Codex
- **Produces documentation?** → Gemini
- **Touches shared interfaces?** → Claude implements → Gemini reviews → Codex tests
- **Ambiguous?** → Claude takes it, flags for parallel review
- **Cross-cutting (all domains)?** → Claude leads, subagents for build, then parallel review + test

### Codebase analysis tasks (assign to Gemini CLI -- Phase 0)

| Task type | Why Gemini | Notes |
|---|---|---|
| Full codebase scan | 1M token context window ingests entire repo | Run before planning phase |
| Architecture mapping | Can analyze all modules and their relationships at once | Writes to ARCHITECTURE.md |
| Pattern discovery | Identifies conventions across the full codebase | Updates MEMORY.md#Patterns |
| Technical debt inventory | Spots inconsistencies by seeing the whole picture | Logs to MEMORY.md#Gotchas |
| Interface extraction | Finds undocumented types, schemas, API shapes | Updates CONTRACTS.md |
| Dependency graph analysis | Can trace imports and relationships across all files | Informs task decomposition |
| Convention audit | Detects naming, structure, and style patterns in use | Updates CONVENTIONS.md |

### Build tasks (assign to Claude Code)

| Task type | Why Claude | Notes |
|---|---|---|
| Feature implementation | Best code generation quality | Use subagents/teams to parallelize independent features |
| API route design + implementation | Strong at system design patterns | Write CONTRACTS.md entry first, then implement |
| Database schema design | Understands data modeling deeply | Update CONTRACTS.md with schema types |
| Business logic | Handles complex conditional logic well | Include edge cases in CHANGELOG entry |
| State management | Good at data flow architecture | Document state shape in MEMORY.md |
| Authentication / authorization | Security-sensitive, needs careful logic | Flag for security-sentinel review after |
| Data transformation / ETL | Strong at pipeline logic | Write types in CONTRACTS.md first |
| Error handling + recovery | Good at anticipating failure modes | Document retry strategies in MEMORY.md |
| Refactoring | Understands intent behind code | Always trigger review after refactoring |
| Bug fixes | Has implementation context | Run bug-reproduction-validator first, log root cause in MEMORY.md |
| Performance optimization | Can reason about algorithmic complexity | Run performance-oracle review after |
| Third-party API integration | Good at reading API docs and adapting | Run framework-docs-researcher first |
| Configuration management | Understands environment patterns | Update CONTRACTS.md with config shapes |
| Migration scripts | Can reason about data state transitions | Flag for Codex to test migration rollback |

### Review tasks (assign to Gemini CLI + Codex CLI + Claude agents in parallel)

| Task type | Gemini's focus | Codex's focus | Claude agents |
|---|---|---|---|
| Code review | Architecture alignment, design patterns, readability | Logic correctness, edge cases, error handling | security-sentinel, performance-oracle, code-simplicity-reviewer |
| Security review | Compliance, data exposure, auth bypass vectors | Injection vulnerabilities, input validation, dependency audit | security-sentinel (deep OWASP analysis) |
| Architecture audit | System-level coherence, coupling, scaling | Concrete performance implications, resource usage | performance-oracle, convention-enforcer |
| API review | REST/GraphQL conventions, documentation gaps | Contract conformance, error response shapes | convention-enforcer |
| Schema review | Normalization, relationship modeling, migration safety | Index coverage, query performance, constraints | test-gap-analyzer |

### Test tasks (assign to Codex CLI)

| Task type | Why Codex | Notes |
|---|---|---|
| Unit tests | Native test runner, sandbox execution | Must conform to CONTRACTS.md types |
| Integration tests | Can run actual services in sandbox | Mock external APIs, test real DB |
| E2E tests | Playwright/Cypress execution support | Run in isolated Codex sandbox |
| Performance benchmarks | Can measure and report metrics | Log baseline numbers in MEMORY.md |
| Load testing | Can spawn parallel workers | Use Codex subagents for parallel load |
| Regression tests | Systematic coverage checking | Run full suite, report deltas |
| Test fixture generation | Can generate realistic mock data | Must match CONTRACTS.md interfaces |

### Infrastructure tasks (assign to Codex CLI)

| Task type | Why Codex | Notes |
|---|---|---|
| CI/CD pipeline setup | Native GitHub Actions support | Test pipeline locally before push |
| Docker configuration | Sandbox execution for validation | Build + run in Codex sandbox |
| Deployment scripts | Can validate in isolated environment | Document deploy steps in MEMORY.md |
| Environment configuration | Good at config file generation | Update CONTRACTS.md with env var shapes |
| Dependency management | Can run audit + update safely | Log breaking changes in CHANGELOG |

### Documentation tasks (assign to Gemini CLI)

| Task type | Why Gemini | Notes |
|---|---|---|
| API documentation | Large context for full-repo coherence | Cross-reference with CONTRACTS.md |
| Architecture docs | Can ingest entire codebase at once | Update ARCHITECTURE.md directly |
| README updates | Understands project-level narrative | Keep consistent with MEMORY.md |
| Onboarding guides | Fresh perspective on code readability | Test instructions against actual setup |
| Technical decision records | Good at articulating tradeoffs | Add to ops/decisions/ |

```

### GEMINI.md (reviewer protocol)

```markdown
# Gemini CLI operating protocol

You are a codebase analyst, reviewer, and documentation specialist in a multi-agent repository.

## Before every task
1. Read ops/TASKS.md -- find tasks assigned to you
2. Read ops/MEMORY.md -- understand recent decisions
3. Read ops/CHANGELOG.md -- understand what changed
4. Read ops/CONTRACTS.md -- understand interface specs
5. Read ops/ARCHITECTURE.md -- understand system design

## Review output format

Use confidence tiering and severity levels in all findings:

### Confidence tiers
- [HIGH] — Verified in codebase (deterministic, confirmed via reading the code)
- [MEDIUM] — Pattern-aggregated detection (likely but not certain)
- [LOW] — Requires intent verification (heuristic, subjective)

Rule: [LOW] confidence findings can NEVER be Priority 1/Critical.

### Severity levels
- P1 Critical: Security vulnerability, data loss, crash, broken core flow
- P2 Important: Performance at scale, missing error handling, design flaws
- P3 Suggestion: Style, naming, documentation, minor optimization

### Do NOT flag (suppressions)
- Redundancy that aids readability (explicit type annotations where inference works)
- Documented threshold values with clear context comments
- Sufficient test assertions (behavior is covered)
- Consistency-only style changes (project convention already applied)
- Issues already addressed in the current diff
- Harmless no-ops

## Output format

Write findings to ops/REVIEW_GEMINI.md:

## Review: [task ID]
### Status: APPROVED | CHANGES_REQUESTED | BLOCKED
### Issues
- [confidence] [severity] [file:line] Description
### Suggestions
- [file] Suggestion description
### Documentation gaps
- [topic] What needs to be documented

## Rules
- Never modify source code directly
- Never modify CONTRACTS.md during review (propose changes in MEMORY.md)
- Log issues as new tasks in TASKS.md with "Agent: Claude" assignment
- Be specific: include file paths and line numbers
```

### CODEX.md (tester + logic reviewer protocol)

```markdown
# Codex CLI operating protocol

You are a tester, logic reviewer, and infrastructure specialist in a multi-agent repository.

## Before every task
1. Read ops/TASKS.md -- find tasks assigned to you
2. Read ops/CONTRACTS.md -- your tests MUST conform to these interfaces
3. Read ops/CHANGELOG.md -- understand what changed
4. Read ops/MEMORY.md -- understand decisions and gotchas

## Review output format

Use confidence tiering and severity levels in all findings:

### Confidence tiers
- [HIGH] — Verified (deterministic, confirmed via test or code reading)
- [MEDIUM] — Pattern match (likely but not certain)
- [LOW] — Heuristic (requires intent verification)

Rule: [LOW] confidence findings can NEVER be Priority 1/Critical.

### Severity levels
- P1 Critical: Security vulnerability, logic error causing wrong output, data loss
- P2 Important: Missing error handling, untested edge cases, type safety gaps
- P3 Suggestion: Style, minor optimization, documentation

### Do NOT flag (suppressions)
- Test fixtures with hardcoded values (normal for tests)
- Readability-aiding redundancy
- Development-only configuration properly gated
- Sufficient test assertions for the behavior being tested
- Already-addressed issues in the diff

## Review output format

Write findings to ops/REVIEW_CODEX.md:

## Review: [task ID]
### Status: APPROVED | CHANGES_REQUESTED | BLOCKED
### Test results
- Total: N | Passing: N | Failing: N | Coverage: N%
### Logic issues
- [confidence] [severity] [file:line] Description
### Security concerns
- [confidence] [severity] [file:line] Description
### Missing test coverage
- [function/module] What needs testing

## Rules
- Never modify source code (only test code and infra configs)
- Never modify CONTRACTS.md directly (propose changes in MEMORY.md)
- Log code issues as new tasks in TASKS.md with "Agent: Claude" assignment
```

---

## Execution phases

The full lifecycle for a goal follows these phases:

```
Phase 0:   Codebase analysis (Gemini with codebase-mapping skill)
Pre-Plan:  Search institutional knowledge (learnings-researcher agent)
Phase 1:   Planning with shadow paths and interface context (writing-plans skill)
Phase 1.5: Plan validation (plan-checker agent)
Phase 2:   Build — subagent mode OR agent team mode with wave orchestration
Phase 3:   Parallel review — Gemini + Codex + Claude specialized agents
Phase 4:   Process reviews — findings-synthesizer agent, iterative-refinement skill
Phase 5:   Test — Codex with TDD skill, test-gap-analyzer agent
Phase 6:   Wrap up — knowledge compounding, session continuity, completion promise
```

### Phase 0: Invoke Gemini for codebase analysis

Before planning, invoke Gemini CLI with the codebase-mapping skill to scan the full codebase (see CLAUDE.md protocol above). Read the updated ARCHITECTURE.md, MEMORY.md, and CONTRACTS.md before proceeding.

Skip Phase 0 when:
- The codebase has not changed since the last sprint
- You are continuing work within the same session (resume from STATE.md)
- The task is a small bug fix

### Pre-planning: Search institutional knowledge

Spawn the learnings-researcher agent to search ops/solutions/ and ops/decisions/ for relevant past patterns. This prevents re-investigating known issues and repeating rejected approaches.

### Phase 1: Planning with shadow paths

When given a high-level goal, follow the writing-plans skill:

1. Read GOALS.md, ARCHITECTURE.md, CONTRACTS.md, MEMORY.md, TASKS.md, and learnings-researcher output
2. Decompose the goal into atomic tasks (each task = 1-2 hours of focused work)
3. Assign each task using the assignment heuristic
4. **Shadow path tracing:** For each non-trivial task, enumerate failure paths alongside the happy path (see shadow-path-tracing skill)
5. **Error/rescue maps:** For tasks with external calls or DB ops, create failure mode tables. Any "?" handling status → subtask
6. **Interface context extraction:** Embed relevant CONTRACTS.md types directly in each task's Context field
7. **Wave grouping:** Group tasks into waves for parallel execution
8. Identify dependency chains and mark blocked tasks
9. Write the full task list to ops/TASKS.md

### Phase 1.5: Plan validation

Before building:

1. Spawn the plan-checker agent
2. It reviews TASKS.md against ARCHITECTURE.md, CONTRACTS.md, MEMORY.md
3. Checks: task completeness, assignment correctness, dependency validity, scope, shadow path coverage
4. If NEEDS_REVISION: fix issues and re-submit (max 3 iterations)
5. Only proceed to Phase 2 when plan-checker returns APPROVED

### Phase 2: Build (wave orchestration)

Execute build tasks using wave orchestration (see wave-orchestration skill).

#### Choosing the build mode

| Condition | Mode | How |
|---|---|---|
| < 5 independent tasks | Subagent mode | Each task dispatched as native Claude subagent |
| 5+ tasks or interdependent | Agent team mode | Spawn agent team with team-lead orchestrating |
| Tasks share no files | Either | Subagent mode is lighter weight |
| Tasks require cross-communication | Agent team mode | Teammates can message each other |

#### Subagent mode (default)

```
Wave 1: Dispatch parallel subagents → collect results → integration-verifier
Wave 2: Dispatch parallel subagents → collect results → integration-verifier
...
Final: Full test suite + build + lint
```

Each subagent receives:
- Task description from TASKS.md
- Relevant types from CONTRACTS.md (embedded, not referenced)
- Skill injection if applicable (e.g., test-driven-development skill)
- Risk scoring rules: halt at risk >20% or file changes >50

#### Agent team mode (complex builds)

```
1. Spawn team-lead agent
2. Team-lead reads plan, groups tasks into work streams
3. Team-lead assigns teammates with explicit file ownership
4. Teammates coordinate via shared task list + messaging
5. Quality gates: TaskCompleted hook verifies tests/lint before accepting
6. Integration-verifier runs between waves
7. Teammates can invoke gemini/codex themselves for review/testing
```

Invoke Gemini/Codex from within a teammate:
```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Teammate invoking Gemini for a specific review
invoke_gemini "architecture-reviewer" \
  "Review the auth module changes in src/auth/. Write to ops/REVIEW_GEMINI.md." \
  "${TMPDIR:-/tmp}/gemini_build_$$_$(date +%s).txt" 600 &

# Teammate invoking Codex for testing
invoke_codex "test_writer" \
  "Write tests for src/auth/login.ts." \
  "${TMPDIR:-/tmp}/codex_build_$$_$(date +%s).txt" 600 &

wait
```

#### Risk scoring during execution

Track risk accumulation per subagent/teammate:

| Signal | Risk increment |
|---|---|
| Revert of own changes | +15% |
| Each file modified beyond task scope | +20% |
| Each multi-file change | +5% |
| 8+ consecutive read-only ops without code changes | Flag analysis paralysis |

**Circuit breaker:** Halt subagent when risk > 20% or file changes > 50. Escalate to lead.

After each task: update CHANGELOG.md, move task to "Done" in TASKS.md.

### Phase 3: Parallel review

After completing build tasks, invoke all reviewers in parallel.

CRITICAL: All reviewers run simultaneously, not sequentially.

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# === External reviewers (background processes) ===

# Gemini architecture review (uses architecture-reviewer agent definition)
invoke_gemini "architecture-reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. Write findings to ops/REVIEW_GEMINI.md." \
  "${TMPDIR:-/tmp}/gemini_review_$$_$(date +%s).txt" 600 &
GEMINI_PID=$!

# Codex logic + security review (uses logic_reviewer agent definition)
invoke_codex "logic_reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. Write findings to ops/REVIEW_CODEX.md." \
  "${TMPDIR:-/tmp}/codex_review_$$_$(date +%s).txt" 600 &
CODEX_PID=$!

# === Claude specialized reviewers (subagents, parallel) ===
# Spawn in a single message for maximum parallelism:
# - security-sentinel agent → deep OWASP analysis
# - performance-oracle agent → algorithmic complexity, N+1, scalability
# - code-simplicity-reviewer agent → over-engineering, YAGNI

# Wait for all external reviewers
wait $GEMINI_PID $CODEX_PID
```

The review protocol (confidence tiering, suppression rules, output format) is embedded in each agent definition rather than repeated inline. The `invoke-external.sh` helper handles feature detection and fallback to legacy prompt injection.

### Phase 4: Process parallel review results (review synthesis)

After all reviews complete, use the review-synthesis skill and findings-synthesizer agent:

1. Spawn the findings-synthesizer agent
2. It reads REVIEW_GEMINI.md, REVIEW_CODEX.md, and subagent review outputs
3. It produces a synthesized report with:
   - Deduplicated findings with confidence tiering
   - Priority ranking (P1/P2/P3)
   - Suppressed false positives
   - Flagged contradictions
4. Apply the iterative-refinement skill for the fix cycle:
   - **Fix P1 (Critical):** Immediately, block ship
   - **Fix P2 (Important):** This cycle
   - **Log P3 (Suggestion):** For later or fix if trivial
5. If fixes are substantial, re-trigger parallel review on changed files only (loop)
6. **Convergence check:**
   - Fast mode: P1 = 0 → proceed
   - Standard mode: P1 = 0 AND P2 = 0 → proceed (default)
   - Deep mode: P1 = 0 AND P2 = 0 AND P3 < 3 → proceed
7. Maximum 3 review-fix cycles. After 3 cycles, escalate to user with remaining issues.

### Phase 5: Test

After reviews converge:

1. Optionally spawn test-gap-analyzer to identify coverage gaps before writing tests
2. Invoke Codex with the `test_writer` agent definition:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# TDD test writing (uses test_writer agent definition, 15 min timeout for TDD cycles)
invoke_codex "test_writer" \
  "Test scope: changed files from ops/TASKS.md and ops/CHANGELOG.md. Write results to ops/TEST_RESULTS.md." \
  "${TMPDIR:-/tmp}/codex_test_$$_$(date +%s).txt" 900
```

The TDD methodology (RED-GREEN-REFACTOR), ops/ file protocol, and coverage targets are embedded in the `test_writer` agent's `developer_instructions`.

3. Read TEST_RESULTS.md
4. If tests pass: proceed to Phase 6
5. If tests fail: fix underlying code, re-run via Codex, loop until green

### Phase 6: Wrap up (knowledge compounding + completion)

1. **Knowledge compounding** (knowledge-compounding skill):
   - If any non-trivial problem was solved, document it in ops/solutions/YYYY-MM-DD-slug.md
   - If any architectural decision was made, document it in ops/decisions/YYYY-MM-DD-slug.md
2. Update CHANGELOG.md with final summary
3. Update MEMORY.md with any new decisions, patterns, or gotchas discovered
4. Move all completed tasks to "Done" in TASKS.md
5. Archive temporary files (REVIEW_GEMINI.md, REVIEW_CODEX.md, TEST_RESULTS.md) to ops/archive/[date]/
6. **Verification checklist** (verification-before-completion skill):
   - All tasks marked done
   - All tests passing
   - All critical/major issues resolved
   - CHANGELOG updated
   - MEMORY.md updated
7. **Completion signal:** Only after ALL checks pass:
   ```
   <promise>DONE</promise>
   ```
8. **Session continuity** (session-continuity skill):
   - If more work remains: write STATE.md with current progress and next actions
   - If sprint complete: write STATE.md as clean handoff for next sprint
   - Sprint summary for user

---

## Context management

### Dual-loop context exhaustion recovery

Two defense mechanisms prevent context exhaustion from killing a sprint:

#### Inner loop (Stop hook)

The `ship-loop.sh` Stop hook prevents premature session exit during active sprints:
- Blocks exit until `<promise>DONE</promise>` signal is emitted
- Re-feeds the task prompt up to 5 iterations
- Session-isolated (only blocks the session that started the loop)
- State tracked in `.claude/ship-loop.local.md`

To activate:
```bash
# Write the ship-loop state file to activate the inner loop
cat > .claude/ship-loop.local.md << EOF
---
iteration: 0
max_iterations: 5
---
[Sprint goal and context here]
EOF
```

#### Outer loop (coordinate script)

The `scripts/coordinate.sh` script spawns fresh Claude Code sessions when context is truly exhausted:
- Each iteration gets a clean context window
- Progress tracked in ops/STATE.md
- Supports flags: `--max N`, `--convergence`, `--team`

```bash
# Full autonomous sprint with context recovery
./scripts/coordinate.sh "Build the authentication module" --max 5 --convergence standard

# Complex build with agent teams
./scripts/coordinate.sh "Build the dashboard" --team --convergence deep
```

### Analysis paralysis detection

The `context-monitor.sh` PostToolUse hook detects:
- **8+ consecutive read-only operations** without code changes → warns agent to write code or report blocker
- **150+ total tool calls** → suggests spawning subagents
- **200+ total tool calls** → critical warning, strongly suggests saving state and wrapping session

### WTF-likelihood risk scoring

Quantitative circuit breaker for subagents and teammates:

| Signal | Risk increment | Rationale |
|---|---|---|
| Revert of own changes | +15% | Thrashing indicator |
| File modified beyond task scope | +20% per file | Scope creep |
| Multi-file change | +5% per file | Complexity indicator |
| 8+ consecutive reads without writes | Flag | Analysis paralysis |

**Halt when:** risk > 20% OR file changes > 50. Escalate to lead for manual review.

---

## Parallel review: implementation detail

### Why parallel reviews are safe

Gemini, Codex, and Claude subagents never write to the same files during review:
- Gemini writes to `ops/REVIEW_GEMINI.md`
- Codex writes to `ops/REVIEW_CODEX.md`
- Claude subagents return results directly to the lead agent
- All append to `ops/CHANGELOG.md` (separate sections, no git conflict)
- None modifies source code during review

### Review focus split

```
                    ┌──────────────────────────┐
                    │     Code under review     │
                    └──────────┬───────────────┘
                               │
           ┌───────────────────┼───────────────────┐
           │                   │                   │
    ┌──────▼──────┐     ┌──────▼──────┐     ┌──────▼──────┐
    │  Gemini CLI  │     │  Codex CLI   │     │  Claude      │
    │              │     │              │     │  Subagents   │
    │ Architecture │     │ Logic        │     │              │
    │ Design       │     │ Correctness  │     │ Security     │
    │ Readability  │     │ Edge cases   │     │ (sentinel)   │
    │ Naming       │     │ Type safety  │     │ Performance  │
    │ Documentation│     │ Security     │     │ (oracle)     │
    │ Consistency  │     │ Test coverage│     │ Simplicity   │
    │              │     │ Performance  │     │ Conventions  │
    └──────┬───────┘     └──────┬──────┘     └──────┬──────┘
           │                   │                   │
           │ REVIEW_GEMINI.md  │ REVIEW_CODEX.md   │ Direct return
           │                   │                   │
           └───────────────────┼───────────────────┘
                               │
                    ┌──────────▼───────────────┐
                    │ findings-synthesizer      │
                    │ Deduplicates + tiers      │
                    │ Confidence + priority     │
                    └──────────┬───────────────┘
                               │
                    ┌──────────▼───────────────┐
                    │  Claude Code fixes issues │
                    └──────────────────────────┘
```

### Handling review conflicts

When reviewers disagree:

1. **Both agree on the problem:** Take the more specific recommendation
2. **Different problems, same code:** Address both
3. **Contradictory recommendations:** findings-synthesizer flags as CONTRADICTION. Claude decides based on ARCHITECTURE.md and MEMORY.md. Log decision in MEMORY.md
4. **One approves, one flags:** The flag wins. Address the concern

---

## Error handling

### Gemini CLI fails to invoke
- Capture stderr from the background process
- Retry once with simplified prompt (fewer files, shorter context)
- If still fails: skip Gemini review, note in TASKS.md as "Review pending: Gemini unavailable"
- Continue with Codex review + Claude subagent reviews only
- Alert user that Gemini review was skipped

### Codex CLI fails to invoke
- Capture stderr
- Retry once with reduced scope (fewer test tasks)
- If still fails: note in TASKS.md as "Tests pending: Codex unavailable"
- Alert user that testing was skipped

### Subagent/teammate failure
- If a subagent fails on a task: retry once with reduced scope
- If retry fails: skip the task, log it as blocked in TASKS.md, continue with other work
- Never spend more than 2 attempts on a failing task

### Review disagreement
- If Gemini approves but Codex flags issues (or vice versa), treat all flagged issues as valid
- The more conservative review wins
- Log the disagreement in MEMORY.md for future reference

### Infinite review loop
- Maximum 3 review cycles per sprint
- If issues persist after 3 cycles, escalate to user with:
  - Summary of unresolved issues
  - All reviewers' perspectives
  - Your recommendation

---

## Execution flow: complete sequence diagram

```
YOU
 │
 ▼
"Build the scraper module for AdWatch AI"
 │
 ▼
┌───────────────────────────────────────────────────────────────┐
│ CLAUDE CODE (Lead Agent)                                       │
│                                                                │
│ Pre-Plan: SEARCH INSTITUTIONAL KNOWLEDGE                       │
│ └── learnings-researcher searches ops/solutions/, ops/decisions│
│                                                                │
│ Phase 0: CODEBASE ANALYSIS (Gemini codebase-analyst agent)      │
│ ├── invoke_gemini "codebase-analyst" "Analyze codebase..."     │
│ ├── Gemini writes ARCHITECTURE.md, MEMORY.md, CONTRACTS.md     │
│ ├── research-synthesizer merges findings (optional)            │
│ └── Claude reads updated ops/ files                            │
│                                                                │
│ Phase 1: PLAN (writing-plans + shadow-path-tracing skills)     │
│ ├── Read GOALS.md, ARCHITECTURE.md, CONTRACTS.md, MEMORY.md   │
│ ├── Decompose goal into atomic tasks                           │
│ ├── Shadow path tracing for non-trivial tasks                  │
│ ├── Error/rescue maps for external calls                       │
│ ├── Embed CONTRACTS.md types in task descriptions              │
│ ├── Group tasks into waves                                     │
│ └── Write TASKS.md                                             │
│                                                                │
│ Phase 1.5: PLAN VALIDATION (plan-checker agent)                │
│ ├── Validate assignments, dependencies, scope, shadow paths    │
│ └── Max 3 iterations until APPROVED                            │
│                                                                │
│ Phase 2: BUILD (wave-orchestration skill)                      │
│ ├── Option A: Subagent mode (< 5 tasks)                       │
│ │   ├── Wave 1: parallel subagents ─────────┐                  │
│ │   ├── integration-verifier ───────────────┤                  │
│ │   ├── Wave 2: parallel subagents ─────────┤                  │
│ │   └── integration-verifier ───────────────┘                  │
│ ├── Option B: Agent team mode (5+ tasks)                       │
│ │   ├── team-lead orchestrates                                 │
│ │   ├── Teammates with file ownership ──────┐                  │
│ │   ├── Quality gates (TaskCompleted hooks) ─┤                  │
│ │   └── Teammates invoke gemini/codex ──────┘                  │
│ ├── Risk scoring per subagent/teammate                         │
│ └── Update CHANGELOG.md + CONTRACTS.md                         │
│                                                                │
│ Phase 3: PARALLEL REVIEW                                       │
│ ├── invoke_gemini "architecture-reviewer" & ── GEMINI_PID     │
│ ├── invoke_codex "logic_reviewer" &       ── CODEX_PID        │
│ ├── Claude: security-sentinel agent ── parallel                │
│ ├── Claude: performance-oracle agent ── parallel               │
│ └── Claude: code-simplicity-reviewer ── parallel               │
│     │                                                          │
│     ▼ (wait for all)                                           │
│                                                                │
│ Phase 4: PROCESS REVIEWS (findings-synthesizer agent)          │
│ ├── Merge + deduplicate all findings                           │
│ ├── Confidence tiering (HIGH/MEDIUM/LOW)                       │
│ ├── Priority ranking (P1/P2/P3)                                │
│ ├── Suppress false positives                                   │
│ ├── Fix P1 + P2 issues                                         │
│ ├── Convergence check (fast/standard/deep)                     │
│ └── If not converged → loop to Phase 3 (max 3x)               │
│                                                                │
│ Phase 5: TEST (Codex test_writer agent)                         │
│ ├── test-gap-analyzer identifies coverage gaps                 │
│ ├── invoke_codex "test_writer" "Write tests..."               │
│ ├── Read TEST_RESULTS.md                                       │
│ ├── Fix failing tests                                          │
│ └── Re-run until green                                         │
│                                                                │
│ Phase 6: WRAP UP                                               │
│ ├── Knowledge compounding (ops/solutions/, ops/decisions/)     │
│ ├── Final CHANGELOG.md update                                  │
│ ├── MEMORY.md: new decisions + gotchas                         │
│ ├── TASKS.md: all tasks marked done                            │
│ ├── Archive review files to ops/archive/[date]/                │
│ ├── Verification checklist (all checks must pass)              │
│ ├── Completion signal: <promise>DONE</promise>                 │
│ └── STATE.md: session handoff                                  │
└───────────────────────────────────────────────────────────────┘
 │
 ▼
YOU: Review summary, check CHANGELOG, approve or request changes
```

---

## Practical setup guide

### Prerequisites

- Claude Code installed and configured with your project template
- Gemini CLI installed and authenticated
- Codex CLI installed and authenticated
- All three CLIs working in non-interactive mode:
  ```bash
  gemini -p "Respond with only: READY"
  codex exec "Respond with only: READY"
  ```

### Plugin installation

```bash
claude plugin add https://github.com/Ninety2UA/agent-triforge
```

The plugin provides agents, skills, commands, and hooks automatically. Your project gets an `ops/` directory (bootstrapped on first session):

```
agent-triforge/                     (plugin — installed automatically)
├── .claude-plugin/plugin.json        Plugin manifest
├── agents/                           19 Claude specialized agent definitions
├── gemini-agents/                    Gemini CLI agent definitions (native subagents)
│   ├── codebase-analyst.md             Phase 0 full-repo analysis
│   ├── architecture-reviewer.md        Phase 3 architecture review
│   ├── targeted-researcher.md          Deep-research targeted analysis
│   ├── documentation-writer.md         Documentation specialist
│   └── policies.toml                   Gemini policy engine rules
├── codex-agents/                     Codex CLI agent definitions (native subagents)
│   └── agents.toml                     logic_reviewer, test_writer, debugger
├── skills/                           12 portable workflow modules
├── commands/                         16 slash commands
├── hooks/
│   ├── hooks.json                    Hook registration
│   └── handlers/                     5 lifecycle hook scripts
├── scripts/
│   ├── coordinate.sh                 Outer loop for context recovery
│   └── invoke-external.sh           Unified Gemini/Codex invocation helper
└── settings.json                     Default env vars

your-project/                       (bootstrapped on first session)
├── CLAUDE.md                         Orchestration protocol (copy from template)
├── .gemini/                          Gemini agent definitions (copied from plugin)
│   ├── agents/                         Agent definitions (.md files)
│   └── policies.toml                   Policy engine rules
├── .codex/                           Codex agent definitions (copied from plugin)
│   └── agents/agents.toml              Agent definitions (TOML)
├── ops/                              Shared coordination files
│   ├── MEMORY.md                       Decisions, patterns, gotchas
│   ├── CHANGELOG.md                    Audit trail
│   ├── STATE.md                        Session continuity
│   ├── solutions/                      Documented solved problems
│   ├── decisions/                      Architecture decision records
│   └── archive/                        Archived review + test files
└── src/                              Your source code
```

### Configuration

The plugin handles all configuration automatically via `hooks/hooks.json` and `settings.json`. No manual `.claude/settings.json` editing needed.

Hook registration uses `${CLAUDE_PLUGIN_ROOT}` for plugin-relative paths:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/handlers/ship-loop.sh" }]
      }
    ]
  }
}
```

---

## Scaling guidelines

### When to use each build mode

| Condition | Mode |
|---|---|
| < 5 independent tasks, no shared state | Subagent mode (parallel) |
| 5+ tasks with dependencies | Agent team mode |
| Tasks share no files and no state | Subagent mode |
| Tasks require cross-communication | Agent team mode |
| Complex multi-module build | Agent team mode with team-lead |
| Quick focused task | Single subagent |

### When to use which review agents

| Scenario | Reviewers |
|---|---|
| Standard code review | Gemini + Codex (default) |
| Security-sensitive code (auth, payments) | + security-sentinel |
| Performance-critical code (hot paths) | + performance-oracle |
| Complex refactoring | + code-simplicity-reviewer + convention-enforcer |
| Full review swarm (ship-ready) | Gemini + Codex + all 4 Claude review agents |

### When NOT to use this framework

- **Trivial tasks** (< 30 minutes): Just use Claude Code directly
- **Pure exploration**: Single agent for brainstorming
- **Tight deadline with no test requirement**: Claude Code solo, skip review + test
- **Non-code deliverables**: Gemini solo with large context
