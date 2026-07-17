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
# Functions:
#   invoke_antigravity   <agent-name> <prompt> [output-file] [timeout-seconds]
#   invoke_codex         <agent-name> <prompt> [output-file] [timeout-seconds]
#   resolve_role         <role>   — roster lookup: prints cli<TAB>model<TAB>effort
#   ensure_core_trio_live         — lazy liveness gate for build/review paths
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
# Codex feature detection: capability decisions for the Codex lane (hooks,
# structured output) come from `codex features list` at runtime — cached once
# per session by _codex_feature_enabled — never from version-string reasoning
# (probe CDX-02, 2026-07-17).
#
# Timeout enforcement is fail-closed: when neither `timeout` nor `gtimeout`
# is on PATH, the helpers refuse to run at all rather than silently running
# without enforcement (macOS: brew install coreutils). Applies to both lanes.

set -euo pipefail

# ---------------------------------------------------------------------------
# Antigravity invocation
# ---------------------------------------------------------------------------

# Mode resolution, in order:
#   native    — `agy agents` (agents from installed agy plugins; empty by
#               default) lists the name; select it with --agent. Workspace
#               .gemini/agents/ and .agents/agents/ are NOT discovered by agy
#               (probed 2026-07-17), so there is no project tier. Re-probed
#               2026-07-17 on agy 1.1.3: installed plugin agents do not yet
#               surface headless (`agy agents` stays empty and --agent
#               silently ignores unknown names), so this lane engages only
#               once agy starts listing them — injection is the operative
#               mode until then (probe rows AGY-12/AGY-13 track it).
#   injection — ${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents/<name>.md
#               exists (agents/ subdir: antigravity-agents/ is a valid agy
#               plugin); its body (after frontmatter) is prefixed onto the
#               prompt.
#   raw       — neither found; warn with the available agents and run the
#               bare prompt (no system prompt applied).
#
# Every constructed agy command pins the model (AE2): agy defaults to a Flash
# variant, never acceptable, so --model "${AGY_MODEL:-Gemini 3.1 Pro (High)}"
# is mandatory on every path — the "(Low)"/"(High)" suffix is how agy encodes
# thinking effort, and AGY_MODEL is the override hook for a roster layer.
# Every command also passes --add-dir "$PWD": agy has no --cwd and otherwise
# runs shell commands in its own scratch dir (~/.gemini/antigravity-cli/scratch)
# instead of the project.
invoke_antigravity() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/antigravity_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local MODEL="${AGY_MODEL:-Gemini 3.1 Pro (High)}"
  local FULL_PROMPT=""
  local MODE=""
  local EXIT_CODE=0

  INVOKE_FAILURE_CLASS="none"

  # Deterministic preflight (KTD-9): a missing binary can never succeed on
  # retry — fail fast with the exact fix instead of burning a timeout window.
  if ! command -v agy >/dev/null 2>&1; then
    echo "invoke_antigravity: ERROR \`agy\` (Antigravity CLI) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: install it (curl -fsSL https://antigravity.google/cli/install.sh | bash), then run \`agy\` interactively once to complete login. No retry (deterministic)." >&2
    INVOKE_FAILURE_CLASS="deterministic"
    return 127
  fi

  local NATIVE_LISTING=""
  NATIVE_LISTING=$(_agy_agents_listing)
  if [ -n "$NATIVE_LISTING" ] && printf '%s\n' "$NATIVE_LISTING" | grep -qE "(^|[[:space:]])${AGENT_NAME}([[:space:]:,.]|$)"; then
    FULL_PROMPT="$PROMPT"
    MODE="native"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents/${AGENT_NAME}.md" ]; then
    local BODY
    BODY=$(awk '/^---[[:space:]]*$/{skip++; next} skip>=2{print}' "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents/${AGENT_NAME}.md")
    FULL_PROMPT="${BODY}

