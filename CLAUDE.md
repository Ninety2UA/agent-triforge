# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this plugin repository.

## Project overview

This is a **Claude Code plugin** — **Agent Triforge** — providing a multi-agent coordination framework where Claude Code serves as the **lead agent**, orchestrating Gemini CLI, Codex CLI, and specialized Claude subagents through a hybrid file-based + bash-invocation + native-subagent protocol. The framework is defined in `docs/agent-triforge.md`.

Install: `claude plugin add https://github.com/Ninety2UA/agent-triforge`

## Architecture

### Multi-agent system

- **Claude Code (Opus max effort)** — lead agent: plans work, builds features, coordinates all agents, merges review feedback
- **Claude specialized agents (Opus max effort)** — 19 focused subagents (`agents/`): plan validation, review synthesis, security, performance, etc. Lead/team-lead may downgrade narrow tasks to Sonnet high effort at runtime.
- **Claude agent teams (Opus max effort)** — multi-instance collaboration for complex builds (5+ interdependent tasks)
- **Gemini CLI** — analyst + reviewer: Phase 0 codebase scans (1M token context), architecture reviews, documentation
- **Codex CLI** — tester + logic reviewer: writes/runs tests, security audits, infrastructure tasks

Claude invokes Gemini via `invoke_gemini` and Codex via `invoke_codex` (from `scripts/invoke-external.sh`) as background bash processes. Skills are embedded in native agent definitions (`gemini-agents/`, `codex-agents/`), with automatic fallback to legacy `$(cat ...)` injection for older CLI versions. Reviews run in parallel (Gemini + Codex + Claude subagents simultaneously), never sequentially.

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
| `RESEARCH_GEMINI.md` | Gemini targeted-research output (temporary) | Gemini writes, Claude reads |
| `TEST_RESULTS.md` | Test results (temporary) | Codex writes, Claude reads |

### Execution phases

The full lifecycle for a goal:

0. **Codebase analysis** — Gemini scans full repo with codebase-mapping skill
1a. **Pre-plan** — learnings-researcher agent searches institutional knowledge
1b. **Planning** — Claude decomposes goal with shadow path tracing, error maps, interface context extraction
1.1. **Ambiguity resolution** — Validate critical assumptions before building
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

### Agent frontmatter fields

Agent definitions in `agents/*.md` support these YAML frontmatter fields:
- `name`, `description` (required) — identity and when-to-use trigger
- `model` — `opus`, `sonnet`, `haiku`, or full model ID. Default: `opus`
- `effort` — `low`, `medium`, `high`, `max` (max is Opus-only). Default: `max`
- `tools` — list of allowed tools (Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, etc.)
- `maxTurns` — maximum agentic turns before the agent stops
- Other: `skills`, `mcpServers`, `hooks`, `memory`, `background`, `isolation`, `color`, `permissionMode`

### Reliability patterns

- **Forced reflection on retry** — agents must self-diagnose before retrying (ship-loop.sh + wave-orchestration)
- **Same-error kill criteria** — 3x same error fingerprint = kill executor + reassign to fresh agent
- **Continuous reviewer** — dedicated per-task reviewer in team builds (1:3-4 ratio with builders)
- **Per-task reflection** — conditional MEMORY.md entries when task took >3 retries, had test failures, or modified >5 files
- **Provenance tracking** — solutions/decisions include sprint_id, task_id, agent, evidence_files, related_decisions

### Hook safety

All 5 hook handlers use `set -euo pipefail`. When using `grep -c`, add `|| true` (not `|| echo "0"`) to prevent script termination on zero matches — `grep -c` already prints `0` to stdout before exiting 1, so `|| echo "0"` duplicates the output and produces a multiline `"0\n0"` value that corrupts downstream display and numeric comparisons.

### Key constraints

- CONTRACTS.md is never modified directly during review — changes must be proposed in MEMORY.md first
- Neither Gemini nor Codex may modify source code; they only write to their designated `ops/` files
- Parallel reviews are safe because agents write to separate files
- Maximum 3 review cycles per sprint before escalating to user
- Phase 0 can be skipped for small bug fixes, same-session continuations, or unchanged codebases
- Risk scoring: halt subagent at risk >20% or file changes >50
- Completion requires `<promise>DONE</promise>` after verification checklist passes

### Security model

- **Codex `approval_policy = "never"`** on all three agents — the framework is designed for trusted pipelines where user approval would block parallel fan-out. `sandbox_mode` (read-only for `logic_reviewer`, `workspace-write` for `test_writer`/`debugger`) plus the per-agent `tools` allowlist provide the actual isolation. If you deploy to an untrusted environment, change to `approval_policy = "on-request"` in `codex-agents/agents.toml`.
- **Codex `tools` allowlist** narrows the tool surface beyond sandbox: `logic_reviewer` has no `write`/`bash`; `test_writer`/`debugger` get both (they need to run tests and reproduce bugs). Defense-in-depth pairs with `sandbox_mode`.
- **Gemini `policies.toml`** enforces shell-command denylists (`rm -rf`, `git push`, `sudo`) and per-agent restrictions (e.g., `architecture-reviewer` is denied `run_shell_command` in addition to omitting it from `tools`).
- **Codex `[agents]` nesting caps** (`max_depth = 2`, `max_threads = 4`) prevent runaway fan-out when `logic_reviewer`/`test_writer` call `spawn_agent` for 5+ file scopes.

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
gemini-agents/            # Gemini CLI native subagent definitions
  codebase-analyst.md       Phase 0 full-repo analysis
  architecture-reviewer.md  Phase 3 architecture review
  targeted-researcher.md    Deep-research targeted analysis
  documentation-writer.md   Documentation specialist
  policies.toml             Policy engine rules (tool restrictions)
