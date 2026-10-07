# Phase 3: the review lanes (core lanes and personas, all in one round)

Read `ops/TASKS.md` to determine the review scope (tasks marked `[R]`). Run the dispatch block with `REVIEW_PKG` set to the directory the review-package block printed. Both core lanes get the package in their prompt, whatever CLI holds the role, and each specialist persona reads `$REVIEW_PKG/package.md` as its input. Devin and Grok in a core role run read-class with no shell, the Antigravity reviewer runs no command, and the cost to Codex is the tokens of a diff it would read anyway. Without a package no lane starts. The block prints a run directory; set `REVIEW_RUN` to it in the wait, optional-lanes and synthesis blocks, which read the list of lanes this cycle dispatched from it. Every block here runs the same under bash and zsh, the shell both leads' tools use on macOS. `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it).

The personas run detached (`persona_spawn`): a top-tier persona can outlast one host tool call, which Claude Code stops at 600 s and a Codex lead at 900 s. So the dispatch block starts them and runs the core lanes, and the wait block collects them. Rerun the wait block while it returns 75; once it returns 0 it promotes each specialist's report.

## Contents

- The dispatch block (the package check, fresh-cycle guard, the run directory and its lane list, the learnings gate, the specialist personas and the gated `learnings-researcher` started detached, roster-driven dispatch of the core lanes, promotion of their captured output, the structured-verdict fold).
- The wait block (`persona_wait` in budgeted steps, then the specialists' exit codes and reports).
- What rc 40 means.

## The dispatch block

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"

# The review package (one per cycle, built after the lead's integrity check)
# is checked before any lane starts, so a missing one cannot leave lanes
# running in the background. The core prompts carry package.md inline, the
# personas read it as their input, and the learnings gate reads the changed
# paths from its inventory, so this block runs no git.
REVIEW_PKG=${REVIEW_PKG:-}
if [ -z "$REVIEW_PKG" ] || [ ! -O "$REVIEW_PKG" ] || [ ! -s "$REVIEW_PKG/package.md" ] || [ ! -f "$REVIEW_PKG/inventory.txt" ]; then
  echo "review: no review package (REVIEW_PKG='${REVIEW_PKG}') — run the review-package block first and set REVIEW_PKG to the directory it printed; no lane started" >&2; exit 1
fi
REVIEW_PACKAGE="$REVIEW_PKG/package.md"
RPKG=$(cat "$REVIEW_PACKAGE")

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

# The CLI each role resolves to, for the promotion check: an optional CLI
# filling a core role reports through a typed `Status:` line, Codex and agy
# through their exit code and their answer's last line (and agy's envelope).
ANALYST_CLI=$(resolve_role analyst 2>/dev/null | cut -f1) || ANALYST_CLI=""
REVIEWER_CLI=$(resolve_role reviewer 2>/dev/null | cut -f1) || REVIEWER_CLI=""
# _promote_ok <cli> <out> — whether a lane that exited 0 may become a REVIEW
# file (a nonzero lane stops the block below before any promotion). It reads
# the CLI's final answer, never its tool output: <out>.last when the helper
# writes one (invoke_codex does on every attempt: Codex's <out> is the whole
# session, tool output included), else <out>, which every other helper fills
# with the final answer (agy's envelope response, claude's result, the
# assistant text of a stream, Devin's reply). An empty answer is never
# promoted. A CLI outside the core trio has a Status contract: promoted only
# on DONE or DONE_WITH_CONCERNS (no Status line is "report missing"). A core
# CLI has none, so its answer reports a status only in its last non-empty
# line, and BLOCKED or NEEDS_CONTEXT there stops the promotion; a finding that
# quotes a Status line further up does not.
_promote_ok() {
  local PCLI=${1:-} POUT=${2:-} PANS ST
  PANS=$POUT
  if [ -e "${POUT}.last" ]; then PANS="${POUT}.last"; fi
  if ! grep -q '[^[:space:]]' "$PANS" 2>/dev/null; then
    echo "review: the ${PCLI:-?} lane gave no final answer (${PANS} is empty) — not promoted; read ${POUT}" >&2; return 1
  fi
  if [ "$(cli_field "${PCLI:-none}" tier 2>/dev/null || true)" = core ]; then
    ST=$(awk 'NF { l = $0 } END { print l }' "$PANS" | _lease_parse_status /dev/stdin 2>/dev/null || echo MISSING)
    case "$ST" in
      BLOCKED|NEEDS_CONTEXT) echo "review: the ${PCLI} lane reported Status: ${ST} — not promoted; read ${PANS}" >&2; return 1 ;;
    esac
    return 0
  fi
  ST=$(_lease_parse_status "$PANS" 2>/dev/null || echo MISSING)
  case "$ST" in
    DONE|DONE_WITH_CONCERNS) return 0 ;;
    BLOCKED|NEEDS_CONTEXT) echo "review: the ${PCLI:-?} lane reported Status: ${ST} — not promoted; read ${PANS}" >&2; return 1 ;;
  esac
  echo "review: the ${PCLI:-?} lane's answer has no final 'Status:' line — report missing, not promoted; read ${PANS}" >&2
  return 1
}

