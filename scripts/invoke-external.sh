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
# OpenCode invocation (optional tier — builder + reviewer on OpenRouter)
# ---------------------------------------------------------------------------
#
# OpenCode has a real `--agent <name>` flag (unlike Codex) that selects a
# markdown agent def from `.opencode/agents/` (project tier) or, via the
# session-start bootstrap, the plugin's `opencode-agents/`. Every call pins the
# model with -m "${OPENCODE_MODEL:-openrouter/z-ai/glm-5.2}" — OPENCODE_MODEL is
# the roster override hook; the shipped default is the OpenRouter GLM.
#
# Structured capture (probe OC-03): `--format json` streams SSE-style events
# (message.updated carries the message role via properties.info; message.part.updated
# carries a TextPart with the assistant's text; session.error carries failures —
# the opencode SDK event union). The assistant reply is the concatenation of its
# non-synthetic TextPart.text values; a python3 parser extracts it into
# OUTPUT_FILE (no literal backticks in the heredoc). On any parse failure the
# raw stream is preserved so nothing is lost.
#
# NEVER --auto (probe OC-06, 2026-07-17): a deny rule in opencode.json did NOT
# survive --auto (the denied command executed), so this helper never passes it.
# Reviewer read-only safety is the agent-def permission map (opencode-agents/
# reviewer.md denies edit/bash); builder confinement is the lease worktree +
# _adapter_env allowlist (R35), never opencode.json denies.
#
# Effort (probe OC-05, unproven): a non-empty effort maps to --variant <effort>
# (provider-specific reasoning effort). Best-effort — if the first attempt fails
# with the variant set, the single KTD-9 retry drops it.
#
# Failure taxonomy (KTD-9): reuses _classify_invoke_failure exactly like the
# other helpers, plus two deterministic preflights of its own (missing binary;
# OpenRouter provider not connected) so a call that cannot succeed fails fast
# with the exact fix instead of a retry-storm.
#
# invoke_opencode <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
invoke_opencode() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/opencode_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${OPENCODE_EFFORT:-}}
  local MODEL="${OPENCODE_MODEL:-openrouter/z-ai/glm-5.2}"
  local MODE="" EXIT_CODE=0
  local RAW="${OUTPUT_FILE}.raw"

  INVOKE_FAILURE_CLASS="none"
  _INVOKE_FAILURE_REASON=""

  # Deterministic preflight 1 (KTD-9): a missing binary can never succeed on
  # retry — fail fast with the exact fix instead of burning a timeout window.
  if ! command -v opencode >/dev/null 2>&1; then
    echo "invoke_opencode: ERROR \`opencode\` (OpenCode CLI) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: install it (curl -fsSL https://opencode.ai/install | bash). No retry (deterministic)." >&2
    # Write the guidance to OUTPUT_FILE too: a caller (e.g. a review fan-out)
    # that only reads the file must not mistake an empty file for "no findings"
    # (the exact trap CLAUDE.md warns about).
    echo "invoke_opencode: opencode CLI not on PATH — install: curl -fsSL https://opencode.ai/install | bash" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="binary-missing"
    return 127
  fi

  # Deterministic preflight 2 (KTD-9): an openrouter/* model needs a connected
  # OpenRouter provider — either OPENROUTER_API_KEY, or a credential from
  # `opencode auth login`. Probes OC-02/OC-04: the call fails hard when it is
  # not connected, and that failure is deterministic. Detect it up front
  # (mirrors roster_member_auth) and fail fast with the exact fix rather than
  # running + retrying a call we know cannot succeed. Only openrouter is
  # preflighted (its fix string is known); a working override
  # (OPENCODE_MODEL=<connected-provider>/<model>) skips this entirely.
  case "$MODEL" in
    openrouter/*)
      if [ -z "${OPENROUTER_API_KEY:-}" ] && ! _run_with_timeout 15 opencode auth list 2>/dev/null | grep -qi 'openrouter'; then
        echo "invoke_opencode: ERROR agent='${AGENT_NAME}' model='${MODEL}' — the OpenRouter provider is not connected (no OPENROUTER_API_KEY, and \`opencode auth list\` does not name it). Fix: set OPENROUTER_API_KEY or run: opencode auth login. No retry (deterministic)." >&2
        # Guidance to OUTPUT_FILE too (see binary-missing note above) so a
        # captured-only caller does not read the empty file as "no findings".
        echo "invoke_opencode: OpenRouter provider not connected for model '${MODEL}' — set OPENROUTER_API_KEY or run: opencode auth login" > "$OUTPUT_FILE" 2>/dev/null || true
        INVOKE_FAILURE_CLASS="deterministic"
        _INVOKE_FAILURE_REASON="auth"
        return 1
      fi
      ;;
  esac

  # Agent resolution: project .opencode/agents/<name>.md first, then the plugin
  # opencode-agents/<name>.md -> --agent <name>; else raw with a warning naming
  # the available agents. An empty AGENT_NAME is a deliberate raw run (used by
  # the READY plumbing probe and lease_dispatch's direct builder command).
  local BASE=(opencode run --format json -m "$MODEL")
  local CMD=("${BASE[@]}")
  if [ -n "$AGENT_NAME" ] && { [ -f ".opencode/agents/${AGENT_NAME}.md" ] || { [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/opencode-agents/${AGENT_NAME}.md" ]; }; }; then
    CMD+=(--agent "$AGENT_NAME")
    MODE="agent"
  elif [ -n "$AGENT_NAME" ]; then
    local AVAILABLE
    AVAILABLE=$(_list_opencode_agents | paste -sd, - 2>/dev/null || echo "")
    echo "invoke_opencode: WARNING agent '${AGENT_NAME}' not found in .opencode/agents/ or plugin opencode-agents/; falling through to raw prompt (no agent applied). Available agents: ${AVAILABLE:-<none>}" >&2
    MODE="raw"
  else
    MODE="raw"
  fi

  # Effort -> --variant (OC-05 best-effort); first attempt only.
  local ATTEMPT=("${CMD[@]}")
  [ -n "$EFFORT" ] && ATTEMPT+=(--variant "$EFFORT")

  echo "invoke_opencode: agent=${AGENT_NAME:-<none>} mode=${MODE} model=${MODEL} effort=${EFFORT:-none}" >&2

  # No --auto, ever (OC-06). Reviewer safety is the agent-def permission map.
  _run_with_timeout "${TIMEOUT}" "${ATTEMPT[@]}" "$PROMPT" > "$RAW" 2>&1 || EXIT_CODE=$?

  if [ "$EXIT_CODE" -ne 0 ]; then
    _classify_invoke_failure "$EXIT_CODE" "$RAW"
    # OpenCode surfaces an OpenRouter provider/auth failure as a
    # ProviderAuthError / session.error in the JSON stream (or a plain
    # "provider not found") that the shared classifier cannot recognize —
    # promote those to deterministic auth so we do not retry a doomed call.
    if [ "$INVOKE_FAILURE_CLASS" = "retryable" ] && grep -qiE 'provider not found|ProviderAuthError|OPENROUTER_API_KEY|no such provider' "$RAW" 2>/dev/null; then
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="auth"
    fi
    case "$INVOKE_FAILURE_CLASS" in
      deterministic)
        case "$_INVOKE_FAILURE_REASON" in
          auth)
            echo "invoke_opencode: agent=${AGENT_NAME} exit=${EXIT_CODE} auth failure — the OpenRouter provider is not connected. Fix: set OPENROUTER_API_KEY or run: opencode auth login. No retry (deterministic)." >&2
            ;;
          binary-missing)
            echo "invoke_opencode: agent=${AGENT_NAME} exit=${EXIT_CODE} — \`opencode\` disappeared from PATH mid-run. Fix: install it (curl -fsSL https://opencode.ai/install | bash). No retry (deterministic)." >&2
            ;;
          *)
            echo "invoke_opencode: agent=${AGENT_NAME} exit=${EXIT_CODE} deterministic failure (${_INVOKE_FAILURE_REASON:-see error above}). No retry." >&2
            ;;
        esac
        cp "$RAW" "$OUTPUT_FILE" 2>/dev/null || true
        rm -f "$RAW"
        return "$EXIT_CODE"
        ;;
      timeout)
        echo "invoke_opencode: agent=${AGENT_NAME} timed out after ${TIMEOUT}s (exit=${EXIT_CODE}). Requeue policy belongs to the caller (lease layer), not this helper." >&2
        cp "$RAW" "$OUTPUT_FILE" 2>/dev/null || true
        rm -f "$RAW"
        return "$EXIT_CODE"
        ;;
      retryable)
        # Single retry: raw prompt, no --agent, and — per OC-05 — no --variant.
        echo "invoke_opencode: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable), retrying once with raw prompt${EFFORT:+ (dropping --variant ${EFFORT})}" >&2
        EXIT_CODE=0
        _run_with_timeout "${TIMEOUT}" "${BASE[@]}" "$PROMPT" > "${RAW}.retry" 2>&1 || EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 0 ]; then
          mv "${RAW}.retry" "$RAW"
          INVOKE_FAILURE_CLASS="none"
        else
          _classify_invoke_failure "$EXIT_CODE" "${RAW}.retry"
          echo "invoke_opencode: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}" >&2
          cp "${RAW}.retry" "$OUTPUT_FILE" 2>/dev/null || true
          rm -f "$RAW" "${RAW}.retry"
          return "$EXIT_CODE"
        fi
        ;;
    esac
  fi

  # Structured capture (success path): extract the assistant's final text from
  # the JSON event stream into OUTPUT_FILE. Parser keeps the latest text per
  # part id (message.part.updated carries the full part text as it grows),
  # concatenates the assistant's non-synthetic text parts in order, and exits
  # nonzero when it finds none — in which case the raw stream is preserved.
  if OC_RAW="$RAW" OC_OUT="$OUTPUT_FILE" python3 -c '
import json, os, sys
raw = open(os.environ["OC_RAW"], "r", errors="replace").read()

def iter_events(text):
    text = text.strip()
    if not text:
        return
    try:
        obj = json.loads(text)
        if isinstance(obj, list):
            for e in obj:
                yield e
            return
        if isinstance(obj, dict):
            yield obj
            return
    except Exception:
        pass
    ok = False
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            yield json.loads(line)
            ok = True
        except Exception:
            continue
    if ok:
        return
    dec = json.JSONDecoder()
    i, n = 0, len(text)
    while i < n:
        while i < n and text[i] not in "{[":
            i += 1
        if i >= n:
            break
        try:
            val, end = dec.raw_decode(text, i)
            yield val
            i = end
        except Exception:
            i += 1

roles = {}
parts = {}
order = 0
for ev in iter_events(raw):
    if not isinstance(ev, dict):
        continue
    props = ev.get("properties") if isinstance(ev.get("properties"), dict) else ev
    info = props.get("info") if isinstance(props, dict) else None
    if isinstance(info, dict) and info.get("id") is not None:
        roles[info.get("id")] = info.get("role")
    part = props.get("part") if isinstance(props, dict) else None
    if not isinstance(part, dict) and ev.get("type") == "text" and "text" in ev:
        part = ev
    if isinstance(part, dict) and part.get("type") == "text" and isinstance(part.get("text"), str):
        pid = part.get("id") or ("_%d" % order)
        prev = parts.get(pid)
        o = prev[0] if prev else order
        parts[pid] = (o, part.get("text"), part.get("messageID"), bool(part.get("synthetic")))
        if not prev:
            order += 1

def collect(pred):
    return "".join(t for (_, t, mid, syn) in
                   sorted(parts.values(), key=lambda x: x[0]) if pred(mid, syn))

text = collect(lambda mid, syn: roles.get(mid) == "assistant" and not syn)
if not text.strip():
    text = collect(lambda mid, syn: roles.get(mid) == "assistant")
if not text.strip():
    text = collect(lambda mid, syn: not syn)
if not text.strip():
    text = collect(lambda mid, syn: True)

if not text.strip():
    sys.stderr.write("no assistant text part found in opencode JSON stream\n")
    sys.exit(3)

with open(os.environ["OC_OUT"], "w") as f:
    f.write(text.strip() + "\n")
' 2>/dev/null; then
    :
  else
    echo "invoke_opencode: WARNING could not extract assistant text from opencode JSON stream — preserving raw stream in ${OUTPUT_FILE}" >&2
    cp "$RAW" "$OUTPUT_FILE" 2>/dev/null || true
  fi
  rm -f "$RAW" "${RAW}.retry"
  return $EXIT_CODE
}

# List known OpenCode agent names: project .opencode/agents/ plus the plugin
# opencode-agents/ templates (basename without .md), deduped.
_list_opencode_agents() {
  {
    if [ -d ".opencode/agents" ]; then
      for f in .opencode/agents/*.md; do
        [ -f "$f" ] && basename "$f" .md
      done 2>/dev/null
    fi
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/opencode-agents" ]; then
      for f in "${CLAUDE_PLUGIN_ROOT}/opencode-agents"/*.md; do
        [ -f "$f" ] && basename "$f" .md
      done 2>/dev/null
    fi
  } | sort -u
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
#   5 roster validation failed  6 chain exhausted (core terminus binary absent
#                                 or every remaining member excluded)
#
# RESOLVE_ROLE_EXCLUDE (comma-separated cli names): members skipped during
# the walk as if absent — the lease layer's requeue hook (KTD-9: requeue
# goes to a DIFFERENT builder, so lease_requeue excludes previous_builder).
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
exclude = set(x for x in os.environ.get('RESOLVE_ROLE_EXCLUDE', '').split(',') if x)
for idx, cli in enumerate(chain):
    if cli in exclude:
        continue          # requeue hook (KTD-9): walk past the failed builder
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
if terminus in exclude:
    sys.stderr.write('resolve_role: ERROR role ' + repr(role) + ' chain exhausted — every remaining member is excluded (RESOLVE_ROLE_EXCLUDE=' + repr(','.join(sorted(exclude))) + ', the requeue hook walking past a failed builder). No alternative builder available.\n')
    sys.exit(6)
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

# ---------------------------------------------------------------------------
# Lease lifecycle (KTD-4) — the builder pool's spine
# ---------------------------------------------------------------------------
#
# Every non-lead build runs under a per-task lease in an isolated git
# worktree (R8, R20, R35). The ledger at ops/leases.toml is LEAD-OWNED and
# single-writer (KTD-4): builders NEVER write it — status flows back through
# the captured exit code and KTD-9 class the launcher drops beside the
# output file (<out>.rc / <out>.class). Runtime state, gitignored.
#
# State machine (mirrors the plan's lease lifecycle diagram):
#
#   [*] -> leased -> building -> review -> merged -> [*]
#              ^         |          |
#              |         |          +-> building   findings, cycle < 3 (U10)
#              |         |          +-> escalated  cycle 3 / no non-author reviewer
#              |         +-> orphaned   heartbeat expiry or silent death
#              |         |       +-> requeued   worktree pruned; once (KTD-9)
#              |         |       +-> escalated  second failure
#              |         +-> failed     deterministic (auth / absent CLI)
#              |                 +-> escalated  fail fast with guidance, no requeue
#              +-------- requeued (re-leased to a DIFFERENT builder)
#
# Confinement (KTD-3, KTD-14, R35): builders never read or write the
# canonical ops/ tree — required context is injected into the dispatch
# prompt; the builder runs with cwd = its worktree under a per-adapter env
# allowlist (_adapter_env) so no cross-provider credential leaks; shared-file
# mutations happen lead-side at collect/merge time on the main tree.

# Repo root of the MAIN checkout (lease functions are lead-side and run from
# the main tree, never from inside a worktree).
_lease_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# BSD-portable realpath (no readlink -f on stock macOS).
_lease_realpath() {
  RP_TARGET="$1" python3 -c "
import os
print(os.path.realpath(os.environ['RP_TARGET']))
"
}

# Lease root: TRIFORGE_LEASE_ROOT override, else
# ${TMPDIR:-/tmp}/triforge-leases/<repo-basename>-<git-hash-of-repo-root-path>
# (the hash is of the canonical root path STRING, so two checkouts of one
# repo get distinct roots). Created, then canonicalized before printing —
# every stored worktree path is canonical from birth, which is what lets
# lease_reclaim compare stored vs canonical byte-for-byte.
_lease_root() {
  local ROOT REPO
  REPO=$(_lease_repo_root) || { echo "lease: ERROR not inside a git repository — worktree leases require one (outside git the builder pool degrades to lead-only in-place execution)." >&2; return 1; }
  REPO=$(_lease_realpath "$REPO")
  if [ -n "${TRIFORGE_LEASE_ROOT:-}" ]; then
    ROOT="$TRIFORGE_LEASE_ROOT"
  else
    local BASE HASH
    BASE=$(basename "$REPO")
    HASH=$(printf '%s' "$REPO" | git hash-object --stdin | cut -c1-12)
    ROOT="${TMPDIR:-/tmp}"
    ROOT="${ROOT%/}/triforge-leases/${BASE}-${HASH}"
  fi
  mkdir -p "$ROOT" || return 1
  _lease_realpath "$ROOT"
}

_lease_ledger_path() {
  local REPO
  REPO=$(_lease_repo_root) || return 1
  printf '%s\n' "${REPO}/ops/leases.toml"
}

# task_id doubles as a directory and branch component — constrain it before
# it can constrain us (first char alphanumeric, then [A-Za-z0-9._-]).
_lease_valid_task_id() {
  case "$1" in
    ""|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# _ledger_update <task_id> key=value...
# The ONLY writer of ops/leases.toml (KTD-4). Read-modify-write: parse with
# tomllib (read-only stdlib), apply updates, re-serialize with a small flat
# emitter (values stay flat strings/ints so the round trip is trivial),
# round-trip-verify the tmp file, then atomic tmp+mv. `updated` is stamped
# on every call. Int keys: pid, created, updated, heartbeat_deadline,
# requeue_count.
_ledger_update() {
  local TASK_ID=$1
  shift
  local LEDGER
  LEDGER=$(_lease_ledger_path) || return 1
  mkdir -p "$(dirname "$LEDGER")"
  LEDGER_FILE="$LEDGER" LEDGER_TASK="$TASK_ID" python3 -c "
import json, os, sys, time
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('_ledger_update: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

path = os.environ['LEDGER_FILE']
task = os.environ['LEDGER_TASK']
data = {}
if os.path.isfile(path):
    with open(path, 'rb') as f:
        data = tomllib.load(f)
leases = data.get('lease', {})
leases = leases if isinstance(leases, dict) else {}
row = dict(leases.get(task, {})) if isinstance(leases.get(task, {}), dict) else {}
INT_KEYS = ('pid', 'created', 'updated', 'heartbeat_deadline', 'requeue_count')
for arg in sys.argv[1:]:
    k, sep, v = arg.partition('=')
    if not sep or not k:
        sys.stderr.write('_ledger_update: ERROR malformed update ' + repr(arg) + ' (want key=value)\n')
        sys.exit(2)
    if k in INT_KEYS:
        try:
            row[k] = int(v)
        except ValueError:
            sys.stderr.write('_ledger_update: ERROR ' + k + ' must be an integer, got ' + repr(v) + '\n')
            sys.exit(2)
    else:
        row[k] = str(v)
row['updated'] = int(time.time())
leases[task] = row

# Flat serializer: only ints, bools, and strings ever land in a row.
# json.dumps escaping is valid TOML for basic strings and quoted keys.
lines = ['# ops/leases.toml — lead-owned lease ledger (KTD-4). Runtime state,',
         '# gitignored. Single writer: the lead, via _ledger_update in',
         '# scripts/invoke-external.sh. Builders never write this file.',
         '']
for t in sorted(leases):
    r = leases[t]
    if not isinstance(r, dict):
        continue
    lines.append('[lease.' + json.dumps(str(t)) + ']')
    for k in sorted(r):
        v = r[k]
        if isinstance(v, bool):
            lines.append(k + ' = ' + ('true' if v else 'false'))
        elif isinstance(v, int):
            lines.append(k + ' = ' + str(v))
        else:
            lines.append(k + ' = ' + json.dumps(str(v)))
    lines.append('')

tmp = path + '.tmp.' + str(os.getpid())
with open(tmp, 'w') as f:
    f.write('\n'.join(lines))
# The ledger MUST stay tomllib-parseable after every transition: verify the
# tmp file round-trips BEFORE it replaces the live ledger.
try:
    with open(tmp, 'rb') as f:
        tomllib.load(f)
except Exception as exc:
    os.unlink(tmp)
    sys.stderr.write('_ledger_update: ERROR serialized ledger failed round-trip parse: ' + str(exc) + '\n')
    sys.exit(4)
os.replace(tmp, path)
" "$@"
}

# _ledger_get <task_id> <key> — print the value ('' when the key is unset);
# nonzero when the ledger or the lease row is missing entirely.
_ledger_get() {
  local LEDGER
  LEDGER=$(_lease_ledger_path) || return 1
  [ -f "$LEDGER" ] || return 1
  LEDGER_FILE="$LEDGER" LEDGER_TASK="$1" LEDGER_KEY="$2" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(1)
with open(os.environ['LEDGER_FILE'], 'rb') as f:
    data = tomllib.load(f)
row = data.get('lease', {}).get(os.environ['LEDGER_TASK'])
if not isinstance(row, dict):
    sys.exit(1)
print(row.get(os.environ['LEDGER_KEY'], ''))
"
}

# _adapter_env <cli> <cmd...> — run an external command under the per-adapter
# environment allowlist (KTD-14): base allowlist HOME PATH TMPDIR TERM LANG
# COLORTERM plus ONLY the invoked CLI's own credential variables (opencode:
# OPENROUTER_API_KEY; kimi: KIMI_*; cursor: CURSOR_API_KEY). claude, codex,
# and antigravity authenticate via HOME-based stores and get nothing extra —
# no cross-provider leakage. env -i execs external commands only; shell
# functions cannot cross it, which is why lease_dispatch composes direct CLI
# commands instead of calling the invoke_* helpers (see there).
_adapter_env() {
  local CLI=$1
  shift
  local -a PAIRS=()
  local V
  for V in HOME PATH TMPDIR TERM LANG COLORTERM; do
    if [ -n "${!V+x}" ]; then
      PAIRS+=("${V}=${!V}")
    fi
  done
  case "$CLI" in
    opencode)
      [ -n "${OPENROUTER_API_KEY+x}" ] && PAIRS+=("OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
      ;;
    kimi)
      for V in $(compgen -v KIMI_ 2>/dev/null || true); do
        PAIRS+=("${V}=${!V}")
      done
      ;;
    cursor)
      [ -n "${CURSOR_API_KEY+x}" ] && PAIRS+=("CURSOR_API_KEY=${CURSOR_API_KEY}")
      ;;
  esac
  env -i "${PAIRS[@]}" "$@"
}

# Absolute path of the timeout binary, for lanes that exec it via env -i.
# Fail-closed like _run_with_timeout: no tool -> _RC_NO_TIMEOUT_TOOL.
_timeout_tool() {
  if command -v timeout >/dev/null 2>&1; then
    command -v timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    command -v gtimeout
  else
    echo "invoke-external.sh: ERROR neither \`timeout\` nor \`gtimeout\` is on PATH — refusing to dispatch a lease without timeout enforcement (fail-closed). Fix: on macOS run \`brew install coreutils\`, then retry." >&2
    return "$_RC_NO_TIMEOUT_TOOL"
  fi
}

# Worktrees lack .agents/skills/ (gitignored in user projects) — provision a
# copy so portable-skill discovery survives isolation (mirrors the
# session-start.sh bootstrap; KTD-3 groundwork).
_lease_provision_skills() {
  local WT=$1
  local SRC=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/skills" ]; then
    SRC="${CLAUDE_PLUGIN_ROOT}/skills"
  elif [ -d "$(_lease_repo_root)/skills" ]; then
    SRC="$(_lease_repo_root)/skills"
  fi
  if [ -z "$SRC" ]; then
    echo "lease: WARNING no skills source found (CLAUDE_PLUGIN_ROOT/skills or repo skills/) — worktree gets no .agents/skills/" >&2
    return 0
  fi
  mkdir -p "${WT}/.agents"
  cp -R "$SRC" "${WT}/.agents/skills" 2>/dev/null || true
}

# lease_create <task_id> <role> — resolve the builder from the roster
# (resolve_role), carve the worktree + lease branch, provision skills, write
# the leased row. Echoes task_id on success so callers can chain.
lease_create() {
  local TASK_ID=${1:?usage: lease_create <task_id> <role>}
  local ROLE=${2:?usage: lease_create <task_id> <role>}
  if ! _lease_valid_task_id "$TASK_ID"; then
    echo "lease_create: ERROR invalid task id '${TASK_ID}' — want [A-Za-z0-9][A-Za-z0-9._-]* (it becomes a branch and directory name)" >&2
    return 1
  fi
  local REPO ROOT RESOLVED CLI MODEL EFFORT WT NOW
  REPO=$(_lease_repo_root) || { echo "lease_create: ERROR not inside a git repository" >&2; return 1; }
  ROOT=$(_lease_root) || return 1
  RESOLVED=$(resolve_role "$ROLE") || return $?
  CLI=$(printf '%s\n' "$RESOLVED" | cut -f1)
  MODEL=$(printf '%s\n' "$RESOLVED" | cut -f2)
  EFFORT=$(printf '%s\n' "$RESOLVED" | cut -f3)
  WT="${ROOT}/${TASK_ID}"
  if [ -e "$WT" ]; then
    echo "lease_create: ERROR worktree path already exists: ${WT} (reclaim the previous lease first)" >&2
    return 1
  fi
  if ! git -C "$REPO" worktree add "$WT" -b "lease/${TASK_ID}" >&2; then
    echo "lease_create: ERROR git worktree add failed for task ${TASK_ID}" >&2
    return 1
  fi
  _lease_provision_skills "$WT"
  NOW=$(date +%s)
  _ledger_update "$TASK_ID" \
    task_id="$TASK_ID" role="$ROLE" \
    builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    state=leased worktree="$WT" branch="lease/${TASK_ID}" \
    pid=0 output_file="" created="$NOW" heartbeat_deadline=0 \
    requeue_count=0 previous_builder="" reviewer="" merge_commit="" reason="" \
    || return 1
  echo "lease_create: task=${TASK_ID} role=${ROLE} builder=${CLI} model=${MODEL:-ladder-resolved} worktree=${WT}" >&2
  echo "$TASK_ID"
}

# lease_dispatch <task_id> <prompt> [timeout-seconds]
#
# Composes the FULL dispatch prompt: injected context header (KTD-3 — the
# lease's roster line plus the explicit confinement contract) + the
# lead-provided task prompt (which carries the task row text and any
# CONTRACTS.md slice — the builder never reads canonical ops/).
#
# The builder launches in the BACKGROUND with cwd = the worktree (subshell
# cd), under _adapter_env's per-CLI allowlist (KTD-14). The invoke_* helpers
# are shell functions and cannot cross env -i, so each lane composes the
# adapter's command core directly: codex = exec + workspace-write + approval
# never + stdin guard (codex's own sandbox then scopes writes to the
# worktree cwd); antigravity = model pin + --add-dir + --print-timeout;
# claude = -p --permission-mode acceptEdits (cwd IS the worktree, no
# --add-dir needed). Exit code and KTD-9 class land in <out>.rc /
# <out>.class for the single-writer lead to collect — the builder process
# never touches the ledger.
#
# Test seam: TRIFORGE_TEST_BUILDER=<script path> replaces the real adapter
# for lifecycle determinism — the script runs with the worktree as cwd and
# the full prompt as its first argument, still under the recorded CLI's env
# allowlist and timeout so the confinement/heartbeat paths stay honest.
lease_dispatch() {
  local TASK_ID=${1:?usage: lease_dispatch <task_id> <prompt> [timeout]}
  local PROMPT=${2:?usage: lease_dispatch <task_id> <prompt> [timeout]}
  local TIMEOUT=${3:-600}
  local STATE CLI MODEL EFFORT ROLE WT ROOT OUT TOBIN NOW DEADLINE PID
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_dispatch: ERROR no lease row for task '${TASK_ID}' — run lease_create first" >&2; return 1; }
  if [ "$STATE" != "leased" ]; then
    echo "lease_dispatch: ERROR task ${TASK_ID} is in state '${STATE}' (want leased)" >&2
    return 1
  fi
  CLI=$(_ledger_get "$TASK_ID" builder_cli)
  MODEL=$(_ledger_get "$TASK_ID" builder_model)
  EFFORT=$(_ledger_get "$TASK_ID" builder_effort)
  ROLE=$(_ledger_get "$TASK_ID" role)
  WT=$(_ledger_get "$TASK_ID" worktree)
  if [ ! -d "$WT" ]; then
    echo "lease_dispatch: ERROR worktree missing: ${WT}" >&2
    return 1
  fi
  ROOT=$(_lease_root) || return 1
  OUT="${ROOT}/${TASK_ID}.out"
  TOBIN=$(_timeout_tool) || return $?

  local FULL_PROMPT
  FULL_PROMPT="## Lease dispatch: ${TASK_ID}
Roster entry: role=${ROLE} cli=${CLI} model=${MODEL:-<ladder-resolved>} effort=${EFFORT}

## Confinement contract
You are working in an isolated worktree at ${WT}. Never modify files outside it. Never read or write the project's canonical ops/ directory — required context is included below. Commit nothing; the lead collects.

## Task
${PROMPT}"

  rm -f "$OUT" "${OUT}.rc" "${OUT}.class"

  (
    cd "$WT" || exit 97
    RC=0
    if [ -n "${TRIFORGE_TEST_BUILDER:-}" ]; then
      # Test seam (see function comment): deterministic fake builder.
      _adapter_env "$CLI" "$TOBIN" "${TIMEOUT}s" "$TRIFORGE_TEST_BUILDER" "$FULL_PROMPT" > "$OUT" 2>&1 || RC=$?
    else
      case "$CLI" in
        claude)
          local -a CMD=(claude -p --permission-mode acceptEdits)
          [ -n "$MODEL" ] && CMD+=(--model "$MODEL")
          _adapter_env claude "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        codex)
          # Mirrors invoke_codex's retry-safe core (sandbox, approval, model
          # pin, stdin guard) — see the env -i note in the function comment.
          # The two sandbox_workspace_write excludes drop codex's default
          # temp-dir write allowance: lease worktrees live under TMPDIR, so
          # without them a builder could cross into sibling worktrees or the
          # lease root (R35: writes restricted to the lease worktree).
          local -a CMD=(codex exec -s workspace-write -c 'approval_policy="never"'
                        -c 'sandbox_workspace_write.exclude_tmpdir_env_var=true'
                        -c 'sandbox_workspace_write.exclude_slash_tmp=true')
          [ -n "$MODEL" ] && CMD+=(-m "$MODEL")
          [ -n "$EFFORT" ] && CMD+=(-c "model_reasoning_effort=\"${EFFORT}\"")
          _adapter_env codex "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        antigravity)
          _adapter_env antigravity "$TOBIN" "${TIMEOUT}s" agy --model "${MODEL:-Gemini 3.1 Pro (High)}" --add-dir "$WT" --print-timeout "${TIMEOUT}s" -p "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        opencode)
          # R35-confined optional-tier builder (U11): raw `opencode run` with
          # cwd = the worktree (the enclosing subshell cd'd there), under
          # _adapter_env opencode — which allowlists ONLY OPENROUTER_API_KEY
          # (KTD-14), so no cross-provider credential leak. No --auto (OC-06:
          # denies do not survive it) and no invoke_opencode (a shell function
          # cannot cross env -i); the confinement contract rides in FULL_PROMPT
          # like every other lane. Shipped default is the OpenRouter GLM, so a
          # live build AUTH-FAILs until the provider is connected — that failure
          # is deterministic and the lead sees it via <out>.class (no requeue).
          _adapter_env opencode "$TOBIN" "${TIMEOUT}s" opencode run --format json -m "${MODEL:-openrouter/z-ai/glm-5.2}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        *)
          echo "lease_dispatch: adapter for '${CLI}' not integrated yet (lands in U11-U13)" > "$OUT"
          RC=95
          ;;
      esac
    fi
    # Only a nonzero exit has a failure class (matches invoke_antigravity /
    # invoke_codex): a clean run is class=none, so lease_collect never reads a
    # spurious 'retryable' off a builder that actually succeeded.
    if [ "$RC" -eq 0 ]; then
      INVOKE_FAILURE_CLASS="none"
    else
      _classify_invoke_failure "$RC" "$OUT"
    fi
    printf '%s\n' "$RC" > "${OUT}.rc"
    printf '%s\n' "${INVOKE_FAILURE_CLASS:-none}" > "${OUT}.class"
    exit "$RC"
  ) &
  PID=$!

  NOW=$(date +%s)
  DEADLINE=$((NOW + TIMEOUT))
  _ledger_update "$TASK_ID" state=building pid="$PID" output_file="$OUT" heartbeat_deadline="$DEADLINE" || return 1
  echo "lease_dispatch: task=${TASK_ID} builder=${CLI} pid=${PID} timeout=${TIMEOUT}s output=${OUT}" >&2
}

# lease_heartbeat_check [task_id] — sweep building leases (or just one).
# Builder alive = the recorded pid answers kill -0 OR the output file was
# modified within the grace window (TRIFORGE_HEARTBEAT_GRACE, default 60s —
# covers a dead wrapper whose work just flushed). A dead pid that left
# <out>.rc is NOT an orphan — the builder finished; run lease_collect. Dead
# and stale, or alive past heartbeat_deadline (hung), goes state=orphaned
# and straight into lease_reclaim's safe prune (KTD-9 timeout class).
lease_heartbeat_check() {
  local ONLY=${1:-}
  local LEDGER GRACE NOW TASKS TASK
  LEDGER=$(_lease_ledger_path) || return 1
  if [ ! -f "$LEDGER" ]; then
    echo "lease_heartbeat_check: no lease ledger at ${LEDGER} — nothing to sweep" >&2
    return 0
  fi
  GRACE=${TRIFORGE_HEARTBEAT_GRACE:-60}
  NOW=$(date +%s)
  TASKS=$(LEDGER_FILE="$LEDGER" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
with open(os.environ['LEDGER_FILE'], 'rb') as f:
    data = tomllib.load(f)
for t, r in sorted(data.get('lease', {}).items()):
    if isinstance(r, dict) and r.get('state') == 'building':
        print(t)
")
  local SWEPT=0 ORPHANED=0
  for TASK in $TASKS; do
    if [ -n "$ONLY" ] && [ "$TASK" != "$ONLY" ]; then
      continue
    fi
    SWEPT=$((SWEPT + 1))
    local PID OUT DEADLINE ALIVE FRESH AGE
    PID=$(_ledger_get "$TASK" pid)
    OUT=$(_ledger_get "$TASK" output_file)
    DEADLINE=$(_ledger_get "$TASK" heartbeat_deadline)
    ALIVE=0
    [ -n "$PID" ] && [ "$PID" -gt 0 ] 2>/dev/null && kill -0 "$PID" 2>/dev/null && ALIVE=1
    if [ "$ALIVE" -eq 1 ]; then
      if [ "$NOW" -le "${DEADLINE:-0}" ]; then
        echo "lease_heartbeat_check: ${TASK} building (pid ${PID} alive, deadline in $((DEADLINE - NOW))s)" >&2
        continue
      fi
      # Hung past its window: still breathing but the lease is expired —
      # kill, then orphan (the launcher's own timeout should have fired;
      # this is the belt to that suspender).
      echo "lease_heartbeat_check: ${TASK} EXPIRED — pid ${PID} alive past heartbeat_deadline; killing and orphaning" >&2
      kill "$PID" 2>/dev/null || true
      sleep 1
      kill -9 "$PID" 2>/dev/null || true
    else
      if [ -n "$OUT" ] && [ -f "${OUT}.rc" ]; then
        echo "lease_heartbeat_check: ${TASK} builder exited (rc=$(cat "${OUT}.rc" 2>/dev/null || true)) — run: lease_collect ${TASK}" >&2
        continue
      fi
      FRESH=0
      AGE=999999
      if [ -n "$OUT" ] && [ -f "$OUT" ]; then
        AGE=$(OUT_FILE="$OUT" python3 -c "
import os, time
print(int(time.time() - os.path.getmtime(os.environ['OUT_FILE'])))
" 2>/dev/null || echo 999999)
        [ "$AGE" -lt "$GRACE" ] 2>/dev/null && FRESH=1
      fi
      if [ "$FRESH" -eq 1 ]; then
        echo "lease_heartbeat_check: ${TASK} pid ${PID} gone but output active ${AGE}s ago (grace ${GRACE}s) — leaving as building" >&2
        continue
      fi
      echo "lease_heartbeat_check: ${TASK} ORPHANED — pid ${PID} dead, no exit record, output stale; reclaiming" >&2
    fi
    ORPHANED=$((ORPHANED + 1))
    _ledger_update "$TASK" state=orphaned || return 1
    lease_reclaim "$TASK" || true
  done
  echo "lease_heartbeat_check: swept ${SWEPT} building lease(s), orphaned ${ORPHANED}" >&2
  return 0
}

# Refusal helper for lease_reclaim: loud, escalates the row, deletes NOTHING.
# Returns 0 so callers can '\; return 1' without tripping errexit.
_lease_refuse_prune() {
  local TASK_ID=$1 STORED=$2 MSG=$3
  echo "lease_reclaim: REFUSING prune for ${TASK_ID}: ${MSG} (stored='${STORED}')" >&2
  _ledger_update "$TASK_ID" state=escalated reason="lease identity mismatch" || true
  return 0
}

# lease_reclaim <task_id> — SAFE PRUNE. Destructive cleanup runs only after
# the lease identity survives, in this exact order:
#   1. canonicalize the stored worktree path (python3 os.path.realpath)
#   2. reject traversal ('..'/'.') components and non-canonical paths —
#      stored paths are canonical from birth (_lease_root realpaths), so any
#      canonical-vs-stored difference means a symlink or tampering
#   3. REQUIRE the canonical path sits strictly beneath the canonical root
#   4. REQUIRE git worktree list --porcelain knows the path
# ANY mismatch: nothing is deleted, state=escalated with reason "lease
# identity mismatch", nonzero return. A clean pass prunes worktree + branch,
# then transitions per the current state:
#   orphaned + requeue_count 0  -> requeued   (lease_requeue re-leases it)
#   orphaned + requeue_count 1+ -> escalated  (KTD-9: requeue once, loudly)
#   merged / anything else      -> state kept (prune only)
lease_reclaim() {
  local TASK_ID=${1:?usage: lease_reclaim <task_id>}
  local REPO ROOT WT_STORED WT_CANON STATE RQ
  REPO=$(_lease_repo_root) || return 1
  ROOT=$(_lease_root) || return 1
  WT_STORED=$(_ledger_get "$TASK_ID" worktree) || { echo "lease_reclaim: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  STATE=$(_ledger_get "$TASK_ID" state)

  if [ -z "$WT_STORED" ]; then
    _lease_refuse_prune "$TASK_ID" "$WT_STORED" "empty worktree path"; return 1
  fi
  case "$WT_STORED" in
    /*) : ;;
    *) _lease_refuse_prune "$TASK_ID" "$WT_STORED" "relative path"; return 1 ;;
  esac
  case "${WT_STORED}/" in
    *"/../"*|*"/./"*) _lease_refuse_prune "$TASK_ID" "$WT_STORED" "path contains traversal"; return 1 ;;
  esac
  WT_CANON=$(_lease_realpath "$WT_STORED")
  if [ "$WT_CANON" != "${WT_STORED%/}" ]; then
    _lease_refuse_prune "$TASK_ID" "$WT_STORED" "stored path is not canonical (symlink component or traversal; canonical='${WT_CANON}')"; return 1
  fi
  case "$WT_CANON" in
    "${ROOT}"/?*) : ;;
    *) _lease_refuse_prune "$TASK_ID" "$WT_STORED" "path not strictly beneath lease root '${ROOT}'"; return 1 ;;
  esac
  if ! git -C "$REPO" worktree list --porcelain | grep -Fxq "worktree ${WT_CANON}"; then
    _lease_refuse_prune "$TASK_ID" "$WT_STORED" "path not registered in git worktree list"; return 1
  fi

  if ! git -C "$REPO" worktree remove --force "$WT_CANON" >&2; then
    echo "lease_reclaim: ERROR git worktree remove failed for ${WT_CANON}" >&2
    _ledger_update "$TASK_ID" state=escalated reason="worktree remove failed" || true
    return 1
  fi
  git -C "$REPO" branch -D "lease/${TASK_ID}" >/dev/null 2>&1 || true

  case "$STATE" in
    orphaned)
      RQ=$(_ledger_get "$TASK_ID" requeue_count)
      if [ "${RQ:-0}" -eq 0 ] 2>/dev/null; then
        _ledger_update "$TASK_ID" state=requeued || return 1
        echo "lease_reclaim: ${TASK_ID} pruned — requeued (one retry available via lease_requeue, KTD-9)" >&2
      else
        _ledger_update "$TASK_ID" state=escalated reason="second builder failure" || return 1
        echo "lease_reclaim: ${TASK_ID} pruned — ESCALATED: second builder failure (requeue_count=${RQ}). KTD-9 allows exactly one requeue; the lead must diagnose or reassign manually." >&2
      fi
      ;;
    *)
      echo "lease_reclaim: ${TASK_ID} pruned (state stays '${STATE}')" >&2
      ;;
  esac
  return 0
}

# lease_requeue <task_id> — one second chance, on a DIFFERENT builder
# (KTD-9: exactly once). Walks the role's fallback chain past
# previous_builder via resolve_role's RESOLVE_ROLE_EXCLUDE hook, carves a
# fresh worktree, and re-leases. requeue_count >= 1 escalates instead.
lease_requeue() {
  local TASK_ID=${1:?usage: lease_requeue <task_id>}
  local STATE RQ PREV ROLE OUT REPO ROOT WT RESOLVED CLI MODEL EFFORT
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_requeue: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  RQ=$(_ledger_get "$TASK_ID" requeue_count)
  OUT=$(_ledger_get "$TASK_ID" output_file)
  if [ "${RQ:-0}" -ge 1 ] 2>/dev/null; then
    _ledger_update "$TASK_ID" state=escalated reason="requeue budget exhausted" || true
    echo "lease_requeue: ${TASK_ID} ESCALATED — requeue_count=${RQ}; KTD-9 allows exactly one requeue and a different builder already failed this task. The lead must diagnose (see ${OUT:-the builder output}) or reassign manually." >&2
    return 1
  fi
  if [ "$STATE" != "requeued" ]; then
    echo "lease_requeue: ERROR task ${TASK_ID} is in state '${STATE}' (want requeued — lease_reclaim sets it after a clean prune)" >&2
    return 1
  fi
  PREV=$(_ledger_get "$TASK_ID" builder_cli)
  ROLE=$(_ledger_get "$TASK_ID" role)
  REPO=$(_lease_repo_root) || return 1
  ROOT=$(_lease_root) || return 1
  RESOLVED=$(RESOLVE_ROLE_EXCLUDE="$PREV" resolve_role "$ROLE") || {
    _ledger_update "$TASK_ID" state=escalated reason="no alternative builder" || true
    echo "lease_requeue: ${TASK_ID} ESCALATED — no live builder past previous '${PREV}' in role '${ROLE}' fallback chain." >&2
    return 1
  }
  CLI=$(printf '%s\n' "$RESOLVED" | cut -f1)
  MODEL=$(printf '%s\n' "$RESOLVED" | cut -f2)
  EFFORT=$(printf '%s\n' "$RESOLVED" | cut -f3)
  WT="${ROOT}/${TASK_ID}"
  if [ -e "$WT" ]; then
    echo "lease_requeue: ERROR stale worktree still present at ${WT} — reclaim first" >&2
    return 1
  fi
  if ! git -C "$REPO" worktree add "$WT" -b "lease/${TASK_ID}" >&2; then
    echo "lease_requeue: ERROR git worktree add failed for task ${TASK_ID}" >&2
    return 1
  fi
  _lease_provision_skills "$WT"
  _ledger_update "$TASK_ID" \
    state=leased builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    previous_builder="$PREV" requeue_count=1 pid=0 heartbeat_deadline=0 reason="" \
    || return 1
  echo "lease_requeue: ${TASK_ID} re-leased to ${CLI} (previous builder: ${PREV}) — dispatch again with lease_dispatch" >&2
  echo "$TASK_ID"
}

# lease_collect <task_id> — lead-side harvest of a finished builder. Exit 0:
# state=review, prints the output-file path (U10 feeds it to the reviewer).
# Nonzero: routed by the KTD-9 class the launcher recorded (<out>.class):
#   deterministic       -> state=failed, fail fast with guidance, NO requeue
#   timeout / retryable -> orphan path (reclaim -> requeue once -> escalate)
lease_collect() {
  local TASK_ID=${1:?usage: lease_collect <task_id>}
  local STATE PID OUT RC CLASS
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_collect: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if [ "$STATE" != "building" ]; then
    echo "lease_collect: ERROR task ${TASK_ID} is in state '${STATE}' (want building)" >&2
    return 1
  fi
  PID=$(_ledger_get "$TASK_ID" pid)
  OUT=$(_ledger_get "$TASK_ID" output_file)
  if [ ! -f "${OUT}.rc" ]; then
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      echo "lease_collect: task ${TASK_ID} still running (pid ${PID}) — wait, or lease_heartbeat_check to enforce the deadline" >&2
      return 1
    fi
    echo "lease_collect: task ${TASK_ID} builder died without an exit record — silent death, taking the orphan path" >&2
    _ledger_update "$TASK_ID" state=orphaned || return 1
    lease_reclaim "$TASK_ID" || true
    return 1
  fi
  RC=$(cat "${OUT}.rc" 2>/dev/null || echo 1)
  CLASS=$(cat "${OUT}.class" 2>/dev/null || true)
  if [ "$RC" -eq 0 ] 2>/dev/null; then
    _ledger_update "$TASK_ID" state=review || return 1
    echo "lease_collect: task ${TASK_ID} builder exited 0 — state=review, output below" >&2
    printf '%s\n' "$OUT"
    return 0
  fi
  if [ -z "$CLASS" ]; then
    _classify_invoke_failure "$RC" "$OUT"
    CLASS="$INVOKE_FAILURE_CLASS"
  fi
  case "$CLASS" in
    deterministic)
      _ledger_update "$TASK_ID" state=failed reason="deterministic failure rc=${RC}" || return 1
      echo "lease_collect: task ${TASK_ID} FAILED deterministically (rc=${RC}) — retry cannot help; fix the cause (see ${OUT}) and escalate. No requeue (KTD-9)." >&2
      return 1
      ;;
    *)
      echo "lease_collect: task ${TASK_ID} builder failed rc=${RC} class=${CLASS} — orphaning for the requeue path (see ${OUT})" >&2
      _ledger_update "$TASK_ID" state=orphaned || return 1
      lease_reclaim "$TASK_ID" || true
      return 1
      ;;
  esac
}

# lease_merge <task_id> <reviewer-identity> — single-commit-per-task merge
# (KTD-5) with the AE3 mechanical guard: reviewer must be nonempty and must
# differ from the lease's builder_cli — self-review never merges (U10 layers
# the full cross-review protocol on this check). The lead snapshots the
# builder's uncommitted worktree changes onto the lease branch ("commit
# nothing; the lead collects"), squash-merges into the MAIN tree, records
# reviewer + merge_commit, then reclaims via the safe-prune path. Squash
# conflicts leave a dirty index: reset --merge, state stays review, the lead
# resolves manually.
lease_merge() {
  local TASK_ID=${1:?usage: lease_merge <task_id> <reviewer-identity>}
  local REVIEWER=${2:-}
  local STATE BUILDER WT BRANCH REPO SHA
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_merge: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if [ "$STATE" != "review" ]; then
    echo "lease_merge: ERROR task ${TASK_ID} is in state '${STATE}' (want review — lease_collect sets it)" >&2
    return 1
  fi
  if [ -z "$REVIEWER" ]; then
    echo "lease_merge: ERROR reviewer identity is required — no merge without a named reviewer (AE3)" >&2
    return 1
  fi
  BUILDER=$(_ledger_get "$TASK_ID" builder_cli)
  if [ "$REVIEWER" = "$BUILDER" ]; then
    echo "lease_merge: REFUSED — reviewer '${REVIEWER}' is the builder of ${TASK_ID}; self-review never merges (AE3). Pick a non-author reviewer." >&2
    return 1
  fi
  WT=$(_ledger_get "$TASK_ID" worktree)
  BRANCH=$(_ledger_get "$TASK_ID" branch)
  REPO=$(_lease_repo_root) || return 1
  if [ ! -d "$WT" ]; then
    echo "lease_merge: ERROR worktree missing: ${WT}" >&2
    return 1
  fi

  # Lead-side collect commit: the builder committed nothing (contract), so
  # snapshot its work onto the lease branch. .agents/ (provisioned skills)
  # is excluded even where a project forgot to gitignore it.
  git -C "$WT" add -A -- . ":(exclude).agents" >&2 || return 1
  if ! git -C "$WT" diff --cached --quiet 2>/dev/null; then
    git -C "$WT" commit -m "lease(${TASK_ID}): builder output snapshot (${BUILDER})" >&2 || return 1
  fi

  # The squash commit must contain exactly this lease's work (KTD-5): a
  # pre-dirtied main index would smuggle unrelated changes into it.
  if ! git -C "$REPO" diff --cached --quiet 2>/dev/null; then
    echo "lease_merge: ERROR main tree index has staged changes — commit or unstage them first; the lease commit must contain only ${TASK_ID}'s work" >&2
    return 1
  fi
  if ! git -C "$REPO" merge --squash "$BRANCH" >&2; then
    git -C "$REPO" reset --merge >&2 || true
    echo "lease_merge: CONFLICT squash-merging ${BRANCH} into the main tree — index reset, state stays review. The lead resolves manually (rebase the lease branch onto HEAD, or cherry-pick), then reruns lease_merge." >&2
    return 1
  fi
  if git -C "$REPO" diff --cached --quiet 2>/dev/null; then
    echo "lease_merge: ERROR ${BRANCH} brought no changes (builder produced nothing?) — state stays review" >&2
    return 1
  fi
  if ! git -C "$REPO" commit -m "lease(${TASK_ID}): merged from ${BUILDER}, reviewed by ${REVIEWER}" >&2; then
    git -C "$REPO" reset --merge >&2 || true
    echo "lease_merge: ERROR commit failed — index reset, state stays review" >&2
    return 1
  fi
  SHA=$(git -C "$REPO" rev-parse HEAD)
  _ledger_update "$TASK_ID" state=merged reviewer="$REVIEWER" merge_commit="$SHA" || return 1
  echo "lease_merge: ${TASK_ID} merged as ${SHA} (builder ${BUILDER}, reviewer ${REVIEWER}) — reclaiming worktree" >&2
  lease_reclaim "$TASK_ID" || true
  return 0
}

# lease_status — human table of the ledger (task, builder, state, age) for
# /status and resume orientation. Tolerant: reports a missing or unparseable
# ledger instead of failing.
lease_status() {
  local LEDGER
  LEDGER=$(_lease_ledger_path) || return 1
  if [ ! -f "$LEDGER" ]; then
    echo "lease_status: no lease ledger (${LEDGER}) — no leases have been created"
    return 0
  fi
  LEDGER_FILE="$LEDGER" python3 -c "
import os, sys, time
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('lease_status: ERROR no TOML parser available\n')
        sys.exit(1)
try:
    with open(os.environ['LEDGER_FILE'], 'rb') as f:
        data = tomllib.load(f)
except Exception as exc:
    sys.stderr.write('lease_status: ERROR ledger unparseable: ' + str(exc) + '\n')
    sys.exit(1)
leases = data.get('lease', {})
now = int(time.time())
counts = {}
rows = [('TASK', 'BUILDER', 'MODEL', 'STATE', 'AGE')]
for t in sorted(leases if isinstance(leases, dict) else {}):
    r = leases[t]
    if not isinstance(r, dict):
        continue
    state = str(r.get('state', '?'))
    counts[state] = counts.get(state, 0) + 1
    try:
        age = max(0, now - int(r.get('updated') or now))
    except (TypeError, ValueError):
        age = 0
    if age >= 3600:
        age_s = str(age // 3600) + 'h' + str((age % 3600) // 60) + 'm'
    elif age >= 60:
        age_s = str(age // 60) + 'm' + str(age % 60) + 's'
    else:
        age_s = str(age) + 's'
    rows.append((str(t), str(r.get('builder_cli', '?')),
                 str(r.get('builder_model', '') or '-'), state, age_s))
if len(rows) == 1:
    print('lease_status: ledger is empty')
    sys.exit(0)
widths = [max(len(r[i]) for r in rows) for i in range(5)]
for r in rows:
    print('  '.join(r[i].ljust(widths[i]) for i in range(5)).rstrip())
print('')
print('states: ' + ', '.join(k + '=' + str(v) for k, v in sorted(counts.items())))
"
}

# ---------------------------------------------------------------------------
# Enrollment (R37/R39) — onboarding optional roster members
# ---------------------------------------------------------------------------
#
# One routine serves both onboarding surfaces (AE6):
#   - R37 first-detection: hooks/handlers/session-start.sh, after optional-CLI
#     detection, calls roster_enroll_member <cli> headless for each newly
#     detected optional member. A hook cannot prompt, so headless silently
#     enrolls the shipped default (KTD-8); a later /setup then shows the member
#     as already-enrolled instead of re-asking.
#   - R39 guided walk: commands/setup.md drives the interactive ask (participate?
#     + which model) and records the answer through roster_write_member.
#
# The [members.<cli>] table in ops/roster.toml is BOTH the enrollment record and
# the idempotency key: its mere presence — enabled=true OR enabled=false —
# suppresses the ask forever. A decline persists as enabled=false ("disabled =
# absent everywhere", R38). roster_write_member is the SINGLE writer of that
# table (mirrors the lease ledger's single-writer discipline): a text-surgical
# tmp+mv with a tomllib round-trip verify, so it preserves the rest of the file
# — role tables, comments, promotion gate — byte-for-byte.
#
# Shipped optional defaults (KTD-8, session-settled; MUST match CLI_DEFAULT_MODEL
# in resolve_role): opencode -> openrouter/z-ai/glm-5.2 ; kimi -> kimi-k3 ;
# cursor -> grok-4.5 (explicit pin, NEVER the Auto router). The core trio
# (claude/antigravity/codex) is required, never enrolled.

# cli name -> binary looked up on PATH (mirrors resolve_role's BINARY map).
_roster_binary() {
  case "${1:-}" in
    claude)      echo "claude" ;;
    antigravity) echo "agy" ;;
    codex)       echo "codex" ;;
    opencode)    echo "opencode" ;;
    kimi)        echo "kimi" ;;
    cursor)      echo "cursor-agent" ;;
    *) return 2 ;;
  esac
}

# Pinned install matrix — OFFICIAL installers only, last verified 2026-07-18.
# /setup PRINTS these for the user to run themselves; Triforge NEVER executes an
# installer. The optional-three URLs are the surface /cli-watch (U14) re-checks
# each cycle — keep the two in sync when an upstream installer URL moves.
_roster_install_cmd() {
  case "${1:-}" in
    opencode)    echo "curl -fsSL https://opencode.ai/install | bash" ;;
    kimi)        echo "curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash" ;;
    cursor)      echo "curl https://cursor.com/install -fsS | bash" ;;
    claude)      echo "npm install -g @anthropic-ai/claude-code" ;;
    antigravity) echo "curl -fsSL https://antigravity.google/cli/install.sh | bash" ;;
    codex)       echo "npm install -g @openai/codex   (or: brew install codex)" ;;
    *) return 2 ;;
  esac
}

# roster_member_default <cli> — print the shipped default model (KTD-8).
# Mirrors CLI_DEFAULT_MODEL in resolve_role; claude is intentionally empty (the
# Claude downgrade ladder resolves its model, never the roster).
roster_member_default() {
  case "${1:?usage: roster_member_default <cli>}" in
    claude)      echo "" ;;
    antigravity) echo "Gemini 3.1 Pro (High)" ;;
    codex)       echo "gpt-5.6-sol" ;;
    opencode)    echo "openrouter/z-ai/glm-5.2" ;;
    kimi)        echo "kimi-k3" ;;
    cursor)      echo "grok-4.5" ;;
    *) echo "roster_member_default: ERROR unknown cli '${1}'" >&2; return 2 ;;
  esac
}

# roster_has_member <cli> — 0 when ops/roster.toml carries a [members.<cli>]
# table, 1 when it does not (or the file is absent — the writer will create it),
# 2 when the file exists but is unparseable. Cheap (tomllib only, no live probe)
# so the session-start trigger stays fast.
roster_has_member() {
  local CLI=${1:?usage: roster_has_member <cli>}
  [ -f "ops/roster.toml" ] || return 1
  ROSTER_FILE="ops/roster.toml" RH_CLI="$CLI" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(2)
try:
    with open(os.environ['ROSTER_FILE'], 'rb') as f:
        data = tomllib.load(f)
except Exception:
    sys.exit(2)
m = data.get('members', {})
sys.exit(0 if isinstance(m, dict) and isinstance(m.get(os.environ['RH_CLI']), dict) else 1)
"
}

# _roster_member_field <cli> <field> — print one field of [members.<cli>]
# (enabled printed as true|false). Nonzero when the entry is absent/unparseable.
_roster_member_field() {
  local CLI=${1:?} FIELD=${2:?}
  [ -f "ops/roster.toml" ] || return 1
  ROSTER_FILE="ops/roster.toml" RF_CLI="$CLI" RF_FIELD="$FIELD" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(1)
try:
    with open(os.environ['ROSTER_FILE'], 'rb') as f:
        data = tomllib.load(f)
except Exception:
    sys.exit(1)
m = data.get('members', {}).get(os.environ['RF_CLI'], {})
if not isinstance(m, dict):
    sys.exit(1)
v = m.get(os.environ['RF_FIELD'], '')
print('true' if v is True else ('false' if v is False else v))
"
}

# roster_write_member <cli> <true|false> <model> [enrolled-tag]
# The SINGLE writer of [members.<cli>] in ops/roster.toml. Text-surgical so it
# preserves everything else in the file (roles, comments, promotion gate): it
# replaces an existing [members.<cli>] block in place, or appends a new one,
# then round-trip-verifies the result parses AND reflects the intended values
# before an atomic tmp+mv. Refuses unknown CLIs and refuses to disable a
# core-trio member (mirrors resolve_role's load-time rule so the roster stays
# resolvable). enrolled-tag defaults to today's date.
roster_write_member() {
  local CLI=${1:?usage: roster_write_member <cli> <true|false> <model> [enrolled-tag]}
  local ENABLED=${2:?usage: roster_write_member <cli> <true|false> <model> [enrolled-tag]}
  local MODEL=${3-}
  local TAG=${4:-$(date +%Y-%m-%d)}
  mkdir -p ops
  ROSTER_FILE="ops/roster.toml" RW_CLI="$CLI" RW_ENABLED="$ENABLED" RW_MODEL="$MODEL" RW_TAG="$TAG" python3 -c "
import json, os, re, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('roster_write_member: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

path = os.environ['ROSTER_FILE']
cli = os.environ['RW_CLI']
enabled = os.environ['RW_ENABLED']
model = os.environ['RW_MODEL']
tag = os.environ['RW_TAG']

CORE = ('claude', 'antigravity', 'codex')
KNOWN = ('claude', 'antigravity', 'codex', 'opencode', 'kimi', 'cursor')
if cli not in KNOWN:
    sys.stderr.write('roster_write_member: ERROR unknown CLI ' + repr(cli) + ' (known: ' + ', '.join(KNOWN) + ')\n')
    sys.exit(2)
if enabled not in ('true', 'false'):
    sys.stderr.write('roster_write_member: ERROR enabled must be true|false, got ' + repr(enabled) + '\n')
    sys.exit(2)
if cli in CORE and enabled == 'false':
    sys.stderr.write('roster_write_member: ERROR [members.' + cli + '] enabled=false rejected — the core trio cannot be disabled\n')
    sys.exit(2)

block = ('[members.' + cli + ']\n'
         'enabled = ' + enabled + '\n'
         'model = ' + json.dumps(model) + '\n'
         'enrolled = ' + json.dumps(tag) + '\n')

raw = ''
if os.path.isfile(path):
    with open(path, 'r') as f:
        raw = f.read()
lines = raw.splitlines(keepends=True)

# An UNcommented header only: '# [members.x]' must not match (top scan below
# uses the same rule so a comment never ends a block).
hdr = re.compile(r'^\[members\.' + re.escape(cli) + r'\][ \t]*$')
top = re.compile(r'^\[')
start = None
for i, ln in enumerate(lines):
    if hdr.match(ln):
        start = i
        break

if start is not None:
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if top.match(lines[j]):
            end = j
            break
    prefix = ''.join(lines[:start])
    suffix = ''.join(lines[end:])
    if prefix and not prefix.endswith('\n'):
        prefix += '\n'
    new_raw = prefix + block
    if suffix.strip():
        if not suffix.startswith('\n'):
            new_raw += '\n'
        new_raw += suffix
    else:
        new_raw += suffix
else:
    new_raw = raw
    if new_raw and not new_raw.endswith('\n'):
        new_raw += '\n'
    if new_raw and not new_raw.endswith('\n\n'):
        new_raw += '\n'
    new_raw += block

tmp = path + '.tmp.' + str(os.getpid())
with open(tmp, 'w') as f:
    f.write(new_raw)
# The roster MUST stay tomllib-parseable AND reflect our values after every
# write — verify the tmp file BEFORE it replaces the live roster.
try:
    with open(tmp, 'rb') as f:
        data = tomllib.load(f)
    m = data.get('members', {}).get(cli, {})
    assert isinstance(m, dict), 'members.' + cli + ' is not a table after write'
    assert m.get('enabled') == (enabled == 'true'), 'enabled mismatch after write'
    assert str(m.get('model', '')) == model, 'model mismatch after write'
except Exception as exc:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    sys.stderr.write('roster_write_member: ERROR serialized roster failed round-trip verify: ' + str(exc) + '\n')
    sys.exit(4)
os.replace(tmp, path)
sys.stderr.write('roster_write_member: [members.' + cli + '] enabled=' + enabled + ' model=' + (model or '<none>') + ' enrolled=' + tag + '\n')
"
}

# roster_member_auth <cli> — readiness (login) check for an OPTIONAL member.
# Prints 'ok' (return 0) or 'auth-failed: <exact fix>' (return 1). Prints
# 'unknown: ...' (return 2) for the core trio (their liveness is
# ensure_core_trio_live's job) or an unknown cli. The result is cached per
# shell ($$ stays the sourcing shell's PID across subshells) so a status table
# that queries the same cli twice probes only once.
#   cursor   -> cursor-agent status         (pure auth query, no tokens)
#   opencode -> OPENROUTER_API_KEY set, else `opencode auth list` names openrouter
#   kimi     -> bounded headless probe. kimi doctor validates CONFIG only and
#               PASSES when signed out (probe KIMI-02 PASS vs KIMI-05 AUTH-FAIL),
#               so login state needs a real headless call. Signed-out fails fast
#               (no model configured, before any network round-trip) so the cap
#               is cheap; signed-in answers the trivial READY quickly.
roster_member_auth() {
  local CLI=${1:?usage: roster_member_auth <cli>}
  local CACHE="${TMPDIR:-/tmp}/triforge_auth_${CLI}_$$"
  if [ -f "$CACHE" ]; then
    local CACHED; CACHED=$(cat "$CACHE")
    printf '%s\n' "$CACHED"
    case "$CACHED" in
      ok) return 0 ;;
      unknown*) return 2 ;;
      *) return 1 ;;
    esac
  fi
  local LINE="" RC=0 OUT=""
  case "$CLI" in
    cursor)
      OUT=$(_run_with_timeout 15 cursor-agent status 2>&1) || true
      if printf '%s' "$OUT" | grep -qi 'logged in'; then
        LINE="ok"
      else
        LINE="auth-failed: run 'cursor-agent login' to sign in"; RC=1
      fi
      ;;
    opencode)
      if [ -n "${OPENROUTER_API_KEY:-}" ]; then
        LINE="ok"
      elif _run_with_timeout 15 opencode auth list 2>/dev/null | grep -qi 'openrouter'; then
        LINE="ok"
      else
        LINE="auth-failed: set OPENROUTER_API_KEY, or run 'opencode auth login' and connect the openrouter provider (the openrouter/z-ai/glm-5.2 default needs it)"; RC=1
      fi
      ;;
    kimi)
      local KERR="${TMPDIR:-/tmp}/triforge_kimi_auth_err_$$"
      OUT=$(_run_with_timeout 45 env KIMI_DISABLE_TELEMETRY=1 kimi --output-format stream-json -p "Respond with only: READY" 2>"$KERR") || true
      local KE=""; KE=$(cat "$KERR" 2>/dev/null || true); rm -f "$KERR"
      if printf '%s\n%s' "$OUT" "$KE" | grep -qiE 'no model configured|not (logged|signed) in|use /login|/login|unauthorized|401|credential|authentication (failed|required|expired)'; then
        LINE="auth-failed: run 'kimi login' (or launch 'kimi' and use /login) to sign in"; RC=1
      elif printf '%s' "$OUT" | grep -qi 'ready'; then
        LINE="ok"
      else
        LINE="ok"   # inconclusive (no READY, no auth-shaped error) — do not block on an ambiguous probe
      fi
      ;;
    claude|antigravity|codex)
      LINE="unknown: core member (readiness via ensure_core_trio_live)"; RC=2
      ;;
    *)
      LINE="unknown: cli '${CLI}'"; RC=2
      ;;
  esac
  printf '%s\n' "$LINE" > "$CACHE" 2>/dev/null || true
  printf '%s\n' "$LINE"
  return $RC
}

# roster_member_status <cli> — single-token status for the /setup table:
#   core                 core-trio member present (required, never enrolled)
#   not-installed        binary absent from PATH
#   enrolled(<model>)    [members.<cli>] enabled=true
#   declined             [members.<cli>] enabled=false (shown "skipped" in table)
#   detected-unenrolled  binary present, no entry, readiness ok
#   auth-failed          binary present, no entry, readiness check failed
# An enrolled member reports enrolled(model) regardless of current auth — the
# table carries a separate auth column for live readiness; enrollment records
# intent, not a live login.
roster_member_status() {
  local CLI=${1:?usage: roster_member_status <cli>}
  local BIN; BIN=$(_roster_binary "$CLI") || { echo "unknown-cli"; return 2; }
  case "$CLI" in
    claude|antigravity|codex)
      if command -v "$BIN" >/dev/null 2>&1; then echo "core"; else echo "not-installed"; fi
      return 0
      ;;
  esac
  if ! command -v "$BIN" >/dev/null 2>&1; then echo "not-installed"; return 0; fi
  local HAS_RC=0
  roster_has_member "$CLI" || HAS_RC=$?
  if [ "$HAS_RC" -eq 0 ]; then
    local ENABLED MODEL
    ENABLED=$(_roster_member_field "$CLI" enabled 2>/dev/null || true)
    MODEL=$(_roster_member_field "$CLI" model 2>/dev/null || true)
    if [ "$ENABLED" = "false" ]; then echo "declined"; else echo "enrolled(${MODEL})"; fi
    return 0
  fi
  if roster_member_auth "$CLI" >/dev/null 2>&1; then echo "detected-unenrolled"; else echo "auth-failed"; fi
  return 0
}

# roster_enroll_member <cli> <interactive|headless> — the shared enrollment
# routine both surfaces call. Idempotent (AE6): an existing [members.<cli>]
# entry short-circuits to already-enrolled. Return codes let callers react
# without parsing stderr:
#   0  done          already enrolled, or headless just enrolled the default
#   2  invalid       unknown cli, core-trio cli, or bad mode
#   4  roster-error  ops/roster.toml exists but is unparseable
#   10 not-installed binary absent — the OFFICIAL install command is PRINTED
#                    (never run); /setup shows the row as "not installed"
#   20 needs-ask     interactive + installed + unenrolled — the CALLER runs the
#                    participate?/which-model ask, then roster_write_member
roster_enroll_member() {
  local CLI=${1:?usage: roster_enroll_member <cli> <interactive|headless>}
  local MODE=${2:?usage: roster_enroll_member <cli> <interactive|headless>}
  local BIN DEFAULT
  BIN=$(_roster_binary "$CLI") || { echo "roster_enroll_member: unknown cli '${CLI}'" >&2; return 2; }
  case "$CLI" in
    claude|antigravity|codex)
      echo "roster_enroll_member: '${CLI}' is core-trio (required, never enrolled) — nothing to do" >&2
      return 2
      ;;
  esac
  case "$MODE" in
    interactive|headless) : ;;
    *) echo "roster_enroll_member: ERROR mode must be interactive|headless, got '${MODE}'" >&2; return 2 ;;
  esac
  DEFAULT=$(roster_member_default "$CLI")

  # Idempotency (AE6): any existing entry — enrolled OR declined — suppresses
  # the ask. This is what makes /setup and first-detection re-runnable.
  local HAS_RC=0
  roster_has_member "$CLI" || HAS_RC=$?
  if [ "$HAS_RC" -eq 0 ]; then
    echo "already-enrolled: ${CLI} — $(roster_member_status "$CLI")"
    return 0
  fi
  if [ "$HAS_RC" -eq 2 ]; then
    echo "roster_enroll_member: ops/roster.toml is unparseable — not enrolling ${CLI} (resolve_role will surface the exact parse error)" >&2
    return 4
  fi

  # Binary detection: absent -> PRINT the official install command (never run
  # it) and return the not-installed code so the caller shows "not installed".
  if ! command -v "$BIN" >/dev/null 2>&1; then
    echo "not-installed: ${CLI} (binary '${BIN}' absent). Install it yourself — Triforge never runs installers for you:"
    echo "    $(_roster_install_cmd "$CLI")"
    return 10
  fi

  # Auth/READY check names the exact fix on failure. Skipped in headless mode
  # so the session-start trigger stays fast (no live probe); a failed auth does
  # not block enrollment (which records intent) — the caller surfaces the fix.
  local AUTH="skipped"
  if [ "$MODE" != "headless" ]; then
    AUTH=$(roster_member_auth "$CLI") || true
  fi

  if [ "$MODE" = "headless" ]; then
    roster_write_member "$CLI" true "$DEFAULT" "headless-default:$(date +%Y-%m-%d)" || return $?
    echo "enrolled: ${CLI} model=${DEFAULT:-<ladder>} (headless-default)"
    return 0
  fi

  # interactive: the CALLER (setup.md) runs the ask and writes the answer.
  echo "needs-ask: ${CLI} installed=yes default-model=${DEFAULT} auth=${AUTH}"
  echo "  enroll : roster_write_member ${CLI} true <model>   (recommended: ${DEFAULT})"
  echo "  decline: roster_write_member ${CLI} false \"\""
  return 20
}
