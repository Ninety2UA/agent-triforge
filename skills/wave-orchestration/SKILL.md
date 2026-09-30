---
name: wave-orchestration
description: "Dependency-grouped parallel build execution under per-task leases with pinned non-author cross-review, merges in wave order, rulings instead of stalls, and integration verification between waves. Use when executing a validated plan of two or more tasks (Phase 2), when a lease returns without a typed report, when a lease call refuses with rc 44 (integrity) or lease_promote blocks with rc 42, or when a mid-wave decision would otherwise park the sprint. Not for writing the plan; that is writing-plans."
metadata:
  triforge-consumer: "Claude (lead)"
  triforge-phase: "2 (build)"
  version: "3.3.0"
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

1. **Assign + dispatch:** For each task, resolve its builder from `ops/roster.toml` (`resolve_role <role>`) and open a lease — `lease_create` carves an isolated worktree, `lease_dispatch` launches the builder with context injected (task rows, relevant CONTRACTS.md slice, roster entry). Tasks in a wave run in parallel; each builder starts in its own worktree, so parallel builders never share a checkout (a contract, not a sandbox).
   - Spawn-time Fable override: when the newest `ops/research/*-probe-record.md` (`latest_probe_record` in scripts/invoke-external.sh), row CC-02, shows Fable PASS on the host, spawn team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) with a model override to `fable` (the Agent tool's `model` parameter)
2. **Collect + cross-review:** `lease_heartbeat_check` until each builder exits, then `lease_collect`, which routes on the builder's typed report: `Status: DONE` or `DONE_WITH_CONCERNS` → state `review` (prints the output path); `BLOCKED` or `NEEDS_CONTEXT` → state `escalated`, never review; no `Status:` line → report-missing (rc 80; see "Report-missing leases" below). Pin a non-author reviewer (a DIFFERENT roster member than the builder — the lead itself is valid) and review the collected output. Approved work merges as ONE commit per task on the sprint integration branch (`lease_merge <task> <reviewer>`, which REFUSES self-review — AE3), **in wave order, never completion order** (see "Merge in wave order" below); findings re-dispatch the same lease to the same builder with the same pinned reviewer, cycle < 3. When a decision is needed and no user is available, rule and ledger it (see "Rulings, not stalls") instead of parking the wave.
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

Every implementation task in a wave — INCLUDING lead-authored ones — is built under a per-task lease and merges only after cross-review by a pinned non-author reviewer. The single-writer rule is retired: any roster member (claude, codex, antigravity, and any enrolled optional member) is an eligible builder. Safety comes from three mechanisms, not from write-restriction: per-task leases in their own git worktrees, a lead-owned ledger (`ops/leases.toml`), and mandatory cross-review before merge (AE3, KTD-10). A worktree is where a builder starts, not a sandbox: the dispatch contract keeps it inside its worktree and out of the canonical `ops/` tree (KTD-3), and nothing enforces that. The lead merges only the snapshot it took at collect (KTD19) and detects changes to git state and the ledger (see "Integrity escalations (rc 44)"); a builder's write to any other file in the main checkout, including the rest of `ops/`, goes undetected. This protocol layers onto both execution paths below: the < 5-task subagent path and the 5+-task dynamic-workflow path.

Assignment reads `ops/roster.toml` per task's role via `resolve_role` (the roster maps builder | reviewer | tester | analyst | documenter → CLI + model + effort, with validated fallback chains). The lead injects context and performs all `ops/` mutations and merges on the main tree; builders run in their own worktrees under the dispatch contract.

### The per-task loop

Source `${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh`, then for each task:

1. `lease_create <task_id> <role>` — resolves the builder from the roster, carves an isolated worktree + `lease/<task_id>` branch, provisions `.agents/skills/`, writes the `leased` row.
2. `lease_dispatch <task_id> <prompt> [timeout]` — the lead injects context (the task's TASKS.md rows, the relevant CONTRACTS.md slice, the roster entry) into the prompt; the builder runs in the BACKGROUND in its worktree under a per-adapter env allowlist. The builder commits nothing.
3. `lease_heartbeat_check [task_id]` — sweep until the builder exits. Orphan / timeout / silent-death handling reclaims the lease and requeues it ONCE to a DIFFERENT builder via `lease_requeue <task_id>` (KTD-9), or escalates; a deterministic failure (auth, absent CLI) fails fast with guidance and does NOT requeue.
4. `lease_collect <task_id>` — lead-side harvest. A clean exit is routed by the builder's final typed report (KTD11): `Status: DONE` / `DONE_WITH_CONCERNS` → state `review`, output path printed, the builder's "Discoveries for later tasks" copied into `ops/MEMORY.md`; `Status: BLOCKED` / `NEEDS_CONTEXT` → state `escalated`, never review (the lead reads the report, supplies the missing context or rules on the blocker, and re-dispatches through the requeue path); no `Status:` line → rc 80, report-missing (below). A clean exit is never review-ready on its own.
5. **Pin the reviewer** — `lease_pin_reviewer <task_id> <reviewer>`. Choose a reviewer that is a DIFFERENT roster member than the lease's `builder_cli`. The lead (Claude) is a valid reviewer for any task built by a *different* CLI — but a Claude-built task needs a *non-Claude* reviewer (the `reviewer` role default, Codex, provides this), because the AE3 guard correctly refuses `reviewer == builder_cli`. `lease_pin_reviewer` records the choice in the ledger so it stays this task's reviewer for ALL ≤3 fix cycles **even across a session boundary** (KTD-10): a fresh session cannot silently re-pin, and `lease_merge` refuses any reviewer that does not match the pin. Self-review is never allowed; **if no non-author agent is live, the merge blocks and escalates to the user.**
6. **Review the collected output**, then:
   - **Approved →** `lease_merge <task_id> <reviewer>` — squashes the snapshot `lease_collect` took (the lead's own commit of the worktree on the recorded base) as ONE commit on the sprint integration branch, records reviewer + merge_commit in the ledger, and reclaims the worktree. It refuses a lease branch that moved after collect or carries commits the builder made itself (naming the commit), a worktree changed after collect, and a diff touching `ops/` (naming the file) — KTD19. Review against the snapshot: anything that writes files in the lease worktree after collect (a reviewer running tests or a formatter there) makes the merge refuse. `lease_merge` REFUSES unless (a) `<reviewer>` is a known adapter identity (a fabricated label like `codex-reviewer` is rejected), (b) it differs from `builder_cli` (AE3 — self-review never merges), and (c) that reviewer was already pinned in step 5 — **the pin is the record that a review happened, so a merge with no pin is refused.** Pin, review, then merge.
   - **Findings, cycle < 3 →** `lease_redispatch <task_id> <prompt-with-findings> [timeout]` re-dispatches the SAME lease's task to the SAME builder with the reviewer's findings appended, keeping the SAME pinned reviewer; it increments `review_cycle` and returns the lease to `building` (state transition `review → building`). This is the ONLY path from `review` back to `building` — `lease_dispatch` requires `leased`, `lease_requeue` requires `requeued`.
   - **Cycle 3 reached →** `lease_redispatch` escalates instead of re-dispatching: it sets state `escalated` and returns a distinct code so the lead pauses for the user (KTD-10 / max 3 review cycles per task).

### Integration branch and promotion gate

Approved merges land as one commit per task on a **sprint integration branch**, never directly on the main branch (`lease_merge` REFUSES to run when the main tree is checked out on the default branch — cut an integration branch first). At wave end, the integration-verifier gate (Step 3 Verify) runs against the integration branch — combined verification across the wave's merged tasks — BEFORE the lead promotes to the main branch via **`lease_promote`** (the actual promotion mechanism).

Promotion honors the KTD-5 `[promotion]` gate in `ops/roster.toml`: `lease_promote` reads `require_user_approval` (default `false`) — when true, it BLOCKS and the lead pauses for explicit user approval before promoting. `lease_promote` has no approve flag: once the user approves, promote by hand (`git checkout <default> && git merge <integration>`) and run `lease_rebaseline` straight after, or the next lease call returns 44 because the default branch moved.

**Protected-path override.** Any task whose diff touches a protected path forces the promotion gate ON regardless of the knob, AND requires the lead or the user as the cross-reviewer — never an external-CLI-only review. The lists live in `${CLAUDE_PLUGIN_ROOT}/scripts/lib/registry.sh`. In every project they cover `ops/roster.toml` (including its `[promotion]` block); each CLI's config and permission tree (`.claude/`, `.codex/`, `.agents/`, `.antigravity/`, `.gemini/`, `.opencode/`, `.kimi-code/`, `.cursor/`, plus `opencode.json`, `opencode.jsonc` and `.cursorrules` at the root); and every `AGENTS.md`, `AGENTS.override.md`, `CLAUDE.md`, `CLAUDE.local.md` and `.mcp.json` at any depth. In the Triforge checkout they also cover the framework's own control plane. This keeps a builder from self-promoting a change to the very controls that govern the pool. `lease_promote` enforces the gate: it scans the integration diff against those lists and BLOCKS (rc 42, no merge) on any match, even when `require_user_approval = false`. The scan is case-folded, sees both sides of a rename, and matches a protected directory's bare name (a symlink in its place); it fails closed: if the scan itself errors, promotion is blocked too. The reviewer rule is yours to keep, because `lease_merge` does not check it: review such a task yourself; if you built it (the pin cannot be your own CLI), pin a non-author CLI so it can merge, and leave the protected-path review to the user at the rc 42 block.

### Attribution

Every merged task's `ops/CHANGELOG.md` row carries **builder + reviewer + merge commit**, read from the ledger (`lease_status`, or the row's `builder_cli` / `reviewer` / `merge_commit` fields). Attribution is mandatory — the ledger is the source of truth for who built and who reviewed each commit. The ≤3-cycle review escalation and the same-error kill criteria (below) both still apply.

### Merge in wave order

Merge in wave order, never completion order. Within a wave, merge approved tasks in their TASKS.md order; a task that finishes and passes review early waits for its predecessors in the wave, so the integration branch history reads as the plan and a dependency violation cannot hide behind a fast builder. A later wave never merges before the earlier wave has fully merged and passed integration verification. If a predecessor is still in a fix cycle, the approved task waits; if the predecessor escalates or is cut, the lead rules on whether the wave proceeds without it and ledgers the ruling.

### Report-missing leases

`lease_collect` returns rc 80 (degraded) when a builder exits cleanly but its output has no final `Status:` line. That lease is report-missing: it is NOT review-ready and its output is never handed to a reviewer as if it were a finished build. `lease_collect` itself drives the two-step recovery through the ledger's `report_missing_count`:

1. **First miss: re-dispatch once with the contract restated.** `lease_collect` moves the lease back to `leased` (same builder, same worktree — the builder's uncommitted work is kept; a pinned reviewer stays pinned). The lead runs `lease_dispatch <task> "<one line saying the previous run ended without a report> <original prompt>"`; `lease_dispatch` always prepends the dispatch contract (typed `Status:` report, no sub-dispatch, git stays local — and the lease env refuses a push mechanically: pre-push hook + `no-push://` URL rewrite, SELF-09). Do not route through the requeue path — `lease_requeue` discards the worktree and re-leases to a different builder.
2. **Second miss: escalated.** Two clean exits without a report mean the builder is not following the contract. `lease_collect` sets the lease `escalated` (rc 1) with both output paths in its reason; treat it like a same-error kill: the lead rules (ledgered as a `Ruling:`) whether to reassign the task to a different roster member or to stop the wave for the user.

### Integrity escalations (rc 44)

A builder without an OS sandbox can write anything the user can. Before they act, the lease functions compare the git state with the lead's recorded baseline (KTD18): `.git/config`, `.git/hooks/`, `.git/info/`, the global git config, the lead's trusted git config, the lead checkout's `.git`, `ops/leases.toml`, the default branch, and each open lease's `.git` pointer and admin files. Any change not made through the lease functions counts, including your own `git config`, `git remote add` or hook installer. The call restores `.git/config`, `.git/hooks/`, the trusted git config and the ledger where it can (only from a lead copy that still matches, after saving the changed version as `<lease root>/lead/<name>.changed-<UTC time>`), escalates every lease in `building` or `review` (or the one lease whose files changed), names the surface, and returns 44 with nothing merged or promoted. `lease_create`, `lease_merge` and `lease_promote` also return 44 when the checkout is on a branch other than the recorded integration branch (on the default branch or a detached HEAD, `lease_merge` and `lease_promote` refuse with rc 1 first), and merge and promotion return 44 when that branch gained commits since the lead's last merge.

A 44 is not one of the four hard stops; resolve it with a ruling:
- Read what changed and which builders were running. A 44 saying the check could not run names no change: fix the cause it prints and rerun.
- If the change is yours or the user's (your commit on the integration branch, `git remote add`, a hook installer, pulling `main`, a promotion done by hand after an approved rc 42): if the 44 restored that surface, copy the saved `.changed-` version back first; then run `lease_rebaseline [task...]` naming the leases the 44 escalated (the message prints the command). It accepts every surface that differs, so never run it to get past a change you haven't looked at, and it never accepts a ledger edit. An edit to `~/.gitconfig` is accepted too, but the lead's git keeps the identity it captured at first use: to pick the edit up, delete `<lease root>/lead/gitconfig`, then rebaseline.
- If a builder made it, or you can't rule that out: stop its process first (the `pid` is in the lease row; nothing sweeps an escalated lease), `lease_reclaim` the lease, and rule on reassigning the task. Say what you found in the ruling.
- Commit your own `ops/` edits after the wave's last merge, or run `lease_rebaseline` right after committing them; stage them by path, never with `git add -A`, which could sweep in a file a builder wrote.

Triforge's own git calls ignore settings a worker could have written; the harness's git and any git you run do not, so a planted hook runs on your next plain `git commit` before any check sees it.

## Rulings, not stalls

When a decision is needed mid-wave and no user is available, the lead rules and continues. It does not park the sprint on "escalate to user" for anything short of the four hard stops below. Every ruling is one line in the wave ledger (the wave execution summary) and in `ops/CHANGELOG.md`:

```
Ruling: <decision> — <reason>
```

Add the cost if the ruling is wrong when it is not obvious from the reason. The wrap step exports every `Ruling:` line before the completion marker, so the user reviews them in one place.

Rule on: a plan conflict between two tasks, an ambiguous acceptance criterion, a reviewer finding the plan did not anticipate, a dependency that turned out to be optional, a choice between two equivalent approaches, whether a wave proceeds without an escalated task, what context a `NEEDS_CONTEXT` builder gets, whether an integrity change (rc 44) was yours or a builder's.

### The four hard stops

Only these stall the wave; everything else is ruled and ledgered:

1. **Destructive or irreversible actions** — deleting data or history, force-removing a worktree with uncommitted output, dropping a schema, anything a task row marks `Reversibility: one-way`.
2. **Pushes to shared branches** — any `git push`, publish, or release; `lease_promote` while the promotion gate is on. The sprint's outward-facing side effects are the user's to trigger.
3. **Changes to the controls that govern the pool** — any diff touching a protected path (see "Protected-path override" above). The lead or the user reviews it, never an external CLI alone; it can merge to the integration branch, and its promotion then stops at hard stop 2 (`lease_promote` returns 42).
4. **A settled decision proving infeasible** — evidence that a session-settled or user-directed decision cannot work. Report the evidence; do not silently choose a different course.

When a hard stop is hit, record `Stop: <what> — <why> — <what the user must decide>` in the same ledger, finish every task that does not depend on it, and then pause.

## Red Flags

Stop and re-read the protocol when:
- You are about to merge a task you built, or a task with no pinned reviewer.
- A lease's output has no `Status:` line and you are reading it as done.
- You are about to run `lease_rebaseline` without having read what the 44 named.
- A task is being merged because it finished, not because its wave position is next.
- You typed "escalate to user" for something that is not one of the four hard stops.
- The next wave is being dispatched before integration verification of the previous one ran.
- A retry is starting without answers to the reflection questions.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "I built it, I know it is right, I can merge it" | Self-merge is refused by `lease_merge` (AE3). Pin a non-author reviewer. |
| "No reviewer is live, so I will skip the pin this once" | A merge without a pin has no record that a review happened. Block and escalate. |
| "T3 finished first, merge it now" | Merge in wave order. Completion order makes the integration history unreadable and hides dependency violations. |
| "The builder's output looks complete, send it to review" | No `Status:` line is report-missing, not done. Re-dispatch with the contract restated. |
| "This decision needs the user, park the sprint" | Unless it is one of the four hard stops, rule, ledger the `Ruling:` line, and continue. |
| "The verify step is slow, start the next wave in parallel" | A next wave on an unverified branch builds on unknown state. Verify, then dispatch. |
| "The retry will work if I just run it again" | Answer the reflection questions first. The same approach three times is a kill criterion. |

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

Capability basis: probe CC-04 in the newest `ops/research/*-probe-record.md` (PASS, expressibility; Claude Code floor ≥ 2.1.267 per D-034) — dynamic workflows can express external-CLI dispatch + requeue + pinned review. The "Builder-pool wave protocol" above is the lease/cross-review contract those stages carry; it is dogfooded end-to-end (two-task wave, cross-review, single-commit merges, AE3 refusal) in the unit that introduced it.

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
- Every `Ruling:` and `Stop:` line made during the wave, in order
- Report-missing and escalated leases with their output paths
- Every integrity escalation (rc 44) and how it was resolved (what was rebaselined, or what was reclaimed)
- Updated TASKS.md with all tasks marked Done or Blocked

## Model routing discretion

Shipped frontmatter floors at `opus` — no shipped file names a model a host may lack. team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) ship at `effort: max`; the other 15 agents ship at `effort: xhigh`. When spawning subagents for narrow, rubric-following tasks (e.g., learnings-researcher, convention-enforcer), you MAY step down the runtime ladder one tier at a time:

Downgrade ladder for narrow runtime tasks: `fable`+`max` (lead + never-downgrade tier when available; otherwise latest `opus` at `max` — the model steps down, the effort does not) → `opus` (Opus 5) + `xhigh` → `opus`+`high` → `sonnet` (Sonnet 5) + `high`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.

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
