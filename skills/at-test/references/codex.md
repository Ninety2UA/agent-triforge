# Under Codex

- Invoke as `$at-test [--gaps-only] [scope]` in the task prompt.
- A sub-agent is `spawn_agent` with the persona prompt inlined (the `test-gap-analyzer` prompt from the Triforge tree; Codex loads no plugin agents). On rc 40 the tester resolved to the lead's native sub-agent lane: spawn the test writer the same way, failing test first, results to `ops/TEST_RESULTS.md`.
- Run the dispatch block through the shell tool and read `ops/TEST_RESULTS.md` and `$TEST_OUT` afterward; under `codex exec` the 900 s dispatch must finish inside the session, so background it and poll the output file when the shell call would time out first.
