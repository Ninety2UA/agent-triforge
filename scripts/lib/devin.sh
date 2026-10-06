#!/usr/bin/env bash
# scripts/lib/devin.sh — the Devin CLI lane (optional tier, R24): invoke_devin, the auth-status reader, the per-run config copy, the login-shell re-import flag setup reads
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh and scripts/lib/registry.sh.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/devin.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Devin CLI invocation (optional tier — reviewer and analyst; builder opt-in)
# ---------------------------------------------------------------------------
#
# Devin CLI (binary: devin, Cognition) runs headless as `devin -p <prompt>`. It
# has no output format flag and no result envelope: -p prints the final answer
# as plain text, so completion is the typed `Status:` line plus the exit code
# (KTD11). It has no headless agent selector either, so the role brief
# devin-agents/<name>.md (frontmatter stripped) is prefixed onto the prompt.
#
# Roles and consent live in the registry entry (scripts/lib/registry.sh):
# role_limit reviewer + analyst, builder only with the roster opt-in
# ([members.devin] opt_in = ["builder"]), and consent = True, so resolve_role
# refuses a roster that enrolls or names devin without a recorded consent.
#
# Two permission classes, picked from the role (_devin_class):
#   read  reviewer, analyst and anything unnamed: --permission-mode auto (Devin
#         approves read-only tools only; a non-interactive run cannot ask for
#         more) + devin-agents/config-read.json, which denies Write(**) and the
#         state-changing git commands and allows git diff/log/show/status
#   edit  builder: --permission-mode dangerous (every tool approved, as the
#         cursor --force and kimi -p lanes) + devin-agents/config-edit.json,
#         which denies push, pull, fetch, commit, rebase, checkout and switch.
#         The no-push GIT_CONFIG backstop of the lease lane (_adapter_env)
#         stays the mechanical block
# --config replaces ~/.config/devin/config.json, so the user's own Devin hooks,
# MCP servers and config never load in a worker; read_config_from keeps only
# agents_standard (AGENTS.md, .agents/skills) and drops Claude Code's config,
# which Devin imports by default (CLAUDE.md, .claude hooks and skills).
# Devin WRITES into the file it is handed (org id, theme, mode 600), so every
# run gets a fresh copy (_devin_config_copy), never the shipped file. The copy
# seeds shell.setup_complete, which skips the first-run banner on stdout.
#
# Login-shell environment (R24): when $SHELL is set, Devin runs it as an
# interactive login shell once per session and imports every variable the
# user's profile exports into its exec tool, which defeats the env -i
# allowlist (KTD-14). With $SHELL unset it logs "login-shell env snapshot
# skipped" and imports nothing (DVN-04). The lease lane never forwards SHELL
# (TRIFORGE_ENV_BASE), and invoke_devin unsets it; devin_env_reimport reads
# DVN-04's verdict for setup's disclosure.
#
# Refusal fallback: DEVIN_REFUSAL_FALLBACK switches models when a provider
# refuses a request, so the served model could drift from the pinned one. It
# stays unset: env -i drops it in the lease lane and invoke_devin unsets it.
#
# Model: --model "${DEVIN_MODEL:-swe-1-6-slow}" on every call. swe-1-6-slow is
# Cognition's own model and what a Devin Free account resolves to; Free
# refuses most others with "Upgrade to Pro" (a deterministic plan failure). A
# paid account can pin any `devin models list` id through the roster model.
# Devin has no effort flag; effort rides in some model ids (swe-2-high,
# swe-2-max) and is otherwise recorded for roster parity only.
#
# Readiness: `devin auth status` exits 0 logged in or not, and "Not logged
# in." contains "logged in", so _devin_auth_ready reads the first line, never
# the exit code or a substring.

# _devin_class <role> — edit for builder, read for anything else.
_devin_class() {
  case "${1:-}" in
    builder) echo edit ;;
    *) echo read ;;
  esac
}

# _devin_config_copy <read|edit> <dest> — copy the shipped per-class config to
# <dest> for one run. Nonzero when the shipped file is missing (a broken
# install: never run Devin with the user's own config instead).
_devin_config_copy() {
  local SRC="${_TRIFORGE_PLUGIN_ROOT}/devin-agents/config-${1:-read}.json"
  if [ ! -f "$SRC" ]; then
    echo "devin: ERROR ${SRC} is missing — the plugin install is incomplete; Devin never runs on the user's own config" >&2
    return 1
  fi
  cp "$SRC" "$2" && chmod 600 "$2"
}

