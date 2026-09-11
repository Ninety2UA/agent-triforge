---
description: "Wrap the current session: compound knowledge, archive files, write STATE.md for next session."
allowed-tools: Read, Grep, Glob, Edit, Write, Bash, Agent
---

You are executing Phase 6 (Wrap up) of the multi-agent framework.

## Step 1: Knowledge compounding

Follow the `knowledge-compounding` skill, gated by the counterfactual bar (CE-1): compound only when a future agent **without** the note would plausibly repeat the mistake or re-derive the decision — that is, when the reasoning is not recoverable from the final code, tests, and docs. Duration and effort are not the bar.
- If a problem solved this session passes the bar, document it in ops/solutions/YYYY-MM-DD-slug.md
- If an architectural decision passes the bar, document it in ops/decisions/YYYY-MM-DD-slug.md
- Check: was anything surprising, counter-intuitive, or hard to debug in a way the diff does not explain? → document it
- If nothing passes the bar, write nothing and say so ("Not compounded: reasoning recoverable from <file or diff>") — a diff narration never qualifies

## Step 2: Update shared files

- If ops/TASKS.md opens with `Ceremony: high-ceremony` (S16), the session summary must cite the plan-checker pass, the `--full` review, and the integration-verifier result by name; a missing one is recorded as a gap in ops/STATE.md, never papered over
- Update ops/CHANGELOG.md with final session summary
- Update ops/MEMORY.md with new decisions, patterns, and gotchas discovered
- Move all completed tasks to "Done" in ops/TASKS.md with result summaries

## Step 2b: Rulings I made (S1)

Every non-catastrophic conflict the lead ruled on during the sprint was ledgered in ops/CHANGELOG.md as `Ruling: <what> | <why> | <cost if wrong>`. Collect them all — the list is exhaustive, never a sample — and print it under a **Rulings I made** heading in the sprint summary (Step 6) so the user can overturn any of them:

```bash
# Rulings I made (S1): every Ruling: line ledgered this sprint. Runs BEFORE
# Step 3 archives anything and BEFORE ops/.sprint-complete exists.
grep -n 'Ruling:' ops/CHANGELOG.md || echo "no rulings recorded this sprint"
```

A sprint with no rulings says so explicitly. A completion marker with unreported rulings is a hidden decision, so this step always precedes Completion.

## Step 2c: Deferred findings export (S14)

Review findings marked `deferred` in the per-cycle dispositions blocks of ops/TASKS.md (`## Review dispositions — Cycle N`), plus any P3 items logged "for later" in Phase 4, must outlive the review files Step 3 archives. Export them now, before anything is archived:

- Fewer than ten rows → append them to ops/MEMORY.md under a `## Deferred findings` heading, one row each: finding, `file:line`, severity, reason deferred, source `REVIEW_*` lane, sprint date.
- Ten or more → write `ops/archive/<YYYY-MM-DD>-deferred-findings.md` with the same columns and add a one-line pointer under `## Deferred findings` in ops/MEMORY.md.
- None → say "no deferred findings this sprint".

Both the rulings list and the deferred-findings export happen BEFORE `ops/.sprint-complete` is created (see Completion).

## Step 3: Archive temporary files

Move to ops/archive/[today's date]/:
- ops/REVIEW_ANTIGRAVITY.md (if exists)
- ops/REVIEW_CODEX.md (if exists)
- ops/TEST_RESULTS.md (if exists)

## Step 4: Verification checklist

Follow `verification-before-completion` skill:
- [ ] All assigned tasks marked done (or blocked with explanation)
- [ ] All tests passing
- [ ] No critical/major issues unresolved
- [ ] CHANGELOG.md updated
- [ ] MEMORY.md updated
- [ ] Rulings I made listed (Step 2b) and deferred findings exported (Step 2c)

## Step 5: Session continuity

Follow `session-continuity` skill — write ops/STATE.md:
- Current phase and progress
- Remaining tasks (if any)
- Key context for next session
- Recommended next actions

## Step 6: Sprint summary

Provide the user with:
- What was accomplished
- What remains (if anything)
- Any decisions that need user input
- **Rulings I made** — the exhaustive list from Step 2b (or "none")
- Deferred findings — where they were exported (Step 2c)
- Metrics (tasks completed, tests passing, review cycles)

## Step 7: Commit with decision context (git trailers)

When creating commits for this sprint's work, append structured trailers to capture decision context that would otherwise be lost:

```
Constraint: <what forced this approach — e.g., "API rate limit requires batch processing">
Rejected: <alternative considered and why — e.g., "WebSocket: too complex for current infra">
Confidence: <high|medium|low — how certain are you this is the right approach>
Scope-risk: <what could break outside the changed files>
Not-tested: <what wasn't covered — e.g., "edge case: concurrent writes">
```

Rules:
- Include at least `Constraint` and `Confidence` on every non-trivial commit
- `Rejected` only when a meaningful alternative was considered
- `Not-tested` only when known gaps exist
- Trailers go after the commit body, separated by a blank line

## Completion

Only when ALL work is verified complete, the rulings list and the deferred-findings export are done (Steps 2b and 2c), and STATE.md is written, create the runtime completion marker as the LAST action:

```bash
touch ops/.sprint-complete
```

This gitignored marker is how outer tooling (`scripts/coordinate.sh`) detects sprint completion. If any verification item failed, do NOT create it — document the blocker instead.
