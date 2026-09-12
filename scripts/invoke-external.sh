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

# Host-marker scrub prefix for the foreground invoke_* lanes (see the header).
_HOST_SCRUB=(env -u CLAUDECODE -u CODEX_SANDBOX -u CODEX_SANDBOX_NETWORK_DISABLED
             -u CODEX_SESSION_ID -u CODEX_THREAD_ID -u CODEX_CI -u GROK_AGENT
             -u GROK_SESSION_ID -u CURSOR_AGENT -u CURSOR_CONVERSATION_ID
             -u OPENCODE_TERMINAL -u CLICOLOR_FORCE -u GH_FORCE_TTY NO_COLOR=1)

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
# Every constructed agy command pins the model: agy's own default is a
# (Medium) variant, so --model "${AGY_MODEL:-Gemini 3.8 Flash (High)}" is
# mandatory on every path — the newest Gemini at its highest thinking level
# (D-022, AGY-05 PASS 2026-09-11; "Gemini 3.1 Pro (High)" is the roster
# opt-in). The "(Low)/(Medium)/(High)" suffix is how agy encodes thinking
# effort (a dedicated --effort flag exists but is rejected for display names —
# AGY-11, KTD1), and AGY_MODEL is the override hook for the roster layer.
# Every command also passes --add-dir "$PWD": agy has no --cwd and otherwise
# runs shell commands in its own scratch dir (~/.gemini/antigravity-cli/scratch)
# instead of the project.
invoke_antigravity() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/antigravity_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local MODEL="${AGY_MODEL:-Gemini 3.8 Flash (High)}"
  local FULL_PROMPT=""
  local MODE=""
  local EXIT_CODE=0

  INVOKE_FAILURE_CLASS="none"
  _INVOKE_FAILURE_REASON=""

  # Deterministic preflight (KTD-9): a missing binary can never succeed on
  # retry — fail fast with the exact fix instead of burning a timeout window.
  if ! command -v agy >/dev/null 2>&1; then
    echo "invoke_antigravity: ERROR \`agy\` (Antigravity CLI) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: install it (curl -fsSL https://antigravity.google/cli/install.sh | bash), then run \`agy\` interactively once to complete login. No retry (deterministic)." >&2
    INVOKE_FAILURE_CLASS="deterministic"
    return 127
  fi

  # Mode switch (KTD10): TRIFORGE_AGY_MODE=injection|native|auto, default
  # injection this release. `auto` selects native when `agy agents` lists the
  # name (the pre-3.3.0 behavior); `native` forces --agent and falls back to
  # injection with a warning when the name is not listed; `injection` never
  # consults the listing. The default flips to auto only after AGY-12 (native
  # round-trip) AND AGY-16 (native-mode negative) pass for a full cycle —
  # native mode drops the injected body, and a mistyped tool name in a
  # definition can hang a reviewer. The resolved mode is written to
  # ${OUTPUT_FILE}.mode so promoted ops/ files can record it.
  local AGY_MODE_WANT="${TRIFORGE_AGY_MODE:-injection}"
  case "$AGY_MODE_WANT" in injection|native|auto) : ;; *)
    echo "invoke_antigravity: WARNING TRIFORGE_AGY_MODE='${AGY_MODE_WANT}' is not injection|native|auto — using injection" >&2
    AGY_MODE_WANT="injection" ;;
  esac
  local NATIVE_LISTING="" LISTED=0
  if [ "$AGY_MODE_WANT" != "injection" ]; then
    NATIVE_LISTING=$(_agy_agents_listing)
    if [ -n "$NATIVE_LISTING" ] && printf '%s\n' "$NATIVE_LISTING" | grep -qE "(^|[[:space:]])${AGENT_NAME}([[:space:]:,.]|$)"; then
      LISTED=1
    fi
  fi
  if [ "$LISTED" -eq 1 ]; then
    FULL_PROMPT="$PROMPT"
    MODE="native"
  elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents/${AGENT_NAME}.md" ]; then
    [ "$AGY_MODE_WANT" = "native" ] && echo "invoke_antigravity: WARNING TRIFORGE_AGY_MODE=native but \`agy agents\` does not list '${AGENT_NAME}' — falling back to injection (reinstall the pack: agy plugin install \${CLAUDE_PLUGIN_ROOT}/antigravity-agents)" >&2
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
  # --output-format json (D-032, KTD2): since agy 1.1.20/1.1.28 benign tool
  # errors and --print-timeout expiry exit 0, and a denied tool leaves
  # status=SUCCESS with an EMPTY response (lead probe 2026-09-11, agy 1.2.0:
  # {"status":"SUCCESS","response":"","denied_actions":[{"action":"read_url",...}]}).
  # The exit code is therefore not a completion signal — the envelope is.
  # stdout (the JSON) goes to ${OUTPUT_FILE}.raw and stderr (progress, the
  # "jetski:" line) to ${OUTPUT_FILE}.err; _agy_parse_envelope writes the prose
  # response to OUTPUT_FILE plus the .status / .denied sidecars that background
  # call sites read (they cannot see INVOKE_FAILURE_CLASS).
  local BASE_CMD=(agy --model "$MODEL" --add-dir "$PWD" --print-timeout "${TIMEOUT}s" --output-format json)
  local CMD=("${BASE_CMD[@]}")
  if [ "$MODE" = "native" ]; then
    CMD+=(--agent "$AGENT_NAME")
  fi
  local RAW="${OUTPUT_FILE}.raw" ERR="${OUTPUT_FILE}.err"
  rm -f "$OUTPUT_FILE" "$RAW" "$ERR" "${OUTPUT_FILE}.status" "${OUTPUT_FILE}.denied"
  printf '%s\n' "$MODE" > "${OUTPUT_FILE}.mode"

  echo "invoke_antigravity: agent=${AGENT_NAME} mode=${MODE} model=${MODEL}" >&2

  _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${CMD[@]}" -p "$FULL_PROMPT" < /dev/null > "$RAW" 2> "$ERR" || EXIT_CODE=$?

  # Envelope verdict on a clean exit: 0 usable prose; 11/13 empty (no denial /
  # non-SUCCESS status) -> retry once with the raw prompt; 10 denied+empty ->
  # deterministic (retry cannot lift a permission denial).
  local PRC=0 AGY_REASON=""
  if [ "$EXIT_CODE" -eq 0 ]; then
    _agy_parse_envelope "$RAW" "$OUTPUT_FILE" || PRC=$?
    case "$PRC" in
      0|12) : ;;
      10) EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="denied"; AGY_REASON="denied" ;;
      11) EXIT_CODE=1; INVOKE_FAILURE_CLASS="retryable"; AGY_REASON="no-output" ;;
      13) EXIT_CODE=1; INVOKE_FAILURE_CLASS="retryable"; AGY_REASON="status" ;;
      # Any other parser exit (an unguarded write failing inside the python
      # helper, an interpreter error) must never read as success: the output
      # file may be missing or stale. Same default the retry path carries.
      *)  EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="no-output"; AGY_REASON="parser-rc-${PRC}" ;;
    esac
  else
    _classify_invoke_failure "$EXIT_CODE" "$ERR"
    [ "$INVOKE_FAILURE_CLASS" = "retryable" ] && _classify_invoke_failure "$EXIT_CODE" "$RAW"
  fi

  # KTD-9: classify before reacting — only retryable failures get the
  # retry-once-with-raw-prompt treatment.
  #
  # Per-CLI by design (KTD-1): the classify -> case -> report -> retry tail below
  # LOOKS duplicated across the six invoke_* helpers, but the only shared part is
  # the 3-arm control flow — every arm's CONTENT is CLI-specific. The
  # deterministic messages name each CLI's own login/install fix; the capture
  # file differs ($OUTPUT_FILE / $RAW / $ERR); and the retryable arm re-runs a
  # DIFFERENT command per CLI. The one genuinely-shared primitive,
  # _classify_invoke_failure, is already extracted. Folding the rest into one
  # helper would need ~6 parameters (label, per-reason messages, retry command
  # array, capture var), shrink no call site meaningfully, and risk subtle
  # per-CLI behavior drift — so it stays inline. (Reviewed as an advisory dedup
  # candidate 2026-07; left inline per KTD-1: per-CLI quirks resist a generic
  # abstraction.)
  if [ "$EXIT_CODE" -ne 0 ]; then
    case "$INVOKE_FAILURE_CLASS" in
      deterministic)
        case "$_INVOKE_FAILURE_REASON" in
          denied)
            # Empty response + denied_actions: the run did nothing usable. Name
            # the user-tier allow rule per denied action (Triforge never writes
            # that file — R18). read_url is the common case since 1.1.28 made it
            # Ask; write denials against ops/ are benign only when a response
            # exists (then they ride the .denied sidecar into the promoted header).
            local DENIED_RULES
            DENIED_RULES=$(sed -E 's/^(.*)$/"\1(*)"/' "${OUTPUT_FILE}.denied" 2>/dev/null | paste -sd, - 2>/dev/null || true)
            echo "invoke_antigravity: agent=${AGENT_NAME} exit=${EXIT_CODE} denied — the run returned an empty response and agy denied: $(paste -sd, "${OUTPUT_FILE}.denied" 2>/dev/null). Fix (user tier, never automated): add permissions.allow: [${DENIED_RULES:-\"read_url(*)\"}] to ~/.gemini/antigravity-cli/settings.json, then re-run. No retry (deterministic)." >&2
            ;;
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
        # Denied leaves OUTPUT_FILE empty by contract (AE2: nothing is
        # promoted); every other deterministic failure surfaces the streams so
        # a captured-only caller never reads an empty file as "no findings".
        if [ "$_INVOKE_FAILURE_REASON" != "denied" ]; then
          cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true
        fi
        return "$EXIT_CODE"
        ;;
      timeout)
        echo "invoke_antigravity: agent=${AGENT_NAME} timed out after ${TIMEOUT}s (exit=${EXIT_CODE}). Requeue policy belongs to the caller (lease layer), not this helper." >&2
        cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true
        return "$EXIT_CODE"
        ;;
      retryable)
        echo "invoke_antigravity: agent=${AGENT_NAME} exit=${EXIT_CODE}${AGY_REASON:+ (${AGY_REASON})} (retryable), retrying with raw prompt" >&2
        EXIT_CODE=0
        _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${BASE_CMD[@]}" -p "$PROMPT" < /dev/null > "${RAW}.retry" 2> "${ERR}.retry" || EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 0 ]; then
          mv "${RAW}.retry" "$RAW"; mv "${ERR}.retry" "$ERR" 2>/dev/null || true
          PRC=0
          _agy_parse_envelope "$RAW" "$OUTPUT_FILE" || PRC=$?
          case "$PRC" in
            0|12) INVOKE_FAILURE_CLASS="none" ;;
            10) EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="denied"
                echo "invoke_antigravity: agent=${AGENT_NAME} retry denied — empty response, agy denied: $(paste -sd, "${OUTPUT_FILE}.denied" 2>/dev/null). Add the matching permissions.allow rule to ~/.gemini/antigravity-cli/settings.json (user tier)." >&2 ;;
            *)  EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="no-output"
                echo "invoke_antigravity: agent=${AGENT_NAME} retry also returned an empty response (status=$(cat "${OUTPUT_FILE}.status" 2>/dev/null)) — no-output. See ${RAW} / ${ERR}." >&2 ;;
          esac
        else
          _classify_invoke_failure "$EXIT_CODE" "${ERR}.retry"
          echo "invoke_antigravity: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}" >&2
          cat "${ERR}.retry" "${RAW}.retry" > "$OUTPUT_FILE" 2>/dev/null || true
        fi
        ;;
    esac
  fi

  if [ "$EXIT_CODE" -eq 0 ]; then
    local DENIED_LIST
    DENIED_LIST=$(paste -sd, "${OUTPUT_FILE}.denied" 2>/dev/null || true)
    echo "invoke_antigravity: agent=${AGENT_NAME} mode=${MODE} status=$(cat "${OUTPUT_FILE}.status" 2>/dev/null || echo unknown) denied=${DENIED_LIST:-none} output=${OUTPUT_FILE}" >&2
  fi
  return $EXIT_CODE
}

# _agy_parse_envelope <raw-json-file> <output-file> — parse agy's
# --output-format json envelope. Writes the prose `response` to <output-file>
# (only when non-empty), `status` to <output-file>.status (PARSE-FAIL when the
# stream is not JSON), and one denied action per line to <output-file>.denied
# (empty file when none). Return codes:
#    0  non-empty response (denials, if any, are listed in .denied)
#   10  empty response AND denied_actions present   -> deterministic (denied)
#   11  empty response, no denial, status SUCCESS   -> no-output
#   12  not JSON — raw stream copied to <output-file>, status PARSE-FAIL
#   13  empty response with a non-SUCCESS status (ERROR/CANCELED/INTERRUPTED/
#       INVALID/WAITING/RUNNING)
# python3 reads its inputs from prefixed env vars (repo convention; no jq).
_agy_parse_envelope() {
  local RAW=$1 OUT=$2
  local PRC=0
  AGY_RAW="$RAW" AGY_OUT="$OUT" python3 - <<'PYAGY' || PRC=$?
import json, os, sys
raw_path = os.environ["AGY_RAW"]; out = os.environ["AGY_OUT"]
try:
    raw = open(raw_path, "r", errors="replace").read()
except OSError:
    raw = ""
obj = None
text = raw.strip()
if text:
    try:
        obj = json.loads(text)
    except Exception:
        dec = json.JSONDecoder(); i = 0; n = len(text)
        while i < n:
            while i < n and text[i] != "{":
                i += 1
            if i >= n:
                break
            try:
                val, end = dec.raw_decode(text, i)
                if isinstance(val, dict) and ("status" in val or "response" in val):
                    obj = val
                i = end
            except Exception:
                i += 1
if not isinstance(obj, dict):
    with open(out, "w") as f:
        f.write(raw)
    with open(out + ".status", "w") as f:
        f.write("PARSE-FAIL\n")
    open(out + ".denied", "w").close()
    sys.exit(12)
status = str(obj.get("status") or "").strip() or "UNKNOWN"
resp = obj.get("response")
if not isinstance(resp, str):
    resp = "" if resp is None else json.dumps(resp)
denied = []
for d in obj.get("denied_actions") or []:
    if isinstance(d, dict):
        name = d.get("action") or d.get("display_name") or d.get("name")
    else:
        name = d
    if name:
        denied.append(str(name))
with open(out + ".status", "w") as f:
    f.write(status + "\n")
with open(out + ".denied", "w") as f:
    for d in denied:
        f.write(d + "\n")
if resp.strip():
    with open(out, "w") as f:
        f.write(resp.strip() + "\n")
    sys.exit(0)
open(out, "w").close()
if denied:
    sys.exit(10)
if status != "SUCCESS":
    sys.exit(13)
sys.exit(11)
PYAGY
  return $PRC
}

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

# ---------------------------------------------------------------------------
# OpenCode invocation (optional tier — builder + reviewer on OpenRouter)
# ---------------------------------------------------------------------------
#
# OpenCode has a real `--agent <name>` flag (unlike Codex) that selects a
# markdown agent def from `.opencode/agents/` (project tier) or, via the
# session-start bootstrap, the plugin's `opencode-agents/`. Every call pins the
# model with -m "${OPENCODE_MODEL:-openrouter/z-ai/glm-5.3}" — OPENCODE_MODEL is
# the roster override hook; the shipped default is the OpenRouter GLM 5.3
# (D-023, OC-04 PASS 2026-09-11; preloaded in models.dev, no provider entry
# needed).
#
# Structured capture (probe OC-03): `--format json` streams SSE-style events
# (message.updated carries the message role via properties.info; message.part.updated
# carries a TextPart with the assistant's text; session.error carries failures —
# the opencode SDK event union). The assistant reply is the concatenation of its
# non-synthetic TextPart.text values; a python3 parser extracts it into
# OUTPUT_FILE (no literal backticks in the heredoc). On any parse failure the
# raw stream is preserved so nothing is lost.
#
# NEVER --auto (probe OC-06, 2026-07-17, still FAIL on 1.18.30 2026-09-11 —
# docs and source say an explicit deny is enforced under --auto, the harness
# disagrees, two lead re-probes hung; open watch D-033): a deny rule in
# opencode.json did NOT survive --auto (the denied command executed), so this
# helper never passes it. Defense-in-depth: every run also exports
# OPENCODE_PERMISSION (the same deny set as templates/.opencode/opencode.json —
# rm -rf, git push, sudo) unless the caller set its own. Reviewer read-only
# safety is the agent-def permission map (opencode-agents/reviewer.md denies
# edit/bash); builder confinement is the lease worktree + _adapter_env
# allowlist (R35), never opencode.json denies.
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
# Shipped OPENCODE_PERMISSION deny set — mirrors templates/.opencode/opencode.json
# (D-033 defense-in-depth; the adapter stays off --auto regardless).
_OPENCODE_PERMISSION_DEFAULT='{"bash":{"*":"allow","rm -rf *":"deny","git push*":"deny","sudo *":"deny"}}'

