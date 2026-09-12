---
name: writing-plans
description: "Goal decomposition into right-sized, lease-ready tasks with Accept and Fails-when criteria, shadow paths, error maps, and interface context. Use when turning a goal into ops/TASKS.md, when a plan-checker verdict asks for task fields to be fixed, or when a task must be split because a builder would face a decision the lead should weigh. Not for validating a finished plan; that is the plan-checker's job."
metadata:
  triforge-consumer: "Claude (lead)"
  triforge-phase: "1b (planning)"
  version: "3.3.0"
---

# Writing Plans

Plans are not wishlists. A plan is a contract that, if followed, produces the feature.

## Before writing ops/TASKS.md: the incomplete-plan guard

`ops/TASKS.md` may already hold a plan for a different goal with open rows. Check before writing:

1. Read `ops/TASKS.md`. If it has unchecked `[ ]` or in-progress `[-]` rows whose goal differs from the current goal, do not overwrite it.
2. Attended: stop and ask the user whether to finish, wrap, or archive the old plan (the session-continuity skill's Wrap step moves it to `ops/archive/<date>/`), or to fold its open rows into the new plan.
3. Unattended: rule and ledger it (`Ruling: archived <N> open rows of goal <X> to ops/archive/<date>/TASKS.md — superseded by <current goal>`), then proceed. Never silently drop open work.

## Structure

Every plan must contain:

### 1. Goal statement (1-2 sentences)
What the user wants and why. Not how.

### 2. Interface context extraction
Extract and embed the relevant types/interfaces directly in the plan. Agents reading this plan should NOT need to explore the codebase to find type definitions.

```
Key interfaces (from CONTRACTS.md):
- User: { id: string; email: string; role: 'admin' | 'member' }
- CreateUserRequest: { email: string; password: string; role?: string }
- UserResponse: Omit<User, 'passwordHash'>
```

### 3. Task decomposition

A task is right-sized when one builder can finish it in one lease without a mid-task decision the lead would weigh. If the builder would have to choose between designs, split the task at that decision or make the decision in the plan.

Each task must be:
- **Atomic:** right-sized as above (as a rule of thumb, 1-2 hours of focused work)
- **Testable:** has an observable pass condition AND a concrete failure condition
- **Assigned:** role specified from the roster (builder | reviewer | tester | analyst | documenter) — `resolve_role` maps it to a CLI via `ops/roster.toml`
- **Scoped:** files listed, dependencies explicit

Format:
```
- [ ] T1: [imperative verb] [what] [where]
      Role: builder | reviewer | tester | analyst | documenter
      Files: [specific file paths]
      Depends: T0 | none
      Precondition: [what must already be true before dispatch — a read-only check the lead can run]
      Context: [what the agent needs to know — include relevant types]
      Accept: [the observable acceptance — a command or observation and its expected result]
      Fails when: [the concrete failure condition that proves Accept is not met]
      Reversibility: one-way | checkpointed | reversible
```

Field rules:

- **Accept:** observable, and runnable wherever a command exists (`bash scripts/validate-skills.sh` exits 0 with twelve skills listed; the endpoint returns 201 with the user object). For documenter and analyst tasks, name the artifact and the sections it must contain.
- **Fails when:** the concrete signal that proves the Accept is not met (`exit code nonzero or fewer than twelve skills listed`; `any 5xx on the happy path`). It is the falsifying direction of Accept, not a restatement. Placeholders such as `TBD`, `N/A`, `none`, `unknown`, or `?` are rejected by the plan-checker.
- **Precondition:** a read-only check the lead runs before dispatch (`ops/CONTRACTS.md` defines `User`; branch `feat/x` exists; the fixture directory is empty). Omit only when the task has no prerequisite state beyond `Depends:`.
- **Reversibility:** `reversible` (a VCS revert undoes it), `checkpointed` (undoable only from a checkpoint taken first: a backup, a tagged commit, a scratch copy; name the checkpoint in `Precondition:`), or `one-way` (cannot be undone: data deletion, schema drop, external publish, a push to a shared branch). A `one-way` task is a hard stop in wave execution; it needs a user checkpoint in the plan, and the plan-checker flags one without it.

### 4. Shadow path tracing

For each task, enumerate what could go wrong:

| Task | Happy path | Shadow paths |
|---|---|---|
| T1: Create user endpoint | Returns 201 with user | Duplicate email → 409; invalid email format → 400; DB connection lost → 503; password too weak → 422 |

Every shadow path must have a handling status:
- **Handled:** implementation covers this
- **?:** unknown — automatically becomes a subtask

### 5. Error/rescue map

For tasks involving external calls, DB operations, or async work:

| Operation | Failure mode | Handling |
|---|---|---|
| DB insert | Unique constraint violation | Return 409 Conflict |
| DB insert | Connection timeout | Retry 1x, then 503 |
| Email send | SMTP failure | Queue for retry, continue |
| API call | Rate limited | Exponential backoff, max 3 |
| API call | ? | Unknown — needs investigation |

Any "?" row becomes a subtask assigned to the investigating agent.

### 6. Dependency graph

```
T1 (types) ──→ T2 (implementation) ──→ T4 (tests)
                                    ──→ T5 (docs)
T3 (config) ──→ T2
```

Tasks with no dependency arrows between them can run in parallel.

### 7. Wave assignment (for parallelization)

Group tasks into waves:
```
Wave 1 (parallel): T1, T3 — no shared files
Wave 2 (parallel): T2a, T2b — shared dependency on T1, but different files
Wave 3 (sequential): T4 — depends on T2
Wave 4 (parallel): T5, T6 — independent
```

## Output

Produce ops/TASKS.md containing:
- All sections above (goal, interfaces, tasks, shadow paths, error map, dependency graph, waves)
- Each task in the standardized format with Role, Files, Depends, Precondition, Context, Accept, Fails when, and Reversibility fields
- Wave assignments for the build phase
- The plan quality checklist (all items checked)

## Plan quality checklist

Before finalizing:
- [ ] The incomplete-plan guard was applied (no open rows from another goal were overwritten)
- [ ] Every task has a role assignment
- [ ] Every task has specific file paths
- [ ] Every task is right-sized (no mid-task decision the lead would weigh)
- [ ] Every task has an `Accept:` and a `Fails when:` with no placeholder
- [ ] Every task has a `Reversibility:`; every `one-way` task has a user checkpoint
- [ ] Dependencies form a DAG (no cycles)
- [ ] Shadow paths identified for non-trivial tasks
- [ ] Error/rescue map complete (no "?" rows left unassigned)
- [ ] Relevant interfaces embedded (not just referenced)
- [ ] Parallel opportunities identified and grouped into waves