# _devin_auth_ready — 0 when `devin auth status` says "Logged in" on its first
# non-empty line. 15 s cap, fail-closed timeout wrapper.
_devin_auth_ready() {
  local OUT=""
  OUT=$(_run_with_timeout 15 devin auth status 2>&1) || true
  printf '%s\n' "$OUT" | awk 'NF {print; exit}' | grep -qE '^[[:space:]]*Logged in'
}

# devin_env_reimport [record] — whether a Devin worker sees the login shell's
# exported variables: yes, no or unknown, from the DVN-04 row's reimport= in
# <record>, else in the project's newest probe record (latest_probe_record),
# else in the plugin's own. Setup states that Devin sees every exported secret
# on yes and on unknown (fail closed).
devin_env_reimport() {
  local ROW="" C
  while IFS= read -r C; do
    [ -n "$C" ] && [ -f "$C" ] || continue
    ROW=$(grep -E '^\|[[:space:]]*DVN-04[[:space:]]*\|' "$C" 2>/dev/null | tail -1 || true)
    if [ -n "$ROW" ]; then break; fi
  done <<REIMPORT_RECORDS
$(if [ -n "${1:-}" ]; then
    printf '%s\n' "$1"   # an explicit record is the only one read
  else
    latest_probe_record 2>/dev/null || true
    ls -1 "${_TRIFORGE_PLUGIN_ROOT}/ops/research/"*-probe-record.md 2>/dev/null | sort | tail -1
  fi)
REIMPORT_RECORDS
  case "$ROW" in
    *reimport=yes*) echo yes ;;
    *reimport=no*)  echo no ;;
    *)              echo unknown ;;
  esac
}

