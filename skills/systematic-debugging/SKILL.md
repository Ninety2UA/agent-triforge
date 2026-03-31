---
name: systematic-debugging
description: "Structured debugging methodology with error taxonomy, assumption tracking, and root cause analysis. Primary consumer: Codex CLI (bug investigation), also Claude."
---

# Systematic Debugging

Never guess. Follow the diagnostic protocol.

## Step 1: Classify the error

Before investigating, classify the error type:

| Category | Signal | Approach |
|---|---|---|
| Syntax/type error | Compiler/linter catches it | Read the error message literally |
| Logic error | Wrong output, tests fail | Trace inputs through logic path |
| State error | Intermittent, order-dependent | Map state transitions, find mutation |
| Integration error | Works alone, fails connected | Check boundaries, contracts, formats |
| Environment error | Works for some, not others | Diff environments, check config |
| Performance error | Correct but slow/resource-heavy | Profile, find hotspot, check complexity |

## Step 2: Reproduce reliably

1. Find the minimal reproduction case
2. Write a failing test that captures the bug (this becomes your RED test)
3. If it can't be reproduced, gather more data before proceeding
4. Document the reproduction steps

## Step 3: Track assumptions

Create an assumption ledger. For each assumption about the bug:

```
ASSUMPTION: [what I believe is true]
STATUS: [unverified / confirmed / disproven]
EVIDENCE: [what I checked to verify]
```

Check assumptions in order of:
1. Easiest to verify
2. Most likely to be wrong
3. Most impactful if wrong

## Step 4: Narrow the search

Use bisection — not linear scanning:
- **Binary search in time:** find the commit that introduced the bug (git bisect)
- **Binary search in code:** comment out half the system, see if bug persists
- **Binary search in data:** try with half the input, narrow to the triggering element

## Step 5: Root cause analysis

When you find the proximate cause, ask "why" up to 5 times:
1. Why did this function return null? → The query returned no rows
2. Why did the query return no rows? → The filter condition used `=` on a nullable column
3. Why was the column nullable? → The migration didn't add a NOT NULL constraint
4. Why wasn't the constraint added? → The seed data had nulls, so migration would fail
5. Root cause: seed data quality issue masked by missing constraint

## Step 6: Fix and verify

1. Fix the ROOT cause (not the symptom)
2. Run the failing test from Step 2 — it should now pass
3. Run the full test suite — no regressions
4. Log the root cause in MEMORY.md#Gotchas for future reference

## Output

Produce a structured diagnosis:
- Error classification (from Step 1)
- Reproduction steps and failing test
- Assumption ledger with confirmed/disproven status
- Root cause chain (the "5 whys")
- Fix applied and verification evidence (test results)
- MEMORY.md entry if root cause was non-obvious

## Degradation detection

Watch for signals that the system is under stress:
- Increasing error rates (not just absolute errors)
- Latency percentile shifts (p99 moving before p50)
- Resource usage creep (memory/connections growing over time)
- Retry storms (exponential backoff failing to resolve)

## Contradiction detection

If two findings contradict each other, do NOT pick one — flag the contradiction:
```
CONTRADICTION: [finding A] vs [finding B]
RESOLUTION NEEDED: [what would resolve this]
```

Never summarize contradictions away. Reconcile against actual system state.
