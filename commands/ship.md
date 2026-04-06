---
description: "Fully autonomous end-to-end sprint: analyze → plan → validate → build → review → test → compound → ship."
argument-hint: "<goal description> [--convergence fast|standard|deep] [--team]"
---

You are running a fully autonomous multi-agent sprint. Follow the complete framework lifecycle (docs/agent-triforge.md).

## Input
Goal: $ARGUMENTS

## Flags
- `--convergence {fast|standard|deep}` — Review convergence mode (default: standard). Fast=P1 only, deep=P1+P2+P3<3.
- `--team` — Activate agent team mode for build phase (5+ interdependent tasks)

## Activation

Write the ship-loop state file to activate the inner loop guard:

```
Create .claude/ship-loop.local.md with:
---
active: true
session_id: "<current-branch-name>"
iteration: 0
max_iterations: 5
completion_promise: "DONE"
---
<the goal description from $ARGUMENTS>
```

## Pipeline

Execute ALL phases in order. Do not skip phases unless explicitly noted.

### Pre-Plan: Search institutional knowledge
Spawn the `learnings-researcher` agent to search ops/solutions/ and ops/decisions/ for relevant patterns.

### Phase 0: Codebase analysis
Invoke Gemini CLI with the codebase-mapping skill (skip if codebase unchanged or small fix):
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

### Phase 1: Planning
Follow the `writing-plans` skill. Apply `shadow-path-tracing` skill for non-trivial tasks. Embed CONTRACTS.md types in task descriptions. Group tasks into waves. Write ops/TASKS.md.

### Phase 1.1: Ambiguity resolution

Before building, surface the 3 most critical unverified assumptions about the goal. Present each with the alternative interpretation and the impact if wrong. Ask the user to confirm or correct. Revise TASKS.md if any assumption is corrected. Skip for unambiguous goals.

### Phase 1.5: Plan validation
Spawn the `plan-checker` agent. Iterate until APPROVED (max 3 rounds).

### Phase 2: Build
- If < 5 independent tasks → subagent mode with wave orchestration
- If 5+ tasks or interdependent → agent team mode with team-lead
- Run `integration-verifier` between waves
- Apply risk scoring (halt at >20% risk or 50+ file changes)

### Phase 3: Parallel review
Launch ALL reviewers simultaneously:
- Gemini CLI (architecture, design) — background bash
- Codex CLI (logic, security, tests) — background bash
- security-sentinel agent — Claude subagent
- performance-oracle agent — Claude subagent
- code-simplicity-reviewer agent — Claude subagent

### Phase 4: Process reviews
Spawn the `findings-synthesizer` agent. Apply `iterative-refinement` skill.
- Fix P1 + P2 issues
- Check convergence (use mode from arguments, default: standard)
- Loop to Phase 3 if not converged (max 3 cycles)

### Phase 5: Test
- Spawn `test-gap-analyzer` to identify coverage gaps
- Invoke Codex with TDD skill
- Fix failures, re-run until green

### Phase 6: Wrap up
- Apply `knowledge-compounding` skill (document solutions to ops/solutions/)
- Update ops/CHANGELOG.md, ops/MEMORY.md, ops/TASKS.md
- Archive review files to ops/archive/[today's date]/
- Apply `verification-before-completion` skill (all checks must pass)
- Write ops/STATE.md for session handoff
- Remove .claude/ship-loop.local.md

Only when ALL work is verified complete:
<promise>DONE</promise>
