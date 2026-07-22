# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this plugin repository.

## Project overview

This is a **Claude Code plugin** — **Agent Triforge** — providing a multi-agent coordination framework where Claude Code serves as the **lead agent**, orchestrating Antigravity CLI (binary: `agy`), Codex CLI, and specialized Claude subagents through a hybrid file-based + bash-invocation + native-subagent protocol. The framework is defined in `docs/agent-triforge.md`.

Install: `claude plugin add https://github.com/Ninety2UA/agent-triforge`

## Architecture

### Multi-agent system

- **Claude Code (lead)** — plans work, orchestrates the builder pool, cross-reviews and merges, promotes to the main branch. Also the default builder and a valid reviewer. Runs Fable 5 at `max` effort when the host has it; otherwise latest Opus at `max`
- **Claude specialized agents** — 19 focused subagents (`agents/`): plan validation, review synthesis, security, performance, etc. Shipped frontmatter floors at `opus` — no shipped file names a model a host may lack: team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) ship `model: opus`, `effort: max`; the other 15 ship `model: opus`, `effort: xhigh`
- **Spawn-time Fable override** — when the current probe record (`ops/research/2026-07-probe-record.md`, row CC-02) shows Fable 5 PASS on the host, the lead spawns team-lead and the never-downgrade trio with a model override to `fable` (the Agent tool's `model` parameter)
- **Claude agent teams** — multi-instance collaboration for complex builds (5+ interdependent tasks)
- **Antigravity CLI (`agy`)** — analyst + reviewer: Phase 0 codebase scans (Gemini 3.1 Pro (High), 1M token context), architecture reviews, documentation
- **Codex CLI** — tester + logic reviewer: writes/runs tests, security audits, infrastructure tasks

**Builder pool.** All six supported CLIs — the core trio (Claude, Antigravity, Codex) plus any enrolled optional member (OpenCode, Kimi, Cursor) — are eligible builders; `ops/roster.toml` assigns each role (builder | reviewer | tester | analyst | documenter). The single-writer rule is retired: safety is per-task leases + worktree isolation + mandatory cross-review by a pinned non-author reviewer, not write-restriction. The role bullets above are the shipped default posture (Claude leads builds, Codex reviews and tests, Antigravity analyzes and documents), which `ops/roster.toml` can override. See "Builder-pool wave protocol" below.

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
| `roster.toml` | Role→CLI/model/effort assignment with validated fallback chains (see "Roster and assignment") | User edits; session-start bootstraps; enrollment appends `[members.*]` |
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

Assignment comes from `ops/roster.toml` (`resolve_role <role>`); the defaults below are the shipped posture, not a write-restriction — any roster member can be assigned as builder, and every build merges only after cross-review.

- **Produces code?** → builder role (default Claude; roster-assignable to any member), built under a lease and cross-reviewed before merge
- **Evaluates existing code?** → reviewer role + Claude specialized agents in parallel (default Codex + Antigravity)
- **Runs/executes something?** → tester role (default Codex)
- **Produces documentation?** → documenter role (default Antigravity)
- **Touches shared interfaces?** → builder implements under a lease → pinned non-author reviewer cross-reviews → tester validates
- **Ambiguous?** → the lead takes it as builder, flags for parallel review

### Roster and assignment

`ops/roster.toml` is the single assignment surface: five `[roles.<name>]` tables — builder, reviewer, tester, analyst, documenter (roles ARE the task types) — each carrying `cli`, `model`, `effort`, and an ordered `fallbacks` chain. The file is deliberately CLI-neutral (ops/-level, parsed via python3 `tomllib`) so every adapter can read its own role; `resolve_role <role>` in `scripts/invoke-external.sh` prints `cli<TAB>model<TAB>effort`. Guided edits go through `/setup`'s role step (defaults-or-customize): `roster_role_entry <role>` prints the merged configuration (no liveness walk; its model column follows resolve_role's primary-model rule, so a cli-only override shows what dispatch would actually run) and `roster_write_role <role> <cli> <model> <effort> [fallbacks-csv]` is the single validated writer for `[roles.*]` — it enforces a strict superset of the load rules (known role/CLI and core-trio chain terminus mirrored from load validation, plus writer-only checks: the effort enum and agy effort→(High)/(Low) suffix normalization) and derives a valid fallback chain when none is given (displaced primary becomes first fallback). Roster model overrides reach every external-CLI dispatch lane — the codex lane rides `CODEX_MODEL` into `codex exec -m`, same pattern as `AGY_MODEL`/`OPENCODE_MODEL`/`KIMI_MODEL`/`CURSOR_MODEL`. The claude lane is the deliberate exception: review/test work resolved to claude runs as a native Agent-tool subagent whose model is governed by the Fable/downgrade ladder, not the roster.