${PROMPT}"
    MODE="injection"
  else
    local AVAILABLE
    AVAILABLE=$(_list_antigravity_agents | paste -sd, - 2>/dev/null || echo "")
    echo "invoke_antigravity: WARNING agent '${AGENT_NAME}' not found in agy plugin agents or plugin antigravity-agents/ templates; falling through to raw prompt (no system prompt applied). Available agents: ${AVAILABLE:-<none>}" >&2
    FULL_PROMPT="$PROMPT"
    MODE="raw"
  fi

  # No --dangerously-skip-permissions, EVER: probed 2026-07-17 — it does NOT
  # respect deny rules (a denied command executed under it), so it would
  # defeat defense-in-depth exactly like the old Gemini YOLO flag did. Safety
  # comes from (1) each agent's tools allowlist and (2) the permission
  # system's normal prompts/policies. --sandbox is likewise NOT a confinement
  # mechanism (probe: an absolute-path write outside the workspace landed).
  # --print-timeout (go-duration) keeps agy's own headless wait (default
  # 5m0s) inside our enforcement window.
  local BASE_CMD=(agy --model "$MODEL" --add-dir "$PWD" --print-timeout "${TIMEOUT}s")
  local CMD=("${BASE_CMD[@]}")
  if [ "$MODE" = "native" ]; then
    CMD+=(--agent "$AGENT_NAME")
  fi

  echo "invoke_antigravity: agent=${AGENT_NAME} mode=${MODE} model=${MODEL}" >&2

  _run_with_timeout "${TIMEOUT}" "${CMD[@]}" -p "$FULL_PROMPT" > "$OUTPUT_FILE" 2>&1 || EXIT_CODE=$?

  # KTD-9: classify before reacting — only retryable failures get the
  # retry-once-with-raw-prompt treatment.
  if [ "$EXIT_CODE" -ne 0 ]; then
    _classify_invoke_failure "$EXIT_CODE" "$OUTPUT_FILE"
    case "$INVOKE_FAILURE_CLASS" in
      deterministic)
        case "$_INVOKE_FAILURE_REASON" in
          auth)
            echo "invoke_antigravity: agent=${AGENT_NAME} exit=${EXIT_CODE} auth failure — agy is not logged in (output matched a credential/login pattern). Fix: run \`agy\` interactively once to complete login. No retry (deterministic)." >&2
            ;;
          binary-missing)
            echo "invoke_antigravity: agent=${AGENT_NAME} exit=${EXIT_CODE} — \`agy\` disappeared from PATH mid-run. Fix: install it (curl -fsSL https://antigravity.google/cli/install.sh | bash), then run \`agy\` interactively once to complete login. No retry (deterministic)." >&2
            ;;
          *)
            echo "invoke_antigravity: agent=${AGENT_NAME} exit=${EXIT_CODE} deterministic failure (${_INVOKE_FAILURE_REASON:-see error above}). No retry." >&2
            ;;
        esac
        return "$EXIT_CODE"
        ;;
      timeout)
        echo "invoke_antigravity: agent=${AGENT_NAME} timed out after ${TIMEOUT}s (exit=${EXIT_CODE}). Requeue policy belongs to the caller (lease layer), not this helper." >&2
        return "$EXIT_CODE"
        ;;
      retryable)
        echo "invoke_antigravity: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable), retrying with raw prompt" >&2
        EXIT_CODE=0
        _run_with_timeout "${TIMEOUT}" "${BASE_CMD[@]}" -p "$PROMPT" > "${OUTPUT_FILE}.retry" 2>&1 || EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 0 ]; then
          mv "${OUTPUT_FILE}.retry" "$OUTPUT_FILE"
          INVOKE_FAILURE_CLASS="none"
        else
          _classify_invoke_failure "$EXIT_CODE" "${OUTPUT_FILE}.retry"
          echo "invoke_antigravity: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}" >&2
        fi
        ;;
    esac
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

  INVOKE_FAILURE_CLASS="none"

  # Deterministic preflight (KTD-9), mirroring invoke_antigravity: a missing
  # binary can never succeed on retry — fail fast with the exact fix instead
  # of burning a timeout window.
  if ! command -v codex >/dev/null 2>&1; then
    echo "invoke_codex: ERROR \`codex\` (Codex CLI) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: install it (npm install -g @openai/codex or brew install codex), then run \`codex login\`. No retry (deterministic)." >&2
    INVOKE_FAILURE_CLASS="deterministic"
    return 127
  fi

  local AGENT_TOML=""
  if [ -f ".codex/agents/agents.toml" ]; then
    AGENT_TOML=".codex/agents/agents.toml"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml" ]; then
    AGENT_TOML="${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml"
  fi

  local AGENT_MODEL="" AGENT_SANDBOX="" AGENT_APPROVAL="" AGENT_INSTR_B64="" AGENT_OUTPUT_SCHEMA=""
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
  # Codex v0.128.0 removed --full-auto; supply its prior semantics (workspace-write
  # sandbox + never approve) explicitly when an agent has no overrides.
  local CMD=(codex exec)
  [ -n "$AGENT_MODEL" ]    && CMD+=(-m "$AGENT_MODEL")
  if [ -n "$AGENT_SANDBOX" ]; then
    CMD+=(-s "$AGENT_SANDBOX")
  else
    CMD+=(-s workspace-write)
  fi
  if [ -n "$AGENT_APPROVAL" ]; then
    CMD+=(-c "approval_policy=\"$AGENT_APPROVAL\"")
  else
    CMD+=(-c "approval_policy=\"never\"")
  fi

  # Hooks trust (probe CDX-04, ADR 2026-07-18-codex-hooks-under-exec): hooks
  # fire under `codex exec` when (a) the project ships .codex/hooks.json and
  # (b) --dangerously-bypass-hook-trust is passed — codex does not persist
  # project trust for arbitrary dirs, and the flag is the documented
  # automation path (0.131.0+). Triforge ships and vets these hooks itself
  # (trusted-pipeline posture, same rationale as approval_policy="never" —
  # see the security model in .claude/CLAUDE.md), so bypassing the
  # interactive trust prompt does not widen what the pipeline already accepts.
  local HOOKS_MODE="off"
  if [ -f ".codex/hooks.json" ] && _codex_feature_enabled hooks; then
    CMD+=(--dangerously-bypass-hook-trust)
    HOOKS_MODE="on"
  fi

  # Structured output (probe CDX-05): when the agent's agents.toml entry
  # carries the Triforge-level `output_schema` key, resolve the schema file
  # (project .codex/agents/ first, then the plugin's codex-agents/) and pass
  # --output-schema plus -o so the schema-valid final message lands in
  # ${OUTPUT_FILE}.last. Feature-gated only if `codex features list` carries
  # a row named like output_schema/structured_output; 0.144.4 has no such
  # row and CDX-05 proves the flag works there, so absent a row we just
  # attempt the flag.
  local SCHEMA_PATH="" SCHEMA_APPLIED=0
  if [ -n "$AGENT_OUTPUT_SCHEMA" ]; then
    local SCHEMA_GATE=1
    if _codex_feature_row_present output_schema || _codex_feature_row_present structured_output; then
      if ! _codex_feature_enabled output_schema && ! _codex_feature_enabled structured_output; then
        SCHEMA_GATE=0
        echo "invoke_codex: WARNING agent '${AGENT_NAME}' requests output_schema but codex features list reports the capability disabled — running without --output-schema" >&2
      fi
    fi
    if [ "$SCHEMA_GATE" -eq 1 ]; then
      if [ -f ".codex/agents/${AGENT_OUTPUT_SCHEMA}" ]; then
        SCHEMA_PATH=".codex/agents/${AGENT_OUTPUT_SCHEMA}"
      elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/codex-agents/${AGENT_OUTPUT_SCHEMA}" ]; then
        SCHEMA_PATH="${CLAUDE_PLUGIN_ROOT}/codex-agents/${AGENT_OUTPUT_SCHEMA}"
      else
        echo "invoke_codex: WARNING agent '${AGENT_NAME}' requests output_schema '${AGENT_OUTPUT_SCHEMA}' but no such file in .codex/agents/ or plugin codex-agents/ — running without --output-schema" >&2
      fi
    fi
  fi

  # BASE_CMD carries everything retry-safe (model pin, sandbox, approval,
  # hooks). Schema flags are first-attempt only: a schema-caused rejection
  # (e.g. 400 invalid_json_schema) would fail identically on retry, so the
  # retry drops agent augmentation — instructions prefix AND schema —
  # mirroring invoke_antigravity's retry-with-raw-prompt.
  local BASE_CMD=("${CMD[@]}")
  if [ -n "$SCHEMA_PATH" ]; then
    CMD+=(--output-schema "$SCHEMA_PATH" -o "${OUTPUT_FILE}.last")
    SCHEMA_APPLIED=1
  fi

  local FULL_PROMPT="$PROMPT"
  if [ -n "$INSTRUCTIONS" ]; then
    FULL_PROMPT="${INSTRUCTIONS}

