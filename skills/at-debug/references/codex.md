# Under Codex

- Invoke as `$at-debug` in the task prompt, followed by the bug description or error message.
- Step 1's validator is `spawn_agent` with the `bug-reproduction-validator` prompt inlined (Codex loads no plugin agents); wait for it, and treat an empty return as a failed sub-task, not as NOT_REPRODUCIBLE.
- The anti-pattern sweep and the test runs go through the shell tool. Under `codex exec` no user answers, so a NOT_REPRODUCIBLE classification ends the run with the request for details in the reply.
