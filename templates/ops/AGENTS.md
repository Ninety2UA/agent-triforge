# Multi-agent operating protocol

<!-- This file is read by all agents before acting. Customize for your project. -->

## Agents in this repo

1. Claude Code (lead) — reads CLAUDE.md for specific instructions
2. Antigravity CLI (agy) — analyst + reviewer (large context for full codebase analysis)
3. Codex CLI — tester + logic reviewer (sandbox execution)

<!-- Add or remove agents as needed. For example:
4. Custom agent — description of role
-->

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
