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

For each wave, drive every task through the builder-pool protocol below (leases + cross-review); the per-task mechanics are detailed in "Builder-pool wave protocol":

1. **Assign + dispatch:** For each task, resolve its builder from `ops/roster.toml` (`resolve_role <role>`) and open a lease — `lease_create` carves an isolated worktree, `lease_dispatch` launches the builder with context injected (task rows, relevant CONTRACTS.md slice, roster entry). Tasks in a wave run in parallel; each builder is confined to its own worktree, so overlapping-directory isolation is automatic.
   - Spawn-time Fable override: when the current probe record (`ops/research/2026-07-probe-record.md`, row CC-02) shows Fable 5 PASS on the host, spawn team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) with a model override to `fable` (the Agent tool's `model` parameter)
2. **Collect + cross-review:** `lease_heartbeat_check` until each builder exits, then `lease_collect` (state → review, prints the output path). Pin a non-author reviewer (a DIFFERENT roster member than the builder — the lead itself is valid) and review the collected output. Approved work merges as ONE commit per task on the sprint integration branch (`lease_merge <task> <reviewer>`, which REFUSES self-review — AE3); findings re-dispatch the same lease to the same builder with the same pinned reviewer, cycle < 3.
3. **Verify:** At wave end, run the integration-verifier against the sprint integration branch (combined verification across the wave's merged tasks):
   - All tests pass
   - Build succeeds
   - Linter clean
   - No merge conflicts between wave outputs
   - Changed files match expected file list (no off-topic changes)
4. **Promote + decide:**
   - All clear → promote the integration branch to the main branch honoring the `[promotion]` gate (see the protocol), then proceed to next wave
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

## Builder-pool wave protocol

Every implementation task in a wave — INCLUDING lead-authored ones — is built under a per-task lease and merges only after cross-review by a pinned non-author reviewer. The single-writer rule is retired: any roster member (claude, codex, antigravity, and any enrolled optional member) is an eligible builder. Safety comes from three mechanisms, not from write-restriction — per-task leases in isolated git worktrees (builders never touch the canonical `ops/` tree — KTD-3), a lead-owned ledger (`ops/leases.toml`), and mandatory cross-review before merge (AE3, KTD-10). This protocol layers onto both execution paths below: the < 5-task subagent path and the 5+-task dynamic-workflow path.

Assignment reads `ops/roster.toml` per task's role via `resolve_role` (the roster maps builder | reviewer | tester | analyst | documenter → CLI + model + effort, with validated fallback chains). The lead injects context and performs all `ops/` mutations and merges on the main tree; builders run confined to their worktrees.

### The per-task loop

Source `${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh`, then for each task:

1. `lease_create <task_id> <role>` — resolves the builder from the roster, carves an isolated worktree + `lease/<task_id>` branch, provisions `.agents/skills/`, writes the `leased` row.
2. `lease_dispatch <task_id> <prompt> [timeout]` — the lead injects context (the task's TASKS.md rows, the relevant CONTRACTS.md slice, the roster entry) into the prompt; the builder runs in the BACKGROUND in its worktree under a per-adapter env allowlist. The builder commits nothing.
3. `lease_heartbeat_check [task_id]` — sweep until the builder exits. Orphan / timeout / silent-death handling requeues ONCE to a DIFFERENT builder (KTD-9) or escalates; a deterministic failure (auth, absent CLI) fails fast with guidance and does NOT requeue.
4. `lease_collect <task_id>` — lead-side harvest. A clean exit sets state `review` and prints the output-file path.
5. **Pin the reviewer.** Choose a reviewer that is a DIFFERENT roster member than the lease's `builder_cli`. The lead (Claude) is a valid reviewer for any task built by a *different* CLI — but a Claude-built task needs a *non-Claude* reviewer (the `reviewer` role default, Codex, provides this), because the AE3 guard correctly refuses `reviewer == builder_cli`. The reviewer pinned here stays this task's reviewer for ALL ≤3 fix cycles (KTD-10): no rubric flip-flop when the roster shifts mid-sprint. Self-review is never allowed; **if no non-author agent is live, the merge blocks and escalates to the user.**
6. **Review the collected output**, then:
   - **Approved →** `lease_merge <task_id> <reviewer>` — snapshots the builder's worktree changes as ONE squash commit on the sprint integration branch, records reviewer + merge_commit in the ledger, and reclaims the worktree. `lease_merge` REFUSES when the reviewer equals `builder_cli` (AE3) — self-review never merges.
   - **Findings, cycle < 3 →** re-dispatch the SAME lease's task to the SAME builder with the reviewer's findings appended, keeping the SAME pinned reviewer; the lease returns to `building` (state transition `review → building`).
   - **Cycle 3 reached →** escalate to the user.

### Integration branch and promotion gate

Approved merges land as one commit per task on a **sprint integration branch**, never directly on the main branch (`lease_merge` REFUSES to run when the main tree is checked out on the default branch — cut an integration branch first). At wave end, the integration-verifier gate (Step 3 Verify) runs against the integration branch — combined verification across the wave's merged tasks — BEFORE the lead promotes to the main branch via **`lease_promote`** (the actual promotion mechanism).

Promotion honors the KTD-5 `[promotion]` gate in `ops/roster.toml`: `lease_promote` reads `require_user_approval` (default `false`) — when true, it BLOCKS and the lead pauses for explicit user approval before promoting.

**Protected-path override.** Any task whose diff touches permission configs, deny rules, `ops/roster.toml` (including its `[promotion]` block), or shipped agent configs forces the promotion gate ON regardless of the knob, AND requires the lead or the user as the cross-reviewer — never an external-CLI-only review. This keeps a builder from self-promoting a change to the very controls that govern the pool. `lease_promote` enforces this: it scans the integration diff against that protected-path set and BLOCKS (distinct nonzero rc, no merge) on any match, even when `require_user_approval = false`.

### Attribution

Every merged task's `ops/CHANGELOG.md` row carries **builder + reviewer + merge commit**, read from the ledger (`lease_status`, or the row's `builder_cli` / `reviewer` / `merge_commit` fields). Attribution is mandatory — the ledger is the source of truth for who built and who reviewed each commit. The ≤3-cycle review escalation and the same-error kill criteria (below) both still apply.

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

Capability basis: probe CC-04 in `ops/research/2026-07-probe-record.md` (PASS, expressibility) — dynamic workflows on Claude Code ≥ 2.1.212 can express external-CLI dispatch + requeue + pinned review. The "Builder-pool wave protocol" above is the lease/cross-review contract those stages carry; it is dogfooded end-to-end (two-task wave, cross-review, single-commit merges, AE3 refusal) in the unit that introduced it.

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
