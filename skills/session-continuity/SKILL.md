---
name: session-continuity
description: "Pause, resume, and wrap protocol built on an ops/STATE.md snapshot whose YAML frontmatter records the verification baseline and the commit it describes. Use when the context window is filling and work remains, when starting a session on existing work, or when ending a sprint cleanly. Not for recording decisions or solutions; that is knowledge-compounding."
metadata:
  triforge-consumer: "Claude (lead)"
  triforge-phase: "session boundaries (pause, resume, wrap)"
  version: "3.3.0"
---

# Session Continuity

Work persists across sessions through explicit state capture. The snapshot records not only where work stopped but what was last proven green, and at which commit, so a resume knows whether that proof still holds.

## Pause (save state)

When pausing a session, write `ops/STATE.md`. The YAML frontmatter is machine-readable and comes first; the prose sections follow.

```markdown
---
saved: [ISO timestamp]
phase: [0-6 — which phase was active when the session paused]
wave: [N, or none]
tasks:
  total: [N]
  done: [N]
  blocked: [N]
verification_baseline:
  command: "[the last command that proved the tree green, e.g. the test suite or the validators]"
  result: "[its exit code and summary line, quoted]"
  commit: [the commit that command ran against]
verification_command: "[the command a resume must re-run to re-establish the baseline]"
state_head: [the commit this snapshot describes — the output of git rev-parse HEAD at save time]
---
# Session state

## Current phase
[Phase 0-6 — same value as the frontmatter, for readers]

## Active sprint
[Goal being worked on]

## Task status snapshot
[Copy current TASKS.md status section — what's done, in progress, blocked]

## In-progress work
- [What was being worked on when session paused]
- [File paths with uncommitted changes]
- [Branch name if applicable]

## Context
- [Key decisions made this session, including any `Ruling:` lines]
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

## Lease snapshot
<!-- Omit this section when ops/leases.toml does not exist -->
Counts: [state=N, ... from ops/leases.toml]
- [task_id]: [builder_cli] — [state]   (one line per non-terminal lease:
  leased | building | review | orphaned | requeued)
```

Frontmatter rules:

- `verification_baseline` is a claim about one commit. Record the command exactly as run, its result verbatim, and the commit it ran against. If nothing has been proven green this session, write `command: none` and `result: "not verified"` rather than copying an older baseline.
- `state_head` is the commit the snapshot describes. When the tree has uncommitted changes, still record HEAD and list the dirty paths under "In-progress work".
- A snapshot written by tooling that cannot run verification (the pre-compaction checkpoint) may omit `verification_baseline`; a resume treats a missing baseline as "not verified".

## Resume (restore state)

When starting a new session on existing work:

1. Read `ops/STATE.md` — understand where you left off
2. Compare the frontmatter with the tree: if `git rev-parse HEAD` differs from `state_head`, or `verification_baseline.commit` differs from HEAD, or the baseline is missing, re-run `verification_command` before continuing and record the fresh result. A baseline from another commit proves nothing about this one
3. Read `ops/TASKS.md` — current task status
4. Read `ops/MEMORY.md` — decisions and gotchas from previous sessions
5. Read `ops/CHANGELOG.md` — what was already done
6. Check `ops/leases.toml` — if it exists, reconstruct wave state from the
   ledger: run `lease_heartbeat_check` to reclaim orphans, requeue or finish
   open leases, and NEVER redo merged leases (their commits are already on
   the integration branch)
7. Check for uncommitted changes (git status)
8. Resume from the phase and action recorded in STATE.md

## Wrap (clean handoff)

Different from pause — wrap is a clean session end, not a checkpoint:

1. Update CHANGELOG.md with session summary, including every `Ruling:` line made this session
2. Update MEMORY.md with new decisions/patterns/gotchas (apply the knowledge-compounding skill's bar)
3. Move completed tasks to Done in TASKS.md
4. Archive temporary files (REVIEW_*.md, TEST_RESULTS.md) to ops/archive/[date]/
5. Write STATE.md with next-session context, with a fresh `verification_baseline` from a run performed now
6. Write sprint summary for user

## Output

- **Pause:** Produce `ops/STATE.md` with the frontmatter and all prose sections from the template above
- **Resume:** No artifact — read existing state, re-establish the verification baseline when HEAD moved, and continue from the recorded phase
- **Wrap:** Produce updated `ops/STATE.md` (fresh baseline) + `ops/CHANGELOG.md` entry + archived review files

## When to use each

| Situation | Action |
|---|---|
| Context window filling up, more work remains | Pause → start new session → Resume |
| Sprint complete, all tasks done | Wrap |
| User needs to step away, will return | Pause |
| Switching to a different goal mid-sprint | Wrap current → start new sprint |
