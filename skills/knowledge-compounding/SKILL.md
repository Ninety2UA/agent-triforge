---
name: knowledge-compounding
description: "Document solved problems and decisions for institutional knowledge. Primary consumer: Claude Code (Phase 6 wrap-up)."
---

# Knowledge Compounding

Each solved problem should make future problems easier. Document non-trivial solutions so they compound over time.

## When to compound

Document a solution when:
- The bug took more than 30 minutes to diagnose
- The solution was non-obvious or counter-intuitive
- The same problem could recur in a different context
- You discovered an undocumented behavior or API quirk
- You made an architectural decision with tradeoffs

Do NOT compound:
- Trivial fixes (typos, missing imports, syntax errors)
- Solutions already documented elsewhere
- One-off workarounds that won't recur

## Solution document format

Write to `ops/solutions/YYYY-MM-DD-slug.md`:

```markdown
---
title: [Descriptive title]
date: YYYY-MM-DD
tags: [relevant technology/module tags]
agent: [which agent solved this]
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

If nothing meets the "when to compound" criteria, produce nothing (absence is valid).

## How compounded knowledge is used

Before planning (Phase 1), the learnings-researcher agent searches `ops/solutions/` and `ops/decisions/` for patterns relevant to the current goal. This prevents:
- Re-investigating known issues
- Repeating rejected approaches
- Missing established conventions
