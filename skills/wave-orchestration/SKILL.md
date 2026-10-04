---
name: wave-orchestration
description: "Use when executing a validated plan of two or more tasks: leases, pinned cross-review, wave-order merges, rc 80/44/42."
metadata:
  triforge-consumer: "the lead"
  triforge-phase: "2 (build)"
  version: "3.3.0"
---

# Wave Orchestration

Run a validated plan as dependency-grouped waves: tasks in a wave build in parallel under per-task leases, every task merges only after a pinned non-author review, and integration verification runs between waves. The lead drives the lease lifecycle from `$ROOT/scripts/invoke-external.sh`; `ROOT` is the plugin root — `${CLAUDE_PLUGIN_ROOT:-$ROOT}` under Claude Code, else the path the `at-` skill's locator printed.

**Done when** every task is merged (one squash commit per task on the sprint integration branch) or ledgered as blocked, the last wave's integration verification passed, and the integration branch is promoted or its promotion recorded as blocked (rc 42).

**Safe failure direction:** a task not shown reviewed, merged in order and verified stays open; nothing merges without a pinned non-author reviewer, nothing promotes past a protected-path block, and a 44 stops every lease call until the change it names is read.

## Wave assignment rules

1. A task goes in the earliest wave where ALL its dependencies are satisfied
2. Tasks in the same wave must NOT modify the same files
3. If two tasks share output files, they must be in different waves (dependency order)
4. Tasks with no dependencies go in Wave 1

## Process

### Step 1: Build the dependency graph

From `ops/TASKS.md`: task IDs, `Depends`, `Files`, roles.

### Step 2: Group into waves

Wave 1 holds the tasks with no dependencies and no file conflicts; each later wave holds tasks whose dependencies all sit in earlier waves, with no file conflicts among themselves.

### Step 3: Execute each wave

Drive every task through the per-task loop in [references/builder-pool-protocol.md](references/builder-pool-protocol.md): assign from `ops/roster.toml`, lease, dispatch, collect, pin a non-author reviewer, merge in wave order. Then verify the integration branch (tests, build, lint, no conflicts between outputs, changed files match the plan) and promote, honoring the `[promotion]` gate. Fix failures before the next wave; a fix that changes a future task updates `ops/TASKS.md`. Before any retry, answer: what specifically failed, what concrete change fixes it, and is the same broken approach being repeated (if yes, change strategy).

### Step 4: Final verification

After the last wave: full test suite, build from a clean state, lint, every `ops/TASKS.md` row Done or Blocked.

## Builder-pool wave protocol

Every implementation task — INCLUDING lead-authored ones — is built under a per-task lease and merges only after cross-review by a pinned non-author reviewer. Any roster member is an eligible builder; safety is leases in their own worktrees, the lead-owned ledger `ops/leases.toml` and cross-review before merge (AE3, KTD-10), not write-restriction. The worktree is not a sandbox: the lead merges only its collect snapshot (KTD19) and detects changes to git state and the ledger (rc 44); a builder's write elsewhere in the main checkout goes undetected.

Non-derivable facts:

- `lease_collect` routes on the typed report: `Status: DONE` / `DONE_WITH_CONCERNS` → review; `BLOCKED` / `NEEDS_CONTEXT` → escalated, never review; no `Status:` line → rc 80, report-missing — re-dispatch once with the contract restated, escalate on the second miss. A clean exit alone is never review-ready.
- The pinned reviewer is a DIFFERENT roster member than `builder_cli` (the lead is valid for a task another CLI built), pinned for all ≤ 3 fix cycles; `lease_merge` refuses self-review, an unknown reviewer identity and a merge with no pin. No non-author reviewer live → block and escalate to the user.
- Merge in wave order, never completion order: one squash commit per task on the sprint integration branch, never on the default branch. `lease_promote` runs at wave end; a protected-path diff blocks it (rc 42) and needs the lead or the user as reviewer.
- Every lease call first compares the git state with the lead's baseline; a change the lead did not make returns 44, and `lease_rebaseline` accepts only a change you have read.
- `ops/CHANGELOG.md` rows: builder + reviewer + merge commit from the ledger (`lease_status`).

References: [builder-pool-protocol.md](references/builder-pool-protocol.md) (per-task loop, promotion gate, protected-path override, attribution, merge order, rationalizations) · [failure-handling.md](references/failure-handling.md) (report-missing, same-error kill, reflection, risk scoring) · [integrity-escalations.md](references/integrity-escalations.md) (rc 44) · [model-routing.md](references/model-routing.md) (ladder pointer, never-downgrade trio, Fable override) · [claude.md](references/claude.md) (Claude Code forms) · [example.md](references/example.md) (a four-wave plan).

## Rulings, not stalls

When a decision is needed mid-wave and no user is available, rule and continue; the sprint parks only on the four hard stops. Every ruling is one line in the wave ledger and in `ops/CHANGELOG.md`:

```
Ruling: <decision> — <reason>
```

Add the cost if the ruling is wrong when it is not obvious from the reason; the wrap step exports every `Ruling:` line before the completion marker. Rule on: a plan conflict between tasks, an ambiguous acceptance criterion, a reviewer finding the plan did not anticipate, an optional dependency, a choice between equivalent approaches, whether a wave proceeds without an escalated task, what context a `NEEDS_CONTEXT` builder gets, whether a 44 was yours or a builder's.

### The four hard stops

1. **Destructive or irreversible actions** — deleting data or history, force-removing a worktree with uncommitted output, dropping a schema, anything marked `Reversibility: one-way`.
2. **Pushes to shared branches** — any `git push`, publish or release; `lease_promote` while the promotion gate is on.
3. **Changes to the controls that govern the pool** — any diff touching a protected path: the lead or the user reviews it, never an external CLI alone; it may merge to the integration branch, and its promotion stops at hard stop 2 (rc 42).
4. **A settled decision proving infeasible** — report the evidence; never silently choose a different course.

On a hard stop, record `Stop: <what> — <why> — <what the user must decide>` in the same ledger, finish every task that does not depend on it, then pause.

## Red Flags

Stop and re-read the protocol when you are about to merge a task you built or one with no pinned reviewer; when output with no `Status:` line is being read as done; before `lease_rebaseline` without having read what the 44 named; when a task merges because it finished rather than because its wave position is next; when "escalate to user" is typed for anything but a hard stop; when a wave dispatches before the previous one was verified; when a retry starts without the reflection answers.

## Wave execution modes

### Subagent mode (default, < 5 tasks per wave)

Each task runs as an independent parallel executor in its own lease, reviewed and merged in wave order in the same session. The Claude Code forms for 5+ tasks or cross-dependent builds (dynamic workflows, team mode) are in [references/claude.md](references/claude.md), under the same lease and cross-review contract.

## Output

After execution, produce: the wave execution summary (tasks per wave, pass/fail, risk scores past threshold); integration verification results per wave and the final verification (tests, build, lint); every `Ruling:` and `Stop:` line in order; report-missing and escalated leases with their output paths; every rc 44 and how it was resolved (rebaselined or reclaimed); `ops/TASKS.md` with every task Done or Blocked.
