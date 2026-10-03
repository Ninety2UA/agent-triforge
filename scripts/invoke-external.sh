#!/usr/bin/env bash
# invoke-external.sh — Unified Antigravity/Codex invocation
#
# Provides invoke_antigravity and invoke_codex functions for running external
# agents with the correct agent definition, model pin, and workspace binding.
# The legacy Gemini CLI lane was removed 2026-07: Google shut down Gemini
# CLI's hosted service on 2026-06-18; Antigravity CLI (binary: agy) is the
# successor and Triforge targets its headless mode (`agy -p`).
#
# Usage: source <plugin root>/scripts/invoke-external.sh
#   Under a Claude Code lead that is `source "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh"`;
#   any other lead sources it by the path scripts/skill-locator/locate-triforge.sh
#   prints. The loader resolves the plugin root itself (KTD6, below) and the
#   lanes read it as ${_TRIFORGE_PLUGIN_ROOT} — never CLAUDE_PLUGIN_ROOT.
#
# Layout: this file is the loader. The lanes live in scripts/lib/ and are
# sourced below, in this order, into the same shell:
#   lib/common.sh       host-marker scrub, timeout wrapper, scrubbing, KTD-9
#                       failure classifier, agy/codex listing helpers
#   lib/registry.sh     shared data: the protected-path lists (KTD8), the model
#                       ladder TRIFORGE_MODEL_LADDER + triforge_ladder (KTD22)
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
#   triforge_plugin_root          — prints the resolved plugin root (${_TRIFORGE_PLUGIN_ROOT})
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

# Plugin root (KTD6 / R42) — resolved ONCE, here, for every lane. The lanes read
# ${_TRIFORGE_PLUGIN_ROOT} (or call triforge_plugin_root), never
# CLAUDE_PLUGIN_ROOT, so the same code runs under a Claude Code lead (which
# exports that variable) and under any lead that does not. Order:
#   1. CLAUDE_PLUGIN_ROOT, when it passes the Triforge-root test;
#   2. the directory above this loader's own scripts/ (bash via BASH_SOURCE, zsh
#      via its prompt-expansion %x — evaluated through eval so bash never
#      parses the zsh form), when IT passes the test;
#   3. otherwise fail closed. There is deliberately no fallback to the working
#      directory's scripts/: a user project with its own
#      scripts/invoke-external.sh or skills/ must never be sourced or
#      provisioned from by accident (SELF-11 checks both).
# Triforge-root test: <dir>/.claude-plugin/plugin.json names "agent-triforge"
# AND <dir>/scripts/invoke-external.sh exists — the same test the skill locator
# (scripts/skill-locator/locate-triforge.sh) and _lease_plugin_root apply.
_triforge_is_plugin_root() { # _triforge_is_plugin_root <dir>
  if [ -n "${1:-}" ] && [ -f "$1/scripts/invoke-external.sh" ] && [ -f "$1/.claude-plugin/plugin.json" ] \
     && grep -Eq '"name"[[:space:]]*:[[:space:]]*"agent-triforge"' "$1/.claude-plugin/plugin.json" 2>/dev/null; then
    return 0
  fi
  return 1
}
_TRIFORGE_SELF_DIR=""
if [ -n "${BASH_SOURCE:-}" ]; then
  _TRIFORGE_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [ -n "${ZSH_VERSION:-}" ]; then
  _TRIFORGE_SELF_DIR="$(cd "$(dirname "$(eval 'echo "${(%):-%x}"')")" && pwd)"
fi
_TRIFORGE_PLUGIN_ROOT=""
if _triforge_is_plugin_root "${CLAUDE_PLUGIN_ROOT:-}"; then
  _TRIFORGE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT%/}"
elif [ -n "$_TRIFORGE_SELF_DIR" ] && _triforge_is_plugin_root "${_TRIFORGE_SELF_DIR}/.."; then
  _TRIFORGE_PLUGIN_ROOT="$(cd "${_TRIFORGE_SELF_DIR}/.." && pwd)"
else
  echo "invoke-external.sh: ERROR no Triforge plugin root — CLAUDE_PLUGIN_ROOT is ${CLAUDE_PLUGIN_ROOT:+set to '${CLAUDE_PLUGIN_ROOT}' but not a Triforge root}${CLAUDE_PLUGIN_ROOT:-unset} and this loader (${_TRIFORGE_SELF_DIR:-<unknown dir>}) is not inside a Triforge plugin tree (.claude-plugin/plugin.json named agent-triforge plus scripts/invoke-external.sh). Source the installed plugin's scripts/invoke-external.sh, or run the Triforge setup skill (\`/setup\` today, \`at-setup\` from 4.0)." >&2
  unset _TRIFORGE_SELF_DIR _TRIFORGE_PLUGIN_ROOT
  return 2 2>/dev/null || exit 2
fi
unset _TRIFORGE_SELF_DIR
_TRIFORGE_SCRIPTS_DIR="${_TRIFORGE_PLUGIN_ROOT}/scripts"
triforge_plugin_root() { printf '%s\n' "$_TRIFORGE_PLUGIN_ROOT"; }

# Load the lanes (fail-closed: a missing lib is a broken install, never a
# silently narrower helper).
for _triforge_lib in common registry antigravity codex opencode kimi cursor roster lease; do
  if [ ! -f "${_TRIFORGE_SCRIPTS_DIR}/lib/${_triforge_lib}.sh" ]; then
    echo "invoke-external.sh: ERROR missing ${_TRIFORGE_SCRIPTS_DIR}/lib/${_triforge_lib}.sh — the plugin install is incomplete (reinstall: claude plugin install agent-triforge@agent-triforge)" >&2
    return 2 2>/dev/null || exit 2
  fi
  # shellcheck source=/dev/null
  source "${_TRIFORGE_SCRIPTS_DIR}/lib/${_triforge_lib}.sh"
done
unset _triforge_lib
