# ops/STATE.md checkpoint template

Write the whole file. Frontmatter first, then the HTML comments, then every section; omit only `## Lease snapshot` when `ops/leases.toml` does not exist.

```markdown
---
saved: [ISO timestamp]
phase: [0-6 — the phase active when the session paused]
wave: [N, or none]
tasks:
  total: [N]
  done: [N]
  blocked: [N]
verification_baseline:
  command: "[the last command that proved the tree green, e.g. the test suite or the validators; none when nothing was proven]"
  result: "[its exit code and summary line, quoted; \"not verified\" when none]"
  commit: [the commit that command ran against]
verification_command: "[the command a resume must re-run to re-establish the baseline]"
state_head: [git rev-parse HEAD at save time]
---
# Session state
<!-- Saved: [ISO timestamp] -->
<!-- Type: checkpoint (not wrap) -->

## Current phase
[0, 1, 1.5, 2, 3, 4, 5 or 6 — on this line, not on the heading]

## Active sprint
[Goal being worked on]

## Task status snapshot
[N done, N in progress, N remaining, N blocked]

## In-progress work
- [What you were actively working on]
- [Uncommitted changes — list the files]
- [Branch name if applicable]

## Context
- [Key decisions made this session, including any Ruling: lines]
- [Blockers or open questions]

## Review cycle state
- Cycle: [N of 3]
- Convergence mode: [fast | standard | deep]
- Outstanding P1: [count]
- Outstanding P2: [count]

## Next actions (when resuming)
1. [Exactly what to do first]
2. [Then what]
3. [Then what]

## Lease snapshot
Counts: [state=N, ... from lease_status]
- [task_id]: [builder_cli] — [state]   (one line per non-terminal lease: leased | building | review | orphaned | requeued)
```

Rules that are easy to get wrong:

- `verification_baseline` describes one commit. If nothing was proven green this session, write `command: none` and `result: "not verified"`; never carry an older baseline forward.
- `state_head` is HEAD even when the tree is dirty; the dirty paths are listed under "In-progress work".
- The `## Current phase` value is on the next line after the heading. The pre-compaction hook reads that shape and rewrites it; an inline `## Current phase: 2` is not read.
