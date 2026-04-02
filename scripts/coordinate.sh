#!/bin/bash
# Coordinate — Outer loop script for context exhaustion recovery
# Spawns fresh Claude Code sessions when context is exhausted.
# Each iteration gets a clean context window.
# Progress tracked in ops/STATE.md.
#
# Usage:
#   ./scripts/coordinate.sh "Build the authentication module"
#   ./scripts/coordinate.sh "Build auth" --max 5
#   ./scripts/coordinate.sh "Build auth" --convergence deep
#
# Flags:
#   --max N          Maximum iterations (default: 5)
#   --convergence    Convergence mode: fast|standard|deep (default: standard)
#   --team           Use agent team mode for Phase 2

set -euo pipefail

# Parse arguments
GOAL=""
MAX_ITERATIONS=5
CONVERGENCE="standard"
USE_TEAM=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --max)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --convergence)
      CONVERGENCE="$2"
      shift 2
      ;;
    --team)
      USE_TEAM="--team"
      shift
      ;;
    *)
      if [ -z "$GOAL" ]; then
        GOAL="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$GOAL" ]; then
  echo "Usage: ./scripts/coordinate.sh \"goal description\" [--max N] [--convergence fast|standard|deep] [--team]"
  exit 1
fi

# --- Notification (optional, env-var-gated) ---
notify() {
  local title="$1" body="$2"
  if [ -n "${NOTIFY_WEBHOOK_URL:-}" ]; then
    curl -s -X POST "$NOTIFY_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"$title: $body\"}" > /dev/null 2>&1 || true
  fi
  if command -v osascript &>/dev/null; then
    osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "$title" "$body" 2>/dev/null || true
  fi
}

PROGRESS_FILE="ops/STATE.md"
ITERATION=0
DONE=false

echo "=== Multi-Agent Coordinate Loop ==="
echo "Goal: $GOAL"
echo "Max iterations: $MAX_ITERATIONS"
echo "Convergence: $CONVERGENCE"
echo ""

while [ "$ITERATION" -lt "$MAX_ITERATIONS" ] && [ "$DONE" = "false" ]; do
  ITERATION=$((ITERATION + 1))
  echo "--- Iteration $ITERATION/$MAX_ITERATIONS ---"

  # Build the prompt for Claude Code
  PROMPT="You are continuing a multi-agent sprint.

GOAL: $GOAL
CONVERGENCE MODE: $CONVERGENCE
ITERATION: $ITERATION of $MAX_ITERATIONS
$USE_TEAM

FIRST: Read ops/STATE.md to understand where the previous session left off.
If this is iteration 1 and no STATE.md exists, start from Phase 0.

Follow the multi-agent framework (docs/multi-agent-framework.md):
- Phase 0: Codebase analysis (Gemini) — skip if STATE.md shows Phase 0 complete
- Phase 1: Planning — skip if TASKS.md already exists for this goal
- Phase 1.5: Plan validation — run plan-checker agent
- Phase 2: Build — use wave orchestration for complex builds
- Phase 3: Parallel review — Gemini + Codex + Claude subagent reviewers
- Phase 4: Process reviews — use findings-synthesizer agent
- Phase 5: Test — Codex writes and runs tests
- Phase 6: Wrap up — compound knowledge, update STATE.md

Before exiting, ALWAYS update ops/STATE.md with current progress.
When ALL work is verified complete, emit: <promise>DONE</promise>"

  # Run Claude Code with the prompt
  OUTPUT=$(claude --print "$PROMPT" 2>&1) || true

  # Check for completion signal
  if echo "$OUTPUT" | grep -q '<promise>DONE</promise>'; then
    DONE=true
    notify "Multi-Agent Framework" "Sprint complete — converged in $ITERATION iterations"
    echo ""
    echo "=== Sprint complete at iteration $ITERATION ==="
  else
    echo "Session ended without completion signal. Spawning fresh session..."
    echo ""
  fi
done

if [ "$DONE" = "false" ]; then
  echo ""
  echo "=== Max iterations ($MAX_ITERATIONS) reached without completion ==="
  notify "Multi-Agent Framework" "Sprint did NOT converge after $MAX_ITERATIONS iterations"
  echo "Check ops/STATE.md for current progress."
  echo "Check ops/TASKS.md for remaining tasks."
  echo "Run again to continue, or review manually."
fi
