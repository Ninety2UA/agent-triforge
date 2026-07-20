---
description: "Execute Phase 2 build with wave orchestration. Assumes planning is already done (TASKS.md exists)."
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, Agent
argument-hint: "[--team] [--wave N]"
---

You are executing Phase 2 (Build) of the multi-agent framework.

## Preflight

Core-trio liveness is gated lazily here — never at session start, so a /status-only session never pays for it. Fast non-model checks (`--version`, cached per session); on failure it names the failing member and its install/login fix:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh
ensure_core_trio_live || exit 1
```

## When to use

- `/build` — Phase 2 only. TASKS.md must already exist (run `/plan` first).
- `/ship` — Full Phase 0–6 autonomous sprint (planning + build + review + test + wrap).
- `/quick` — Small focused change (<3 files, obvious fix). Skips review swarm.

## Prerequisites
- ops/TASKS.md must exist with assigned tasks
- Phase 1.5 plan validation should have passed

Read ops/TASKS.md, ops/CONTRACTS.md, ops/MEMORY.md, and ops/ARCHITECTURE.md first.

## Arguments
$ARGUMENTS

## Flags
- `--team` — Activate agent team mode with team-lead (for 5+ tasks or cross-dependent work)
- `--wave N` — Resume build starting from wave N (skip already-completed waves)

## Builder-pool wave protocol

Phase 2 runs the builder pool (see the `wave-orchestration` skill, "Builder-pool wave protocol"). The single-writer rule is retired: every implementation task — including lead-authored ones — is assigned from `ops/roster.toml`, built under a per-task lease in an isolated worktree, and merged only after cross-review by a pinned non-author reviewer. Safety is leases + worktree isolation + cross-review, not write-restriction.

Per task (with `invoke-external.sh` sourced from the preflight):
1. `lease_create <task> <role>` → `lease_dispatch <task> <prompt>` — builder resolved via `resolve_role`, context injected, builder runs confined in its worktree (commits nothing).
2. `lease_heartbeat_check` until it exits → `lease_collect` (state → review, prints the output path).
3. Pin a reviewer that is a DIFFERENT roster member than the builder (the lead is valid) with `lease_pin_reviewer <task> <reviewer>`, review the collected output, then `lease_merge <task> <reviewer>` — ONE squash commit per task on the sprint integration branch. `lease_merge` REFUSES self-review (AE3), an unknown reviewer identity, or a merge with no pin (the pin is the record that a review happened — pin, review, then merge). Findings re-dispatch the same lease/builder with the same pinned reviewer, cycle < 3; cycle 3 escalates.
4. At wave end, `integration-verifier` runs against the integration branch, then the lead promotes to the main branch with `lease_promote` — it reads `[promotion] require_user_approval` (default false) and scans the integration diff, BLOCKING (no merge) when approval is required or a protected path is touched. Protected-path diffs (permission configs, deny rules, `ops/roster.toml`, shipped agent configs) force the gate on and require the lead or user as reviewer — never an external-CLI-only review. (`lease_merge` also refuses to run when the main tree is on the default branch — merges land on the sprint integration branch, promotion is `lease_promote`'s job.)

CHANGELOG rows carry builder + reviewer + merge commit from the ledger (`lease_status`).

## Build mode selection

Check the task count and dependencies:
- **< 5 independent tasks** → Subagent mode (default)
- **5+ tasks or `--team` flag** → Agent team mode with team-lead
- **`--wave N`** → Start from wave N (for resuming)

## Subagent mode

Follow the `wave-orchestration` skill (its "Builder-pool wave protocol" governs assignment, leases, and cross-review):

1. Group tasks into waves based on dependencies and file ownership
2. For each wave:
   a. Assign + dispatch each task under a lease (`lease_create` → `lease_dispatch`), builder resolved from the roster, context injected
   b. Apply risk scoring (halt at >20% or 50+ file changes)
   c. Collect each builder (`lease_collect`), pin a non-author reviewer (`lease_pin_reviewer`), and merge approved work as one commit per task on the integration branch (`lease_merge` — refuses self-review AE3, an unknown reviewer, or a merge with no pin)
   d. Spawn `integration-verifier` agent against the integration branch: tests pass, build clean, lint clean, no conflicts
   e. If verification fails → fix before proceeding
3. After all waves: run full test suite + build from clean state, then promote the integration branch honoring the `[promotion]` gate

## Agent team mode

1. Spawn the `team-lead` agent
2. Team-lead reads TASKS.md, groups into waves
3. Team-lead assigns each task to a builder resolved from `ops/roster.toml`, dispatched under a lease, and pins a non-author reviewer per task
4. Builders run confined in worktrees; the team-lead injects context and does all merges on the main tree (KTD-3)
5. Teammates can invoke antigravity/codex for specific reviews (replace `<scope>` with actual paths):
   ```bash
   set -euo pipefail
   source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

   AGY_OUT="${TMPDIR:-/tmp}/antigravity_build_$$_$(date +%s).txt"
   CODEX_OUT="${TMPDIR:-/tmp}/codex_build_$$_$(date +%s).txt"

   # Architecture review for build scope
   invoke_antigravity "architecture-reviewer" \
     "Review <scope> for architecture. Write to ops/REVIEW_ANTIGRAVITY.md if you can; otherwise return findings as your response." \
     "$AGY_OUT" 600 &
   AGY_PID=$!

   # Test writing for build scope
   invoke_codex "test_writer" \
     "Write tests for <scope>." \
     "$CODEX_OUT" 600 &
   CODEX_PID=$!

   # Per-PID wait so a silent failure doesn't leave downstream agents staring at
   # an empty file and calling it "no findings".
   AGY_RC=0; CODEX_RC=0
   wait $AGY_PID || AGY_RC=$?
   wait $CODEX_PID  || CODEX_RC=$?
   if [ $AGY_RC -ne 0 ] || [ $CODEX_RC -ne 0 ]; then
     echo "build: helper failed — antigravity=$AGY_RC codex=$CODEX_RC" >&2
     echo "build: last stderr in $AGY_OUT / $CODEX_OUT" >&2
     exit 1
   fi
   ```
6. Quality gates: tests + lint must pass, and a pinned non-author reviewer must approve, before a task merges (self-review refused — AE3)
7. Integration-verifier runs between waves against the integration branch; the lead promotes to the main branch honoring the `[promotion]` gate

## After build

- Update ops/CHANGELOG.md — each merged task's row carries builder + reviewer + merge commit from the ledger (`lease_status`)
- Move completed build tasks to "Done" in ops/TASKS.md
- Move review tasks to "Review" status
- Update ops/CONTRACTS.md if new interfaces were introduced
- Promote the sprint integration branch to the main branch only after integration-verifier passes and the `[promotion]` gate is satisfied
