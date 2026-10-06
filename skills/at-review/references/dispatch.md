# Phase 3: the core lanes (always launched, in the background)

Read `ops/TASKS.md` to determine the review scope (tasks marked `[R]`), then write the review package (the trust rules list its parts) to a file and set `REVIEW_PACKAGE` to its path at the top of the block: it is the specialist personas' input, data under review. The block prints a run directory; set `REVIEW_RUN` to it in the optional-lanes and synthesis blocks, which read the list of lanes this cycle dispatched from it. The block runs the same under bash and zsh, the shell both leads' tools use on macOS. `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it).

## Contents

- The dispatch block (the package check, fresh-cycle guard, the run directory and its lane list, the learnings gate, roster-driven dispatch, the specialist personas and the gated `learnings-researcher`, the waits, promotion of captured output, the structured-verdict fold).
- What rc 40 means.

## The dispatch block

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"

# The review package (trust rules: the collect-snapshot diff, the task rows,
# the ops/CONTRACTS.md slice, the acceptance criteria) is checked before any
# lane starts, so a missing one cannot leave lanes running in the background.
: "${REVIEW_PACKAGE:?write the review package to a file and set REVIEW_PACKAGE to its path first}"
[ -s "$REVIEW_PACKAGE" ] || { echo "review: REVIEW_PACKAGE ($REVIEW_PACKAGE) is missing or empty" >&2; exit 1; }

# Fresh-cycle guard (prevents stale findings surviving a fix cycle). A reviewer
# that returns findings as stdout (headless permission auto-deny) is promoted
# into ops/REVIEW_*.md ONLY when that file is ABSENT (the `[ ! -f ... ]` guards
# below). Without clearing prior-cycle files first, cycle N-1's REVIEW_*.md
# would survive and findings-synthesizer would read it as cycle N's result —
# a green-while-red review that hides newly-introduced findings. Archive (not
# delete) so each prior cycle stays auditable under ops/archive/reviews/.
# find, not a glob: an unmatched glob aborts under zsh.
if [ "$(find ops -maxdepth 1 -name 'REVIEW_*.md' 2>/dev/null | grep -c . || true)" -gt 0 ]; then
  _REV_ARCH="ops/archive/reviews/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$_REV_ARCH"
  find ops -maxdepth 1 -name 'REVIEW_*.md' -exec mv {} "$_REV_ARCH"/ \;
fi

# The run directory, new and owner-only from mktemp (no name another user can
# plant first): the personas' outputs and exit codes, and "lanes", one
# ops/REVIEW_*.md path per lane this cycle dispatches. Synthesis treats a lane
# on that list whose file is missing or empty as a gap, never as no findings.
REVIEW_RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-review.XXXXXX")
printf '%s\n' ops/REVIEW_ANTIGRAVITY.md ops/REVIEW_CODEX.md > "$REVIEW_RUN/lanes"
: > "$REVIEW_RUN/specialists"
echo "review: run directory $REVIEW_RUN (set REVIEW_RUN to it in the later blocks)"

AGY_OUT="$REVIEW_RUN/antigravity.txt"
CODEX_OUT="$REVIEW_RUN/codex.txt"

# Gated learnings-researcher (C4, the learnings gate reference): derive module
# names from the changed paths (full path, basename, stem, parent directory)
# and grep ops/solutions/ for them, with no model call. On at least one match
# the persona starts in the background round below; an empty corpus, or one
# that never mentions these modules, costs nothing.
CHANGED=$( { git diff --name-only HEAD 2>/dev/null || true; git diff --name-only HEAD~1 HEAD 2>/dev/null || true; } | sort -u )
MATCH_LIST="$REVIEW_RUN/learnings-matches.txt"
: > "$MATCH_LIST"
if [ -d ops/solutions ] && [ -n "$CHANGED" ]; then
  while IFS= read -r F; do
    [ -n "$F" ] || continue
    BASE=$(basename "$F"); STEM="${BASE%.*}"; DIR=$(basename "$(dirname "$F")")
    for NEEDLE in "$F" "$BASE" "$STEM" "$DIR"; do
      # skip empty, dot-dir, and very short needles (they would match everything)
      [ -n "$NEEDLE" ] && [ "$NEEDLE" != "." ] && [ "${#NEEDLE}" -ge 4 ] || continue
      grep -rlF -- "$NEEDLE" ops/solutions/ 2>/dev/null >> "$MATCH_LIST" || true
    done
  done <<< "$CHANGED"
  sort -u -o "$MATCH_LIST" "$MATCH_LIST"
fi

# Core review swarm, ROSTER-DRIVEN (R19/AE4): the analyst role (shipped default
# Antigravity, architecture-reviewer) and the reviewer role (shipped default
# Codex, logic_reviewer). Routing through dispatch_role — instead of hardcoding
# invoke_antigravity/invoke_codex — means a roster override such as
# `[roles.reviewer] cli = "opencode"` actually takes effect here (it was
# previously ignored for the core lane). dispatch_role returns 40 when a role
# resolves to the CLAUDE lane (run that reviewer as a sub-agent, below);
# any other nonzero is a real reviewer failure.
dispatch_role analyst "architecture-reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. Write findings to ops/REVIEW_ANTIGRAVITY.md if you can; otherwise return them as your response." \
  "$AGY_OUT" 600 &
AGY_PID=$!

# If scope covers 5+ files, the reviewer CLI may spawn internal subagents.
dispatch_role reviewer "logic_reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. If scope covers 5+ files, spawn separate agents for logic review, security audit, and test coverage analysis — merge all findings into ops/REVIEW_CODEX.md. Otherwise review sequentially and write to ops/REVIEW_CODEX.md." \
  "$CODEX_OUT" 600 &
CODEX_PID=$!

# Specialist personas, launched in the same round. Keep the lines the flags
# select and delete the rest (--full keeps all five; high-ceremony forces
# --full). Each persona's manifest entry sets its tools, model tier and turns;
# security-sentinel is in the never-downgrade trio and runs as top-tier Claude
# whichever CLI leads, or its call fails naming the fix. The input is the
# package, data under review; the task is the --brief. _spec <persona> records
# the persona's lane (its name in capitals, dashes as underscores), runs it in
# the background and leaves its exit code in <LANE>.rc: exit codes in files,
# not a PID list, because zsh does not split an unquoted "$PIDS" into words.
# The arguments are read through "$@" only: Claude Code substitutes a
# numbered positional parameter in a skill's text.
SPEC_BRIEF="Review the change in the input: the [R] tasks' collect-snapshot diff, their task rows, the ops/CONTRACTS.md slice and the acceptance criteria. Report findings in your output format."
_spec() { # _spec <persona>
  local P LANE
  for P in "$@"; do
    LANE=$(printf '%s' "$P" | LC_ALL=C tr 'a-z-' 'A-Z_')
    printf '%s\n' "$LANE" >> "$REVIEW_RUN/specialists"
    printf 'ops/REVIEW_%s.md\n' "$LANE" >> "$REVIEW_RUN/lanes"
    ( R=0; dispatch_persona "$P" "$REVIEW_PACKAGE" "$REVIEW_RUN/$LANE.md" --brief "$SPEC_BRIEF" || R=$?; printf '%s\n' "$R" > "$REVIEW_RUN/$LANE.rc" ) &
  done
}
_spec security-sentinel
_spec performance-oracle
_spec code-simplicity-reviewer
_spec convention-enforcer
_spec architecture-strategist

# The learnings-researcher on a gate match, in the same round: its input is
# the changed paths and the matched entries (data), its task the --brief, and
# its report learnings.md, known-issue context for synthesis rather than a
# review lane, so it stays off the lane list; its exit code goes to
# learnings.rc.
if [ -s "$MATCH_LIST" ]; then
  echo "learnings-researcher: dispatch — ops/solutions/ entries mentioning the changed modules:"
  cat "$MATCH_LIST"
  { echo "Changed paths:"; printf '%s\n' "$CHANGED"; echo; echo "ops/solutions/ entries that mention them:"; cat "$MATCH_LIST"; } > "$REVIEW_RUN/learnings-input.md"
  ( R=0
    dispatch_persona learnings-researcher "$REVIEW_RUN/learnings-input.md" "$REVIEW_RUN/learnings.md" \
      --brief "Known-issue check for this review: read the ops/solutions/ entries the input lists and report which past fixes or gotchas the changed paths must not undo." || R=$?
    printf '%s\n' "$R" > "$REVIEW_RUN/learnings.rc" ) &
else
  echo "learnings-researcher skipped: no ops/solutions/ entry mentions the changed modules"
fi

# Wait for every lane before judging any, so a failure never leaves one running.
# A silent failure (an empty REVIEW_*.md that looks like "no findings") fails
# fast. rc 40 = resolved to the claude lane, handled by a sub-agent below —
# NOT a failure. A failed learnings-researcher is not a review failure.
AGY_RC=0; CODEX_RC=0
wait "$AGY_PID" || AGY_RC=$?
wait "$CODEX_PID" || CODEX_RC=$?
wait || true   # the specialist personas and the learnings-researcher: every background job left
if [ -s "$MATCH_LIST" ]; then
  LRC=$(cat "$REVIEW_RUN/learnings.rc" 2>/dev/null || echo missing)
  [ "$LRC" = 0 ] || echo "learnings-researcher failed rc=$LRC: synthesis runs without known-issue context, and the report says so" >&2
fi
if [ "$AGY_RC" -eq 40 ]; then
  echo "review: analyst role resolved to the claude lane — run the architecture review as a sub-agent (below), not a shell helper" >&2
elif [ "$AGY_RC" -ne 0 ]; then
  echo "review: analyst (architecture) reviewer failed rc=$AGY_RC — see $AGY_OUT" >&2; exit 1
fi
if [ "$CODEX_RC" -eq 40 ]; then
  echo "review: reviewer role resolved to the claude lane — run the logic/security review as a sub-agent (below), not a shell helper" >&2
elif [ "$CODEX_RC" -ne 0 ]; then
  echo "review: reviewer (logic) reviewer failed rc=$CODEX_RC — see $CODEX_OUT" >&2; exit 1
fi
# A specialist persona that fails or writes nothing fails the review; it never
# reads as "no findings". Each output becomes its own ops/REVIEW_<NAME>.md lane.
while read -r N; do
  [ -n "$N" ] || continue
  R=$(cat "$REVIEW_RUN/$N.rc" 2>/dev/null || echo missing)
  [ "$R" = 0 ] || { echo "review: specialist $N failed rc=$R — see $REVIEW_RUN" >&2; exit 1; }
  [ -s "$REVIEW_RUN/$N.md" ] || { echo "review: specialist $N wrote nothing — see $REVIEW_RUN" >&2; exit 1; }
  { echo "<!-- persona output via dispatch_persona -->"; _scrub < "$REVIEW_RUN/$N.md"; } > "ops/REVIEW_$N.md"
done < "$REVIEW_RUN/specialists"

# Headless resilience: agy (and any optional-CLI primary) auto-denies file
# writes in -p mode, so a reviewer may return findings as stdout instead of
# writing ops/. Promote captured output (scrubbed) so the pipeline stays alive
# either way — symmetric for BOTH core lanes now that the reviewer lane can be
# any roster CLI, not just Codex-writes-directly.
# Promotion guard (KTD2/D-032): promote captured agy output only when it is
# non-empty prose AND the JSON-envelope status sidecar written by
# invoke_antigravity reads SUCCESS (a denied/empty run leaves the file empty and
# returns non-zero — nothing is promoted, AE2). A non-agy roster lane writes no
# sidecar and is promoted on non-empty output as before. The header records the
# resolved mode (injection|native|raw) and any denied actions so a degraded run
# is attributable in the promoted file.
if [ ! -f "ops/REVIEW_ANTIGRAVITY.md" ] && [ -s "$AGY_OUT" ] && { [ ! -f "${AGY_OUT}.status" ] || [ "$(cat "${AGY_OUT}.status")" = "SUCCESS" ]; }; then
  {
    echo "<!-- captured from analyst-role output; agent could not write ops/ directly (headless permission auto-deny); mode=$(cat "${AGY_OUT}.mode" 2>/dev/null || echo unknown); denied_actions=$([ -s "${AGY_OUT}.denied" ] && paste -sd, "${AGY_OUT}.denied" || echo none) -->"
    _scrub < "$AGY_OUT"
  } > ops/REVIEW_ANTIGRAVITY.md
fi
if [ ! -f "ops/REVIEW_CODEX.md" ] && [ -s "$CODEX_OUT" ]; then
  { echo "<!-- captured from reviewer-role output; agent could not write ops/ directly (headless permission auto-deny) -->"; _scrub < "$CODEX_OUT"; } > ops/REVIEW_CODEX.md
fi

# Codex structured verdict (R16): invoke_codex writes <out>.verdict.json when the
# reviewer agent declares an output_schema (logic_reviewer does, via
# review-verdict.schema.json). Fold it (scrubbed) into REVIEW_CODEX.md so
# findings-synthesizer actually CONSUMES the structured verdict instead of it
# being produced-but-ignored. Guarded on existence: only the Codex lane emits it,
# so a roster override to a non-Codex reviewer simply skips this.
if [ -f "${CODEX_OUT}.verdict.json" ]; then
  {
    echo ""
    echo "<!-- structured verdict (codex --output-schema, review-verdict.schema.json) -->"
    echo '```json'
    _scrub < "${CODEX_OUT}.verdict.json"
    echo '```'
  } >> ops/REVIEW_CODEX.md 2>/dev/null || true
fi
```

## rc 40

If `AGY_RC` or `CODEX_RC` was 40, that role resolved to the claude lane (its default CLI is absent, or the roster pins `cli = "claude"`) under a lead whose sub-agents enforce their tools; under any other lead `dispatch_role` runs `claude -p` itself and returns its exit code. For the analyst lane run `dispatch_persona architecture-strategist "$REVIEW_PACKAGE" <out> --brief "<the specialist brief>"` and promote `<out>` (scrubbed) into `ops/REVIEW_ANTIGRAVITY.md`; for the reviewer lane run a logic + security review as a sub-agent writing `ops/REVIEW_CODEX.md`, so `findings-synthesizer` sees both alongside the other lanes. The harness notes carry how that sub-agent is spawned.
