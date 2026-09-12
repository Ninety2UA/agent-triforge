---
name: knowledge-compounding
description: "Counterfactual-gated capture of solved problems and decisions into ops/solutions/ and ops/decisions/. Use when a task completes and a future agent without a note would plausibly repeat the mistake or re-derive the decision, or when a wrap-up must confirm nothing that cleared that bar was skipped. Not for trivial fixes whose reasoning is recoverable from the diff; those produce no note, and this skill says why."
metadata:
  triforge-consumer: "Claude (lead)"
  triforge-phase: "task completion (lease_collect); 6 (wrap-up)"
  version: "3.3.0"
---

# Knowledge Compounding

Each solved problem should make future problems easier. Document the solutions and decisions whose reasoning would otherwise be lost.

## The counterfactual bar

Compound only when this sentence is true: **a future agent without this note would plausibly repeat the mistake or re-derive the decision.**

Test it with three questions:

1. Is the reasoning recoverable from the final code, tests, or docs? If yes, the diff is the note. Write nothing.
2. Would losing it cause recurrence, risk, or rediscovery? If no, write nothing.
3. Can you name the future task that would hit it? If not, the note has no reader.

Trivial fixes are not compounded, and here is why: a typo, a missing import, a syntax error, or a one-line workaround carries its whole explanation in the diff and the commit message. A note for it adds a file that a future reader must open and dismiss, which is exactly the cost the store exists to avoid. Narrating a diff is not knowledge.

What clears the bar: a diagnosed race or ordering dependency, a library behavior that contradicts its documentation, an API quirk that cost investigation, a decision with rejected alternatives, a convention adopted on purpose, an environment difference that changed an outcome.

Duration and diff size are not the criteria. A ten-minute fix can clear the bar; a two-day build whose reasoning is fully in its tests may not.

## When to capture

Capture at task completion, not at sprint end. When the lead collects a lease (`lease_collect`) or closes a task, apply the bar to that task while the reasoning is fresh; the builder's "Discoveries for later tasks" block is the first input. Phase 6 wrap-up only checks that nothing which cleared the bar was skipped. It is not the moment to reconstruct a sprint's learnings from memory.

Do NOT compound:
- Solutions already documented elsewhere (link to them instead)
- One-off workarounds that cannot recur
- Anything whose reasoning the diff already states

## Common rationalizations

| Excuse | Reality |
|---|---|
| "It took a long time, so it must be worth a note" | Duration is not the bar. Ask whether the reasoning is recoverable from the diff. |
| "I will write up the sprint's learnings at wrap" | By wrap the reasoning is gone. Capture at task completion. |
| "A note never hurts" | Every note is a file a future reader opens and dismisses. Notes that fail the bar make the ones that pass harder to find. |
| "The fix was small, skip it" | Small fixes with non-obvious causes (a race, a docs-contradicting behavior) clear the bar. Size is not the criterion either. |

## Solution document format

Write to `ops/solutions/YYYY-MM-DD-slug.md`:

```markdown
---
title: [Descriptive title]
date: YYYY-MM-DD
tags: [relevant technology/module tags]
agent: [which agent solved this]
sprint_id: [sprint or goal identifier, if applicable]
task_id: [task ID from TASKS.md, if applicable]
evidence_files: [list of files that demonstrate the fix]
related_decisions: [list of related decision file slugs]
---

## Problem
[What went wrong — be specific about symptoms and context]

## Root cause
[Why it went wrong — the actual underlying issue]

## Solution
[What fixed it — include code snippets if helpful]

## Prevention
[How to prevent this class of problem in the future]

## Related
- [Links to related files, issues, or other solutions]
```

## Decision record format

Write to `ops/decisions/YYYY-MM-DD-slug.md`:

```markdown
---
title: [Decision title]
date: YYYY-MM-DD
status: accepted | superseded | deprecated
sprint_id: [sprint or goal identifier, if applicable]
task_id: [task ID from TASKS.md, if applicable]
agent: [which agent made this decision]
related_decisions: [list of related decision file slugs]
---

## Context
[What situation prompted this decision]

## Decision
[What we decided to do]

## Alternatives considered
- [Alternative 1]: [why rejected]
- [Alternative 2]: [why rejected]

## Consequences
- [Positive consequence]
- [Negative consequence / tradeoff]
```

## Output

Produce one or both:
- `ops/solutions/YYYY-MM-DD-slug.md` — for solved problems (using format above)
- `ops/decisions/YYYY-MM-DD-slug.md` — for architectural decisions (using format above)

If nothing clears the counterfactual bar, write nothing and say so in one line naming where the reasoning lives: `nothing compounded: reasoning is recoverable from <diff / tests / commit message>`. Absence is a valid result; a note that fails the bar is not.

## How compounded knowledge is used

Before planning (Phase 1), the learnings-researcher agent searches `ops/solutions/` and `ops/decisions/` for patterns relevant to the current goal. This prevents:
- Re-investigating known issues
- Repeating rejected approaches
- Missing established conventions
