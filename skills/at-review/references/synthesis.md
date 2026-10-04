# Phase 4: synthesize findings

Wait for all reviewers to complete first.

1. Write a brief file naming the cycle number and, when the gate dispatched it, the `learnings-researcher` output file, then run `dispatch_persona findings-synthesizer <brief file> <out>` with `<out>` outside `ops/REVIEW_*`; `<out>` is the synthesized report. The synthesizer is in the never-downgrade trio and runs as top-tier Claude whichever CLI leads.
2. It reads ALL `ops/REVIEW_*.md` lanes (Antigravity + Codex + any optional-tier `REVIEW_OPENCODE`/`KIMI`/`CURSOR.md` + each specialist persona's `ops/REVIEW_<PERSONA>.md`), and the `learnings-researcher` output as known-issue context when there is one.
3. It produces the synthesized report with confidence tiering (HIGH/MEDIUM/LOW) and priority (P1/P2/P3). A `[LOW]` confidence finding is never P1.
4. Apply the `iterative-refinement` skill:
   - Fix P1 (critical) immediately.
   - Fix P2 (important) this cycle.
   - Log P3 (suggestion) for later.
5. Record the cycle's dispositions: append `## Review dispositions — Cycle N` to `ops/TASKS.md` with one row per finding (`finding → fixed | dismissed-with-reason | deferred`); rows are append-only across cycles, and `deferred` rows are exported by the wrap-up skill.
6. Convergence check: P1 = 0 AND P2 = 0 → proceed (standard mode).
7. If not converged, re-trigger the review on changed files only (max 3 cycles).
8. After 3 cycles without convergence, escalate to the user.
