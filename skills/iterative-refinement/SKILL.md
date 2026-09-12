---
name: iterative-refinement
description: "Review-fix-review loop with confidence tiering, convergence modes, a per-cycle dispositions ledger, and a three-cycle cap. Use when processing findings from parallel reviewers after a build, when deciding whether another review cycle is needed, or when a task returns from a fix cycle. Not for merging reviewer outputs into one report; that is review-synthesis, which runs first."
metadata:
  triforge-consumer: "Claude (lead)"
  triforge-phase: "4 (process reviews)"
  version: "3.3.0"
---

# Iterative Refinement

Process review findings in structured cycles until quality converges.

## The loop

```
REVIEW → TRIAGE → FIX → DISPOSITIONS → VERIFY → (loop or exit)
```

## No pre-judging

The lead does not tell reviewers which findings are acceptable before they review. A review dispatch carries the diff, the task rows, the contracts slice, and the category-level suppressions below; it never carries "the plan chose X, do not flag it", "treat Y as at most Minor", or "ignore the retry logic". Reviewers report what they see; adjudication happens here, in triage, and is recorded in the dispositions ledger where the user can audit it.

Treat a builder's report as unverified claims. A rationale in the report ("this is safe because…") never lowers a finding's severity; only evidence does.

## Step 1: Triage findings

Categorize all findings from all reviewers (REVIEW_ANTIGRAVITY.md, REVIEW_CODEX.md, subagent reviews):

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

## Step 4: Record dispositions

After the fixes of a cycle, append one block to `ops/TASKS.md` (under the task, or under a `## Review dispositions` section for a sprint-wide review). Every finding from the cycle gets a row; later cycles add new blocks and never edit earlier ones, so the ledger shows how each concern was handled across cycles.

```markdown
## Review dispositions — Round N (<REVIEW_* snapshot commit>)

| Finding | Severity | Disposition | Detail |
|---|---|---|---|
| src/auth/login.ts:45 — SQL injection via email input | P1 | fixed | parameterized query, commit abc1234 |
| src/api/users.ts:89 — possible N+1 in user list | P2 | dismissed | reason: ORM batches the relation; verified with query log |
| src/utils/format.ts:12 — simplify | P3 | deferred | follow-up task T9 |
```

Dispositions are exactly one of `fixed`, `dismissed` (always with a reason a reader can check), or `deferred` (always with where it went). A finding with no row was not triaged; the cycle is not complete until every finding has one.

## Step 5: Convergence check

### Convergence modes

| Mode | Exit criteria | When to use |
|---|---|---|
| Fast | P1 count = 0 | Time-pressured, fix critical only |
| Standard | P1 = 0 AND P2 = 0 | Normal development (default) |
| Deep | P1 = 0 AND P2 = 0 AND P3 < 3 | High-quality release |

A dismissed finding counts as resolved for convergence only when its reason is evidence (a grep, a run, a contract clause), not a preference.

### Cycle limits

- Maximum 3 review-fix cycles per sprint
- If issues persist after 3 cycles, escalate to user with:
  - Summary of remaining issues
  - All reviewers' perspectives
  - The dispositions ledger for every round
  - Your recommendation
  - Whether to ship with known issues or continue fixing

### Exit decision

After each fix cycle:
- Count remaining issues by priority
- Check against convergence mode
- If converged → exit loop, proceed to testing
- If not converged AND cycles < 3 → re-trigger review on changed files only
- If not converged AND cycles = 3 → escalate

## Suppressions (category-level only)

Never instruct a reviewer to ignore a specific issue. Suppressions name a category of finding that is noise in this project, never a location, a finding, or a task's design choice. If a specific finding should not block, it gets a `dismissed` row with a reason in the dispositions ledger; it is not pre-filtered out of the review.

These categories are not findings:
- Redundancy that aids readability (e.g., explicit type annotations where inference works)
- Documented threshold values with clear comments
- Sufficient test assertions (do not flag "too few assertions" when behavior is covered)
- Consistency-only changes (do not flag "could use X instead of Y" when Y is the project convention)
- Test fixtures and generated files (do not flag style inside them)
- Already-addressed issues visible in the diff
- Harmless no-ops (e.g., `return undefined` at end of void function)

## Common rationalizations

| Excuse | Reality |
|---|---|
| "Tell the reviewer the plan chose this so it does not waste a finding" | That is pre-judging. Let the finding land, then dismiss it with a checkable reason in the ledger. |
| "The builder explained why it is safe" | A rationale is a claim. Severity moves only on evidence. |
| "Three findings were trivial, I fixed them without rows" | A finding with no row was not triaged. Every finding gets a disposition. |
| "It is cycle 3, mark the rest as deferred and converge" | Deferred rows need a destination. Without one, escalate; do not launder a stall into convergence. |
| "Re-run the suite to check the reviewer's claim" | The tester role owns runs. Re-read the file at its path; report a gap if the evidence is truncated. |

## Output

After each cycle, produce:
- Remaining issue counts by priority (P1/P2/P3)
- What was fixed this cycle with confidence level
- The `## Review dispositions — Round N` block appended to `ops/TASKS.md`
- Convergence status (converged / not converged — cycle N of 3)
- If escalating: summary of remaining issues, all perspectives, the full dispositions ledger, and recommendation
