# Phase 4: synthesize findings

Start only after the dispatch reference's wait block has returned 0, when every reviewer is done. Every lane the cycle dispatched is on the lane list in `$REVIEW_RUN` (the dispatch block, the optional lanes and an rc 40 fallback write the same `ops/REVIEW_*.md` paths), so a lane that left no file, or an empty one, is a gap: the cycle cannot converge on it, and it is never read as "no findings".

`findings-synthesizer` runs detached like the other personas: the first block builds its input and starts it, the second waits for it. Rerun the second while it returns 75. Both run the same under bash and zsh.

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
: "${REVIEW_RUN:?set REVIEW_RUN to the run directory the dispatch block printed}"
CYCLE="${CYCLE:-1}"   # this review cycle's number

# The block first checks for a synthesizer this run started earlier, before it
# changes any file of the run. persona_wait, given at most a second here,
# checks its recorded process (pid, process group, start time). A running one
# is refused and never orphaned, and its input and the gaps it is judged by
# stay as they were. One that ended is stopped, with anything it left
# running, before its record is cleared. persona_stop's own lines stay on
# stderr.
if [ -f "$REVIEW_RUN/synthesis.pid" ]; then
  SRC=0; TRIFORGE_LEAD_WAIT_BUDGET_S=1 persona_wait "$REVIEW_RUN" synthesis >/dev/null 2>&1 || SRC=$?
  [ "$SRC" -ne 75 ] || { echo "review: the findings-synthesizer started earlier for $REVIEW_RUN is still running; run the synthesis wait block, or stop it first (persona_stop $REVIEW_RUN synthesis)" >&2; exit 1; }
  persona_stop "$REVIEW_RUN" synthesis >/dev/null || { echo "review: the earlier findings-synthesizer left processes that could not be stopped (persona_stop rc $?, above); nothing started" >&2; exit 1; }
fi

# The input is data: each expected lane and its state, then the known-issue
# context: the learnings-researcher's report only when it exited 0, a marker
# when it was dispatched and failed. The task, the expected lanes included, is
# the --brief. Relative ops/ paths resolve against the project root. The lanes
# loop also writes the gaps to a file the wait block reads.
SYN_IN="$REVIEW_RUN/synthesis-input.md"
: > "$REVIEW_RUN/gaps"
{
  echo "Expected review lanes this cycle (path: state):"
  while read -r LANE; do
    [ -n "$LANE" ] || continue
    if [ -s "$LANE" ]; then echo "- $LANE: present"; else echo "- $LANE: MISSING OR EMPTY"; printf '%s\n' "$LANE" >> "$REVIEW_RUN/gaps"; fi
  done < "$REVIEW_RUN/lanes"
  if [ -f "$REVIEW_RUN/learnings.pid" ]; then
    LRC=$(cat "$REVIEW_RUN/learnings.rc" 2>/dev/null || echo missing)
    echo
    if [ "$LRC" = 0 ] && [ -s "$REVIEW_RUN/learnings.md" ]; then
      echo "Known-issue context (learnings-researcher):"; cat "$REVIEW_RUN/learnings.md"
    else
      echo "Known-issue context: the learnings-researcher failed (rc $LRC), so there is none this cycle."
    fi
  fi
} > "$SYN_IN"
LANES=$(grep . "$REVIEW_RUN/lanes" | paste -sd, -)
rm -f "$REVIEW_RUN/synthesis.pid" "$REVIEW_RUN/synthesis.rc" "$REVIEW_RUN/synthesis.md"
persona_spawn "$REVIEW_RUN" synthesis findings-synthesizer "$SYN_IN" "$REVIEW_RUN/synthesis.md" --brief "Synthesize review cycle $CYCLE. Read every expected lane file the input lists: $LANES. A lane the input marks MISSING OR EMPTY is a gap, never no findings: list each gap under a ### Gaps heading before the findings, and while any gap exists end the Verdict with Recommendation: FIX_AND_REREVIEW, never PROCEED. Use the known-issue context, when the input carries it, to flag findings that would undo a past fix; say so when it reports the learnings-researcher failed."
echo "review: findings-synthesizer started; run the synthesis wait block next (REVIEW_RUN=$REVIEW_RUN)"
```

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
: "${REVIEW_RUN:?set REVIEW_RUN to the run directory the dispatch block printed}"
persona_wait "$REVIEW_RUN" synthesis || { rc=$?; [ "$rc" -eq 75 ] && echo "review: findings-synthesizer still running; rerun this block"; exit "$rc"; }
R=$(cat "$REVIEW_RUN/synthesis.rc" 2>/dev/null || echo missing)
[ "$R" = 0 ] && [ -s "$REVIEW_RUN/synthesis.md" ] || { echo "review: findings-synthesizer failed rc=$R or wrote nothing — see $REVIEW_RUN" >&2; exit 1; }
cat "$REVIEW_RUN/synthesis.md"
if [ -s "$REVIEW_RUN/gaps" ]; then
  echo "review: NOT converged, lanes missing or empty: $(paste -sd' ' "$REVIEW_RUN/gaps") (re-run each before this cycle can converge)" >&2
  exit 3
fi
```

1. The blocks above run `findings-synthesizer`, in the never-downgrade trio, so it runs as top-tier Claude whichever CLI leads. `$REVIEW_RUN/synthesis.md` is the synthesized report. In the wait block, exit code 75 means rerun it, 1 a failed or empty synthesis, and 3 a report printed for a cycle with gaps. The start block exits 1, starting nothing and changing no file, while a synthesizer it started earlier for the same run is still running.
2. It reads every expected lane (Antigravity + Codex + any optional-tier `REVIEW_OPENCODE`/`KIMI`/`CURSOR.md` + each specialist persona's `ops/REVIEW_<PERSONA>.md`), and the `learnings-researcher` report as known-issue context when there is one.
3. It produces the synthesized report with confidence tiering (HIGH/MEDIUM/LOW) and priority (P1/P2/P3). A `[LOW]` confidence finding is never P1.
4. Apply the `iterative-refinement` skill:
   - Fix P1 (critical) immediately.
   - Fix P2 (important) this cycle.
   - Log P3 (suggestion) for later.
5. Record the cycle's dispositions: append `## Review dispositions — Cycle N` to `ops/TASKS.md` with one row per finding (`finding → fixed | dismissed-with-reason | deferred`); rows are append-only across cycles, and `deferred` rows are exported by the wrap-up skill.
6. Convergence check: no gap (the wait block exited 0 and the report has no `### Gaps` section) AND P1 = 0 AND P2 = 0 → proceed (standard mode). A gap is re-run, never waived.
7. If not converged, re-trigger the review on changed files only, and re-run each gap's lane (max 3 cycles).
8. After 3 cycles without convergence, escalate to the user.
