#!/bin/bash
# Context Monitor — PostToolUse hook
# Detects analysis paralysis (excessive read-only ops without producing code)
# and warns when approaching context limits.
#
# Hook event: PostToolUse
# Configuration: add to .claude/settings.json hooks.PostToolUse

STATE_FILE=".claude/context-monitor.local.md"

# Read hook input from stdin (Claude Code delivers PostToolUse data as JSON on stdin)
HOOK_INPUT=$(cat)
TOOL_NAME=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_name','unknown'))" 2>/dev/null || echo "unknown")

# Initialize state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" << 'EOF'
---
total_calls: 0
consecutive_reads: 0
last_write_at: 0
---
EOF
fi

# Read current state (POSIX-compatible — no grep -P on BSD/macOS)
TOTAL=$(sed -n 's/^total_calls: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
TOTAL="${TOTAL:-0}"
READS=$(sed -n 's/^consecutive_reads: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
READS="${READS:-0}"
LAST_WRITE=$(sed -n 's/^last_write_at: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
LAST_WRITE="${LAST_WRITE:-0}"

# Increment total
NEW_TOTAL=$((TOTAL + 1))

# Classify tool as read-only or action/write
case "$TOOL_NAME" in
  Read|Grep|Glob|LS|WebFetch|WebSearch|TaskList|TaskGet|NotebookRead)
    NEW_READS=$((READS + 1))
    ;;
  Write|Edit|Bash|NotebookEdit|Agent|Skill|TaskCreate|TaskUpdate|SendMessage|CronCreate|CronDelete|TeamCreate|TeamDelete|RemoteTrigger)
    NEW_READS=0
    LAST_WRITE=$NEW_TOTAL
    ;;
  *)
    # Unknown tools are treated as actions (reset counter) to avoid false positives
    NEW_READS=0
    LAST_WRITE=$NEW_TOTAL
    ;;
esac

# Update state file
cat > "$STATE_FILE" << EOF
---
total_calls: $NEW_TOTAL
consecutive_reads: $NEW_READS
last_write_at: $LAST_WRITE
---
EOF

# Analysis paralysis detection: 8+ consecutive read-only ops
if [ "$NEW_READS" -ge 8 ]; then
  echo "Context monitor: $NEW_READS consecutive read-only operations without writing code."
  echo "Consider: Are you stuck? Either write code, report a blocker, or spawn a subagent."
  echo "If researching intentionally, continue — but be aware of context usage."
fi

# Context usage warnings
if [ "$NEW_TOTAL" -ge 200 ]; then
  echo "Context monitor: CRITICAL — $NEW_TOTAL tool calls. Context window is likely near capacity."
  echo "Strongly consider: save state (ops/STATE.md), wrap session, spawn subagents for remaining work."
elif [ "$NEW_TOTAL" -ge 150 ]; then
  echo "Context monitor: WARNING — $NEW_TOTAL tool calls. Consider spawning subagents for intensive operations."
fi

# Always exit 0 — this hook is advisory only, never blocks
exit 0