- **Resolution order:** `ops/roster.toml` overlays built-in shipped defaults PER-FIELD — a role overriding only `effort` keeps the default cli + model; no roster file at all resolves to the shipped builder-pool posture (defaults are mirrored inside `resolve_role`, kept in sync with `templates/ops/roster.toml`).
- **Fallback chains:** resolution walks the primary `cli`, then `fallbacks` in order; a member is skipped when its binary is absent or its `[members.<cli>]` entry is disabled. Optional-member skips are silent (AE1); core-member skips log a degradation warning. Load-time validation (on every load) requires each chain to terminate at a core-trio member — a chain resolving entirely to optional members is rejected — so the only way a chain exhausts is an absent core-trio terminus, which is a hard error with install guidance (R21).
- **Enabled flag (R38):** `[members.<cli>] enabled = false` means absent everywhere — no dispatches, every role falls back cleanly; re-enabling is the flag flip alone. The core trio (claude, antigravity, codex) cannot be disabled. The shipped template carries NO live `[members.*]` entries, so first-detection enrollment fires and a decline persists as `enabled = false`.
- **Model rules:** agy pins are always `"Gemini 3.1 Pro (High)"`/`(Low)` — never Flash; the (High)/(Low) suffix is agy's effort control, so `effort` maps into the model-variant suffix. Cursor pins `grok-4.5` explicitly — never the Auto router — and has no effort control (`effort` inert). Builder's model is empty by design: the Claude downgrade ladder resolves it. Optional-member fallback models come from `[members.<cli>].model`, else the shipped defaults (opencode → `openrouter/z-ai/glm-5.2`, kimi → `kimi-k3`, cursor → `grok-4.5`).
- **Promotion knob:** `[promotion] require_user_approval` (default `false`) gates wave-end promotion to main (KTD-5); protected-path diffs force approval on regardless — enforced by the wave protocol, not the roster.
- **Lazy liveness:** `ensure_core_trio_live` (non-model `--version` checks, 15s each, success cached per session) runs in the `/build` and `/review` preambles only — never at session start, so a `/status`-only session never triggers it.

### Builder-pool wave protocol

Phase 2 builds run a builder pool: every implementation task — including lead-authored ones — is assigned from `ops/roster.toml`, built under a per-task lease in an isolated worktree, and merged only after cross-review by a pinned non-author reviewer. The single-writer rule is retired; safety is leases + worktree isolation + cross-review. Full mechanics live in the `wave-orchestration` skill ("Builder-pool wave protocol"); the lead drives the lease lifecycle from `scripts/invoke-external.sh`.

