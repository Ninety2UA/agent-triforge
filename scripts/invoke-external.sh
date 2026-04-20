#!/usr/bin/env bash
# invoke-external.sh — Unified Gemini/Codex invocation
#
# Provides invoke_gemini and invoke_codex functions for running external
# agents with the correct config, system prompt, and policy file.
#
# Usage: source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh
#
# Functions:
#   invoke_gemini <agent-name> <prompt> <output-file> <timeout-seconds>
#   invoke_codex  <agent-name> <prompt> <output-file> <timeout-seconds>

set -euo pipefail

# ---------------------------------------------------------------------------
# Gemini invocation
# ---------------------------------------------------------------------------

# If .gemini/agents/<agent-name>.md exists in CWD, uses @<agent-name> native
# routing. Otherwise falls back to injecting the plugin template's body as
# prompt prefix.
#
# Also passes --policy <file> when a project or plugin policies.toml exists —
# Gemini auto-discovers policies only from ~/.gemini/policies/*.toml (user
# tier), not project tier, so we load ours explicitly.
invoke_gemini() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/gemini_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local FULL_PROMPT=""
  local MODE=""
  local EXIT_CODE=0

  local POLICY_ARGS=()
  if [ -f ".gemini/policies.toml" ]; then
    POLICY_ARGS=(--policy .gemini/policies.toml)
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/gemini-agents/policies.toml" ]; then
    POLICY_ARGS=(--policy "${CLAUDE_PLUGIN_ROOT}/gemini-agents/policies.toml")
  fi

  if [ -f ".gemini/agents/${AGENT_NAME}.md" ]; then
    FULL_PROMPT="@${AGENT_NAME} ${PROMPT}"
    MODE="native"
  else
    local AGENT_FILE=""
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/gemini-agents/${AGENT_NAME}.md" ]; then
      AGENT_FILE="${CLAUDE_PLUGIN_ROOT}/gemini-agents/${AGENT_NAME}.md"
    fi
    if [ -n "$AGENT_FILE" ]; then
      local BODY
      BODY=$(awk '/^---[[:space:]]*$/{skip++; next} skip>=2{print}' "$AGENT_FILE")
      FULL_PROMPT="${BODY}

${PROMPT}"
      MODE="legacy-injection"
    else
      local AVAILABLE
      AVAILABLE=$(_list_gemini_agents | paste -sd, - 2>/dev/null || echo "")
      echo "invoke_gemini: WARNING agent '${AGENT_NAME}' not found in .gemini/agents or plugin template; falling through to raw prompt (no system prompt applied). Available agents: ${AVAILABLE:-<none>}" >&2
      FULL_PROMPT="$PROMPT"
      MODE="raw"
    fi
  fi

  local POLICY_LOG="none"
  if [ "${#POLICY_ARGS[@]}" -gt 0 ]; then
    POLICY_LOG="${POLICY_ARGS[*]}"
  fi
  echo "invoke_gemini: agent=${AGENT_NAME} mode=${MODE} policy=${POLICY_LOG}" >&2

  _run_with_timeout "${TIMEOUT}" gemini "${POLICY_ARGS[@]}" -y -p "$FULL_PROMPT" > "$OUTPUT_FILE" 2>&1 || EXIT_CODE=$?

  # Retry once with simplified prompt on failure (per docs/agent-triforge.md)
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "invoke_gemini: agent=${AGENT_NAME} exit=${EXIT_CODE}, retrying with raw prompt" >&2
    EXIT_CODE=0
    _run_with_timeout "${TIMEOUT}" gemini "${POLICY_ARGS[@]}" -y -p "$PROMPT" > "${OUTPUT_FILE}.retry" 2>&1 || EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
      mv "${OUTPUT_FILE}.retry" "$OUTPUT_FILE"
    else
      echo "invoke_gemini: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE}" >&2
    fi
  fi

  return $EXIT_CODE
}

# ---------------------------------------------------------------------------
# Codex invocation
# ---------------------------------------------------------------------------

# Codex has no CLI flag to pick a subagent — upstream "subagents" are only
# spawned from within a running session. So we simulate it: extract the agent's
# config from agents.toml and pass it as -c/-s/-a overrides, with the
# developer_instructions injected as prompt prefix.
#
# Agents.toml lookup: project `.codex/agents/agents.toml` first, then plugin
# template `${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml`.
invoke_codex() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/codex_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EXIT_CODE=0

  local AGENT_TOML=""
  if [ -f ".codex/agents/agents.toml" ]; then
    AGENT_TOML=".codex/agents/agents.toml"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml" ]; then
    AGENT_TOML="${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml"
  fi

  local AGENT_MODEL="" AGENT_SANDBOX="" AGENT_APPROVAL="" AGENT_INSTR_B64=""
  if [ -n "$AGENT_TOML" ]; then
    local CONFIG_SH
    CONFIG_SH=$(_extract_codex_agent_config "$AGENT_TOML" "$AGENT_NAME") || CONFIG_SH=""
    if [ -n "$CONFIG_SH" ]; then
      eval "$CONFIG_SH"
    fi
  fi

  # Loud warning when the agent wasn't found in agents.toml — otherwise we
  # silently run with session defaults (no model, no sandbox, no instructions).
  if [ -z "$AGENT_MODEL" ] && [ -z "$AGENT_SANDBOX" ] && [ -z "$AGENT_INSTR_B64" ]; then
    local AVAILABLE
    AVAILABLE=$(_list_codex_agents "$AGENT_TOML" | paste -sd, - 2>/dev/null || echo "")
    echo "invoke_codex: WARNING agent '${AGENT_NAME}' not found in agents.toml; running with session defaults (no model/sandbox/instructions applied). Available agents: ${AVAILABLE:-<none>}" >&2
  fi

  local INSTRUCTIONS=""
  if [ -n "$AGENT_INSTR_B64" ]; then
    INSTRUCTIONS=$(printf '%s' "$AGENT_INSTR_B64" | base64 -d 2>/dev/null || echo "")
  fi

  # `codex exec` accepts -m/-s but NOT -a (approval is set via -c override).
  local CMD=(codex exec)
  [ -n "$AGENT_MODEL" ]    && CMD+=(-m "$AGENT_MODEL")
  [ -n "$AGENT_SANDBOX" ]  && CMD+=(-s "$AGENT_SANDBOX")
  [ -n "$AGENT_APPROVAL" ] && CMD+=(-c "approval_policy=\"$AGENT_APPROVAL\"")
  # --full-auto provides sensible defaults only when neither sandbox nor approval is set.
  if [ -z "$AGENT_SANDBOX" ] && [ -z "$AGENT_APPROVAL" ]; then
    CMD+=(--full-auto)
  fi

  local FULL_PROMPT="$PROMPT"
  if [ -n "$INSTRUCTIONS" ]; then
    FULL_PROMPT="${INSTRUCTIONS}

