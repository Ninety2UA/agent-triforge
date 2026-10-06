# Step 1: identify test gaps

Write the scope (the paths to analyze) to a file, then run `dispatch_persona test-gap-analyzer <scope file> <out> --brief "Find the untested paths in the scope the input names."` after sourcing the helper. It runs with Bash in a disposable worktree at the default `--at ref:HEAD`, which holds committed work only. When the scope has uncommitted changes (`git status --porcelain -- <scope paths>` prints anything), stop before the dispatch and tell the user the persona sees committed HEAD only; ask them to commit the changes or name a ref for `--at`, and never commit for them. A persona that fails or writes nothing is a failed step, never "no gaps". Its report identifies:

- Files with no tests
- Functions without test coverage
- Missing error path coverage
- Missing edge case coverage
- Weak assertions
- Recommended test writing priority order

With the `--gaps-only` flag: report the gaps and stop.
