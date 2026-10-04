# Step 1: identify test gaps

Spawn a sub-agent with the `test-gap-analyzer` persona on the scope. It identifies:

- Files with no tests
- Functions without test coverage
- Missing error path coverage
- Missing edge case coverage
- Weak assertions
- Recommended test writing priority order

With the `--gaps-only` flag: report the gaps and stop.
