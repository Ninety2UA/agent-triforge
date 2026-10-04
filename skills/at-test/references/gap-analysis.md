# Step 1: identify test gaps

Write the scope to a brief file, then run `dispatch_persona test-gap-analyzer <brief file> <out>` after sourcing the helper; it runs with Bash in a disposable worktree at the default `--at ref:HEAD`. A persona that fails or writes nothing is a failed step, never "no gaps". Its report identifies:

- Files with no tests
- Functions without test coverage
- Missing error path coverage
- Missing edge case coverage
- Weak assertions
- Recommended test writing priority order

With the `--gaps-only` flag: report the gaps and stop.