# invoke_devin <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
# The role comes from DEVIN_ROLE (dispatch_role sets it), else the agent name.
# Returns devin's exit code; 80 when a clean run printed no Status line
# (report missing, never "no findings"); 1 when it printed nothing at all.
invoke_devin() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/devin_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${DEVIN_EFFORT:-}}
  local MODEL="${DEVIN_MODEL:-swe-1-6-slow}"
  local ROLE=${DEVIN_ROLE:-$AGENT_NAME}
  local ERR="${OUTPUT_FILE}.err" CLASS MODE BRIEF_FILE="" BODY="" FULL_PROMPT CFG="" EXIT_CODE=0 ATTEMPT=1

  INVOKE_FAILURE_CLASS="none"
  _INVOKE_FAILURE_REASON=""

  if ! command -v devin >/dev/null 2>&1; then
    echo "invoke_devin: ERROR \`devin\` (Devin CLI) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: $(cli_install_fix devin 2>/dev/null || echo 'install Devin CLI, then run devin auth login'). No retry (deterministic)." >&2
    echo "invoke_devin: devin CLI not on PATH — $(cli_install_fix devin 2>/dev/null || echo 'install Devin CLI')" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="binary-missing"
    return 127
  fi

  CLASS=$(_devin_class "$ROLE")
  MODE=auto
  if [ "$CLASS" = edit ]; then MODE=dangerous; fi

  # The brief: the agent's own (devin-agents/<agent>.md), else the role's —
  # it carries the typed report contract, so a persona name without a Devin
  # brief still gets it — else the raw prompt with a warning.
  if [ -n "$AGENT_NAME" ] && [ -f "${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${AGENT_NAME}.md" ]; then
    BRIEF_FILE="${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${AGENT_NAME}.md"
  elif [ -n "$ROLE" ] && [ -f "${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${ROLE}.md" ]; then
    BRIEF_FILE="${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${ROLE}.md"
  elif [ -n "$AGENT_NAME" ]; then
    echo "invoke_devin: WARNING no devin-agents/ brief for '${AGENT_NAME}' or role '${ROLE}' (Devin has no headless agent selector — injection only); raw prompt. Available briefs: $(_list_devin_agents | paste -sd, - 2>/dev/null || true)" >&2
  fi
  if [ -n "$BRIEF_FILE" ]; then
    BODY=$(awk '/^---[[:space:]]*$/{skip++; next} skip>=2{print}' "$BRIEF_FILE")
  fi
  FULL_PROMPT="${BODY:+${BODY}

}## Task
${PROMPT}"

  echo "invoke_devin: agent=${AGENT_NAME:-<none>} role=${ROLE:-<none>} class=${CLASS} mode=${MODE} model=${MODEL} effort=${EFFORT:-none} (no effort flag — recorded for roster parity) brief=${BRIEF_FILE:-none}" >&2

  while :; do
    CFG=$(mktemp "${TMPDIR:-/tmp}/triforge-devin-cfg.XXXXXX") || { INVOKE_FAILURE_CLASS="deterministic"; return 1; }
    if ! _devin_config_copy "$CLASS" "$CFG"; then
      rm -f "$CFG"
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="config-missing"
      return 1
    fi
    EXIT_CODE=0
    _run_with_timeout "$TIMEOUT" "${_HOST_SCRUB[@]}" env -u SHELL -u DEVIN_REFUSAL_FALLBACK -u DEVIN_PERMISSION_MODE -u DEVIN_SANDBOX -u DEVIN_MODEL \
      devin --config "$CFG" --model "$MODEL" --permission-mode "$MODE" --respect-workspace-trust false -p "$FULL_PROMPT" \
      < /dev/null > "$OUTPUT_FILE" 2> "$ERR" || EXIT_CODE=$?
    rm -f "$CFG"
    if [ "$EXIT_CODE" -eq 0 ]; then
      if [ ! -s "$OUTPUT_FILE" ] || ! grep -q '[^[:space:]]' "$OUTPUT_FILE" 2>/dev/null; then
        # A clean exit with nothing printed is no completion (as agy's empty
        # response): retryable, the stderr kept for the reader.
        EXIT_CODE=1
        INVOKE_FAILURE_CLASS="retryable"
        _INVOKE_FAILURE_REASON="empty-response"
      else
        INVOKE_FAILURE_CLASS="none"
        break
      fi
    elif grep -qiE 'upgrade to (pro|max|a paid plan)|requires? a (paid|pro) plan|not available on your plan' "$ERR" "$OUTPUT_FILE" 2>/dev/null; then
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="plan"
    elif grep -qiE 'not logged in|devin auth login|unauthorized|unauthenticated|401' "$ERR" "$OUTPUT_FILE" 2>/dev/null; then
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON="auth"
    else
      _classify_invoke_failure "$EXIT_CODE" "$ERR"
    fi
    if [ "$INVOKE_FAILURE_CLASS" = retryable ] && [ "$ATTEMPT" -eq 1 ]; then
      echo "invoke_devin: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable${_INVOKE_FAILURE_REASON:+, ${_INVOKE_FAILURE_REASON}}), retrying once" >&2
      ATTEMPT=2
      continue
    fi
    case "$_INVOKE_FAILURE_REASON" in
      plan) echo "invoke_devin: agent=${AGENT_NAME} exit=${EXIT_CODE} the Devin plan does not include model '${MODEL}' (\"Upgrade to Pro\"). Fix: pin a model the account can use in the roster ([members.devin] model; \`devin models list\`), or upgrade the plan. No retry (deterministic)." >&2 ;;
      auth) echo "invoke_devin: agent=${AGENT_NAME} exit=${EXIT_CODE} Devin is not signed in. Fix: run \`devin auth login\`. No retry (deterministic)." >&2 ;;
      *)    echo "invoke_devin: agent=${AGENT_NAME} exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}${_INVOKE_FAILURE_REASON:+ (${_INVOKE_FAILURE_REASON})} — see ${ERR}" >&2 ;;
    esac
    # Whatever devin said goes to OUTPUT_FILE too, so a caller that reads only
    # the file never takes an empty file for "no findings".
    cat "$ERR" >> "$OUTPUT_FILE" 2>/dev/null || true
    return "$EXIT_CODE"
  done
  rm -f "$ERR"
  if [ "$(_lease_parse_status "$OUTPUT_FILE")" = MISSING ]; then
    echo "invoke_devin: agent=${AGENT_NAME} exit=0 but no Status: line — report missing, not review-ready (rc ${_RC_DEGRADED}); the answer is in ${OUTPUT_FILE}" >&2
    INVOKE_FAILURE_CLASS="retryable"
    _INVOKE_FAILURE_REASON="report-missing"
    return "$_RC_DEGRADED"
  fi
  return 0
}

# _list_devin_agents — the role briefs in the plugin's devin-agents/ (basename
# without .md), README excluded.
_list_devin_agents() {
  local f
  for f in "${_TRIFORGE_PLUGIN_ROOT}/devin-agents"/*.md; do
    [ -f "$f" ] || continue
    case "$(basename "$f" .md)" in README) continue ;; esac
    basename "$f" .md
  done 2>/dev/null | sort -u
}
