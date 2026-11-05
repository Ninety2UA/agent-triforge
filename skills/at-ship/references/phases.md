# Pipeline: every phase in order

Execute ALL phases in order. Do not skip a phase unless its entry says so, and state the reason when you do.

## Contents

- Pre-plan, Phase 0 (with the dispatch block), Phases 1, 1.1, 1.5, 2, 3, 4, 5, 6.

## Pre-plan: search institutional knowledge

The `learnings-researcher` persona searches `ops/solutions/` and `ops/decisions/` for patterns relevant to the goal. When `learnings_store_empty` returns 0 (`ops/solutions/` and `ops/decisions/` hold no file, `ops/MEMORY.md` and `ops/CHANGELOG.md` are absent or unchanged from their templates), print "learnings-researcher skipped: the store holds only the skeleton", start nothing and go on. Otherwise write the goal to a file, start it with `persona_spawn "$RUN" learnings learnings-researcher <goal file> "$RUN/learnings.md" --brief "Search ops/solutions/ and ops/decisions/ for patterns relevant to the goal in the input."` (`RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-plan.XXXXXX")`), and rerun `persona_wait "$RUN"` in a separate block while it returns 75.

## Phase 0: codebase analysis

Dispatch Antigravity with the `codebase-analyst` agent definition (skip if the codebase is unchanged or the change is a small fix). `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it):

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

## Phase 1: planning

Follow the `writing-plans` skill. Apply the `shadow-path-tracing` skill for non-trivial tasks. Embed `ops/CONTRACTS.md` types in task descriptions. Group tasks into waves. Write `ops/TASKS.md`.

## Phase 1.1: ambiguity resolution

Before building, surface the 3 most critical unverified assumptions about the goal. Present each with the alternative interpretation and the impact if wrong. Ask the user to confirm or correct. Revise `ops/TASKS.md` if any assumption is corrected. Skip for unambiguous goals.

## Phase 1.5: plan validation

Start it detached in one block, `persona_spawn "$RUN" plan-checker plan-checker ops/TASKS.md "$RUN/verdict.md"` with `RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-plan.XXXXXX")`; in the next, rerun `persona_wait "$RUN"` while it returns 75, then read the verdict through `persona_verdict "$RUN/verdict.md" plan` once `plan-checker.rc` is 0: 0 is APPROVED, 1 is NEEDS_REVISION or a contradiction to fix and resubmit, 2 is a malformed or missing verdict to run again. Iterate until it returns 0 (max 3 rounds).

## Phase 2: build

- Assign every task from `ops/roster.toml` and build it under a per-task lease in an isolated worktree; merge only after cross-review by a pinned non-author reviewer (the builder-pool wave protocol in the `wave-orchestration` skill). The single-writer rule is retired; safety is leases + worktree isolation + cross-review.
- Fewer than 5 independent tasks → sub-agent mode with wave orchestration.
- 5 or more tasks, or interdependent tasks, or `--team` → agent-team mode with the `team-lead` persona.
- Approved merges land as one commit per task on the sprint integration branch (`lease_merge` refuses the default branch); the `integration-verifier` persona runs against that branch between waves (`--at ref:<integration branch>`), its verdict read through `persona_verdict "$RUN/verify.md" verify`, where anything but 0 blocks the next wave; after the last wave, the lead promotes to the main branch once with `lease_promote`, which honors `[promotion]` and BLOCKS on protected-path diffs (they force the gate on).
- Apply risk scoring (halt at risk above 20 % or more than 50 changed files).

## Phase 3: parallel review

Build the review package with `REVIEW_BASE` set to the commit on the `Build base:` line of `ops/TASKS.md`: Phase 2 has promoted, so the default base would leave only the last commit to review.

Launch ALL reviewers simultaneously:

- Antigravity (architecture, design), in the background.
- Codex (logic, security, tests), in the background.
- `security-sentinel`, `performance-oracle` and `code-simplicity-reviewer` as personas in the same round, the way the `at-review` skill's dispatch and wait blocks run them: each starts detached (`persona_spawn "$RUN" <LANE> <persona> <review package file> <out> --brief "<the review task>"`) and a wait block, rerun while it returns 75, collects them. `REVIEW_JUDGE_RULE` and `REVIEW_COVERAGE_RULE` exist in a shell that has sourced `scripts/invoke-external.sh`: use them there as `$REVIEW_JUDGE_RULE $REVIEW_COVERAGE_RULE`, and print them (`printf '%s\n%s\n' "$REVIEW_JUDGE_RULE" "$REVIEW_COVERAGE_RULE"`) for a brief you write by hand. Every lane's prompt or brief carries both, so its report ends in a Coverage line.

## Phase 4: process reviews

Run `findings-synthesizer` the way the `at-review` skill's synthesis does: started detached with the expected lanes and their state as its input and the task and the expected lane files in `--brief`, then a wait block rerun while it returns 75; a lane that is missing or empty, or that does not end in `Coverage: complete` (`review_coverage_gaps <lanes file> <gaps file>`, `scripts/lib/gates.sh`: the lanes file lists one `ops/REVIEW_*.md` per line, relative to the project root, and each lane there whose file is short of complete adds `<lane>: coverage <value>` to the gaps file; a missing or empty file you add to the gaps yourself, as the synthesis block does), is a gap and the cycle does not converge on it. Apply the `iterative-refinement` skill:

- Fix P1 + P2 issues.
- Check convergence (the mode from the invocation; default `standard`) by the `iterative-refinement` skill's exit decision.
- Loop to Phase 3 if not converged (max 3 cycles).

## Phase 5: test

- Write the scope (the changed paths) to a file, start `persona_spawn "$RUN" test-gap-analyzer test-gap-analyzer <scope file> "$RUN/gaps.md" --brief "Find the untested paths in the scope the input names."` and rerun `persona_wait "$RUN"` in a separate block while it returns 75. It runs at the default `--at ref:HEAD`, which sees committed work only: when the scope has uncommitted changes, stop and ask the user to commit them or name a branch or a full commit id, and never commit for them.
- Dispatch Codex to write tests, failing test first.
- Fix failures, re-run until green.

## Phase 6: wrap up

- Apply the `knowledge-compounding` skill (document solutions to `ops/solutions/`).
- Update `ops/CHANGELOG.md`, `ops/MEMORY.md`, `ops/TASKS.md`.
- Archive review files to `ops/archive/<today's date>/`.
- Apply the `verification-before-completion` skill (all checks must pass).
- Write `ops/STATE.md` for session handoff.
- Only when the full completion-gating checklist passes: create the runtime marker `ops/.sprint-complete` (`touch ops/.sprint-complete`) as the LAST action.

If any checklist item fails, do NOT create `ops/.sprint-complete`; document the blocker in `ops/TASKS.md` and `ops/STATE.md` instead.
