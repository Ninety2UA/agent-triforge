# Sub-agent mode (default, fewer than 5 independent tasks)

Follow the `wave-orchestration` skill; its "Builder-pool wave protocol" governs assignment, leases and cross-review.

1. Group tasks into waves based on dependencies and file ownership.
2. For each wave:
   1. Assign and dispatch each task under a lease (`lease_create` → `lease_dispatch`), the builder resolved from the roster, context injected.
   2. Apply risk scoring: halt at risk above 20 % or more than 50 changed files (`lease_stop <task>` stops a running builder).
   3. Wait on the builders (`lease_wait`, which collects each finished one; the lease-lifecycle reference has the loop), pin a non-author reviewer (`lease_pin_reviewer`), and merge approved work as one commit per task on the integration branch (`lease_merge`, which refuses self-review AE3, an unknown reviewer, or a merge with no pin).
   4. Verify the integration branch: tests pass, build clean, lint clean, no conflicts. Run the project's build, test and lint commands yourself, in your own checkout of the integration branch where its dependencies are installed, with the output captured to a file. Then start the persona detached, `persona_spawn "$RUN" integration-verifier integration-verifier <that file> "$RUN/verify.md" --at ref:<integration branch> --brief "Judge build, tests and lint from the output in the input, captured in the lead's checkout. Check file conflicts, off-topic changes and contract conformance in your worktree. A failure the environment causes is NEEDS_CONTEXT naming what is missing, never FAIL."` with `RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-wave.XXXXXX")`, and in a separate block rerun `persona_wait "$RUN"` while it returns 75 (a persona can outlast one tool call); read `$RUN/verify.md` once it returns 0 and `integration-verifier.rc` is 0. `FAIL` blocks the next wave. `NEEDS_CONTEXT` comes back to you: fix the environment in your checkout and run both steps again; it never passes a wave on its own. A persona that fails or writes nothing blocks the next wave, the same as a failed verification.
   5. If verification fails, fix before proceeding.
3. After all waves: run the full test suite and a build from a clean state, then promote the integration branch honoring the `[promotion]` gate.

Reliability rules that apply to every builder: retry only after a written self-diagnosis; the same error fingerprint three times means a fresh builder, not another retry.
