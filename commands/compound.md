---
description: "Document a solved problem or architectural decision to ops/solutions/ or ops/decisions/."
argument-hint: "[solution | decision] <description>"
---

You are documenting institutional knowledge. Follow the `knowledge-compounding` skill.

## Input
$ARGUMENTS

## Determine the type

If the input describes a **solved problem** (bug fix, workaround, non-obvious behavior):
→ Write to ops/solutions/

If the input describes an **architectural decision** (chose X over Y, tradeoff analysis):
→ Write to ops/decisions/

If unclear, ask the user.

## For solutions

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

## For decisions

Write to `ops/decisions/YYYY-MM-DD-slug.md`:

```markdown
---
title: [Decision title]
date: YYYY-MM-DD
status: accepted
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

## After writing

Confirm to user: "Documented to ops/[solutions|decisions]/[filename]. The learnings-researcher agent will find this in future sprints."
