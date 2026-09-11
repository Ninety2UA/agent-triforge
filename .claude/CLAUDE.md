# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this plugin repository.

## Project overview

This is a **Claude Code plugin** — **Agent Triforge** — providing a multi-agent coordination framework where Claude Code serves as the **lead agent**, orchestrating Antigravity CLI (binary: `agy`), Codex CLI, and specialized Claude subagents through a hybrid file-based + bash-invocation + native-subagent protocol. The framework is defined in `docs/agent-triforge.md`.

Install: `claude plugin add https://github.com/Ninety2UA/agent-triforge`

## Architecture

### Multi-agent system

- **Claude Code (lead)** — plans work, orchestrates the builder pool, cross-reviews and merges, promotes to the main branch. Also the default builder and a valid reviewer. Runs Fable 5.1 (the `fable` alias, Claude Code ≥ 2.1.257) at `max` effort when the host has it; otherwise Opus 5 (`opus`) at `max`
- **Claude specialized agents** — 19 focused subagents (`agents/`): plan validation, review synthesis, security, performance, etc. Shipped frontmatter floors at `opus` — no shipped file names a model a host may lack: team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) ship `model: opus`, `effort: max`; the other 15 ship `model: opus`, `effort: xhigh`
- **Spawn-time Fable override** — when the newest `ops/research/*-probe-record.md` (`latest_probe_record` in `scripts/invoke-external.sh`), row CC-02, shows Fable PASS on the host, the lead spawns team-lead and the never-downgrade trio with a model override to `fable` (the Agent tool's `model` parameter)
- **Claude agent teams** — multi-instance collaboration for complex builds (5+ interdependent tasks)
- **Antigravity CLI (`agy`)** — analyst + reviewer: Phase 0 codebase scans (Gemini 3.8 Flash (High) by default — the newest Gemini at its highest thinking level, D-022; the roster opt-in is 3.1 Pro (High); 1M token context), architecture reviews, documentation
- **Codex CLI** — tester + logic reviewer: writes/runs tests, security audits, infrastructure tasks

**Builder pool.** All six supported CLIs — the core trio (Claude, Antigravity, Codex) plus any enrolled optional member (OpenCode, Kimi, Cursor) — are eligible builders; `ops/roster.toml` assigns each role (builder | reviewer | tester | analyst | documenter). The single-writer rule is retired: safety is per-task leases + worktree isolation + mandatory cross-review by a pinned non-author reviewer, not write-restriction. The role bullets above are the shipped default posture (Claude leads builds, Codex reviews and tests, Antigravity analyzes and documents), which `ops/roster.toml` can override. See "Builder-pool wave protocol" below.

For narrow, rubric-following runtime tasks the lead/team-lead may step down one tier at a time:

Downgrade ladder for narrow runtime tasks: `fable`+`max` (lead + never-downgrade tier when available; otherwise latest `opus` at `max` — the model steps down, the effort does not) → `opus` (Opus 5) + `xhigh` → `opus`+`high` → `sonnet` (Sonnet 5) + `high`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.

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

`ops/roster.toml` is the single assignment surface: five `[roles.<name>]` tables — builder, reviewer, tester, analyst, documenter (roles ARE the task types) — each carrying `cli`, `model`, `effort`, and an ordered `fallbacks` chain. The file is deliberately CLI-neutral (ops/-level, parsed via python3 `tomllib`) so every adapter can read its own role; `resolve_role <role>` in `scripts/invoke-external.sh` prints `cli<TAB>model<TAB>effort`. Guided edits go through `/setup`'s role step (defaults-or-customize): `roster_role_entry <role>` prints the merged configuration (no liveness walk; its model column follows resolve_role's primary-model rule, so a cli-only override shows what dispatch would actually run) and `roster_write_role <role> <cli> <model> <effort> [fallbacks-csv]` is the single validated writer for `[roles.*]` — it enforces a strict superset of the load rules (known role/CLI and core-trio chain terminus mirrored from load validation, plus writer-only checks: the effort enum, the agy effort→`(Low)`/`(Medium)`/`(High)` suffix normalization, and the Cursor effort→`-low|-medium|-high|-xhigh` model-id suffix) and derives a valid fallback chain when none is given (displaced primary becomes first fallback). Roster model overrides reach every external-CLI dispatch lane — the codex lane rides `CODEX_MODEL` into `codex exec -m`, same pattern as `AGY_MODEL`/`OPENCODE_MODEL`/`KIMI_MODEL`/`CURSOR_MODEL`. The claude lane is the deliberate exception: review/test work resolved to claude runs as a native Agent-tool subagent whose model is governed by the Fable/downgrade ladder, not the roster.