- **Assign + lease:** `resolve_role <role>` picks the builder; `lease_create` carves the worktree + `lease/<task>` branch; `lease_dispatch` launches the builder with context injected (task rows, CONTRACTS.md slice, roster entry). Builders commit nothing and never read the canonical `ops/` tree (KTD-3).
- **Collect + pin a reviewer:** `lease_heartbeat_check` → `lease_collect` (state → review). The lead pins a reviewer (`lease_pin_reviewer <task> <reviewer>`) that is a DIFFERENT roster member than the builder (the lead itself is valid); that reviewer stays pinned across all ≤3 fix cycles of the task (KTD-10). If no non-author reviewer is live, the merge blocks and escalates to the user.
- **Merge + attribute:** approved → `lease_merge <task> <reviewer>` lands ONE squash commit per task on the sprint integration branch and records builder + reviewer + merge_commit; it REFUSES self-review (reviewer ≠ `builder_cli` — AE3), an unknown reviewer identity, or a merge with no pin (the pin is the record that a review happened — pin, review, then merge). Findings re-dispatch the same lease/builder with the same pinned reviewer (cycle < 3); at cycle 3 escalate. `ops/CHANGELOG.md` rows carry builder + reviewer + merge commit from the ledger (`lease_status`).
- **Verify + promote:** at wave end `integration-verifier` runs against the integration branch (combined verification across the wave's merged tasks); the lead promotes to the main branch honoring `[promotion] require_user_approval` (default false). Any diff touching protected paths (permission configs, deny rules, `ops/roster.toml` incl. `[promotion]`, shipped agent configs, and the framework's own control-plane code — `scripts/invoke-external.sh`, `scripts/coordinate.sh`, `scripts/probe-capabilities.sh`, hook handlers, `.claude/settings*.json`) forces the promotion gate on and requires the lead or the user as the cross-reviewer — never an external-CLI-only review.

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
- Every implementation task — lead-authored included — is built under a per-task lease and merges only after cross-review by a pinned non-author reviewer; no agent self-merges (AE3). The single-writer rule is retired — any roster member is an eligible builder; safety is leases + worktree isolation + cross-review, not write-restriction
- Approved merges land as one commit per task on the sprint integration branch; the lead promotes to the main branch at wave end honoring `[promotion] require_user_approval` (default false)
- Protected-path diffs (permission configs, deny rules, `ops/roster.toml` incl. `[promotion]`, shipped agent configs, and the framework's own control-plane code — `scripts/invoke-external.sh`, `scripts/coordinate.sh`, `scripts/probe-capabilities.sh`, hook handlers, `.claude/settings*.json`) force the promotion gate on and require the lead or user as the cross-reviewer — never an external-CLI-only review
- Parallel reviews are safe because reviewers write to separate `ops/REVIEW_*.md` files
- Maximum 3 review cycles per task before escalating to user
- Phase 0 can be skipped for small bug fixes, same-session continuations, or unchanged codebases
- Risk scoring: halt subagent at risk >20% or file changes >50
- Completion requires creating the `ops/.sprint-complete` runtime marker, only after the verification checklist passes (never earlier)

### Security model

- **Builder-pool safety model** — the framework runs a builder pool where any roster member can be assigned implementation tasks, so isolation replaces write-restriction as the safety boundary: (1) every non-lead build runs under a per-task lease in an isolated git worktree, confined by a per-adapter env allowlist (KTD-3, KTD-14) — builders never touch the canonical `ops/` tree; (2) the lease ledger `ops/leases.toml` is lead-owned and single-writer; (3) every task merges only after cross-review by a pinned non-author reviewer (AE3, KTD-10), landing as one squash commit per task on a sprint integration branch; (4) the lead promotes to the main branch at wave end honoring the `[promotion]` gate — and any diff touching protected paths (permission configs, deny rules, `ops/roster.toml` incl. `[promotion]`, shipped agent configs, and the framework's own control-plane code — `scripts/invoke-external.sh`, `scripts/coordinate.sh`, `scripts/probe-capabilities.sh`, hook handlers, `.claude/settings*.json`) forces the gate on and requires the lead or user as the reviewer, never an external-CLI-only review; (5) `ops/CHANGELOG.md` attribution carries builder + reviewer + merge commit from the ledger. A roster config can restore the reviewer-only posture (external CLIs off the builder role) for deployments that want it.
- **Provider data egress (R36) + credential handling (KTD-14)** — every dispatched CLI sends its task prompt and the code context it is handed to that CLI's model provider. Under the shipped defaults, code + task context reaches: **Anthropic** (Claude), **Google** (Antigravity → Gemini 3.1 Pro), and **OpenAI** (Codex) for the core trio; and, for any enrolled optional member, **Zhipu / Z.ai** (GLM, routed through the **OpenRouter** intermediary — which also sees the traffic), **Moonshot** (Kimi), and **xAI** (Grok, via Cursor). `ops/roster.toml` is the control surface: disabling a member (`enabled = false`) or dropping a provider's model from every role removes that provider from the egress set (the core trio always stays; chains must still terminate at a core member). Credentials never live in the repo — each adapter reads its own from the OS / vendor store (Claude / Codex / `agy` logins, `OPENROUTER_API_KEY`, `kimi login` OAuth-or-API-key, `cursor-agent login` / `CURSOR_API_KEY`). The lease env allowlist (KTD-14, `_adapter_env`) scopes **environment variables** per-adapter — each optional member is handed only its own provider key (opencode → `OPENROUTER_API_KEY`, kimi → `KIMI_*`, cursor → `CURSOR_API_KEY`), never another member's. It does **not** isolate HOME-based credential *files*: `HOME` is forwarded to every adapter (the core trio authenticate through `~/.claude` / `~/.codex` / `agy`'s HOME store), so a builder shares the invoking user's HOME and could read those files. The enforced confinement boundary is therefore the lease worktree (write scope) + prompt confinement + the env-var allowlist — **not** read-isolation of the user's home credential stores; treat a builder as capable of reading any credential file under `$HOME`. Captured CLI output is scrubbed (`_scrub`) before it lands in `ops/`, and rotation follows each vendor's own token flow (revoke + re-login/re-key, then re-run `/setup`).
- **Codex `approval_policy = "never"`** on all three agents — the framework is designed for trusted pipelines where user approval would block parallel fan-out. `sandbox_mode` (read-only for `logic_reviewer`, `workspace-write` for `test_writer`/`debugger`) plus the per-agent `tools` allowlist provide the actual isolation. If you deploy to an untrusted environment, change to `approval_policy = "on-request"` in `codex-agents/agents.toml`. The no-agent fallback in `scripts/invoke-external.sh` supplies the same defaults explicitly (`-s workspace-write -c approval_policy="never"`) rather than the `--full-auto` shorthand, which Codex has **deprecated** (it still runs but prints a warning; the docs steer new scripts to explicit `--sandbox workspace-write` — corrected from the earlier "removed in v0.128.0" wording per the 2026-07-18 cli-watch primary-source check).
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
opencode-agents/          # OpenCode adapter role briefs (optional tier; prompt-injection)
kimi-agents/              # Kimi Code adapter role briefs (optional tier; prompt-injection)
cursor-agents/            # Cursor adapter role briefs (optional tier; prompt-injection)
skills/                   # 13 portable skill files (all agents consume)
commands/                 # 19 slash commands (adds /setup onboarding + /cli-watch + /repo-watch)
hooks/
  hooks.json              # Hook registration (uses ${CLAUDE_PLUGIN_ROOT})
  handlers/               # Lifecycle hook scripts
    session-start.sh        Session orientation + ops/ + agent bootstrapping
    context-monitor.sh      Warns on analysis paralysis
settings.json             # Default env vars (agent teams)
templates/                # Project bootstrapping templates
  CLAUDE.md                 Template for user projects
  ops/                      Skeleton ops/ files (incl. roster.toml, watch-registry.toml)
  .antigravity/settings.json Antigravity workspace settings (permission deny rules)
  .codex/config.toml        Codex project config (disables Codex's auto-memory pipeline)
  .codex/hooks.json         Codex PostToolUse hook (CHANGELOG attribution under codex exec)
  .codex/README.md          What the hook enforces, why bypass-trust, how to disable
scripts/
  coordinate.sh           # Outer loop for context exhaustion recovery
  invoke-external.sh      # Unified six-CLI invocation, roster resolution, lease lifecycle, feature detection
  probe-capabilities.sh   # Rerunnable capability probe (feeds ops/research/*-probe-record.md)
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
| `watch-cycle` | Claude | CLI/repo watch methodology (research → gap table → adopt/defer ADR) |

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

**Run `/setup` — it is the one guided path** from a fresh install to a working roster (R39/AE8): it gates the core trio live, walks each optional CLI (enroll with a chosen model, or decline cleanly), then offers role assignment — accept the shipped defaults (recommended) or customize any role's CLI · model · effort via `roster_write_role` (`/setup roles` jumps straight to that step). Idempotent and re-runnable. The manual probes below are exactly what `/setup` automates.

**Core trio (required).** All three must be installed and answer a headless READY probe (floors per KTD-13):
```bash
claude --version                                                   # Claude Code ≥ 2.1.212 (session-caps/monitors line; /goal, dynamic workflows, worktree isolation landed earlier)
agy --model "Gemini 3.1 Pro (High)" -p "Respond with only: READY"  # Antigravity ≥ 1.1.3 — always pin the model (agy defaults to a Flash variant)
codex exec "Respond with only: READY"                              # Codex ≥ 0.144.0
```

**Optional tier (enroll via `/setup` when you want them as builders/reviewers).** Each is skipped cleanly in every roster fallback chain when absent:
```bash
opencode run --format json -m openrouter/z-ai/glm-5.2 "Respond with only: READY"  # OpenCode ≥ 1.18 — needs the OpenRouter provider connected (OPENROUTER_API_KEY or `opencode auth login`)
kimi -p "Respond with only: READY"                                                # Kimi Code ≥ 0.15 — OAuth device-code OR API key (`kimi login`)
cursor-agent -p --trust --model grok-4.5 "Respond with only: READY"               # Cursor (date-versioned) — pin grok-4.5, never the Auto router
```

Python 3 is also required (used by hook handlers for JSON parsing):
```bash
python3 --version
```

On macOS, install GNU `coreutils` so `timeout` enforcement works for external invocations (`invoke-external.sh` is fail-closed: without `timeout`/`gtimeout` it refuses to run external invocations at all):
```bash
brew install coreutils
```
`session-start.sh` emits a warning when neither `timeout` nor `gtimeout` is on PATH.

## Compatibility

Re-baselined from the capability probe record `ops/research/2026-07-probe-record.md` (2026-07-17). The framework runs a **core trio** (required) plus an **optional tier** (enroll via `/setup`). This supersedes the old single-line "Tested against Codex 0.130.0 and Gemini 0.41.2" baseline.

| CLI | Tier | Floor (KTD-13) | Tested | READY probe |
|---|---|---|---|---|
| Claude Code (`claude`) | core | ≥ 2.1.212 | 2.1.214 | `claude --version` |
| Antigravity (`agy`) | core | ≥ 1.1.3 | 1.1.4 | `agy --model "Gemini 3.1 Pro (High)" -p "Respond with only: READY"` |
| Codex (`codex`) | core | ≥ 0.144.0 | 0.144.4 | `codex exec "Respond with only: READY"` |
| OpenCode (`opencode`) | optional | ≥ 1.18 | 1.18.3 | `opencode run --format json -m openrouter/z-ai/glm-5.2 "Respond with only: READY"` |
| Kimi Code (`kimi`) | optional | ≥ 0.15 | 0.15 (probe host; near-daily cadence, latest 0.27) | `kimi -p "Respond with only: READY"` |
| Cursor (`cursor-agent`) | optional | date-versioned | 2026.07.16 | `cursor-agent -p --trust --model grok-4.5 "Respond with only: READY"` |

**Minimum supported versions / notes:**
- **Codex ≥ 0.144.0** — `--output-schema` (structured review verdicts), `codex features list` (runtime capability detection); hooks-under-exec verified on 0.144.4. Older versions degrade: `invoke_codex` still runs, but hook enforcement and structured verdicts silently fall back to raw output.
- **Gemini CLI floor removed** — the Gemini lane was replaced by Antigravity (agy ≥ 1.1.3, tested 1.1.3 2026-07-17). Google's hosted Gemini CLI service stopped serving consumer tiers 2026-06-18; legacy Gemini users pin plugin v2.4.3.
- **Optional tier is skip-clean** — an absent or declined optional CLI is silently skipped in every roster fallback chain, which always terminates at a core-trio member; the core trio cannot be disabled.

**Known-fails / partial support:**
- Codex hooks **fire under `codex exec`** as of 0.144.4 (D-004 reversed — probe CDX-04, 2026-07-17: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Stop` all fired), but only with all three preconditions: nested `hooks.json` shape, project-tier `.codex/hooks.json`, and `--dangerously-bypass-hook-trust` (project trust is not persisted for arbitrary dirs; the flag is the documented automation path, and `invoke_codex` passes it only when the project ships `.codex/hooks.json` and `codex features list` reports `hooks` enabled). See `ops/decisions/2026-07-18-codex-hooks-under-exec.md`.
- Antigravity plugin agents are **not surfaced in headless mode** on agy 1.1.3 (`agy agents` stays empty and `--agent` silently ignores unknown names), so `invoke_antigravity` runs in injection mode; project-tier hooks and project-tier permission allow-rules also do not take effect under `agy -p` (probed 2026-07-17) — the `/review` and `/deep-research` commands compensate by promoting captured output into `ops/` when the agent could not write there directly.

### Release checklist

1. `claude plugin validate --strict .` passes green (warnings are errors) — required gate
2. Doc-consistency greps pass (see Verification Contract in the active plan)
3. Ladder byte-identity holds across `agents/team-lead.md`, `skills/wave-orchestration/SKILL.md`, `templates/CLAUDE.md`, and this file
4. Version bumped in `.claude-plugin/plugin.json`; README "Recent changes" entry added
