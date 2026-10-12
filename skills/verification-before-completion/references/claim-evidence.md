# Claim, evidence, and what is not enough

The proof each kind of claim needs, and what is commonly offered in its place. Read it when naming the proof (step 2 of the gate function).

## The table

| Claim | Requires | Not sufficient |
|---|---|---|
| Tests pass | The full suite run after the last change, with the exit code and totals quoted | Running only the new tests; a run from before the last edit; a builder's "all green" line |
| Bug fixed | Red-green-revert: the reproduction fails on the old code, passes on the fix, and fails again when the fix is reverted | The symptom not appearing once; a fix that should cover it |
| Regression test works | Red-green-revert, with the test's failure message naming the behavior it guards | A test that passed the first time it ran |
| Feature works | The feature exercised end to end through its real entry point, with the observed output quoted | Unit tests alone; reading the code; a screenshot from an earlier build |
| Migration applied | The schema or data queried after the migration and the result quoted; the rollback tried on a scratch copy | The migration file existing; the migration command exiting 0 |
| Docs match code | Every documented command or flag executed as written, and every documented name grepped in the source, with hits quoted | Rereading the docs for style; the docs and code changing in the same commit |
| Refactor preserves behavior | The pre-refactor tests (or characterization tests) unchanged and green, and the VCS diff shows only intended changes | "The logic is equivalent"; new tests written alongside the refactor |
| Builder completed | The VCS diff read by the lead shows the change, and the builder's final Status line parsed | The builder's prose report; a clean exit code |
| Lint clean | The linter run on the changed files with zero findings quoted | The editor showing no warnings |
