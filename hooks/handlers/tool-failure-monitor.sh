#!/usr/bin/env bash
# tool-failure-monitor.sh — PostToolUse hook that tracks tool failures.
#
# PostToolUse fires on every tool call (success and failure). This handler
# inspects tool_response for an error signal and only counts failures.
# Warns at 5 consecutive or 10 total failures per session.

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/tool-failures.local.md"
mkdir -p .claude

# Parse tool_name and failure signal from hook input.
# Claude Code marks failed tool responses with is_error=true or an error field.
PARSED=$(echo "$HOOK_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    tool = d.get('tool_name', 'unknown')
    resp = d.get('tool_response', {})
    is_err = False
    if isinstance(resp, dict):
        if resp.get('is_error') is True:
            is_err = True
        elif resp.get('error'):
            is_err = True
    print(f'{tool}|{\"1\" if is_err else \"0\"}')
except Exception:
    print('unknown|0')
" 2>/dev/null || echo "unknown|0")

TOOL_NAME="${PARSED%|*}"
FAILED="${PARSED#*|}"

# Non-failure: reset consecutive counter and exit quietly.
if [ "$FAILED" != "1" ]; then
  if [ -f "$STATE_FILE" ]; then
    TEMP_FILE="${STATE_FILE}.tmp.$$"
    sed 's/^consecutive_failures: .*/consecutive_failures: 0/' "$STATE_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$STATE_FILE"
  fi
  exit 0
fi

# Initialize state file if missing
if [ ! -f "$STATE_FILE" ]; then
  cat > "$STATE_FILE" << 'EOF'
---
failure_count: 0
consecutive_failures: 0
---
EOF
fi

# Parse current counts (default to 0 if missing/malformed)
FAILURE_COUNT=$(sed -n 's/^failure_count: \([0-9]*\).*/\1/p' "$STATE_FILE")
FAILURE_COUNT="${FAILURE_COUNT:-0}"
CONSECUTIVE=$(sed -n 's/^consecutive_failures: \([0-9]*\).*/\1/p' "$STATE_FILE")
CONSECUTIVE="${CONSECUTIVE:-0}"

FAILURE_COUNT=$((FAILURE_COUNT + 1))
CONSECUTIVE=$((CONSECUTIVE + 1))

# Atomic state update via python to avoid sed-injection risk
TEMP_FILE="${STATE_FILE}.tmp.$$"
FAILURE_COUNT="$FAILURE_COUNT" CONSECUTIVE="$CONSECUTIVE" python3 -c "
import os
print('---')
print(f'failure_count: {os.environ[\"FAILURE_COUNT\"]}')
print(f'consecutive_failures: {os.environ[\"CONSECUTIVE\"]}')
print('---')
" > "$TEMP_FILE"
mv "$TEMP_FILE" "$STATE_FILE"

# Warn at thresholds
if [ "$CONSECUTIVE" -ge 5 ]; then
  printf '⚠ %s consecutive tool failures (latest: %s). Consider investigating before continuing.\n' "$CONSECUTIVE" "$TOOL_NAME"
elif [ "$FAILURE_COUNT" -ge 10 ]; then
  printf '⚠ %s total tool failures this session (latest: %s). Check .claude/tool-failures.local.md for details.\n' "$FAILURE_COUNT" "$TOOL_NAME"
fi

exit 0
