# Under Codex

- Invoke as `$agent-triforge:at-debug` in the task prompt, followed by the bug description or error message.
- Step 1's validator starts detached through `persona_spawn` from the shell tool, not `spawn_agent`; run the wait block in `exec_command`: `persona_wait` returns inside the registry's 900 s `wait_budget_s`, with 75 while personas still run, so you rerun it.
- The anti-pattern sweep and the test runs go through the shell tool. Under `codex exec` no user answers, so a NOT_REPRODUCIBLE classification ends the run with the request for details in the reply.
