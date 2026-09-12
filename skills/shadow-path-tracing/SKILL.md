---
name: shadow-path-tracing
description: "Failure-path enumeration for every planned task across inputs, external dependencies, and state transitions, each with a handling status, producing the shadow-path table and the error/rescue map. Use when writing or validating a plan, when a task touches external calls, storage, or state, or when a review asks what happens on the unhappy path. Not for diagnosing a failure that already happened; that is systematic-debugging."
metadata:
  triforge-consumer: "Claude (lead)"
  triforge-phase: "1b (planning); 1.5 (plan validation)"
  version: "3.3.0"
---

# Shadow Path Tracing

Every feature has a happy path and shadow paths. Plan for both.

## What are shadow paths?

Shadow paths are the failure, error, and edge-case flows that exist alongside the happy path. They include:
- Invalid inputs (null, empty, wrong type, too large, malformed)
- Missing data (record not found, empty result set, null references)
- Conflicts (duplicate entries, concurrent modifications, stale data)
- External failures (timeout, rate limit, service unavailable, network error)
- Authorization failures (expired token, insufficient permissions, revoked access)
- State violations (out-of-order operations, already-processed, expired)

## How to trace

For each task in the plan:

### 1. Identify the happy path
What happens when everything works correctly?

### 2. Enumerate inputs
What are all the inputs to this operation? For each input:
- What if it's null/undefined?
- What if it's empty (empty string, empty array, zero)?
- What if it's the wrong type?
- What if it exceeds limits (too long, too large, negative)?

### 3. Enumerate external dependencies
What external systems does this touch? For each:
- What if it times out?
- What if it returns an error?
- What if it returns unexpected data?
- What if it's rate-limited?
- What if it's completely unavailable?

### 4. Enumerate state transitions
What state changes does this operation cause? For each:
- What if the state is already in the target state?
- What if concurrent operations are modifying the same state?
- What if the operation partially completes (crash mid-way)?

## Common rationalizations

| Excuse | Reality |
|---|---|
| "The happy path is the feature; error handling is polish" | Shadow paths are task scope. A task without them ships the 500. |
| "Mark it Handled, we will add the code later" | Handled means the code exists or is in a task row. Otherwise it is a "?" and becomes a subtask. |
| "Leave the ? rows, the builder will figure it out" | Every "?" becomes a subtask before the plan is validated. The builder is not the planner. |
| "This path cannot happen in practice" | Then write why as the handling ("acceptable risk: ..."). An unwritten reason is an unhandled path. |

## Output

### Shadow path table

| Task | Happy path | Shadow paths | Handling |
|---|---|---|---|
| T1: Create user | 201 Created + user object | Duplicate email → 409; Invalid email → 400; DB down → 503; Weak password → 422 | All handled |
| T2: Send welcome email | Email delivered | SMTP timeout → retry 1x; Invalid email format → log + skip; Queue full → ? | "?" needs subtask |

### Error/rescue map

For tasks with external calls or DB operations:

| Operation | Failure mode | Response | Status |
|---|---|---|---|
| DB insert user | Unique constraint | 409 Conflict | Handled |
| DB insert user | Connection timeout | Retry 1x → 503 | Handled |
| Send email | SMTP rejected | Log, continue without email | Handled |
| Call billing API | 429 Rate limited | Exponential backoff 3x | Handled |
| Call billing API | 500 Server error | ? | **Needs subtask** |

## Rules

1. Every "?" in the handling column automatically becomes a subtask
2. "Handled" means specific code exists (or will be written) for that path
3. Shadow paths are NOT optional nice-to-haves — they are required task scope
4. Review shadow path coverage during plan validation (Phase 1.5)
5. If a shadow path is intentionally unhandled, document WHY (e.g., "acceptable risk for MVP")
