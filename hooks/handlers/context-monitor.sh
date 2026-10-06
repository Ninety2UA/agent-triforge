#!/usr/bin/env bash
# Context Monitor — PostToolUse hook
# Detects analysis paralysis (excessive read-only ops without producing code)
# and warns when approaching context limits.
#
# Hook event: PostToolUse
# Configuration: registered in hooks/hooks.json (plugin)
#
# ON_CRASH: ALLOW — a crash must never block the tool call (R14/G7): this hook
#   is advisory only; the EXIT trap below turns any unexpected non-zero status
#   (set -e / set -u, e.g. an unwritable state dir) into a stderr notice +
#   exit 0, and every explicit exit path is `exit 0`.
# Exit codes: 0 ok · 2 hook deny (never used by Triforge handlers) · 64 usage ·
#   66 no-input · 69 unavailable · 70 internal · 80 degraded (documented only —
#   Triforge handlers always return 0).
# Hook stdout must never look like JSON: no stdout line may start with `{`
#   (Claude Code ≥ 2.1.246 rejects hook stdout that parses as JSON — D-031c).
#   Audited 2026-10-06: every stdout line starts "Context monitor:" /
#   "Consider:" / "Strongly consider:" / "If researching"; the one-per-session
#   NOTE goes to stderr.
#
# Tool vocabulary (KTD1, R21): which tool names are reads is the lead's
# registry data (lead.tool_vocab_read / lead.tool_vocab_action in
# scripts/lib/registry.sh, read through lead_field), never a list here. A name
# in the read list is a read; "<tool>(read)" there makes a call of <tool>
# whose command only reads (cat, sed -n, rg, git log, ...) a read — how a
# Codex lead's shell reads count, since its hook payload names exec_command
# Bash (CDX-21). Any other name is an action, so an unmapped tool never
# raises a false warning. A lead whose read vocabulary is empty, or a lead
# that can't be resolved, leaves the hook inert, said once per session on
# stderr (R21, R44).
#
# State, classification and output live in monitors.py beside this file (the
# "context" half): per-session counts under
#   ${TMPDIR}/triforge-monitors-<uid>/<checkout>-<hash>/<session_id>.context
# outside the project, in directories checked private on every call (owned by
# this user, not a symlink, no group or other bits) and files written without
# following a link; the lead's vocabulary is cached there (lead-vocab), keyed
# on the roster and the registry. This handler keeps the hook contract and
# reads the vocabulary through the helper library when monitors.py asks for it
# (exit 3).

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

_cm_on_exit() {
  local RC=$?
  [ "$RC" -eq 0 ] && return 0
  echo "context-monitor: WARNING hook crashed (rc=${RC}) — advisory only, tool call continues (ON_CRASH: ALLOW)" >&2
  exit 0
}
trap _cm_on_exit EXIT

# Read hook input from stdin (each lead delivers PostToolUse data as JSON on stdin)
HOOK_INPUT=$(cat)
CM_HANDLERS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CM_PLUGIN_ROOT=$(cd "${CM_HANDLERS}/../.." && pwd)

RC=0
printf '%s' "$HOOK_INPUT" | CM_PLUGIN_ROOT="$CM_PLUGIN_ROOT" python3 "${CM_HANDLERS}/monitors.py" context || RC=$?
if [ "$RC" -eq 3 ]; then
  # The lead's vocabulary is not cached for this roster and registry: read it
  # through the helper library (lead_field, KTD1), then classify with it.
  VOCAB=$( (
    # shellcheck source=/dev/null
    source "${CM_PLUGIN_ROOT}/scripts/invoke-external.sh" >/dev/null 2>&1 && lead_field name lead.tool_vocab_read lead.tool_vocab_action 2>/dev/null
  ) ) || VOCAB=""
  RC=0
  printf '%s' "$HOOK_INPUT" | CM_PLUGIN_ROOT="$CM_PLUGIN_ROOT" CM_VOCAB_FRESH=1 CM_VOCAB="$VOCAB" python3 "${CM_HANDLERS}/monitors.py" context || RC=$?
fi
if [ "$RC" -ne 0 ]; then
  echo "context-monitor: WARNING the monitor failed (rc=${RC}) — advisory only, tool call continues (ON_CRASH: ALLOW)" >&2
fi

# Always exit 0 — this hook is advisory only, never blocks
exit 0