- **Resolution order:** `ops/roster.toml` overlays built-in shipped defaults PER-FIELD — a role overriding only `effort` keeps the default cli + model; no roster file at all resolves to the shipped builder-pool posture (defaults are mirrored inside `resolve_role`, kept in sync with `templates/ops/roster.toml`).
- **Fallback chains:** resolution walks the primary `cli`, then `fallbacks` in order; a member is skipped when its binary is absent or its `[members.<cli>]` entry is disabled. Optional-member skips are silent (AE1); core-member skips log a degradation warning. Load-time validation (on every load) requires each chain to terminate at a core-trio member — a chain resolving entirely to optional members is rejected — so the only way a chain exhausts is an absent core-trio terminus, which is a hard error with install guidance (R21).
- **Enabled flag (R38):** `[members.<cli>] enabled = false` means absent everywhere — no dispatches, every role falls back cleanly; re-enabling is the flag flip alone. The core trio (claude, antigravity, codex) cannot be disabled. The shipped template carries NO live `[members.*]` entries, so first-detection enrollment fires and a decline persists as `enabled = false`.
- **Model rules:** agy pins the newest Gemini model at its highest thinking level, Pro or Flash (D-022) — currently `"Gemini 3.8 Flash (High)"`; the 3.1 Pro line (`"Gemini 3.1 Pro (Low|High)"`) is the documented per-role opt-in. The `(Low)`/`(Medium)`/`(High)` suffix is agy's effort control, so `effort` maps into the model-variant suffix (`roster_write_role` normalizes low→Low, medium→Medium, high/xhigh/max→High; 3.1 Pro has no Medium, so medium collapses to Low with a NOTE). Cursor pins `cursor-grok-4.6-xhigh` explicitly — never the Auto router; effort rides in the model-id suffix (`cursor-grok-4.6-low|medium|high|xhigh` — the bracket form `grok-4.6[effort=xhigh]` is rejected headless, CUR-10), the writer composes the suffix from a bare `grok-4.6` plus the role effort, and an explicit suffixed id passes through unchanged. The Cursor binary is `cursor-agent` first; `agent` is accepted only when its `--version` matches `YYYY.MM.DD-<hex>` (`_cursor_bin`). Builder's model is empty by design: the Claude downgrade ladder resolves it. Optional-member fallback models come from `[members.<cli>].model`, else the shipped defaults (opencode → `openrouter/z-ai/glm-5.3`, kimi → `kimi-code/k3`, cursor → `cursor-grok-4.6-xhigh`).
- **Promotion knob:** `[promotion] require_user_approval` (default `false`) gates wave-end promotion to main (KTD-5); protected-path diffs force approval on regardless — enforced by the wave protocol, not the roster.
- **Lazy liveness:** `ensure_core_trio_live` (non-model `--version` checks, 15s each, success cached per session) runs in the `/build` and `/review` preambles only — never at session start, so a `/status`-only session never triggers it.

### Builder-pool wave protocol

Phase 2 builds run a builder pool: every implementation task — including lead-authored ones — is assigned from `ops/roster.toml`, built under a per-task lease in an isolated worktree, and merged only after cross-review by a pinned non-author reviewer. The single-writer rule is retired; safety is leases + worktree isolation + cross-review. Full mechanics live in the `wave-orchestration` skill ("Builder-pool wave protocol"); the lead drives the lease lifecycle from `scripts/invoke-external.sh`.

- **Assign + lease:** `resolve_role <role>` picks the builder; `lease_create` carves the worktree + `lease/<task>` branch; `lease_dispatch` launches the builder with context injected (task rows, CONTRACTS.md slice, roster entry). Builders commit nothing and never read the canonical `ops/` tree (KTD-3).
- **Dispatch contract + completion signal (KTD11):** every lease carries one contract block, CLI-neutral, prepended by `lease_dispatch` before the `env -i` boundary — no sub-dispatch, git stays local (never `push`/`pull`/`fetch`), and a typed final report ending in `Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT` with commits, a one-line test summary, concerns, and "Discoveries for later tasks (or None)". `lease_collect` parses the Status line into the ledger's `report_status`: DONE and DONE_WITH_CONCERNS route to review (discoveries copied into `ops/MEMORY.md` by the lead); BLOCKED and NEEDS_CONTEXT route to escalated, never review; a clean exit with no Status line is "report missing" (rc 80, `_RC_DEGRADED`; the lease stays building) — re-dispatch once with the contract restated, escalate on the second miss. agy leases additionally surface the JSON envelope's `status` and `denied_actions` (KTD2).
- **Collect + pin a reviewer:** `lease_heartbeat_check` → `lease_collect` (typed report → review). The lead pins a reviewer (`lease_pin_reviewer <task> <reviewer>`) that is a DIFFERENT roster member than the builder (the lead itself is valid); that reviewer stays pinned across all ≤3 fix cycles of the task (KTD-10). If no non-author reviewer is live, the merge blocks and escalates to the user.
- **Merge + attribute:** approved → `lease_merge <task> <reviewer>` lands ONE squash commit per task on the sprint integration branch and records builder + reviewer + merge_commit; it REFUSES self-review (reviewer ≠ `builder_cli` — AE3), an unknown reviewer identity, or a merge with no pin (the pin is the record that a review happened — pin, review, then merge). Findings re-dispatch the same lease/builder with the same pinned reviewer (cycle < 3); at cycle 3 escalate. `ops/CHANGELOG.md` rows carry builder + reviewer + merge commit from the ledger (`lease_status`).
- **Verify + promote:** at wave end `integration-verifier` runs against the integration branch (combined verification across the wave's merged tasks); the lead promotes to the main branch honoring `[promotion] require_user_approval` (default false). Any diff touching protected paths (permission configs, deny rules, `ops/roster.toml` incl. `[promotion]`, shipped agent configs, and the framework's own control-plane code — `scripts/invoke-external.sh`, `scripts/coordinate.sh`, `scripts/probe-capabilities.sh`, hook handlers, `.claude/settings*.json`) forces the promotion gate on and requires the lead or the user as the cross-reviewer — never an external-CLI-only review.

### Agent frontmatter fields

