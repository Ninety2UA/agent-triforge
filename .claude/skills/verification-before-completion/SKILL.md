---
name: verification-before-completion
description: "Evidence-based completion verification checklist. Used by all agents before marking work done."
---

# Verification Before Completion

Never claim completion without evidence. Every claim must be backed by a check.

## Completion checklist

Before marking ANY task as done, verify:

### Code quality
- [ ] Code compiles/transpiles without errors
- [ ] No new linter warnings introduced
- [ ] No commented-out code left behind
- [ ] No debug logging (console.log, print, debugger) left in production code
- [ ] No hardcoded secrets, API keys, or credentials

### Tests
- [ ] All existing tests pass (run full suite, not just new tests)
- [ ] New code has corresponding tests
- [ ] Tests actually test behavior (not just line coverage)
- [ ] Edge cases covered (empty inputs, boundaries, error conditions)

### Contracts
- [ ] Output conforms to interfaces defined in CONTRACTS.md
- [ ] If new interfaces were introduced, they are documented
- [ ] If existing interfaces were modified, change was proposed in MEMORY.md first

### Integration
- [ ] Changes work with the rest of the system (not just in isolation)
- [ ] No N+1 queries or obvious performance regressions
- [ ] Error handling covers failure modes (timeouts, missing data, auth failures)

### Documentation
- [ ] CHANGELOG.md updated with changes and attribution
- [ ] MEMORY.md updated with any new decisions, patterns, or gotchas
- [ ] TASKS.md updated (task moved to "Done" with result summary)

## Output

Produce a completed checklist with pass/fail status for each item, plus:
- `<promise>DONE</promise>` if all checks pass
- Blocker documentation in TASKS.md if any check fails

## Completion signal

Only after ALL checks pass, emit the completion signal:

```
<promise>DONE</promise>
```

This signal means: "I have verified that all work is complete and all checks pass." It is not a summary — it is a commitment.

## What to do when checks fail

- If tests fail: fix the code, re-run, do not mark done
- If linter fails: fix the warnings, re-run
- If integration fails: investigate, fix root cause, re-verify
- If you cannot fix an issue: do NOT mark done. Instead:
  1. Document the blocker in TASKS.md
  2. Create a new task for the unresolved issue
  3. Mark current task as BLOCKED (not done)
