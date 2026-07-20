#!/usr/bin/env bash
# Coordinate — Outer loop script for context exhaustion recovery
# Spawns fresh Claude Code sessions when context is exhausted.
# Each iteration gets a clean context window.
# Progress tracked in ops/STATE.md.
#
# Completion contract (native /goal gating, probe CC-03):
#   - Each composed prompt LEADS with a `/goal` line carrying the completion
#     checklist, so Claude Code hard-gates the session natively.
#   - The session creates the runtime marker ops/.sprint-complete ONLY after
#     the verification checklist passes (Phase 6 wrap).
#   - This loop clears the marker at start and detects completion solely by
#     the file's existence — headless-observable, no output parsing.
#
# Usage:
#   ./scripts/coordinate.sh "Build the authentication module"
#   ./scripts/coordinate.sh "Build auth" --max 5
#   ./scripts/coordinate.sh "Build auth" --convergence deep
#   ./scripts/coordinate.sh "Build auth" --dry-run
#
# Flags:
#   --max N          Maximum iterations (default: 5)
#   --convergence    Convergence mode: fast|standard|deep (default: standard)
#   --team           Use agent team mode for Phase 2
#   --dry-run        Print the composed session prompt and exit without
#                    invoking claude (asserted by probe SELF-02)

set -euo pipefail

# Parse arguments
GOAL=""
MAX_ITERATIONS=5
CONVERGENCE="standard"
USE_TEAM=""
DRY_RUN=false

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
    --dry-run)
      DRY_RUN=true
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
  echo "Usage: ./scripts/coordinate.sh \"goal description\" [--max N] [--convergence fast|standard|deep] [--team] [--dry-run]"
  exit 1
fi

SENTINEL="ops/.sprint-complete"

