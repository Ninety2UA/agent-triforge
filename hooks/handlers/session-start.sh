#!/usr/bin/env bash
# Session Start — SessionStart hook
# Scans for existing state, pending tasks, and available context.
# Provides orientation when starting a new session.
#
# Hook event: SessionStart
# Configuration: registered in hooks/hooks.json (plugin)

set -euo pipefail

# Ensure .claude/ directory exists for project-local state files
mkdir -p .claude

# Clean stale state files from previous sessions
rm -f .claude/context-monitor.local.md

# Bootstrap ops/ directory if it doesn't exist
if [ ! -d "ops" ]; then
  mkdir -p ops/solutions ops/decisions ops/archive
  # Copy skeleton files from plugin templates if available
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    for f in MEMORY.md CHANGELOG.md AGENTS.md GOALS.md; do
      if [ -f "${CLAUDE_PLUGIN_ROOT}/templates/ops/${f}" ] && [ ! -f "ops/${f}" ]; then
        cp "${CLAUDE_PLUGIN_ROOT}/templates/ops/${f}" "ops/${f}"
      fi
    done
  fi
fi

# Suggest CLAUDE.md template if not present
if [ ! -f "CLAUDE.md" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md" ]; then
  CLAUDE_MD_TIP="\nTip: No CLAUDE.md found. Copy the template: cp \"${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md\" ./CLAUDE.md"
fi

# Check for existing state
HAS_STATE=""
HAS_TASKS=""
HAS_GOALS=""
HAS_AGENTS=""
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

if [ -f "ops/AGENTS.md" ]; then
  HAS_AGENTS="yes"
fi

if [ -f "ops/REVIEW_GEMINI.md" ] || [ -f "ops/REVIEW_CODEX.md" ] || [ -f "ops/TEST_RESULTS.md" ]; then
  HAS_REVIEWS="yes"
fi

SOLUTION_COUNT=$(find ops/solutions -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || echo "0")

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

if [ "$HAS_AGENTS" = "yes" ]; then
  MSG="$MSG\nAgent protocol found (ops/AGENTS.md)."
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

# Append CLAUDE.md tip if set
MSG="$MSG${CLAUDE_MD_TIP:-}"

printf '%b\n' "Multi-agent framework ready.$MSG"
echo ""
echo "Commands: /ship /plan /build /review /test /debug /quick /deep-research /status /pause /resume /wrap /compound"

exit 0
