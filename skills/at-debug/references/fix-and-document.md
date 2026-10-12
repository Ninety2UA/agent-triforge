# Steps 3–4: fix and document

## Step 3: fix

1. Fix the ROOT cause, not the symptom.
2. Run the failing test from Step 1 — it should now pass.
3. Run the full test suite — no regressions.
4. Check whether similar patterns exist elsewhere (search for the same anti-pattern). If found, create tasks in `ops/TASKS.md` for those instances.

## Step 4: document

- Log the root cause in `ops/MEMORY.md#Gotchas`.
- If the bug took more than 30 minutes or was non-obvious, document it in `ops/solutions/` via the `knowledge-compounding` skill.
- Update `ops/CHANGELOG.md` with the fix and the root cause.
