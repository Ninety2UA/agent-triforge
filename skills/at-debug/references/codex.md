# Under Codex

- Invoke as `$at-debug` in the task prompt, followed by the bug description or error message.
- Step 1's validator runs through `dispatch_persona` from the shell tool, not `spawn_agent`.
- The anti-pattern sweep and the test runs go through the shell tool. Under `codex exec` no user answers, so a NOT_REPRODUCIBLE classification ends the run with the request for details in the reply.
