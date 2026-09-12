#!/usr/bin/env bash
# scripts/lib/kimi.sh — the Kimi Code lane (optional tier): invoke_kimi (--agent-file) and the stream-json extractor
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/kimi.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

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
    if grep -qiE 'usage limit|quota (exceeded|exhausted|reached)|reached your (monthly|daily|usage)|billing cycle|purchase extra usage' "$RAW" "$ERR" 2>/dev/null; then
      # Quota exhaustion arrives as `provider.auth_error: 403 You've reached
      # your monthly usage limit …` — auth-shaped text, but login cannot fix it.
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="quota"
    elif grep -qiE 'no model configured|use /login|/login|not (logged|signed) in|unauthorized|401|credential|authentication (failed|required|expired)' "$RAW" "$ERR" 2>/dev/null; then
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
          quota)
            echo "invoke_kimi: agent=${AGENT_NAME} exit=${EXIT_CODE} Kimi usage quota exhausted for this billing cycle — wait for the refresh or purchase extra usage (https://www.kimi.com/membership/subscription?tab=quota); the roster falls back to the next member. No retry (deterministic)." >&2
            ;;
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
