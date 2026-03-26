#!/bin/bash
# Session Start — SessionStart hook
# Scans for existing state, pending tasks, and available context.
# Provides orientation when starting a new session.
#
# Hook event: SessionStart
# Configuration: add to .claude/settings.json hooks.SessionStart

# Check for existing state
HAS_STATE=""
HAS_TASKS=""
HAS_GOALS=""
HAS_REVIEWS=""
BLOCKED_COUNT=0
PENDING_COUNT=0
IN_PROGRESS_COUNT=0
SOLUTION_COUNT=0

if [ -f "ops/STATE.md" ]; then
  HAS_STATE="yes"
fi

if [ -f "ops/TASKS.md" ]; then
  HAS_TASKS="yes"
  BLOCKED_COUNT=$(grep -c '\[B\]' ops/TASKS.md 2>/dev/null || echo "0")
  PENDING_COUNT=$(grep -c '\[ \]' ops/TASKS.md 2>/dev/null || echo "0")
  IN_PROGRESS_COUNT=$(grep -c '\[-\]' ops/TASKS.md 2>/dev/null || echo "0")
fi

if [ -f "ops/GOALS.md" ]; then
  HAS_GOALS="yes"
fi

if [ -f "ops/REVIEW_GEMINI.md" ] || [ -f "ops/REVIEW_CODEX.md" ] || [ -f "ops/TEST_RESULTS.md" ]; then
  HAS_REVIEWS="yes"
fi

SOLUTION_COUNT=$(find ops/solutions -name "*.md" 2>/dev/null | wc -l | tr -d ' ')

# Build orientation message
MSG=""

if [ "$HAS_STATE" = "yes" ]; then
  MSG="$MSG\nPrevious session state found (ops/STATE.md). Use /resume to continue."
fi

if [ "$HAS_TASKS" = "yes" ]; then
  MSG="$MSG\nActive sprint found (ops/TASKS.md): $PENDING_COUNT pending, $IN_PROGRESS_COUNT in progress, $BLOCKED_COUNT blocked."
fi

if [ "$HAS_GOALS" = "yes" ]; then
  MSG="$MSG\nProject goals found (ops/GOALS.md)."
fi

if [ "$HAS_REVIEWS" = "yes" ]; then
  MSG="$MSG\nUnprocessed review files found. Consider running /review to process them."
fi

if [ "$SOLUTION_COUNT" -gt "0" ]; then
  MSG="$MSG\nInstitutional knowledge: $SOLUTION_COUNT documented solutions in ops/solutions/."
fi

if [ -z "$MSG" ]; then
  MSG="\nNo active sprint. Use /plan <goal> to start or /ship <goal> for full autonomous mode."
fi

echo -e "Multi-agent framework ready.$MSG"
echo ""
echo "Commands: /ship /plan /build /review /test /debug /quick /deep-research /status /pause /resume /wrap /compound"

exit 0