# _oc_extract_text <raw-stream-file> <output-file> — extract the assistant's final
# text from a opencode JSON event stream (`opencode run --format json`) into <output-file>; exits nonzero (writing nothing)
# when no text is found so the caller can preserve the raw stream. Shared by
# the foreground invoke_* helper and the lease lane (lease_dispatch), whose
# builders answer in the same stream shape — the typed `Status:` report
# (KTD11) is only parseable from the extracted prose.
_oc_extract_text() {
  OC_RAW="$1" OC_OUT="$2" python3 -c '
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
' 2>/dev/null
}

# _kimi_extract_text <raw-stream-file> <output-file> — extract the assistant's final
# text from a kimi stream-json into <output-file>; exits nonzero (writing nothing)
# when no text is found so the caller can preserve the raw stream. Shared by
# the foreground invoke_* helper and the lease lane (lease_dispatch), whose
# builders answer in the same stream shape — the typed `Status:` report
# (KTD11) is only parseable from the extracted prose.
_kimi_extract_text() {
  K_RAW="$1" K_OUT="$2" python3 -c '
import json, os, sys
raw = open(os.environ["K_RAW"], "r", errors="replace").read()

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

def norm(ev):
    if not isinstance(ev, dict):
        return None
    msg = ev.get("message") if isinstance(ev.get("message"), dict) else ev
    role = msg.get("role") or ev.get("role")
    if role is None:
        t = ev.get("type") or msg.get("type")
        if t in ("assistant", "tool", "user", "system"):
            role = t
    mid = msg.get("id") or ev.get("id")
    content = msg.get("content")
    if content is None:
        content = ev.get("content")
    if content is None:
        content = ev.get("text") or msg.get("text")
    text = ""
    if isinstance(content, str):
        text = content
    elif isinstance(content, list):
        parts = []
        for p in content:
            if isinstance(p, str):
                parts.append(p)
            elif isinstance(p, dict):
                if isinstance(p.get("text"), str):
                    parts.append(p["text"])
                elif p.get("type") == "text" and isinstance(p.get("content"), str):
                    parts.append(p["content"])
        text = "".join(parts)
    elif isinstance(content, dict):
        if isinstance(content.get("text"), str):
            text = content["text"]
    return (role, mid, text)

order = []
by_id = {}
seq = 0
for ev in iter_events(raw):
    r = norm(ev)
    if r is None:
        continue
    role, mid, text = r
    if role != "assistant" or not isinstance(text, str) or not text.strip():
        continue
    key = mid if mid is not None else ("_%d" % seq)
    if key not in by_id:
        by_id[key] = text
        order.append(key)
        seq += 1
    elif len(text) >= len(by_id[key]):
        by_id[key] = text

final = by_id[order[-1]] if order else ""
if not final.strip():
    sys.stderr.write("no assistant text found in kimi stream-json\n")
    sys.exit(3)

with open(os.environ["K_OUT"], "w") as f:
    f.write(final.strip() + "\n")
' 2>/dev/null
}

# _cursor_extract_text <raw-stream-file> <output-file> — extract the assistant's final
# text from a cursor-agent stream-json into <output-file>; exits nonzero (writing nothing)
# when no text is found so the caller can preserve the raw stream. Shared by
# the foreground invoke_* helper and the lease lane (lease_dispatch), whose
# builders answer in the same stream shape — the typed `Status:` report
# (KTD11) is only parseable from the extracted prose.
_cursor_extract_text() {
  C_RAW="$1" C_OUT="$2" python3 -c '
import json, os, sys
raw = open(os.environ["C_RAW"], "r", errors="replace").read()

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

def extract_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for p in content:
            if isinstance(p, str):
                parts.append(p)
            elif isinstance(p, dict) and isinstance(p.get("text"), str):
                parts.append(p["text"])
        return "".join(parts)
    if isinstance(content, dict) and isinstance(content.get("text"), str):
        return content["text"]
    return ""

assistant_texts = []
result_text = ""
result_seen = False
result_is_error = False
for ev in iter_events(raw):
    if not isinstance(ev, dict):
        continue
    t = ev.get("type")
    if t == "assistant":
        msg = ev.get("message") if isinstance(ev.get("message"), dict) else ev
        text = extract_text(msg.get("content"))
        if text.strip():
            assistant_texts.append(text)
    elif t == "result":
        r = ev.get("result")
        if isinstance(r, str):
            result_text = r
            result_seen = True
            result_is_error = bool(ev.get("is_error"))

final = ""
if result_seen and not result_is_error and result_text.strip():
    final = result_text
elif assistant_texts:
    final = assistant_texts[-1]
elif result_seen and result_text.strip():
    final = result_text

if not final.strip():
    sys.stderr.write("no assistant/result text found in cursor stream-json\n")
    sys.exit(3)

with open(os.environ["C_OUT"], "w") as f:
    f.write(final.strip() + "\n")
' 2>/dev/null
}

# invoke_opencode <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
invoke_opencode() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/opencode_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${OPENCODE_EFFORT:-}}
  local MODEL="${OPENCODE_MODEL:-openrouter/z-ai/glm-5.3}"
  local MODE="" EXIT_CODE=0
  local RAW="${OUTPUT_FILE}.raw"
  local OC_PERM="${OPENCODE_PERMISSION:-$_OPENCODE_PERMISSION_DEFAULT}"

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
  local BASE=(env "OPENCODE_PERMISSION=${OC_PERM}" opencode run --format json -m "$MODEL")
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
  _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${ATTEMPT[@]}" "$PROMPT" > "$RAW" 2>&1 || EXIT_CODE=$?

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
        _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${BASE[@]}" "$PROMPT" > "${RAW}.retry" 2>&1 || EXIT_CODE=$?
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
  if _oc_extract_text "$RAW" "$OUTPUT_FILE"; then
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
# Kimi Code invocation (optional tier — builder + reviewer on Kimi)
# ---------------------------------------------------------------------------
#
# Kimi Code (binary: kimi) >= 0.33 has a native agent surface (probe KIMI-03
# flipped FAIL -> PASS on 0.42.0, 2026-09-11): `--agent-file <path>` loads a
# Markdown agent definition whose body extends Kimi's own prompt through the
# ${base_prompt} / ${skills} / ${agents_md} template variables and whose
# frontmatter carries a `tools` allowlist (the reviewer's read-only boundary)
# and `subagents: []` (no delegation). Roles therefore ride the plugin's
# kimi-agents/<name>.md as --agent-file on BOTH attempts (D-024) — dropping it
# on retry would re-run the reviewer with Kimi's full toolset. The absolute
# plugin path is composed here so it also crosses env -i in the lease lane.
# An agent-file load/parse error is deterministic (no retry). The project
# .kimi-code/AGENTS.md role sections remain as documentation.
#
# Every call pins the model with -m "${KIMI_MODEL:-kimi-code/k3}" — KIMI_MODEL
# is the roster override hook; the shipped default is the OAuth-managed alias
# kimi-code/k3 (D-024 — the former open-platform id (history: kimi-k3) fails on OAuth
# hosts). Live verification is PENDING-AUTH on this host until `kimi login`
# (KIMI-05/06/08/09 in the newest probe record).
#
# Auth (probe KIMI-05, AUTH-FAIL on this host): `kimi doctor` validates CONFIG
# ONLY and PASSES when signed out, so it cannot gate auth. A signed-out headless
# call fails fast BEFORE any network round-trip with "No model configured. Run
# `kimi` and use /login...". This helper classifies that output text as a
# deterministic auth failure (exact fix, NO retry-storm) — mirroring
# roster_member_auth's kimi branch — instead of burning a retry on a doomed call.
#
# Telemetry (probe KIMI-07, R25): env KIMI_DISABLE_TELEMETRY=1 is set on EVERY
# invocation (and in templates/.kimi-code/config.toml via telemetry=false).
#
# Skills interop (probe KIMI-04, D-024): Kimi discovers .agents/skills/ natively
# and --skills-dir REPLACES that auto-discovery, so the flag is no longer passed;
# skills are invoked as /skill:<name>.
#
# Structured capture: --output-format stream-json emits one JSON object per line
# (assistant/tool chat messages; thinking stays on stderr — clean separation, so
# stdout is captured separately for the answer). A python3 parser (no literal
# backticks) extracts the assistant's FINAL text into OUTPUT_FILE; on any parse
# failure the raw stream is preserved so nothing looks like "no findings".
#
# Effort: Kimi K3 reasoning is max-effort-only (fact sheet) — there is no headless
# thinking-level flag, so the effort arg is largely inert. It is recorded for
# roster parity, never fabricated into a flag.
#
# Failure taxonomy (KTD-9): reuses _classify_invoke_failure exactly like the
# other helpers, plus the deterministic auth override above and a missing-binary
# preflight, so a call that cannot succeed fails fast with the exact fix.
#
# invoke_kimi <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
invoke_kimi() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/kimi_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${KIMI_EFFORT:-}}
  local MODEL="${KIMI_MODEL:-kimi-code/k3}"
  local MODE="" EXIT_CODE=0
  local RAW="${OUTPUT_FILE}.raw"
  local ERR="${OUTPUT_FILE}.err"
  local AGENT_FILE=""

  INVOKE_FAILURE_CLASS="none"
  _INVOKE_FAILURE_REASON=""

  # Deterministic preflight (KTD-9): a missing binary can never succeed on retry
  # — fail fast with the exact fix (G12 install guidance) instead of burning a
  # timeout window.
  if ! command -v kimi >/dev/null 2>&1; then
    echo "invoke_kimi: ERROR \`kimi\` (Kimi Code CLI) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: install it (curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash), then run \`kimi login\`. No retry (deterministic)." >&2
    # Write the guidance to OUTPUT_FILE too: a caller (e.g. a review fan-out)
    # that only reads the file must not mistake an empty file for "no findings"
    # (the exact trap CLAUDE.md warns about).
    echo "invoke_kimi: kimi CLI not on PATH — install: curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="binary-missing"
    return 127
  fi

  # Agent resolution (KIMI-03 PASS on 0.42.0, D-024): the plugin's
  # kimi-agents/<name>.md is a native agent definition loaded through
  # --agent-file (absolute path). It carries the reviewer's read-only `tools`
  # allowlist and `subagents: []`, so it rides on BOTH attempts — never
  # injected, never dropped on retry. Else raw with a warning naming the
  # available definitions. An empty AGENT_NAME is a deliberate raw run (the
  # READY plumbing probe and lease_dispatch's direct builder command).
  local FULL_PROMPT="$PROMPT"
  if [ -n "$AGENT_NAME" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/kimi-agents/${AGENT_NAME}.md" ]; then
    AGENT_FILE="${CLAUDE_PLUGIN_ROOT}/kimi-agents/${AGENT_NAME}.md"
    MODE="agent-file"
  elif [ -n "$AGENT_NAME" ]; then
    local AVAILABLE
    AVAILABLE=$(_list_kimi_agents | paste -sd, - 2>/dev/null || echo "")
    echo "invoke_kimi: WARNING agent '${AGENT_NAME}' not found in plugin kimi-agents/; falling through to raw prompt (no agent definition applied). Available definitions: ${AVAILABLE:-<none>}" >&2
    MODE="raw"
  else
    MODE="raw"
  fi

  # Command core: pin model, stream-json capture, telemetry off (R25), the
  # agent definition when resolved. No --skills-dir (it would REPLACE Kimi's
  # native .agents/skills discovery — KIMI-04/D-024). No --yolo/--auto: -p
  # already runs Kimi's auto policy; reviewer read-only is the agent file's
  # tools allowlist + worktree confinement (kimi-agents/reviewer.md).
  # Flag order matters (commander.js): `-p <prompt>` consumes the NEXT token as
  # its value, so -p MUST come last with the prompt right after it — otherwise
  # `-p --output-format` swallows the format flag and kimi errors "unknown
  # command 'stream-json'". BASE carries everything BEFORE the prompt; each call
  # appends `-p "<prompt>"` itself (matches the KIMI-05 probe invocation order).
  local BASE=(kimi --output-format stream-json -m "$MODEL")
  [ -n "$AGENT_FILE" ] && BASE+=(--agent-file "$AGENT_FILE")

  echo "invoke_kimi: agent=${AGENT_NAME:-<none>} mode=${MODE} model=${MODEL} effort=${EFFORT:-none} (recorded for roster parity — Kimi exposes no headless effort flag) agent-file=${AGENT_FILE:-none}" >&2

  # stdout -> RAW (clean JSONL for the parser), stderr -> ERR (thinking/progress
  # AND the signed-out error text). KIMI_DISABLE_TELEMETRY rides via `env` so it
  # is set no matter the caller's environment.
  _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" KIMI_DISABLE_TELEMETRY=1 "${BASE[@]}" -p "$FULL_PROMPT" > "$RAW" 2>"$ERR" || EXIT_CODE=$?

  if [ "$EXIT_CODE" -ne 0 ]; then
    # Deterministic overrides FIRST (KIMI-05): kimi doctor cannot gate auth, so
    # classify from the CLI's own error text before falling back to the shared
    # classifier. Two signed-out shapes, both deterministic (retry cannot help),
    # NEVER a retry-storm (mirrors roster_member_auth's kimi branch and
    # invoke_opencode's local provider-not-found override):
    #   auth         no -m  -> "No model configured ... use /login"
    #   model-config with -m -> "config.invalid: Model \"kimi-code/k3\" is not
    #                configured in config.toml" — login provisions the managed
    #                model aliases, so a signed-out host has none (also fires on a
    #                genuinely bad KIMI_MODEL override). Distinct reason so the
    #                fix guidance is accurate for both causes.
    if grep -qiE 'no model configured|use /login|/login|not (logged|signed) in|unauthorized|401|credential|authentication (failed|required|expired)' "$RAW" "$ERR" 2>/dev/null; then
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="auth"
    elif grep -qiE 'is not configured in config\.toml|config\.invalid|model .* (is )?not configured|no such model|unknown model' "$RAW" "$ERR" 2>/dev/null; then
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="model-config"
    elif [ -n "$AGENT_FILE" ] && grep -qiE 'agent[- ]file|failed to (load|parse) agent|invalid agent|agent definition' "$RAW" "$ERR" 2>/dev/null; then
      # A definition Kimi cannot load fails identically on retry — and a retry
      # without it would silently drop the reviewer's tools allowlist.
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="agent-file"
    else
      _classify_invoke_failure "$EXIT_CODE" "$ERR"
    fi
    case "$INVOKE_FAILURE_CLASS" in
      deterministic)
        case "$_INVOKE_FAILURE_REASON" in
          auth)
            echo "invoke_kimi: agent=${AGENT_NAME} exit=${EXIT_CODE} auth failure — kimi is not signed in (\"No model configured\"). Fix: run \`kimi login\` (or launch \`kimi\` and use /login), or set the Kimi API key. No retry (deterministic)." >&2
            ;;
          model-config)
            echo "invoke_kimi: agent=${AGENT_NAME} exit=${EXIT_CODE} model '${MODEL}' not configured — either kimi is not signed in (\`kimi login\` provisions the managed aliases, kimi-code/k3 included) or KIMI_MODEL names a model with no [models.*] entry in ~/.kimi-code/config.toml. Fix: run \`kimi login\`, or set KIMI_MODEL to a configured alias. No retry (deterministic)." >&2
            ;;
          agent-file)
            echo "invoke_kimi: agent=${AGENT_NAME} exit=${EXIT_CODE} kimi could not load the agent definition ${AGENT_FILE} (see ${ERR}). The definition carries the role's tools allowlist, so it is never dropped on retry — fix the file. No retry (deterministic)." >&2
            ;;
          binary-missing)
            echo "invoke_kimi: agent=${AGENT_NAME} exit=${EXIT_CODE} — \`kimi\` disappeared from PATH mid-run. Fix: install it (curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash), then run \`kimi login\`. No retry (deterministic)." >&2
            ;;
          *)
            echo "invoke_kimi: agent=${AGENT_NAME} exit=${EXIT_CODE} deterministic failure (${_INVOKE_FAILURE_REASON:-see error above}). No retry." >&2
            ;;
        esac
        # Guidance to OUTPUT_FILE too (see binary-missing note above) so a
        # captured-only caller does not read an empty file as "no findings":
        # the raw streams first, then an explicit fix line for the signed-out
        # shapes.
        cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true
        case "$_INVOKE_FAILURE_REASON" in
          auth)
            echo "invoke_kimi: kimi is not signed in — run: kimi login (or launch kimi and use /login), or set the Kimi API key" >> "$OUTPUT_FILE" 2>/dev/null || true
            ;;
          model-config)
            echo "invoke_kimi: model '${MODEL}' not configured — run: kimi login (provisions the managed aliases, kimi-code/k3 included), or set KIMI_MODEL to a configured model" >> "$OUTPUT_FILE" 2>/dev/null || true
            ;;
        esac
        rm -f "$RAW" "$ERR"
        return "$EXIT_CODE"
        ;;
      timeout)
        echo "invoke_kimi: agent=${AGENT_NAME} timed out after ${TIMEOUT}s (exit=${EXIT_CODE}). Requeue policy belongs to the caller (lease layer), not this helper." >&2
        cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true
        rm -f "$RAW" "$ERR"
        return "$EXIT_CODE"
        ;;
      retryable)
        # Single retry: raw prompt. BASE keeps the model pin, stream-json, AND
        # --agent-file (D-024: the definition is the reviewer's enforcement
        # boundary, so it is never dropped — unlike the sibling helpers' prompt
        # prefixes, which are safe to shed).
        echo "invoke_kimi: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable), retrying once with raw prompt" >&2
        EXIT_CODE=0
        _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" KIMI_DISABLE_TELEMETRY=1 "${BASE[@]}" -p "$PROMPT" > "${RAW}.retry" 2>"${ERR}.retry" || EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 0 ]; then
          mv "${RAW}.retry" "$RAW"
          mv "${ERR}.retry" "$ERR" 2>/dev/null || true
          INVOKE_FAILURE_CLASS="none"
        else
          _classify_invoke_failure "$EXIT_CODE" "${ERR}.retry"
          echo "invoke_kimi: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}" >&2
          cat "${ERR}.retry" "${RAW}.retry" > "$OUTPUT_FILE" 2>/dev/null || true
          rm -f "$RAW" "$ERR" "${RAW}.retry" "${ERR}.retry"
          return "$EXIT_CODE"
        fi
        ;;
    esac
  fi

  # Structured capture (success path): extract the assistant's FINAL text from
  # the stream-json stdout into OUTPUT_FILE. Each line is a chat-message JSON
  # object; regular replies are Assistant messages, tool turns interleave
  # Assistant(tool_calls)+Tool messages. Parser keeps the longest text per
  # message id (cumulative-delta safe), returns the LAST non-empty assistant
  # message text, and exits nonzero when it finds none — raw stream preserved.
  if _kimi_extract_text "$RAW" "$OUTPUT_FILE"; then
    :
  else
    echo "invoke_kimi: WARNING could not extract assistant text from kimi stream-json — preserving raw stream in ${OUTPUT_FILE}" >&2
    cat "$RAW" "$ERR" > "$OUTPUT_FILE" 2>/dev/null || cp "$RAW" "$OUTPUT_FILE" 2>/dev/null || true
  fi
  rm -f "$RAW" "$ERR" "${RAW}.retry" "${ERR}.retry"
  return $EXIT_CODE
}