Agent definitions in `agents/*.md` support these YAML frontmatter fields (verified against the official docs 2026-09-11):
- `name`, `description` (required) — identity and when-to-use trigger
- `model` — `fable`, `opus`, `sonnet`, `haiku`, a full model ID, or `inherit`. Shipped Triforge agents floor at `opus`; the lead applies the spawn-time `fable` override (see the ladder above)
- `effort` — `low`, `medium`, `high`, `xhigh`, `max` (`max` supported on Fable 5.1, Opus 5, and Sonnet 5); honored on pinned-default models only from Claude Code 2.1.267 — hence the floor
- `tools` — allowlist of tools (Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, etc.); `disallowedTools` is the deny-side counterpart
- `maxTurns` — maximum agentic turns before the agent stops
- `initialPrompt` — new: auto-submitted first turn when the agent runs as the main session via `--agent`
- `experimental` — a map; its `cacheTtl` key (`5m` or `1h`) sets the prompt-cache lifetime for the subagent's requests (Claude Code ≥ 2.1.248; read only from subagent files; `1h` is ignored while a subscription runs on usage credits). No Triforge agent sets it
- Other top-level fields: `skills`, `memory`, `background`, `isolation` (accepts only `"worktree"`), `color`
- **Plugin restriction:** plugin-shipped agents do not support `permissionMode`, `hooks`, or `mcpServers` (security restriction — those three apply only to user- and project-level agent files); no Triforge agent carries them

Antigravity and Codex agent files use their CLIs' own conventions: Antigravity (`antigravity-agents/agents/*.md`) uses the agy Markdown-agent frontmatter (`mainAgent`, `subagent`, `commandExecutionPolicy`, `model: inherit` — the dispatch `--model` governs) with `tools` in agy's own vocabulary (`view_file`, `list_dir`, `find_by_name`, `grep_search`, `write_to_file`, `run_command`, `read_url_content`, `search_web`); Codex (`codex-agents/agents.toml`, deployed as `.codex/triforge-agents.toml`) uses `model_reasoning_effort`, `sandbox_mode`, `approval_policy`, and a `tools` list that is a Triforge-internal allowlist declaration (Codex never reads the file — `invoke_codex` replays the keys as `codex exec` flags and carries the allowlist in the developer instructions).

### Reliability patterns

- **Forced reflection on retry** — agents must self-diagnose before retrying (wave-orchestration; workflow requeue prepends the reflection questions)
- **Same-error kill criteria** — 3x same error fingerprint = kill executor + reassign to fresh agent
- **Continuous reviewer** — dedicated per-task reviewer in team builds (1:3-4 ratio with builders)
- **Per-task reflection** — conditional MEMORY.md entries when task took >3 retries, had test failures, or modified >5 files
- **Provenance tracking** — solutions/decisions include sprint_id, task_id, agent, evidence_files, related_decisions

### Hook safety

All 4 hook handlers use `set -euo pipefail`. When using `grep -c`, add `|| true` (not `|| echo "0"`) to prevent script termination on zero matches — `grep -c` already prints `0` to stdout before exiting 1, so `|| echo "0"` duplicates the output and produces a multiline `"0\n0"` value that corrupts downstream display and numeric comparisons.

- **`ON_CRASH` declaration (G7):** every handler's header declares `ON_CRASH: ALLOW` and installs an EXIT trap that turns an unexpected non-zero status into a stderr notice + `exit 0` — a crashed hook must never block the session, the tool call, or compaction. Degraded states are reported as notices, never as exit codes.
- **Exit-code vocabulary:** `0` ok · `2` hook deny · `64` usage · `66` no-input · `69` unavailable · `70` internal · `80` degraded. Documented in each header for readers — Triforge handlers always return `0`.
- **Hook stdout must never start with `{`:** Claude Code ≥ 2.1.246 treats hook stdout that looks like JSON as a structured hook result and rejects malformed JSON as a hook error (D-031c). Every stdout line stays prose; captured external-CLI output (`agy plugin list`, `agy agents`) is consumed inside the handler and never echoed.
- **Bash 3.2:** hooks run under macOS `/bin/bash` 3.2 — no associative arrays, no `mapfile`, no `"${arr[@]}"` expansion of a possibly-empty array under `set -u`, no other bash-4 features.

### Key constraints

