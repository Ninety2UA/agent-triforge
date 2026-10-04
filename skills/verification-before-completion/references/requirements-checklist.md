# Requirements met

The completion checklist. Each item is a claim; each claim needs its own proof under the gate function.

## Before marking a task done

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
