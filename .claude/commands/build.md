---
description: "Execute Phase 2 build with wave orchestration. Assumes planning is already done (TASKS.md exists)."
argument-hint: "[--team] [--wave N]"
---

You are executing Phase 2 (Build) of the multi-agent framework.

## Prerequisites
- ops/TASKS.md must exist with assigned tasks
- Phase 1.5 plan validation should have passed

Read ops/TASKS.md, ops/CONTRACTS.md, ops/MEMORY.md, and ops/ARCHITECTURE.md first.

## Arguments
$ARGUMENTS

## Flags
- `--team` — Activate agent team mode with team-lead (for 5+ tasks or cross-dependent work)
- `--wave N` — Resume build starting from wave N (skip already-completed waves)

## Build mode selection

Check the task count and dependencies:
- **< 5 independent tasks** → Subagent mode (default)
- **5+ tasks or `--team` flag** → Agent team mode with team-lead
- **`--wave N`** → Start from wave N (for resuming)

## Subagent mode

Follow the `wave-orchestration` skill:

1. Group tasks into waves based on dependencies and file ownership
2. For each wave:
   a. Dispatch parallel subagents — each gets task description + relevant CONTRACTS.md types
   b. Apply risk scoring (halt at >20% or 50+ file changes)
   c. Collect results
   d. Spawn `integration-verifier` agent: tests pass, build clean, lint clean, no conflicts
   e. If verification fails → fix before proceeding
3. After all waves: run full test suite + build from clean state

## Agent team mode

1. Spawn the `team-lead` agent
2. Team-lead reads TASKS.md, groups into work streams
3. Team-lead assigns teammates with explicit file ownership
4. Teammates coordinate via shared task list + messaging
5. Teammates can invoke gemini/codex for specific reviews:
   ```bash
   gemini -p "$(cat .claude/skills/codebase-mapping/SKILL.md) Review src/auth/ for architecture. Write to ops/REVIEW_GEMINI.md." &
   codex exec "$(cat .claude/skills/test-driven-development/SKILL.md) Write tests for src/auth/login.ts." &
   ```
6. Quality gates: tests + lint must pass before marking tasks done
7. Integration-verifier runs between waves

## After build

- Update ops/CHANGELOG.md with all changes and attribution
- Move completed build tasks to "Done" in ops/TASKS.md
- Move review tasks to "Review" status
- Update ops/CONTRACTS.md if new interfaces were introduced
