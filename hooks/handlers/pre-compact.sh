#!/usr/bin/env bash
# PreCompact hook: Auto-checkpoint STATE.md before context compaction
# Hook: PreCompact (fires before Claude Code compacts the context window)
# Must complete quickly — compaction waits for this hook.

set -euo pipefail

# Only checkpoint if ops/ directory exists (we're in an active sprint)
[ -d "ops" ] || exit 0

# Only checkpoint if there are active tasks
[ -f "ops/TASKS.md" ] || exit 0

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Check for active tasks (lines containing [ ] or [-])
PENDING=$(grep -c '^\s*- \[ \]' ops/TASKS.md 2>/dev/null || echo "0")
IN_PROGRESS=$(grep -c '^\s*- \[-\]' ops/TASKS.md 2>/dev/null || echo "0")
DONE=$(grep -c '^\s*- \[x\]' ops/TASKS.md 2>/dev/null || echo "0")
BLOCKED=$(grep -c '^\s*- \[B\]' ops/TASKS.md 2>/dev/null || echo "0")

# Read current phase from existing STATE.md if present
CURRENT_PHASE="unknown"
if [ -f "ops/STATE.md" ]; then
  CURRENT_PHASE=$(sed -n 's/^## Current phase: *//p' ops/STATE.md 2>/dev/null || echo "unknown")
fi

# Write minimal checkpoint (must be fast)
cat > "ops/STATE.md" << EOF
# Session state
<!-- Auto-checkpoint before context compaction: $TIMESTAMP -->

## Current phase
$CURRENT_PHASE

## Task status snapshot
- Pending: $PENDING
- In progress: $IN_PROGRESS
- Done: $DONE
- Blocked: $BLOCKED

## Next actions
1. Resume from current phase after context compaction
2. Re-read ops/TASKS.md for task details
3. Re-read ops/MEMORY.md for architectural context
EOF

exit 0
