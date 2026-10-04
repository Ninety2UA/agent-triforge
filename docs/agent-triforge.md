# Multi-agent coordination framework: hybrid pattern

> Claude Code as lead agent with native subagents, agent teams, and external agent delegation to Antigravity CLI and Codex CLI

---

## Overview

This framework establishes Claude Code as the lead agent in a multi-agent system. Before any planning begins, Antigravity CLI performs a Phase 0 codebase analysis -- ingesting the full repository to produce an up-to-date picture of the architecture, patterns, and contracts. Claude Code then plans work, validates the plan, decomposes goals into tasks, and assigns each to a roster member (`ops/roster.toml`). Every implementation task — including the lead's own — is built under a per-task lease in an isolated worktree and merged only after cross-review by a pinned non-author reviewer; the lead orchestrates the pool, injects context, and performs all merges. Review and testing fan out to Antigravity CLI, Codex CLI, and specialized Claude subagents in parallel, never sequentially.

The coordination model is hybrid: file-based shared state (TASKS.md, MEMORY.md, CHANGELOG.md, CONTRACTS.md) provides the persistent context layer, while direct bash invocation provides the real-time orchestration layer. Claude Code owns both.

### Agents and their roles

| Agent | Invocation | Strengths | Primary domain |
|---|---|---|---|
| Claude Code (Fable 5.1 at max; Opus 5.5 at max when the host lacks Fable) | Native (lead agent) | Complex code generation, multi-file refactors, system design, business logic | Feature implementation, API design, database schemas, orchestration |
| Claude Code subagents (Opus 5.5 floor; Fable 5.1 via the spawn-time override) | Native Agent tool | Parallel isolated tasks within Claude's domain | Splitting large build tasks into parallel tracks |
| Claude Code agent teams (Opus 5.5 floor; Fable 5.1 via the spawn-time override) | Native team coordination | Multi-instance collaboration with shared task lists | Complex builds with 5+ interdependent tasks |
| Claude specialized agents (Opus 5.5 floor; never-downgrade trio at max with the spawn-time Fable override) | Agent tool with agent definitions | Focused expertise (security, performance, plan validation, etc.) | Review enhancement, research, verification |
| Antigravity CLI (`agy`) | `agy -p "..."` via bash, agent definitions in `antigravity-agents/agents/` (an agy plugin in the agy Markdown-agent format; `TRIFORGE_AGY_MODE` selects prompt-prefix injection — the shipped default — or native `--agent`) | Large context window (1M tokens, Gemini 3.8 Flash (High) by default; 3.1 Pro opt-in), whole-repo analysis, different model perspective, per-agent tools allowlists | Codebase analysis (Phase 0), code review, documentation, architecture audits |
| Codex CLI | `codex exec "..."` via bash, Triforge agent definitions deployed as `.codex/triforge-agents.toml` (replayed as flags by the helper) | Native test runner, subagent parallelism, sandbox execution, per-agent sandbox modes | Testing, infrastructure, deployment, benchmarking, security review |

> **Builder pool.** The rows above are the shipped default posture. Under the builder pool, any roster member — the core trio plus enrolled optional members (OpenCode, Kimi, Cursor) — is an eligible builder assigned via `ops/roster.toml`; every build runs under a per-task lease in an isolated worktree and merges only after cross-review by a pinned non-author reviewer. The single-writer rule is retired: safety is leases + worktree isolation + cross-review, not write-restriction.

### Four coordination modes

1. **File-based layer (persistent):** All agents read and write to shared markdown files in `ops/`. This is the source of truth that persists across sessions, provides audit trails, and enables async coordination.

2. **Direct invocation layer (real-time):** Claude Code calls Antigravity and Codex via bash within a single session. Output is captured, parsed, and acted on immediately.

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
| `CONTRACTS.md` | Shared TypeScript interface definitions — treated as immutable unless change proposed via MEMORY.md | Claude modifies, Antigravity discovers |
| `ARCHITECTURE.md` | System design document | Antigravity writes during Phase 0 |
| `AGENTS.md` | Master operating protocol read by all agents | Manual |
| `GOALS.md` | High-level product goals | Manual |
| `CONVENTIONS.md` | Code style and standards | Antigravity discovers, Claude maintains |
| `STATE.md` | Session continuity — current phase, progress, next actions | Claude writes on pause/wrap |
| `REVIEW_ANTIGRAVITY.md` | Antigravity's review output (temporary) | Antigravity writes, Claude reads |
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
- [ ] T1: [task description] (Agent: Claude | Antigravity | Codex)
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
- [R] T1: [task] (Reviewers: Antigravity + Codex) [Submitted: timestamp]

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
  Affected agents: Codex (test fixtures), Antigravity (docs)
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

### Antigravity CLI
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

Skills are model-agnostic markdown files that encode reusable methodologies. The `skills/` tree holds 27 skills: the 10 portable skills below, which ALL agents consume, and the 17 lead workflows (`skills/at-*/`). A lead runs a workflow as `/at-<name>` under Claude Code or `$at-<name>` in a Codex prompt; the workflows reach a lead only from its plugin install and are never copied into `.agents/skills/` or a lease worktree (KTD12). The portable skills:

- **Claude Code:** Uses skills natively via the skill system
- **Antigravity CLI:** Skills embedded in native agent definitions (`antigravity-agents/agents/*.md`). The `invoke-external.sh` helper injects the agent body (skill included) as a prompt prefix by default (`TRIFORGE_AGY_MODE=injection`); `native`/`auto` route through `--agent` when `agy agents` lists the definition.
- **Codex CLI:** Skills embedded in native agent definitions (`codex-agents/agents.toml` as `developer_instructions`, deployed as `.codex/triforge-agents.toml`). The `invoke-external.sh` helper extracts the config and injects the instructions as a prompt prefix.
- **Workspace tier:** `session-start.sh` also copies the portable skills to `.agents/skills/` (the Antigravity workspace-skills tier and cross-CLI agentskills.io path, read by agy, Codex, OpenCode, Cursor, and Kimi — not Claude Code) and refreshes the copy on plugin version change under the `.agents/skills/.triforge-plugin-version` stamp, which records a content digest per directory Triforge wrote: only Triforge's own unchanged copies are replaced or retired; an edited copy is kept with a notice (customizations are safest in a differently named directory).

