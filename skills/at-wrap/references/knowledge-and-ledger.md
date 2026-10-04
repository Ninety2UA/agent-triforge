# Knowledge compounding, shared files, rulings and deferred findings

## Step 1: knowledge compounding

Follow the `knowledge-compounding` skill, gated by the counterfactual bar (CE-1): compound only when a future agent **without** the note would plausibly repeat the mistake or re-derive the decision, that is, when the reasoning is not recoverable from the final code, tests and docs. Duration and effort are not the bar.

- If a problem solved this session passes the bar, document it in `ops/solutions/YYYY-MM-DD-slug.md`.
- If an architectural decision passes the bar, document it in `ops/decisions/YYYY-MM-DD-slug.md`.
- Check: was anything surprising, counter-intuitive, or hard to debug in a way the diff does not explain? Document it.
- If nothing passes the bar, write nothing and say so ("Not compounded: reasoning recoverable from <file or diff>"); a diff narration never qualifies.

## Step 2: update shared files

- If `ops/TASKS.md` opens with `Ceremony: high-ceremony` (S16), the session summary must cite the plan-checker pass, the `--full` review, and the integration-verifier result by name; a missing one is recorded as a gap in `ops/STATE.md`, never papered over.
- Update `ops/CHANGELOG.md` with the final session summary.
- Update `ops/MEMORY.md` with new decisions, patterns, and gotchas discovered.
- Move all completed tasks to "Done" in `ops/TASKS.md` with result summaries.

## Step 2b: rulings I made (S1)

Every non-catastrophic conflict the lead ruled on during the sprint was ledgered in `ops/CHANGELOG.md` as `Ruling: <what> | <why> | <cost if wrong>`. Collect them all (the list is exhaustive, never a sample) and print it under a **Rulings I made** heading in the sprint summary so the user can overturn any of them:

```bash
# Rulings I made (S1): every Ruling: line ledgered this sprint. Runs BEFORE
# the archive step moves anything and BEFORE ops/.sprint-complete exists.
grep -n 'Ruling:' ops/CHANGELOG.md || echo "no rulings recorded this sprint"
```

A sprint with no rulings says so explicitly. A completion marker with unreported rulings is a hidden decision, so this step always precedes completion.

## Step 2c: deferred findings export (S14)

Review findings marked `deferred` in the per-cycle dispositions blocks of `ops/TASKS.md` (`## Review dispositions — Cycle N`), plus any P3 items logged "for later" in Phase 4, must outlive the review files the archive step moves. Export them now, before anything is archived:

- Fewer than ten rows: append them to `ops/MEMORY.md` under a `## Deferred findings` heading, one row each: finding, `file:line`, severity, reason deferred, source `REVIEW_*` lane, sprint date.
- Ten or more: write `ops/archive/<YYYY-MM-DD>-deferred-findings.md` with the same columns and add a one-line pointer under `## Deferred findings` in `ops/MEMORY.md`.
- None: say "no deferred findings this sprint".

Both the rulings list and the deferred-findings export happen BEFORE `ops/.sprint-complete` is created.
