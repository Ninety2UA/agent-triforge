#!/usr/bin/env bash
# scripts/lib/codex.sh — the Codex lane: invoke_codex (triforge-agents.toml replay, --output-schema, hooks-under-exec)
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/codex.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Codex invocation
# ---------------------------------------------------------------------------

# Codex has no CLI flag to pick a subagent — upstream "subagents" are only
# spawned from within a running session. So we simulate it: extract the agent's
# config from agents.toml and pass it as -c/-s/-a overrides, with the
# developer_instructions injected as prompt prefix.
#
# Agents.toml lookup: the deployed project copy `.codex/triforge-agents.toml`
# first (D-026: Codex >= 0.147 sweeps `.codex/agents/*.toml` as standalone role
# files and warns on this multi-agent file, so session-start deploys it under a
# name outside that sweep), then the plugin template
# `${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml`.
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
  if [ -f ".codex/triforge-agents.toml" ]; then
    AGENT_TOML=".codex/triforge-agents.toml"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml" ]; then
    AGENT_TOML="${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml"
  fi

  local AGENT_MODEL="" AGENT_SANDBOX="" AGENT_APPROVAL="" AGENT_INSTR_B64="" AGENT_OUTPUT_SCHEMA="" AGENT_EFFORT=""
  local AGENT_MODEL_B64="" AGENT_SANDBOX_B64="" AGENT_APPROVAL_B64="" AGENT_OUTPUT_SCHEMA_B64="" AGENT_EFFORT_B64=""
  if [ -n "$AGENT_TOML" ]; then
    local CONFIG_SH
    CONFIG_SH=$(_extract_codex_agent_config "$AGENT_TOML" "$AGENT_NAME") || CONFIG_SH=""
    if [ -n "$CONFIG_SH" ]; then
      # Every emitted line is NAME=<base64> — injection-safe under eval (base64
      # has no shell metacharacters), unlike raw config values which could carry
      # $()/backticks that eval would execute in this lead shell. Decode each
      # field back to its real value after the (now-safe) eval.
      eval "$CONFIG_SH"
      AGENT_MODEL=$(printf '%s' "${AGENT_MODEL_B64:-}" | base64 -d 2>/dev/null || true)
      AGENT_SANDBOX=$(printf '%s' "${AGENT_SANDBOX_B64:-}" | base64 -d 2>/dev/null || true)
      AGENT_APPROVAL=$(printf '%s' "${AGENT_APPROVAL_B64:-}" | base64 -d 2>/dev/null || true)
      AGENT_OUTPUT_SCHEMA=$(printf '%s' "${AGENT_OUTPUT_SCHEMA_B64:-}" | base64 -d 2>/dev/null || true)
      AGENT_EFFORT=$(printf '%s' "${AGENT_EFFORT_B64:-}" | base64 -d 2>/dev/null || true)
    fi
  fi

  # Loud warning when the agent wasn't found in agents.toml — otherwise we
  # silently run with session defaults (no model, no sandbox, no instructions).
  if [ -z "$AGENT_MODEL" ] && [ -z "$AGENT_SANDBOX" ] && [ -z "$AGENT_INSTR_B64" ]; then
    local AVAILABLE
    AVAILABLE=$(_list_codex_agents "$AGENT_TOML" | paste -sd, - 2>/dev/null || echo "")
    echo "invoke_codex: WARNING agent '${AGENT_NAME}' not found in agents.toml; running with session defaults (no model/sandbox/instructions applied). Available agents: ${AVAILABLE:-<none>}" >&2
  fi

  # Roster model override (mirrors AGY_MODEL / OPENCODE_MODEL / KIMI_MODEL /
  # CURSOR_MODEL on the sibling lanes): a caller-set CODEX_MODEL wins over the
  # agents.toml pin so a [roles.*] model customization actually reaches
  # `codex exec -m`. Unset -> agents.toml (or session default) as before.
  # Sandbox, approval, and instructions always stay agents.toml-owned. Applied
  # after the not-found warning so the override never masks a missing agent.
  if [ -n "${CODEX_MODEL:-}" ]; then
    AGENT_MODEL="$CODEX_MODEL"
  fi
  # Effort replay (R3, KTD5): agents.toml's model_reasoning_effort rides as a
  # -c override on every exec; CODEX_EFFORT (set by dispatch_role from the
  # roster's effort column) wins over the file so a [roles.*] effort actually
  # reaches Codex — the lease lane already did this, the foreground lane did not.
  if [ -n "${CODEX_EFFORT:-}" ]; then
    AGENT_EFFORT="$CODEX_EFFORT"
  fi

  local INSTRUCTIONS=""
  if [ -n "$AGENT_INSTR_B64" ]; then
    INSTRUCTIONS=$(printf '%s' "$AGENT_INSTR_B64" | base64 -d 2>/dev/null || echo "")
  fi

  # `codex exec` accepts -m/-s but NOT -a (approval is set via -c override).
  # --full-auto was REMOVED in Codex 0.147.0 (PR 36054 — `error: unexpected
  # argument` on 0.154.0; the 2026-07 "deprecated, prints a warning" wording is
  # superseded per D-026). Its former semantics (workspace-write sandbox + never
  # approve) are supplied explicitly when an agent has no overrides.
  local CMD=(codex exec)
  [ -n "$AGENT_MODEL" ]    && CMD+=(-m "$AGENT_MODEL")
  [ -n "$AGENT_EFFORT" ]   && CMD+=(-c "model_reasoning_effort=\"${AGENT_EFFORT}\"")
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
  # carries the Triforge-level `output_schema` key, resolve the schema file at
  # the plugin tier (`${CLAUDE_PLUGIN_ROOT}/codex-agents/` — nothing ever
  # deployed a project copy, and `.codex/agents/` is now Codex's role-file
  # sweep, D-026) and pass
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
      if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/codex-agents/${AGENT_OUTPUT_SCHEMA}" ]; then
        SCHEMA_PATH="${CLAUDE_PLUGIN_ROOT}/codex-agents/${AGENT_OUTPUT_SCHEMA}"
      else
        echo "invoke_codex: WARNING agent '${AGENT_NAME}' requests output_schema '${AGENT_OUTPUT_SCHEMA}' but no such file in the plugin's codex-agents/ (CLAUDE_PLUGIN_ROOT unset or file missing) — running without --output-schema" >&2
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

  echo "invoke_codex: agent=${AGENT_NAME} model=${AGENT_MODEL:-session-default} effort=${AGENT_EFFORT:-session-default} sandbox=${AGENT_SANDBOX:-session-default} approval=${AGENT_APPROVAL:-session-default} hooks=${HOOKS_MODE} schema=${SCHEMA_PATH:-none} agents-toml=${AGENT_TOML:-none}" >&2

  # `< /dev/null` is mandatory: codex exec reads piped stdin ("Reading
  # additional input from stdin...") and hangs waiting for EOF whenever the
  # caller's stdin is not a TTY (probe record 2026-07-17).
  _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUTPUT_FILE" 2>&1 || EXIT_CODE=$?

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
        _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${BASE_CMD[@]}" "$PROMPT" < /dev/null > "${OUTPUT_FILE}.retry" 2>&1 || EXIT_CODE=$?
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

  # Codex prints two advisory lines into the captured stream that would
  # otherwise be promoted verbatim into ops/REVIEW_CODEX.md (commands/review.md
  # consumer): the --dangerously-bypass-hook-trust warning and, when a stale
  # .codex/agents/agents.toml is still present, "Ignoring malformed agent role
  # definition". Strip them from OUTPUT_FILE; the raw stream is not otherwise
  # altered.
  if [ -f "$OUTPUT_FILE" ]; then
    grep -vE '^(warning|WARN|WARNING):? .*bypass-hook-trust|Ignoring malformed agent role definition' "$OUTPUT_FILE" > "${OUTPUT_FILE}.clean" 2>/dev/null || true
    mv "${OUTPUT_FILE}.clean" "$OUTPUT_FILE" 2>/dev/null || true
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
