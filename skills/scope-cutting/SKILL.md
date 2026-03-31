---
name: scope-cutting
description: "Systematically cut scope when a sprint is too large. Prioritize by unblocking value and risk reduction."
---

# Scope Cutting

When a sprint has too many tasks, too many review cycles, or is running over time — cut scope systematically, not arbitrarily.

## When to cut scope

- Sprint has > 15 tasks
- Review cycle 3 still has P2 issues
- Context window approaching limits (150+ tool calls)
- User requests faster delivery
- Estimated effort exceeds available time

## Cutting methodology

### Step 1: Classify every task by value type

| Value type | Definition | Example |
|---|---|---|
| **Unblocking** | Enables other tasks or future work | Define types in CONTRACTS.md |
| **Core** | Directly delivers the requested feature | Implement the API endpoint |
| **Hardening** | Makes existing code more robust | Add error handling for edge cases |
| **Polish** | Improves quality without changing behavior | Refactor naming, add docs |
| **Speculative** | Prepares for hypothetical future needs | Add plugin system, config options |

### Step 2: Assign cut priority

Cut in this order (cut speculative first, unblocking last):

```
KEEP (never cut)     ← Unblocking tasks
KEEP (strongly)      ← Core tasks
CUT IF NEEDED        ← Hardening tasks
CUT FIRST            ← Polish tasks
CUT IMMEDIATELY      ← Speculative tasks
```

### Step 3: Apply the cut

For each cut task:
1. Move to a BACKLOG section in TASKS.md (don't delete — preserve the work)
2. Add a note: `Cut reason: [scope reduction] | Priority: [P3]`
3. If the cut task has dependents, assess if dependents can proceed without it
4. If a dependent can't proceed, either keep the task or cut the dependent too

### Step 4: Verify the reduced plan

After cutting:
- Remaining tasks still deliver the core value
- No broken dependency chains
- Unblocking tasks are all preserved
- Estimate is now feasible

## Rules

- Never cut unblocking tasks — they enable everything else
- Cut speculative work immediately — YAGNI
- Hardening can often be deferred to a follow-up sprint
- Polish is valuable but never urgent
- Document what was cut and why in MEMORY.md for the follow-up sprint
- Always inform the user what was cut and what remains

## Output

```markdown
## Scope cut summary

### Kept ([count] tasks)
- [task] — [value type: unblocking/core]

### Cut ([count] tasks)
- [task] — [value type] — Cut reason: [reason]

### Impact
- Original scope: [N tasks]
- Reduced scope: [N tasks]
- Cut: [N tasks] ([percentage]%)
- Deferred to follow-up: [list]
```
