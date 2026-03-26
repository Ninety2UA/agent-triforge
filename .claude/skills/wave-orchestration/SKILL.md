---
name: wave-orchestration
description: "Dependency-grouped parallel execution with integration verification between waves. Primary consumer: Claude Code (Phase 2 complex builds)."
---

# Wave Orchestration

Organize tasks into dependency-grouped waves. Tasks within a wave run in parallel; integration verification runs between waves.

## Wave assignment rules

1. A task goes in the **earliest wave** where ALL its dependencies are satisfied
2. Tasks in the **same wave** must NOT modify the same files
3. If two tasks share output files, they must be in different waves (dependency order)
4. Tasks with no dependencies go in Wave 1

## Process

### Step 1: Build the dependency graph

From TASKS.md, extract:
- Task IDs
- Dependencies (Depends field)
- File paths (Files field)
- Agent assignments

### Step 2: Group into waves

```
Wave 1: [tasks with no dependencies, no file conflicts]
Wave 2: [tasks depending on Wave 1, no file conflicts among themselves]
Wave 3: [tasks depending on Wave 1-2, no file conflicts]
...
```

### Step 3: Execute each wave

For each wave:

1. **Dispatch:** Launch all tasks in the wave in parallel
   - Each executor gets: task description, relevant CONTRACTS.md types, file paths
   - Isolate tasks that touch overlapping directories (worktrees in Claude, sandboxes in Codex)
2. **Collect:** Wait for all executors to complete
3. **Verify:** Run the integration verifier:
   - All tests pass
   - Build succeeds
   - Linter clean
   - No merge conflicts between wave outputs
   - Changed files match expected file list (no off-topic changes)
4. **Decide:**
   - All clear → proceed to next wave
   - Failures → fix before proceeding (do NOT start next wave with broken state)
   - If a fix requires changing a task in a future wave, update TASKS.md

### Step 4: Final verification

After all waves complete:
- Run full test suite
- Build from clean state
- Verify all tasks in TASKS.md are marked Done
- Run lint

## Wave execution modes

### Parallel mode (default, < 5 tasks per wave)

Each task dispatched as an independent parallel executor:
- Lighter weight, same session
- Results returned directly
- Good for focused, independent tasks

### Team mode (complex, 5+ tasks or cross-dependent)

Each task assigned to a coordinated team worker:
- Workers coordinate via shared task list
- Direct messaging for cross-task questions
- Quality gates enforced between waves
- Orchestrator monitors and resolves conflicts

## Example

```
Goal: Build user authentication system

Wave 1 (parallel, no dependencies):
  T1: Define auth interfaces in CONTRACTS.md (Claude)
  T3: Set up JWT library configuration (Claude)

  → Integration verify: interfaces compile, config loads

Wave 2 (parallel, depends on Wave 1):
  T2a: Implement registration endpoint
  T2b: Implement login endpoint
  T2c: Implement token refresh endpoint

  → Integration verify: all endpoints compile, unit tests pass

Wave 3 (depends on Wave 2):
  T4: Integration tests (Codex)
  T5: Auth middleware (Claude)

  → Integration verify: full test suite, build clean

Wave 4 (depends on Wave 3):
  T6: Documentation (Gemini)
  T7: Security review (Gemini + Codex parallel)
```

## Output

After execution, produce:
- Wave execution summary (tasks per wave, pass/fail)
- Integration verification results between each wave
- Final verification results (tests, build, lint)
- Risk score per executor (if any exceeded thresholds)
- Updated TASKS.md with all tasks marked Done or Blocked

## Risk scoring during execution

Track risk accumulation per executor:
- Revert of own changes: +15%
- Each file modified beyond task scope: +20%
- Each multi-file change: +5%
- Halt executor when risk > 20% or file changes > 50
- Escalate to lead for manual review
