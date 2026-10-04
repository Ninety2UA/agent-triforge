# Pipeline: every phase in order

Execute ALL phases in order. Do not skip a phase unless its entry says so, and state the reason when you do.

## Contents

- Pre-plan, Phase 0 (with the dispatch block), Phases 1, 1.1, 1.5, 2, 3, 4, 5, 6.

## Pre-plan: search institutional knowledge

Write a brief file naming the goal, then run `dispatch_persona learnings-researcher <brief file> <out>` to search `ops/solutions/` and `ops/decisions/` for relevant patterns.

## Phase 0: codebase analysis

Dispatch Antigravity with the `codebase-analyst` agent definition (skip if the codebase is unchanged or the change is a small fix). `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it):

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

## Phase 1: planning

Follow the `writing-plans` skill. Apply the `shadow-path-tracing` skill for non-trivial tasks. Embed `ops/CONTRACTS.md` types in task descriptions. Group tasks into waves. Write `ops/TASKS.md`.

## Phase 1.1: ambiguity resolution

Before building, surface the 3 most critical unverified assumptions about the goal. Present each with the alternative interpretation and the impact if wrong. Ask the user to confirm or correct. Revise `ops/TASKS.md` if any assumption is corrected. Skip for unambiguous goals.

## Phase 1.5: plan validation

Run `dispatch_persona plan-checker ops/TASKS.md <out>` and read the verdict from `<out>`. Iterate until APPROVED (max 3 rounds).

## Phase 2: build

- Assign every task from `ops/roster.toml` and build it under a per-task lease in an isolated worktree; merge only after cross-review by a pinned non-author reviewer (the builder-pool wave protocol in the `wave-orchestration` skill). The single-writer rule is retired; safety is leases + worktree isolation + cross-review.
- Fewer than 5 independent tasks → sub-agent mode with wave orchestration.
- 5 or more tasks, or interdependent tasks, or `--team` → agent-team mode with the `team-lead` persona.
- Approved merges land as one commit per task on the sprint integration branch (`lease_merge` refuses the default branch); the `integration-verifier` persona runs against that branch between waves (`--at ref:<integration branch>`), then the lead promotes to the main branch with `lease_promote`, which honors `[promotion]` and BLOCKS on protected-path diffs (they force the gate on).
- Apply risk scoring (halt at risk above 20 % or 50+ file changes).

## Phase 3: parallel review

Launch ALL reviewers simultaneously:

- Antigravity (architecture, design), in the background.
- Codex (logic, security, tests), in the background.
- `security-sentinel`, `performance-oracle` and `code-simplicity-reviewer` as personas (`dispatch_persona <persona> <review package file> <out>`, in the background), launched in the same round.

## Phase 4: process reviews

Run `dispatch_persona findings-synthesizer <brief file> <out>`, the brief naming the cycle. Apply the `iterative-refinement` skill:

- Fix P1 + P2 issues.
- Check convergence (the mode from the invocation; default `standard`).
- Loop to Phase 3 if not converged (max 3 cycles).

## Phase 5: test

- Run `dispatch_persona test-gap-analyzer <brief file> <out>` (default `--at ref:HEAD`) to identify coverage gaps.
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
