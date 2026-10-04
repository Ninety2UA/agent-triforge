# Failure handling

What the lead does when a lease comes back without a report, when the same error recurs, after a hard task, and when an executor's risk accumulates. The reflection questions every retry must answer first are in the core skill (Step 3).

## Report-missing leases

`lease_collect` returns rc 80 (degraded) when a builder exits cleanly but its output has no final `Status:` line. That lease is report-missing: it is NOT review-ready and its output is never handed to a reviewer as if it were a finished build. `lease_collect` itself drives the two-step recovery through the ledger's `report_missing_count`:

1. **First miss: re-dispatch once with the contract restated.** `lease_collect` moves the lease back to `leased` (same builder, same worktree — the builder's uncommitted work is kept; a pinned reviewer stays pinned). The lead runs `lease_dispatch <task> "<one line saying the previous run ended without a report> <original prompt>"`; `lease_dispatch` always prepends the dispatch contract (typed `Status:` report, no sub-dispatch, git stays local — and the lease env refuses a push mechanically: pre-push hook + `no-push://` URL rewrite, SELF-09). Do not route through the requeue path — `lease_requeue` discards the worktree and re-leases to a different builder.
2. **Second miss: escalated.** Two clean exits without a report mean the builder is not following the contract. `lease_collect` sets the lease `escalated` (rc 1) with both output paths in its reason; treat it like a same-error kill: the lead rules (ledgered as a `Ruling:`) whether to reassign the task to a different roster member or to stop the wave for the user.

## Same-error kill criteria

Track error recurrence per executor:
1. When an executor hits an error, fingerprint it (core error message, stripped of line numbers and timestamps)
2. If the same fingerprint appears **3+ times** across retries of the same task:
   - **Kill** the executor immediately (a lease builder still running: `lease_stop <task_id>`)
   - **Reassign** the task to a fresh executor with context: "Previous executor failed 3+ times on this error: [error fingerprint]. Do NOT repeat the same approach. Try a fundamentally different strategy."
3. Log killed executors in the wave execution summary

## Post-task reflection (conditional)

After a task completes, check if reflection is warranted:
- Task took **>3 retries/iterations** to complete, OR
- Task produced **test failures** that required fixes, OR
- Task modified **>5 files**

If any condition is met, append a reflection entry to `ops/MEMORY.md`:

```markdown
## Reflection: [task ID] ([date])
- **Surprise:** [What was unexpected or non-obvious]
- **Pattern:** [One reusable pattern worth adding to conventions]
- **Improvement:** [One prompt or process improvement suggestion]
```

Skip reflection for tasks that completed cleanly on first attempt.

## Risk scoring during execution

Track risk accumulation per executor:
- Revert of own changes: +15%
- Each file modified beyond task scope: +20%
- Each multi-file change: +5%
- Halt executor when risk > 20% or file changes > 50 (`lease_stop <task_id>` for a lease builder)
- Escalate to lead for manual review