# List known Kimi agent-definition names: the plugin kimi-agents/ files
# (basename without .md), excluding README. These are loaded via --agent-file
# (D-024); nothing is bootstrapped into .agents/agents/ (KTD13: agy and Kimi
# both scan it with incompatible vocabularies).
_list_kimi_agents() {
  {
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/kimi-agents" ]; then
      for f in "${CLAUDE_PLUGIN_ROOT}/kimi-agents"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f" .md)" in README) continue ;; esac
        basename "$f" .md
      done 2>/dev/null
    fi
  } | sort -u
}

# ---------------------------------------------------------------------------
# Cursor CLI invocation (optional tier — builder + reviewer on Grok)
# ---------------------------------------------------------------------------
#
# Cursor (binary: cursor-agent) has NO headless custom-agent selector (re-probed
# 2026-07-18, cursor-agent 2026.07.16-*): `cursor-agent --help` exposes no
# `--agent <name>` flag — the .cursor/agents/ defs are delegation triggers for
# background subagents, not a headless top-level selector. Roles are therefore
# INJECTION-ONLY, exactly like invoke_kimi: the cursor-agents/<name>.md brief
# body is prefixed onto the prompt (never a native flag). The project-tier
# backstop is the copied .cursor/agents/ defs (valid cursor agent defs) plus the
# AGENTS.md / CLAUDE.md at the repo root, which cursor reads.
#
# Every call pins the model with --model "${CURSOR_MODEL:-cursor-grok-4.6-xhigh}"
# — NEVER the Auto router (CUR-03/CUR-05): ledger attribution needs a named
# model, and Auto resolves nondeterministically. CURSOR_MODEL is the roster
# override hook; cursor-grok-4.6-xhigh is the shipped default (D-025; Composer
# 2.5 is the leading alternative).
#
# Binary (D-025): the install script now names `agent` primary and `cursor-agent`
# legacy, but an unrelated ~/.grok/bin/agent shadows it on some hosts, so
# _cursor_bin resolves `cursor-agent` first and accepts an `agent` only when its
# --version matches Cursor's YYYY.MM.DD-<hex> build id (CUR-11).
#
# --trust is MANDATORY headless (CUR-04): it bypasses the workspace-trust prompt
# that otherwise blocks a non-TTY run. -p/--print is a BOOLEAN flag here (unlike
# kimi's value-consuming -p), so the prompt is a TRAILING POSITIONAL argument
# after every option — verified live 2026-07-18 (the READY probe echoed READY
# with the prompt last). Do NOT place the prompt right after -p.
#
# Role -> flags (the helper learns the role from CURSOR_ROLE, else infers it from
# the agent name):
#   reviewer -> --mode plan   read-only enforced (CUR-08: a write did not land);
#               NOT --force. --sandbox is NOT used — CUR-07 proved --sandbox
#               enabled did not confine (an absolute-path write escaped), so
#               reviewer read-only rests on --mode plan and builder confinement
#               is the lease worktree + env allowlist (R35), never --sandbox.
#   builder  -> --force        apply edits without confirmation (within the R35
#               worktree). NOT --mode plan.
#   <other>  -> neither        a plain query (the READY plumbing probe): matches
#               the CUR-04 probe shape exactly (no --force, no --mode plan).
#
# Structured capture: --output-format stream-json emits one JSON object per line
# on stdout (system/user/thinking/assistant/result); stderr stays clean. A
# python3 parser (no literal backticks) prefers the terminal result event's text
# (cursor's canonical final answer), falling back to the last assistant message;
# on any parse failure the raw stream is preserved so nothing looks like "no
# findings".
#
# Effort (D-025, CUR-10/CUR-12): cursor has no reasoning-effort flag and REJECTS
# the documented bracket form (grok-4.6[effort=xhigh] -> "Cannot use this
# model"); effort is the model-id SUFFIX: cursor-grok-4.6-low|medium|high|xhigh.
# _cursor_model_for_effort composes the suffixed id from a bare Grok family name
# + the roster effort (xhigh/max -> -xhigh) and passes an explicit suffixed id
# through untouched (effort recorded "in model id"). Never a fabricated suffix
# for an unknown effort — the bare id is used with a warning.
#
# Failure taxonomy (KTD-9): reuses _classify_invoke_failure exactly like the
# other helpers, plus a deterministic auth preflight (`cursor-agent status`) and a
# missing-binary preflight, so a call that cannot succeed fails fast with the
# exact fix.
#
# _cursor_bin — print the Cursor CLI binary to use (D-025, CUR-11). Order:
#   1. TRIFORGE_CURSOR_BIN when already resolved this session (also honored by
#      resolve_role's Python BINARY map)
#   2. `cursor-agent` on PATH (the legacy name Cursor still ships as a symlink)
#   3. every `agent` on PATH, in order, whose `--version` (15 s, fail-closed
#      timeout wrapper) matches Cursor's ^YYYY.MM.DD-<hex> build id — an
#      unrelated ~/.grok/bin/agent (prints "grok 0.2.118") is rejected
# Returns 1 (prints nothing) when none qualifies. PATH is walked by python3 so
# the same code runs under bash and zsh (this file is sourced under either).
# No file cache: a PID-keyed path under TMPDIR is predictable on shared-/tmp
# hosts and was executed after only an -x check (CWE-377/427). Reuse rides
# solely on the exported TRIFORGE_CURSOR_BIN; a fresh shell re-resolves, which
# costs one `--version` per PATH candidate only on hosts without cursor-agent.
_cursor_bin() {
  if [ -n "${TRIFORGE_CURSOR_BIN:-}" ] && [ -x "$TRIFORGE_CURSOR_BIN" ]; then
    printf '%s\n' "$TRIFORGE_CURSOR_BIN"; return 0
  fi
  local CAND="" V=""
  if CAND=$(command -v cursor-agent 2>/dev/null) && [ -n "$CAND" ]; then
    export TRIFORGE_CURSOR_BIN="$CAND"
    printf '%s\n' "$CAND"; return 0
  fi
  while IFS= read -r CAND; do
    [ -n "$CAND" ] || continue
    V=$(_run_with_timeout 15 "$CAND" --version 2>/dev/null | head -1 || true)
    if printf '%s' "$V" | grep -qE '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9a-f]+'; then
      export TRIFORGE_CURSOR_BIN="$CAND"
      printf '%s\n' "$CAND"; return 0
    fi
  done <<AGENTS
$(python3 -c "
import os
seen = set()
for d in os.environ.get('PATH', '').split(os.pathsep):
    c = os.path.join(d, 'agent')
    if os.path.isfile(c) and os.access(c, os.X_OK) and c not in seen:
        seen.add(c); print(c)
" 2>/dev/null)
AGENTS
  return 1
}

# _cursor_model_for_effort <model> <effort> — compose Cursor's suffixed model id
# (D-025: effort rides in the id, cursor-grok-4.6-low|medium|high|xhigh).
#   bare family (grok-4.6 / cursor-grok-4.6) + effort -> cursor-grok-4.6-<sfx>
#   explicit suffixed id                              -> unchanged ("in model id")
#   empty effort                                      -> unchanged
#   unknown effort                                    -> bare id + warning (never a fabricated suffix)
#   non-Grok id (composer-2.5, …)                      -> unchanged
# Sets _CURSOR_EFFORT_NOTE for the stderr summary.
# Sibling: roster_write_role's cursor branch is the WRITE-time composer — it
# normalizes a conflicting explicit suffix to the effort (with a NOTE) so the
# stored pin is self-consistent; this dispatch-time composer honors the stored
# pin as written (cursor-agents/builder.md). Same regex in both — keep them in
# step when the Cursor id format changes.
_CURSOR_EFFORT_NOTE=""
_cursor_model_for_effort() {
  local M=${1:-} E=${2:-}
  _CURSOR_EFFORT_NOTE="in model id"
  CM_MODEL="$M" CM_EFFORT="$E" python3 -c "
import os, re, sys
m = os.environ['CM_MODEL']; e = os.environ['CM_EFFORT']
sfx = {'low': 'low', 'medium': 'medium', 'high': 'high', 'xhigh': 'xhigh', 'max': 'xhigh'}
mm = re.match(r'^(?:cursor-)?(grok-[0-9][0-9.]*?)(?:-(low|medium|high|xhigh))?(-fast)?\$', m)
if not e or not mm:
    print(m); sys.exit(0)
fam, had, fast = mm.group(1), mm.group(2), mm.group(3) or ''
if had:
    print('cursor-' + fam + '-' + had + fast); sys.exit(0)   # explicit suffix wins
if e not in sfx:
    sys.stderr.write('invoke_cursor: WARNING unknown effort ' + repr(e) + ' — passing the bare model ' + repr(m) + ' through (no fabricated suffix)\n')
    print(m); sys.exit(0)
print('cursor-' + fam + '-' + sfx[e] + fast)
"
}

# invoke_cursor <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
invoke_cursor() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/cursor_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${CURSOR_EFFORT:-}}
  local MODEL="${CURSOR_MODEL:-cursor-grok-4.6-xhigh}"
  local MODE="" EXIT_CODE=0
  local RAW="${OUTPUT_FILE}.raw"
  local ERR="${OUTPUT_FILE}.err"
  local CBIN=""

  INVOKE_FAILURE_CLASS="none"
  _INVOKE_FAILURE_REASON=""

  # Effort -> model-id suffix (D-025); the composed id is what --model carries.
  MODEL=$(_cursor_model_for_effort "$MODEL" "$EFFORT")

  # Deterministic preflight 1 (KTD-9): a missing binary can never succeed on
  # retry — fail fast with the exact fix (G12 install guidance) instead of
  # burning a timeout window. _cursor_bin: cursor-agent first, verified `agent`
  # fallback (CUR-11 rejects the unrelated ~/.grok/bin/agent).
  if ! CBIN=$(_cursor_bin); then
    echo "invoke_cursor: ERROR no Cursor CLI on PATH (\`cursor-agent\`, or an \`agent\` whose --version matches YYYY.MM.DD-<hex>) — cannot invoke agent '${AGENT_NAME}'. Fix: install it (curl https://cursor.com/install -fsS | bash), then run \`cursor-agent login\`. No retry (deterministic)." >&2
    # Write the guidance to OUTPUT_FILE too: a caller (e.g. a review fan-out)
    # that only reads the file must not mistake an empty file for "no findings"
    # (the exact trap CLAUDE.md warns about).
    echo "invoke_cursor: cursor-agent CLI not on PATH — install: curl https://cursor.com/install -fsS | bash" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="binary-missing"
    return 127
  fi

  # Deterministic preflight 2 (KTD-9): a signed-out cursor-agent cannot make a
  # live call. `cursor-agent status` is a pure local auth query (no tokens, exits
  # 0 when logged in); a missing "Logged in" line is a deterministic auth failure
  # — fail fast with the fix rather than retry a doomed call (mirrors
  # roster_member_auth's cursor branch). Output captured (not piped) so the
  # exit-code / pipefail interaction cannot misfire.
  local STATUS_OUT=""
  STATUS_OUT=$(_run_with_timeout 15 "$CBIN" status 2>&1) || true
  if ! printf '%s' "$STATUS_OUT" | grep -qi 'logged in'; then
    echo "invoke_cursor: ERROR agent='${AGENT_NAME}' — cursor-agent is not logged in (\`cursor-agent status\` did not report 'Logged in'). Fix: run \`cursor-agent login\` (or set CURSOR_API_KEY). No retry (deterministic)." >&2
    # Guidance to OUTPUT_FILE too (see binary-missing note above).
    echo "invoke_cursor: cursor-agent not logged in — run: cursor-agent login (or set CURSOR_API_KEY)" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="auth"
    return 1
  fi

  # Agent resolution: cursor has NO headless --agent selector (re-probed
  # 2026-07-18) -> INJECTION ONLY. The cursor-agents/<name>.md body (after
  # frontmatter) is prefixed onto the prompt (reusing the awk frontmatter-strip);
  # else raw with a warning naming the available briefs. An empty AGENT_NAME is a
  # deliberate raw run (the READY plumbing probe).
  local FULL_PROMPT="$PROMPT"
  if [ -n "$AGENT_NAME" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/cursor-agents/${AGENT_NAME}.md" ]; then
    local BODY
    BODY=$(awk '/^---[[:space:]]*$/{skip++; next} skip>=2{print}' "${CLAUDE_PLUGIN_ROOT}/cursor-agents/${AGENT_NAME}.md")
    FULL_PROMPT="${BODY}

${PROMPT}"
    MODE="injection"
  elif [ -n "$AGENT_NAME" ]; then
    local AVAILABLE
    AVAILABLE=$(_list_cursor_agents | paste -sd, - 2>/dev/null || echo "")
    echo "invoke_cursor: WARNING agent '${AGENT_NAME}' not found in plugin cursor-agents/ (cursor has no headless --agent selector — injection only); falling through to raw prompt (no role brief applied). Available briefs: ${AVAILABLE:-<none>}" >&2
    MODE="raw"
  else
    MODE="raw"
  fi

  # Role -> flags. CURSOR_ROLE wins; else infer from the agent name. reviewer ->
  # --mode plan (CUR-08 read-only); builder -> --force (apply edits in-worktree);
  # anything else (incl. the empty-name raw READY probe) -> neither, a plain query.
  local ROLE="${CURSOR_ROLE:-}"
  if [ -z "$ROLE" ]; then
    case "$AGENT_NAME" in
      *reviewer*) ROLE="reviewer" ;;
      *builder*)  ROLE="builder" ;;
      *)          ROLE="" ;;
    esac
  fi

  # Command core: pin model, stream-json capture, --trust (mandatory headless,
  # CUR-04). BASE carries everything BEFORE the prompt; the prompt is appended
  # LAST on each call (trailing positional — -p is boolean, not value-consuming).
  # NEVER --model auto (CUR-03/CUR-05).
  local BASE=("$CBIN" -p --output-format stream-json --model "$MODEL" --trust)
  local ROLE_FLAG_DESC="none"
  case "$ROLE" in
    reviewer) BASE+=(--mode plan); ROLE_FLAG_DESC="--mode plan (read-only, CUR-08)" ;;
    builder)  BASE+=(--force);     ROLE_FLAG_DESC="--force" ;;
  esac

  echo "invoke_cursor: agent=${AGENT_NAME:-<none>} mode=${MODE} role=${ROLE:-raw} model=${MODEL} effort=${EFFORT:-none} (${_CURSOR_EFFORT_NOTE:-in model id}) binary=${CBIN} role-flags=${ROLE_FLAG_DESC}" >&2

  # stdout -> RAW (JSONL for the parser), stderr -> ERR (diagnostics). Prompt is
  # the trailing positional (after every flag).
  _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${BASE[@]}" "$FULL_PROMPT" > "$RAW" 2>"$ERR" || EXIT_CODE=$?

  if [ "$EXIT_CODE" -ne 0 ]; then
    # Deterministic auth override FIRST: a mid-run signed-out/credential error
    # from cursor is deterministic (retry cannot help). Scan both streams before
    # falling back to the shared classifier (mirrors invoke_kimi / invoke_opencode).
    if grep -qiE 'not logged in|logged out|please (log|sign) in|cursor-agent login|unauthorized|401|invalid api key|authentication (failed|required|expired)|no credentials' "$RAW" "$ERR" 2>/dev/null; then
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="auth"
    else
      _classify_invoke_failure "$EXIT_CODE" "$ERR"
    fi
    case "$INVOKE_FAILURE_CLASS" in
      deterministic)
        case "$_INVOKE_FAILURE_REASON" in
          auth)
            echo "invoke_cursor: agent=${AGENT_NAME} exit=${EXIT_CODE} auth failure — cursor-agent is not logged in. Fix: run \`cursor-agent login\` (or set CURSOR_API_KEY). No retry (deterministic)." >&2
            ;;
          binary-missing)
            echo "invoke_cursor: agent=${AGENT_NAME} exit=${EXIT_CODE} — \`cursor-agent\` disappeared from PATH mid-run. Fix: install it (curl https://cursor.com/install -fsS | bash), then run \`cursor-agent login\`. No retry (deterministic)." >&2
            ;;
          *)
            echo "invoke_cursor: agent=${AGENT_NAME} exit=${EXIT_CODE} deterministic failure (${_INVOKE_FAILURE_REASON:-see error above}). No retry." >&2
            ;;
        esac
        # Guidance to OUTPUT_FILE too so a captured-only caller does not read an
        # empty file as "no findings": raw streams first, then an explicit fix
        # line for the signed-out shape.
        cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true
        if [ "$_INVOKE_FAILURE_REASON" = "auth" ]; then
          echo "invoke_cursor: cursor-agent not logged in — run: cursor-agent login (or set CURSOR_API_KEY)" >> "$OUTPUT_FILE" 2>/dev/null || true
        fi
        rm -f "$RAW" "$ERR"
        return "$EXIT_CODE"
        ;;
      timeout)
        echo "invoke_cursor: agent=${AGENT_NAME} timed out after ${TIMEOUT}s (exit=${EXIT_CODE}). Requeue policy belongs to the caller (lease layer), not this helper." >&2
        cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true
        rm -f "$RAW" "$ERR"
        return "$EXIT_CODE"
        ;;
      retryable)
        # Single retry: raw prompt, no injected brief (mirrors the sibling
        # helpers). BASE keeps the model pin, stream-json, --trust, and the
        # retry-safe role flag.
        echo "invoke_cursor: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable), retrying once with raw prompt" >&2
        EXIT_CODE=0
        _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${BASE[@]}" "$PROMPT" > "${RAW}.retry" 2>"${ERR}.retry" || EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 0 ]; then
          mv "${RAW}.retry" "$RAW"
          mv "${ERR}.retry" "$ERR" 2>/dev/null || true
          INVOKE_FAILURE_CLASS="none"
        else
          _classify_invoke_failure "$EXIT_CODE" "${ERR}.retry"
          echo "invoke_cursor: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}" >&2
          cat "${ERR}.retry" "${RAW}.retry" > "$OUTPUT_FILE" 2>/dev/null || true
          rm -f "$RAW" "$ERR" "${RAW}.retry" "${ERR}.retry"
          return "$EXIT_CODE"
        fi
        ;;
    esac
  fi

  # Structured capture (success path): extract cursor's final answer from the
  # stream-json stdout into OUTPUT_FILE. Prefer the terminal result event's text
  # (cursor's canonical final answer); fall back to the last assistant message;
  # surface an error-result rather than an empty file; exit nonzero when nothing
  # is found so the raw stream is preserved (never "no findings" from an empty file).
  if _cursor_extract_text "$RAW" "$OUTPUT_FILE"; then
    :
  else
    echo "invoke_cursor: WARNING could not extract assistant text from cursor stream-json — preserving raw stream in ${OUTPUT_FILE}" >&2
    cat "$RAW" "$ERR" > "$OUTPUT_FILE" 2>/dev/null || cp "$RAW" "$OUTPUT_FILE" 2>/dev/null || true
  fi
  rm -f "$RAW" "$ERR" "${RAW}.retry" "${ERR}.retry"
  return $EXIT_CODE
}

