# Phase 3: the core lanes (always launched, in the background)

Read `ops/TASKS.md` to determine the review scope (tasks marked `[R]`). `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it).

## Contents

- The dispatch block (fresh-cycle guard, roster-driven dispatch, per-PID waits, promotion of captured output, the structured-verdict fold).
- What rc 40 means.

## The dispatch block

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"

# Fresh-cycle guard (prevents stale findings surviving a fix cycle). A reviewer
# that returns findings as stdout (headless permission auto-deny) is promoted
# into ops/REVIEW_*.md ONLY when that file is ABSENT (the `[ ! -f ... ]` guards
# below). Without clearing prior-cycle files first, cycle N-1's REVIEW_*.md
# would survive and findings-synthesizer would read it as cycle N's result —
# a green-while-red review that hides newly-introduced findings. Archive (not
# delete) so each prior cycle stays auditable under ops/archive/reviews/.
if ls ops/REVIEW_*.md >/dev/null 2>&1; then
  _REV_ARCH="ops/archive/reviews/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$_REV_ARCH" && mv ops/REVIEW_*.md "$_REV_ARCH"/ 2>/dev/null || true
fi

AGY_OUT="${TMPDIR:-/tmp}/antigravity_review_$$_$(date +%s).txt"
CODEX_OUT="${TMPDIR:-/tmp}/codex_review_$$_$(date +%s).txt"

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

# Wait per-PID so a silent failure (which would leave REVIEW_*.md empty and look
# like "no findings") fails fast. rc 40 = resolved to the claude lane, handled
# by a sub-agent below — NOT a failure.
AGY_RC=0; CODEX_RC=0
wait $AGY_PID || AGY_RC=$?
wait $CODEX_PID  || CODEX_RC=$?
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

If `AGY_RC` or `CODEX_RC` was 40, that role resolved to the claude lane (its default CLI is absent, or the roster pins `cli = "claude"`). Run that reviewer as a sub-agent against the `[R]` scope (`architecture-strategist` for the analyst lane; a logic + security review for the reviewer lane), writing findings to `ops/REVIEW_ANTIGRAVITY.md` or `ops/REVIEW_CODEX.md` respectively, so `findings-synthesizer` sees them alongside the other lanes. The harness notes carry how a sub-agent is spawned under each lead.
