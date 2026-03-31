---
name: writing-plans
description: "Methodology for decomposing goals into actionable task plans with shadow paths, error maps, and interface context. Primary consumer: Claude Code (Phase 1)."
---

# Writing Plans

Plans are not wishlists. A plan is a contract that, if followed, produces the feature.

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

Each task must be:
- **Atomic:** completable in 1-2 hours of focused work
- **Testable:** has a clear pass/fail condition
- **Assigned:** agent specified using the heuristic matrix
- **Scoped:** files listed, dependencies explicit

Format:
```
- [ ] T1: [imperative verb] [what] [where]
      Agent: Claude | Gemini | Codex
      Files: [specific file paths]
      Depends: T0 | none
      Context: [what the agent needs to know — include relevant types]
      Accept: [how to verify this is done]
```

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
- Each task in the standardized format with Agent, Files, Depends, Context, Accept fields
- Wave assignments for the build phase
- The plan quality checklist (all items checked)

## Plan quality checklist

Before finalizing:
- [ ] Every task has an agent assignment
- [ ] Every task has specific file paths
- [ ] Dependencies form a DAG (no cycles)
- [ ] Shadow paths identified for non-trivial tasks
- [ ] Error/rescue map complete (no "?" rows left unassigned)
- [ ] Relevant interfaces embedded (not just referenced)
- [ ] Parallel opportunities identified and grouped into waves
