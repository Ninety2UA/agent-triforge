# Under Claude Code

- Invoke as `/at-test [--gaps-only] [scope]`.
- Step 1's `test-gap-analyzer` runs through `dispatch_persona` with the Bash tool, not the Agent tool. On rc 40 the tests are written by a sub-agent, the Agent tool (failing test first, results to `ops/TEST_RESULTS.md`): pin model and effort on the spawn and wait for it; a sub-agent that returns nothing is a failed sub-task.
- Run the dispatch block with the Bash tool in the background (its 900 s timeout exceeds the foreground tool limit) and wait on it; `ops/TEST_RESULTS.md` and `$TEST_OUT`, not the shell's exit code, are what Step 3 reads.
