# Multi-agent operating protocol

<!-- This file is read by all agents before acting. Customize for your project. -->

## Agents in this repo

1. Claude Code (lead) — reads CLAUDE.md for specific instructions
2. Gemini CLI — analyst + reviewer (1M token context for full codebase analysis)
3. Codex CLI — tester + logic reviewer (sandbox execution)

<!-- Add or remove agents as needed. For example:
4. Custom agent — description of role
-->

## Shared rules

- Before acting: read TASKS.md, MEMORY.md, CHANGELOG.md, CONTRACTS.md
- After acting: update CHANGELOG.md with agent name, timestamp, changes
- Never modify files outside your assigned scope without proposing in MEMORY.md
- Never modify CONTRACTS.md directly — propose changes in MEMORY.md first
- If you discover a conflict with another agent's work, log it in TASKS.md
- All code must conform to type definitions in CONTRACTS.md
- Attribution is mandatory on every change

## Project-specific rules

<!-- Add rules specific to your project below. Examples: -->
<!-- - All API endpoints must have OpenAPI annotations -->
<!-- - Database migrations require rollback scripts -->
<!-- - No direct DOM manipulation — use the framework's reactive system -->
