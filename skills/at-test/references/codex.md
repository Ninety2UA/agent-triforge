# Under Codex

- Invoke as `$at-test [--gaps-only] [scope]` in the task prompt.
- Step 1's `test-gap-analyzer` starts detached through `persona_spawn` from the shell tool, not `spawn_agent`; run the wait block in `exec_command`: `persona_wait` returns inside the registry's 900 s `wait_budget_s`, with 75 while personas still run, so you rerun it. A tester that resolves to claude runs as a `claude -p` worker inside `dispatch_role` (edit tools in this checkout, Bash in Claude Code's sandbox), so rc 40 does not come back under this lead; its report lands in `$TEST_OUT`.
- Run the dispatch block through the shell tool and read `ops/TEST_RESULTS.md` and `$TEST_OUT` afterward; under `codex exec` the 900 s dispatch must finish inside the session, so background it and poll the output file when the shell call would time out first.
