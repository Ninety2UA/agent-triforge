---
description: "Structured debugging: reproduce → diagnose → fix using systematic methodology."
argument-hint: "<bug description or error message>"
---

You are debugging a reported issue. Follow the systematic-debugging skill methodology.

## Bug report
$ARGUMENTS

## Step 1: Validate the bug

Spawn the `bug-reproduction-validator` agent:
"Validate this bug report: $ARGUMENTS"

The validator will:
- Attempt to reproduce the issue
- Write a failing test if reproducible
- Identify the root cause
- Classify: CONFIRMED | INTERMITTENT | NOT_REPRODUCIBLE | ALREADY_FIXED

If NOT_REPRODUCIBLE: report to user, ask for more details. Stop.
If ALREADY_FIXED: report the fixing commit. Stop.

## Step 2: Diagnose (if confirmed)

Follow the `systematic-debugging` skill:

1. **Classify the error** (syntax, logic, state, integration, environment, performance)
2. **Track assumptions** — create an assumption ledger, verify each one
3. **Narrow the search** — use bisection, not linear scanning
4. **Root cause analysis** — ask "why" up to 5 times to find the actual root cause
5. **Check for contradiction** — if two findings conflict, flag it, don't silently pick one

## Step 3: Fix

1. Fix the ROOT cause, not the symptom
2. Run the failing test from Step 1 — it should now pass
3. Run the full test suite — no regressions
4. Check if similar patterns exist elsewhere (grep for same anti-pattern)
   - If found: create tasks in ops/TASKS.md for those instances

## Step 4: Document

- Log the root cause in ops/MEMORY.md#Gotchas
- If the bug took > 30 minutes or was non-obvious, document in ops/solutions/ via knowledge-compounding skill
- Update ops/CHANGELOG.md with the fix and root cause