- CONTRACTS.md is never modified directly during review — changes must be proposed in MEMORY.md first
- Every implementation task — lead-authored included — is built under a per-task lease and merges only after cross-review by a pinned non-author reviewer; no agent self-merges (AE3). The single-writer rule is retired — any roster member is an eligible builder; safety is leases + worktree isolation + cross-review, not write-restriction
- Every dispatched builder receives the same contract (no sub-dispatch, git stays local, a typed `Status:` report); a bare exit 0 is never review-ready — a missing report is "report missing" (rc 80), not "no findings" (see "Dispatch contract + completion signal")
- Approved merges land as one commit per task on the sprint integration branch; the lead promotes to the main branch at wave end honoring `[promotion] require_user_approval` (default false)
- Protected-path diffs (permission configs, deny rules, `ops/roster.toml` incl. `[promotion]`, shipped agent configs, and the framework's own control-plane code — `scripts/invoke-external.sh`, `scripts/coordinate.sh`, `scripts/probe-capabilities.sh`, hook handlers, `.claude/settings*.json`) force the promotion gate on and require the lead or user as the cross-reviewer — never an external-CLI-only review
- Parallel reviews are safe because reviewers write to separate `ops/REVIEW_*.md` files
- Maximum 3 review cycles per task before escalating to user
- Phase 0 can be skipped for small bug fixes, same-session continuations, or unchanged codebases
- Risk scoring: halt subagent at risk >20% or file changes >50
- Completion requires creating the `ops/.sprint-complete` runtime marker, only after the verification checklist passes (never earlier)

### Security model

- **Builder-pool safety model** — the framework runs a builder pool where any roster member can be assigned implementation tasks, so isolation replaces write-restriction as the safety boundary: (1) every non-lead build runs under a per-task lease in an isolated git worktree, confined by a per-adapter env allowlist (KTD-3, KTD-14) — builders never touch the canonical `ops/` tree; (2) the lease ledger `ops/leases.toml` is lead-owned and single-writer; (3) every task merges only after cross-review by a pinned non-author reviewer (AE3, KTD-10), landing as one squash commit per task on a sprint integration branch; (4) the lead promotes to the main branch at wave end honoring the `[promotion]` gate — and any diff touching protected paths (permission configs, deny rules, `ops/roster.toml` incl. `[promotion]`, shipped agent configs, and the framework's own control-plane code — `scripts/invoke-external.sh`, `scripts/coordinate.sh`, `scripts/probe-capabilities.sh`, hook handlers, `.claude/settings*.json`) forces the gate on and requires the lead or user as the reviewer, never an external-CLI-only review; (5) `ops/CHANGELOG.md` attribution carries builder + reviewer + merge commit from the ledger. A roster config can restore the reviewer-only posture (external CLIs off the builder role) for deployments that want it.
- **Provider data egress (R36) + credential handling (KTD-14)** — every dispatched CLI sends its task prompt and the code context it is handed to that CLI's model provider. Under the shipped defaults, code + task context reaches: **Anthropic** (Claude), **Google** (Antigravity → Gemini 3.8 Flash), and **OpenAI** (Codex) for the core trio; and, for any enrolled optional member, **Zhipu / Z.ai** (GLM, routed through the **OpenRouter** intermediary — which also sees the traffic), **Moonshot** (Kimi), and **xAI** (Grok, via Cursor). `ops/roster.toml` is the control surface: disabling a member (`enabled = false`) or dropping a provider's model from every role removes that provider from the egress set (the core trio always stays; chains must still terminate at a core member). Credentials never live in the repo — each adapter reads its own from the OS / vendor store (Claude / Codex / `agy` logins, `OPENROUTER_API_KEY`, `kimi login` OAuth-or-API-key, `cursor-agent login` / `CURSOR_API_KEY`). The lease env allowlist (KTD-14, `_adapter_env`) scopes **environment variables** per-adapter — each optional member is handed only its own provider key (opencode → `OPENROUTER_API_KEY`, kimi → `KIMI_*`, cursor → `CURSOR_API_KEY`), never another member's. It does **not** isolate HOME-based credential *files*: `HOME` is forwarded to every adapter (the core trio authenticate through `~/.claude` / `~/.codex` / `agy`'s HOME store), so a builder shares the invoking user's HOME and could read those files. The enforced confinement boundary is therefore the lease worktree (write scope) + prompt confinement + the env-var allowlist — **not** read-isolation of the user's home credential stores; treat a builder as capable of reading any credential file under `$HOME`. Captured CLI output is scrubbed (`_scrub`) before it lands in `ops/`, and rotation follows each vendor's own token flow (revoke + re-login/re-key, then re-run `/setup`).
- **Codex `approval_policy = "never"`** on all three agents — the framework is designed for trusted pipelines where user approval would block parallel fan-out. `sandbox_mode` (read-only for `logic_reviewer`, `workspace-write` for `test_writer`/`debugger`) plus `approval_policy` are the enforced isolation (KTD5). If you deploy to an untrusted environment, change to `approval_policy = "on-request"` in `codex-agents/agents.toml`. The no-agent fallback in `scripts/invoke-external.sh` supplies the same defaults explicitly (`-s workspace-write -c approval_policy="never"`) — the `--full-auto` shorthand was **removed in Codex 0.147.0** (D-026; `error: unexpected argument` on 0.154.0), so the helper never passes it.
- **Codex `tools` allowlist and `[agents]` caps are Triforge-internal declarations** (KTD5) — `codex-agents/agents.toml` is parsed only by `invoke_codex`, which replays `model`, `model_reasoning_effort`, `sandbox_mode`, `approval_policy`, and `output_schema` as `codex exec` flags and carries the per-agent `tools` list (`logic_reviewer` has no `write`/`bash`; `test_writer`/`debugger` get both, since they run tests and reproduce bugs) inside the developer instructions. Codex itself never reads the file, so the allowlist and the caps are instructions to the model, not enforced config; the enforced isolation is `sandbox_mode` + `approval_policy`.
- **Antigravity permission guardrails** — `antigravity-agents/permissions.json` documents the three denies in agy's action syntax — `command(rm -rf)`, `command(git push)`, `command(sudo)` — and `templates/.antigravity/settings.json` ships them as a mergeable `permissions` block (deny intent). Project-tier settings.json is **not read headless** (`.gemini/`, `.agents/`, `.antigravity/` — probed 2026-07-17, re-confirmed 2026-09-11); the only tier agy enforces headless is the user tier `~/.gemini/antigravity-cli/settings.json`, which Triforge never writes (R18). Project-tier hooks **fired on agy 1.2.0** (lead marker-file re-probe 2026-09-11 05:03, documented `.agents/hooks.json` named-hook shape, `--add-dir` bound — the July "inert headless" reading was a probe-shape error), but the harness re-run the same evening on **agy 1.2.1** recorded AGY-08 **FAIL** with both hooks.json files loaded (`agy -p /hooks` lists them; no handler executes) — treat headless agy hooks as an open watch, not an enforcement path; Triforge ships no agy hooks and relies on none (AGY-08). The per-agent `tools` allowlist + `commandExecutionPolicy` in `antigravity-agents/agents/*.md` is the primary guardrail in every mode (`architecture-reviewer` and `documentation-writer` carry `commandExecutionPolicy: "off"` and omit `run_command` — the omission is the denial). In injection mode (`TRIFORGE_AGY_MODE=injection`, the shipped default — KTD10) agy's headless permission auto-deny still applies and denials surface in the JSON envelope; in native mode (`native`, or `auto` when `agy agents` lists the name) the two `commandExecutionPolicy: auto` agents run `run_command` live and their enforced boundary is the user-tier deny list — which `/setup` documents and only the user writes.
- **Antigravity headless completion signal (D-032/KTD2)** — `invoke_antigravity` runs `--output-format json` and reads the envelope instead of the exit code (since agy 1.1.20/1.1.28 benign tool errors and `--print-timeout` expiry exit 0, and a denied tool leaves `status: SUCCESS` with an empty `response`). `_agy_parse_envelope` writes the prose `response` to the output file and the `status`, `denied_actions`, and resolved `mode` to the `<out>.status`, `<out>.denied`, `<out>.mode` sidecars (background call sites cannot read a shell variable). An empty `response` with `denied_actions` is a deterministic failure whose message names the user-tier allow rule the run needs — `permissions.allow: ["read_url(*)"]` in `~/.gemini/antigravity-cli/settings.json` for the research lanes (a broad grant; human-written, never by Triforge). A non-empty response with denials still succeeds; the promoted `ops/` file gets an HTML-comment header listing them and the mode. Write denials against `ops/` are never fatal (`/review` and `/deep-research` promote captured output).
- **Codex `[agents]` caps** (`max_depth = 2`, `max_threads = 4`, `default_subagent_model`/`default_subagent_reasoning_effort`) are Triforge-internal declarations of the intended fan-out (one spawn round, no spawn-of-spawn, every spawn pinned to the shipped model + effort); nothing replays them as `-c` overrides yet (deferred). `max_depth` is honored only by the V1 multi-agent runtime — `gpt-6-astra` runs `multi_agent_v2` by catalog and ignores it — and `job_max_runtime_seconds` is a no-op on current Codex (D-026).
- **Codex auto-memory disabled by default** — Triforge ships `templates/.codex/config.toml` with `[memories] use_memories = false` to prevent Codex's v0.129.0 pipeline from writing `~/.codex/memories/{MEMORY.md, skills/, ...}` in parallel with Triforge's `ops/MEMORY.md` and `ops/solutions/`. Users who want Codex memories can remove the block or override in `~/.codex/config.toml`. The project `.codex/config.toml` applies only in a **trusted** project: Codex ≥ 0.147 skips project-tier `config.toml`/`hooks.json`/`.rules` (and project `AGENTS.md` since 0.150) under `exec` when the project is untrusted — unset means untrusted, and `exec` never prompts. The durable path is a user-tier entry `[projects."<abs path>"] trust_level = "trusted"` in `~/.codex/config.toml`, which `/setup` detects and prints but never writes (R18); linked worktrees inherit the root checkout's trust.
- **Antigravity skills interop** — `hooks/handlers/session-start.sh` copies `skills/` to `.agents/skills/` (the Antigravity workspace-skills tier and the cross-CLI agentskills.io path, read by agy, Codex, OpenCode, Cursor, and Kimi — not Claude Code) so those CLIs pick up Triforge's portable skills without per-prompt `$(cat ...)` injection. The copy is refreshed on plugin version change under a stamp (`.agents/skills/.triforge-plugin-version`, written last, safe to commit): shipped-name directories are Triforge-owned and overwritten; user customizations belong in a differently named directory, which the refresh never touches (KTD7). Project-tier agy hooks: fired on agy 1.2.0, FAIL again on 1.2.1 the same day (AGY-08 — open watch); Triforge ships none; the retired Gemini hooks example was removed with the Gemini lane.

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
codex-agents/             # Codex CLI agent definitions (Triforge-internal; parsed by invoke_codex, never by Codex)
  agents.toml               logic_reviewer, test_writer, debugger — deployed as .codex/triforge-agents.toml (never .codex/agents/)
  review-verdict.schema.json Structured review verdict (--output-schema, logic_reviewer; resolved at the plugin tier)
opencode-agents/          # OpenCode adapter role briefs (optional tier; prompt-injection)
kimi-agents/              # Kimi Code native agent definitions (optional tier; loaded via --agent-file, ${base_prompt} embedded)
cursor-agents/            # Cursor adapter role briefs (optional tier; prompt-injection)
skills/                   # 12 portable skill files (all agents consume)
commands/                 # 17 slash commands (adds /setup onboarding)
hooks/
  hooks.json              # Hook registration (uses ${CLAUDE_PLUGIN_ROOT})
  handlers/               # Lifecycle hook scripts (ON_CRASH: ALLOW; always exit 0)
    session-start.sh        Session orientation + ops/ bootstrap + upgrade migration (skills stamp, agy pack, Codex file move)
    context-monitor.sh      Warns on analysis paralysis
    pre-compact.sh          STATE.md checkpoint before context compaction
    tool-failure-monitor.sh Consecutive / total tool-failure thresholds
settings.json             # Default env vars (agent teams; CLAUDE_CODE_ENABLE_TODO_TOOLS for shared task lists)
templates/                # Project bootstrapping templates
  CLAUDE.md                 Template for user projects
  ops/                      Skeleton ops/ files (incl. roster.toml)
  .antigravity/settings.json Antigravity workspace settings (deny intent in command(...) syntax; user tier enforces)
  .codex/config.toml        Codex project config (disables Codex's auto-memory pipeline; read only in a trusted project)
  .codex/hooks.json         Codex PostToolUse hook (CHANGELOG attribution under codex exec)
  .codex/README.md          Deploy name (triforge-agents.toml), project-trust paths (D-026), --full-auto removal, hook on/off
scripts/
  coordinate.sh           # Outer loop for context exhaustion recovery
  invoke-external.sh      # Unified six-CLI invocation, roster resolution, lease lifecycle, feature detection
  probe-capabilities.sh   # Rerunnable capability probe (writes the date-stamped ops/research/<YYYY-MM>-probe-record.md)
  validate-skills.sh      # Release gate: skill frontmatter / "Use when" / ## Output structure checks
  validate-versions.sh    # Release gate: version lockstep, ladder md5 ×4, DEFAULTS drift, scoped stale-pin sweep, surface counts
.github/
  PULL_REQUEST_TEMPLATE.md # PR template (S20): evidence table + validator results
ops/                      # This repo's own project state (not part of plugin)
  watch-registry.toml       Watch targets for the repo-local /cli-watch + /repo-watch cycle
.claude/                  # This repo's own Claude Code project config (not part of plugin)
  commands/                 /cli-watch + /repo-watch — framework self-maintenance, run from this checkout only
  skills/watch-cycle/       Shared methodology for the two watch commands
docs/                     # Framework design documentation
```

## Framework self-maintenance (repo-local, not shipped)

`/cli-watch` and `/repo-watch` keep Triforge current against its six CLIs and four reference repos. They are maintainer tooling for THIS checkout — project-local commands in `.claude/commands/`, backed by `.claude/skills/watch-cycle/SKILL.md` and the tracked registry `ops/watch-registry.toml`. None of the three is part of the plugin: `commands/`, `skills/`, and `templates/ops/` ship without them, and `session-start.sh` never bootstraps the registry into user projects. Claude Code discovers `.claude/commands/` automatically when run from the repo root; schedule monthly via `/schedule`.

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

Skills consumed by Antigravity/Codex are embedded in their native agent definitions (`antigravity-agents/agents/`, `codex-agents/`). The `invoke-external.sh` helper handles feature detection and falls back to prompt-prefix injection when native agent routing isn't available. The `.agents/skills/` workspace copy is refreshed on plugin version change (stamp `.agents/skills/.triforge-plugin-version`; shipped-name directories are overwritten — keep customizations in a differently named directory).

### Where each CLI finds skills and commands (six-harness matrix, 2026-09-11)

Fixture evidence from `ops/research/2026-09-11-cli-updates.md` §3.1 — a uniquely named `SKILL.md` planted in every candidate path, each CLI asked headless what it sees (Kimi from its docs: AUTH-FAIL on the probe host):

| Path | Claude Code 2.1.268 | agy 1.2.0 | Codex 0.154.0 | OpenCode 1.18.30 | Cursor 2026.09.10 | Kimi 0.42.0 (docs) |
|---|---|---|---|---|---|---|
| `.agents/skills/` (Triforge's session-start copy) | ✗ ("Unknown command") | ✓ (only with the workspace bound: `--add-dir` or trusted) | ✓ | ✓ | ✓ | ✓ |
| `.claude/skills/` | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ |
| `.codex/skills/` | ✗ | ✗ | ✓ (undocumented) | ✗ | ✓ | ✗ |
| `.opencode/skill/` + `skills/` | ✗ | ✗ | ✗ | ✓ both | ✗ | ✗ |
| `.cursor/skills/` | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| `.kimi-code/skills/` | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |

Claude Code is the one CLI that does **not** read `.agents/skills/` — it reads the plugin's `skills/` and `.claude/skills/`. Invocation forms per harness (verified live 2026-09-11 except Kimi):

| CLI | Skill invocation | Commands |
|---|---|---|
| Claude Code | `/name` (plugin skill or `.claude/skills/`) | `.claude/commands/` ≡ skills; Triforge's 17 commands are lead-only |
| agy | `agy --add-dir "$PWD" -p "/name"` (headless expansion since 1.1.9; `agy -p "/skills"` lists them with no model call) | skills ARE the slash commands |
| Codex | `$name` in the `codex exec` prompt | custom prompts are deprecated and **not expanded under `exec`** (the model searched the tree instead) — no portable commands |
| OpenCode | `/name` → native `skill` tool | `opencode run --command <name>` from `.opencode/command/` (or `commands/`) |
| Cursor | `/name` in `-p` (also by bare name) | `.cursor/commands/` + `/name` in `-p` |
| Kimi | `/skill:name` | headless expansion undocumented (PENDING-AUTH) |

Rules: **agent definitions are never deployed into `.agents/agents/`** — agy and Kimi both scan that directory with incompatible tool vocabularies, so agy stays on `agy plugin install` of `antigravity-agents/` and Kimi loads `kimi-agents/*.md` through `--agent-file` (KTD13). Slash commands stay per-harness; only skills are portable.

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

The helper's Antigravity routing is governed by `TRIFORGE_AGY_MODE` (`injection` | `native` | `auto`; default `injection` this release — KTD10). `native` passes `--agent <name>` when `agy agents` lists the name and warns + falls back to injection when it does not; `auto` selects native only when the name is listed; `injection` (the shipped default) extracts the agent body from `antigravity-agents/agents/<name>.md` and injects it as a prompt prefix. The resolved mode is written to `<out>.mode` and into the promoted `ops/REVIEW_ANTIGRAVITY.md` / `ops/RESEARCH_ANTIGRAVITY.md` header so a behavior change is attributable. The pack is reinstalled on version change by session start (`agy plugin install`, KTD8); the default flips to `auto` only after AGY-12 (native round-trip) and AGY-16 (native-mode negative) have passed for a full cycle. Codex agents load from `.codex/triforge-agents.toml` (project copy first, then the plugin's `codex-agents/agents.toml`).

### External agent definitions

| Definition | CLI | Role |
|---|---|---|
| `antigravity-agents/agents/codebase-analyst.md` | Antigravity | Phase 0 full-repo analysis |
| `antigravity-agents/agents/architecture-reviewer.md` | Antigravity | Phase 3 architecture review |
| `antigravity-agents/agents/targeted-researcher.md` | Antigravity | Deep-research targeted analysis |
| `antigravity-agents/agents/documentation-writer.md` | Antigravity | Documentation generation |
| `codex-agents/agents.toml → logic_reviewer` (deployed as `.codex/triforge-agents.toml`) | Codex | Phase 3 logic + security review |
| `codex-agents/agents.toml → test_writer` | Codex | Phase 5 TDD test writing |
| `codex-agents/agents.toml → debugger` | Codex | Bug investigation |

Claude invokes Antigravity via `invoke_antigravity` and Codex via `invoke_codex` as background bash processes. At session start, Codex definitions are copied to `.codex/triforge-agents.toml` in user projects (a pre-3.3.0 `.codex/agents/agents.toml` is moved there once — Codex ≥ 0.147 sweeps `.codex/agents/*.toml` as standalone role files and warns on a multi-agent file) and the Antigravity agent pack is installed via `agy plugin install` and reinstalled whenever the plugin version changes (KTD8); `invoke_antigravity` stays in injection mode unless `TRIFORGE_AGY_MODE` selects native routing. Reviews run in parallel (Antigravity + Codex + Claude subagents simultaneously), never sequentially.

## Context management

- **Completion gating:** the `ops/.sprint-complete` sentinel is the authoritative completion signal (created only after the verification checklist passes; `scripts/coordinate.sh` detects it). The `/goal` checklist is a **best-effort assist**, not a hard gate: `scripts/coordinate.sh` composes it as the leading line of each session prompt and `/ship` / `/coordinate` print a copyable `/goal` line, but headless gating is model-behavior-dependent — probe CC-03 passed 1 of 3 runs in the 2026-09 cycle (D-030; the retired ship-loop.sh Stop hook is not coming back)
- **Outer loop:** `scripts/coordinate.sh` spawns fresh sessions on context exhaustion; detects completion via the `ops/.sprint-complete` sentinel (headless-observable, no output parsing)
- **Analysis paralysis:** `hooks/handlers/context-monitor.sh` warns at 8+ consecutive reads without writes
- **Context checkpoint:** `hooks/handlers/pre-compact.sh` auto-snapshots `ops/STATE.md` (current phase + task counts) before Claude Code compacts the window, so a resume after compaction has a fresh anchor
- **Tool-failure threshold:** `hooks/handlers/tool-failure-monitor.sh` tracks consecutive and total tool failures, warning at 5 consecutive or 10 total per session
- **Risk scoring:** Subagents halted at risk >20% or 50+ file changes

## Prerequisites

**Run `/setup` — it is the one guided path** from a fresh install to a working roster (R39/AE8): it gates the core trio live, walks each optional CLI (enroll with a chosen model, or decline cleanly), then offers role assignment — accept the shipped defaults (recommended) or customize any role's CLI · model · effort via `roster_write_role` (`/setup roles` jumps straight to that step). Idempotent and re-runnable. The manual probes below are exactly what `/setup` automates.

**Core trio (required).** All three must be installed and answer a headless READY probe (floors per KTD-13):
```bash
claude --version                                                     # Claude Code ≥ 2.1.267 (effort: frontmatter honored on pinned-default models; the fable alias = Fable 5.1 since 2.1.257)
agy --model "Gemini 3.8 Flash (High)" -p "Respond with only: READY"  # Antigravity ≥ 1.1.27 — pin the model (agy's own default is a (Medium) variant)
codex exec "Respond with only: READY"                                # Codex ≥ 0.153.0 (gpt-6-astra's minimal client version)
```

**Optional tier (enroll via `/setup` when you want them as builders/reviewers).** Each is skipped cleanly in every roster fallback chain when absent:
```bash
opencode run --format json -m openrouter/z-ai/glm-5.3 "Respond with only: READY"  # OpenCode ≥ 1.18.20 — needs the OpenRouter provider connected (OPENROUTER_API_KEY or `opencode auth login`)
kimi -p "Respond with only: READY"                                                # Kimi Code ≥ 0.33.0 — OAuth device-code OR API key (`kimi login`)
cursor-agent -p --trust --model cursor-grok-4.6-xhigh "Respond with only: READY"  # Cursor (date-versioned) — pin the suffixed Grok id, never the Auto router; use `agent` when only the new name exists
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

Re-baselined from the newest capability probe record (`ops/research/2026-09-probe-record.md`, 2026-09-11; "the current record" always means the newest `ops/research/*-probe-record.md` — `latest_probe_record`). The framework runs a **core trio** (required) plus an **optional tier** (enroll via `/setup`). Supersedes the July 2026 baseline (D-034).

| CLI | Tier | Floor (KTD-13) | Tested | READY probe |
|---|---|---|---|---|
| Claude Code (`claude`) | core | ≥ 2.1.267 | 2.1.268 | `claude --version` |
| Antigravity (`agy`) | core | ≥ 1.1.27 | 1.2.0 | `agy --model "Gemini 3.8 Flash (High)" -p "Respond with only: READY"` |
| Codex (`codex`) | core | ≥ 0.153.0 | 0.154.0 | `codex exec "Respond with only: READY"` |
| OpenCode (`opencode`) | optional | ≥ 1.18.20 | 1.18.30 | `opencode run --format json -m openrouter/z-ai/glm-5.3 "Respond with only: READY"` |
| Kimi Code (`kimi`) | optional | ≥ 0.33.0 | 0.42.0 (AUTH-FAIL on the probe host; live rows PENDING-AUTH until `kimi login`) | `kimi -p "Respond with only: READY"` |
| Cursor (`cursor-agent`; `agent` fallback) | optional | date-versioned | 2026.09.10 | `cursor-agent -p --trust --model cursor-grok-4.6-xhigh "Respond with only: READY"` |

**Minimum supported versions / notes:**
- **Claude Code ≥ 2.1.267** — the build that first honors `effort:` frontmatter on pinned-default models (Triforge's shipped `max`/`xhigh` only take effect from it); the `fable` alias resolves to Fable 5.1 from 2.1.257 and `opus` to Opus 5 from 2.1.219. Task/Todo tools are off on current models unless `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (shipped in `settings.json`, D-031a).
- **Antigravity `agy` ≥ 1.1.27** — `denied_actions` in the JSON envelope (the completion signal `invoke_antigravity` reads); ≥ 1.1.10 is the hard minimum (`--model` was ignored under `-p` on 1.1.5–1.1.9). The Gemini CLI lane was retired in v3.0.0 (Google's hosted service stopped serving consumer tiers 2026-06-18; legacy Gemini users pin plugin v2.4.3).
- **Codex ≥ 0.153.0** — `gpt-6-astra`'s `minimal_client_version`; `--output-schema` (structured review verdicts) and `codex features list` (runtime capability detection) predate it. Older versions degrade: `invoke_codex` still runs, but hook enforcement and structured verdicts silently fall back to raw output.
- **OpenCode ≥ 1.18.20** — `opencode run` answers subagent permission asks. **Kimi ≥ 0.33.0** — agent-core-v2 engine; `--agent`/`--agent-file` in `-p` (KIMI-03 PASS on 0.42.0).
- **Optional tier is skip-clean** — an absent or declined optional CLI is silently skipped in every roster fallback chain, which always terminates at a core-trio member; the core trio cannot be disabled.

**Known-fails / partial support:**
- Codex hooks **fire under `codex exec`** (probe CDX-04 PASS on 0.154.0, re-verified 2026-09-11: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Stop`) with all three preconditions: nested `hooks.json` shape, project-tier `.codex/hooks.json`, and `--dangerously-bypass-hook-trust` (`invoke_codex` passes it only when the project ships `.codex/hooks.json` and `codex features list` reports `hooks` enabled). Project trust gates the rest: `.codex/config.toml`, `.rules`, and project `AGENTS.md` are skipped under `exec` in an untrusted project — the durable path is the user-tier `[projects."<abs>"] trust_level = "trusted"` entry (`/setup` detects it, never writes it). See `ops/decisions/2026-07-18-codex-hooks-under-exec.md` and D-026.
- Antigravity plugin agents: the pack now ships the agy Markdown-agent format (`mainAgent`/`subagent`/`commandExecutionPolicy`, agy tool names — D-027); whether `agy agents` lists the four Triforge agents is verified by row AGY-12 in the newest record, and injection stays the default routing until AGY-12 and AGY-16 pass for a full cycle (KTD10). Project-tier hooks fired headless on agy 1.2.0 with the documented `.agents/hooks.json` shape but not on 1.2.1 (AGY-08 FAIL in the fresh record — open watch); project-tier permission allow-rules do not apply headless (user tier only) — the `/review` and `/deep-research` commands compensate by promoting captured output into `ops/` when the agent could not write there directly.

### Release checklist

1. `claude plugin validate --strict .` passes green (warnings are errors) — required gate
2. `bash scripts/validate-skills.sh` exits 0 (all shipped skills: portable frontmatter, "Use when" descriptions, `## Output` sections)
3. `bash scripts/validate-versions.sh` exits 0 — version lockstep, the ladder md5 printed four times (byte-identity across `agents/team-lead.md`, `skills/wave-orchestration/SKILL.md`, `templates/CLAUDE.md`, and this file), `DEFAULTS` drift, the scoped stale-pin sweep (zero hits outside `ops/research/`, `ops/decisions/`, `docs/plans/`, `ops/solutions/`, `docs/images/`), and surface counts
4. Doc-consistency greps pass (see Verification Contract in the active plan)
5. The probe record is regenerated (`bash scripts/probe-capabilities.sh` writes `ops/research/<YYYY-MM>-probe-record.md`), committed, and cited by the release notes together with the ladder hash
6. Version bumped in `.claude-plugin/plugin.json` and `antigravity-agents/plugin.json` (lockstep); README "What's new" + "Recent changes" entries added
