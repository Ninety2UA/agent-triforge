# Sub-agent mode (default, fewer than 5 independent tasks)

Follow the `wave-orchestration` skill; its "Builder-pool wave protocol" governs assignment, leases and cross-review.

1. Group tasks into waves based on dependencies and file ownership.
2. For each wave:
   1. Assign and dispatch each task under a lease (`lease_create` → `lease_dispatch`), the builder resolved from the roster, context injected.
   2. Apply risk scoring: halt at risk above 20 % or at 50 or more file changes (`lease_stop <task>` stops a running builder).
   3. Wait on the builders (`lease_wait`, which collects each finished one; the lease-lifecycle reference has the loop), pin a non-author reviewer (`lease_pin_reviewer`), and merge approved work as one commit per task on the integration branch (`lease_merge`, which refuses self-review AE3, an unknown reviewer, or a merge with no pin).
   4. Spawn `integration-verifier` as a sub-agent against the integration branch: tests pass, build clean, lint clean, no conflicts.
   5. If verification fails, fix before proceeding.
3. After all waves: run the full test suite and a build from a clean state, then promote the integration branch honoring the `[promotion]` gate.

Reliability rules that apply to every builder: retry only after a written self-diagnosis; the same error fingerprint three times means a fresh builder, not another retry.
