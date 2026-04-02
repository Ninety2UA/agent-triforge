---
description: "Wrap the current session: compound knowledge, archive files, write STATE.md for next session."
---

You are executing Phase 6 (Wrap up) of the multi-agent framework.

## Step 1: Knowledge compounding

Follow the `knowledge-compounding` skill:
- If any non-trivial problem was solved this session, document it in ops/solutions/YYYY-MM-DD-slug.md
- If any architectural decision was made, document it in ops/decisions/YYYY-MM-DD-slug.md
- Check: was anything surprising, counter-intuitive, or hard to debug? → document it

## Step 2: Update shared files

- Update ops/CHANGELOG.md with final session summary
- Update ops/MEMORY.md with new decisions, patterns, and gotchas discovered
- Move all completed tasks to "Done" in ops/TASKS.md with result summaries

## Step 3: Archive temporary files

Move to ops/archive/[today's date]/:
- ops/REVIEW_GEMINI.md (if exists)
- ops/REVIEW_CODEX.md (if exists)
- ops/TEST_RESULTS.md (if exists)

## Step 4: Verification checklist

Follow `verification-before-completion` skill:
- [ ] All assigned tasks marked done (or blocked with explanation)
- [ ] All tests passing
- [ ] No critical/major issues unresolved
- [ ] CHANGELOG.md updated
- [ ] MEMORY.md updated

## Step 5: Session continuity

Follow `session-continuity` skill — write ops/STATE.md:
- Current phase and progress
- Remaining tasks (if any)
- Key context for next session
- Recommended next actions

## Step 6: Sprint summary

Provide the user with:
- What was accomplished
- What remains (if anything)
- Any decisions that need user input
- Metrics (tasks completed, tests passing, review cycles)

## Step 7: Commit with decision context (git trailers)

When creating commits for this sprint's work, append structured trailers to capture decision context that would otherwise be lost:

```
Constraint: <what forced this approach — e.g., "API rate limit requires batch processing">
Rejected: <alternative considered and why — e.g., "WebSocket: too complex for current infra">
Confidence: <high|medium|low — how certain are you this is the right approach>
Scope-risk: <what could break outside the changed files>
Not-tested: <what wasn't covered — e.g., "edge case: concurrent writes">
```

Rules:
- Include at least `Constraint` and `Confidence` on every non-trivial commit
- `Rejected` only when a meaningful alternative was considered
- `Not-tested` only when known gaps exist
- Trailers go after the commit body, separated by a blank line

## Completion

Only when ALL work is verified complete and STATE.md is written:
<promise>DONE</promise>