# Gated learnings-researcher (C4, the learnings gate reference): derive module
# names from the changed paths (full path, basename, stem, parent directory)
# and grep ops/solutions/ for them, with no model call. The paths are the
# package inventory's (rename sources included, untracked files too). On at
# least one match the persona starts in the background round below; an empty
# corpus, or one that never mentions these modules, costs nothing.
CHANGED=$(cut -f2- "$REVIEW_PKG/inventory.txt" | tr '\t' '\n' | sed '/^$/d' | sort -u)
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

# Specialist personas, started detached before the core lanes. Keep the
# lines the flags select and delete the rest (--full keeps all five;
# high-ceremony forces --full). Each persona's manifest entry sets its tools,
# model tier and turns; security-sentinel is in the never-downgrade trio and
# runs as top-tier Claude whichever CLI leads, or its run fails naming the fix.
# The input is the package, data under review; the task is the --brief, which
# names the package's full diff and inventory for an inline diff that was cut.
# _spec <persona> records the persona's lane (its name in capitals, dashes as
# underscores) and starts it with persona_spawn, which returns at once and
# leaves <LANE>.pid now and <LANE>.rc when the run ends. The arguments are read
# through "$@" only: Claude Code substitutes a numbered positional parameter
# in a skill's text. A persona that cannot start stops the others: nothing is
# left running behind a failed block.
SPEC_BRIEF="Review the change in the input, the review package: each [R] task of ops/TASKS.md with its fields (Accept:, Fails when: and the rest), the changed files and the diff. When the input says the diff was cut, read the full diff in $REVIEW_PKG/full.diff; the complete list of changed files is $REVIEW_PKG/inventory.txt. Report findings in your output format."
# _stop_all stops every persona this cycle started and sets STOPPED to what
# happened. persona_stop's own lines stay on stderr, and its rc 80 (a process
# it could not stop, or ps unreadable) is reported as incomplete cleanup.
_stop_all() {
  STOPPED="no persona had started"
  [ -n "$(find "$REVIEW_RUN" -maxdepth 1 -name '*.pid' 2>/dev/null)" ] || return 0
  STOPPED="the personas were stopped"
  persona_stop "$REVIEW_RUN" >/dev/null || STOPPED="the personas could NOT all be stopped (persona_stop rc $?; its lines above name what is left: check ps)"
}
_spawn_failed() { # _spawn_failed <what> <rc>
  _stop_all
  echo "review: could not start $* — $STOPPED" >&2
  exit 1
}
_spec() { # _spec <persona>
  local P LANE SRC
  for P in "$@"; do
    LANE=$(printf '%s' "$P" | LC_ALL=C tr 'a-z-' 'A-Z_')
    printf '%s\n' "$LANE" >> "$REVIEW_RUN/specialists"
    printf 'ops/REVIEW_%s.md\n' "$LANE" >> "$REVIEW_RUN/lanes"
    SRC=0
    persona_spawn "$REVIEW_RUN" "$LANE" "$P" "$REVIEW_PACKAGE" "$REVIEW_RUN/$LANE.md" --brief "$SPEC_BRIEF" || SRC=$?
    [ "$SRC" -eq 0 ] || _spawn_failed "$P" "rc=$SRC"
  done
}
_spec security-sentinel
_spec performance-oracle
_spec code-simplicity-reviewer
_spec convention-enforcer
_spec architecture-strategist

