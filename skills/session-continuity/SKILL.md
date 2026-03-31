---
name: session-continuity
description: "Save and resume work across sessions using STATE.md. Primary consumer: Claude Code (session management)."
---

# Session Continuity

Work persists across sessions through explicit state capture.

## Pause (save state)

When pausing a session, write `ops/STATE.md`:

```markdown
# Session state
<!-- Saved: [ISO timestamp] -->

## Current phase
[Phase 0-6 — which phase was active when session paused]

## Active sprint
[Goal being worked on]

## Task status snapshot
[Copy current TASKS.md status section — what's done, in progress, blocked]

## In-progress work
- [What was being worked on when session paused]
- [File paths with uncommitted changes]
- [Branch name if applicable]

## Context
- [Key decisions made this session]
- [Blockers encountered]
- [Pending questions for user]

## Next actions
1. [First thing to do when resuming]
2. [Second thing]
3. [Third thing]

## Review cycle state
- Cycle: [N of 3]
- Convergence mode: [fast | standard | deep]
- Outstanding issues: [count by priority]
```

## Resume (restore state)

When starting a new session on existing work:

1. Read `ops/STATE.md` — understand where you left off
2. Read `ops/TASKS.md` — current task status
3. Read `ops/MEMORY.md` — decisions and gotchas from previous sessions
4. Read `ops/CHANGELOG.md` — what was already done
5. Check for uncommitted changes (git status)
6. Resume from the phase and action recorded in STATE.md

## Wrap (clean handoff)

Different from pause — wrap is a clean session end, not a checkpoint:

1. Update CHANGELOG.md with session summary
2. Update MEMORY.md with new decisions/patterns/gotchas
3. Move completed tasks to Done in TASKS.md
4. Archive temporary files (REVIEW_*.md, TEST_RESULTS.md) to ops/archive/[date]/
5. Write STATE.md with next-session context
6. Write sprint summary for user

## Output

- **Pause:** Produce `ops/STATE.md` with all fields from the template above
- **Resume:** No artifact — read existing state and continue from recorded phase
- **Wrap:** Produce updated `ops/STATE.md` + `ops/CHANGELOG.md` entry + archived review files

## When to use each

| Situation | Action |
|---|---|
| Context window filling up, more work remains | Pause → start new session → Resume |
| Sprint complete, all tasks done | Wrap |
| User needs to step away, will return | Pause |
| Switching to a different goal mid-sprint | Wrap current → start new sprint |
