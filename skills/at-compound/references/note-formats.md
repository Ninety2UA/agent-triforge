# Note formats

Both notes are read by the learnings-researcher before planning (Phase 1a), which searches `ops/solutions/` and `ops/decisions/` for patterns relevant to the next goal. The provenance fields (`sprint_id`, `task_id`, `evidence_files`, `related_decisions`) are what make a note findable from a later sprint; fill the ones you know and omit the rest.

## Solution — `ops/solutions/YYYY-MM-DD-slug.md`

```markdown
---
title: [Descriptive title]
date: YYYY-MM-DD
tags: [relevant technology/module tags]
agent: [which agent solved this]
sprint_id: [sprint or goal identifier, if applicable]
task_id: [task ID from ops/TASKS.md, if applicable]
evidence_files: [files that demonstrate the fix]
related_decisions: [related decision file slugs]
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

## Decision — `ops/decisions/YYYY-MM-DD-slug.md`

```markdown
---
title: [Decision title]
date: YYYY-MM-DD
status: accepted
sprint_id: [sprint or goal identifier, if applicable]
task_id: [task ID from ops/TASKS.md, if applicable]
agent: [which agent made this decision]
related_decisions: [related decision file slugs]
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

`status` is `accepted` for a new decision; a later note that replaces it sets the old one to `superseded` (or `deprecated`) and names it under `related_decisions`.

## What clears the bar, what does not

Clears it: a diagnosed race or ordering dependency, a library behaviour that contradicts its documentation, an API quirk that cost investigation, a decision with rejected alternatives, a convention adopted on purpose, an environment difference that changed an outcome.

Does not: a typo, a missing import, a syntax error, a one-line workaround whose whole explanation is in the diff and the commit message, a solution already documented elsewhere (link it), a one-off workaround that cannot recur.
