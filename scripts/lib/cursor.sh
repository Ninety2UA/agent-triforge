#!/usr/bin/env bash
# scripts/lib/cursor.sh — the Cursor lane (optional tier): the cursor-agent/agent resolver, the effort->model-id suffix composer, invoke_cursor, the stream-json extractor
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/cursor.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

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
