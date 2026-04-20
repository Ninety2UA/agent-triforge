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

# Check for active tasks (lines containing [ ] or [-]).
# `grep -c` already prints 0 on zero matches; `|| true` stops set -e without
# duplicating output. Using `|| echo "0"` would produce "0\n0" on zero matches.
PENDING=$(grep -c '^\s*- \[ \]' ops/TASKS.md 2>/dev/null || true)
IN_PROGRESS=$(grep -c '^\s*- \[-\]' ops/TASKS.md 2>/dev/null || true)
DONE=$(grep -c '^\s*- \[x\]' ops/TASKS.md 2>/dev/null || true)
BLOCKED=$(grep -c '^\s*- \[B\]' ops/TASKS.md 2>/dev/null || true)

# Read current phase from existing STATE.md if present.
# `sed -n` with no match exits 0 (not an error) so `|| echo "unknown"` would
# never fire — check for empty output separately and fall back explicitly.
CURRENT_PHASE="unknown"
if [ -f "ops/STATE.md" ]; then
  FOUND_PHASE=$(sed -n 's/^## Current phase: *//p' ops/STATE.md 2>/dev/null | head -n 1 || true)
  [ -n "$FOUND_PHASE" ] && CURRENT_PHASE="$FOUND_PHASE"
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
