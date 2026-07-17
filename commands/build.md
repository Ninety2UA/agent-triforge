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

## Build mode selection

Check the task count and dependencies:
- **< 5 independent tasks** → Subagent mode (default)
- **5+ tasks or `--team` flag** → Agent team mode with team-lead
- **`--wave N`** → Start from wave N (for resuming)

## Subagent mode

Follow the `wave-orchestration` skill:

1. Group tasks into waves based on dependencies and file ownership
2. For each wave:
   a. Dispatch parallel subagents — each gets task description + relevant CONTRACTS.md types
   b. Apply risk scoring (halt at >20% or 50+ file changes)
   c. Collect results
   d. Spawn `integration-verifier` agent: tests pass, build clean, lint clean, no conflicts
   e. If verification fails → fix before proceeding
3. After all waves: run full test suite + build from clean state

## Agent team mode

1. Spawn the `team-lead` agent
2. Team-lead reads TASKS.md, groups into work streams
3. Team-lead assigns teammates with explicit file ownership
4. Teammates coordinate via shared task list + messaging
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
6. Quality gates: tests + lint must pass before marking tasks done
7. Integration-verifier runs between waves

## After build

- Update ops/CHANGELOG.md with all changes and attribution
- Move completed build tasks to "Done" in ops/TASKS.md
- Move review tasks to "Review" status
- Update ops/CONTRACTS.md if new interfaces were introduced
