# The full lifecycle, phase by phase

Follow `docs/agent-triforge.md` (under the plugin root) through ALL phases.

## Phase 0: codebase analysis

Dispatch Antigravity with the `codebase-analyst` agent definition (skip if unnecessary). `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it):

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"

# Full codebase analysis (uses codebase-analyst agent definition)
AGY_OUT="${TMPDIR:-/tmp}/antigravity_phase0_$$_$(date +%s).txt"
AGY_RC=0
invoke_antigravity "codebase-analyst" \
  "Analyze the full codebase. Write to ops/ARCHITECTURE.md, ops/MEMORY.md (append), ops/CONTRACTS.md (append) if you can; otherwise return the complete content as your response, sectioned per target file." \
  "$AGY_OUT" 600 || AGY_RC=$?
if [ "$AGY_RC" -ne 0 ]; then
  echo "phase0: codebase-analyst failed rc=$AGY_RC (see $AGY_OUT, ${AGY_OUT}.err) — continuing without a fresh ARCHITECTURE.md" >&2
fi

# Promotion guard (KTD2/D-032): promote captured agy output only when it is
# non-empty prose AND the JSON-envelope status sidecar written by
# invoke_antigravity reads SUCCESS (a denied/empty run leaves the file empty and
# returns non-zero — nothing is promoted, AE2). A non-agy roster lane writes no
# sidecar and is promoted on non-empty output as before. The header records the
# resolved mode (injection|native|raw) and any denied actions so a degraded run
# is attributable in the promoted file.
if [ ! -f "ops/ARCHITECTURE.md" ] && [ -s "$AGY_OUT" ] && { [ ! -f "${AGY_OUT}.status" ] || [ "$(cat "${AGY_OUT}.status")" = "SUCCESS" ]; }; then
  {
    echo "<!-- captured from codebase-analyst output; agent could not write ops/ directly (headless permission auto-deny); mode=$(cat "${AGY_OUT}.mode" 2>/dev/null || echo unknown); denied_actions=$([ -s "${AGY_OUT}.denied" ] && paste -sd, "${AGY_OUT}.denied" || echo none) -->"
    _scrub < "$AGY_OUT"
  } > ops/ARCHITECTURE.md
fi
```

Read the updated `ops/` files after completion.

## Pre-plan: institutional knowledge

The `learnings-researcher` persona searches `ops/solutions/` and `ops/decisions/` for patterns relevant to the goal. Write the goal to a file, start it with `persona_spawn "$RUN" learnings learnings-researcher <goal file> "$RUN/learnings.md" --brief "Search ops/solutions/ and ops/decisions/ for patterns relevant to the goal in the input."` (`RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-plan.XXXXXX")`), and rerun `persona_wait "$RUN"` in a separate block while it returns 75.

## Phase 1: planning

Follow the `writing-plans` and `shadow-path-tracing` skills. Embed `ops/CONTRACTS.md` types. Group into waves. Write `ops/TASKS.md`.

## Phase 1.1: ambiguity resolution

Before proceeding to build, list every critical assumption in your plan. If any assumption could change the architecture or approach, pause and ask the user to confirm. Do not build on unvalidated assumptions.

## Phase 1.5: plan validation

Start it detached in one block, `persona_spawn "$RUN" plan-checker plan-checker ops/TASKS.md "$RUN/verdict.md"` with `RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-plan.XXXXXX")`; in the next, rerun `persona_wait "$RUN"` while it returns 75, then read the verdict from `$RUN/verdict.md` once `plan-checker.rc` is 0. Iterate until APPROVED (max 3 rounds).

## Phase 2: build

Use wave orchestration (the `wave-orchestration` skill: every task leased from `ops/roster.toml`, merged only after a pinned non-author review, one commit per task on the integration branch). Sub-agent mode for fewer than 5 tasks, agent-team mode for 5 or more. Run the `integration-verifier` persona between waves (`--at ref:<integration branch>`). Apply risk scoring (halt at risk above 20 % or more than 50 changed files).

## Phase 3: parallel review

Launch Antigravity + Codex (in the background) + the review personas simultaneously, the way the `at-review` skill's dispatch and wait blocks run them: each persona starts detached (`persona_spawn "$RUN" <LANE> <persona> <review package file> <out> --brief "<the review task>"`) and a wait block, rerun while it returns 75, collects them:

- `security-sentinel`
- `performance-oracle`
- `code-simplicity-reviewer`
- `convention-enforcer`
- `architecture-strategist`

## Phase 4: process reviews

Run `findings-synthesizer` the way the `at-review` skill's synthesis does: started detached with the expected lanes and their state as its input and the task and the expected lane files in `--brief`, then a wait block rerun while it returns 75; a lane that is missing or empty is a gap and the cycle does not converge on it. Apply the `iterative-refinement` skill. Fix P1 + P2. Loop if needed (max 3 cycles).

## Phase 5: test

Write the scope (the changed paths) to a file, start `persona_spawn "$RUN" test-gap-analyzer test-gap-analyzer <scope file> "$RUN/gaps.md" --brief "Find the untested paths in the scope the input names."` and rerun `persona_wait "$RUN"` in a separate block while it returns 75. It runs at the default `--at ref:HEAD`, which sees committed work only: when the scope has uncommitted changes, stop and ask the user to commit them or name a branch or a full commit id, and never commit for them. Dispatch Codex to write tests, failing test first. Fix failures until green (max 3 cycles).

## Phase 6: wrap up

- Apply `knowledge-compounding` (document to `ops/solutions/` if non-trivial).
- Update `ops/CHANGELOG.md`, `ops/MEMORY.md`, `ops/TASKS.md`.
- Archive review files to `ops/archive/<today's date>/`.
- Apply the `verification-before-completion` skill.
- Write `ops/STATE.md`.
- Only when the full completion-gating checklist passes: create the runtime marker `ops/.sprint-complete` (`touch ops/.sprint-complete`) as the LAST action.
- Sprint summary for the user.

If any checklist item fails, do NOT create `ops/.sprint-complete`; document the blocker in `ops/TASKS.md` and `ops/STATE.md` instead.
