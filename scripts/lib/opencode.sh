#!/usr/bin/env bash
# scripts/lib/opencode.sh — the OpenCode lane (optional tier): invoke_opencode, the OPENCODE_PERMISSION deny set, the JSON-event-stream extractor
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/opencode.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

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
# (D-033 defense-in-depth; the adapter stays off --auto regardless). The
# patterns are prefix globs on the command string, so the common bypass
# spellings are enumerated (rm -fr / -Rf / -r, `command sudo`, `doas`,
# `git -c … push`, `git -C … push`); a pattern set can never be complete —
# the enforced boundary stays the lease worktree + the no-push git config.
_OPENCODE_PERMISSION_DEFAULT='{"bash":{"*":"allow","rm -rf*":"deny","rm -fr*":"deny","rm -Rf*":"deny","rm -fR*":"deny","rm -r *":"deny","rm -R *":"deny","git push*":"deny","git -c * push*":"deny","git -C * push*":"deny","sudo*":"deny","command sudo*":"deny","doas *":"deny"}}'

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