===USER PROMPT===
${PROMPT}"
  fi

  echo "invoke_codex: agent=${AGENT_NAME} model=${AGENT_MODEL:-session-default} sandbox=${AGENT_SANDBOX:-session-default} approval=${AGENT_APPROVAL:-session-default} hooks=${HOOKS_MODE} schema=${SCHEMA_PATH:-none}" >&2

  # `< /dev/null` is mandatory: codex exec reads piped stdin ("Reading
  # additional input from stdin...") and hangs waiting for EOF whenever the
  # caller's stdin is not a TTY (probe record 2026-07-17).
  _run_with_timeout "${TIMEOUT}" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUTPUT_FILE" 2>&1 || EXIT_CODE=$?

  # KTD-9: same taxonomy as invoke_antigravity — classify before reacting;
  # only retryable failures get the retry-once-with-raw-prompt treatment.
  if [ "$EXIT_CODE" -ne 0 ]; then
    _classify_invoke_failure "$EXIT_CODE" "$OUTPUT_FILE"
    case "$INVOKE_FAILURE_CLASS" in
      deterministic)
        case "$_INVOKE_FAILURE_REASON" in
          auth)
            echo "invoke_codex: agent=${AGENT_NAME} exit=${EXIT_CODE} auth failure — codex is not logged in (output matched a credential/login pattern). Fix: run \`codex login\`. No retry (deterministic)." >&2
            ;;
          binary-missing)
            echo "invoke_codex: agent=${AGENT_NAME} exit=${EXIT_CODE} — \`codex\` disappeared from PATH mid-run. Fix: install it (npm install -g @openai/codex or brew install codex), then run \`codex login\`. No retry (deterministic)." >&2
            ;;
          *)
            echo "invoke_codex: agent=${AGENT_NAME} exit=${EXIT_CODE} deterministic failure (${_INVOKE_FAILURE_REASON:-see error above}). No retry." >&2
            ;;
        esac
        return "$EXIT_CODE"
        ;;
      timeout)
        echo "invoke_codex: agent=${AGENT_NAME} timed out after ${TIMEOUT}s (exit=${EXIT_CODE}). Requeue policy belongs to the caller (lease layer), not this helper." >&2
        return "$EXIT_CODE"
        ;;
      retryable)
        echo "invoke_codex: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable), retrying with raw prompt" >&2
        EXIT_CODE=0
        SCHEMA_APPLIED=0
        _run_with_timeout "${TIMEOUT}" "${BASE_CMD[@]}" "$PROMPT" < /dev/null > "${OUTPUT_FILE}.retry" 2>&1 || EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 0 ]; then
          mv "${OUTPUT_FILE}.retry" "$OUTPUT_FILE"
          INVOKE_FAILURE_CLASS="none"
        else
          _classify_invoke_failure "$EXIT_CODE" "${OUTPUT_FILE}.retry"
          echo "invoke_codex: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}" >&2
        fi
        ;;
    esac
  fi

  # Structured-verdict capture: validate the schema-constrained last message
  # as JSON; valid → pretty-printed to ${OUTPUT_FILE}.verdict.json, invalid →
  # warn and leave the raw output as the source of truth.
  if [ "$EXIT_CODE" -eq 0 ] && [ "$SCHEMA_APPLIED" -eq 1 ]; then
    if [ -f "${OUTPUT_FILE}.last" ] && VERDICT_IN="${OUTPUT_FILE}.last" VERDICT_OUT="${OUTPUT_FILE}.verdict.json" python3 -c "