# List known Cursor role-brief names: the plugin cursor-agents/ injection briefs
# (basename without .md), excluding README. Cursor has NO headless --agent
# selector (re-probed 2026-07-18), so the plugin briefs are the injection source;
# the copied .cursor/agents/ project defs are delegation targets, not headless
# selectors, so they are not enumerated here.
_list_cursor_agents() {
  {
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/cursor-agents" ]; then
      for f in "${CLAUDE_PLUGIN_ROOT}/cursor-agents"/*.md; do
        [ -f "$f" ] || continue
        case "$(basename "$f" .md)" in README) continue ;; esac
        basename "$f" .md
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
    timeout -k 10s "${SECS}s" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k 10s "${SECS}s" "$@"
  else
    echo "invoke-external.sh: ERROR neither \`timeout\` nor \`gtimeout\` is on PATH — refusing to run \`${1:-}\` without timeout enforcement (fail-closed). Fix: on macOS run \`brew install coreutils\`, then retry." >&2
    return "$_RC_NO_TIMEOUT_TOOL"
  fi
}

# _scrub — redact known key/token shapes from captured external-CLI output
# before it lands in a committed ops/ file (KTD-14 / R36). Reads stdin, writes
# scrubbed stdout. Mirrors the standalone copy in probe-capabilities.sh (that
# script is not sourced into this shell, so the two intentionally each carry
# their own copy — keep the patterns in sync when either changes).
_scrub() {
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{8,}/[REDACTED-KEY]/g' \
    -e 's/AIza[0-9A-Za-z_-]{10,}/[REDACTED-KEY]/g' \
    -e 's/gh[pousr]_[A-Za-z0-9]{16,}/[REDACTED-KEY]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED-KEY]/g' \
    -e 's/(Bearer|bearer) +[A-Za-z0-9._-]{12,}/Bearer [REDACTED]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9._-]{20,}/[REDACTED-JWT]/g'
}

# _kill_tree <pid> [signal] — best-effort recursive process-tree kill, portable
# across macOS + Linux (both ship `pgrep -P`). Signals descendants leaf-first so
# a killed parent never re-parents its children to init before they are reached.
# The heartbeat backstop needs this: a builder is launched as
# subshell -> env -i -> timeout -> CLI, so killing only the recorded subshell
# pid would orphan the timeout/CLI grandchildren (the very processes that
# outlived their own `timeout` enforcement).
_kill_tree() {
  local ROOT=$1 SIG=${2:-TERM} KID
  [ -n "$ROOT" ] && [ "$ROOT" -gt 0 ] 2>/dev/null || return 0
  for KID in $(pgrep -P "$ROOT" 2>/dev/null || true); do
    _kill_tree "$KID" "$SIG"
  done
  kill -"$SIG" "$ROOT" 2>/dev/null || true
}

# The six integrated adapter identities. A valid reviewer/builder identity is
# exactly one of these — canonicalizing against this set (rather than accepting
# any free-form label) is what closes fabricated reviewer names like
# "codex-reviewer", which would otherwise pass lease_merge's plain != builder
# string compare (AE3) while no real review ran.
_KNOWN_CLIS="claude antigravity codex opencode kimi cursor"
_is_known_cli() {
  case " ${_KNOWN_CLIS} " in *" ${1:-} "*) return 0 ;; *) return 1 ;; esac
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

# Emit shell variable assignments extracted from a Codex agents.toml entry.
# EVERY value is base64-encoded so the caller can eval the lines without risk:
# a raw config value like `model = "$(rm -rf ~)"` would command-substitute
# inside eval, but base64 output has no shell metacharacters (injection-safe).
# Outputs (all base64; caller decodes):
#   AGENT_MODEL_B64 AGENT_SANDBOX_B64 AGENT_APPROVAL_B64
#   AGENT_INSTR_B64 AGENT_OUTPUT_SCHEMA_B64
# Missing fields emit base64 of the empty string. Fails loudly (exit 1 + stderr
# warning) if python or a TOML parser is unavailable, so callers can detect the
# condition and log it rather than silently running with session defaults.
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
def _b64(v):
    return base64.b64encode(str(v).encode()).decode()
# Emit EVERY field base64-encoded. The caller eval's these lines, and a raw
# json.dumps'd value like \"\$(rm -rf ~)\" still command-substitutes inside
# eval (json.dumps quotes but does not neutralize \$()/backticks). base64's
# alphabet ([A-Za-z0-9+/=]) has no shell metacharacters, so eval of
# NAME=<base64> is injection-proof; the caller base64-decodes each field.
print('AGENT_MODEL_B64='         + _b64(agent.get('model', '')))
print('AGENT_SANDBOX_B64='       + _b64(agent.get('sandbox_mode', '')))
print('AGENT_APPROVAL_B64='      + _b64(agent.get('approval_policy', '')))
print('AGENT_INSTR_B64='         + _b64(agent.get('developer_instructions', '')))
print('AGENT_OUTPUT_SCHEMA_B64=' + _b64(agent.get('output_schema', '')))
print('AGENT_EFFORT_B64='        + _b64(agent.get('model_reasoning_effort', '')))
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
# (builder's model field is empty by design: the shell `claude -p` builder lane
# runs the host's default Claude Code model with no --model pin, so the roster
# has no model to carry there. The Fable/downgrade ladder is an Agent-tool
# subagent concern — the Agent tool's `model` parameter — NOT this shell lane.)
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
  # Prime TRIFORGE_CURSOR_BIN for the BINARY map below: on a host that ships
  # only Cursor's `agent` binary the presence check would otherwise look for
  # `cursor-agent` and skip the member silently (AE1) even when the roster
  # names cursor as a role's primary. Cheap when cursor-agent exists.
  [ -n "${TRIFORGE_CURSOR_BIN:-}" ] || _cursor_bin >/dev/null 2>&1 || true
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
# templates/ops/roster.toml (keep the two in sync). builder model '' means: the
# shell claude -p lease lane runs the host default Claude model (no --model pin);
# the Fable/downgrade ladder is an Agent-tool subagent concern, not this lane.
DEFAULTS = {
    'builder':    {'cli': 'claude',      'model': '',                      'effort': 'max',   'fallbacks': ['codex', 'antigravity']},
    'reviewer':   {'cli': 'codex',       'model': 'gpt-6-astra',           'effort': 'xhigh', 'fallbacks': ['antigravity', 'claude']},
    'tester':     {'cli': 'codex',       'model': 'gpt-6-astra',           'effort': 'xhigh', 'fallbacks': ['claude']},
    'analyst':    {'cli': 'antigravity', 'model': 'Gemini 3.8 Flash (High)', 'effort': 'high',  'fallbacks': ['claude']},
    'documenter': {'cli': 'antigravity', 'model': 'Gemini 3.8 Flash (High)', 'effort': 'high',  'fallbacks': ['claude']},
}
CORE_TRIO = ('claude', 'antigravity', 'codex')
# cli name -> binary looked up on PATH
BINARY = {'claude': 'claude', 'antigravity': 'agy', 'codex': 'codex',
          'opencode': 'opencode', 'kimi': 'kimi',
          # cursor: cursor-agent first; _cursor_bin (KTD3 / D-025) exports the
          # verified fallback path (an agent binary whose --version matches the
          # Cursor YYYY.MM.DD-<hex> format) as TRIFORGE_CURSOR_BIN for this map.
          'cursor': os.environ.get('TRIFORGE_CURSOR_BIN') or 'cursor-agent'}
# Shipped per-CLI default model, used when a member is reached via fallback
# or chosen as an overridden primary with no explicit role model. Policy
# (D-022, user-directed 2026-09-11): agy pins the NEWEST Gemini model at its
# highest thinking level, Pro or Flash — currently Gemini 3.8 Flash (High)
# (AGY-05 PASS 2026-09-11; Gemini 3.1 Pro (High) stays a documented roster
# opt-in); codex gpt-6-astra (D-021, CDX-03); opencode glm-5.3 (D-023);
# kimi kimi-code/k3 (D-024, the OAuth-managed alias); cursor
# cursor-grok-4.6-xhigh (D-025 — effort rides in the model-id suffix, never
# the Auto router). Keep in sync with roster_member_default and
# templates/ops/roster.toml; scripts/validate-versions.sh diffs the copies.
# A [members.<cli>].model entry overrides the shipped default.
CLI_DEFAULT_MODEL = {
    'claude': '',
    'antigravity': 'Gemini 3.8 Flash (High)',
    'codex': 'gpt-6-astra',
    'opencode': 'openrouter/z-ai/glm-5.3',
    'kimi': 'kimi-code/k3',
    'cursor': 'cursor-grok-4.6-xhigh',
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

# Distinct return code meaning "this role resolved to the claude lane; spawn a
# native Agent-tool subagent instead of a background CLI helper" (see
# dispatch_role). Deliberately outside the codes the invoke_* helpers and
# timeout(1) use (1, 124, 125-127) and outside resolve_role's 2-6.
_RC_DISPATCH_ROLE_CLAUDE=40

# dispatch_role <role> <agent-name> <prompt> [output-file] [timeout-seconds]
#
# Roster-driven dispatch for the REVIEW and TEST phases (R19, AE4). resolve_role
# picks the cli+model+effort for the role; this then case-dispatches to the
# resolved cli's invoke_* helper, threading the resolved model/effort through
# that helper's override env var (AGY_MODEL / OPENCODE_MODEL / KIMI_MODEL /
# CURSOR_MODEL) so a roster override actually reaches the CLI. This is what
# makes the optional invoke_opencode/invoke_kimi/invoke_cursor helpers LIVE and
# lets a [roles.tester] cli="opencode" override run opencode instead of codex —
# without it, resolve_role only drove the builder lane (lease_create) and the
# review/test phases hardcoded codex/antigravity.
#
# The claude lane is special: review/test work assigned to claude runs as a
# NATIVE Claude Agent-tool subagent (a subagent has the ops/ context and tool
# surface the shell CLIs lack), not a shell helper. So for cli=claude this prints
#   DISPATCH_ROLE_CLAUDE <agent-name> <output-file>
# to stdout and returns _RC_DISPATCH_ROLE_CLAUDE (40), signalling the calling
# command to spawn a Claude subagent instead of a background CLI. Every other
# lane invokes its helper and returns the helper's own exit code
# (INVOKE_FAILURE_CLASS stays visible for a synchronous, same-shell caller).
#
# Callers MUST invoke this in a context that ignores set -e (e.g.
# `dispatch_role ... || RC=$?`), exactly like the invoke_* helpers — otherwise a
# nonzero helper return would abort the sourcing shell.
dispatch_role() {
  local ROLE=${1:?usage: dispatch_role <role> <agent-name> <prompt> [output-file] [timeout]}
  local AGENT_NAME=${2:?usage: dispatch_role <role> <agent-name> <prompt> [output-file] [timeout]}
  local PROMPT=${3:?usage: dispatch_role <role> <agent-name> <prompt> [output-file] [timeout]}
  local OUTPUT_FILE=${4:-"${TMPDIR:-/tmp}/dispatch_${ROLE}_$$_$(date +%s).txt"}
  local TIMEOUT=${5:-600}
  local RESOLVED CLI MODEL EFFORT
  RESOLVED=$(resolve_role "$ROLE") || return $?
  CLI=$(printf '%s\n' "$RESOLVED" | cut -f1)
  MODEL=$(printf '%s\n' "$RESOLVED" | cut -f2)
  EFFORT=$(printf '%s\n' "$RESOLVED" | cut -f3)
  echo "dispatch_role: role=${ROLE} -> cli=${CLI} model=${MODEL:-<default>} effort=${EFFORT} agent=${AGENT_NAME}" >&2
  case "$CLI" in
    antigravity)
      AGY_MODEL="$MODEL" invoke_antigravity "$AGENT_NAME" "$PROMPT" "$OUTPUT_FILE" "$TIMEOUT"
      ;;
    codex)
      # Codex resolves sandbox/approval/instructions from its agents.toml entry;
      # the roster model and effort ride the CODEX_MODEL / CODEX_EFFORT
      # overrides (same pattern as the other lanes) so a [roles.*] model or
      # effort customization reaches `codex exec -m` / -c model_reasoning_effort.
      # The shipped defaults (gpt-6-astra, xhigh) match the agents.toml pins, so
      # this is a no-op until a user actually customizes the role.
      CODEX_MODEL="$MODEL" CODEX_EFFORT="$EFFORT" invoke_codex "$AGENT_NAME" "$PROMPT" "$OUTPUT_FILE" "$TIMEOUT"
      ;;
    opencode)
      OPENCODE_MODEL="$MODEL" invoke_opencode "$AGENT_NAME" "$PROMPT" "$OUTPUT_FILE" "$TIMEOUT" "$EFFORT"
      ;;
    kimi)
      KIMI_MODEL="$MODEL" invoke_kimi "$AGENT_NAME" "$PROMPT" "$OUTPUT_FILE" "$TIMEOUT" "$EFFORT"
      ;;
    cursor)
      CURSOR_MODEL="$MODEL" invoke_cursor "$AGENT_NAME" "$PROMPT" "$OUTPUT_FILE" "$TIMEOUT" "$EFFORT"
      ;;
    claude)
      # Review/test on the claude lane runs as a native Agent-tool subagent, not
      # a shell helper — signal the caller to spawn one (see function comment).
      printf 'DISPATCH_ROLE_CLAUDE %s %s\n' "$AGENT_NAME" "$OUTPUT_FILE"
      return "$_RC_DISPATCH_ROLE_CLAUDE"
      ;;
    *)
      echo "dispatch_role: ERROR role '${ROLE}' resolved to unknown cli '${CLI}' — not integrated. Known lanes: claude, codex, antigravity, opencode, kimi, cursor." >&2
      return 1
      ;;
  esac
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

# Repo default branch (KTD-5). origin/HEAD's target when set, else the first of
# main/master that exists locally, else empty (a single-branch or detached repo
# with no default-branch concept). Printed WITHOUT the refs/remotes/origin/
# prefix. Tolerant: every probe is guarded so a repo with no remote still works.
_lease_default_branch() {
  local REPO=$1 REF="" B
  REF=$(git -C "$REPO" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || REF=""
  if [ -n "$REF" ]; then
    printf '%s\n' "${REF#refs/remotes/origin/}"
    return 0
  fi
  for B in main master; do
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/${B}" 2>/dev/null; then
      printf '%s\n' "$B"
      return 0
    fi
  done
  return 0
}

# Current checked-out branch of the main tree, or empty on detached HEAD.
_lease_current_branch() {
  git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || true
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
# requeue_count, review_cycle.
_ledger_update() {
  local TASK_ID=$1
  shift
  local LEDGER LOCK RC=0 TRIES=0
  LEDGER=$(_lease_ledger_path) || return 1
  mkdir -p "$(dirname "$LEDGER")"
  # Serialize the read-modify-write on the lead-owned ledger (KTD-4). The
  # documented wave keeps writes lead-serial, but a mkdir-lock (portable —
  # flock is not on macOS) makes the single-writer guarantee hold even under
  # accidental concurrency (e.g. a dynamic-workflow parallel group). Atomic
  # create; bounded wait with one stale-lock reclaim so a crashed writer can't
  # wedge the ledger forever.
  LOCK="${LEDGER}.lock"
  while ! mkdir "$LOCK" 2>/dev/null; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -gt 200 ]; then
      # ~10s of contention. Reclaim ONLY if the recorded holder is provably dead
      # (kill -0 fails). Never steal a LIVE holder's lock — that silently loses a
      # concurrent writer's lease transition. If the holder is alive, or reclaim
      # still cannot acquire, FAIL CLOSED (never write unlocked): surface the
      # wedged ledger instead of racing it. (PID reuse could in theory mark a
      # dead holder as live and block once more — accepted: the lock is normally
      # held <1s and fail-closed-then-retry is safe; a truly wedged lock is
      # removed manually per the message.)
      local HOLDER=""
      [ -f "${LOCK}/pid" ] && HOLDER=$(cat "${LOCK}/pid" 2>/dev/null || true)
      if [ -n "$HOLDER" ] && kill -0 "$HOLDER" 2>/dev/null; then
        echo "_ledger_update: ERROR ledger lock held by LIVE pid ${HOLDER} after ~10s (${LOCK}) — refusing to write unlocked. Another writer is active; retry, or if it is wedged remove ${LOCK} and retry." >&2
        return 1
      fi
      rm -rf "$LOCK" 2>/dev/null || true        # holder absent/dead — reclaim once
      if mkdir "$LOCK" 2>/dev/null; then break; fi
      echo "_ledger_update: ERROR could not acquire ledger lock after ~10s (${LOCK}) — refusing to write unlocked (fail-closed)." >&2
      return 1
    fi
    sleep 0.05
  done
  printf '%s\n' "$$" > "${LOCK}/pid" 2>/dev/null || true
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
INT_KEYS = ('pid', 'created', 'updated', 'heartbeat_deadline', 'requeue_count', 'review_cycle', 'report_missing_count')
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
  RC=$?
  rm -rf "$LOCK" 2>/dev/null || true   # lock dir now carries a pid file — rm -rf, not rmdir
  return $RC
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
# COLORTERM USER plus ONLY the invoked CLI's own credential variables (opencode:
# OPENROUTER_API_KEY; kimi: KIMI_*; cursor: CURSOR_API_KEY). claude, codex,
# and antigravity authenticate via HOME-based stores and get nothing extra —
# no cross-provider leakage. env -i execs external commands only; shell
# functions cannot cross it, which is why lease_dispatch composes direct CLI
# commands instead of calling the invoke_* helpers (see there).
_adapter_env() {
  local CLI=$1
  shift
  local -a PAIRS=()
  # Base allowlist — enumerated explicitly rather than via ${!V} indirect
  # expansion. This file is `source`d under the CALLER's shell (the commands
  # do a plain `source`, which ignores the bash shebang), and on macOS that is
  # zsh, where ${!V} raises "bad substitution" and would kill every lease
  # dispatch. Explicit ${HOME+x} tests and array append work under both bash
  # and zsh (verified).
  [ -n "${HOME+x}" ]      && PAIRS+=("HOME=${HOME}")
  [ -n "${PATH+x}" ]      && PAIRS+=("PATH=${PATH}")
  [ -n "${TMPDIR+x}" ]    && PAIRS+=("TMPDIR=${TMPDIR}")
  [ -n "${TERM+x}" ]      && PAIRS+=("TERM=${TERM}")
  [ -n "${LANG+x}" ]      && PAIRS+=("LANG=${LANG}")
  [ -n "${COLORTERM+x}" ] && PAIRS+=("COLORTERM=${COLORTERM}")
  # USER is identity, not a secret: Claude Code resolves its keychain credential
  # account from it, so without it `claude -p` under env -i answers "Not logged
  # in" on every macOS host (live bisect 2026-09-11: +USER -> READY; LOGNAME
  # alone does not help). Mirrored by _lane_run in scripts/probe-capabilities.sh.
  [ -n "${USER+x}" ]      && PAIRS+=("USER=${USER}")
  PAIRS+=("NO_COLOR=1")   # captured output is parsed, never rendered (U5)
  case "$CLI" in
    opencode)
      [ -n "${OPENROUTER_API_KEY+x}" ] && PAIRS+=("OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
      # D-033 defense-in-depth: the shipped deny set rides as OPENCODE_PERMISSION
      # (caller's own value wins) — the adapter stays off --auto regardless.
      PAIRS+=("OPENCODE_PERMISSION=${OPENCODE_PERMISSION:-$_OPENCODE_PERMISSION_DEFAULT}")
      ;;
    kimi)
      # Forward every EXPORTED KIMI_* var. `compgen` and ${!V} are bash-only,
      # so python3 (already required) enumerates os.environ and emits each
      # matching NAME=VALUE pair base64-encoded, one per line. base64 has no
      # internal newlines, so line-based read is portable across bash and zsh
      # AND preserves values that themselves contain newlines or `=`.
      local _kv_b64
      while IFS= read -r _kv_b64; do
        [ -n "$_kv_b64" ] && PAIRS+=("$(printf '%s' "$_kv_b64" | base64 -d 2>/dev/null)")
      done <<KIMIENV
$(python3 -c "
import os, base64, sys
for k, v in os.environ.items():
    if k.startswith('KIMI_'):
        sys.stdout.write(base64.b64encode((k + '=' + v).encode()).decode() + '\n')
")
KIMIENV
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
  # `cp -R src/. dest/` — never `cp -R src dest`, which NESTS when the worktree
  # already carries a committed .agents/skills/ (the stamp is safe to commit in
  # user projects, so that layout is expected). Shipped-name directories are
  # Triforge-owned and replaced, matching session-start's refresh (KTD7).
  local NAME
  mkdir -p "${WT}/.agents/skills"
  for NAME in "$SRC"/*/; do
    [ -d "$NAME" ] || continue
    NAME=$(basename "$NAME")
    rm -rf "${WT}/.agents/skills/${NAME}" 2>/dev/null || true
    mkdir -p "${WT}/.agents/skills/${NAME}" 2>/dev/null && cp -R "${SRC}/${NAME}/." "${WT}/.agents/skills/${NAME}/" 2>/dev/null || true
  done
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
    requeue_count=0 review_cycle=0 pinned_reviewer="" previous_builder="" reviewer="" merge_commit="" reason="" \
    || return 1
  echo "lease_create: task=${TASK_ID} role=${ROLE} builder=${CLI} model=${MODEL:-host-default} worktree=${WT}" >&2
  echo "$TASK_ID"
}

# _lease_extract_stream <cli> <out> — for the stream-shaped lanes, turn the
# captured JSON event stream in <out> into the assistant's final prose so the
# builder's typed report can be parsed: <out> -> <out>.raw, extractor -> <out>.
# Non-stream lanes and a failed extraction leave <out> untouched (a plain-text
# TRIFORGE_TEST_BUILDER stream is simply not JSON).
_lease_extract_stream() {
  local CLI=$1 OUT=$2 X=""
  case "$CLI" in
    opencode) X=_oc_extract_text ;;
    kimi)     X=_kimi_extract_text ;;
    cursor)   X=_cursor_extract_text ;;
    *) return 0 ;;
  esac
  [ -s "$OUT" ] || return 0
  cp "$OUT" "${OUT}.raw" 2>/dev/null || return 0
  if "$X" "${OUT}.raw" "${OUT}.text"; then
    mv -f "${OUT}.text" "$OUT" 2>/dev/null || true
  else
    rm -f "${OUT}.text" 2>/dev/null || true
    echo "lease_dispatch: WARNING could not extract assistant text from the ${CLI} stream — raw stream left in ${OUT} (report may parse as missing)" >&2
  fi
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

  # Dispatch contract (KTD11 / S5+S13+S14) — one block for EVERY lane, claude
  # included: no sub-dispatch, git stays local, and a typed final report whose
  # `Status:` line lease_collect parses (a clean exit without it is "report
  # missing", never review-ready). The lane's builder brief body (opencode /
  # cursor: opencode-agents|cursor-agents/builder.md, frontmatter stripped) is
  # prepended here; Kimi's arrives natively via --agent-file; claude / codex /
  # antigravity carry no separate builder brief (their role instructions are
  # the contract itself). Wording is CLI-neutral on purpose.
  local BRIEF_BODY="" BRIEF_FILE=""
  case "$CLI" in
    opencode|cursor)
      BRIEF_FILE="${CLAUDE_PLUGIN_ROOT:-}/${CLI}-agents/builder.md"
      if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$BRIEF_FILE" ]; then
        BRIEF_BODY=$(awk '/^---[[:space:]]*$/{skip++; next} skip>=2{print}' "$BRIEF_FILE")
      fi
      ;;
  esac
  local FULL_PROMPT
  FULL_PROMPT="## Lease dispatch: ${TASK_ID}
