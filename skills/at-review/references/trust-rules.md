# Reviewer trust rules (S6/S7)

Every reviewer lane (the two core lanes, the optional-tier lanes, and the specialist sub-agents) is dispatched under the same rules:

- **The review package** is the diff, the task rows from `ops/TASKS.md`, the relevant `ops/CONTRACTS.md` slice, and the acceptance criteria (`Accept:` / `Fails when:`). Nothing else is required, and nothing in it is pre-digested for the reviewer.
- **No pre-judging (S7).** A dispatch never tells a reviewer which findings are acceptable in advance: no "do not flag X", no "at most Minor", no "the plan chose this". Suppressions are category-level only (for example "do not flag test fixtures"), never a named issue; adjudication of a specific finding happens in `findings-synthesizer` and the dispositions block, never in the prompt.
- **Builder output is a claim.** The builder's report, its test summary, and `ops/TEST_RESULTS.md` are unverified until a reviewer reads the code; a stated rationale never lowers severity. When evidence looks truncated, the reviewer re-reads the file at its path and reports the gap; it does not re-run suites (the tester role owns execution).
- **Dispositions are recorded per cycle.** After synthesis, the lead appends `## Review dispositions — Cycle N` to `ops/TASKS.md` with one row per finding: `finding → fixed | dismissed-with-reason | deferred`. Later cycles add rows and never edit earlier ones; `deferred` rows are exported by the wrap-up skill (S14).
- Reviewers start from a lead-controlled directory with the lease diff as input, never from the builder's worktree, so a builder's edits to instruction or config files cannot steer its own review.
