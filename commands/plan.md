---
description: "Decompose a goal into tasks with shadow paths, error maps, and wave grouping. Validates via plan-checker."
argument-hint: "<goal description>"
---

You are executing Phase 0 → Phase 1 → Phase 1.5 of the multi-agent framework.

## Goal
$ARGUMENTS

## Pre-Plan: Search institutional knowledge

Spawn the `learnings-researcher` agent:
"Search institutional knowledge for patterns relevant to: $ARGUMENTS"

## Phase 0: Codebase analysis (if needed)

Skip if:
- Codebase unchanged since last sprint
- Continuing within same session
- Small bug fix

Otherwise, invoke Gemini with codebase-mapping skill:
```bash
gemini -p "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/codebase-mapping/SKILL.md) Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append)." > /tmp/gemini_phase0.txt 2>&1 &
GEMINI_PID=$!

# Wait with timeout (10 min)
AGENT_TIMEOUT=600
( sleep $AGENT_TIMEOUT && kill -TERM $GEMINI_PID 2>/dev/null && sleep 5 && kill -9 $GEMINI_PID 2>/dev/null ) &
WD=$!
wait $GEMINI_PID 2>/dev/null
kill $WD 2>/dev/null; wait $WD 2>/dev/null
```

Read updated ops/ files after completion.

## Phase 1: Planning

Follow the `writing-plans` skill:

1. Read: ops/GOALS.md, ops/ARCHITECTURE.md, ops/CONTRACTS.md, ops/MEMORY.md, ops/TASKS.md, learnings-researcher output
2. Decompose goal into atomic tasks (1-2 hours each)
3. Assign using the heuristic matrix:
   - Produces code → Claude
   - Evaluates code → Gemini + Codex + Claude agents in parallel
   - Runs/executes → Codex
   - Documentation → Gemini
4. Apply `shadow-path-tracing` skill: enumerate failure paths for non-trivial tasks
5. Build error/rescue maps for external calls and DB operations (any "?" → subtask)
6. Extract and embed relevant CONTRACTS.md types in each task's Context field
7. Group tasks into waves for parallel execution
8. Write ops/TASKS.md

## Phase 1.1: Ambiguity resolution

Before validating the plan, surface critical assumptions:

1. List the **3 most critical assumptions** you are making about the goal that, if wrong, would invalidate the plan
2. For each assumption, state:
   - What you assumed
   - What the alternative interpretation could be
   - Impact if the assumption is wrong (which tasks would change)
3. Present these to the user and ask for confirmation or correction
4. If the user corrects any assumption → revise TASKS.md before proceeding to validation
5. If the user confirms all assumptions → proceed to Phase 1.5

Skip this step if: the goal is unambiguous (single file fix, explicit user instructions with no room for interpretation).

## Phase 1.5: Plan validation

Spawn the `plan-checker` agent. It validates:
- Task completeness (agent, files, acceptance criteria)
- Assignment correctness (heuristic matrix)
- Dependency correctness (DAG, no cycles)
- Scope assessment (atomic tasks, reasonable count)
- Shadow path coverage
- Architecture alignment

If NEEDS_REVISION: fix and re-submit (max 3 iterations).
Only report APPROVED result to user when done.