Roster entry: role=${ROLE} cli=${CLI} model=${MODEL:-<host-default>} effort=${EFFORT}

## Confinement contract
You are working in an isolated worktree at ${WT}. Never modify files outside it. Never read or write the project's canonical ops/ directory — required context is included below. Commit nothing; the lead collects.

## Dispatch contract (applies to every builder)
- Do not spawn sub-agents, delegate, or invoke other coding tools; do the work yourself in this worktree.
- Never run git push, git pull, or git fetch. Do not commit, rebase, or switch branches.
- Finish with a final report in exactly this shape (the lead parses the Status line; a run without it is treated as incomplete):
  Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
  Files changed: <list>
  Tests: <one-line summary, or none>
  Concerns: <list, or None>
  Discoveries for later tasks: <list, or None>
${BRIEF_BODY:+
## Builder role brief
${BRIEF_BODY}
}
## Task
${PROMPT}"

  rm -f "$OUT" "${OUT}.rc" "${OUT}.class"

  # Lane-specific composition that must happen LEAD-SIDE, before env -i: the
  # Kimi builder definition's absolute plugin path (D-024), the Cursor binary and
  # the effort-suffixed Cursor model id (D-025). The ledger records the id that
  # was actually dispatched (dispatched_model) beside the roster values
  # (builder_model / builder_effort).
  local KIMI_AGENT_FILE="" CBIN="" DISPATCH_MODEL="$MODEL"
  case "$CLI" in
    kimi)
      [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/kimi-agents/builder.md" ] && KIMI_AGENT_FILE="${CLAUDE_PLUGIN_ROOT}/kimi-agents/builder.md"
      DISPATCH_MODEL="${MODEL:-kimi-code/k3}"
      ;;
    cursor)
      DISPATCH_MODEL=$(_cursor_model_for_effort "${MODEL:-cursor-grok-4.6-xhigh}" "$EFFORT")
      if ! CBIN=$(_cursor_bin); then
        echo "lease_dispatch: ERROR no Cursor CLI on PATH (cursor-agent, or an agent whose --version matches YYYY.MM.DD-<hex>) — cannot dispatch ${TASK_ID}" >&2
        return 1
      fi
      ;;
    antigravity) DISPATCH_MODEL="${MODEL:-Gemini 3.8 Flash (High)}" ;;
    opencode)    DISPATCH_MODEL="${MODEL:-openrouter/z-ai/glm-5.3}" ;;
  esac
  _ledger_update "$TASK_ID" dispatched_model="$DISPATCH_MODEL" || return 1

  (
    cd "$WT" || exit 97
    RC=0
    CLASS_SET=0
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
          # JSON envelope (KTD2, D-032): exit 0 is not a completion signal on
          # agy >= 1.1.20 — parse status/response/denied_actions instead. The
          # prose lands in $OUT (what lease_collect prints), the streams in
          # $OUT.raw / $OUT.err, the verdict in $OUT.status / $OUT.denied.
          _adapter_env antigravity "$TOBIN" "${TIMEOUT}s" agy --model "${MODEL:-Gemini 3.8 Flash (High)}" --add-dir "$WT" --print-timeout "${TIMEOUT}s" --output-format json -p "$FULL_PROMPT" < /dev/null > "${OUT}.raw" 2> "${OUT}.err" || RC=$?
          if [ "$RC" -eq 0 ]; then
            AGY_PRC=0
            _agy_parse_envelope "${OUT}.raw" "$OUT" || AGY_PRC=$?
            case "$AGY_PRC" in
              0|12) : ;;
              10) RC=1; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1
                  echo "lease_dispatch: agy builder returned an empty response with denied actions: $(paste -sd, "${OUT}.denied" 2>/dev/null) — add the matching permissions.allow rule to ~/.gemini/antigravity-cli/settings.json (user tier)" >> "$OUT" ;;
              *)  RC=1; INVOKE_FAILURE_CLASS="retryable"; CLASS_SET=1
                  echo "lease_dispatch: agy builder returned an empty response (status=$(cat "${OUT}.status" 2>/dev/null)) — treated as failure, not review-ready" >> "$OUT" ;;
            esac
          else
            cat "${OUT}.err" "${OUT}.raw" > "$OUT" 2>/dev/null || true
          fi
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
          # Effort -> --variant (OC-05 best-effort), guarded on a non-empty effort
          # exactly like the codex case guards model_reasoning_effort. The lease
          # path has no retry, so a provider that rejects the variant surfaces as a
          # KTD-9-classified failure the lead requeues — same as any other lane.
          local -a CMD=(opencode run --format json -m "${MODEL:-openrouter/z-ai/glm-5.3}")
          [ -n "$EFFORT" ] && CMD+=(--variant "$EFFORT")
          _adapter_env opencode "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        kimi)
          # R35-confined optional-tier builder (U12): raw `kimi -p` with cwd =
          # the worktree (the enclosing subshell cd'd there), under _adapter_env
          # kimi — which allowlists ONLY KIMI_* (KTD-14), so no cross-provider
          # credential leak. Telemetry off (R25) via the inner `env`. --skills-dir
          # .agents/skills when present (KIMI-04). Kimi has no per-tool sandbox
          # flag and -p uses the auto policy, so confinement is the worktree + env
          # allowlist; the role brief rides in FULL_PROMPT (injection — KIMI-03
          # has no --agent, so no invoke_kimi either: a shell function cannot
          # cross env -i). Shipped default is kimi-code/k3 (the OAuth-managed
          # alias, D-024), so a live build AUTH-FAILs until kimi is signed in —
          # that failure is deterministic and the lead sees it via <out>.class
          # (no requeue). The builder definition rides as --agent-file with the
          # ABSOLUTE plugin path composed by the lead shell (KIMI_AGENT_FILE,
          # below) so it survives env -i; no --skills-dir (it would replace
          # Kimi's native .agents/skills discovery — KIMI-04).
          # -p LAST (commander.js consumes the next token as -p's value; see the
          # invoke_kimi note) — prompt right after -p.
          local -a CMD=(kimi --output-format stream-json -m "${MODEL:-kimi-code/k3}")
          [ -n "$KIMI_AGENT_FILE" ] && CMD+=(--agent-file "$KIMI_AGENT_FILE")
          _adapter_env kimi "$TOBIN" "${TIMEOUT}s" env KIMI_DISABLE_TELEMETRY=1 "${CMD[@]}" -p "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        cursor)
          # R35-confined optional-tier builder (U13): raw `cursor-agent -p` with
          # cwd = the worktree (the enclosing subshell cd'd there), under
          # _adapter_env cursor — which allowlists ONLY CURSOR_API_KEY (KTD-14),
          # so no cross-provider credential leak. --trust bypasses the
          # workspace-trust prompt (mandatory headless, CUR-04); --force applies
          # edits without confirmation (builder role, inside the worktree). Model
          # pinned to the suffixed id composed by _cursor_model_for_effort from
          # the roster model + effort (D-025; default cursor-grok-4.6-xhigh),
          # NEVER Auto (ledger attribution needs a named model). Binary resolved
          # lead-side by _cursor_bin (CBIN — cursor-agent first, verified `agent`
          # fallback) and exec'd by absolute path inside env -i. Confinement is
          # the worktree + env allowlist, NOT --sandbox (CUR-07: --sandbox
          # enabled did not confine — an absolute-path write escaped). -p is a
          # BOOLEAN flag (unlike kimi's -p); the prompt is the TRAILING
          # POSITIONAL (verified live 2026-07-18), so it comes LAST. No
          # invoke_cursor (a shell function cannot cross env -i; the role brief
          # rides in FULL_PROMPT via injection — cursor has no headless --agent
          # selector). A live build AUTH-FAILs until cursor-agent is logged in —
          # that failure is deterministic and the lead sees it via <out>.class.
          local -a CMD=("$CBIN" -p --output-format stream-json --model "$DISPATCH_MODEL" --trust --force)
          _adapter_env cursor "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        *)
          echo "lease_dispatch: ERROR unknown builder CLI '${CLI}' — not integrated. Known builder lanes: claude, codex, antigravity, opencode, kimi, cursor." > "$OUT"
          RC=95
          ;;
      esac
    fi
    # Only a nonzero exit has a failure class (matches invoke_antigravity /
    # invoke_codex): a clean run is class=none, so lease_collect never reads a
    # spurious 'retryable' off a builder that actually succeeded.
    if [ "$RC" -eq 0 ]; then
      INVOKE_FAILURE_CLASS="none"
      # The opencode / kimi / cursor lanes answer as a JSON event stream; the
      # typed `Status:` report (KTD11) lives inside it as escaped text, so a
      # line-anchored parser can never see it. Extract the prose into $OUT
      # (raw stream kept in ${OUT}.raw); an extraction miss leaves $OUT as is.
      _lease_extract_stream "$CLI" "$OUT"
    elif [ "${CLASS_SET:-0}" -ne 1 ]; then
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

