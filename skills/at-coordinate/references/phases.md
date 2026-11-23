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
  "Analyze the full codebase. Return the complete content as your final response, sectioned per target file (ops/ARCHITECTURE.md, ops/MEMORY.md, ops/CONTRACTS.md): the lead saves that response. Do not write a file and do not run a command." \
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
    echo "<!-- captured from codebase-analyst output; mode=$(cat "${AGY_OUT}.mode" 2>/dev/null || echo unknown); denied_actions=$([ -s "${AGY_OUT}.denied" ] && paste -sd, "${AGY_OUT}.denied" || echo none) -->"
    _scrub < "$AGY_OUT"
  } > ops/ARCHITECTURE.md
fi
```

Read the updated `ops/` files after completion.

## Pre-plan: institutional knowledge

The `learnings-researcher` persona searches `ops/solutions/` and `ops/decisions/` for patterns relevant to the goal. When `learnings_store_empty` returns 0 (`ops/solutions/` and `ops/decisions/` hold no file, `ops/MEMORY.md` and `ops/CHANGELOG.md` are absent or unchanged from their templates), print "learnings-researcher skipped: the store holds only the skeleton", start nothing and go on. Otherwise write the goal to a file, start it with `persona_spawn "$RUN" learnings learnings-researcher <goal file> "$RUN/learnings.md" --brief "Search ops/solutions/ and ops/decisions/ for patterns relevant to the goal in the input."` (`RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-plan.XXXXXX")`), and rerun `persona_wait "$RUN"` in a separate block while it returns 75.

## Phase 1: planning

Follow the `writing-plans` and `shadow-path-tracing` skills. Embed `ops/CONTRACTS.md` types. Group into waves. Write `ops/TASKS.md`.

## Phase 1.1: ambiguity resolution

Before proceeding to build, list every critical assumption in your plan. If any assumption could change the architecture or approach, pause and ask the user to confirm. Do not build on unvalidated assumptions. When no user is answering (a `coordinate.sh` iteration, a headless run), do not stall: take the reading that keeps the most options open, record `Ruling: assumed <reading> — <reason>` in `ops/CHANGELOG.md`, and go on; stop only where the assumption meets one of the `wave-orchestration` skill's four hard stops.

## Phase 1.5: plan validation

Start it detached in one block, `persona_spawn "$RUN" plan-checker plan-checker ops/TASKS.md "$RUN/verdict.md"` with `RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-plan.XXXXXX")`; in the next, rerun `persona_wait "$RUN"` while it returns 75, then read the verdict through `persona_verdict "$RUN/verdict.md" plan` once `plan-checker.rc` is 0: 0 is APPROVED, 1 is NEEDS_REVISION or a contradiction to fix and resubmit, 2 is a malformed or missing verdict to run again. Iterate until it returns 0 (max 3 rounds).

## Phase 2: build

Use wave orchestration (the `wave-orchestration` skill: every task leased from `ops/roster.toml`, merged only after a pinned non-author review, one commit per task on the integration branch). Sub-agent mode for fewer than 5 tasks, agent-team mode for 5 or more. Run the `integration-verifier` persona between waves (`--at ref:<integration branch>`) and read its verdict through `persona_verdict "$RUN/verify.md" verify`, where anything but 0 blocks the next wave. Apply risk scoring (halt at risk above 20 % or more than 50 changed files).

## Phase 3: parallel review

Launch the analyst and reviewer roles (`dispatch_role analyst` and `dispatch_role reviewer`, shipped as Antigravity and Codex, in the background) + the review personas simultaneously, the way the `at-review` skill's dispatch and wait blocks run them: each persona starts detached (`persona_spawn "$RUN" <LANE> <persona> <review package file> <out> --brief "<the review task>"`) and a wait block, rerun while it returns 75, collects them:

- `security-sentinel`
- `performance-oracle`
- `code-simplicity-reviewer`
- `convention-enforcer`
- `architecture-strategist`

`REVIEW_JUDGE_RULE` and `REVIEW_COVERAGE_RULE` exist in a shell that has sourced `scripts/invoke-external.sh`: use them there as `$REVIEW_JUDGE_RULE $REVIEW_COVERAGE_RULE`, and print them (`printf '%s\n%s\n' "$REVIEW_JUDGE_RULE" "$REVIEW_COVERAGE_RULE"`) for a brief you write by hand. Every lane's prompt or brief carries both, so its report ends in a Coverage line.

