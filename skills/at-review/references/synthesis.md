# Phase 4: synthesize findings

Wait for all reviewers to complete first. Every lane the cycle dispatched is on the lane list in `$REVIEW_RUN` (the dispatch block, the optional lanes and an rc 40 fallback write the same `ops/REVIEW_*.md` paths), so a lane that left no file, or an empty one, is a gap: the cycle cannot converge on it, and it is never read as "no findings".

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
: "${REVIEW_RUN:?set REVIEW_RUN to the run directory the dispatch block printed}"
CYCLE="${CYCLE:-1}"   # this review cycle's number

# The input is data: each expected lane and its state, then the known-issue
# context when the gate dispatched it. The task, the expected lanes included,
# is the --brief. Relative ops/ paths resolve against the project root.
SYN_IN="$REVIEW_RUN/synthesis-input.md"
GAPS=""
{
  echo "Expected review lanes this cycle (path: state):"
  while read -r LANE; do
    [ -n "$LANE" ] || continue
    if [ -s "$LANE" ]; then echo "- $LANE: present"; else echo "- $LANE: MISSING OR EMPTY"; fi
  done < "$REVIEW_RUN/lanes"
  if [ -s "$REVIEW_RUN/learnings.md" ]; then
    echo; echo "Known-issue context (learnings-researcher):"; cat "$REVIEW_RUN/learnings.md"
  fi
} > "$SYN_IN"
while read -r LANE; do
  [ -n "$LANE" ] || continue
  [ -s "$LANE" ] || GAPS="$GAPS $LANE"
done < "$REVIEW_RUN/lanes"
LANES=$(grep . "$REVIEW_RUN/lanes" | paste -sd, -)

dispatch_persona findings-synthesizer "$SYN_IN" "$REVIEW_RUN/synthesis.md" --brief "Synthesize review cycle $CYCLE. Read every expected lane file the input lists: $LANES. A lane the input marks MISSING OR EMPTY is a gap, never no findings: list each gap under a ### Gaps heading before the findings, and while any gap exists end the Verdict with Recommendation: FIX_AND_REREVIEW, never PROCEED. Use the known-issue context, when the input carries it, to flag findings that would undo a past fix."
cat "$REVIEW_RUN/synthesis.md"
if [ -n "$GAPS" ]; then
  echo "review: NOT converged, lanes missing or empty:$GAPS (re-run each before this cycle can converge)" >&2
  exit 3
fi
```

1. The block above runs `findings-synthesizer`, in the never-downgrade trio, so it runs as top-tier Claude whichever CLI leads. `$REVIEW_RUN/synthesis.md` is the synthesized report; a persona failure fails the step under `set -e`, and exit code 3 means the report is printed but the cycle has gaps.
2. It reads every expected lane (Antigravity + Codex + any optional-tier `REVIEW_OPENCODE`/`KIMI`/`CURSOR.md` + each specialist persona's `ops/REVIEW_<PERSONA>.md`), and the `learnings-researcher` report as known-issue context when there is one.
3. It produces the synthesized report with confidence tiering (HIGH/MEDIUM/LOW) and priority (P1/P2/P3). A `[LOW]` confidence finding is never P1.
4. Apply the `iterative-refinement` skill:
   - Fix P1 (critical) immediately.
   - Fix P2 (important) this cycle.
   - Log P3 (suggestion) for later.
5. Record the cycle's dispositions: append `## Review dispositions — Cycle N` to `ops/TASKS.md` with one row per finding (`finding → fixed | dismissed-with-reason | deferred`); rows are append-only across cycles, and `deferred` rows are exported by the wrap-up skill.
6. Convergence check: no gap (the block exited 0 and the report has no `### Gaps` section) AND P1 = 0 AND P2 = 0 → proceed (standard mode). A gap is re-run, never waived.
7. If not converged, re-trigger the review on changed files only, and re-run each gap's lane (max 3 cycles).
8. After 3 cycles without convergence, escalate to the user.