# lease_redispatch <task_id> <prompt-with-findings> [timeout] — the review ->
# building fix cycle (KTD-10; wave-orchestration "Findings, cycle < 3 -> re-
# dispatch the SAME lease to the SAME builder"). This is the ONLY path from
# state=review back to building: without it a reviewer that requests changes
# strands the lease, because lease_dispatch requires state=leased and
# lease_requeue requires state=requeued. Increments review_cycle and, at the
# 3rd cycle, ESCALATES to the user instead of re-dispatching (state=escalated) —
# the "Maximum 3 review cycles per task" cap. Builder, worktree, and roster
# entry are unchanged; the reviewer's findings ride in <prompt-with-findings>.
lease_redispatch() {
  local TASK_ID=${1:?usage: lease_redispatch <task_id> <prompt-with-findings> [timeout]}
  local PROMPT=${2:?usage: lease_redispatch <task_id> <prompt-with-findings> [timeout]}
  local TIMEOUT=${3:-600}
  local STATE WT CYCLE NEXT
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_redispatch: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if [ "$STATE" != "review" ]; then
    echo "lease_redispatch: ERROR task ${TASK_ID} is in state '${STATE}' (want review — lease_collect sets it; redispatch is the findings path). Approved work goes to lease_merge; orphaned/timed-out work to lease_requeue." >&2
    return 1
  fi
  WT=$(_ledger_get "$TASK_ID" worktree)
  if [ ! -d "$WT" ]; then
    echo "lease_redispatch: ERROR worktree missing: ${WT} (already merged/reclaimed?) — cannot re-dispatch" >&2
    return 1
  fi
  CYCLE=$(_ledger_get "$TASK_ID" review_cycle 2>/dev/null || true)
  case "${CYCLE:-}" in ''|*[!0-9]*) CYCLE=0 ;; esac
  NEXT=$((CYCLE + 1))
  # Cap at 3 cycles: the 3rd round of findings escalates to the user instead of a
  # 4th builder run (KTD-10 / "Maximum 3 review cycles per task").
  if [ "$NEXT" -ge 3 ]; then
    _ledger_update "$TASK_ID" state=escalated review_cycle="$NEXT" || return 1
    echo "lease_redispatch: task ${TASK_ID} reached review cycle ${NEXT} (cap 3) — ESCALATED to the user; no further auto re-dispatch (KTD-10). Resolve manually, then lease_merge or abandon the lease." >&2
    return "$_RC_LEASE_ESCALATED"
  fi
  # review -> leased (transient), then reuse lease_dispatch's launch machinery to
  # re-run the SAME builder in the SAME worktree; lease_dispatch sets state=building.
  _ledger_update "$TASK_ID" state=leased review_cycle="$NEXT" || return 1
  echo "lease_redispatch: task ${TASK_ID} findings re-dispatch — review cycle ${NEXT}/3, same builder, same worktree" >&2
  lease_dispatch "$TASK_ID" "$PROMPT" "$TIMEOUT"
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
  local SWEPT=0 ORPHANED=0 UNVERIFIED=0
  # $TASKS is NEWLINE-separated. Iterate with read, NOT `for TASK in $TASKS`:
  # under zsh (the caller's shell on macOS) an unquoted $TASKS is not
  # word-split, so `for` would run once on the whole "taskA\ntaskB" blob and
  # corrupt the sweep for 2+ concurrent leases — the parallel-wave case. The
  # heredoc (not a `printf | while` pipe) keeps the loop in THIS shell so the
  # SWEPT/ORPHANED counters persist.
  while IFS= read -r TASK; do
    [ -z "$TASK" ] && continue
    if [ -n "$ONLY" ] && [ "$TASK" != "$ONLY" ]; then
      continue
    fi
    SWEPT=$((SWEPT + 1))
    local PID OUT DEADLINE ALIVE FRESH AGE
    PID=$(_ledger_get "$TASK" pid)
    OUT=$(_ledger_get "$TASK" output_file)
    if [ -z "$PID" ] || [ -z "$OUT" ]; then
      # Could not verify: a building row with no pid/output to judge liveness
      # by (ledger written by an older version, or a crash between dispatch
      # and its ledger update). Report it, leave it alone — never guess.
      echo "lease_heartbeat_check: ${TASK} building but pid/output_file missing from the ledger — cannot verify liveness (degraded); inspect and reclaim by hand" >&2
      UNVERIFIED=$((UNVERIFIED + 1))
      continue
    fi
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
      echo "lease_heartbeat_check: ${TASK} EXPIRED — pid ${PID} alive past heartbeat_deadline; killing the builder process tree and orphaning" >&2
      _kill_tree "$PID" TERM
      sleep 1
      _kill_tree "$PID" KILL
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
  done <<HEARTBEAT_TASKS
$TASKS
HEARTBEAT_TASKS
  echo "lease_heartbeat_check: swept ${SWEPT} building lease(s), orphaned ${ORPHANED}, unverifiable ${UNVERIFIED}" >&2
  [ "$UNVERIFIED" -gt 0 ] && return "$_RC_DEGRADED"
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

# _lease_parse_status <output-file> — print the builder's typed completion
# signal from its final report (KTD11): the LAST line matching
# `Status: DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT` (case-insensitive,
# optional leading list marker / bold). Prints MISSING when no such line exists.
# The token must END the line (a closing `**`, optional trailing punctuation,
# then whitespace/EOL — never a `|`): the dispatch contract's own template line
# `Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT` is echoed back
# into the captured output by CLIs that print the prompt (codex exec does, on
# stderr), and an unanchored match read every such run as DONE.
_lease_parse_status() {
  local F=${1:?usage: _lease_parse_status <output-file>}
  local S=""
  S=$(grep -iE '^[[:space:]]*[-*]*[[:space:]]*\**Status\**:?\**[[:space:]]*\**(DONE_WITH_CONCERNS|DONE|BLOCKED|NEEDS_CONTEXT)\**[.,;)]?([[:space:]]*$|[[:space:]]+[^|[:space:]])' "$F" 2>/dev/null | tail -1 | grep -oiE 'DONE_WITH_CONCERNS|DONE|BLOCKED|NEEDS_CONTEXT' | head -1 | tr '[:lower:]' '[:upper:]' || true)
  printf '%s\n' "${S:-MISSING}"
}

# _lease_copy_discoveries <task_id> <builder> <output-file> — copy the
# builder's "Discoveries for later tasks" block into ops/MEMORY.md (scrubbed,
# lead-side — builders never write ops/). Skips "None"/empty.
# The LAST block wins (the contract template echoed back by a prompt-printing
# CLI carries an earlier placeholder block); the placeholder itself and the
# None spellings are skipped; the copy is bounded (20 lines x 400 chars) and
# labeled as unverified builder claims, never as lead decisions — MEMORY.md is
# read as trusted institutional knowledge by later sessions. It lands as a
# 4-space-indented literal block, never a fence: a builder line of three
# backticks would close a fence and turn the rest into live Markdown.
_lease_copy_discoveries() {
  local TASK_ID=$1 BUILDER=$2 F=$3
  local BLOCK
  BLOCK=$(awk 'BEGIN{p=0; b=""} /^[[:space:]]*[-*]?[[:space:]]*\**Discoveries for later tasks\**:?/{p=1; b=""; line=$0; sub(/^[^:]*:[[:space:]]*/, "", line); if (line != "") b=line "\n"; next} p==1{ if ($0 ~ /^[[:space:]]*$/) {p=0; next} b=b $0 "\n" } END{printf "%s", b}' "$F" 2>/dev/null | head -n 20 | cut -c1-400 | _scrub || true)
  case "$(printf '%s' "$BLOCK" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')" in ''|none|'-none'|'*none'|'none.'|'<list,ornone>'|'<listornone>') return 0 ;; esac
  mkdir -p ops
  {
    echo ""
    echo "## Builder-reported discoveries — lease ${TASK_ID} (builder: ${BUILDER}, $(date -u +%Y-%m-%d))"
    echo "Unverified builder claims, not lead decisions — promote into Decisions/Gotchas only after checking them:"
    echo ""
    printf '%s\n' "$BLOCK" | sed 's/^/    /'
  } >> ops/MEMORY.md 2>/dev/null || true
  echo "lease_collect: copied the builder's discoveries into ops/MEMORY.md (labeled unverified)" >&2
}

# lease_collect <task_id> — lead-side harvest of a finished builder. Exit 0:
# state=review, prints the output-file path (U10 feeds it to the reviewer).
# Nonzero: routed by the KTD-9 class the launcher recorded (<out>.class):
#   deterministic       -> state=failed, fail fast with guidance, NO requeue
#   timeout / retryable -> orphan path (reclaim -> requeue once -> escalate)
# On a CLEAN exit the typed report decides (KTD11):
#   Status: DONE / DONE_WITH_CONCERNS -> state=review (report_status recorded;
#                                        discoveries copied to ops/MEMORY.md)
#   Status: BLOCKED / NEEDS_CONTEXT    -> state=escalated, never review
#   no Status line                     -> "report missing": state stays
#                                        building, rc _RC_DEGRADED (80); the
#                                        lead re-dispatches with the contract
#                                        restated (lease_redispatch needs
#                                        state=review, so use lease_requeue's
#                                        sibling: mark orphaned -> reclaim ->
#                                        requeue) or escalates after one repeat
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
    local REPORT BUILDER
    REPORT=$(_lease_parse_status "$OUT")
    BUILDER=$(_ledger_get "$TASK_ID" builder_cli 2>/dev/null || true)
    _ledger_update "$TASK_ID" report_status="$REPORT" || return 1
    case "$REPORT" in
      DONE|DONE_WITH_CONCERNS)
        _ledger_update "$TASK_ID" state=review || return 1
        _lease_copy_discoveries "$TASK_ID" "${BUILDER:-unknown}" "$OUT"
        echo "lease_collect: task ${TASK_ID} builder exited 0 with Status: ${REPORT} — state=review, output below" >&2
        printf '%s\n' "$OUT"
        return 0
        ;;
      BLOCKED|NEEDS_CONTEXT)
        local WHY
        WHY=$(grep -iE '^[[:space:]]*[-*]?[[:space:]]*\**Concerns\**:?' "$OUT" 2>/dev/null | tail -1 | cut -c1-200 | _scrub || true)
        _ledger_update "$TASK_ID" state=escalated reason="builder reported ${REPORT}: ${WHY:-see output}" || return 1
        echo "lease_collect: task ${TASK_ID} builder reported Status: ${REPORT} — ESCALATED, never routed to review (see ${OUT}). Supply the missing context / unblock, then re-lease." >&2
        return 1
        ;;
      *)
        # Report missing (KTD11). A finished builder with a dead pid is never
        # orphaned by lease_heartbeat_check and lease_requeue refuses a building
        # row, so the lease must transition here: the FIRST miss goes back to
        # leased — lease_dispatch (which always prepends the contract) re-runs
        # the SAME builder in the SAME worktree, keeping its uncommitted work —
        # and the SECOND miss escalates (two clean exits without a report mean
        # the builder is not following the contract).
        local MISSES
        MISSES=$(_ledger_get "$TASK_ID" report_missing_count 2>/dev/null || true)
        case "${MISSES:-}" in ''|*[!0-9]*) MISSES=0 ;; esac
        MISSES=$((MISSES + 1))
        if [ "$MISSES" -ge 2 ]; then
          local FIRST_OUT
          FIRST_OUT=$(_ledger_get "$TASK_ID" report_missing_output 2>/dev/null || true)
          _ledger_update "$TASK_ID" state=escalated report_missing_count="$MISSES" reason="report missing twice: clean exits without a Status line (outputs: ${FIRST_OUT:-?} ; ${OUT})" || return 1
          echo "lease_collect: task ${TASK_ID} builder exited 0 without a final 'Status:' report for the SECOND time — ESCALATED, never review (KTD11: rule on reassigning the task to another roster member or stopping the wave; ledger the Ruling). Output: ${OUT}" >&2
          return 1
        fi
        # Keep the first miss's output: the re-dispatch rewrites ${OUT} in place.
        cp "$OUT" "${OUT}.miss1" 2>/dev/null || true
        _ledger_update "$TASK_ID" state=leased report_missing_count="$MISSES" report_missing_output="${OUT}.miss1" reason="report missing: clean exit without a Status line (${OUT}; re-dispatch once, contract restated)" || return 1
        echo "lease_collect: task ${TASK_ID} builder exited 0 but its output has NO final 'Status:' report line — report missing, NOT review-ready (rc ${_RC_DEGRADED}; state back to leased, same builder + worktree kept). Re-dispatch once: lease_dispatch ${TASK_ID} \"<one line: the previous run ended without a report> <original prompt>\" — a second miss escalates. Output: ${OUT}" >&2
        return "$_RC_DEGRADED"
        ;;
    esac
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

