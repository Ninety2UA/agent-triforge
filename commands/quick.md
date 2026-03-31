---
description: "Lightweight workflow for small changes (< 3 files). Skips Phase 0, plan validation, and full review swarm."
argument-hint: "<change description>"
---

You are making a small, focused change. Use the lightweight workflow — skip the heavy multi-agent machinery.

## Input
$ARGUMENTS

## When to use /quick vs /ship

- **/quick:** < 3 files changed, obvious fix, low risk
- **/ship:** Multi-file features, architectural changes, anything security-sensitive

## Lightweight workflow

### 1. Understand the change
Read the relevant files. Check ops/MEMORY.md for gotchas related to this area.

### 2. Write a failing test (if applicable)
Follow TDD — write a test that captures the expected behavior. Skip only if the change is purely cosmetic (docs, comments, config).

### 3. Make the change
Implement the fix directly. No subagents, no wave orchestration — just do it.

### 4. Verify
- Run existing tests — nothing should break
- Run the new test — it should pass
- Quick lint check

### 5. Lightweight review (self-review)
Review your own change through these lenses:
- Does it match ops/CONTRACTS.md types?
- Does it follow patterns in ops/MEMORY.md?
- Any obvious security issues? (injection, auth, data exposure)
- Any performance concerns? (N+1, O(n²), unbounded)

If ANY of these raise concerns, escalate to `/review --security` or `/review --perf` instead.

### 6. Wrap up
- Update ops/CHANGELOG.md (1-2 lines)
- Update ops/MEMORY.md if you discovered a gotcha
- If the fix was non-trivial, document in ops/solutions/ via knowledge-compounding skill