# The learnings-researcher on a gate match, started the same way under the
# name "learnings": its input is the changed paths and the matched entries
# (data), its task the --brief, and its report learnings.md, known-issue
# context for synthesis rather than a review lane, so it stays off the lane
# list.
if [ -s "$MATCH_LIST" ]; then
  echo "learnings-researcher: dispatch — ops/solutions/ entries mentioning the changed modules:"
  cat "$MATCH_LIST"
  { echo "Changed paths:"; printf '%s\n' "$CHANGED"; echo; echo "ops/solutions/ entries that mention them:"; cat "$MATCH_LIST"; } > "$REVIEW_RUN/learnings-input.md"
  SRC=0
  persona_spawn "$REVIEW_RUN" learnings learnings-researcher "$REVIEW_RUN/learnings-input.md" "$REVIEW_RUN/learnings.md" \
    --brief "Known-issue check for this review: read the ops/solutions/ entries the input lists and report which past fixes or gotchas the changed paths must not undo. The diff under review is $REVIEW_PKG/full.diff." || SRC=$?
  [ "$SRC" -eq 0 ] || _spawn_failed learnings-researcher "rc=$SRC"
else
  echo "learnings-researcher skipped: no ops/solutions/ entry mentions the changed modules"
fi

# Core review swarm, ROSTER-DRIVEN (R19/AE4): the analyst role (shipped default
# Antigravity, architecture-reviewer) and the reviewer role (shipped default
# Codex, logic_reviewer). Routing through dispatch_role — instead of hardcoding
# invoke_antigravity/invoke_codex — means a roster override such as
# `[roles.reviewer] cli = "opencode"` actually takes effect here (it was
# previously ignored for the core lane). dispatch_role returns 40 when a role
# resolves to the CLAUDE lane (see rc 40 below); any other nonzero is a real
# reviewer failure. Each prompt carries the package.
dispatch_role analyst "architecture-reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md; the review package below holds each of those tasks with its fields (Accept:, Fails when: and the rest), the changed files and the diff. Write findings to ops/REVIEW_ANTIGRAVITY.md if you can; otherwise return them as your response.

${RPKG}" \
  "$AGY_OUT" 600 &
AGY_PID=$!

# If scope covers 5+ files, the reviewer CLI may spawn internal subagents.
dispatch_role reviewer "logic_reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md; the review package below holds each of those tasks with its fields (Accept:, Fails when: and the rest), the changed files and the diff. If scope covers 5+ files, spawn separate agents for logic review, security audit, and test coverage analysis — merge all findings into ops/REVIEW_CODEX.md. Otherwise review sequentially and write to ops/REVIEW_CODEX.md.

${RPKG}" \
  "$CODEX_OUT" 600 &
CODEX_PID=$!