# lease_pin_reviewer <task_id> <reviewer> — record the non-author reviewer for a
# lease (KTD-10). The reviewer pinned here stays this task's reviewer for ALL
# <=3 fix cycles, and — because it lives in the ledger — that pin survives a
# session boundary, so a fresh session cannot silently re-pin a different
# reviewer mid-sprint. Idempotent: re-pinning the SAME reviewer is a no-op;
# pinning a DIFFERENT one is refused. Refuses reviewer == builder_cli (AE3).
# Call it after lease_collect (state=review), before reviewing.
lease_pin_reviewer() {
  local TASK_ID=${1:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local REVIEWER=${2:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local BUILDER PINNED
  _ledger_get "$TASK_ID" state >/dev/null || { echo "lease_pin_reviewer: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if ! _is_known_cli "$REVIEWER"; then
    echo "lease_pin_reviewer: REFUSED — '${REVIEWER}' is not a known reviewer identity (one of: ${_KNOWN_CLIS}). A fabricated label cannot stand in for a real reviewer (AE3)." >&2
    return 1
  fi
  BUILDER=$(_ledger_get "$TASK_ID" builder_cli)
  if [ "$REVIEWER" = "$BUILDER" ]; then
    echo "lease_pin_reviewer: REFUSED — reviewer '${REVIEWER}' is the builder of ${TASK_ID}; self-review is never allowed (AE3). Pick a non-author reviewer." >&2
    return 1
  fi
  PINNED=$(_ledger_get "$TASK_ID" pinned_reviewer 2>/dev/null || true)
  if [ -n "$PINNED" ] && [ "$PINNED" != "$REVIEWER" ]; then
    echo "lease_pin_reviewer: REFUSED — ${TASK_ID} is already pinned to reviewer '${PINNED}' (KTD-10: the same reviewer stays across all fix cycles). Re-review with '${PINNED}', or escalate to the user if that reviewer is unavailable." >&2
    return 1
  fi
  _ledger_update "$TASK_ID" pinned_reviewer="$REVIEWER" || return 1
  echo "lease_pin_reviewer: ${TASK_ID} reviewer pinned to '${REVIEWER}' (holds across all <=3 cycles)" >&2
}

# lease_merge <task_id> <reviewer-identity> — single-commit-per-task merge
# (KTD-5) with the AE3 mechanical guard, hardened three ways: the reviewer must
# be (1) a KNOWN adapter identity (a fabricated label like "codex-reviewer" is
# rejected), (2) different from builder_cli (self-review never merges), and (3)
# already PINNED via lease_pin_reviewer — the pin is the "a review happened"
# receipt, so a merge with no pin is refused (U10 layers the full cross-review
# protocol on these checks). The lead snapshots the
# builder's uncommitted worktree changes onto the lease branch ("commit
# nothing; the lead collects"), squash-merges into the MAIN tree, records
# reviewer + merge_commit, then reclaims via the safe-prune path. Squash
# conflicts leave a dirty index: reset --merge, state stays review, the lead
# resolves manually.
lease_merge() {
  local TASK_ID=${1:?usage: lease_merge <task_id> <reviewer-identity>}
  local REVIEWER=${2:-}
  local STATE BUILDER WT BRANCH REPO SHA PINNED
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_merge: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if [ "$STATE" != "review" ]; then
    echo "lease_merge: ERROR task ${TASK_ID} is in state '${STATE}' (want review — lease_collect sets it)" >&2
    return 1
  fi
  if [ -z "$REVIEWER" ]; then
    echo "lease_merge: ERROR reviewer identity is required — no merge without a named reviewer (AE3)" >&2
    return 1
  fi
  if ! _is_known_cli "$REVIEWER"; then
    echo "lease_merge: REFUSED — '${REVIEWER}' is not a known reviewer identity (one of: ${_KNOWN_CLIS}). A fabricated label like 'codex-reviewer' cannot pass the non-author gate (AE3)." >&2
    return 1
  fi
  BUILDER=$(_ledger_get "$TASK_ID" builder_cli)
  if [ "$REVIEWER" = "$BUILDER" ]; then
    echo "lease_merge: REFUSED — reviewer '${REVIEWER}' is the builder of ${TASK_ID}; self-review never merges (AE3). Pick a non-author reviewer." >&2
    return 1
  fi
  # Pin IS the "a review happened" receipt (KTD-10). A merge with NO pinned
  # reviewer means the pin/review step (lease_pin_reviewer) never ran — refuse,
  # rather than trust a bare argument that no review backs. When a pin exists,
  # the SAME reviewer must approve every cycle: reject a mismatch so a session
  # boundary cannot swap the reviewer.
  PINNED=$(_ledger_get "$TASK_ID" pinned_reviewer 2>/dev/null || true)
  if [ -z "$PINNED" ]; then
    echo "lease_merge: REFUSED — no reviewer is pinned for ${TASK_ID}. Pin the reviewer first: 'lease_pin_reviewer ${TASK_ID} <reviewer>' (that step records that a review happened); merging without a pin is not allowed (AE3/KTD-10)." >&2
    return 1
  fi
  if [ "$PINNED" != "$REVIEWER" ]; then
    echo "lease_merge: REFUSED — ${TASK_ID} is pinned to reviewer '${PINNED}' (KTD-10) but lease_merge was called with '${REVIEWER}'. The same non-author reviewer must approve across all cycles; re-run with '${PINNED}' (or escalate if that reviewer is unavailable)." >&2
    return 1
  fi
  WT=$(_ledger_get "$TASK_ID" worktree)
  BRANCH=$(_ledger_get "$TASK_ID" branch)
  REPO=$(_lease_repo_root) || return 1
  if [ ! -d "$WT" ]; then
    echo "lease_merge: ERROR worktree missing: ${WT}" >&2
    return 1
  fi

  # Integration-branch guard (KTD-5): lease_merge lands a squash commit on the
  # SPRINT INTEGRATION BRANCH, never the repo's default branch. Refuse when the
  # main tree is checked out on the default branch — the lead must cut an
  # integration branch first; promotion to the default branch is lease_promote's
  # gated job. When there is no default-branch concept (detached HEAD, or a
  # single-branch repo with no origin/HEAD and no local main/master), allow it
  # but log so the honest boundary is visible.
  local DEFAULT_BRANCH CURRENT_BRANCH
  DEFAULT_BRANCH=$(_lease_default_branch "$REPO")
  CURRENT_BRANCH=$(_lease_current_branch "$REPO")
  if [ -n "$DEFAULT_BRANCH" ] && [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
    echo "lease_merge: REFUSED — the main tree is on the default branch '${DEFAULT_BRANCH}'. lease_merge lands on a sprint integration branch, not the default branch — cut/checkout an integration branch first (e.g. git checkout -b sprint/<name>), then rerun. Promotion to '${DEFAULT_BRANCH}' is lease_promote's gated job (KTD-5)." >&2
    return 1
  fi
  if [ -z "$DEFAULT_BRANCH" ] || [ -z "$CURRENT_BRANCH" ]; then
    # No default-branch concept (detached HEAD, or a single-branch repo with no
    # origin/HEAD and no local main/master). With no default branch there is no
    # integration/promotion separation to enforce, so landing the squash here
    # would silently bypass the KTD-5 gate (lease_promote would never run).
    # Refuse unless the lead explicitly confirms this checkout IS the intended
    # integration branch via TRIFORGE_INTEGRATION_BRANCH.
    if [ -z "${TRIFORGE_INTEGRATION_BRANCH:-}" ]; then
      echo "lease_merge: REFUSED — no default-branch concept (default='${DEFAULT_BRANCH:-<none>}' current='${CURRENT_BRANCH:-<detached>}'), so the integration/promotion separation (KTD-5) cannot be enforced and lease_promote's gate would be bypassed. Set TRIFORGE_INTEGRATION_BRANCH=<name> to confirm this checkout is the integration branch and proceed intentionally." >&2
      return 1
    fi
    echo "lease_merge: NOTE no default-branch concept — proceeding because TRIFORGE_INTEGRATION_BRANCH='${TRIFORGE_INTEGRATION_BRANCH}' explicitly confirms the integration branch (single-branch or detached repo)." >&2
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
  _ledger_update "$TASK_ID" state=merged reviewer="$REVIEWER" pinned_reviewer="$REVIEWER" merge_commit="$SHA" || return 1
  echo "lease_merge: ${TASK_ID} merged as ${SHA} (builder ${BUILDER}, reviewer ${REVIEWER}) — reclaiming worktree" >&2
  lease_reclaim "$TASK_ID" || true
  return 0
}

# Distinct return code for "promotion is gated — the lead/user must approve"
# (lease_promote). Outside the invoke_* / timeout / resolve_role code space.
_RC_PROMOTE_BLOCKED=42

# Distinct return code for "review fix cycle hit the 3-cycle cap — escalated to
# the user" (lease_redispatch). Same reserved code space as the gates above.
_RC_LEASE_ESCALATED=43

# Degraded: the operation completed but its result could not be verified —
# lease_collect on a clean exit with NO final `Status:` report line (the lease
# stays `building`, never review-ready), and lease_heartbeat_check when a row
# lacks the pid/output it needs to judge liveness. Deliberately outside the
# resolve_role roster errors (2–6), the invoke_* / timeout codes (1, 124–127),
# and the gate codes above (40–43, 96).
_RC_DEGRADED=80

# lease_promote [<default-branch>] — wave-end promotion of the sprint integration
# branch to the repo default branch (KTD-5). This is the ONLY path that writes the
# default branch; lease_merge only ever lands on the integration branch. Run it
# from the main tree checked out ON the integration branch (where lease_merge put
# the wave's squash commits), NOT on the default branch.
#
# Gate, in order:
#   (a) read [promotion].require_user_approval from ops/roster.toml (default false)
#   (b) compute the integration branch's changed paths vs the default branch:
#       git diff --name-only <default>...HEAD
#   (c) scan them against PROTECTED_PATHS — the controls that govern the pool:
#       permission configs, deny/policy rules, ops/roster.toml (incl [promotion]),
#       and the shipped agent configs
#   (d) require_user_approval=true OR any protected path touched -> BLOCK: print
#       that promotion needs lead/user approval (a protected-path diff forces the
#       gate on and requires the lead or user as reviewer, never external-CLI-only),
#       return _RC_PROMOTE_BLOCKED, do NOT merge
#   (e) else fast-forward (or merge) the integration branch into the default
#       branch and report the promotion.
# Atomic where it matters: the default branch is never touched unless the gate
# passes — the block path leaves the tree exactly as it found it.
lease_promote() {
  local REPO DEFAULT_BRANCH CURRENT_BRANCH INTEGRATION_BRANCH
  REPO=$(_lease_repo_root) || { echo "lease_promote: ERROR not inside a git repository" >&2; return 1; }
  DEFAULT_BRANCH=${1:-$(_lease_default_branch "$REPO")}
  if [ -z "$DEFAULT_BRANCH" ]; then
    echo "lease_promote: ERROR could not determine the default branch (no origin/HEAD, no local main/master). Pass it explicitly: lease_promote <default-branch>." >&2
    return 1
  fi
  CURRENT_BRANCH=$(_lease_current_branch "$REPO")
  if [ -z "$CURRENT_BRANCH" ]; then
    echo "lease_promote: ERROR the main tree is in detached HEAD — check out the sprint integration branch first." >&2
    return 1
  fi
  if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
    echo "lease_promote: ERROR the main tree is already on the default branch '${DEFAULT_BRANCH}' — nothing to promote. lease_promote runs from the sprint integration branch." >&2
    return 1
  fi
  INTEGRATION_BRANCH="$CURRENT_BRANCH"
  # A dirty index would ride into the promotion merge — refuse it.
  if ! git -C "$REPO" diff --cached --quiet 2>/dev/null; then
    echo "lease_promote: ERROR the main tree index has staged changes — commit or unstage them before promoting." >&2
    return 1
  fi

  # (a) user-approval knob (default false; absent/unparseable roster -> false).
  local REQUIRE_APPROVAL="false"
  if [ -f "ops/roster.toml" ]; then
    REQUIRE_APPROVAL=$(ROSTER_FILE="ops/roster.toml" python3 -c "
import os, sys
# Fail CLOSED: an existing roster that cannot be parsed (no TOML library, or a
# malformed file) must NOT silently disable the approval gate — that would let
# an unattended promotion land on the default branch despite a maintainer who
# configured require_user_approval=true. A misconfigured roster requires human
# approval. Only an ABSENT roster uses the documented false default, and that
# case never reaches this block (the enclosing -f test guards it).
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('true'); sys.exit(0)
try:
    with open(os.environ['ROSTER_FILE'], 'rb') as f:
        data = tomllib.load(f)
except Exception:
    print('true'); sys.exit(0)
p = data.get('promotion', {})
v = p.get('require_user_approval', False) if isinstance(p, dict) else False
print('true' if v is True else 'false')
" 2>/dev/null || echo "true")
  fi

  # (b) changed paths of the integration branch vs the default branch.
  local CHANGED
  CHANGED=$(git -C "$REPO" diff --name-only "${DEFAULT_BRANCH}...HEAD" 2>/dev/null) || {
    echo "lease_promote: ERROR could not diff '${DEFAULT_BRANCH}...HEAD' — is '${DEFAULT_BRANCH}' a valid branch reachable from HEAD?" >&2
    return 1
  }

  # (c) protected-path scan. A single match forces the gate ON regardless of the
  # knob. Prefixes cover every shipped agent config, each CLI's permission/deny
  # config (shipped templates/.*/ AND the project-level live .*/ dirs), and
  # ops/roster.toml (incl
  # its [promotion] block), and the shipped agent configs (agents/, and every
  # <cli>-agents/ dir). No literal backticks in the heredoc.
  local PROTECTED_HIT=""
  PROTECTED_HIT=$(CHANGED="$CHANGED" python3 -c "
import os
protected_prefixes = (
    'agents/',
    'antigravity-agents/',
    'codex-agents/',
    'opencode-agents/',
    'kimi-agents/',
    'cursor-agents/',
    # Orchestration + lifecycle control plane — the framework's own files that
    # IMPLEMENT the lease/confinement/promotion/review machinery and lifecycle
    # hooks. Protected by SPECIFIC path (not whole top-level dirs) so a wave in a
    # USER project whose own app code lives under scripts/ or commands/ is not
    # force-gated on every touch; these are the plugin's control-plane files
    # (when dogfooding this repo) plus the permission configs sensitive in ANY
    # project. A wave must never promote a change to its own enforcement code or
    # permission config on an external-CLI-only review.
    'scripts/invoke-external.sh',
    'scripts/coordinate.sh',
    'scripts/probe-capabilities.sh',
    'hooks/hooks.json',
    'hooks/handlers/',
    '.claude/settings.json',
    '.claude/settings.local.json',
    '.claude-plugin/',
    # Shipped per-CLI templates (member-governing configs, permission/deny
    # rules) — every optional member's dir, symmetric with the core trio's.
    'templates/.antigravity/',
    'templates/.opencode/',
    'templates/.codex/',
    'templates/.kimi-code/',
    'templates/.cursor/',
    'templates/ops/roster.toml',
    # Project-level live CLI configs — a wave must not silently rewrite the
    # permission/governance config any adapter reads.
    '.codex/',
    '.opencode/',
    '.kimi-code/',
    '.cursor/',
    '.antigravity/',
    'ops/roster.toml',
)
for line in os.environ.get('CHANGED', '').splitlines():
    p = line.strip()
    if p and p.startswith(protected_prefixes):
        print(p)
" 2>/dev/null || true)

  # (d) block when gated.
  if [ "$REQUIRE_APPROVAL" = "true" ] || [ -n "$PROTECTED_HIT" ]; then
    echo "lease_promote: BLOCKED — promotion of '${INTEGRATION_BRANCH}' to '${DEFAULT_BRANCH}' needs lead/user approval. No merge performed." >&2
    if [ "$REQUIRE_APPROVAL" = "true" ]; then
      echo "  reason: [promotion].require_user_approval = true in ops/roster.toml (KTD-5 user gate)." >&2
    fi
    if [ -n "$PROTECTED_HIT" ]; then
      echo "  reason: the integration diff touches protected paths (controls that govern the pool). A protected-path diff forces the gate ON regardless of the knob and requires the LEAD or USER as reviewer — never an external-CLI-only review:" >&2
      printf '%s\n' "$PROTECTED_HIT" | while IFS= read -r _ph; do
        [ -n "$_ph" ] && echo "    ${_ph}" >&2
      done
    fi
    echo "  Once the lead/user approves, promote by hand (git checkout ${DEFAULT_BRANCH} && git merge ${INTEGRATION_BRANCH}) or set [promotion].require_user_approval=false for a purely non-protected diff and rerun." >&2
    return "$_RC_PROMOTE_BLOCKED"
  fi

  # (e) promote: fast-forward when possible, else a merge commit.
  if ! git -C "$REPO" checkout "$DEFAULT_BRANCH" >&2; then
    echo "lease_promote: ERROR could not checkout the default branch '${DEFAULT_BRANCH}'." >&2
    return 1
  fi
  if git -C "$REPO" merge --ff-only "$INTEGRATION_BRANCH" >&2; then
    :
  elif git -C "$REPO" merge --no-edit "$INTEGRATION_BRANCH" >&2; then
    :
  else
    git -C "$REPO" merge --abort 2>/dev/null || true
    git -C "$REPO" checkout "$INTEGRATION_BRANCH" >&2 2>/dev/null || true
    echo "lease_promote: ERROR merging '${INTEGRATION_BRANCH}' into '${DEFAULT_BRANCH}' failed (conflicts) — aborted and returned to '${INTEGRATION_BRANCH}'. Resolve manually." >&2
    return 1
  fi
  local SHA
  SHA=$(git -C "$REPO" rev-parse HEAD)
  echo "lease_promote: PROMOTED '${INTEGRATION_BRANCH}' -> '${DEFAULT_BRANCH}' (HEAD ${SHA}); require_user_approval=${REQUIRE_APPROVAL}, protected-paths=none." >&2
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
# in resolve_role): opencode -> openrouter/z-ai/glm-5.3 ; kimi -> kimi-code/k3 ;
# cursor -> cursor-grok-4.6-xhigh (explicit suffixed pin — effort rides in the
# suffix — NEVER the Auto router). The core trio (claude/antigravity/codex) is
# required, never enrolled.

# cli name -> binary looked up on PATH (mirrors resolve_role's BINARY map).
_roster_binary() {
  case "${1:-}" in
    claude)      echo "claude" ;;
    antigravity) echo "agy" ;;
    codex)       echo "codex" ;;
    opencode)    echo "opencode" ;;
    kimi)        echo "kimi" ;;
    cursor)      _cursor_bin 2>/dev/null || echo "cursor-agent" ;;
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

# roster_member_default <cli> — print the shipped default model (D-020..D-025).
# Mirrors CLI_DEFAULT_MODEL in resolve_role; claude is intentionally empty (the
# shell claude -p lane runs the host default model; the Fable/ladder override is
# an Agent-tool subagent concern, not this lane).
roster_member_default() {
  case "${1:?usage: roster_member_default <cli>}" in
    claude)      echo "" ;;
    antigravity) echo "Gemini 3.8 Flash (High)" ;;
    codex)       echo "gpt-6-astra" ;;
    opencode)    echo "openrouter/z-ai/glm-5.3" ;;
    kimi)        echo "kimi-code/k3" ;;
    cursor)      echo "cursor-grok-4.6-xhigh" ;;
    *) echo "roster_member_default: ERROR unknown cli '${1}'" >&2; return 2 ;;
  esac
}

