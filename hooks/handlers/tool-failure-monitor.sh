#!/usr/bin/env bash
# PostToolUseFailure hook: Track tool failures, warn on accumulation
# Hook: PostToolUseFailure (fires when any tool call fails)

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/tool-failures.local.md"
mkdir -p .claude

# Extract tool name from hook input
TOOL_NAME=$(echo "$HOOK_INPUT" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    print(data.get('tool_name', 'unknown'))
except:
    print('unknown')
" 2>/dev/null)

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" << 'EOF'
---
failure_count: 0
consecutive_failures: 0
---
EOF
fi

# Parse current counts
FAILURE_COUNT=$(sed -n 's/^failure_count: \([0-9]*\).*/\1/p' "$STATE_FILE")
CONSECUTIVE=$(sed -n 's/^consecutive_failures: \([0-9]*\).*/\1/p' "$STATE_FILE")
FAILURE_COUNT=$((FAILURE_COUNT + 1))
CONSECUTIVE=$((CONSECUTIVE + 1))

# Update state
TEMP_FILE="${STATE_FILE}.tmp.$$"
sed "s/^failure_count: .*/failure_count: $FAILURE_COUNT/" "$STATE_FILE" | \
  sed "s/^consecutive_failures: .*/consecutive_failures: $CONSECUTIVE/" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Warn at thresholds
if [ "$CONSECUTIVE" -ge 5 ]; then
  printf '⚠ %s consecutive tool failures (latest: %s). Consider investigating before continuing.\n' "$CONSECUTIVE" "$TOOL_NAME"
elif [ "$FAILURE_COUNT" -ge 10 ]; then
  printf '⚠ %s total tool failures this session (latest: %s). Check .claude/tool-failures.local.md for details.\n' "$FAILURE_COUNT" "$TOOL_NAME"
fi

exit 0