codex-agents/             # Codex CLI native agent definitions
  agents.toml               logic_reviewer, test_writer, debugger
skills/                   # 12 portable skill files (all agents consume)
commands/                 # 16 slash commands
hooks/
  hooks.json              # Hook registration (uses ${CLAUDE_PLUGIN_ROOT})
  handlers/               # Lifecycle hook scripts
    session-start.sh        Session orientation + ops/ + agent bootstrapping
    ship-loop.sh            Blocks premature exit during sprints
    context-monitor.sh      Warns on analysis paralysis
settings.json             # Default env vars (agent teams)
templates/                # Project bootstrapping templates
  CLAUDE.md                 Template for user projects
  ops/                      Skeleton ops/ files
scripts/
  coordinate.sh           # Outer loop for context exhaustion recovery
  invoke-external.sh      # Unified Gemini/Codex invocation with feature detection
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

Skills consumed by Gemini/Codex are embedded in their native agent definitions (`gemini-agents/`, `codex-agents/`). The `invoke-external.sh` helper handles feature detection and falls back to legacy `$(cat ...)` injection for older CLI versions.

## Specialized agents

19 agents in `agents/` with restricted tools and focused expertise:

**Core workflow:** plan-checker, findings-synthesizer, integration-verifier, learnings-researcher, team-lead, research-synthesizer, continuous-reviewer

**Review enhancement:** security-sentinel, performance-oracle, code-simplicity-reviewer, convention-enforcer, architecture-strategist, test-gap-analyzer

**Research & verification:** framework-docs-researcher, best-practices-researcher, git-history-analyzer, bug-reproduction-validator, deployment-verifier, pr-comment-resolver

## Agent invocation patterns

Commands invoke Gemini and Codex through the unified helper with feature detection:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Use ${TMPDIR}-scoped, PID+timestamped paths so concurrent runs don't collide.
GEMINI_OUT="${TMPDIR:-/tmp}/gemini_output_$$_$(date +%s).txt"
CODEX_OUT="${TMPDIR:-/tmp}/codex_output_$$_$(date +%s).txt"

# Gemini codebase analysis (uses codebase-analyst agent definition)
invoke_gemini "codebase-analyst" "Analyze codebase..." "$GEMINI_OUT" 600 &
GEMINI_PID=$!

# Codex test writing (uses test_writer agent definition)
invoke_codex "test_writer" "Write tests..." "$CODEX_OUT" 900 &
CODEX_PID=$!

# Per-PID wait — a silent failure in either helper leaves the downstream
# ops/REVIEW_*.md or ops/TEST_RESULTS.md empty and looks like "no findings".
GEMINI_RC=0; CODEX_RC=0
wait $GEMINI_PID || GEMINI_RC=$?
wait $CODEX_PID  || CODEX_RC=$?
[ $GEMINI_RC -ne 0 ] || [ $CODEX_RC -ne 0 ] && { echo "helper failed — gemini=$GEMINI_RC codex=$CODEX_RC" >&2; exit 1; }
```

The helper detects native subagent support at runtime. If available, the CLI loads agent definitions from `.gemini/agents/` or `.codex/agents/` automatically. If not, the helper extracts the agent body and injects it as a prompt prefix (legacy mode).

### External agent definitions

| Definition | CLI | Role |
|---|---|---|
| `gemini-agents/codebase-analyst.md` | Gemini | Phase 0 full-repo analysis |
| `gemini-agents/architecture-reviewer.md` | Gemini | Phase 3 architecture review |
| `gemini-agents/targeted-researcher.md` | Gemini | Deep-research targeted analysis |
| `gemini-agents/documentation-writer.md` | Gemini | Documentation generation |
| `codex-agents/agents.toml → logic_reviewer` | Codex | Phase 3 logic + security review |
| `codex-agents/agents.toml → test_writer` | Codex | Phase 5 TDD test writing |
| `codex-agents/agents.toml → debugger` | Codex | Bug investigation |

Claude invokes Gemini via `invoke_gemini` and Codex via `invoke_codex` as background bash processes. Agent definitions are copied to `.gemini/agents/` and `.codex/agents/` in user projects at session start. Reviews run in parallel (Gemini + Codex + Claude subagents simultaneously), never sequentially.

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

Python 3 is also required (used by hook handlers for JSON parsing):
```bash
python3 --version
```

On macOS, install GNU `coreutils` so `timeout` enforcement works for Gemini/Codex invocations (`invoke-external.sh` otherwise falls back to a no-timeout exec):
```bash
brew install coreutils
```
`session-start.sh` emits a warning when neither `timeout` nor `gtimeout` is on PATH.
