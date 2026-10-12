# Step 3: process test results

1. Read `ops/TEST_RESULTS.md`.
2. If all tests pass → report success.
3. If tests fail:
   - Read the failing test details.
   - Fix the underlying code.
   - Re-run the specific failing tests through the tester (the same role dispatch as Step 2).
   - Loop until green (max 3 cycles); after the third cycle, escalate the remaining failures to the user.
4. Report the final coverage metrics.