import json, os
with open(os.environ['VERDICT_IN']) as f:
    data = json.load(f)
with open(os.environ['VERDICT_OUT'], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\\n')
" 2>/dev/null; then
      echo "invoke_codex: structured verdict captured (${OUTPUT_FILE}.verdict.json)" >&2
    else
      echo "invoke_codex: WARNING --output-schema was passed but ${OUTPUT_FILE}.last is missing or not valid JSON — raw output ${OUTPUT_FILE} stays the source of truth" >&2
    fi
  fi

  return $EXIT_CODE
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Distinct return code for "no timeout tool on PATH" (fail-closed preflight).
# Deliberately outside the codes agy/codex/timeout(1) use (1, 124, 125-127).
_RC_NO_TIMEOUT_TOOL=96

# Run a command under timeout enforcement. macOS lacks `timeout` by default;
# try `gtimeout` from coreutils. Fail-closed (R1): when neither is on PATH we
# refuse to run the command at all and return _RC_NO_TIMEOUT_TOOL — the old
# run-without-enforcement fallback let a hung Antigravity/Codex process block
# a pipeline indefinitely.
_run_with_timeout() {
  local SECS=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${SECS}s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${SECS}s" "$@"
  else
    echo "invoke-external.sh: ERROR neither \`timeout\` nor \`gtimeout\` is on PATH — refusing to run \`${1:-}\` without timeout enforcement (fail-closed). Fix: on macOS run \`brew install coreutils\`, then retry." >&2
    return "$_RC_NO_TIMEOUT_TOOL"
  fi
}

# Classify a failed external-CLI invocation (KTD-9). Shared so future per-CLI
# helpers reuse one taxonomy instead of reinventing bare retry-once. Sets:
#   INVOKE_FAILURE_CLASS    deterministic | timeout | retryable
#   _INVOKE_FAILURE_REASON  binary-missing | timeout-tool-missing | auth | ""
# Args: <exit-code> [output-file] — the output file is scanned for
# auth-shaped patterns when present.
_classify_invoke_failure() {
  local RC=$1
  local OUT=${2:-}
  _INVOKE_FAILURE_REASON=""
  if [ "$RC" -eq 124 ] || [ "$RC" -eq 137 ]; then
    # 124 = timeout(1) expiry; 137 = 128+SIGKILL (timeout -k or hard kill).
    INVOKE_FAILURE_CLASS="timeout"
  elif [ "$RC" -eq 127 ]; then
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="binary-missing"
  elif [ "$RC" -eq "$_RC_NO_TIMEOUT_TOOL" ] && ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="timeout-tool-missing"
  elif [ -n "$OUT" ] && [ -f "$OUT" ] && grep -qiE 'not logged in|login required|unauthorized|401|credential|authentication (failed|required|expired)' "$OUT" 2>/dev/null; then
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="auth"
  else
    INVOKE_FAILURE_CLASS="retryable"
  fi
}

# Raw `agy agents` listing (native agents come from installed agy plugins
# only; header "Available agents:" then names, empty by default). 10s cap,
# tolerant: any failure — including fail-closed timeout preflight — yields an
# empty listing so mode resolution falls through to injection/raw.
# NO flags here (probed 2026-07-17 on agy 1.1.3): `agy agents` rejects
# --model/--add-dir ("flags provided but not defined") and exits 1 with empty
# stdout, which silently disabled native matching forever. The AE2 model-pin
# rule covers session commands; this metadata query cannot carry the flag.
_agy_agents_listing() {
  command -v agy >/dev/null 2>&1 || return 0
  _run_with_timeout 10 agy agents 2>/dev/null || true
}

# List known Antigravity agent names: plugin injection templates plus whatever
# `agy agents` reports (first token per name line; the "Available agents:"
# header is dropped).
_list_antigravity_agents() {
  {
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents" ]; then
      for f in "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents"/*.md; do
        [ -f "$f" ] && basename "$f" .md
      done 2>/dev/null
    fi
    _agy_agents_listing | awk 'NF > 0 && $0 !~ /^Available agents:/ {print $1}'
  } | sort -u
}

# --- Codex runtime feature detection (probe CDX-02) -----------------------
# `codex features list` emits rows like:
#   hooks                                stable             true
# Capability decisions come from this matrix at runtime — never from
# version-string reasoning. The listing runs ONCE per session: the first call
# caches it (keyed on $$, which bash keeps at the original shell's PID even
# in background subshells) and later calls grep the cache.

_CODEX_FEATURES_CACHE="${TMPDIR:-/tmp}/codex_features_$$.txt"

# Populate the cache on first use. Tolerant: a missing binary returns 1
# (features treated as absent); a failed listing leaves an empty cache file
# so the (slow) listing is still attempted only once per session.
_codex_features_cache_fill() {
  [ -f "$_CODEX_FEATURES_CACHE" ] && return 0
  command -v codex >/dev/null 2>&1 || return 1
  _run_with_timeout 20 codex features list > "$_CODEX_FEATURES_CACHE" 2>/dev/null || true
}

# True (0) when the named feature row exists AND its enabled column is `true`.
_codex_feature_enabled() {
  local FLAG=$1
  _codex_features_cache_fill || return 1
  grep -E "^${FLAG}[[:space:]]" "$_CODEX_FEATURES_CACHE" 2>/dev/null | grep -qE "[[:space:]]true[[:space:]]*$"
}

# True (0) when a row for the named feature exists at all (any stage/state).
# Lets callers distinguish "feature explicitly disabled" from "feature not in
# the matrix" (in which case flags are attempted rather than gated).
_codex_feature_row_present() {
  local FLAG=$1
  _codex_features_cache_fill || return 1
  grep -qE "^${FLAG}[[:space:]]" "$_CODEX_FEATURES_CACHE" 2>/dev/null
}

# Emit bash variable assignments extracted from a Codex agents.toml entry.
# Outputs:
#   AGENT_MODEL=<string>
#   AGENT_SANDBOX=<string>
#   AGENT_APPROVAL=<string>
#   AGENT_INSTR_B64=<base64 string>
#   AGENT_OUTPUT_SCHEMA=<string>   (Triforge-level key; schema file name)
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
        sys.stderr.write('invoke-external.sh: Codex agent config extraction failed; using session defaults. Install Python 3.11+ (for tomllib) or run: pip install tomli\\n')
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
print('AGENT_OUTPUT_SCHEMA=' + json.dumps(agent.get('output_schema', '')))
"
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

# ---------------------------------------------------------------------------
# Roster resolution (KTD-2) — ops/roster.toml decides who does what
# ---------------------------------------------------------------------------

# resolve_role <role> — map a task-type role (builder | reviewer | tester |
# analyst | documenter) to the member that should handle it right now.
# Prints one line on success:   cli<TAB>model<TAB>effort
# (builder's model field is empty by design — the Claude lane resolves its
# model via the downgrade ladder, not the roster).
#
# Sources of truth, in order: ops/roster.toml when present, overlaid
# PER-FIELD onto built-in defaults — a role overriding only effort keeps the
# default cli + model; no roster file at all resolves to the shipped
# builder-pool posture. Load-time validation runs on EVERY load, not just for
# the requested role:
#   - unknown role / CLI / member names are rejected (typo guard)
#   - each role's chain ([cli] + fallbacks) must terminate at a core-trio
#     member — a chain resolving entirely to optional members cannot ship
#   - [members.<core-trio>] enabled=false is rejected (cannot be disabled)
# The resolution walk tries the primary cli, then fallbacks in order; a
# member is SKIPPED when its binary is absent from PATH or its
# [members.<cli>] entry says enabled=false (R38: disabled = absent
# everywhere). Optional-member skips are silent (AE1); a skipped core member
# logs a degradation warning; an absent core-trio terminus is a hard error
# with install guidance (R21) — the only way a validated chain can exhaust.
#
# Distinct exit codes so callers can react without parsing stderr:
#   2 unknown role requested    3 no TOML parser     4 malformed roster.toml
#   5 roster validation failed  6 chain exhausted (core terminus binary absent)
resolve_role() {
  local ROLE=${1:?usage: resolve_role <role>}
  ROLE="$ROLE" ROSTER_FILE="ops/roster.toml" python3 -c "
import os, shutil, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('resolve_role: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

# Built-in defaults — the single source of truth in this function; mirrors
# templates/ops/roster.toml (keep the two in sync). builder model '' means:
# resolved by the Claude downgrade ladder, never by the roster.
DEFAULTS = {
    'builder':    {'cli': 'claude',      'model': '',                      'effort': 'max',   'fallbacks': ['codex', 'antigravity']},
    'reviewer':   {'cli': 'codex',       'model': 'gpt-5.6-sol',           'effort': 'xhigh', 'fallbacks': ['antigravity', 'claude']},
    'tester':     {'cli': 'codex',       'model': 'gpt-5.6-sol',           'effort': 'xhigh', 'fallbacks': ['claude']},
    'analyst':    {'cli': 'antigravity', 'model': 'Gemini 3.1 Pro (High)', 'effort': 'high',  'fallbacks': ['claude']},
    'documenter': {'cli': 'antigravity', 'model': 'Gemini 3.1 Pro (High)', 'effort': 'high',  'fallbacks': ['claude']},
}
CORE_TRIO = ('claude', 'antigravity', 'codex')
# cli name -> binary looked up on PATH
BINARY = {'claude': 'claude', 'antigravity': 'agy', 'codex': 'codex',
          'opencode': 'opencode', 'kimi': 'kimi', 'cursor': 'cursor-agent'}
# Shipped per-CLI default model, used when a member is reached via fallback
# or chosen as an overridden primary with no explicit role model (KTD-8
# session-settled pins: never a Flash variant for agy, never Auto for
# cursor). A [members.<cli>].model entry overrides the shipped default.
CLI_DEFAULT_MODEL = {
    'claude': '',
    'antigravity': 'Gemini 3.1 Pro (High)',
    'codex': 'gpt-5.6-sol',
    'opencode': 'openrouter/z-ai/glm-5.2',
    'kimi': 'kimi-k3',
    'cursor': 'grok-4.5',
}
# G12-style install/login guidance (R21), matching the invoke_* wording.
INSTALL_FIX = {
    'claude': 'install Claude Code (npm install -g @anthropic-ai/claude-code), then run claude once and /login',
    'antigravity': 'install it (curl -fsSL https://antigravity.google/cli/install.sh | bash), then run agy interactively once to complete login',
    'codex': 'install it (npm install -g @openai/codex or brew install codex), then run codex login',
}

path = os.environ.get('ROSTER_FILE', 'ops/roster.toml')
roster = {}
if os.path.isfile(path):
    try:
        with open(path, 'rb') as f:
            roster = tomllib.load(f)
    except tomllib.TOMLDecodeError as exc:
        # TOMLDecodeError text names the line ('... at line N, column M').
        sys.stderr.write('resolve_role: ERROR malformed ' + path + ': ' + str(exc) + '\n')
        sys.exit(4)

user_roles = roster.get('roles', {})
user_roles = user_roles if isinstance(user_roles, dict) else {}
members = roster.get('members', {})
members = members if isinstance(members, dict) else {}

def reject(msg):
    sys.stderr.write('resolve_role: ERROR invalid ' + path + ': ' + msg + '\n')
    sys.exit(5)

# --- Load-time validation (every load, all roles) --------------------------
for name in user_roles:
    if name not in DEFAULTS:
        reject('unknown role ' + repr(name) + ' (valid: ' + ', '.join(DEFAULTS) + ')')
for name, entry in members.items():
    if name not in BINARY:
        reject('unknown member ' + repr(name) + ' (known CLIs: ' + ', '.join(BINARY) + ')')
    if name in CORE_TRIO and isinstance(entry, dict) and entry.get('enabled') is False:
        reject('[members.' + name + '] enabled = false — the core trio cannot be disabled')

merged = {}
for name, dflt in DEFAULTS.items():
    entry = dict(dflt)
    user = user_roles.get(name, {})
    user = user if isinstance(user, dict) else {}
    for field in ('cli', 'model', 'effort', 'fallbacks'):
        if field in user:
            entry[field] = user[field]
    entry['user_model'] = 'model' in user
    if not isinstance(entry['cli'], str):
        reject('role ' + repr(name) + ': cli must be a string')
    if not isinstance(entry['fallbacks'], list) or not all(isinstance(x, str) for x in entry['fallbacks']):
        reject('role ' + repr(name) + ': fallbacks must be an array of CLI names')
    chain = [entry['cli']] + list(entry['fallbacks'])
    for cli in chain:
        if cli not in BINARY:
            reject('role ' + repr(name) + ' names unknown CLI ' + repr(cli) + ' (known: ' + ', '.join(BINARY) + ')')
    if chain[-1] not in CORE_TRIO:
        reject('role ' + repr(name) + ' fallback chain ' + repr(chain) + ' does not terminate at a core-trio member (claude, antigravity, codex) — a chain resolving entirely to optional members cannot ship')
    merged[name] = entry

# --- Resolution walk -------------------------------------------------------
role = os.environ.get('ROLE', '')
if role not in merged:
    sys.stderr.write('resolve_role: ERROR unknown role ' + repr(role) + ' (valid: ' + ', '.join(DEFAULTS) + ')\n')
    sys.exit(2)
entry = merged[role]
chain = [entry['cli']] + list(entry['fallbacks'])
for idx, cli in enumerate(chain):
    m = members.get(cli, {})
    m = m if isinstance(m, dict) else {}
    if m.get('enabled') is False:
        continue          # disabled = absent everywhere (R38); silent skip
    if shutil.which(BINARY[cli]) is None:
        if idx == len(chain) - 1:
            break         # core-trio terminus absent -> hard error below
        if cli in CORE_TRIO:
            sys.stderr.write('resolve_role: WARNING core member ' + repr(cli) + ' (binary ' + BINARY[cli] + ') absent — role ' + repr(role) + ' degrades to the next fallback\n')
        continue          # optional-member skip is silent (AE1)
    if idx == 0 and (entry['user_model'] or cli == DEFAULTS[role]['cli']):
        model = entry['model']      # explicit role model, or default primary
    else:
        model = m.get('model', '') or CLI_DEFAULT_MODEL[cli]
    print(cli + '\t' + str(model) + '\t' + str(entry['effort']))
    sys.exit(0)

terminus = chain[-1]
sys.stderr.write('resolve_role: ERROR role ' + repr(role) + ' chain exhausted — core-trio terminus ' + repr(terminus) + ' (binary ' + BINARY[terminus] + ') is not on PATH. Fix: ' + INSTALL_FIX[terminus] + '. No retry (deterministic).\n')
sys.exit(6)
"
}

# Cache file for ensure_core_trio_live — bash keeps $$ at the sourcing
# shell's PID even in subshells, so one successful probe covers the session.
_TRIO_LIVE_CACHE="${TMPDIR:-/tmp}/triforge_trio_live_$$"

# ensure_core_trio_live — lazy liveness gate for the build/review paths.
# Fast NON-MODEL checks only: command -v plus a 15s <cli> --version under
# _run_with_timeout (fail-closed) — no tokens spent, no login round-trips.
# Success is cached in _TRIO_LIVE_CACHE so repeat calls are free; failures
# are re-probed each call so a mid-session fix is picked up.
# NOT called at session start — a /status-only session must never trigger
# it. Call sites live in the /build and /review preambles.
# On failure: hard error listing exactly which member failed and its
# install/login fix (KTD-9 wording), return 1.
ensure_core_trio_live() {
  [ -f "$_TRIO_LIVE_CACHE" ] && return 0
  local FAILED=0
  local PAIR NAME BIN FIX
  for PAIR in "claude:claude" "antigravity:agy" "codex:codex"; do
    NAME=${PAIR%%:*}
    BIN=${PAIR##*:}
    case "$NAME" in
      claude)      FIX="install Claude Code (npm install -g @anthropic-ai/claude-code), then run \`claude\` once and /login" ;;
      antigravity) FIX="install it (curl -fsSL https://antigravity.google/cli/install.sh | bash), then run \`agy\` interactively once to complete login" ;;
      codex)       FIX="install it (npm install -g @openai/codex or brew install codex), then run \`codex login\`" ;;
    esac
    if ! command -v "$BIN" >/dev/null 2>&1; then
      echo "ensure_core_trio_live: ERROR core member ${NAME} — \`${BIN}\` not found on PATH. Fix: ${FIX}. No retry (deterministic)." >&2
      FAILED=1
    elif ! _run_with_timeout 15 "$BIN" --version >/dev/null; then
      # stderr stays visible so the fail-closed timeout-tool message (or the
      # CLI's own complaint) names the real cause, not a generic wrapper line.
      echo "ensure_core_trio_live: ERROR core member ${NAME} — \`${BIN} --version\` failed its 15s liveness check (broken install or hung binary). Fix: ${FIX}. No retry (deterministic)." >&2
      FAILED=1
    fi
  done
  if [ "$FAILED" -ne 0 ]; then
    echo "ensure_core_trio_live: the core trio (claude, antigravity/agy, codex) must be live before /build or /review can dispatch — see fixes above." >&2
    return 1
  fi
  : > "$_TRIO_LIVE_CACHE"
  return 0
}
