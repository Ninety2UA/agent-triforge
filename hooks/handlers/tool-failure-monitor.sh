#!/usr/bin/env bash
# tool-failure-monitor.sh — PostToolUse hook that tracks tool failures.
#
# PostToolUse fires on every tool call (success and failure). This handler
# inspects tool_response for an error signal and only counts failures.
# Warns at 5 consecutive or 10 total failures per session.
#
# The error signal, by payload shape: a tool_response object with is_error
# true or an error field (Claude Code); a plain-text tool_response that opens
# with "Exit code: <n>" (Codex's apply_patch), failed when n is not 0. Plain
# text with no exit code (Codex reports its exec_command calls that way, CDX-21)
# carries no signal: such a call counts as a success, and the first one in a
# session says so once on stderr (R44).
#
# State lives outside the project, for either lead (R21):
#   ${TMPDIR}/triforge-monitors-<uid>/<checkout>-<cksum>/<session_id>.failures
# one file per session (the session_id in the hook payload); see
# context-monitor.sh, which prunes the directory.
#
# Hook event: PostToolUse
# Configuration: registered in hooks/hooks.json (plugin)
#
# ON_CRASH: ALLOW — a crash must never block the tool call (R14/G7): this hook
#   is advisory only; the EXIT trap below turns any unexpected non-zero status
#   (set -e / set -u, e.g. an unwritable state dir) into a stderr notice +
#   exit 0, and every explicit exit path (the non-failure early return) is
#   `exit 0`.
# Exit codes: 0 ok · 2 hook deny (never used by Triforge handlers) · 64 usage ·
#   66 no-input · 69 unavailable · 70 internal · 80 degraded (documented only —
#   Triforge handlers always return 0).
# Hook stdout must never look like JSON: no stdout line may start with `{`
#   (Claude Code ≥ 2.1.246 rejects hook stdout that parses as JSON — D-031c).
#   Audited 2026-10-04: the only stdout lines start "WARN:"; the
#   one-per-session NOTE goes to stderr.

# Worker marker (KTD9, R34): in a lease worker or persona (TRIFORGE_LEASE_WORKER
# set by _adapter_env) this hook does nothing and prints nothing — a worker's
# CLI may load the plugin's hooks, and they must not write state into its
# worktree. The input is still read, so a large PostToolUse payload never
# meets a closed pipe.
if [ -n "${TRIFORGE_LEASE_WORKER:-}" ]; then
  [ -t 0 ] || cat > /dev/null 2>&1 || true
  exit 0
fi

set -euo pipefail

_tf_on_exit() {
  local RC=$?
  [ "$RC" -eq 0 ] && return 0
  echo "tool-failure-monitor: WARNING hook crashed (rc=${RC}) — advisory only, tool call continues (ON_CRASH: ALLOW)" >&2
  exit 0
}
trap _tf_on_exit EXIT

HOOK_INPUT=$(cat)

# _monitor_root / _monitor_state_dir — kept in step with context-monitor.sh:
# the checkout (nearest ancestor holding .git, else the working directory) and
# its state dir under a per-user base of mode 700 (rc 1, hook inert, when the
# base is not a directory this user owns).
_monitor_root() {
  local ROOT D
  ROOT=$(pwd -P 2>/dev/null) || ROOT=$PWD
  D=$ROOT
  while [ -n "$D" ] && [ "$D" != "/" ]; do
    if [ -e "$D/.git" ]; then
      ROOT=$D
      break
    fi
    D=${D%/*}
  done
  printf '%s\n' "$ROOT"
}
_monitor_state_dir() {
  local BASE D
  BASE="${TMPDIR:-/tmp}"
  BASE="${BASE%/}/triforge-monitors-$(id -u)"
  mkdir -p -m 700 "$BASE" 2>/dev/null || return 1
  if [ -L "$BASE" ] || [ ! -O "$BASE" ]; then
    return 1
  fi
  D="${BASE}/$(basename "$1")-$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  mkdir -p "$D" 2>/dev/null || return 1
  printf '%s\n' "$D"
}

if ! STATE_DIR=$(_monitor_state_dir "$(_monitor_root)"); then
  echo "tool-failure-monitor: NOTE no private state directory under ${TMPDIR:-/tmp} (not owned by this user, or a symlink) — failure tracking is off (R21)" >&2
  exit 0
fi

# Parse the session, tool_name and failure signal from hook input:
# "<session>|<tool>|<failed 0/1>|<signal yes/no>".
PARSED=$(printf '%s' "$HOOK_INPUT" | python3 -c "
import json, re, sys
try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        d = {}
except Exception:
    d = {}
tool = re.sub(r'[^A-Za-z0-9._:()-]', '_', str(d.get('tool_name') or 'unknown'))[:80]
sid = re.sub(r'[^A-Za-z0-9._-]', '_', str(d.get('session_id') or ''))[:80] or 'session'
resp = d.get('tool_response', {})
is_err, signal = False, 'yes'
if isinstance(resp, dict):
    is_err = resp.get('is_error') is True or bool(resp.get('error'))
elif isinstance(resp, str):
    m = re.match(r'\\s*Exit code:\\s*(-?[0-9]+)', resp)
    if m:
        is_err = int(m.group(1)) != 0
    else:
        signal = 'no'
print(sid + '|' + tool + '|' + ('1' if is_err else '0') + '|' + signal)
" 2>/dev/null || echo "session|unknown|0|yes")

SESSION=${PARSED%%|*}
PARSED_REST=${PARSED#*|}
TOOL_NAME=${PARSED_REST%%|*}
PARSED_REST=${PARSED_REST#*|}
FAILED=${PARSED_REST%%|*}
SIGNAL=${PARSED_REST#*|}
STATE_FILE="${STATE_DIR}/${SESSION}.failures"

# R44: a payload with no failure signal is said once per session.
if [ "$SIGNAL" = "no" ] && [ ! -f "${STATE_DIR}/${SESSION}.signal-noted" ]; then
  : > "${STATE_DIR}/${SESSION}.signal-noted"
  echo "tool-failure-monitor: NOTE the PostToolUse payload for ${TOOL_NAME} carries no failure signal (plain-text tool_response, no exit code), so its failures are not counted this session (R44)" >&2
fi

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
  printf 'WARN:%s consecutive tool failures (latest: %s). Consider investigating before continuing.\n' "$CONSECUTIVE" "$TOOL_NAME"
elif [ "$FAILURE_COUNT" -ge 10 ]; then
  printf 'WARN:%s total tool failures this session (latest: %s). Check %s for details.\n' "$FAILURE_COUNT" "$TOOL_NAME" "$STATE_FILE"
fi

exit 0