# Wait for both core lanes. A silent failure (an empty REVIEW_*.md that looks
# like "no findings") fails fast and stops the personas too. rc 40 = the role
# resolved to the claude lane: the analyst's fallback persona starts detached
# here, collected by the wait block; the reviewer's is a sub-agent (rc 40
# below).
AGY_RC=0; CODEX_RC=0
wait "$AGY_PID" || AGY_RC=$?
wait "$CODEX_PID" || CODEX_RC=$?
if [ "$AGY_RC" -eq 40 ]; then
  echo "review: analyst role resolved to the claude lane — its architecture-strategist persona starts detached; the wait block promotes it" >&2
  SRC=0
  persona_spawn "$REVIEW_RUN" ANALYST_FALLBACK architecture-strategist "$REVIEW_PACKAGE" "$REVIEW_RUN/ANALYST_FALLBACK.md" --brief "$SPEC_BRIEF" || SRC=$?
  [ "$SRC" -eq 0 ] || _spawn_failed "the analyst's architecture-strategist" "rc=$SRC"
elif [ "$AGY_RC" -ne 0 ]; then
  _stop_all
  echo "review: analyst (architecture) reviewer failed rc=$AGY_RC — see $AGY_OUT; $STOPPED" >&2; exit 1
fi
if [ "$CODEX_RC" -eq 40 ]; then
  echo "review: reviewer role resolved to the claude lane — run the logic/security review as a sub-agent (rc 40 below), not a shell helper" >&2
elif [ "$CODEX_RC" -ne 0 ]; then
  _stop_all
  echo "review: reviewer (logic) reviewer failed rc=$CODEX_RC — see $CODEX_OUT; $STOPPED" >&2; exit 1
fi

# Headless resilience: agy (and any optional-CLI primary) auto-denies file
# writes in -p mode, so a reviewer may return findings as stdout instead of
# writing ops/. Promote captured output (scrubbed) so the pipeline stays alive
# either way — symmetric for BOTH core lanes now that the reviewer lane can be
# any roster CLI, not just Codex-writes-directly.
# Promotion guard (KTD2/D-032): promote captured agy output only when it is
# non-empty prose AND the JSON-envelope status sidecar written by
# invoke_antigravity reads SUCCESS (a denied/empty run leaves the file empty and
# returns non-zero — nothing is promoted, AE2). A non-agy roster lane writes no
# sidecar and is promoted on non-empty output that passes _promote_ok (an
# optional CLI's typed report must say DONE or DONE_WITH_CONCERNS). The header records the
# resolved mode (injection|native|raw) and any denied actions so a degraded run
# is attributable in the promoted file.
if [ ! -f "ops/REVIEW_ANTIGRAVITY.md" ] && [ -s "$AGY_OUT" ] && { [ ! -f "${AGY_OUT}.status" ] || [ "$(cat "${AGY_OUT}.status")" = "SUCCESS" ]; } && _promote_ok "$ANALYST_CLI" "$AGY_OUT"; then
  {
    echo "<!-- captured from analyst-role output; agent could not write ops/ directly (headless permission auto-deny); mode=$(cat "${AGY_OUT}.mode" 2>/dev/null || echo unknown); denied_actions=$([ -s "${AGY_OUT}.denied" ] && paste -sd, "${AGY_OUT}.denied" || echo none) -->"
    _scrub < "$AGY_OUT"
  } > ops/REVIEW_ANTIGRAVITY.md
