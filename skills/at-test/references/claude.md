# Under Claude Code

- Invoke as `/at-test [--gaps-only] [scope]`.
- A sub-agent is the Agent tool: the `test-gap-analyzer` persona for Step 1, and on rc 40 a sub-agent that writes the tests (failing test first, results to `ops/TEST_RESULTS.md`). Pin model and effort on every spawn and wait for each one; a sub-agent that returns nothing is a failed sub-task.
- Run the dispatch block with the Bash tool in the background (its 900 s timeout exceeds the foreground tool limit) and wait on it; `ops/TEST_RESULTS.md` and `$TEST_OUT`, not the shell's exit code, are what Step 3 reads.
