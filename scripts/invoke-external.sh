#!/usr/bin/env bash
# invoke-external.sh — Unified Antigravity/Codex invocation
#
# Provides invoke_antigravity and invoke_codex functions for running external
# agents with the correct agent definition, model pin, and workspace binding.
# The legacy Gemini CLI lane was removed 2026-07: Google shut down Gemini
# CLI's hosted service on 2026-06-18; Antigravity CLI (binary: agy) is the
# successor and Triforge targets its headless mode (`agy -p`).
#
# Usage: source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh
#
# Layout: this file is the loader. The lanes live in scripts/lib/ and are
# sourced below, in this order, into the same shell:
#   lib/common.sh       host-marker scrub, timeout wrapper, scrubbing, KTD-9
#                       failure classifier, agy/codex listing helpers
#   lib/antigravity.sh  invoke_antigravity + _agy_parse_envelope
#   lib/codex.sh        invoke_codex
#   lib/opencode.sh     invoke_opencode + the OPENCODE_PERMISSION deny set
#   lib/kimi.sh         invoke_kimi
#   lib/cursor.sh       _cursor_bin, _cursor_model_for_effort, invoke_cursor
#   lib/roster.sh       resolve_role, dispatch_role, roster_* (DEFAULTS live here)
#   lib/lease.sh        the lease lifecycle + _adapter_env + the typed-report parser
# Function names and contracts are unchanged by the split; commands keep
# sourcing this file only.
#
# Functions:
#   invoke_antigravity   <agent-name> <prompt> [output-file] [timeout-seconds]
#   invoke_codex         <agent-name> <prompt> [output-file] [timeout-seconds]
#   resolve_role         <role>   — roster lookup: prints cli<TAB>model<TAB>effort
#   ensure_core_trio_live         — lazy liveness gate for build/review paths
#   latest_probe_record           — path of the newest ops/research/*-probe-record.md
#
# Failure taxonomy (KTD-9): both helpers classify failures instead of
# blindly retrying, and expose the class via INVOKE_FAILURE_CLASS:
#   deterministic — retry cannot help (CLI binary missing, not logged in,
#                   timeout tool missing); fails fast with fix guidance and
#                   does NOT burn a second timeout window
#   timeout       — the timeout wrapper killed the run (exit 124/137);
#                   requeue policy belongs to the caller (lease layer),
#                   not this helper
#   retryable     — any other nonzero; retried once with the raw prompt
#                   before giving up
#   none          — invocation succeeded
# The variable is only visible on synchronous calls in the same shell —
# background invocations (`invoke_antigravity ... &`) cannot export it back.
#
# Host-marker scrub (D-031c / U5): every foreground invoke_* helper runs its CLI
# under _HOST_SCRUB — `env -u` of the markers the lead's own harness exports
# (CLAUDECODE, CODEX_SANDBOX*, CODEX_SESSION_ID, CODEX_THREAD_ID, CODEX_CI,
# GROK_AGENT, GROK_SESSION_ID, CURSOR_AGENT, CURSOR_CONVERSATION_ID,
# OPENCODE_TERMINAL, CLICOLOR_FORCE, GH_FORCE_TTY) plus NO_COLOR=1 — so a
# dispatched CLI never mistakes the lead's session for its own and never
# colors captured output. The lease lane's _adapter_env is `env -i` with an
# explicit allowlist, so those markers are already absent there; it adds the
# same NO_COLOR=1.
#
# Codex feature detection: capability decisions for the Codex lane (hooks,
# structured output) come from `codex features list` at runtime — cached once
# per session by _codex_feature_enabled — never from version-string reasoning
# (probe CDX-02, 2026-07-17).
#
# Timeout enforcement is fail-closed: when neither `timeout` nor `gtimeout`
# is on PATH, the helpers refuse to run at all rather than silently running
# without enforcement (macOS: brew install coreutils). Applies to both lanes.

set -euo pipefail

# Directory of this file, resolved for both shells that `source` it (bash via
# BASH_SOURCE, zsh via its prompt-expansion %x — evaluated through eval so
# bash never parses the zsh form). CLAUDE_PLUGIN_ROOT wins when set.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/scripts" ]; then
  _TRIFORGE_SCRIPTS_DIR="${CLAUDE_PLUGIN_ROOT}/scripts"
elif [ -n "${BASH_SOURCE:-}" ]; then
  _TRIFORGE_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _TRIFORGE_SCRIPTS_DIR="$(cd "$(dirname "$(eval 'echo "${(%):-%x}"')")" && pwd)"
else
  _TRIFORGE_SCRIPTS_DIR="$(pwd)/scripts"
fi

# Load the lanes (fail-closed: a missing lib is a broken install, never a
# silently narrower helper).
for _triforge_lib in common antigravity codex opencode kimi cursor roster lease; do
  if [ ! -f "${_TRIFORGE_SCRIPTS_DIR}/lib/${_triforge_lib}.sh" ]; then
    echo "invoke-external.sh: ERROR missing ${_TRIFORGE_SCRIPTS_DIR}/lib/${_triforge_lib}.sh — the plugin install is incomplete (reinstall: claude plugin install agent-triforge@agent-triforge)" >&2
    return 2 2>/dev/null || exit 2
  fi
  # shellcheck source=/dev/null
  source "${_TRIFORGE_SCRIPTS_DIR}/lib/${_triforge_lib}.sh"
done
unset _triforge_lib
