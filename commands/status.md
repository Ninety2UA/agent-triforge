---
description: "Show current sprint state: phase, tasks by status, blockers, available commands."
---

You are providing a quick status overview of the current sprint.

## Gather state

Read these files (silently — don't dump contents to user):
1. ops/STATE.md (if exists) — last saved state
2. ops/TASKS.md (if exists) — current tasks
3. ops/CHANGELOG.md (if exists) — recent activity
4. ops/MEMORY.md (if exists) — recent decisions

Also check:
- git status (uncommitted changes?)
- Are there unprocessed review files? (REVIEW_GEMINI.md, REVIEW_CODEX.md, TEST_RESULTS.md)

## Report

Present a concise status:

```
## Sprint status

**Goal:** [from TASKS.md header or STATE.md]
**Phase:** [current phase, or "no active sprint"]

### Tasks
- Done: N
- In progress: N
- Active (pending): N
- Blocked: N
- In review: N

### Blockers
- [any blocked tasks with reasons]

### Recent activity
- [last 3-5 CHANGELOG entries]

### Pending reviews
- [REVIEW_GEMINI.md exists? processed?]
- [REVIEW_CODEX.md exists? processed?]
- [TEST_RESULTS.md exists? processed?]

### Uncommitted changes
- [git status summary]

### Available commands
- /plan <goal> — start a new sprint
- /build — execute Phase 2 (needs TASKS.md)
- /review — trigger parallel review
- /test — run test phase
- /ship <goal> — full autonomous sprint
- /coordinate <goal> — full sprint with exit guard
- /quick <change> — lightweight fix
- /debug <bug> — structured debugging
- /deep-research <topic> — research swarm
- /analyze <url> — compatibility analysis of external repo
- /pause — save checkpoint
- /resume — continue from checkpoint
- /wrap — clean session end
- /compound — document a solution
- /resolve-pr <PR#> — resolve PR review comments
- /status — this command
```
