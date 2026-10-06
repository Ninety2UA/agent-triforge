# Phases 1.1 and 1.5: ambiguity resolution and plan validation

## Phase 1.1: ambiguity resolution

Before validating the plan, surface the critical assumptions:

1. List the 3 most critical assumptions about the goal that, if wrong, would invalidate the plan.
2. For each: what was assumed, the alternative interpretation, and the impact if wrong (which tasks would change).
3. Present them to the user and ask for confirmation or correction.
4. A corrected assumption means revising `ops/TASKS.md` before validation.
5. All confirmed means proceeding to Phase 1.5.

Skip this phase only when the goal is unambiguous (a single-file fix, explicit user instructions with no room for interpretation) — never at high-ceremony.

## Phase 1.5: plan validation

The plan-checker runs detached, because a top-tier persona can outlast one host tool call (Claude Code stops one at 600 s, a Codex lead at 900 s). The first block starts it; rerun the second while it returns 75, then read the verdict. Both run the same under bash and zsh.

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
PLAN_RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-plan.XXXXXX")
persona_spawn "$PLAN_RUN" plan-checker plan-checker ops/TASKS.md "$PLAN_RUN/verdict.md" \
  --brief "Validate the plan in the input and end with APPROVED or NEEDS_REVISION."
echo "plan: plan-checker started; run the wait block next (PLAN_RUN=$PLAN_RUN)"
```

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
: "${PLAN_RUN:?set PLAN_RUN to the run directory the start block printed}"
persona_wait "$PLAN_RUN" || { rc=$?; [ "$rc" -eq 75 ] && echo "plan: plan-checker still running; rerun this block"; exit "$rc"; }
R=$(cat "$PLAN_RUN/plan-checker.rc" 2>/dev/null || echo missing)
[ "$R" = 0 ] && [ -s "$PLAN_RUN/verdict.md" ] || { echo "plan: plan-checker failed rc=$R or wrote nothing — see $PLAN_RUN" >&2; exit 1; }
cat "$PLAN_RUN/verdict.md"
```

It validates:

- Task completeness (agent, files, acceptance criteria)
- Assignment correctness (the heuristic matrix)
- Dependency correctness (a DAG, no cycles)
- Scope (atomic tasks, a reasonable count)
- Shadow path coverage
- Architecture alignment
- Task field integrity (G6/G11): every command-shaped `Accept:` carries a concrete `Fails when:` (placeholders such as TBD or N/A are rejected), and every `Reversibility: one-way` task names a checkpoint in `Precondition:`

Trivial goals skip this phase (the `Ceremony:` line at the top of `ops/TASKS.md` says so); high-ceremony goals never skip it. The plan-checker is one of the never-downgrade trio: its manifest entry pins it to top-tier Claude whichever CLI leads, and no skill or lead overrides that.

A NEEDS_REVISION verdict is fixed and resubmitted, at most 3 iterations. Only an APPROVED result is reported to the user.
