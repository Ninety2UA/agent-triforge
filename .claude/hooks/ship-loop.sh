#!/bin/bash
# Ship Loop — Stop hook (inner loop)
# Prevents premature session exit during active sprints.
# Re-feeds the task prompt up to 5 iterations.
# Only blocks the session that started the loop.
#
# Hook event: Stop
# Configuration: add to .claude/settings.json hooks.Stop

STATE_FILE=".claude/ship-loop.local.md"

# If no state file, sprint is not active — allow exit
if [ ! -f "$STATE_FILE" ]; then
  exit 0
fi

# Read iteration count from state file (POSIX-compatible — no grep -P on BSD/macOS)
ITERATION=$(sed -n 's/^iteration: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
ITERATION="${ITERATION:-0}"
MAX_ITERATIONS=$(sed -n 's/^max_iterations: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
MAX_ITERATIONS="${MAX_ITERATIONS:-5}"
# Check for completion signal in recent assistant output
if echo "$CLAUDE_STOP_ASSISTANT_MESSAGE" 2>/dev/null | grep -q '<promise>DONE</promise>'; then
  # Sprint complete — clean up and allow exit
  rm -f "$STATE_FILE"
  exit 0
fi

# Check iteration limit
if [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
  echo "Ship loop: max iterations ($MAX_ITERATIONS) reached. Allowing exit. Sprint may be incomplete." >&2
  rm -f "$STATE_FILE"
  exit 0
fi

# Increment iteration and update state file
NEW_ITERATION=$((ITERATION + 1))
sed -i.bak "s/iteration: $ITERATION/iteration: $NEW_ITERATION/" "$STATE_FILE"
rm -f "${STATE_FILE}.bak"

# Block exit — re-inject prompt
echo "Ship loop: iteration $NEW_ITERATION/$MAX_ITERATIONS — sprint not complete yet."
echo ""
echo "Continue working on the sprint. Check ops/TASKS.md for remaining tasks."
echo "When ALL work is verified complete, emit: <promise>DONE</promise>"

# Exit code 2 = block exit and send feedback
exit 2
