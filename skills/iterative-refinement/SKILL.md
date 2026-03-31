---
name: iterative-refinement
description: "Review-fix-review loop methodology with convergence modes and cycle limits. Primary consumer: Claude Code (Phase 4 review processing)."
---

# Iterative Refinement

Process review findings in structured cycles until quality converges.

## The loop

```
REVIEW → TRIAGE → FIX → VERIFY → (loop or exit)
```

## Step 1: Triage findings

Categorize all findings from all reviewers (REVIEW_GEMINI.md, REVIEW_CODEX.md, subagent reviews):

| Priority | Definition | Action |
|---|---|---|
| P1 Critical | Security vulnerability, data loss, crash, broken core flow | Fix immediately this cycle |
| P2 Important | Performance at scale, missing error handling, test gaps, logic errors | Fix this cycle |
| P3 Suggestion | Style, naming, documentation, minor optimization | Log for later or fix if trivial |

Apply confidence tiering:
- **[HIGH]** — verified in codebase (grep confirms), reliably detectable → trust the finding
- **[MEDIUM]** — pattern-aggregated, some noise expected → verify before fixing
- **[LOW]** — requires intent verification → never treat as P1, investigate first

Rule: LOW confidence findings cannot be P1. If a finding is LOW confidence, it is at most P2.

## Step 2: Deduplicate

When multiple reviewers flag the same issue:
- Same problem, same recommendation → single entry, higher confidence
- Same problem, different recommendations → single entry, note both approaches, decide based on ARCHITECTURE.md
- Different problems, same code location → keep both as separate entries
- One approves, one flags → the flag wins

## Step 3: Fix

Fix in priority order: P1 first, then P2, then P3 (if time allows).

For each fix:
1. Understand the root cause (not just the symptom)
2. Make the minimal change that resolves the issue
3. Verify existing tests still pass
4. If the fix is substantial (touches 3+ files), flag for re-review

## Step 4: Convergence check

### Convergence modes

| Mode | Exit criteria | When to use |
|---|---|---|
| Fast | P1 count = 0 | Time-pressured, fix critical only |
| Standard | P1 = 0 AND P2 = 0 | Normal development (default) |
| Deep | P1 = 0 AND P2 = 0 AND P3 < 3 | High-quality release |

### Cycle limits

- Maximum 3 review-fix cycles per sprint
- If issues persist after 3 cycles, escalate to user with:
  - Summary of remaining issues
  - All reviewers' perspectives
  - Your recommendation
  - Whether to ship with known issues or continue fixing

### Exit decision

After each fix cycle:
- Count remaining issues by priority
- Check against convergence mode
- If converged → exit loop, proceed to testing
- If not converged AND cycles < 3 → re-trigger review on changed files only
- If not converged AND cycles = 3 → escalate

## Output

After each cycle, produce:
- Remaining issue counts by priority (P1/P2/P3)
- What was fixed this cycle with confidence level
- Convergence status (converged / not converged — cycle N of 3)
- If escalating: summary of remaining issues, all perspectives, and recommendation

## Suppressions (do not flag)

These patterns should NOT be treated as findings:
- Redundancy that aids readability (e.g., explicit type annotations where inference works)
- Documented threshold values with clear comments
- Sufficient test assertions (don't flag "too few assertions" if behavior is covered)
- Consistency-only changes (don't flag "could use X instead of Y" when Y is the project convention)
- Already-addressed issues visible in the diff
- Harmless no-ops (e.g., `return undefined` at end of void function)
