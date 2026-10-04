# Sprint status template

Print these sections in this order. A section with nothing to say says "none"; never omit one. Read the source files silently and summarise — do not paste them.

```markdown
## Sprint status

**Goal:** [the ops/TASKS.md header, else the "Active sprint" line of ops/STATE.md]
**Phase:** [the current phase 0–6, or "no active sprint"]

### Tasks
- Done: N
- In progress: N
- Active (pending): N
- Blocked: N
- In review: N
- Open leases: N — only when ops/leases.toml exists; counts by state from lease_status

### Blockers
- [each blocked task with its reason, from ops/TASKS.md and ops/MEMORY.md]

### Recent activity
- [the last 3–5 ops/CHANGELOG.md entries]

### Pending reviews
- ops/REVIEW_ANTIGRAVITY.md — [absent | exists, unprocessed | exists, processed]
- ops/REVIEW_CODEX.md — [absent | exists, unprocessed | exists, processed]
- ops/TEST_RESULTS.md — [absent | exists, unprocessed | exists, processed]

### Uncommitted changes
- [git status summary: branch, N modified, N untracked, or "clean"]

### Available commands
- /at-plan <goal> — start a new sprint
- /at-build — execute Phase 2 (needs ops/TASKS.md)
- /at-review — trigger parallel review
- /at-test — run the test phase
- /at-ship <goal> — full autonomous sprint
- /at-coordinate <goal> — full sprint with exit guard
- /at-quick <change> — lightweight fix
- /at-debug <bug> — structured debugging
- /at-deep-research <topic> — research swarm
- /at-analyze <url> — compatibility analysis of an external repo
- /at-pause — save a checkpoint
- /at-resume — continue from the checkpoint
- /at-wrap — clean session end
- /at-compound — document a solution or decision
- /at-resolve-pr <PR#> — resolve PR review comments
- /at-setup — onboarding: core trio, optional members, roles
- /at-status — this overview
```

Rendering rule for "Available commands": print the invocation form of the lead's harness — `/at-name` under Claude Code, `$at-name` under Codex — and exactly one form. "Processed" for a review file means `ops/TASKS.md` holds a `## Review dispositions — Cycle N` block for it; archived files (under `ops/archive/<date>/`) are absent, not pending.
