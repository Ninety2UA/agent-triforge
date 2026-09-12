#!/usr/bin/env bash
# scripts/lib/antigravity.sh — the Antigravity (agy) lane: invoke_antigravity and the JSON-envelope parser (KTD2/D-032)
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/antigravity.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

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
                echo "invoke_antigravity: agent=${AGENT_NAME} retry also returned an empty response (status=$(cat "${OUTPUT_FILE}.status" 2>/dev/null)) — no-output. See ${RAW} / ${ERR}." >&2
                # Leave the diagnostic in OUTPUT_FILE, like the first-pass branch: a
                # captured-only caller must never read an empty file as "no findings".
                cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true ;;
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
