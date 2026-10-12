# Lightweight workflow

## 1. Understand the change

Read the relevant files. Check `ops/MEMORY.md` for gotchas related to this area.

## 2. Write a failing test (if applicable)

Follow TDD — write a test that captures the expected behavior. Skip only if the change is purely cosmetic (docs, comments, config).

## 3. Make the change

Implement the fix directly. No sub-agents, no wave orchestration — just do it.

## 4. Verify

- Run the existing tests — nothing should break.
- Run the new test — it should pass.
- Quick lint check.

## 5. Lightweight review (self-review)

Review your own change through these lenses:

- Does it match `ops/CONTRACTS.md` types?
- Does it follow patterns in `ops/MEMORY.md`?
- Any obvious security issues? (injection, auth, data exposure)
- Any performance concerns? (N+1, O(n²), unbounded)

If any of these raise concerns, escalate to `at-review --security` or `at-review --perf` instead. If the blast radius grew past trivial while you worked, raise the ceremony rather than adding a single review lens.

## 6. Wrap up

- Update `ops/CHANGELOG.md` (1–2 lines).
- Update `ops/MEMORY.md` if you discovered a gotcha.
- If the fix was non-trivial, document it in `ops/solutions/` via the `knowledge-compounding` skill.
