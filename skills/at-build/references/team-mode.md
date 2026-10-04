# Agent-team mode (5 or more tasks, cross-dependent work, or `--team`)

1. Start the `team-lead` persona. Its manifest class is `agent-team`: under a lead whose `agent_teams` capability is set (Claude Code), the harness spawns it as a teammate, the one native spawn left and labeled unenforced (the Claude reference); under any other lead the lead takes the role itself (the Codex reference).
2. Team-lead reads `ops/TASKS.md` and groups the tasks into waves.
3. Team-lead assigns each task to a builder resolved from `ops/roster.toml`, dispatched under a lease, and pins a non-author reviewer per task.
4. Builders run confined in worktrees; the team-lead injects context and does all merges on the main tree (KTD-3).
5. Teammates can dispatch the external lanes for specific reviews or tests (replace `<scope>` with actual paths):

   ```bash
   set -euo pipefail
   ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"

   AGY_OUT="${TMPDIR:-/tmp}/antigravity_build_$$_$(date +%s).txt"
   CODEX_OUT="${TMPDIR:-/tmp}/codex_build_$$_$(date +%s).txt"

   # Architecture review for build scope
   invoke_antigravity "architecture-reviewer" \
     "Review <scope> for architecture. Write to ops/REVIEW_ANTIGRAVITY.md if you can; otherwise return findings as your response." \
     "$AGY_OUT" 600 &
   AGY_PID=$!

   # Test writing for build scope
   invoke_codex "test_writer" \
     "Write tests for <scope>." \
     "$CODEX_OUT" 600 &
   CODEX_PID=$!

   # Per-PID wait so a silent failure doesn't leave downstream agents staring at
   # an empty file and calling it "no findings".
   AGY_RC=0; CODEX_RC=0
   wait $AGY_PID || AGY_RC=$?
   wait $CODEX_PID  || CODEX_RC=$?
   if [ $AGY_RC -ne 0 ] || [ $CODEX_RC -ne 0 ]; then
     echo "build: helper failed — antigravity=$AGY_RC codex=$CODEX_RC" >&2
     echo "build: last stderr in $AGY_OUT / $CODEX_OUT" >&2
     exit 1
   fi

   # Promotion guard (KTD2/D-032): promote captured agy output only when it is
   # non-empty prose AND the JSON-envelope status sidecar written by
   # invoke_antigravity reads SUCCESS (a denied/empty run leaves the file empty and
   # returns non-zero — nothing is promoted, AE2). A non-agy roster lane writes no
   # sidecar and is promoted on non-empty output as before. The header records the
   # resolved mode (injection|native|raw) and any denied actions so a degraded run
   # is attributable in the promoted file.
   if [ ! -f "ops/REVIEW_ANTIGRAVITY.md" ] && [ -s "$AGY_OUT" ] && { [ ! -f "${AGY_OUT}.status" ] || [ "$(cat "${AGY_OUT}.status")" = "SUCCESS" ]; }; then
     {
       echo "<!-- captured from architecture-reviewer output; agent could not write ops/ directly (headless permission auto-deny); mode=$(cat "${AGY_OUT}.mode" 2>/dev/null || echo unknown); denied_actions=$([ -s "${AGY_OUT}.denied" ] && paste -sd, "${AGY_OUT}.denied" || echo none) -->"
       _scrub < "$AGY_OUT"
     } > ops/REVIEW_ANTIGRAVITY.md
   fi
   ```

   `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it); a teammate working elsewhere uses that same path, never one relative to its working directory.
6. Quality gates: tests and lint must pass, and a pinned non-author reviewer must approve, before a task merges (self-review refused, AE3).
7. The `integration-verifier` persona runs between waves against the integration branch (`--at ref:<integration branch>`); the lead promotes to the main branch honoring the `[promotion]` gate.
