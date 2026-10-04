# Phase 1: planning

Follow the `writing-plans` skill:

1. Read `ops/GOALS.md`, `ops/ARCHITECTURE.md`, `ops/CONTRACTS.md`, `ops/MEMORY.md`, `ops/TASKS.md` and the learnings-researcher output.
2. Decompose the goal into atomic tasks (1–2 hours each).
3. Assign each task a role. `ops/roster.toml` maps role to CLI, model and effort via `resolve_role`; Phase 2 passes the role to `lease_create`:
   - Produces code → builder (the builder pool; Claude Code leads by default)
   - Evaluates code → reviewer (the Claude specialized review agents run in parallel regardless)
   - Runs or executes tests → tester
   - Deep codebase analysis → analyst
   - Documentation → documenter
4. Apply the `shadow-path-tracing` skill: enumerate failure paths for every non-trivial task.
5. Build error/rescue maps for external calls and database operations; any "?" becomes a subtask.
6. Extract the relevant `ops/CONTRACTS.md` types and embed them in each task's Context field.
7. Group tasks into waves for parallel execution.
8. Run the incomplete-plan guard below, then write `ops/TASKS.md`.

## Incomplete-plan guard (AS-6)

Never overwrite another goal's open work. Before writing `ops/TASKS.md`, look for open rows that belong to a different goal:

```bash
# Incomplete-plan guard (AS-6): open `[ ]` / `[-]` rows for another goal must
# not be silently rewritten. Read-only — the decision is made below.
if [ -f ops/TASKS.md ]; then
  OPEN_ROWS=$(grep -c '^- \[ \]\|^- \[-\]' ops/TASKS.md || true)
  echo "open rows in ops/TASKS.md: ${OPEN_ROWS}"
  grep -n -m1 -i '^# \|^Goal:\|^Ceremony:' ops/TASKS.md || true
fi
```

If the count is nonzero and the recorded goal is not the current goal (or the rows plainly describe other work), stop and ask the user what to do with the open rows — one of three answers:

- **archive** them: move them to `ops/archive/<YYYY-MM-DD>-tasks-<old-goal-slug>.md`;
- **merge** them into the new plan as their own wave;
- **abandon** them: mark `[x]` with an "abandoned: <reason>" note.

Open rows for the same goal are a continuation — fold them in without asking.

When unattended — headless or autonomous (`$ROOT/scripts/coordinate.sh`, an `at-ship` run with no user answering) — do not stall: rule **archive** (the recoverable choice), move the rows to the dated archive file, record the ruling in `ops/CHANGELOG.md` (S1) as

```
Ruling: archived <N> open rows for "<old goal>" | the new goal supersedes them | cost if wrong: rows are recoverable from ops/archive/
```

and continue.
