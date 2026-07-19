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
# `[[:space:]]` not `\s` — BSD grep treats `\s` as a literal 's' (GNU-only).
PENDING=$(grep -c '^[[:space:]]*- \[ \]' ops/TASKS.md 2>/dev/null || true)
IN_PROGRESS=$(grep -c '^[[:space:]]*- \[-\]' ops/TASKS.md 2>/dev/null || true)
DONE=$(grep -c '^[[:space:]]*- \[x\]' ops/TASKS.md 2>/dev/null || true)
BLOCKED=$(grep -c '^[[:space:]]*- \[B\]' ops/TASKS.md 2>/dev/null || true)

# Read current phase from existing STATE.md if present. The canonical format
# (written by this same script below, and by the session-continuity skill) is a
# `## Current phase` heading with the value on the NEXT non-blank line — NOT
# `## Current phase: <value>` inline. Read the first non-blank line after the
# heading, tolerating both shapes, so a mid-sprint compaction preserves the
# real phase instead of overwriting it with "unknown".
CURRENT_PHASE="unknown"
if [ -f "ops/STATE.md" ]; then
  FOUND_PHASE=$(awk '
    /^## Current phase:[[:space:]]*[^[:space:]]/ { sub(/^## Current phase:[[:space:]]*/, ""); print; exit }
    /^## Current phase[[:space:]]*$/ { grab=1; next }
    grab && NF { print; exit }
  ' ops/STATE.md 2>/dev/null || true)
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

# Lease snapshot (KTD-4/U9): with an active ledger, a post-compaction resume
# must reconstruct wave state from ops/leases.toml instead of restarting the
# wave. Single tolerant python3 pass — a malformed ledger reports itself in
# the snapshot rather than breaking the checkpoint (must stay fast).
if [ -f "ops/leases.toml" ]; then
  LEASE_SNAPSHOT=$(python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('- ledger present but no TOML parser available')
        sys.exit(0)
try:
    with open('ops/leases.toml', 'rb') as f:
        data = tomllib.load(f)
except Exception as exc:
    print('- ledger present but unparseable: ' + str(exc))
    sys.exit(0)
leases = data.get('lease', {})
leases = leases if isinstance(leases, dict) else {}
NON_TERMINAL = ('leased', 'building', 'review', 'orphaned', 'requeued')
counts = {}
lines = []
for t in sorted(leases):
    r = leases[t]
    if not isinstance(r, dict):
        continue
    state = str(r.get('state', '?'))
    counts[state] = counts.get(state, 0) + 1
    if state in NON_TERMINAL:
        lines.append('- ' + str(t) + ': ' + str(r.get('builder_cli', '?')) + ' — ' + state)
print('Counts: ' + (', '.join(k + '=' + str(v) for k, v in sorted(counts.items())) if counts else 'none'))
for line in lines:
    print(line)
" 2>/dev/null || true)
  if [ -n "$LEASE_SNAPSHOT" ]; then
    {
      echo ""
      echo "## Lease snapshot"
      printf '%s\n' "$LEASE_SNAPSHOT"
      echo ""
      echo "Reconstruct from ops/leases.toml on resume: lease_heartbeat_check reclaims orphans; never redo merged leases."
    } >> "ops/STATE.md"
  fi
fi

exit 0
