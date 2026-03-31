---
description: "Quick checkpoint: save current state to STATE.md without archiving or summarizing."
---

You are saving a quick checkpoint. This is NOT a clean wrap — it's a mid-sprint save.

Unlike /wrap, /pause does NOT:
- Archive review files
- Write a sprint summary
- Compound knowledge
- Move tasks to Done

/pause ONLY saves where you are so you can /resume later.

## Save state

Write ops/STATE.md with:

```markdown
# Session state
<!-- Saved: [ISO timestamp] -->
<!-- Type: checkpoint (not wrap) -->

## Current phase
[Which phase you're in: 0, 1, 1.5, 2, 3, 4, 5, 6]

## Active sprint
[Goal being worked on]

## Task status snapshot
[Quick summary: N done, N in progress, N remaining, N blocked]

## In-progress work
- [What you were actively working on]
- [Any uncommitted changes — list files]
- [Branch name if applicable]

## Context
- [Key decisions made this session — bullet list]
- [Any blockers or open questions]

## Review cycle state
- Cycle: [N of 3]
- Convergence mode: [fast | standard | deep]
- Outstanding P1: [count]
- Outstanding P2: [count]

## Next actions (when resuming)
1. [Exactly what to do first]
2. [Then what]
3. [Then what]
```

Report to user: "State saved. Use /resume to continue."
