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

Spawn a sub-agent with the `plan-checker` persona. It validates:

- Task completeness (agent, files, acceptance criteria)
- Assignment correctness (the heuristic matrix)
- Dependency correctness (a DAG, no cycles)
- Scope (atomic tasks, a reasonable count)
- Shadow path coverage
- Architecture alignment
- Task field integrity (G6/G11): every command-shaped `Accept:` carries a concrete `Fails when:` (placeholders such as TBD or N/A are rejected), and every `Reversibility: one-way` task names a checkpoint in `Precondition:`

Trivial goals skip this phase (the `Ceremony:` line at the top of `ops/TASKS.md` says so); high-ceremony goals never skip it. The plan-checker is one of the never-downgrade trio: it runs on the top model tier whichever CLI leads.

A NEEDS_REVISION verdict is fixed and resubmitted, at most 3 iterations. Only an APPROVED result is reported to the user.
