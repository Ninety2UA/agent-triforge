# Multi-agent operating protocol

<!-- Copied into ops/ by Triforge's session start when the project has no ops/ yet. Customize the project-specific section. The shared protocol lives in the plugin's root AGENTS.md and docs/agent-triforge.md, not here. -->

## Agents in this repo

Roles come from `ops/roster.toml`: builder, reviewer, tester, analyst and documenter, each a CLI + model + effort with a fallback chain. The lead CLI (Claude Code or Codex) reads the root `AGENTS.md`; workers get their context in the dispatch.

<!-- Add project-specific agents or notes here. For example:
- Custom agent — description of role
-->

## Shared rules

- Any roster member can build. Every implementation task runs under a per-task lease in an isolated worktree and merges only after cross-review by a pinned reviewer who is not the builder; no agent reviews or merges its own build.
- Builders under a lease work only inside their worktree and never read or write the canonical `ops/` tree — the lead injects the context (TASKS.md rows, CONTRACTS.md slice, roster entry) at dispatch and applies `ops/` changes at collect/merge. Commit nothing; the lead collects.
- The lead reads TASKS.md, MEMORY.md, CHANGELOG.md and CONTRACTS.md before acting and updates CHANGELOG.md after; each merged task's row carries builder, reviewer and merge commit from the lease ledger.
- Stay within your assigned scope (a builder's scope is its worktree); propose cross-scope changes in MEMORY.md first.
- Never modify CONTRACTS.md directly — propose changes in MEMORY.md first. All code conforms to the type definitions in CONTRACTS.md.
- A conflict with another agent's work is logged in TASKS.md.
- Attribution is mandatory on every change.
- Never create or touch `ops/.sprint-complete` — it is the lead's runtime completion marker (gitignored), created only at wrap after the verification checklist passes.

## Project-specific rules

<!-- Add rules specific to your project below. Examples: -->
<!-- - All API endpoints must have OpenAPI annotations -->
<!-- - Database migrations require rollback scripts -->
<!-- - No direct DOM manipulation — use the framework's reactive system -->
