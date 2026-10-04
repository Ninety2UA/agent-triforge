# Step 1: identify test gaps

Run `dispatch_persona test-gap-analyzer` with the scope and an output file, after sourcing the helper. A persona that fails or writes nothing is a failed step, never "no gaps". Its report identifies:

- Files with no tests
- Functions without test coverage
- Missing error path coverage
- Missing edge case coverage
- Weak assertions
- Recommended test writing priority order

With the `--gaps-only` flag: report the gaps and stop.