**Conformance validator.** `scripts/validate-skills.sh` enforces the 26-check list from `ops/research/2026-09-27-repo-mining.md` §3 (C1–C26: frontmatter shape and the strict-YAML subset, the allowed keys plus the validator-owned exceptions `disable-model-invocation` and `argument-hint`, a trigger-first description within 150 characters and ≤ 300, the 4,000-character budget over all shipped descriptions counted once per skill, the 8,000-byte body cap with a shrink-only `OVER_BUDGET` allowlist, no Claude-only interpolation or bare `${CLAUDE_PLUGIN_ROOT}`, no harness tool names outside `references/<harness>.md`, the layout and one-level reference rules, script hygiene, `agents/openai.yaml` parity) plus two Triforge gates: KTD1 (no `case` or comparison over the lead's CLI value outside `scripts/lib/registry.sh` and `roster.sh`) and KTD6 (every `skills/at-*/scripts/` carries the shared locator byte-identical). Since U23 made strict mode the default, every rule fails in every mode. Each rule has a fixture under `scripts/fixtures/validate-skills/<rule>/` (a scratch repo root with an `EXPECT` file), and `--self-test` runs every fixture in both modes, asserting that exactly the named rule fires at the named severity; `.github/workflows/gates.yml` runs it after the validator. `skills-ref validate` runs when the binary is on PATH and prints a `skip:` line otherwise, so its verdict on the two widened keys is pending until it is installed. The repo-local `.claude/skills/at-skill-work/SKILL.md` carries the authoring rules.

### Available skills and their primary consumers

| Skill | Primary consumer | Phase | Purpose |
|---|---|---|---|
| `codebase-mapping` | Antigravity | Phase 0 | Systematic full-repo analysis methodology |
| `writing-plans` | Claude | Phase 1 | Task decomposition with shadow paths and error maps |
| `shadow-path-tracing` | Claude | Phase 1 | Enumerate failure paths alongside happy paths |
| `wave-orchestration` | Claude | Phase 2 | Dependency-grouped parallel execution |
| `iterative-refinement` | Claude | Phase 4 | Review-fix-review loop with convergence modes |
| `review-synthesis` | Claude | Phase 4 | Merge and deduplicate multi-reviewer findings |
| `verification-before-completion` | All | Phase 6 | Evidence-based completion checklist |
| `knowledge-compounding` | Claude | Phase 6 | Document solutions and decisions for future sprints |
| `session-continuity` | Claude | Any | Save and resume work across sessions |
| `scope-cutting` | Claude | Any | Systematically cut scope when overwhelmed |

### External agent definitions

Skills consumed by Antigravity and Codex are embedded in their native agent definitions, loaded automatically at session start:

| Agent definition | CLI | Embedded skill | Role |
|---|---|---|---|
| `antigravity-agents/agents/codebase-analyst.md` | Antigravity | `codebase-mapping` | Phase 0 full-repo analysis |
| `antigravity-agents/agents/architecture-reviewer.md` | Antigravity | (inline review protocol) | Phase 3 architecture review |
| `antigravity-agents/agents/targeted-researcher.md` | Antigravity | `codebase-mapping` (subset) | Deep-research targeted analysis |
| `antigravity-agents/agents/documentation-writer.md` | Antigravity | (inline docs protocol) | Documentation generation |
| `codex-agents/agents.toml → logic_reviewer` | Codex | (inline review protocol) | Phase 3 logic + security review |
| `codex-agents/agents.toml → test_writer` | Codex | (inline TDD protocol) | Phase 5 TDD test writing |
| `codex-agents/agents.toml → debugger` | Codex | (inline diagnostic protocol) | Bug investigation |

### Invocation via invoke-external.sh

The shared helper `scripts/invoke-external.sh` provides unified invocation with feature detection:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Antigravity Phase 0 with codebase-analyst agent
invoke_antigravity "codebase-analyst" \
  "Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append)." \
  "${TMPDIR:-/tmp}/antigravity_phase0_$$_$(date +%s).txt" 600

# Codex testing with test_writer agent
invoke_codex "test_writer" \
  "Test scope: changed files from ops/TASKS.md. Write results to ops/TEST_RESULTS.md." \
  "${TMPDIR:-/tmp}/codex_test_$$_$(date +%s).txt" 900

# Codex bug investigation with debugger agent
invoke_codex "debugger" \
  "Investigate the bug: [description]. Follow the diagnostic protocol. Write findings to ops/REVIEW_CODEX.md." \
  "${TMPDIR:-/tmp}/codex_debug_$$_$(date +%s).txt" 600
```

**Plugin root resolution (KTD6).** The loader resolves the plugin root once, at `source` time, and the lanes read it as `${_TRIFORGE_PLUGIN_ROOT}` (or call `triforge_plugin_root`). None of `scripts/lib/*.sh` reads `CLAUDE_PLUGIN_ROOT`, so the same helpers run under a Claude Code lead (which exports that variable) and under a lead that does not. Order: `CLAUDE_PLUGIN_ROOT` when it passes the Triforge-root test (`.claude-plugin/plugin.json` named `agent-triforge` plus `scripts/invoke-external.sh`); else the directory above the loader's own `scripts/` when it passes the same test; else the loader refuses to load (rc 2) and names the setup skill. There is no fallback to the working directory's `scripts/`, so a user project with its own `scripts/invoke-external.sh` or `skills/` is never sourced or provisioned from (`_lease_plugin_root` and `_lease_provision_skills` use only the resolved root).

Skills reach the loader through `scripts/skill-locator/locate-triforge.sh`, a POSIX-sh locator every `at-` skill carries as a byte-identical copy in its own `scripts/`. It tries `CLAUDE_PLUGIN_ROOT`, then its own location (the directory two levels above the skill, skipped when that directory lies inside the working directory's project or is a CLI configuration directory such as `<project>/.agents` or `.claude`, because a root planted there would pass the test), then the per-user pointer `<project>/.agents/triforge-plugin-root.local` written by the setup skill's `triforge_bootstrap` (a user project gitignores `.agents/*.local`; this repository ignores `/.agents/` whole). The pointer is refused when the project's git tracks it under any letter case, when `<project>/.agents` is a symlink, when its target resolves inside the project's git toplevel (the main checkout's pointer is tried from a linked worktree), or when the target fails the root test. Otherwise the locator fails closed and names `at-setup`. SELF-11 covers every branch.

**How `invoke_antigravity` works:** Routing follows `TRIFORGE_AGY_MODE` (`injection` | `native` | `auto`; default `injection` this release — KTD10): `injection` extracts the body of `antigravity-agents/agents/<name>.md` and injects it as a prompt prefix; `native` passes `--agent <name>` and falls back to injection with a warning when `agy agents` does not list it; `auto` goes native only when listed. Every call pins the model (`--model "Gemini 3.8 Flash (High)"` by default — agy's own default is a `(Medium)` variant; `AGY_MODEL`/the roster override it), binds the workspace with `--add-dir "$PWD"`, caps agy's own headless wait with `--print-timeout`, and runs `--output-format json`: the JSON envelope, not the exit code, is the completion signal (since agy 1.1.20/1.1.28 benign tool errors and timeout expiry exit 0). `_agy_parse_envelope` writes the prose `response` to the output file and `status`/`denied_actions`/resolved `mode` to `.status`/`.denied`/`.mode` sidecars; an empty response with denials is a deterministic failure naming the user-tier allow rule (`read_url(*)` for the research lanes), an empty response without denials is `no-output`. Failures are classified (KTD-9) via `INVOKE_FAILURE_CLASS`: `deterministic` fails fast with fix guidance, `timeout` returns to the caller for requeue policy, and only `retryable` failures get one retry with the raw prompt. Each call logs `agent/mode/model` to stderr.

**How `invoke_codex` works:** Codex has no CLI flag to select a subagent — upstream "subagents" only spawn from within a running Codex session. The helper simulates agent selection by extracting the agent's config from the Triforge-internal TOML and passing it as `-m` (model), `-c model_reasoning_effort=` (effort replay — `gpt-6-astra` at `xhigh` on every lane), `-s` (sandbox), `-c approval_policy=` overrides, plus `--output-schema` when the agent declares one (resolved at the plugin tier), with `developer_instructions` injected as prompt prefix. Lookup order: project `.codex/triforge-agents.toml` first, then the plugin's `codex-agents/agents.toml`. The file never lives under `.codex/agents/` — Codex ≥ 0.147 sweeps that directory as standalone role files and warns on a multi-agent file.

### Debugging the subagent layer

- **Antigravity:** `agy agents` — inspect loaded agent definitions (from installed agy plugins; run with NO other flags — `agy agents` rejects `--model`/`--add-dir`). `agy plugin list` shows whether the agent-triforge pack is installed. `agy --model "Gemini 3.8 Flash (High)" -p "Respond with only: READY"` is the minimal smoke test for the headless lane.
- **Codex:** In an interactive session, `/agent` switches between active agent threads and inspects ongoing ones. In non-interactive mode (`codex exec`), inspect the session transcript captured by `invoke_codex`'s output file.

### Hard constraint: Antigravity agents do not fan out

Claude (the lead) is the only agent that launches Antigravity agents; no Antigravity agent fans out to other Antigravity agents. If you need parallel Antigravity work, launch multiple top-level `invoke_antigravity` calls from Claude's shell in the background (as `at-review` already does).

### Why portable skills instead of Antigravity's native subsystems

Antigravity CLI ships its own plugin system (`agy plugin {install,uninstall,list,enable,disable}`) and a user-tier skills directory (`~/.gemini/antigravity-cli/skills/`). We use the plugin system only as an agent-definition carrier (`antigravity-agents/` is a valid agy plugin), not as a skills registry:

- **Skills:** Our 10 portable skills in `skills/` are markdown files consumed by all three agents (Claude/Antigravity/Codex) via prompt-prefix injection or native definition embedding, plus the `.agents/skills/` workspace copy for agents that discover workspace skills. Registering them per-CLI would fragment the portability story. The 17 lead workflows in the same tree (`skills/at-*/`) are the lead's alone and stay out of that copy.
- **Hooks:** Our `hooks/handlers/*.sh` are Claude Code lifecycle hooks (SessionStart, Stop, PostToolUse, etc.) — the Antigravity CLI runs as a subprocess of a Claude Code session, a different layer with different events. Project-tier agy hooks are an open watch, not an enforcement path: they fired under `agy -p` on agy 1.2.0 in the documented `.agents/hooks.json` named-hook shape (lead marker-file re-probe 2026-09-11 — the July "inert headless" reading was a probe-shape error) but not on agy 1.2.1 the same evening (AGY-08 FAIL in the shipped record, both hooks.json files loaded, no handler executed). Triforge ships none either way: its lifecycle logic stays in the Claude Code hooks.

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

These agents run alongside Antigravity and Codex to add review depth:

| Agent | Focus | Complements |
|---|---|---|
| `security-sentinel` | OWASP Top 10, injection, auth/authz, data exposure | Codex security review |
| `performance-oracle` | O(n²), N+1 queries, memory leaks, scalability | Depth beyond Antigravity's and Codex's review focus |
| `code-simplicity-reviewer` | Over-engineering, YAGNI, unnecessary abstractions | Antigravity readability review |
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

# Security review (Claude subagent, parallel with Antigravity/Codex)
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
| 2 | Failing test before implementation (TDD) | Phase 2 | Stated inline in `at-test`, `at-quick` and the Codex `test_writer` agent: a failing test that names the behavior comes before the implementation |
| 3 | Root cause analysis before fixes | Any | Stated inline in `at-debug` and the Codex `debugger` agent: reproduce first, name the root cause with evidence before changing code |
| 4 | Verification evidence before completion | Phase 6 | verification-before-completion skill requires checklist |
| 5 | Code review before shipping | Phase 3-4 | Parallel review (Antigravity + Codex + Claude subagents), max 3 cycles |

---

## Agent-specific protocol files

### AGENTS.md

The master operating protocol. All agents read this.

```markdown
# Multi-agent operating protocol

## Agents in this repo
1. The lead CLI (Claude Code or Codex) -- reads the root AGENTS.md for specific instructions
2. Antigravity CLI -- reads the ANTIGRAVITY.md protocol embedded in docs/agent-triforge.md for specific instructions
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

### Lead agent protocol (formerly the CLAUDE.md template; the root AGENTS.md and the skills carry it now)

```markdown
# Claude Code operating protocol

You are the lead agent in a multi-agent repository. You have three responsibilities:
1. Build features (your primary strength)
2. Coordinate the other agents (Antigravity CLI and Codex CLI)
3. Manage specialized subagents and agent teams for complex work

## Phase 0: Codebase analysis (Antigravity CLI)

Before planning any work, invoke Antigravity CLI with the `codebase-analyst` agent definition to perform a full codebase scan. The agent definition embeds the codebase-mapping methodology and the ops/ file protocol.

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Full codebase analysis (uses codebase-analyst agent definition)
invoke_antigravity "codebase-analyst" \
  "Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append)." \
  "${TMPDIR:-/tmp}/antigravity_phase0_$$_$(date +%s).txt" 600
```

For parallel fan-out (optional, for large codebases), launch a second Antigravity process with a targeted researcher:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Parallel: structural analysis + targeted risk analysis
invoke_antigravity "codebase-analyst" \
  "Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append)." \
  "${TMPDIR:-/tmp}/antigravity_structure_$$_$(date +%s).txt" 600 &
PID1=$!

invoke_antigravity "targeted-researcher" \
  "Analyze dependencies, risks, and technical debt related to: [goal]." \
  "${TMPDIR:-/tmp}/antigravity_risks_$$_$(date +%s).txt" 600 &
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

Assignment is roster-driven (`ops/roster.toml`, via `resolve_role <role>`); use this matrix as the default posture. YOU decide each task's role, and every build runs under a per-task lease with cross-review by a pinned non-author reviewer before merge — not a write-restriction on any CLI.

### Quick reference

- **Produces code?** → builder role (default Claude; roster-assignable to any member), built under a lease and cross-reviewed before merge
- **Evaluates existing code?** → reviewer role + Claude specialized agents in parallel (default Codex + Antigravity)
- **Runs/executes something?** → tester role (default Codex)
- **Produces documentation?** → documenter role (default Antigravity)
- **Touches shared interfaces?** → builder implements under a lease → pinned non-author reviewer cross-reviews → tester validates
- **Ambiguous?** → the lead takes it as builder, flags for parallel review
- **Cross-cutting (all domains)?** → the lead leads, leases per task for build, then parallel review + test

### Codebase analysis tasks (assign to Antigravity CLI -- Phase 0)

| Task type | Why Antigravity | Notes |
|---|---|---|
| Full codebase scan | 1M token context window ingests entire repo | Run before planning phase |
| Architecture mapping | Can analyze all modules and their relationships at once | Writes to ARCHITECTURE.md |
| Pattern discovery | Identifies conventions across the full codebase | Updates MEMORY.md#Patterns |
| Technical debt inventory | Spots inconsistencies by seeing the whole picture | Logs to MEMORY.md#Gotchas |
| Interface extraction | Finds undocumented types, schemas, API shapes | Updates CONTRACTS.md |
| Dependency graph analysis | Can trace imports and relationships across all files | Informs task decomposition |
| Convention audit | Detects naming, structure, and style patterns in use | Updates CONVENTIONS.md |

### Build tasks (default builder: Claude Code; roster-assignable)

Assignment is roster-driven — any member can be the builder. Every build runs under a per-task lease and merges only after cross-review by a pinned non-author reviewer. The table below is the default-posture rationale for why Claude leads builds:

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

### Review tasks (assign to Antigravity CLI + Codex CLI + Claude agents in parallel)

| Task type | Antigravity's focus | Codex's focus | Claude agents |
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

### Documentation tasks (assign to Antigravity CLI)

| Task type | Why Antigravity | Notes |
|---|---|---|
| API documentation | Large context for full-repo coherence | Cross-reference with CONTRACTS.md |
| Architecture docs | Can ingest entire codebase at once | Update ARCHITECTURE.md directly |
| README updates | Understands project-level narrative | Keep consistent with MEMORY.md |
| Onboarding guides | Fresh perspective on code readability | Test instructions against actual setup |
| Technical decision records | Good at articulating tradeoffs | Add to ops/decisions/ |

```

### ANTIGRAVITY.md (reviewer protocol)

```markdown
# Antigravity CLI operating protocol

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

Write findings to ops/REVIEW_ANTIGRAVITY.md:

## Review: [task ID]
### Status: APPROVED | CHANGES_REQUESTED | BLOCKED
### Issues
- [confidence] [severity] [file:line] Description
### Suggestions
- [file] Suggestion description
### Documentation gaps
- [topic] What needs to be documented

## Rules
- When reviewing, return findings — don't edit the code under review (a build lease is where you'd modify source, if the roster assigns you one)
- Never modify CONTRACTS.md during review (propose changes in MEMORY.md)
- Log issues as new tasks in TASKS.md, assigned from the roster
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
- When reviewing, edit only test code and infra configs — return findings on the source under review rather than rewriting it (a build lease is where you'd modify source, if the roster assigns you one)
- Never modify CONTRACTS.md directly (propose changes in MEMORY.md)
- Log code issues as new tasks in TASKS.md, assigned from the roster
```

---

## Execution phases

The full lifecycle for a goal follows these phases:

```
Phase 0:   Codebase analysis (Antigravity with codebase-mapping skill)
Pre-Plan:  Search institutional knowledge (learnings-researcher agent)
Phase 1:   Planning with shadow paths and interface context (writing-plans skill)
Phase 1.5: Plan validation (plan-checker agent)
Phase 2:   Build — subagent mode OR agent team mode with wave orchestration
Phase 3:   Parallel review — Antigravity + Codex + Claude specialized agents
Phase 4:   Process reviews — findings-synthesizer agent, iterative-refinement skill
Phase 5:   Test — Codex test_writer (failing test first), test-gap-analyzer agent
Phase 6:   Wrap up — knowledge compounding, session continuity, completion sentinel
```

### Phase 0: Invoke Antigravity for codebase analysis

Before planning, invoke Antigravity CLI with the codebase-mapping skill to scan the full codebase (see the lead agent protocol above). Read the updated ARCHITECTURE.md, MEMORY.md, and CONTRACTS.md before proceeding.

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

#### Builder-pool wave protocol

Every implementation task — including lead-authored ones — is assigned from `ops/roster.toml`, built under a per-task lease in an isolated worktree, and merged only after cross-review by a pinned non-author reviewer. The single-writer rule is retired: any roster member is an eligible builder; safety is leases + worktree isolation + cross-review, not write-restriction. The lead drives the lease lifecycle from `scripts/invoke-external.sh`:

1. **Assign + lease:** `resolve_role <role>` picks the builder; `lease_create <task> <role>` carves the worktree + `lease/<task>` branch; `lease_dispatch <task> <prompt>` launches the builder with context injected (task rows, CONTRACTS.md slice, roster entry), detached in its own session and process group (KTD10), so it outlives the lead's tool call, turn or terminal; the row records `pid`, `pgid` and the start time, so a reused pid is never taken for the builder. To stop a builder, the lead runs `lease_stop <task>`, which signals its whole process group only while the recorded pid, pgid and start time still match. Builders commit nothing. Each starts in its own worktree and is contracted to stay out of the canonical `ops/` tree (KTD-3), but the worktree limits where a builder starts, not where it writes: the lead detects changes to git state and the ledger, and merges only its own collect snapshot (step 3). This is detection, not prevention; a write elsewhere in the main checkout is not detected.
2. **Collect + pin a reviewer:** `lease_wait`, the one waiting primitive, blocks within the lead's registry `wait_budget_s`, collects each finished builder through `lease_collect` (state → review) and prints the new states. The lead loops it in bounded slices until no lease is building, each repeat naming only the leases on the last `still building:` line, or none to watch every building lease. Exit 75 means the budget ran out while builders were still running, so the lead calls it again. Exit 80 means a building row could not be verified; that ends the loop, and the lead reads the message before doing anything else. A lead that exits leaves its builders running: on resume `lease_heartbeat_check` adopts the live ones and collects the finished ones with `reason=lead-exit`, the requeue budget untouched. The lead pins a reviewer that is a DIFFERENT roster member than the builder (the lead is valid); that reviewer stays pinned across all ≤3 fix cycles of the task (KTD-10). If no non-author reviewer is live, the merge blocks and escalates to the user.
3. **Merge on approval:** pin the reviewer (`lease_pin_reviewer <task> <reviewer>`), then `lease_merge <task> <reviewer>` squashes the snapshot the lead took at `lease_collect` (one commit on the recorded base) as ONE commit per task on the sprint integration branch and records builder + reviewer + merge_commit; it REFUSES self-review (reviewer ≠ `builder_cli` — AE3), an unknown reviewer identity, a merge with no pin, a lease branch carrying commits the builder made itself, a worktree changed after collect, and a diff touching the lead-owned `ops/` (KTD19). Every lease git call runs through `_lead_git`, and the lease functions check the git state against the lead's baseline first: a change the lead didn't make is restored where possible and escalated with rc 44 — detection, not prevention (KTD18); `lease_rebaseline` accepts a change the lead or user made. Findings re-dispatch the same lease/builder with the same pinned reviewer (cycle < 3); at cycle 3 escalate.
4. **Verify + promote:** at wave end `integration-verifier` runs against the integration branch (combined verification across the wave's merged tasks); the lead promotes to the main branch honoring `[promotion] require_user_approval` (default false). Protected-path diffs force the gate on and require the lead or user as the cross-reviewer — never an external-CLI-only review. The lists live in `scripts/lib/registry.sh`: in every project they cover `ops/roster.toml` incl. `[promotion]`, each CLI's config and permission tree (`.claude/`, `.codex/`, `.agents/`, `.antigravity/`, `.gemini/`, `.opencode/`, `.kimi-code/`, `.cursor/`, plus `opencode.json`, `opencode.jsonc` and `.cursorrules` at the root), and every `AGENTS.md`, `AGENTS.override.md`, `CLAUDE.md`, `CLAUDE.local.md` and `.mcp.json` at any depth; in the Triforge checkout they also cover the framework's control plane. `lease_promote` scans the integration diff case-folded and sees both sides of a rename; a match blocks promotion (rc 42), and so does a scan error (fail-closed).

CHANGELOG rows carry builder + reviewer + merge commit from the ledger. The subagent and agent-team modes below are the two ways to run this loop.

#### Choosing the build mode

| Condition | Mode | How |
|---|---|---|
| < 5 independent tasks | Subagent mode | Each task dispatched as native Claude subagent |
| 5+ tasks or interdependent | Agent team mode | Spawn agent team with team-lead orchestrating |
| Tasks share no files | Either | Subagent mode is lighter weight |
| Tasks require cross-communication | Agent team mode | Teammates can message each other |

#### Subagent mode (default)

```
Wave 1: lease + dispatch per task → collect → cross-review → merge to integration branch → integration-verifier
Wave 2: lease + dispatch per task → collect → cross-review → merge to integration branch → integration-verifier
...
Final: Full test suite + build + lint, then promote the integration branch per the [promotion] gate
```

Each builder receives (injected into the dispatch prompt — the contract keeps it out of canonical `ops/`):
- Task description from TASKS.md
- Relevant types from CONTRACTS.md (embedded, not referenced)
- Skill injection if applicable (e.g., verification-before-completion skill)
- Risk scoring rules: halt at risk >20% or file changes >50

#### Agent team mode (complex builds)

```
1. Spawn team-lead agent
2. Team-lead reads plan, groups tasks into waves
3. Team-lead assigns each task to a builder resolved from ops/roster.toml, dispatched under a lease, and pins a non-author reviewer per task
4. Builders run confined in worktrees; the team-lead injects context and does all merges on the main tree (KTD-3)
5. Quality gates: tests/lint pass and a pinned non-author reviewer approves before a task merges (self-review refused — AE3)
6. Integration-verifier runs between waves against the integration branch; the lead promotes per the [promotion] gate
7. Teammates can invoke antigravity/codex themselves for review/testing
```

Invoke Antigravity/Codex from within a teammate:
```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Teammate invoking Antigravity for a specific review
invoke_antigravity "architecture-reviewer" \
  "Review the auth module changes in src/auth/. Write to ops/REVIEW_ANTIGRAVITY.md." \
  "${TMPDIR:-/tmp}/antigravity_build_$$_$(date +%s).txt" 600 &

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

After each task merges: its CHANGELOG.md row carries builder + reviewer + merge commit (from the ledger), and the task moves to "Done" in TASKS.md.

### Phase 3: Parallel review

After completing build tasks, invoke all reviewers in parallel.

CRITICAL: All reviewers run simultaneously, not sequentially.

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# === External reviewers (background processes) ===

# Antigravity architecture review (uses architecture-reviewer agent definition)
invoke_antigravity "architecture-reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. Write findings to ops/REVIEW_ANTIGRAVITY.md." \
  "${TMPDIR:-/tmp}/antigravity_review_$$_$(date +%s).txt" 600 &
AGY_PID=$!

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
wait $AGY_PID $CODEX_PID
```

The review protocol (confidence tiering, suppression rules, output format) is embedded in each agent definition rather than repeated inline. The `invoke-external.sh` helper handles feature detection and fallback to legacy prompt injection.

### Phase 4: Process parallel review results (review synthesis)

After all reviews complete, use the review-synthesis skill and findings-synthesizer agent:

1. Spawn the findings-synthesizer agent
2. It reads REVIEW_ANTIGRAVITY.md, REVIEW_CODEX.md, and subagent review outputs
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
5. Archive temporary files (REVIEW_ANTIGRAVITY.md, REVIEW_CODEX.md, TEST_RESULTS.md) to ops/archive/[date]/
6. **Verification checklist** (verification-before-completion skill):
   - All tasks marked done
   - All tests passing
   - All critical/major issues resolved
   - CHANGELOG updated
   - MEMORY.md updated
7. **Completion signal:** Only after ALL checks pass, create the runtime marker as the LAST action:
   ```bash
   touch ops/.sprint-complete
   ```
   The marker is gitignored and never committed; `scripts/coordinate.sh` detects sprint completion solely by its existence.
8. **Session continuity** (session-continuity skill):
   - If more work remains: write STATE.md with current progress and next actions
   - If sprint complete: write STATE.md as clean handoff for next sprint
   - Sprint summary for user

---

## Context management

### Completion gating + context exhaustion recovery

Two mechanisms keep a sprint honest and alive:

#### Completion gating (native /goal + sentinel)

Sprint completion is gated by Claude Code's native `/goal` command (probe CC-03; this replaced the retired `ship-loop.sh` Stop hook and its `<promise>` convention):
- `scripts/coordinate.sh` composes each session prompt with a leading `/goal` line carrying the completion checklist, so headless sessions are hard-gated natively
- Interactive `at-ship` and `at-coordinate` print a copyable `/goal` line at sprint start (a skill cannot invoke `/goal` itself: under a Claude Code lead it is user-typed or the leading line of a `claude -p` prompt; a Codex lead has no such gate and completes on the sentinel alone, KTD14) and hold the lead to the same checklist
- The session creates the runtime marker `ops/.sprint-complete` ONLY after the verification checklist passes — the marker is gitignored and is the sole completion signal outer tooling reads

#### Outer loop (coordinate script)

The `scripts/coordinate.sh` script spawns fresh Claude Code sessions when context is truly exhausted:
- Each iteration gets a clean context window
- Progress tracked in ops/STATE.md
- Completion detected via the `ops/.sprint-complete` sentinel (cleared at loop start, checked after each iteration — no output parsing)
- Supports flags: `--max N`, `--convergence`, `--team`, `--dry-run` (print the composed prompt without invoking claude)

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

Antigravity, Codex, and Claude subagents never write to the same files during review:
- Antigravity writes to `ops/REVIEW_ANTIGRAVITY.md`
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
    │ Antigravity  │     │  Codex CLI   │     │  Claude      │
    │ CLI (agy)    │     │              │     │  Subagents   │
    │ Architecture │     │ Logic        │     │              │
    │ Design       │     │ Correctness  │     │ Security     │
    │ Readability  │     │ Edge cases   │     │ (sentinel)   │
    │ Naming       │     │ Type safety  │     │ Performance  │
    │ Documentation│     │ Security     │     │ (oracle)     │
    │ Consistency  │     │ Test coverage│     │ Simplicity   │
    │              │     │ Performance  │     │ Conventions  │
    └──────┬───────┘     └──────┬──────┘     └──────┬──────┘
           │                   │                   │
           │ REVIEW_           │ REVIEW_CODEX.md   │ Direct return
           │ ANTIGRAVITY.md    │                   │
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

### Antigravity CLI fails to invoke
- Capture stderr from the background process
- Retry once with simplified prompt (fewer files, shorter context)
- If still fails: skip Antigravity review, note in TASKS.md as "Review pending: Antigravity unavailable"
- Continue with Codex review + Claude subagent reviews only
- Alert user that Antigravity review was skipped

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
- If Antigravity approves but Codex flags issues (or vice versa), treat all flagged issues as valid
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
│ Phase 0: CODEBASE ANALYSIS (Antigravity codebase-analyst agent) │
│ ├── invoke_antigravity "codebase-analyst" "Analyze codebase..."│
│ ├── Antigravity writes ARCHITECTURE.md, MEMORY.md, CONTRACTS.md│
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
│ │   └── Teammates invoke antigravity/codex ─┘                  │
│ ├── Risk scoring per subagent/teammate                         │
│ └── Update CHANGELOG.md + CONTRACTS.md                         │
│                                                                │
│ Phase 3: PARALLEL REVIEW                                       │
│ ├── invoke_antigravity "architecture-reviewer" & ── AGY_PID   │
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
│ ├── Completion marker: touch ops/.sprint-complete              │
│ └── STATE.md: session handoff                                  │
└───────────────────────────────────────────────────────────────┘
 │
 ▼
YOU: Review summary, check CHANGELOG, approve or request changes
```

---

## Practical setup guide

### Prerequisites

**Run `at-setup`** (`/at-setup` under a Claude Code lead, `$at-setup` in a Codex prompt). It is the one guided path from a fresh install to a working roster: it checks that the core trio is live, walks you through each optional CLI (enroll it with a model you choose, or decline it), then offers role assignment. Keep the shipped defaults (recommended) or change any role's CLI, model and effort; `at-setup roles` jumps straight to that step. It is idempotent, so you can re-run it any time. The probes below are the checks it automates.

**Core trio (required)** — installed, authenticated, and answering a headless READY probe (floors per KTD-13):
```bash
claude --version                                                     # Claude Code ≥ 2.1.277 (reads the root AGENTS.md; 2.1.267 first honored effort: frontmatter on pinned-default models; fable alias = Fable 5.1 since 2.1.257)
agy --model "Gemini 3.8 Flash (High)" -p "Respond with only: READY"  # Antigravity ≥ 1.1.27 — pin the model (agy's own default is a (Medium) variant)
codex exec "Respond with only: READY"                                # Codex ≥ 0.153.0 (gpt-6-astra's minimal client version)
```

**Optional tier** (enroll via `at-setup` to use them as builders/reviewers; each is skipped cleanly in every roster fallback chain when absent):
```bash
opencode run --format json -m openrouter/z-ai/glm-5.3 "Respond with only: READY"  # OpenCode ≥ 1.18.20 (OpenRouter provider connected)
kimi -p "Respond with only: READY"                                                # Kimi Code ≥ 0.33.0 (OAuth device-code or API key)
cursor-agent -p --trust --model cursor-grok-4.6-xhigh "Respond with only: READY"  # Cursor (date-versioned; pin the suffixed Grok id, never the Auto router; `agent` when only the new name exists)
```

### Plugin installation

```bash
claude plugin marketplace add https://github.com/Ninety2UA/agent-triforge
claude plugin install agent-triforge@agent-triforge
```

The plugin provides agents, skills and hooks automatically. Your project gets an `ops/` directory (bootstrapped on first session):

```
agent-triforge/                     (plugin — installed automatically)
├── .claude-plugin/plugin.json        Plugin manifest
├── agents/                           19 Claude specialized agent definitions
├── antigravity-agents/               Antigravity CLI agent pack (valid agy plugin)
│   ├── plugin.json                     agy plugin manifest
│   ├── permissions.json                Permission guardrails (migrated deny rules)
│   └── agents/
│       ├── codebase-analyst.md           Phase 0 full-repo analysis
│       ├── architecture-reviewer.md      Phase 3 architecture review
│       ├── targeted-researcher.md        Deep-research targeted analysis
│       └── documentation-writer.md       Documentation specialist
├── codex-agents/                     Codex CLI agent definitions (native subagents)
│   └── agents.toml                     logic_reviewer, test_writer, debugger
├── skills/                           27 skills in one tree
│   ├── <name>/SKILL.md                 10 portable skills, copied to .agents/skills/ and lease worktrees
│   │   └── references/                 where a skill is split (wave-orchestration, verification-before-completion)
│   └── at-<name>/                      17 lead workflows; never copied (KTD12)
│       ├── SKILL.md                      the router: goal, done condition, safe failure, invocation
│       ├── references/                   the detail the router points to
│       ├── scripts/locate-triforge.sh    byte-identical locator (KTD6); finds the plugin root from either lead
│       └── agents/openai.yaml            Codex skill metadata
├── hooks/
│   ├── hooks.json                    Hook registration
│   └── handlers/                     4 lifecycle hook scripts
├── scripts/
│   ├── coordinate.sh                 Outer loop for context recovery
│   └── invoke-external.sh           Unified six-CLI invocation (roster, leases, feature detection)
└── settings.json                     Default env vars

your-project/                       (bootstrapped on first session)
├── AGENTS.md                         Your instruction file, with Triforge's pointer block (templates/AGENTS.md)
├── .agents/skills/                   The 10 portable skills, digest-stamped (read by agy, Codex, OpenCode, Cursor, Kimi)
├── .antigravity/                     Antigravity workspace settings (copied from plugin)
│   └── settings.json                   Permission deny rules
├── .codex/                           Codex agent declarations (copied from plugin)
│   └── triforge-agents.toml            logic_reviewer, test_writer, debugger (never under .codex/agents/)
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

Hook registration uses a double-quoted `"${CLAUDE_PLUGIN_ROOT}"` for plugin-relative paths (an unquoted placeholder fails `claude plugin validate --strict` since Claude Code 2.1.281 — D-039):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/handlers/session-start.sh\"" }]
      }
    ]
  }
}
```

---

## Staying current (`/cli-watch`, `/repo-watch`)

The framework tracks its own dependencies instead of drifting. The two watch commands are **repo-local maintainer tooling**: they live in `.claude/commands/` of the agent-triforge checkout (the plugin ships no commands directory; its lead workflows are the `skills/at-*/` skills), read `ops/watch-registry.toml` (a seeded, editable list of watch targets, tracked in this repo), and share the repo-local `.claude/skills/watch-cycle/SKILL.md` methodology (primary-source research → per-target changelog → gap table vs current Triforge → adopt/defer ADR):

- **`/cli-watch`** — checks the six CLIs against primary sources, writes a gap report + adopt/defer ADR to `ops/research/` and `ops/decisions/`, and re-runs `scripts/probe-capabilities.sh`.
- **`/repo-watch`** — mines external reference repos for adoptable patterns and produces prioritized recommendations (recommends only; never implements).

Run either from a clone of this repo — manually, or scheduled monthly as a Claude Code cloud Routine. Fetched pages are treated as untrusted evidence, never as instructions; a dead or renamed registry entry is flagged in the report, never silently dropped.

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
| Standard code review | Antigravity + Codex (default) |
| Security-sensitive code (auth, payments) | + security-sentinel |
| Performance-critical code (hot paths) | + performance-oracle |
| Complex refactoring | + code-simplicity-reviewer + convention-enforcer |
| Full review swarm (ship-ready) | Antigravity + Codex + all 4 Claude review agents |

### When NOT to use this framework

- **Trivial tasks** (< 30 minutes): Just use Claude Code directly
- **Pure exploration**: Single agent for brainstorming
- **Tight deadline with no test requirement**: Claude Code solo, skip review + test
- **Non-code deliverables**: Antigravity solo with large context


---

## Reference moved from the instruction file

These sections moved here from `.claude/CLAUDE.md` on 2026-10-01, when the root `AGENTS.md` replaced it (plan unit U3; `docs/rule-inventory.md` maps each rule to its new home). They are reference material that no agent loads on every session: `AGENTS.md` keeps the short rules and points here for the detail. The lead workflows named below (`at-setup`, `at-build`, `at-review`, …) are the `skills/at-*/` skills that replaced the 3.x slash commands in 4.0.

### Roster and assignment

`ops/roster.toml` is the single assignment surface: five `[roles.<name>]` tables — builder, reviewer, tester, analyst, documenter (roles ARE the task types) — each carrying `cli`, `model`, `effort`, and an ordered `fallbacks` chain. The file is deliberately CLI-neutral (ops/-level, parsed via python3 `tomllib`) so every adapter can read its own role; `resolve_role <role>` in `scripts/invoke-external.sh` prints `cli<TAB>model<TAB>effort`. Guided edits go through `at-setup`'s role step (defaults-or-customize): `roster_role_entry <role>` prints the merged configuration (no liveness walk; its model column follows resolve_role's primary-model rule, so a cli-only override shows what dispatch would actually run) and `roster_write_role <role> <cli> <model> <effort> [fallbacks-csv]` is the single validated writer for `[roles.*]` — it enforces a strict superset of the load rules (known role/CLI and core-trio chain terminus mirrored from load validation, plus writer-only checks: the effort enum, the agy effort→`(Low)`/`(Medium)`/`(High)` suffix normalization, and the Cursor effort→`-low|-medium|-high|-xhigh` model-id suffix) and derives a valid fallback chain when none is given (displaced primary becomes first fallback). Roster model overrides reach every external-CLI dispatch lane — the codex lane rides `CODEX_MODEL` into `codex exec -m`, same pattern as `AGY_MODEL`/`OPENCODE_MODEL`/`KIMI_MODEL`/`CURSOR_MODEL`. The claude lane is the deliberate exception: review/test work resolved to claude runs as a native Agent-tool subagent whose model is governed by the Fable/downgrade ladder, not the roster.

**Worker marker (KTD9, U11).** `_adapter_env` exports `TRIFORGE_LEASE_WORKER` into every lease worker (`builder`, or `persona` for a persona dispatch). The lead-only helpers — every `lease_*` writer, `_ledger_update`, `roster_write_role` and `roster_write_member` — start with `_lead_only` and refuse with rc 45 (`_RC_LEAD_ONLY`) under the marker or when run from a directory under the lease root (found by walking up to the lease root's `lead/gitconfig`, no git involved). They also refuse, with the same rc, in a shell that is not the lead's. `_lead_host_gate` resolves `[lead]` (`resolve_lead`; no table means claude) and lets a helper run under that lead's host markers, from a terminal (`lease_create` then records `lead_via = tty`), or under the SELF harness's `TRIFORGE_TEST_BUILDER` plus `TRIFORGE_TEST_LEAD`. Under the other lead's markers the refusal names `at-setup lead`. `roster_write_lead`, the lead switch, skips only this check. Readers (`lease_status`, `resolve_role`, `dispatch_role`) stay open. The four hook handlers exit 0 with no output under the marker, so a worker CLI that loads the plugin's hooks bootstraps nothing in its worktree. `lease_create` records what `_lease_provision_skills` put into the worktree in the row's `provisioned` field, and `lease_collect`'s snapshot leaves exactly those paths out (a pre-4.0 row without the field leaves all of `.agents/` at base). `templates/.codex/hooks.json` ships an empty hooks map: attribution comes from the ledger, and session start replaces an unchanged 3.x copy once. SELF-15 covers the refusals, the inert hooks and the squash; SELF-15b/15c run a live `claude -p` and `codex exec` worker.

**CLI registry (KTD7, R25/R41).** Every per-CLI fact lives once, in `scripts/lib/registry.sh`: `_TRIFORGE_CLIS_PY` is one Python literal per CLI — `name`, `tier` (core | optional), `binary` with `binary_env`/`resolver`/`version_re` (Cursor's `cursor-agent`-then-verified-`agent` resolution), the shipped `model` and the `model_env` its lane honors, `install` and `login` hints (printed, never run), `env_keys` (the exact variables `_adapter_env` forwards; `KIMI_*` is the one documented wildcard), `lane` (shell | subagent), `egress` (the provider that sees the code), and for the two lead-capable CLIs the KTD1 `lead` fields (`launch_argv`, `wait_budget_s`, `tool_vocab_read`/`tool_vocab_action`, `goal_gate`, `ask_user`, `native_subagents_enforced_tools`, `agent_teams`, `plugin_root_env`); `TRIFORGE_ENV_BASE` beside it is the base lease allowlist. Shell readers call `cli_list [core|optional]`, `cli_field <cli> <field>[.<sub>]`, `cli_install_fix <cli>` and `_registry_binary <cli>`; the Python inside `resolve_role`, `roster_role_entry` and the roster writers splices the literal, next to the one role table `_ROLE_DEFAULTS_PY` (`DEFAULTS`) in `roster.sh`. `validate-versions.sh` check 3 parses the registry and fails on a malformed entry, a wildcard key other than `KIMI_*`, a role default whose model differs from its CLI's, a stale pin in `templates/ops/roster.toml` or in a lane's `${X_MODEL:-…}` default, or a hand copy creeping back into `lease.sh`, `session-start.sh` or the probe's `_lane_run`. Adding a CLI is one registry entry plus its lane file, probe rows, setup entry and egress line.

- **Resolution order:** `ops/roster.toml` overlays built-in shipped defaults PER-FIELD — a role overriding only `effort` keeps the default cli + model; no roster file at all resolves to the shipped builder-pool posture (defaults are mirrored inside `resolve_role`, kept in sync with `templates/ops/roster.toml`).
- **Fallback chains:** resolution walks the primary `cli`, then `fallbacks` in order; a member is skipped when its binary is absent or its `[members.<cli>]` entry is disabled. Optional-member skips are silent (AE1); core-member skips log a degradation warning. Load-time validation (on every load) requires each chain to terminate at a core-trio member — a chain resolving entirely to optional members is rejected — so the only way a chain exhausts is an absent core-trio terminus, which is a hard error with install guidance (R21).
- **Enabled flag (R38):** `[members.<cli>] enabled = false` means absent everywhere — no dispatches, every role falls back cleanly; re-enabling is the flag flip alone. The core trio (claude, antigravity, codex) cannot be disabled. The shipped template carries NO live `[members.*]` entries, so first-detection enrollment fires and a decline persists as `enabled = false`.
- **Model rules:** agy pins the newest Gemini model at its highest thinking level, Pro or Flash (D-022) — currently `"Gemini 3.8 Flash (High)"`; the 3.1 Pro line (`"Gemini 3.1 Pro (Low|High)"`) is the documented per-role opt-in. The `(Low)`/`(Medium)`/`(High)` suffix is agy's effort control, so `effort` maps into the model-variant suffix (`roster_write_role` normalizes low→Low, medium→Medium, high/xhigh/max→High; 3.1 Pro has no Medium, so medium collapses to Low with a NOTE). Cursor pins `cursor-grok-4.6-xhigh` explicitly — never the Auto router; effort rides in the model-id suffix (`cursor-grok-4.6-low|medium|high|xhigh` — the bracket form `grok-4.6[effort=xhigh]` is rejected headless, CUR-10), the writer composes the suffix from a bare `grok-4.6` plus the role effort, and an explicit suffixed id passes through unchanged. The Cursor binary is `cursor-agent` first; `agent` is accepted only when its `--version` matches `YYYY.MM.DD-<hex>` (`_cursor_bin`). Builder's model is empty by design: the Claude downgrade ladder resolves it. Optional-member fallback models come from `[members.<cli>].model`, else the shipped defaults (opencode → `openrouter/z-ai/glm-5.3`, kimi → `kimi-code/k3`, cursor → `cursor-grok-4.6-xhigh`).
- **Promotion knob:** `[promotion] require_user_approval` (default `false`) gates wave-end promotion to main (KTD-5); protected-path diffs force approval on regardless — enforced by the wave protocol, not the roster.
- **Lazy liveness:** `ensure_core_trio_live` (non-model `--version` checks, 15s each, success cached per session) runs in the `at-build` and `at-review` preambles only — never at session start, so an `at-status`-only session never triggers it.

### Agent frontmatter fields

Agent definitions in `agents/*.md` support these YAML frontmatter fields (verified against the official docs 2026-09-11):
- `name`, `description` (required) — identity and when-to-use trigger
- `model` — `fable`, `opus`, `sonnet`, `haiku`, a full model ID, or `inherit`. Shipped Triforge agents floor at `opus`; the lead applies the spawn-time `fable` override (see the ladder above)
- `effort` — `low`, `medium`, `high`, `xhigh`, `max` (`max` supported on Fable 5.1, Opus 5.5, and Sonnet 5.5); honored on pinned-default models only from Claude Code 2.1.267 — hence the floor
- `tools` — allowlist of tools (Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, etc.); `disallowedTools` is the deny-side counterpart
- `maxTurns` — maximum agentic turns before the agent stops
- `initialPrompt` — new: auto-submitted first turn when the agent runs as the main session via `--agent`
- `experimental` — a map; its `cacheTtl` key (`5m` or `1h`) sets the prompt-cache lifetime for the subagent's requests (Claude Code ≥ 2.1.248; read only from subagent files; `1h` is ignored while a subscription runs on usage credits). No Triforge agent sets it
- Other top-level fields: `skills`, `memory`, `background`, `isolation` (accepts only `"worktree"`), `color`
- **Plugin restriction:** plugin-shipped agents do not support `permissionMode`, `hooks`, or `mcpServers` (security restriction — those three apply only to user- and project-level agent files); no Triforge agent carries them

Antigravity and Codex agent files use their CLIs' own conventions: Antigravity (`antigravity-agents/agents/*.md`) uses the agy Markdown-agent frontmatter (`mainAgent`, `subagent`, `commandExecutionPolicy`, `model: inherit` — the dispatch `--model` governs) with `tools` in agy's own vocabulary (`view_file`, `list_dir`, `find_by_name`, `grep_search`, `write_to_file`, `run_command`, `read_url_content`, `search_web`); Codex (`codex-agents/agents.toml`, deployed as `.codex/triforge-agents.toml`) uses `model_reasoning_effort`, `sandbox_mode`, `approval_policy`, and a `tools` list that is a Triforge-internal allowlist declaration (Codex never reads the file — `invoke_codex` replays the keys as `codex exec` flags and carries the allowlist in the developer instructions).

### Security model

- **Builder-pool safety model** — the framework runs a builder pool where any roster member can be assigned implementation tasks, so isolation replaces write-restriction as the safety boundary: (1) every non-lead build runs under a per-task lease in its own git worktree with a per-adapter env allowlist (KTD-3, KTD-14) that also carries the no-push git config (a lease builder cannot `git push` — pre-push hook + `no-push://` URL rewrite). The worktree limits where a builder starts, not where it writes: a builder with a shell and no OS sandbox can write anything the user can, including the lead's `.git/config` and hooks, other branches, and `ops/leases.toml`. Triforge detects such changes and merges only the lead's own snapshot (KTD18/KTD19, see "Integrity" above) — it does not prevent them; (2) the lease ledger `ops/leases.toml` is lead-owned and single-writer; (3) every task merges only after cross-review by a pinned non-author reviewer (AE3, KTD-10), landing as one squash commit per task on a sprint integration branch; (4) the lead promotes to the main branch at wave end honoring the `[promotion]` gate — and any diff touching a protected path (listed under "Key constraints"; code lists in `scripts/lib/registry.sh`) forces the gate on and requires the lead or user as the reviewer, never an external-CLI-only review; (5) `ops/CHANGELOG.md` attribution carries builder + reviewer + merge commit from the ledger. A roster config can restore the reviewer-only posture (external CLIs off the builder role) for deployments that want it.
- **Provider data egress (R36) + credential handling (KTD-14)** — every dispatched CLI sends its task prompt and the code context it is handed to that CLI's model provider. Under the shipped defaults, code + task context reaches: **Anthropic** (Claude), **Google** (Antigravity → Gemini 3.8 Flash), and **OpenAI** (Codex) for the core trio; and, for any enrolled optional member, **Zhipu / Z.ai** (GLM, routed through the **OpenRouter** intermediary — which also sees the traffic), **Moonshot** (Kimi), and **xAI** (Grok, via Cursor). `ops/roster.toml` is the control surface: disabling a member (`enabled = false`) or dropping a provider's model from every role removes that provider from the egress set (the core trio always stays; chains must still terminate at a core member). Credentials never live in the repo — each adapter reads its own from the OS / vendor store (Claude / Codex / `agy` logins, `OPENROUTER_API_KEY`, `kimi login` OAuth-or-API-key, `cursor-agent login` / `CURSOR_API_KEY`). The lease env allowlist (KTD-14, `_adapter_env`) scopes **environment variables** per-adapter — each optional member is handed only its own provider key (opencode → `OPENROUTER_API_KEY`, kimi → `KIMI_*`, cursor → `CURSOR_API_KEY`), never another member's. It also does **not** bound the worker's tool shell (probe rows CC-11/CC-13 and CDX-15/CDX-17, U29): `claude -p` re-adds the user's `~/.claude/settings.json` `env` block and plugin SessionStart exports to the commands it runs, and `codex exec` runs tool commands through a login shell (`zsh -lc`) that re-reads the user's profile, so a variable the allowlist dropped can reappear inside the worker's shell. It does **not** isolate HOME-based credential *files* either: `HOME` is forwarded to every adapter (the core trio authenticate through `~/.claude` / `~/.codex` / `agy`'s HOME store), so a builder shares the invoking user's HOME and could read those files. The enforced controls are therefore the env-var allowlist, the no-push git config, hardened lead-side git (`_lead_git`), integrity detection, snapshot-only merges and the protected-path gate — **not** a write scope (the worktree limits where a builder starts, not where it writes) and **not** read-isolation of the user's home credential stores; treat a builder as capable of reading any credential file under `$HOME` and of writing anything the user can. Captured CLI output is scrubbed (`_scrub`) before it lands in `ops/`, and rotation follows each vendor's own token flow (revoke + re-login/re-key, then re-run `at-setup`).
- **Codex `approval_policy = "never"`** on all three agents — the framework is designed for trusted pipelines where user approval would block parallel fan-out. `sandbox_mode` (read-only for `logic_reviewer`, `workspace-write` for `test_writer`/`debugger`) plus `approval_policy` are the enforced isolation (KTD5). If you deploy to an untrusted environment, change to `approval_policy = "on-request"` in `codex-agents/agents.toml`. The no-agent fallback in `scripts/invoke-external.sh` supplies the same defaults explicitly (`-s workspace-write -c approval_policy="never"`) — the `--full-auto` shorthand was **removed in Codex 0.147.0** (D-026; `error: unexpected argument` on 0.154.0), so the helper never passes it.
- **Claude worker sandbox (KTD16)** — the `claude -p` worker lane runs Bash in Claude Code's sandbox. The lane covers a lease builder, and a reviewer, tester, analyst or documenter that `dispatch_role` runs under a lead whose sub-agents don't enforce their tools. Writes stay in the working directory. The lead's git common dir and the known credential paths are blocked, and the credential paths are closed to the Read tool too. There is no network, and a command that fails in the sandbox is never retried outside it. Probe row CC-15 records this on the host. Where the sandbox can't start (Linux without bubblewrap and socat), the worker refuses to run and the lease fails as deterministic. `TRIFORGE_CLAUDE_SANDBOX=off` in the lead's environment runs the lane without the sandbox, and a Claude worker with Bash then has no OS confinement. The lane also reads only project and local settings, loads no MCP server, offers an explicit set of built-in tools without the Agent or web tools, and caps each run with `--max-turns`.
- **Codex `tools` allowlist and `[agents]` caps are Triforge-internal declarations** (KTD5) — `codex-agents/agents.toml` is parsed only by `invoke_codex`, which replays `model`, `model_reasoning_effort`, `sandbox_mode`, `approval_policy`, and `output_schema` as `codex exec` flags and carries the per-agent `tools` list (`logic_reviewer` has no `write`/`bash`; `test_writer`/`debugger` get both, since they run tests and reproduce bugs) inside the developer instructions. Codex itself never reads the file, so the allowlist and the caps are instructions to the model, not enforced config; the enforced isolation is `sandbox_mode` + `approval_policy`.
- **Antigravity permission guardrails** — `antigravity-agents/permissions.json` documents the three denies in agy's action syntax — `command(rm -rf)`, `command(git push)`, `command(sudo)` — and `templates/.antigravity/settings.json` ships them as a mergeable `permissions` block (deny intent). Project-tier settings.json is **not read headless** (`.gemini/`, `.agents/`, `.antigravity/` — probed 2026-07-17, re-confirmed 2026-09-11); the only tier agy enforces headless is the user tier `~/.gemini/antigravity-cli/settings.json`, which Triforge never writes (R18). Project-tier hooks **fired on agy 1.2.0** (lead marker-file re-probe 2026-09-11 05:03, documented `.agents/hooks.json` named-hook shape, `--add-dir` bound — the July "inert headless" reading was a probe-shape error), but the harness re-run the same evening on **agy 1.2.1** recorded AGY-08 **FAIL** with both hooks.json files loaded (`agy -p /hooks` lists them; no handler executes) — treat headless agy hooks as an open watch, not an enforcement path; Triforge ships no agy hooks and relies on none (AGY-08). The per-agent `tools` allowlist + `commandExecutionPolicy` in `antigravity-agents/agents/*.md` is the primary guardrail in every mode (`architecture-reviewer` and `documentation-writer` carry `commandExecutionPolicy: "off"` and omit `run_command` — the omission is the denial). In injection mode (`TRIFORGE_AGY_MODE=injection`, the shipped default — KTD10) agy's headless permission auto-deny still applies and denials surface in the JSON envelope; in native mode (`native`, or `auto` when `agy agents` lists the name) the two `commandExecutionPolicy: auto` agents run `run_command` live and their enforced boundary is the user-tier deny list — which `at-setup` documents and only the user writes.
- **Antigravity headless completion signal (D-032/KTD2)** — `invoke_antigravity` runs `--output-format json` and reads the envelope instead of the exit code (since agy 1.1.20/1.1.28 benign tool errors and `--print-timeout` expiry exit 0, and a denied tool leaves `status: SUCCESS` with an empty `response`). `_agy_parse_envelope` writes the prose `response` to the output file and the `status`, `denied_actions`, and resolved `mode` to the `<out>.status`, `<out>.denied`, `<out>.mode` sidecars (background call sites cannot read a shell variable). An empty `response` with `denied_actions` is a deterministic failure whose message names the user-tier allow rule the run needs — `permissions.allow: ["read_url(*)"]` in `~/.gemini/antigravity-cli/settings.json` for the research lanes (a broad grant; human-written, never by Triforge). A non-empty response with denials still succeeds; the promoted `ops/` file gets an HTML-comment header listing them and the mode. Write denials against `ops/` are never fatal (`at-review` and `at-deep-research` promote captured output).
- **Codex `[agents]` caps** (`max_depth = 2`, `max_threads = 4`, `default_subagent_model`/`default_subagent_reasoning_effort`) are Triforge-internal declarations of the intended fan-out (one spawn round, no spawn-of-spawn, every spawn pinned to the shipped model + effort); nothing replays them as `-c` overrides yet (deferred). `max_depth` is honored only by the V1 multi-agent runtime — `gpt-6-astra` runs `multi_agent_v2` by catalog and ignores it — and `job_max_runtime_seconds` is a no-op on current Codex (D-026).
- **Codex auto-memory disabled by default** — Triforge ships `templates/.codex/config.toml` with `[memories] use_memories = false` to prevent Codex's v0.129.0 pipeline from writing `~/.codex/memories/{MEMORY.md, skills/, ...}` in parallel with Triforge's `ops/MEMORY.md` and `ops/solutions/`. Users who want Codex memories can remove the block or override in `~/.codex/config.toml`. The project `.codex/config.toml` applies only in a **trusted** project: Codex ≥ 0.147 skips project-tier `config.toml`/`hooks.json`/`.rules` under `exec` when trust is unset (unset means untrusted for those files, and `exec` never prompts). Project `AGENTS.md` is different (D-045): since 0.150 it is skipped only when trust is explicitly `untrusted`, so an unset project still loads the root `AGENTS.md`. The durable path is a user-tier entry `[projects."<abs path>"] trust_level = "trusted"` in `~/.codex/config.toml`, which `at-setup` detects and prints but never writes (R18); linked worktrees inherit the root checkout's trust.
- **Antigravity skills interop** — `hooks/handlers/session-start.sh` copies `skills/` to `.agents/skills/` (the Antigravity workspace-skills tier and the cross-CLI agentskills.io path, read by agy, Codex, OpenCode, Cursor, and Kimi — not Claude Code) so those CLIs pick up Triforge's portable skills without per-prompt `$(cat ...)` injection. The copy is refreshed on plugin version change under a stamp (`.agents/skills/.triforge-plugin-version`, written last, safe to commit) that records a content digest per directory Triforge wrote: a shipped-name directory is replaced or retired only while its digest still matches (a 3.3.0–3.3.2 stamp without digests is migrated against `scripts/lib/skill-digests.txt`, the released copies); an edited copy, or a user directory under a shipped name, is kept with a notice, and a differently named directory is never touched (KTD12, `scripts/lib/skills-sync.py` — the same rule provisions lease worktrees). Project-tier agy hooks: fired on agy 1.2.0, FAIL again on 1.2.1 the same day (AGY-08 — open watch); Triforge ships none; the retired Gemini hooks example was removed with the Gemini lane.

### Compatibility notes and known-fails

Floors per KTD-13; the compatibility table itself is in the README.

**Minimum supported versions / notes:**
- **Claude Code ≥ 2.1.277** — the first build that reads a root `AGENTS.md` (D-037; only while no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists in the working directory or above). It includes 2.1.267, the build that first honors `effort:` frontmatter on pinned-default models (Triforge's shipped `max`/`xhigh` only take effect from it); the `fable` alias resolves to Fable 5.1 from 2.1.257 and `opus` to Opus 5.5 from 2.1.280 (Opus 5 on 2.1.219–2.1.279). Task/Todo tools are off on current models unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (shipped in `settings.json`, D-031a).
- **Antigravity `agy` ≥ 1.1.27** — `denied_actions` in the JSON envelope (the completion signal `invoke_antigravity` reads); ≥ 1.1.10 is the hard minimum (`--model` was ignored under `-p` on 1.1.5–1.1.9). The Gemini CLI lane was retired in v3.0.0 (Google's hosted service stopped serving consumer tiers 2026-06-18; legacy Gemini users pin plugin v2.4.3).
- **Codex ≥ 0.153.0** — `gpt-6-astra`'s `minimal_client_version`; `--output-schema` (structured review verdicts) and `codex features list` (runtime capability detection) predate it. Older versions degrade: `invoke_codex` still runs, but structured verdicts silently fall back to raw output.
- **OpenCode ≥ 1.18.20** — `opencode run` answers subagent permission asks. **Kimi ≥ 0.33.0** — agent-core-v2 engine; `--agent`/`--agent-file` in `-p` (KIMI-03 PASS on 0.42.0).
- **Optional tier is skip-clean** — an absent or declined optional CLI is silently skipped in every roster fallback chain, which always terminates at a core-trio member; the core trio cannot be disabled.

**Known-fails / partial support:**
- Codex hooks **fire under `codex exec`** (probe CDX-04 PASS on 0.154.0, re-verified 2026-09-11: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Stop`) given the nested `hooks.json` shape, a project-tier `.codex/hooks.json` and hook trust; the probe passes `--dangerously-bypass-hook-trust` to stand in for that trust. `invoke_codex` never passes the flag, so project and plugin hooks go through Codex's own trust under `exec`; the shipped `templates/.codex/hooks.json` has no hooks. Project trust gates every project-tier file: `.codex/hooks.json`, `.codex/config.toml` and `.rules` are skipped under `exec` while trust is unset, and project `AGENTS.md` is skipped only when trust is explicitly `untrusted` (D-045). The durable path is the user-tier `[projects."<abs>"] trust_level = "trusted"` entry (`at-setup` detects it, never writes it). See `ops/decisions/2026-07-18-codex-hooks-under-exec.md` and D-026.
- Antigravity plugin agents: the pack now ships the agy Markdown-agent format (`mainAgent`/`subagent`/`commandExecutionPolicy`, agy tool names — D-027); whether `agy agents` lists the four Triforge agents is verified by row AGY-12 in the newest record, and injection stays the default routing until AGY-12 and AGY-16 pass for a full cycle (KTD10). Project-tier hooks fired headless on agy 1.2.0 with the documented `.agents/hooks.json` shape but not on 1.2.1 (AGY-08 FAIL in the fresh record — open watch); project-tier permission allow-rules do not apply headless (user tier only) — the `at-review` and `at-deep-research` workflows compensate by promoting captured output into `ops/` when the agent could not write there directly.

### Release checklist

1. `claude plugin validate --strict .claude-plugin/plugin.json` and `claude plugin validate --strict .claude-plugin/marketplace.json` both pass green (warnings are errors) — required gate; a bare `validate .` now picks the marketplace manifest only, so name both
2. `bash scripts/validate-skills.sh` exits 0 (the 26-check conformance list plus the KTD1 and KTD6 gates; warnings fail by default, `--warn` relaxes them) and `bash scripts/validate-skills.sh --self-test` reports every fixture OK, and `bash scripts/probe-capabilities.sh --self-only` exits 0 (the SELF gate: static SELF rows only, record to a scratch path, exit 3 on any SELF FAIL — `.github/workflows/gates.yml` runs both on every PR to `main` and `release/4.0`)
3. `bash scripts/validate-versions.sh` exits 0 — version lockstep, the ladder one-definition check (`TRIFORGE_MODEL_LADDER` in `scripts/lib/registry.sh` is the only line that spells the rungs out; `agents/team-lead.md`, `skills/wave-orchestration/SKILL.md` and `AGENTS.md` carry pointers), `DEFAULTS` drift, the scoped stale-pin sweep (zero hits outside `ops/research/`, `ops/decisions/`, `docs/plans/`, `docs/brainstorms/`, `ops/solutions/`, `docs/images/`), surface counts, the root `AGENTS.md` budget (≤ 200 lines and ≤ 16 KiB, once the file exists) `docs/rule-inventory.md` completeness (every row has a destination, no `TBD` cell, every cited destination path exists in the tree, once the file exists), the retired `commands/` directory (no `commands/*.md` ships; the directory stays on `FRAMEWORK_PROTECTED` because the plugin host auto-loads it), the lead-workflow surfaces (the `at-` prefix spelled identically at its four code sites; the session-start banner and the status template enumerate exactly the `skills/at-*/` names) and the other-harness skill manifests (`skills/.devin-plugin/plugin.json` and the root `package.json` `pi.skills` list exactly the portable skill directories, no `at-*` entry, metadata and skills only; no root `.devin-plugin/`)
4. Doc-consistency greps pass (see Verification Contract in the active plan)
5. The probe record is regenerated (`bash scripts/probe-capabilities.sh` writes `ops/research/<YYYY-MM>-probe-record.md`), committed, and cited by the release notes
6. Version bumped in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` (both fields) and `antigravity-agents/plugin.json` (lockstep, checked by `validate-versions.sh`); README "What's new" + "Recent changes" entries added — the "Recent changes" heading must read `### <YYYY-MM-DD> — v<version>: <title>` because it becomes the GitHub release (checked by `validate-versions.sh`; preview with `bash scripts/release-notes.sh --title` / `--body`)
7. Merge to `main`. `.github/workflows/release.yml` runs on every push to `main` that touches `.claude-plugin/plugin.json`: it re-runs both validators, tags `v<version>` at the commit that set the version (an existing tag is kept), and publishes the GitHub release with the title and body from `scripts/release-notes.sh`. It is idempotent — an existing release is left alone. Confirm with `gh release view v<version>`; if the run was skipped or failed, fix the cause and re-run it by hand with `gh workflow run release.yml` (an older version can be back-published via the `version` input). Never create the release by hand first and leave the ledger entry missing — the workflow is the record