## Phase 4: process reviews

Run `findings-synthesizer` the way the `at-review` skill's synthesis does: started detached with the expected lanes and their state as its input and the task and the expected lane files in `--brief`, then a wait block rerun while it returns 75; a lane that is missing or empty, or that does not end in `Coverage: complete` (`review_coverage_gaps <lanes file> <gaps file>`, `scripts/lib/gates.sh`: the lanes file lists one `ops/REVIEW_*.md` per line, relative to the project root, and each lane there whose file is short of complete adds `<lane>: coverage <value>` to the gaps file; a missing or empty file you add to the gaps yourself, as the synthesis block does), is a gap and the cycle does not converge on it. Apply the `iterative-refinement` skill. Fix P1 + P2. Loop if needed (max 3 cycles), by the `iterative-refinement` skill's exit decision.

## Phase 5: test

Before anything else in Phase 5, save the untracked files' digests for the delta review below: `delta_untracked_save ops/archive/phase5-untracked-<snapshot>.txt`, where `<snapshot>` is the commit in the converged cycle's `## Review dispositions` header.

Write the scope (the changed paths) to a file, start `persona_spawn "$RUN" test-gap-analyzer test-gap-analyzer <scope file> "$RUN/gaps.md" --brief "Find the untested paths in the scope the input names."` and rerun `persona_wait "$RUN"` in a separate block while it returns 75. It runs at the default `--at ref:HEAD`, which sees committed work only: when the scope has uncommitted changes, stop and ask the user to commit them or name a branch or a full commit id, and never commit for them. Dispatch the tester role (`dispatch_role tester`, shipped as Codex) to write tests, failing test first, as the `at-test` skill's Step 2 does. Fix failures until green (max 3 cycles) under a lease with a pinned non-author reviewer, as the `at-test` skill's fix cycle (`at-test/references/fix-cycle.md`) does: Phase 2 already promoted, and `lease_merge` refuses the default branch, so a fix lease merges on a new sprint integration branch, promoted again with `lease_promote`.

When code or tests changed after the converged review, a delta review covers those changes before Phase 6. `<snapshot>` is the commit in the converged cycle's `## Review dispositions` header. Phase 5's first step saved the untracked files' digests (`delta_untracked_save`, `scripts/lib/gates.sh`; a resumed session keeps the list its first session saved). Before Phase 6, `delta_review_paths <snapshot> ops/archive/phase5-untracked-<snapshot>.txt` prints every changed path: the tracked diff with renames off, so a file moved into an exempt path shows under its old name, and each untracked file that is new, changed or gone since the saved list, leaving out the sprint's own bookkeeping (`ops/STATE.md`, `ops/TASKS.md`, `ops/CHANGELOG.md`, `ops/MEMORY.md`, `ops/REVIEW_*.md`, `ops/TEST_RESULTS.md` and `ops/archive/`). Test files count, new ones included, and so does any other `ops/` change such as `ops/roster.toml`. Any printed path means a delta review is due. Its rc 1 (a git call failed) stops the sprint with its error, never read as no change. Its rc 3 means `<snapshot>` names no commit: the delta review then covers the whole sprint from the `Build base:` commit at the top of `ops/TASKS.md`, and when that names none either, stop and record the missing base as the blocker. The delta review is the `at-review` dispatch with `REVIEW_BASE=<snapshot>` (the package's diff carries new untracked files outside `ops/` and dot directories, so every lane reads them), judged by a roster member that wrote none of them (when the tester and the reviewer role run on the same CLI, another roster member judges the tests). It counts against the three-cycle cap; with the cap spent, escalate to the user.

## Phase 6: wrap up

- Apply `knowledge-compounding` when the work corrected a wrong belief (a failed first approach or hypothesis, a P1 or P2 finding a reviewer caught, a wrong assumption or doc); the skill alone decides whether anything is written, and a naming, style or preference fix does not count.
- Update `ops/CHANGELOG.md`, `ops/MEMORY.md`, `ops/TASKS.md`.
- Archive review files to `ops/archive/<today's date>/`.
- Apply the `verification-before-completion` skill.
- Write `ops/STATE.md`.
- Only when the full completion-gating checklist passes: create the runtime marker `ops/.sprint-complete` (`touch ops/.sprint-complete`) as the LAST action.
- Sprint summary for the user.

If any checklist item fails, do NOT create `ops/.sprint-complete`; document the blocker in `ops/TASKS.md` and `ops/STATE.md` instead.
