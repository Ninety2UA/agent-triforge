---
description: "Resume work from a previous session using STATE.md."
---

You are resuming a multi-agent sprint from a previous session.

Follow the `session-continuity` skill — resume protocol:

## Step 1: Load state

Read these files in order:
1. ops/STATE.md — where you left off (phase, progress, next actions)
2. ops/TASKS.md — current task status
3. ops/MEMORY.md — decisions and gotchas from previous sessions
4. ops/CHANGELOG.md — what was already done
5. ops/CONTRACTS.md — current interface definitions

## Step 2: Assess current state

- Check for uncommitted changes (git status)
- Check which phase was active when session paused
- Check remaining tasks by status (active, in progress, blocked, review)
- Check if any review files exist (REVIEW_GEMINI.md, REVIEW_CODEX.md, TEST_RESULTS.md)

## Step 3: Report to user

Summarize:
- Sprint goal
- Current phase
- Tasks completed vs remaining
- Any blockers or pending decisions
- Recommended next action

## Step 4: Resume execution

Pick up from the phase recorded in STATE.md:
- If mid-Phase 2 (build) → continue with remaining build tasks
- If mid-Phase 3-4 (review) → check if reviews are complete, process if so
- If mid-Phase 5 (test) → check test results, fix failures
- If Phase 6 needed → wrap up

Ask the user if they want to continue automatically or review the state first.