===USER PROMPT===
${PROMPT}"
  fi

  echo "invoke_codex: agent=${AGENT_NAME} model=${AGENT_MODEL:-session-default} sandbox=${AGENT_SANDBOX:-session-default} approval=${AGENT_APPROVAL:-session-default}" >&2

  _run_with_timeout "${TIMEOUT}" "${CMD[@]}" "$FULL_PROMPT" > "$OUTPUT_FILE" 2>&1 || EXIT_CODE=$?

  # Retry once with raw prompt on failure (mirrors invoke_gemini behavior).
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "invoke_codex: agent=${AGENT_NAME} exit=${EXIT_CODE}, retrying with raw prompt" >&2
    EXIT_CODE=0
    _run_with_timeout "${TIMEOUT}" "${CMD[@]}" "$PROMPT" > "${OUTPUT_FILE}.retry" 2>&1 || EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
      mv "${OUTPUT_FILE}.retry" "$OUTPUT_FILE"
    else
      echo "invoke_codex: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE}" >&2
    fi
  fi

  return $EXIT_CODE
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Run a command with a timeout. macOS lacks `timeout` by default; try `gtimeout`
# from coreutils; fall back to direct exec (no timeout enforcement).
_run_with_timeout() {
  local SECS=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${SECS}s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${SECS}s" "$@"
  else
    "$@"
  fi
}

# Emit bash variable assignments extracted from a Codex agents.toml entry.
# Outputs:
#   AGENT_MODEL=<string>
#   AGENT_SANDBOX=<string>
#   AGENT_APPROVAL=<string>
#   AGENT_INSTR_B64=<base64 string>
# Missing fields emit empty values. Fails loudly (exit 1 + stderr warning) if
# python or a TOML parser is unavailable, so callers can detect the condition
# and log it rather than silently running with session defaults.
_extract_codex_agent_config() {
  local AGENT_TOML=$1
  local AGENT_NAME=$2
  AGENT_TOML="$AGENT_TOML" AGENT_NAME="$AGENT_NAME" python3 -c "
import sys, os, json, base64
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('invoke-external.sh: Codex agent config extraction failed; using session defaults. Install Python 3.11+ (for tomllib) or `pip install tomli` to enable agent config loading.\\n')
        sys.exit(1)
with open(os.environ['AGENT_TOML'], 'rb') as f:
    data = tomllib.load(f)
agent_raw = data.get('agents', {}).get(os.environ['AGENT_NAME'], {})
agent = agent_raw if isinstance(agent_raw, dict) else {}
instr_b64 = base64.b64encode(agent.get('developer_instructions', '').encode()).decode()
print('AGENT_MODEL='    + json.dumps(agent.get('model', '')))
print('AGENT_SANDBOX='  + json.dumps(agent.get('sandbox_mode', '')))
print('AGENT_APPROVAL=' + json.dumps(agent.get('approval_policy', '')))
print('AGENT_INSTR_B64=' + json.dumps(instr_b64))
"
}

# List known Gemini agent names (project tier first, falling back to plugin).
_list_gemini_agents() {
  local dir=""
  if [ -d ".gemini/agents" ]; then
    dir=".gemini/agents"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/gemini-agents" ]; then
    dir="${CLAUDE_PLUGIN_ROOT}/gemini-agents"
  fi
  [ -z "$dir" ] && return
  for f in "$dir"/*.md; do
    [ -f "$f" ] && basename "$f" .md
  done 2>/dev/null | sort -u
}

# List known Codex agent names from agents.toml (skips non-table keys like
# max_depth that live at [agents] top-level).
_list_codex_agents() {
  local AGENT_TOML=$1
  [ -z "$AGENT_TOML" ] && return
  [ -f "$AGENT_TOML" ] || return
  AGENT_TOML="$AGENT_TOML" python3 -c "
import sys, os
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
with open(os.environ['AGENT_TOML'], 'rb') as f:
    data = tomllib.load(f)
for k, v in sorted(data.get('agents', {}).items()):
    if isinstance(v, dict):
        print(k)
" 2>/dev/null
}
