# Archive, verification, session continuity, summary and completion

## Step 3: archive temporary files

Move to `ops/archive/<today's date>/`:

- `ops/REVIEW_ANTIGRAVITY.md` (if it exists)
- `ops/REVIEW_CODEX.md` (if it exists)
- `ops/TEST_RESULTS.md` (if it exists)

## Step 4: verification checklist

Follow the `verification-before-completion` skill:

- [ ] All assigned tasks marked done (or blocked with explanation)
- [ ] All tests passing
- [ ] No critical/major issues unresolved
- [ ] `ops/CHANGELOG.md` updated
- [ ] `ops/MEMORY.md` updated
- [ ] Rulings I made listed (Step 2b) and deferred findings exported (Step 2c)

## Step 5: session continuity

Follow the `session-continuity` skill and write `ops/STATE.md`:

- Current phase and progress
- Remaining tasks (if any)
- Key context for the next session
- Recommended next actions

## Step 6: sprint summary

Provide the user with:

- What was accomplished
- What remains (if anything)
- Any decisions that need user input
- **Rulings I made**: the exhaustive list from Step 2b (or "none")
- Deferred findings: where they were exported (Step 2c)
- Metrics (tasks completed, tests passing, review cycles)

## Completion

Only when ALL work is verified complete, the rulings list and the deferred-findings export are done (Steps 2b and 2c), and `ops/STATE.md` is written, create the runtime completion marker as the LAST action:

```bash
touch ops/.sprint-complete
```

This gitignored marker is how outer tooling (`$ROOT/scripts/coordinate.sh`) detects sprint completion. If any verification item failed, do NOT create it; document the blocker instead.
