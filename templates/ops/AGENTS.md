# Multi-agent operating protocol

<!-- This file is read by all agents before acting. Customize for your project. -->

## Agents in this repo

1. Claude Code (lead) — reads CLAUDE.md for specific instructions; orchestrates the builder pool and merges after cross-review
2. Antigravity CLI (agy) — analyst + reviewer (large context for full codebase analysis)
3. Codex CLI — tester + logic reviewer (sandbox execution)

<!-- Add or remove agents as needed. For example:
4. Custom agent — description of role
-->

The framework runs a **builder pool**: any roster member (`ops/roster.toml`) can be assigned implementation tasks, not just the lead. Every build runs under a per-task lease in an isolated worktree and merges only after cross-review by a pinned non-author reviewer — safety is leases + worktree isolation + cross-review, not write-restriction. The roles above are the shipped default posture.

## Invoking external agents

All Antigravity/Codex invocations go through the plugin's unified helper
(handles model pinning, fail-closed timeout enforcement, retries, and
native-agent routing with prompt-prefix injection as a fallback):

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh
invoke_antigravity "<agent-name>" "<prompt>" "<output-file>" <timeout-seconds>
invoke_codex       "<agent-name>" "<prompt>" "<output-file>" <timeout-seconds>
```

Available native agents live in the plugin at `antigravity-agents/agents/` and `codex-agents/`.

## Shared rules

- **Builders under a lease** work only inside their assigned worktree and never read or write the canonical `ops/` tree — required context (TASKS.md rows, CONTRACTS.md slice, roster entry) is injected into the dispatch prompt, and the lead applies all `ops/` mutations at collect/merge time (KTD-3). Commit nothing; the lead collects.
- **The lead** reads TASKS.md, MEMORY.md, CHANGELOG.md, CONTRACTS.md before acting and updates CHANGELOG.md after — each merged task's row carries builder + reviewer + merge commit from the lease ledger.
- Every implementation task — lead-authored included — merges only after cross-review by a pinned non-author reviewer; no agent reviews or merges its own build (AE3).
- Stay within your assigned scope (a builder's scope is its worktree); propose cross-scope changes in MEMORY.md first
- Never modify CONTRACTS.md directly — propose changes in MEMORY.md first. All code must conform to type definitions in CONTRACTS.md
- If you discover a conflict with another agent's work, log it in TASKS.md
- Attribution is mandatory on every change
- Never create or touch `ops/.sprint-complete` — it is the lead agent's runtime sprint-completion marker (gitignored), created only at Phase 6 wrap after the verification checklist passes

## Project-specific rules

<!-- Add rules specific to your project below. Examples: -->
<!-- - All API endpoints must have OpenAPI annotations -->
<!-- - Database migrations require rollback scripts -->
<!-- - No direct DOM manipulation — use the framework's reactive system -->