# Lease-ledger resume (KTD-4/U9): when ops/leases.toml still holds
# non-terminal leases, the fresh session must reconstruct the wave from the
# ledger instead of restarting it. Prints the extra prompt paragraph, or
# nothing. (probe-capabilities.sh SELF-02 asserts the /goal line + this resume
# paragraph appear in --dry-run output — that probe is the verification hook.)
lease_resume_paragraph() {
  [ -f "ops/leases.toml" ] || return 0
  local COUNTS ACTIVE ATTENTION
  # Two counts: live (mid-flight work to reconstruct) and attention (terminal
  # failed/escalated rows a fresh session must still resolve, not silently drop
  # — they are NOT "live" reclaimable work, so they get their own surface).
  COUNTS=$(python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('0 0')
        sys.exit(0)
try:
    with open('ops/leases.toml', 'rb') as f:
        data = tomllib.load(f)
    leases = data.get('lease', {})
    rows = [v for v in (leases.values() if isinstance(leases, dict) else []) if isinstance(v, dict)]
    live = ('leased', 'building', 'review', 'orphaned', 'requeued')
    attention = ('failed', 'escalated')
    print(sum(1 for v in rows if v.get('state') in live),
          sum(1 for v in rows if v.get('state') in attention))
except Exception:
    print('0 0')
" 2>/dev/null || echo '0 0')
  ACTIVE=$(printf '%s' "$COUNTS" | awk '{print $1+0}')
  ATTENTION=$(printf '%s' "$COUNTS" | awk '{print $2+0}')
  if [ "${ACTIVE:-0}" -gt 0 ] 2>/dev/null; then
    printf '%s' "A lease ledger exists (ops/leases.toml). FIRST reconstruct wave state from it — reclaim orphans (lease_heartbeat_check), keep merged work, requeue or finish open leases — instead of restarting the wave from scratch."
  fi
  if [ "${ATTENTION:-0}" -gt 0 ] 2>/dev/null; then
    [ "${ACTIVE:-0}" -gt 0 ] && printf ' '
    printf '%s' "${ATTENTION} lease(s) are in a failed/escalated state needing a decision — surface them (lease_status) and resolve or abandon them before the sprint is considered done; do NOT silently drop them."
  fi
  return 0
}

# Compose the per-iteration session prompt. Sets $PROMPT.
# $1 = iteration number.
# The leading /goal line makes Claude Code hard-gate the session on the
# completion checklist (a slash command can only be user-typed or the first
# line of a -p prompt — which is exactly what this is).
compose_prompt() {
  local LEASE_RESUME
  LEASE_RESUME=$(lease_resume_paragraph)
  PROMPT="/goal Sprint complete ONLY when ALL of: (1) every framework phase for the goal is done or explicitly skipped with a stated reason; (2) the verification-before-completion checklist passes with evidence; (3) ops/STATE.md is written for session handoff; (4) temporary review files are archived to ops/archive/; (5) the runtime marker ops/.sprint-complete exists — created LAST, only after conditions 1-4 hold.

You are continuing a multi-agent sprint.

GOAL: $GOAL
CONVERGENCE MODE: $CONVERGENCE
ITERATION: $1 of $MAX_ITERATIONS
$USE_TEAM

FIRST: Read ops/STATE.md to understand where the previous session left off.
If this is iteration 1 and no STATE.md exists, start from Phase 0.${LEASE_RESUME:+

$LEASE_RESUME}

Follow the Agent Triforge framework (docs/agent-triforge.md):
- Phase 0: Codebase analysis (Antigravity) — skip if STATE.md shows Phase 0 complete
- Phase 1: Planning — skip if TASKS.md already exists for this goal
- Phase 1.5: Plan validation — run plan-checker agent
- Phase 2: Build — use wave orchestration for complex builds
- Phase 3: Parallel review — Antigravity + Codex + Claude subagent reviewers
- Phase 4: Process reviews — use findings-synthesizer agent
- Phase 5: Test — Codex writes and runs tests
- Phase 6: Wrap up — compound knowledge, update STATE.md

Before exiting, ALWAYS update ops/STATE.md with current progress.
Completion signal: ONLY when the /goal checklist above is fully satisfied, create the empty runtime marker ops/.sprint-complete (touch ops/.sprint-complete) as your LAST action. NEVER create it early — the outer loop detects completion solely by this file's existence."
}

# Dry run: print the composed prompt (iteration 1) and exit. No claude
# invocation, no sentinel mutation — placed before the CLI preflight because
# nothing is executed.
if [ "$DRY_RUN" = "true" ]; then
  compose_prompt 1
  printf '%s\n' "$PROMPT"
  exit 0
fi

# Preflight: coordinate.sh drives Claude via `claude --print`. If the CLI is
# missing (e.g. user installed only the IDE extension), `|| true` below would
# mask every iteration as a silent no-op.
if ! command -v claude >/dev/null 2>&1; then
  echo "coordinate.sh: ERROR \`claude\` CLI not found on PATH." >&2
  echo "  This script requires the Claude Code command-line interface." >&2
  echo "  Install from https://docs.claude.com/claude-code or ensure it is on PATH." >&2
  exit 1
fi

# --- Notification (optional, env-var-gated) ---
notify() {
  local title="$1" body="$2"
  if [ -n "${NOTIFY_WEBHOOK_URL:-}" ]; then
    curl -s --connect-timeout 5 --max-time 10 -X POST "$NOTIFY_WEBHOOK_URL" \
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

# Fresh run: clear any stale completion marker (runtime file, gitignored)
rm -f "$SENTINEL"

while [ "$ITERATION" -lt "$MAX_ITERATIONS" ] && [ "$DONE" = "false" ]; do
  ITERATION=$((ITERATION + 1))
  echo "--- Iteration $ITERATION/$MAX_ITERATIONS ---"

  compose_prompt "$ITERATION"

  # Run Claude Code with the goal-gated prompt (tail shown for observability)
  OUTPUT=$(claude --print --permission-mode acceptEdits "$PROMPT" 2>&1) || true
  printf '%s\n' "$OUTPUT" | tail -n 20

  # Completion check: headless-observable sentinel created by the session
  # only after the verification checklist passes
  if [ -f "$SENTINEL" ]; then
    DONE=true
    notify "Agent Triforge" "Sprint complete — converged in $ITERATION iterations"
    echo ""
    echo "=== Sprint complete at iteration $ITERATION ($SENTINEL present) ==="
  else
    echo "Session ended without creating $SENTINEL. Spawning fresh session..."
    echo ""
  fi
done

if [ "$DONE" = "false" ]; then
  echo ""
  echo "=== Max iterations ($MAX_ITERATIONS) reached without completion ==="
  notify "Agent Triforge" "Sprint did NOT converge after $MAX_ITERATIONS iterations"
  echo "Check ops/STATE.md for current progress."
  echo "Check ops/TASKS.md for remaining tasks."
  echo "Run again to continue, or review manually."
fi