fi
if [ ! -f "ops/REVIEW_CODEX.md" ] && [ -s "$CODEX_OUT" ] && _promote_ok "$REVIEWER_CLI" "$CODEX_OUT"; then
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
echo "review: core lanes done; the personas run detached: run the wait block next (REVIEW_RUN=$REVIEW_RUN)"
```

## The wait block

Run it after the dispatch block, and again while it returns 75. `persona_wait` waits inside the lead's budget (`wait_budget_s` in the registry, less a margin) and never stops a persona. On rc 0 every persona has an exit code, and the block promotes each specialist's report into its own `ops/REVIEW_<LANE>.md` lane. A cycle that started no persona skips the wait.

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
: "${REVIEW_RUN:?set REVIEW_RUN to the run directory the dispatch block printed}"
[ -f "$REVIEW_RUN/specialists" ] || { echo "review: $REVIEW_RUN is not a run directory the dispatch block made (no specialists list)" >&2; exit 64; }
# With no persona started (no specialist kept, no learnings match, no analyst
# fallback), there is nothing to wait for. persona_wait refuses a run
# directory with no runs (64), and every other caller keeps that refusal.
if [ -n "$(find "$REVIEW_RUN" -maxdepth 1 -name '*.pid' 2>/dev/null)" ]; then
  persona_wait "$REVIEW_RUN" || { rc=$?; [ "$rc" -eq 75 ] && echo "review: personas still running; rerun this block"; exit "$rc"; }
else
  echo "review: no personas were started this cycle; nothing to wait for"
fi

# A failed learnings-researcher is not a review failure: synthesis marks the
# missing known-issue context.
if [ -f "$REVIEW_RUN/learnings.pid" ]; then
  LRC=$(cat "$REVIEW_RUN/learnings.rc" 2>/dev/null || echo missing)
  [ "$LRC" = 0 ] || echo "learnings-researcher failed rc=$LRC: synthesis runs without known-issue context, and the report says so" >&2
fi
# The analyst's rc 40 fallback, when the dispatch block started it: promoted
# into ops/REVIEW_ANTIGRAVITY.md on success; on failure the lane stays empty,
# which synthesis reports as a gap.
if [ -f "$REVIEW_RUN/ANALYST_FALLBACK.pid" ]; then
  R=$(cat "$REVIEW_RUN/ANALYST_FALLBACK.rc" 2>/dev/null || echo missing)
  if [ "$R" = 0 ] && [ -s "$REVIEW_RUN/ANALYST_FALLBACK.md" ]; then
    [ -f ops/REVIEW_ANTIGRAVITY.md ] || { echo "<!-- analyst lane on the claude lane: architecture-strategist via persona_spawn -->"; _scrub < "$REVIEW_RUN/ANALYST_FALLBACK.md"; } > ops/REVIEW_ANTIGRAVITY.md
  else
    echo "review: the analyst's architecture-strategist failed rc=$R — ops/REVIEW_ANTIGRAVITY.md stays a gap" >&2
  fi
fi
# A specialist persona that fails or writes nothing fails the review; it never
# reads as "no findings". Each output becomes its own ops/REVIEW_<LANE>.md lane.
while read -r N; do
  [ -n "$N" ] || continue
  R=$(cat "$REVIEW_RUN/$N.rc" 2>/dev/null || echo missing)
  [ "$R" = 0 ] || { echo "review: specialist $N failed rc=$R — see $REVIEW_RUN" >&2; exit 1; }
  [ -s "$REVIEW_RUN/$N.md" ] || { echo "review: specialist $N wrote nothing — see $REVIEW_RUN" >&2; exit 1; }
  { echo "<!-- persona output via dispatch_persona -->"; _scrub < "$REVIEW_RUN/$N.md"; } > "ops/REVIEW_$N.md"
done < "$REVIEW_RUN/specialists"
echo "review: every lane collected (REVIEW_RUN=$REVIEW_RUN)"
```

## rc 40

If `AGY_RC` or `CODEX_RC` was 40, that role resolved to the claude lane (its default CLI is absent, or the roster pins `cli = "claude"`) under a lead whose sub-agents enforce their tools; under any other lead `dispatch_role` runs `claude -p` itself and returns its exit code. For the analyst lane, the dispatch block starts `architecture-strategist` on the package itself (`persona_spawn`, name `ANALYST_FALLBACK`), and the wait block promotes its report (scrubbed) into `ops/REVIEW_ANTIGRAVITY.md`. For the reviewer lane run a logic + security review as a sub-agent against the `[R]` scope, with the review package's path in its prompt (`$REVIEW_PKG/package.md`), writing `ops/REVIEW_CODEX.md`, so `findings-synthesizer` sees both alongside the other lanes. The harness notes carry how that sub-agent is spawned.