# latest_probe_record — print the path of the NEWEST ops/research/*-probe-record.md
# (KTD9: "the current probe record" is always the newest file; the harness
# writes a date-stamped record per cycle). rc 1 when none exists. Paths are
# repo-relative when run from the repo root, absolute otherwise.
latest_probe_record() {
  local REPO
  REPO=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  local NEWEST
  NEWEST=$(ls -1 "${REPO}/ops/research/"*-probe-record.md 2>/dev/null | sort | tail -1)
  if [ -z "$NEWEST" ]; then
    echo "latest_probe_record: no ops/research/*-probe-record.md found — run: bash scripts/probe-capabilities.sh" >&2
    return 1
  fi
  case "$PWD" in
    "$REPO") printf '%s\n' "${NEWEST#"${REPO}/"}" ;;
    *)       printf '%s\n' "$NEWEST" ;;
  esac
}

# roster_role_entry <role> — print the role's MERGED configuration:
#   cli<TAB>model<TAB>effort<TAB>fallbacks-csv
# Shipped defaults overlaid per-field by any [roles.<role>] entry in
# ops/roster.toml, WITHOUT the liveness walk: this reports what is configured
# (for the /setup role table), not which member would answer right now. The
# model column follows resolve_role's primary-model rule — an explicit role
# model always wins, and a cli-only override displays that CLI's member/shipped
# default (what dispatch would actually run), never the role-default model of a
# different CLI. Nonzero on unknown role (rc 2) or unparseable roster (rc 4).
roster_role_entry() {
  local ROLE=${1:?usage: roster_role_entry <role>}
  RE_ROLE="$ROLE" ROSTER_FILE="ops/roster.toml" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('roster_role_entry: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

# Mirrors DEFAULTS and CLI_DEFAULT_MODEL in resolve_role (keep in sync).
DEFAULTS = {
    'builder':    {'cli': 'claude',      'model': '',                      'effort': 'max',   'fallbacks': ['codex', 'antigravity']},
    'reviewer':   {'cli': 'codex',       'model': 'gpt-6-astra',           'effort': 'xhigh', 'fallbacks': ['antigravity', 'claude']},
    'tester':     {'cli': 'codex',       'model': 'gpt-6-astra',           'effort': 'xhigh', 'fallbacks': ['claude']},
    'analyst':    {'cli': 'antigravity', 'model': 'Gemini 3.8 Flash (High)', 'effort': 'high',  'fallbacks': ['claude']},
    'documenter': {'cli': 'antigravity', 'model': 'Gemini 3.8 Flash (High)', 'effort': 'high',  'fallbacks': ['claude']},
}
CLI_DEFAULT_MODEL = {
    'claude': '',
    'antigravity': 'Gemini 3.8 Flash (High)',
    'codex': 'gpt-6-astra',
    'opencode': 'openrouter/z-ai/glm-5.3',
    'kimi': 'kimi-code/k3',
    'cursor': 'cursor-grok-4.6-xhigh',
}
role = os.environ['RE_ROLE']
if role not in DEFAULTS:
    sys.stderr.write('roster_role_entry: ERROR unknown role ' + repr(role) + ' (valid: ' + ', '.join(DEFAULTS) + ')\n')
    sys.exit(2)
path = os.environ['ROSTER_FILE']
roster = {}
user = {}
if os.path.isfile(path):
    try:
        with open(path, 'rb') as f:
            roster = tomllib.load(f)
    except tomllib.TOMLDecodeError as exc:
        sys.stderr.write('roster_role_entry: ERROR malformed ' + path + ': ' + str(exc) + '\n')
        sys.exit(4)
    # Normalize non-table shapes exactly like resolve_role does — a TOML-valid
    # scalar roles value must degrade to defaults, not crash the reader.
    # (NB: this python source lives in a double-quoted bash string; backticks
    # here would be command-substituted by the shell.)
    roles = roster.get('roles', {})
    roles = roles if isinstance(roles, dict) else {}
    user = roles.get(role, {})
    user = user if isinstance(user, dict) else {}
entry = dict(DEFAULTS[role])
for field in ('cli', 'model', 'effort', 'fallbacks'):
    if field in user:
        entry[field] = user[field]
# Primary-model display rule (mirrors resolve_role's walk): a hand-edited
# cli-only override must show the model dispatch would use for that CLI —
# [members.<cli>].model, else the CLI's shipped default — not the role-default
# model that belongs to a different CLI.
if 'model' not in user and str(entry['cli']) != DEFAULTS[role]['cli']:
    m = roster.get('members', {})
    m = m.get(str(entry['cli']), {}) if isinstance(m, dict) else {}
    m = m if isinstance(m, dict) else {}
    entry['model'] = m.get('model', '') or CLI_DEFAULT_MODEL.get(str(entry['cli']), '')
fb = entry['fallbacks'] if isinstance(entry['fallbacks'], list) else []
print(str(entry['cli']) + '\t' + str(entry['model']) + '\t' + str(entry['effort']) + '\t' + ','.join(str(x) for x in fb))
"
}

# roster_write_role <role> <cli> <model> <effort> [fallbacks-csv]
# The SINGLE writer of [roles.<role>] in ops/roster.toml (R39 role step —
# same discipline as roster_write_member for [members.*]). Text-surgical:
# replaces an existing [roles.<role>] block in place (preserving any trailing
# standalone comment block, e.g. the optional-members guidance after
# [roles.documenter]; interior same-line comments on replaced field lines are
# dropped — replace semantics), or appends a new block, then round-trip-verifies
# the result parses AND reflects the intended values before an atomic tmp+mv.
#
# Validation is a strict SUPERSET of resolve_role's load-time rules, so a
# written roster always still loads: unknown role/CLI rejected and the chain
# (cli + fallbacks) must terminate at a core-trio member (both mirrored from
# resolve_role's load validation), plus writer-only checks resolve_role does
# not run at load — the effort enum (low|medium|high|xhigh|max) and the agy
# effort→(High)/(Low) model-suffix normalization below.
#
# When fallbacks-csv is omitted, the chain is derived from the role's CURRENT
# merged chain (read via roster_role_entry — the shared read surface, so this
# function carries no defaults copy of its own): the new primary is removed
# (the displaced primary becomes the first fallback) and 'claude' is appended
# if the result would not terminate at a core member. Model may be empty
# (builder's shell lane runs the host default Claude model by design).
roster_write_role() {
  local ROLE=${1:?usage: roster_write_role <role> <cli> <model> <effort> [fallbacks-csv]}
  local CLI=${2:?usage: roster_write_role <role> <cli> <model> <effort> [fallbacks-csv]}
  local MODEL=${3-}
  local EFFORT=${4:?usage: roster_write_role <role> <cli> <model> <effort> [fallbacks-csv]}
  local FALLBACKS=${5-__derive__}
  mkdir -p ops
  # Current merged chain from the sibling read surface — also surfaces an
  # unknown role (rc 2) or malformed roster (rc 4) with its precise error
  # before we touch the file.
  local CUR CUR_CLI CUR_FB
  CUR=$(roster_role_entry "$ROLE") || return $?
  CUR_CLI=$(printf '%s' "$CUR" | cut -f1)
  CUR_FB=$(printf '%s' "$CUR" | cut -f4)
  ROSTER_FILE="ops/roster.toml" WR_ROLE="$ROLE" WR_CLI="$CLI" WR_MODEL="$MODEL" WR_EFFORT="$EFFORT" WR_FALLBACKS="$FALLBACKS" WR_CUR_CLI="$CUR_CLI" WR_CUR_FB="$CUR_FB" python3 -c "
import json, os, re, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('roster_write_role: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

# Mirrors CORE_TRIO/KNOWN in resolve_role (keep in sync). Role names are
# validated by the roster_role_entry call in the shell wrapper; the current
# merged chain arrives via WR_CUR_* so no role-defaults copy lives here.
CORE_TRIO = ('claude', 'antigravity', 'codex')
KNOWN = ('claude', 'antigravity', 'codex', 'opencode', 'kimi', 'cursor')
EFFORTS = ('low', 'medium', 'high', 'xhigh', 'max')

path = os.environ['ROSTER_FILE']
role = os.environ['WR_ROLE']
cli = os.environ['WR_CLI']
model = os.environ['WR_MODEL'].strip()
effort = os.environ['WR_EFFORT']
fb_arg = os.environ['WR_FALLBACKS']

if cli not in KNOWN:
    sys.stderr.write('roster_write_role: ERROR unknown CLI ' + repr(cli) + ' (known: ' + ', '.join(KNOWN) + ')\n')
    sys.exit(2)
if effort not in EFFORTS:
    sys.stderr.write('roster_write_role: ERROR effort must be one of ' + '|'.join(EFFORTS) + ', got ' + repr(effort) + '\n')
    sys.exit(2)

raw = ''
roster = {}
if os.path.isfile(path):
    with open(path, 'r') as f:
        raw = f.read()
    try:
        roster = tomllib.loads(raw)
    except tomllib.TOMLDecodeError as exc:
        sys.stderr.write('roster_write_role: ERROR malformed ' + path + ': ' + str(exc) + '\n')
        sys.exit(4)

# Current merged chain, as resolved by roster_role_entry in the wrapper.
cur_chain = [os.environ['WR_CUR_CLI']] + [x for x in os.environ['WR_CUR_FB'].split(',') if x]

if fb_arg == '__derive__':
    fallbacks = [x for x in cur_chain if x != cli]
    if not fallbacks or fallbacks[-1] not in CORE_TRIO:
        fallbacks.append('claude')
else:
    fallbacks = [x.strip() for x in fb_arg.split(',') if x.strip()]

for x in fallbacks:
    if x not in KNOWN:
        sys.stderr.write('roster_write_role: ERROR fallbacks name unknown CLI ' + repr(x) + ' (known: ' + ', '.join(KNOWN) + ')\n')
        sys.exit(2)
chain = [cli] + fallbacks
if chain[-1] not in CORE_TRIO:
    sys.stderr.write('roster_write_role: ERROR chain ' + repr(chain) + ' does not terminate at a core-trio member (claude, antigravity, codex) — a chain resolving entirely to optional members cannot ship\n')
    sys.exit(2)

# agy's effort control IS the (Low)/(Medium)/(High) model-variant suffix (see
# the roster template header): normalize the written pair so it cannot
# contradict itself — dispatch passes only the model string, so a mismatched
# suffix would silently win over effort. Three-state map (a behavior change
# from v3.1, which collapsed medium to (Low)): low -> (Low), medium ->
# (Medium), high/xhigh/max -> (High). Families without a (Medium) variant
# (3.1 Pro: agy lists only (Low)/(High)) collapse medium to (Low) with a NOTE.
# An EMPTY agy model is auto-filled with the effort-matched shipped default
# (Gemini 3.8 Flash (<want>) — D-022: newest Gemini at its highest thinking
# level, Pro or Flash); otherwise the empty model falls back to the (High)
# default at dispatch and a low/medium effort is silently lost. Models without
# a variant suffix are written through untouched, no note. This block runs
# AFTER every rejecting check above so its stderr NOTE is only ever emitted on
# a path that reaches the write.
if cli == 'antigravity':
    want = {'low': 'Low', 'medium': 'Medium'}.get(effort, 'High')
    NO_MEDIUM = ('Gemini 3.1 Pro',)   # families agy lists without a (Medium) variant
    if not model:
        model = 'Gemini 3.8 Flash (' + want + ')'
        sys.stderr.write('roster_write_role: NOTE empty agy model auto-filled with the effort-matched pin ' + repr(model) + ' (agy effort rides in the (Low)/(Medium)/(High) suffix)\n')
    else:
        m2 = re.match(r'^(.*?)\s*\((High|Medium|Low)\)$', model)
        if m2:
            family = m2.group(1).strip()
            eff_want = want
            if eff_want == 'Medium' and family in NO_MEDIUM:
                eff_want = 'Low'
                sys.stderr.write('roster_write_role: NOTE ' + family + ' has no (Medium) variant — medium effort maps to (Low)\n')
            if m2.group(2) != eff_want:
                model = family + ' (' + eff_want + ')'
                sys.stderr.write('roster_write_role: NOTE agy effort maps into the (Low)/(Medium)/(High) model suffix — model normalized to ' + repr(model) + ' to match effort=' + effort + '\n')

# Cursor's effort control is likewise a model-id SUFFIX (D-025, CUR-10/12):
# cursor-grok-4.6-low|medium|high|xhigh. A bare Grok family name (grok-4.6) is
# composed into the suffixed id from effort; an explicit suffixed id is
# normalized to match the effort; anything else (composer-2.5, a non-Grok id)
# is written through untouched. Empty model -> the shipped default family.
# Sibling: _cursor_model_for_effort is the DISPATCH-time composer and keeps an
# explicit suffix as written — the two precedence rules are deliberate (writer
# normalizes the stored pin, dispatcher honors it). Same regex in both.
if cli == 'cursor':
    sfx = {'low': 'low', 'medium': 'medium', 'high': 'high'}.get(effort, 'xhigh')
    m3 = re.match(r'^(?:cursor-)?(grok-[0-9][0-9.]*?)(?:-(low|medium|high|xhigh))?(-fast)?$', model or 'grok-4.6')
    if m3:
        fam, had, fast = m3.group(1), m3.group(2), m3.group(3) or ''
        new_model = 'cursor-' + fam + '-' + sfx + fast
        if not model:
            sys.stderr.write('roster_write_role: NOTE empty cursor model auto-filled with the effort-matched pin ' + repr(new_model) + ' (cursor effort rides in the model-id suffix)\n')
        elif had and had != sfx:
            sys.stderr.write('roster_write_role: NOTE cursor effort maps into the model-id suffix — model normalized to ' + repr(new_model) + ' to match effort=' + effort + '\n')
        elif not had:
            sys.stderr.write('roster_write_role: NOTE bare cursor model ' + repr(model) + ' composed to ' + repr(new_model) + ' (effort=' + effort + ' rides in the suffix)\n')
        model = new_model

block = ('[roles.' + role + ']\n'
         'cli = ' + json.dumps(cli) + '\n'
         'model = ' + json.dumps(model) + '\n'
         'effort = ' + json.dumps(effort) + '\n'
         'fallbacks = ' + json.dumps(fallbacks) + '\n')

lines = raw.splitlines(keepends=True)
hdr = re.compile(r'^\[roles\.' + re.escape(role) + r'\][ \t]*$')
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
    # Trailing standalone comment/blank lines after the table's last key are
    # documentation for what FOLLOWS (e.g. the optional-members guidance block
    # after [roles.documenter]) — walk end back so they survive the replace.
    while end > start + 1 and (lines[end - 1].strip() == '' or lines[end - 1].lstrip().startswith('#')):
        end -= 1
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
    r = data.get('roles', {}).get(role, {})
    assert isinstance(r, dict), 'roles.' + role + ' is not a table after write'
    assert r.get('cli') == cli, 'cli mismatch after write'
    assert str(r.get('model', '')) == model, 'model mismatch after write'
    assert r.get('effort') == effort, 'effort mismatch after write'
    assert r.get('fallbacks') == fallbacks, 'fallbacks mismatch after write'
except Exception as exc:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    sys.stderr.write('roster_write_role: ERROR serialized roster failed round-trip verify: ' + str(exc) + '\n')
    sys.exit(4)
os.replace(tmp, path)
sys.stderr.write('roster_write_role: [roles.' + role + '] cli=' + cli + ' model=' + (model or '<host default>') + ' effort=' + effort + ' fallbacks=' + ','.join(fallbacks) + '\n')
"
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
      local CBIN_AUTH=""
      CBIN_AUTH=$(_cursor_bin) || CBIN_AUTH="cursor-agent"
      OUT=$(_run_with_timeout 15 "$CBIN_AUTH" status 2>&1) || true
      if printf '%s' "$OUT" | grep -qi 'logged in'; then
        LINE="ok"
      else
        LINE="auth-failed: run '${CBIN_AUTH##*/} login' to sign in"; RC=1
      fi
      ;;
    opencode)
      if [ -n "${OPENROUTER_API_KEY:-}" ]; then
        LINE="ok"
      elif _run_with_timeout 15 opencode auth list 2>/dev/null | grep -qi 'openrouter'; then
        LINE="ok"
      else
        LINE="auth-failed: set OPENROUTER_API_KEY, or run 'opencode auth login' and connect the openrouter provider (the openrouter/z-ai/glm-5.3 default needs it)"; RC=1
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
