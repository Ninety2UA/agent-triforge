# Step 3: process test results

1. Read `ops/TEST_RESULTS.md`.
2. If all tests pass → report success.
3. If tests fail:
   - Read the failing test details.
   - Fix the underlying code under a lease with a pinned non-author reviewer (the `at-build` lease loop: `lease_create`, `lease_dispatch`, `lease_pin_reviewer`, `lease_merge`), never by editing it in place. `lease_merge` refuses the default branch: when the checkout is on it (a sprint that already promoted), start a new sprint integration branch first and promote it with `lease_promote` after the merge.
   - Re-run the specific failing tests through the tester (the same role dispatch as Step 2).
   - Loop until green (max 3 cycles); after the third cycle, escalate the remaining failures to the user.
   - Inside a sprint whose review already converged, every code or test change here also needs the non-author delta review before completion (`at-ship` and `at-coordinate` Phase 5), counted against the review's three-cycle cap.
4. Report the final coverage metrics.
