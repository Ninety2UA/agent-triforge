#!/usr/bin/env bash
# scripts/lib/common.sh — shared helpers: the host-marker scrub, the fail-closed timeout wrapper, output scrubbing, the KTD-9 failure classifier, and the agy/codex listing + feature-detection helpers
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/common.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# Host-marker scrub prefix for the foreground invoke_* lanes (see the header).
_HOST_SCRUB=(env -u CLAUDECODE -u CODEX_SANDBOX -u CODEX_SANDBOX_NETWORK_DISABLED
             -u CODEX_SESSION_ID -u CODEX_THREAD_ID -u CODEX_CI -u GROK_AGENT
             -u GROK_SESSION_ID -u CURSOR_AGENT -u CURSOR_CONVERSATION_ID
             -u OPENCODE_TERMINAL -u CLICOLOR_FORCE -u GH_FORCE_TTY NO_COLOR=1)

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
#   _INVOKE_FAILURE_REASON  binary-missing | timeout-tool-missing | auth | quota | ""
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
  elif [ -n "$OUT" ] && [ -f "$OUT" ] && grep -qiE 'usage limit|quota (exceeded|exhausted|reached)|reached your (monthly|daily|usage)|billing cycle|purchase extra usage|insufficient (credit|balance|quota)' "$OUT" 2>/dev/null; then
    # Provider quota / usage-limit exhaustion: a retry cannot help and burns a
    # second timeout window; the fix is a refreshed cycle or purchased usage.
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="quota"
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
