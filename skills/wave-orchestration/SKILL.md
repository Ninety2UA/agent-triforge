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
   - Isolate tasks that touch overlapping directories (separate execution contexts)
   - Spawn-time Fable override: when the current probe record (`ops/research/2026-07-probe-record.md`, row CC-02) shows Fable 5 PASS on the host, spawn team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) with a model override to `fable` (the Agent tool's `model` parameter)
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
5. **Reflect (on retry):** Before retrying any failed task, the executor MUST answer:
   - What specifically failed?
   - What concrete change will fix it?
   - Am I repeating the same broken approach? If yes, try a fundamentally different strategy.

### Step 4: Final verification

After all waves complete:
- Run full test suite
- Build from clean state
- Verify all tasks in TASKS.md are marked Done
- Run lint

## Wave execution modes

### Subagent mode (default, < 5 tasks per wave)

Each task dispatched as an independent parallel executor:
- Lighter weight, same session
- Results returned directly
- Good for focused, independent tasks

### Dynamic workflow mode (5+ tasks or cross-dependent)

For 5+-task waves, author the wave as a native Claude Code dynamic workflow (`ultracode:` prefix) instead of hand-dispatching each subagent. The dependency-grouping process above (Steps 1–2) IS the workflow-authoring method — the wave plan translates directly:

- **Stages:** each wave becomes a workflow stage — tasks within a wave run as a `parallel` group; waves chain as a `pipeline` in dependency order
- **Integration verification:** the between-wave verify (Step 3.3) runs as its own stage between parallel groups; external-CLI steps (Antigravity/Codex via `invoke_antigravity`/`invoke_codex`) dispatch as workflow steps like any other
- **Mid-run requeue:** a failed task re-enters its stage via a workflow loop with the reflection questions (Step 3.5) prepended, instead of aborting the run
- **Pinned reviewer:** give the continuous reviewer a fixed label so review work routes to the same instance across stages (1:3–4 ratio with builders)

Capability basis: probe CC-04 in `ops/research/2026-07-probe-record.md` (PASS, expressibility) — dynamic workflows on Claude Code ≥ 2.1.212 can express external-CLI dispatch + requeue + pinned review. The live dogfooded wave lands with the builder-pool wave unit.

### Team mode (experimental alternative for cross-dependent builds)

> **Note:** Team mode requires Claude Code's experimental Agent Teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`). This mode is Claude-specific and not available when this skill is injected into Antigravity or Codex.

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
  T6: Documentation (Antigravity)
  T7: Security review (Antigravity + Codex parallel)
```

## Output

After execution, produce:
- Wave execution summary (tasks per wave, pass/fail)
- Integration verification results between each wave
- Final verification results (tests, build, lint)
- Risk score per executor (if any exceeded thresholds)
- Updated TASKS.md with all tasks marked Done or Blocked

## Model routing discretion

Shipped frontmatter floors at `opus` — no shipped file names a model a host may lack. team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) ship at `effort: max`; the other 15 agents ship at `effort: xhigh`. When spawning subagents for narrow, rubric-following tasks (e.g., learnings-researcher, convention-enforcer), you MAY step down the runtime ladder one tier at a time:

Downgrade ladder for narrow runtime tasks: `fable`+`max` (lead + never-downgrade tier when available; otherwise latest `opus` at `max` — the model steps down, the effort does not) → `opus` (4.8) + `xhigh` → `opus`+`high` → `sonnet` (5) + `high`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.

- Pick the smallest downgrade that fits the task — don't skip to Sonnet when Opus/xhigh would do.
- Only downgrade for tasks with clear rubrics and limited scope.

## Same-error kill criteria

Track error recurrence per executor:
1. When an executor hits an error, fingerprint it (core error message, stripped of line numbers and timestamps)
2. If the same fingerprint appears **3+ times** across retries of the same task:
   - **Kill** the executor immediately
   - **Reassign** the task to a fresh executor with context: "Previous executor failed 3+ times on this error: [error fingerprint]. Do NOT repeat the same approach. Try a fundamentally different strategy."
3. Log killed executors in the wave execution summary

## Post-task reflection (conditional)

After a task completes, check if reflection is warranted:
- Task took **>3 retries/iterations** to complete, OR
- Task produced **test failures** that required fixes, OR
- Task modified **>5 files**

If any condition is met, append a reflection entry to `ops/MEMORY.md`:

```markdown
## Reflection: [task ID] ([date])
- **Surprise:** [What was unexpected or non-obvious]
- **Pattern:** [One reusable pattern worth adding to conventions]
- **Improvement:** [One prompt or process improvement suggestion]
```

Skip reflection for tasks that completed cleanly on first attempt.

## Risk scoring during execution

Track risk accumulation per executor:
- Revert of own changes: +15%
- Each file modified beyond task scope: +20%
- Each multi-file change: +5%
- Halt executor when risk > 20% or file changes > 50
- Escalate to lead for manual review
