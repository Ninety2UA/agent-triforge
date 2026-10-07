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
# State and output live in monitors.py beside this file (the "failures"
# half): per-session counts under
#   ${TMPDIR}/triforge-monitors-<uid>/<checkout>-<hash>/<session_id>.failures
# outside the project (R21), in directories checked private on every call and
# files written without following a link; every value printed is stripped of
# control characters.
#
# Hook event: PostToolUse
# Configuration: registered in hooks/hooks.json (plugin)
#
# ON_CRASH: ALLOW — a crash must never block the tool call (R14/G7): this hook
#   is advisory only; the EXIT trap below turns any unexpected non-zero status
#   (set -e / set -u) into a stderr notice + exit 0, a monitors.py failure is
#   one stderr notice, and every explicit exit path is `exit 0`.
# Exit codes: 0 ok · 2 hook deny (never used by Triforge handlers) · 64 usage ·
#   66 no-input · 69 unavailable · 70 internal · 80 degraded (documented only —
#   Triforge handlers always return 0).
# Hook stdout must never look like JSON: no stdout line may start with `{`
#   (Claude Code ≥ 2.1.246 rejects hook stdout that parses as JSON — D-031c).
#   Audited 2026-10-06: the only stdout lines start "WARN:"; the
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

# _tf_nopython <payload> — python3 is a Triforge prerequisite; without it the
# monitor is off, and says so once per session, not on every call (Phase 3
# round 4, P3-4). The marker is a directory made by mkdir (atomic, and never
# a write through a link) in the per-user base monitors.py keeps under
# TMPDIR, when that base is a real directory of this user; with no readable
# session id, or no such base, the note prints on every call instead.
_tf_nopython() {
  local S="" B="" M=""
  S=$(printf '%s' "$1" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9._-]\{1,80\}\)".*/\1/p' 2>/dev/null | head -1) || S=""
  B="${TMPDIR:-/tmp}/triforge-monitors-${UID:-unknown}"
  if [ -n "$S" ] && { [ -d "$B" ] || mkdir -m 700 "$B" 2>/dev/null; } && [ -d "$B" ] && [ ! -L "$B" ] && [ -O "$B" ]; then
    M="${B}/tool-failure-monitor.${S}.nopython-noted"
    if ! mkdir "$M" 2>/dev/null && [ -d "$M" ] && [ ! -L "$M" ]; then
      return 0
    fi
  fi
  echo "tool-failure-monitor: WARNING python3 is not on PATH, so failure tracking is off (python3 is a Triforge prerequisite; said once per session) — advisory only, tool call continues" >&2
}

# monitors.py reads the payload from the hook's stdin itself. When it fails
# (no monitors.py beside this file) whatever it left unread is drained, so
# the caller never writes into a closed pipe.
TF_HANDLERS=${BASH_SOURCE[0]%/*}
if [ "$TF_HANDLERS" = "${BASH_SOURCE[0]}" ]; then TF_HANDLERS=.; fi

if ! command -v python3 >/dev/null 2>&1; then
  TF_IN=""
  if [ ! -t 0 ]; then TF_IN=$(cat 2>/dev/null) || TF_IN=""; fi
  _tf_nopython "$TF_IN"
  exit 0
fi

RC=0
python3 "${TF_HANDLERS}/monitors.py" failures || RC=$?
if [ "$RC" -ne 0 ]; then
  [ -t 0 ] || cat > /dev/null 2>&1 || true
  echo "tool-failure-monitor: WARNING the monitor failed (rc=${RC}) — advisory only, tool call continues (ON_CRASH: ALLOW)" >&2
fi
exit 0
