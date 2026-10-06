#!/usr/bin/env bash
# scripts/lib/roster.sh — roster resolution (KTD-2) and enrollment (R37/R39): resolve_role, dispatch_role, ensure_core_trio_live, latest_probe_record, roster_* helpers. The role table is the DEFAULTS literal here (_ROLE_DEFAULTS_PY, parsed by scripts/validate-versions.sh check 3); every per-CLI value — binary, model, tier, install hint — comes from the CLI registry in scripts/lib/registry.sh (KTD7)
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/roster.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Roster resolution (KTD-2) — ops/roster.toml decides who does what
# ---------------------------------------------------------------------------

# The role table — the ONE copy of the shipped role defaults, spliced into
# resolve_role and roster_role_entry (python source, like _TRIFORGE_CLIS_PY in
# scripts/lib/registry.sh, which supplies everything per-CLI). Mirrors
# templates/ops/roster.toml; scripts/validate-versions.sh check 3 parses this
# literal, requires each role's model to equal its CLI's registry model, and
# diffs the template against it. builder model "" means: the claude -p lease
# lane runs Claude Code's own default model (no --model pin; the lane reads no
# user-tier settings, KTD16); the Fable/downgrade ladder is the lead's
# spawn-time choice, never this lane's.
# Single-quoted shell literal: python strings inside use double quotes only.
_ROLE_DEFAULTS_PY='
DEFAULTS = {
    "builder":    {"cli": "claude",      "model": "",                        "effort": "max",   "fallbacks": ["codex", "antigravity"]},
    "reviewer":   {"cli": "codex",       "model": "gpt-6-astra",             "effort": "xhigh", "fallbacks": ["antigravity", "claude"]},
    "tester":     {"cli": "codex",       "model": "gpt-6-astra",             "effort": "xhigh", "fallbacks": ["claude"]},
    "analyst":    {"cli": "antigravity", "model": "Gemini 3.8 Flash (High)", "effort": "high",  "fallbacks": ["claude"]},
    "documenter": {"cli": "antigravity", "model": "Gemini 3.8 Flash (High)", "effort": "high",  "fallbacks": ["claude"]},
}
'

# resolve_role <role> — map a task-type role (builder | reviewer | tester |
# analyst | documenter) to the member that should handle it right now.
# Prints one line on success:   cli<TAB>model<TAB>effort
# (builder's model field is empty by design: the `claude -p` builder lane runs
# Claude Code's own default model with no --model pin, so the roster has no
# model to carry there. The Fable/downgrade ladder is the lead's spawn-time
# choice — the Agent tool's `model` parameter under a Claude lead — NOT this
# shell lane.)
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
#   - a [lead] table must name a CLI that can lead, with valid fields (KTD1;
#     lead_load in _LEAD_PY, below)
#   - a consent CLI (devin) needs a recorded consent before it is enabled or
#     named in a chain, and a role-limited CLI takes another role only through
#     its recorded opt-in (R24; member_rules in _MEMBER_RULES_PY, below)
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
# resolve_role also adds opencode itself when the installed binary is V2 or
# its version can't be read (D-049), with one stderr WARNING per call.
resolve_role() {
  local ROLE=${1:?usage: resolve_role <role>}
  # Prime TRIFORGE_CURSOR_BIN for the BINARY map below: on a host that ships
  # only Cursor's `agent` binary the presence check would otherwise look for
  # `cursor-agent` and skip the member silently (AE1) even when the roster
  # names cursor as a role's primary. Cheap when cursor-agent exists.
  [ -n "${TRIFORGE_CURSOR_BIN:-}" ] || _cursor_bin >/dev/null 2>&1 || true
  # OpenCode V2, or an OpenCode whose version can't be read (D-049): every
  # dispatch to it refuses, so walk past it like an absent member and let the
  # fallback chain pick the next CLI, instead of failing the role on every
  # task. Only a roster that names opencode can put it in a chain (no shipped
  # default chain does), so a stock roster never pays for the version probe.
  local RR_EXCLUDE=${RESOLVE_ROLE_EXCLUDE:-}
  if [ -f ops/roster.toml ] && grep -q 'opencode' ops/roster.toml 2>/dev/null \
     && command -v opencode >/dev/null 2>&1 && ! _opencode_v2_check opencode; then
    RR_EXCLUDE="${RR_EXCLUDE:+${RR_EXCLUDE},}opencode"
    echo "resolve_role: WARNING opencode skipped in every role's chain — version ${_OPENCODE_VERSION:-unreadable} is unsupported or unconfirmed (D-049); pin V1 with: ${_OPENCODE_V1_PIN}" >&2
  fi
  RESOLVE_ROLE_EXCLUDE="$RR_EXCLUDE" ROLE="$ROLE" ROSTER_FILE="ops/roster.toml" python3 -c "
import os, re, shutil, sys
${_CURSOR_ID_PY}
${_TRIFORGE_CLIS_PY}
${_ROLE_DEFAULTS_PY}
${_LEAD_PY}
${_MEMBER_RULES_PY}
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('resolve_role: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

# DEFAULTS (the role table, _ROLE_DEFAULTS_PY above) and CLIS (the CLI
# registry, scripts/lib/registry.sh) are the two spliced literals; everything
# per-CLI below is derived from CLIS, never written out here.
CORE_TRIO = tuple(c for c, e in CLIS.items() if e['tier'] == 'core')
# cli name -> binary looked up on PATH. A registry binary_env (cursor:
# TRIFORGE_CURSOR_BIN, which _cursor_bin exports after accepting an agent
# binary whose --version matches the Cursor YYYY.MM.DD-<hex> format — KTD3 /
# D-025) replaces the plain name when set.
BINARY = {c: (os.environ.get(e['binary_env']) if e['binary_env'] else None) or e['binary'] for c, e in CLIS.items()}
# Shipped per-CLI default model (the registry's model field), used when a
# member is reached via fallback or chosen as an overridden primary with no
# explicit role model. A [members.<cli>].model entry overrides it.
CLI_DEFAULT_MODEL = {c: e['model'] for c, e in CLIS.items()}
# G12-style install/login guidance (R21) — the same line cli_install_fix prints.
INSTALL_FIX = {c: 'install ' + e['name'] + ' (' + e['install'] + ')' + (', then ' + e['login'] if e['login'] else '') for c, e in CLIS.items()}

path = os.environ.get('ROSTER_FILE', 'ops/roster.toml')
# A malformed roster exits 4, its TOMLDecodeError text naming the line.
roster = lead_roster(tomllib, path, 'resolve_role')

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
# [lead] (KTD1): a lead that cannot load fails every load, like a bad role.
lead_load(roster, reject)

merged = {}
for name, dflt in DEFAULTS.items():
    entry = dict(dflt)
    user = user_roles.get(name, {})
    user = user if isinstance(user, dict) else {}
    for field in ('cli', 'model', 'effort', 'fallbacks'):
        if field in user:
            entry[field] = user[field]
    entry['user_model'] = 'model' in user
    entry['user_effort'] = 'effort' in user
    if not isinstance(entry['cli'], str):
        reject('role ' + repr(name) + ': cli must be a string')
    if not isinstance(entry['fallbacks'], list) or not all(isinstance(x, str) for x in entry['fallbacks']):
        reject('role ' + repr(name) + ': fallbacks must be an array of CLI names')
    chain = [entry['cli']] + list(entry['fallbacks'])
    for cli in chain:
        if cli not in BINARY:
            reject('role ' + repr(name) + ' names unknown CLI ' + repr(cli) + ' (known: ' + ', '.join(BINARY) + ')')
    if chain[-1] not in CORE_TRIO:
        reject('role ' + repr(name) + ' fallback chain ' + repr(chain) + ' does not terminate at a core-trio member (' + ', '.join(CORE_TRIO) + ') — a chain resolving entirely to optional members cannot ship')
    merged[name] = entry
# Consent and role limits (R24, _MEMBER_RULES_PY): every role's chain, every load.
member_rules(members, {n: [e['cli']] + list(e['fallbacks']) for n, e in merged.items()}, reject)

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
    # An effort-only override on a role whose model is the shipped default:
    # agy and Cursor carry effort IN the model id, so the default's suffix
    # would silently win over the roster effort. Recompose the suffix from the
    # effort (same maps as roster_write_role); an explicit roster model is a
    # user pin and passes through unchanged (explicit suffix wins).
    if entry['user_effort'] and not entry['user_model'] and isinstance(model, str):
        e = str(entry['effort'])
        if cli == 'antigravity':
            fam = re.sub(r'\s*\((Low|Medium|High)\)\s*$', '', model)
            sfx = {'low': 'Low', 'medium': 'Medium'}.get(e, 'High')
            if sfx == 'Medium' and '3.1 Pro' in fam:
                sfx = 'Low'                     # the 3.1 Pro line has no (Medium)
            model = fam + ' (' + sfx + ')'
        elif cli == 'cursor':
            mm = cursor_grok_match(model)     # shared id format (_CURSOR_ID_PY, D-050)
            if mm:
                sfx = {'low': 'low', 'medium': 'medium', 'high': 'high'}.get(e, 'xhigh')
                model = cursor_grok_id(mm.group(1), sfx, mm.group(3))
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
# CURSOR_MODEL / DEVIN_MODEL) so a roster override actually reaches the CLI. This is what
# makes the optional invoke_opencode/invoke_kimi/invoke_cursor helpers LIVE and
# lets a [roles.tester] cli="opencode" override run opencode instead of codex —
# without it, resolve_role only drove the builder lane (lease_create) and the
# review/test phases hardcoded codex/antigravity.
#
# The claude lane depends on the lead (R2, KTD16). A lead whose native
# sub-agents enforce their tool lists (the registry's
# lead.native_subagents_enforced_tools: Claude Code) runs review/test work
# assigned to claude as a NATIVE Agent-tool subagent, so this prints
#   DISPATCH_ROLE_CLAUDE <agent-name> <output-file>
# to stdout and returns _RC_DISPATCH_ROLE_CLAUDE (40), signalling the calling
# command to spawn one. Any other lead (Codex) has no such sub-agent, and
# claude is an ordinary worker there: _dispatch_role_claude runs `claude -p`
# and writes its output file. Every other lane invokes its helper and returns
# the helper's own exit code (INVOKE_FAILURE_CLASS stays visible for a
# synchronous, same-shell caller).
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
  # The registry's lane field decides the subagent path (claude today): review/
  # test work on a "subagent" lane runs as a native Agent-tool subagent when the
  # lead's sub-agents enforce their tools, else as `claude -p` (see above).
  if [ "$(cli_field "$CLI" lane 2>/dev/null || true)" = "subagent" ]; then
    local NATIVE=""
    NATIVE=$(lead_field lead.native_subagents_enforced_tools) || return $?
    if [ "$NATIVE" = true ]; then
      printf 'DISPATCH_ROLE_CLAUDE %s %s\n' "$AGENT_NAME" "$OUTPUT_FILE"
      return "$_RC_DISPATCH_ROLE_CLAUDE"
    fi
    _dispatch_role_claude "$ROLE" "$AGENT_NAME" "$PROMPT" "$OUTPUT_FILE" "$TIMEOUT" "$MODEL" "$EFFORT"
    return $?
  fi
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
    devin)
      # DEVIN_ROLE picks the permission class (read for reviewer and analyst,
      # edit for an opted-in builder) and the brief a persona name lacks.
      DEVIN_MODEL="$MODEL" DEVIN_ROLE="$ROLE" invoke_devin "$AGENT_NAME" "$PROMPT" "$OUTPUT_FILE" "$TIMEOUT" "$EFFORT"
      ;;
    *)
      echo "dispatch_role: ERROR role '${ROLE}' resolved to cli '${CLI}', which has no shell dispatch arm here — not integrated. Registered CLIs: $(_known_clis '<registry unreadable>')." >&2
      return 1
      ;;
  esac
}

# _dispatch_role_claude <role> <agent-name> <prompt> <output-file> <timeout>
#   <model> <effort> — dispatch_role's claude arm under a lead without native,
# tool-enforcing sub-agents (R2, KTD16): `claude -p` from the caller's
# directory under _adapter_env (the env allowlist, the worker marker, the
# no-push config, the claude values), composed by _claude_lane_argv. A
# reviewer or an analyst gets the read class: read tools, dontAsk, and Bash
# only inside the sandbox with the working directory unwritable; a tester or a
# documenter the edit class, the ledger unwritable. Both keep the lead's git
# common dir unwritable. A Claude Code below TRIFORGE_CLAUDE_SANDBOX_FLOOR, or
# one whose version can't be read, is refused with the sandbox on
# (_claude_sandbox_floor_ok: rc 1, deterministic, the reason in <output-file>
# and on stderr). The envelope's result text lands in <output-file>
# (the envelope itself beside it, <output-file>.raw and .envelope); a run that
# returns no envelope leaves the CLI's own output there. Returns the CLI's
# exit code, with INVOKE_FAILURE_CLASS set as the invoke_* helpers set it.
_dispatch_role_claude() {
  local ROLE=$1 AGENT_NAME=$2 PROMPT=$3 OUT=$4 TIMEOUT=$5 MODEL=$6 EFFORT=$7 CLASS=read RC=0 TOBIN
  local -a DENY=()
  INVOKE_FAILURE_CLASS="none"
  if ! command -v claude >/dev/null 2>&1; then
    echo "dispatch_role: ERROR \`claude\` (Claude Code) not found on PATH — cannot run '${AGENT_NAME}'. Fix: $(cli_install_fix claude 2>/dev/null || true). No retry (deterministic)." >&2
    INVOKE_FAILURE_CLASS="deterministic"
    return 127
  fi
  TOBIN=$(_timeout_tool) || { INVOKE_FAILURE_CLASS="deterministic"; return "$_RC_NO_TIMEOUT_TOOL"; }
  if ! _claude_sandbox_floor_ok; then
    _claude_sandbox_refusal dispatch_role >&2
    _claude_sandbox_refusal dispatch_role > "$OUT" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    return 1
  fi
  case "$ROLE" in tester|documenter) CLASS=edit ;; esac
  if _lease_ctx 2>/dev/null; then
    DENY+=("$_LEASE_COMMON")
    if [ "$CLASS" = edit ]; then DENY+=("$_LEASE_LEDGER"); fi
  fi
  if [ "$CLASS" = read ]; then DENY+=("$(pwd -P)"); fi
  # Expanded only when set: outside a git repository the edit class has none.
  if [ "${#DENY[@]}" -gt 0 ]; then
    _claude_lane_argv "$CLASS" "$MODEL" "$EFFORT" "" "${DENY[@]}" || return 1
  else
    _claude_lane_argv "$CLASS" "$MODEL" "$EFFORT" "" || return 1
  fi
  echo "dispatch_role: claude -p (${CLASS} class) agent=${AGENT_NAME} model=${MODEL:-<default>} effort=${EFFORT:-<default>}" >&2
  _adapter_env claude "$TOBIN" -k 10s "${TIMEOUT}s" "${_LEASE_LANE_ARGV[@]}" "$PROMPT" < /dev/null > "$OUT" 2> "${OUT}.err" || RC=$?
  _lease_claude_envelope "$OUT" "${OUT}.err" || true
  if [ "$RC" -ne 0 ]; then
    _classify_invoke_failure "$RC" "$OUT"
    echo "dispatch_role: claude -p agent=${AGENT_NAME} exit=${RC} class=${INVOKE_FAILURE_CLASS} (see ${OUT})" >&2
  fi
  return "$RC"
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
# it. Call sites live in the at-build and at-review preambles.
# On failure: hard error listing exactly which member failed and its
# install/login fix (KTD-9 wording), return 1.
ensure_core_trio_live() {
  [ -f "$_TRIO_LIVE_CACHE" ] && return 0
  local FAILED=0
  local ROWS CORE="" NAME BIN FIX
  # The core set and each member's binary come from the CLI registry
  # (scripts/lib/registry.sh) in one read — cli_table, one line per member —
  # and the install fix is composed only when a member fails, so the happy path
  # costs one lookup for the whole trio. The rows arrive on fd 3 so the probed
  # commands keep the caller's stdin.
  ROWS=$(cli_table core binary) || return 1
  while IFS=$'\t' read -r -u 3 NAME BIN; do
    [ -n "$NAME" ] || continue
    CORE="${CORE:+${CORE} }${NAME}"
    if ! command -v "$BIN" >/dev/null 2>&1; then
      FIX=$(cli_install_fix "$NAME" 2>/dev/null || true)
      echo "ensure_core_trio_live: ERROR core member ${NAME} — \`${BIN}\` not found on PATH. Fix: ${FIX}. No retry (deterministic)." >&2
      FAILED=1
    elif ! _run_with_timeout 15 "$BIN" --version >/dev/null; then
      # stderr stays visible so the fail-closed timeout-tool message (or the
      # CLI's own complaint) names the real cause, not a generic wrapper line.
      FIX=$(cli_install_fix "$NAME" 2>/dev/null || true)
      echo "ensure_core_trio_live: ERROR core member ${NAME} — \`${BIN} --version\` failed its 15s liveness check (broken install or hung binary). Fix: ${FIX}. No retry (deterministic)." >&2
      FAILED=1
    fi
  done 3<<TRIO_ROWS_EOF
${ROWS}
TRIO_ROWS_EOF
  if [ "$FAILED" -ne 0 ]; then
    echo "ensure_core_trio_live: the core trio (${CORE// /, }) must be live before at-build or at-review can dispatch — see fixes above." >&2
    return 1
  fi
  : > "$_TRIO_LIVE_CACHE"
  return 0
}


# ---------------------------------------------------------------------------
# The lead (KTD1 — R1, R38, R40, R44) — [lead] in ops/roster.toml
# ---------------------------------------------------------------------------
#
# [lead] names the CLI that leads this checkout: cli, model, effort. A CLI can
# lead when its registry entry carries the KTD1 lead fields
# (scripts/lib/registry.sh: Claude Code and Codex, the Key Decision), and no
# [lead] table means claude (R40). Lead behavior is those fields plus the
# runtime capabilities resolve_lead_caps prints: outside this file and
# registry.sh, code reads fields (lead_field) and never branches on the lead's
# name (the KTD1 gate in scripts/validate-skills.sh). The CLI-specific facts
# left — which host markers each lead sets, how each one runs hooks — are
# decided here.
#
# The table is read from the checkout's roster: ops/roster.toml under the
# nearest ancestor holding .git (_lead_roster_path), the same directory whose
# ops/leases.toml the lease helpers use, so a helper run from a subdirectory
# sees the same lead. The readers exit as resolve_role does: 3 no TOML parser,
# 4 malformed roster, 5 an invalid [lead] (a CLI that cannot lead, a value that
# is not a table, an unknown key, an effort outside the enum).

# _LEAD_PY — the python the readers, resolve_role's load validation and the
# writer splice (single-quoted: double quotes only inside, no apostrophes).
# lead_load(roster, reject) returns (cli, model, effort, explicit). A [lead]
# that leaves out model gets its CLI's registry model; one that leaves out
# effort gets LEAD_DEFAULT_EFFORT (Codex runs at xhigh, D-021; a Claude lead
# keeps the session default, "").
_LEAD_PY='
LEAD_DEFAULT_CLI = "claude"
LEAD_DEFAULT_EFFORT = {"codex": "xhigh"}
LEAD_EFFORTS = ("low", "medium", "high", "xhigh", "max")
LEAD_KEYS = ("cli", "model", "effort")

def lead_capable():
    return [c for c, e in CLIS.items() if isinstance(e.get("lead"), dict) and e["lead"]]

def lead_toml(who):
    try:
        import tomllib
    except ImportError:
        try:
            import tomli as tomllib
        except ImportError:
            sys.stderr.write(who + ": ERROR no TOML parser available, so ops/roster.toml and its [lead] table cannot be read (a missing parser, not a missing lead capability). Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n")
            sys.exit(3)
    return tomllib

def lead_roster(tomllib, path, who):
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "rb") as f:
            return tomllib.load(f)
    except tomllib.TOMLDecodeError as exc:
        sys.stderr.write(who + ": ERROR malformed " + path + ": " + str(exc) + "\n")
        sys.exit(4)

def lead_reject(who, path, msg):
    sys.stderr.write(who + ": ERROR invalid " + path + ": " + msg + "\n")
    sys.exit(5)

def lead_load(roster, reject):
    if "lead" not in roster:
        return LEAD_DEFAULT_CLI, CLIS[LEAD_DEFAULT_CLI]["model"], LEAD_DEFAULT_EFFORT.get(LEAD_DEFAULT_CLI, ""), False
    t = roster["lead"]
    if not isinstance(t, dict):
        reject("[lead] must be a table (cli, model, effort), got a " + type(t).__name__)
    for k in t:
        if k not in LEAD_KEYS:
            reject("[lead] has an unknown key " + repr(k) + " (valid: " + ", ".join(LEAD_KEYS) + ")")
    cli = t.get("cli", LEAD_DEFAULT_CLI)
    capable = lead_capable()
    if not isinstance(cli, str) or cli not in capable:
        reject("[lead] cli = " + repr(cli) + " cannot lead: the lead is one of " + ", ".join(capable) + " (the CLIs with enforceable headless hooks and permission control)")
    model = t.get("model", CLIS[cli]["model"])
    if not isinstance(model, str):
        reject("[lead] model must be a string, got a " + type(model).__name__)
    effort = t.get("effort", LEAD_DEFAULT_EFFORT.get(cli, ""))
    if not isinstance(effort, str) or (effort and effort not in LEAD_EFFORTS):
        reject("[lead] effort must be one of " + "|".join(LEAD_EFFORTS) + " or empty (the host default), got " + repr(effort))
    return cli, model, effort, True
'

# _ROSTER_SPLICE_PY — the text surgery behind the three roster writers
# (roster_write_lead, roster_write_role, roster_write_member), spliced like
# _LEAD_PY (single-quoted: double quotes only inside, no apostrophes).
# splice_table(raw, header_re, block, keep_trailing_comments) replaces the
# first table whose header line matches header_re (an uncommented header: the
# scan for where it ends uses the same rule, so a comment never ends a table)
# with block, up to the next line that starts with [, or appends block after a
# blank line when there is none. keep_trailing_comments keeps the standalone
# comment and blank lines that end the old table: they document what follows.
# write_verified(path, new_raw, verify, who) writes new_raw beside path, loads
# it with the caller's module-level tomllib and hands it to verify, which
# raises when it does not hold the intended values; only then does it replace
# path. On a failure it removes the temporary file and exits 4.
_ROSTER_SPLICE_PY='
def splice_table(raw, header_re, block, keep_trailing_comments):
    lines = raw.splitlines(keepends=True)
    hdr = re.compile(header_re)
    top = re.compile(r"^\[")
    start = None
    for i, ln in enumerate(lines):
        if hdr.match(ln):
            start = i
            break
    if start is None:
        new_raw = raw
        if new_raw and not new_raw.endswith("\n"):
            new_raw += "\n"
        if new_raw and not new_raw.endswith("\n\n"):
            new_raw += "\n"
        return new_raw + block
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if top.match(lines[j]):
            end = j
            break
    if keep_trailing_comments:
        while end > start + 1 and (lines[end - 1].strip() == "" or lines[end - 1].lstrip().startswith("#")):
            end -= 1
    prefix = "".join(lines[:start])
    suffix = "".join(lines[end:])
    if prefix and not prefix.endswith("\n"):
        prefix += "\n"
    new_raw = prefix + block
    if suffix.strip() and not suffix.startswith("\n"):
        new_raw += "\n"
    return new_raw + suffix

def write_verified(path, new_raw, verify, who):
    tmp = path + ".tmp." + str(os.getpid())
    with open(tmp, "w") as f:
        f.write(new_raw)
    try:
        with open(tmp, "rb") as f:
            data = tomllib.load(f)
        verify(data)
    except Exception as exc:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        sys.stderr.write(who + ": ERROR serialized roster failed round-trip verify: " + str(exc) + "\n")
        sys.exit(4)
    os.replace(tmp, path)
'

# _MEMBER_RULES_PY — the consent and role-limit rules (R24) the registry's
# consent, role_limit and opt_in_roles fields declare, spliced into
# resolve_role (load validation, every load) and roster_write_role (which
# refuses what a load would), like _LEAD_PY (double quotes only inside, no
# apostrophes). member_rules(members, chains, reject), with chains a
# {role: [cli, ...]} map, calls reject when:
#   - a consent CLI has an enabled [members.<cli>] table without a consent
#     string, or a chain names it while it has no table at all (never
#     enrolled, so never consented; a declined table is absent everywhere);
#   - [members.<cli>].opt_in names a role the CLI does not offer as opt-in;
#   - a chain names a role-limited CLI for a role outside its role_limit,
#     unless the role is one of its opt_in_roles and the table opts in.
_MEMBER_RULES_PY='
def member_rules(members, chains, reject):
    for cli, e in CLIS.items():
        m = members.get(cli)
        if not isinstance(m, dict):
            continue
        opted = m.get("opt_in", [])
        if not isinstance(opted, list) or not all(isinstance(r, str) for r in opted):
            reject("[members." + cli + "] opt_in must be an array of role names")
        for r in opted:
            if r not in e["opt_in_roles"]:
                reject("[members." + cli + "] opt_in names " + repr(r) + ", which " + cli + " does not offer as an opt-in (" + (", ".join(e["opt_in_roles"]) or "none") + ")")
        if e["consent"] and m.get("enabled") is not False:
            c = m.get("consent")
            if not (isinstance(c, str) and c.strip()):
                reject("[members." + cli + "] is enabled without a recorded consent: " + e["name"] + " sends prompts and code to " + e["egress"] + ". Ask the user, then record the yes with roster_write_member " + cli + " true <model> --consent user (at-setup asks)")
    for role, chain in chains.items():
        for cli in chain:
            e = CLIS.get(cli)
            if e is None:
                continue
            m = members.get(cli)
            if e["consent"] and not isinstance(m, dict):
                reject("role " + repr(role) + " names " + cli + ", which needs the user consent on record first: enroll it with at-setup (roster_write_member " + cli + " true <model> --consent user)")
            lim = e["role_limit"]
            if not lim or role in lim:
                continue
            opted = m.get("opt_in", []) if isinstance(m, dict) else []
            if role in e["opt_in_roles"]:
                if role not in opted:
                    reject("role " + repr(role) + " names " + cli + ", which takes " + ", ".join(lim) + " by default; " + role + " needs the opt-in on record: roster_write_member " + cli + " true <model> --opt-in " + role)
            else:
                reject("role " + repr(role) + " names " + cli + ", which takes only " + ", ".join(lim + e["opt_in_roles"]) + (" (" + ", ".join(e["opt_in_roles"]) + " with the opt-in)" if e["opt_in_roles"] else ""))
'

# _lead_roster_path — the checkout's roster: <nearest ancestor holding .git>/
# ops/roster.toml (physical path, no git run — like _lease_ctx's walk), or the
# relative ops/roster.toml outside any repository.
_lead_roster_path() {
  local D
  D=$(pwd -P 2>/dev/null) || D=""
  while [ -n "$D" ]; do
    if [ -e "${D}/.git" ] || [ -L "${D}/.git" ]; then
      printf '%s/ops/roster.toml\n' "${D%/}"
      return 0
    fi
    if [ "$D" = "/" ]; then
      break
    fi
    D=${D%/*}
    if [ -z "$D" ]; then D=/; fi
  done
  printf 'ops/roster.toml\n'
}

# _lead_read <who> <3|4> — resolve_lead's and roster_lead_entry's one read.
_lead_read() {
  RL_WHO="$1" RL_COLS="$2" RL_ROSTER="$(_lead_roster_path)" python3 -c "
import os, sys
${_TRIFORGE_CLIS_PY}
${_LEAD_PY}
who, path = os.environ['RL_WHO'], os.environ['RL_ROSTER']
roster = lead_roster(lead_toml(who), path, who)
cli, model, effort, explicit = lead_load(roster, lambda msg: lead_reject(who, path, msg))
cols = [cli, model, effort]
if os.environ['RL_COLS'] == '4':
    cols.append('roster' if explicit else 'default')
print('\t'.join(cols))
"
}

# _lead_resolve — set _LEAD_RESOLVED to resolve_lead's line and _LEAD_CLI to
# its first column, with resolve_lead's rc and stderr. Call it directly, never
# in $(...): what it keeps would leave with the subshell. A success is kept for
# this shell under what decides it: the directory, the roster's path and bytes
# (_lead_roster_sig, read before and after python reads the roster, and kept
# only when the two agree), PATH and PYTHONPATH (which python and which TOML
# parser read it). While that key holds, resolve_lead, lead_field, lead_is and
# the lead host check use the kept line instead of starting python again. A
# failure is never kept: each call reads the roster again and reports it again.
_LEAD_RESOLVED=""
_LEAD_CLI=""
_LEAD_RESOLVED_KEY=""
_lead_resolve() {
  local R S K="" RC=0
  R=$(_lead_roster_path)
  S=$(_lead_roster_sig "$R")
  if [ -n "$S" ]; then K="${PWD}|${R}|${S}|${PATH:-}|${PYTHONPATH:-}"; fi
  if [ -n "$K" ] && [ "$K" = "$_LEAD_RESOLVED_KEY" ]; then
    return 0
  fi
  _LEAD_RESOLVED_KEY=""
  _LEAD_RESOLVED=$(_lead_read resolve_lead 3) || RC=$?
  if [ "$RC" -ne 0 ]; then
    _LEAD_RESOLVED=""
    _LEAD_CLI=""
    return "$RC"
  fi
  _LEAD_CLI=${_LEAD_RESOLVED%%$'\t'*}
  if [ -n "$K" ] && [ "$(_lead_roster_sig "$R")" = "$S" ]; then
    _LEAD_RESOLVED_KEY=$K
  fi
  return 0
}

# _lead_roster_sig <roster> — the roster's cksum, "absent" when there is no
# roster, nothing when one exists but can't be read (_lead_resolve then keeps
# nothing).
_lead_roster_sig() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    cksum 2>/dev/null < "$1" || true
  else
    echo absent
  fi
}

# resolve_lead — the lead of this checkout: cli<TAB>model<TAB>effort ([lead]
# overlaid on the defaults; no [lead] prints claude, an empty model and
# effort). rc 3 / 4 / 5 as described above; nothing on stderr on success.
resolve_lead() {
  _lead_resolve || return $?
  printf '%s\n' "$_LEAD_RESOLVED"
}

# roster_lead_entry — what the roster configures, for at-setup:
# cli<TAB>model<TAB>effort<TAB>roster|default (default: no [lead] table, the
# claude default). Same rc as resolve_lead.
roster_lead_entry() {
  _lead_read roster_lead_entry 4
}

# lead_field <field>... — the lead's registry values, as cli_field prints them
# for the resolved lead (lead_field lead.wait_budget_s; lead_field name
# lead.wait_budget_s for both on one line). How code outside this file reads a
# lead fact without naming the lead (KTD1). rc: resolve_lead's, then
# cli_field's.
lead_field() {
  _lead_resolve || return $?
  cli_field "$_LEAD_CLI" "$@"
}

# lead_is <cli> — 0 when <cli> is this checkout's lead, 1 when it is not or the
# lead can't be resolved, so a caller asking "is this review the lead's?" fails
# closed. The lease helpers' one comparison with the lead's CLI (U10, KTD2: a
# lead-class pin or approval counts only while its CLI is the current lead),
# kept here with the other lead facts (KTD1).
lead_is() {
  _lead_resolve 2>/dev/null || return 1
  if [ -n "${1:-}" ] && [ "$_LEAD_CLI" = "$1" ]; then
    return 0
  fi
  return 1
}

# The lead of a ledger row written before 4.0, which recorded none: 3.3.x had
# only the Claude Code lead, so such a row reads as claude (U10).
_LEAD_LEGACY_CLI=claude

# The host markers each lead CLI puts in its tool shell (U29: CC-11, CDX-15),
# as the refusal messages name them; _lead_host_read tests these four names.
_LEAD_HOST_MARKERS='CLAUDECODE or CLAUDE_CODE_ENTRYPOINT for Claude Code, CODEX_THREAD_ID or CODEX_CI for Codex'

# _lead_host_read — set _LEAD_HOST (no subshell) to the lead CLI this shell
# runs under, from the host markers: claude for CLAUDECODE or
# CLAUDE_CODE_ENTRYPOINT (Claude Code's hooks see both as well), codex for
# CODEX_THREAD_ID or CODEX_CI, none for neither, ambiguous for both (one CLI
# started from inside the other: neither can be told to lead). A worker of the
# same CLI carries the same names, which is why _lead_only tests the worker
# marker first.
_lead_host_read() {
  local C="" X=""
  if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ]; then C=claude; fi
  if [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_CI:-}" ]; then X=codex; fi
  if [ -n "$C" ] && [ -n "$X" ]; then
    _LEAD_HOST=ambiguous
  else
    _LEAD_HOST=${C:-${X:-none}}
  fi
}

# lead_host_detect — print _lead_host_read's answer: claude, codex, none or
# ambiguous.
lead_host_detect() {
  local _LEAD_HOST
  _lead_host_read
  printf '%s\n' "$_LEAD_HOST"
}

# _lead_origin — set _LEAD_VIA and _LEAD_HOST for this shell (call it
# directly, never in $(...)): ambiguous and ambiguous when both marker
# families are set, before any other source can settle it; lead-session and
# the host when one family is; tty and none when stdin is a terminal (a person
# running the helper); test and TRIFORGE_TEST_LEAD when neither but the SELF
# harness set both TRIFORGE_TEST_BUILDER and TRIFORGE_TEST_LEAD; none and none
# otherwise. lease_create records _LEAD_VIA in the row (lead_via); U10's
# approval helper stamps its records with it.
_lead_origin() {
  _lead_host_read
  case "$_LEAD_HOST" in
    ambiguous) _LEAD_VIA=ambiguous ;;
    none)
      if [ -t 0 ]; then
        _LEAD_VIA=tty
      elif [ -n "${TRIFORGE_TEST_BUILDER:-}" ] && [ -n "${TRIFORGE_TEST_LEAD:-}" ]; then
        _LEAD_VIA=test
        _LEAD_HOST=$TRIFORGE_TEST_LEAD
      else
        _LEAD_VIA=none
      fi
      ;;
    *) _LEAD_VIA=lead-session ;;
  esac
}

# _lead_origin_match <via> <host> <cli> — whether an origin (_lead_origin's,
# or one a ledger record carries) can stand for <cli>'s lead: 0 for via=tty (a
# person at a terminal) or via=lead-session / via=test whose host (the
# markers' CLI, the seam's simulated lead) is <cli>; 1 for another host; 2 for
# no origin (via=none or empty); 3 for ambiguous markers. The one origin rule
# behind the lead host check, roster_write_lead and lease_approve (and the
# merge gate's reading of a recorded approval); each caller words its own
# refusal.
_lead_origin_match() {
  case "${1:-}" in
    ambiguous) return 3 ;;
    tty) return 0 ;;
    lead-session|test)
      if [ -n "${3:-}" ] && [ "${2:-}" = "${3:-}" ]; then return 0; fi
      return 1
      ;;
  esac
  return 2
}

# _lead_ambiguous_note — the reason every refusal of ambiguous markers gives.
_lead_ambiguous_note() {
  printf '%s' "both lead host marker families are set (${_LEAD_HOST_MARKERS}): one CLI was started from inside the other, so which lead this shell runs under is ambiguous, and a terminal or the SELF seam does not settle it; run it from the lead's own tool shell, or unset the other CLI's markers"
}

# _lead_host_gate <helper> — R38, called by _lead_only (common.sh) after the
# worker-marker and lease-root checks: 0 when this shell may run a lead-owned
# helper, else one stderr line and _RC_LEAD_ONLY. It runs under the lead's own
# host markers, from a terminal (as the user, lead_via=tty), or under the SELF
# seam when TRIFORGE_TEST_LEAD names the lead (_lead_origin_match). It refuses
# under the other lead's markers (naming at-setup lead and roster_write_lead
# <cli>, the writer it runs), under both leads' markers at once, with no
# markers and no terminal, and when the lead can't be resolved (fail closed,
# with the resolver's message, read by running resolve_lead once more). A pass
# is cached in this shell for the same directory, roster bytes and origin
# (_lead_origin's via and host: the decision's whole input), so the nested
# calls (every _ledger_update) cost one cksum.
_lead_host_gate() {
  local OP=$1 ROSTER SIG="" KEY OUT RC=0 LEAD LNAME HNAME SEAM="" M=0
  ROSTER=$(_lead_roster_path)
  if [ -f "$ROSTER" ]; then SIG=$(cksum < "$ROSTER" 2>/dev/null || true); fi
  _lead_origin
  KEY="${PWD}|${ROSTER}|${SIG}|${_LEAD_VIA}|${_LEAD_HOST}"
  if [ -n "${_LEAD_GATE_KEY:-}" ] && [ "$_LEAD_GATE_KEY" = "$KEY" ]; then
    return 0
  fi
  _lead_resolve 2>/dev/null || RC=$?
  if [ "$RC" -ne 0 ]; then
    OUT=$(resolve_lead 2>&1) || true   # for its message; RC is the first call's
    echo "${OP}: REFUSED — the lead could not be resolved (rc ${RC}), so whether this shell may run a lead-owned helper is unknown; fail closed (KTD1, rc ${_RC_LEAD_ONLY}): $(printf '%s' "$OUT" | tail -1)" >&2
    return "$_RC_LEAD_ONLY"
  fi
  LEAD=$_LEAD_CLI
  _lead_origin_match "$_LEAD_VIA" "$_LEAD_HOST" "$LEAD" || M=$?
  case "$M" in
    0) ;;
    1)
      LNAME=$(cli_field "$LEAD" name 2>/dev/null) || LNAME=$LEAD
      HNAME=$(cli_field "$_LEAD_HOST" name 2>/dev/null) || HNAME=$_LEAD_HOST
      if [ "$_LEAD_VIA" = test ]; then SEAM=" (simulated: TRIFORGE_TEST_LEAD)"; fi
      echo "${OP}: REFUSED — this checkout's lead is ${LNAME} ([lead] cli = \"${LEAD}\" in ${ROSTER}), but this shell runs under ${HNAME}${SEAM}; run it from the ${LNAME} lead, or make ${HNAME} the lead first with at-setup lead or roster_write_lead ${_LEAD_HOST} (R38, rc ${_RC_LEAD_ONLY})" >&2
      return "$_RC_LEAD_ONLY"
      ;;
    3)
      echo "${OP}: REFUSED — $(_lead_ambiguous_note) (R38, rc ${_RC_LEAD_ONLY})" >&2
      return "$_RC_LEAD_ONLY"
      ;;
    *)
      echo "${OP}: REFUSED — no lead host markers (${_LEAD_HOST_MARKERS}) and no terminal on stdin, so nothing says this shell is the ${LEAD} lead; run it from the lead's tool shell or from a terminal (KTD1, R38, rc ${_RC_LEAD_ONLY})" >&2
      return "$_RC_LEAD_ONLY"
      ;;
  esac
  _LEAD_GATE_KEY=$KEY
  return 0
}

# _lead_session_key — a file-name-safe key for the lead session: the lead
# process and its start time (_lease_lead_proc in lease-wait.sh: the parent of
# the tool shell's process group leader, so one key spans every tool call of a
# Claude Code or Codex session) and the checkout; this shell's pid when the
# lead process can't be read.
_lead_session_key() {
  local K
  _LEAD_PID=0
  _LEAD_STARTED=""
  if command -v _lease_lead_proc >/dev/null 2>&1; then _lease_lead_proc; fi
  if [ "${_LEAD_PID:-0}" -gt 0 ] 2>/dev/null; then
    K="${_LEAD_PID}-$(printf '%s' "$_LEAD_STARTED" | cksum | cut -d' ' -f1)"
  else
    K="sh$$"
  fi
  printf '%s-%s\n' "$K" "$(_lead_roster_path | cksum | cut -d' ' -f1)"
}

# _lead_hooks_detect <cli> — "hooks_trusted.<event><TAB>present|absent<TAB>why"
# for each event the plugin's hooks/hooks.json declares (one
# "hooks_trusted<TAB>absent<TAB>why" line when it declares none or can't be
# read): the runtime half of KTD1. A Claude Code lead runs an enabled plugin's
# hooks, headless too (CC-12), so a declared event is present. A Codex lead
# runs hooks only when `codex features list` has hooks on, the user's Codex
# config trusts the project (read here, never written) and the project's
# .codex/hooks.json declares the event; otherwise absent, the first unmet
# condition as the reason. Whether a Codex lead also runs a plugin's hooks is
# U14's to verify (CDX-16 covers workers).
_lead_hooks_detect() {
  local CLI=${1:-} FEAT=0 ROSTER ROOT
  ROSTER=$(_lead_roster_path)
  case "$ROSTER" in
    /*) ROOT=${ROSTER%/ops/roster.toml} ;;
    *)  ROOT=$(pwd -P 2>/dev/null || pwd) ;;
  esac
  if [ "$CLI" = codex ] && _codex_feature_enabled hooks; then FEAT=1; fi
  LH_CLI="$CLI" LH_FEAT="$FEAT" LH_ROOT="${ROOT:-/}" LH_PLUGIN="${_TRIFORGE_PLUGIN_ROOT:-}/hooks/hooks.json" \
  LH_CODEX_CFG="${CODEX_HOME:-${HOME:-}/.codex}/config.toml" python3 -c "
import json, os, sys

def declared(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, ValueError):
        return None
    hooks = data.get('hooks') if isinstance(data, dict) else None
    return [e for e, v in hooks.items() if v] if isinstance(hooks, dict) else []

events = declared(os.environ['LH_PLUGIN'])
if not events:
    print('hooks_trusted\tabsent\tthe plugin hooks/hooks.json declares no event or could not be read')
    sys.exit(0)
cli = os.environ['LH_CLI']
every, why = '', {}
if cli == 'claude':
    pass
elif cli == 'codex':
    root = os.path.realpath(os.environ['LH_ROOT'])
    cfg_path = os.environ['LH_CODEX_CFG']
    if os.environ['LH_FEAT'] != '1':
        every = 'hooks is not on in codex features list'
    else:
        cfg = {}
        try:
            try:
                import tomllib
            except ImportError:
                import tomli as tomllib
            with open(cfg_path, 'rb') as f:
                cfg = tomllib.load(f)
        except (ImportError, OSError, ValueError):
            cfg = {}
        projects = cfg.get('projects', {}) if isinstance(cfg, dict) else {}
        projects = projects if isinstance(projects, dict) else {}
        if not any(isinstance(v, dict) and v.get('trust_level') == 'trusted' and os.path.realpath(k) == root for k, v in projects.items()):
            every = 'the project ' + root + ' is not trusted in ' + cfg_path
        else:
            local = declared(os.path.join(root, '.codex', 'hooks.json')) or []
            for e in events:
                if e not in local:
                    why[e] = '.codex/hooks.json declares no ' + e + ' hook'
else:
    every = 'no hook detection for this lead'
for e in events:
    r = every or why.get(e, '')
    print('hooks_trusted.' + e + '\t' + ('absent' if r else 'present') + '\t' + (r or 'detected'))
"
}

# resolve_lead_caps — the lead's capabilities, one "<name><TAB><value>" line
# each: the registry's KTD1 lead fields as cli_field formats them
# (launch_argv, wait_budget_s, tool_vocab_read, tool_vocab_action, goal_gate,
# ask_user, native_subagents_enforced_tools, agent_teams, plugin_root_env),
# then hooks_trusted.<event> present|absent, detected at runtime
# (_lead_hooks_detect) and cached for the lead session (_lead_session_key) in
# TMPDIR. The first read in a session names every capability that is empty,
# false or absent in one stderr NOTE; later reads in that session stay quiet
# (R44: reported once, never skipped silently). rc: resolve_lead's (3 no TOML
# parser, 4, 5); 2 when the registry can't be read.
resolve_lead_caps() {
  local LEAD TAB STATIC HOOKS KEY CACHE NEW=0 N V R MISS="" HMISS="" GROUP="" GR="" LNAME
  TAB=$(printf '\t')
  _lead_resolve || return $?
  LEAD=$_LEAD_CLI
  STATIC=$(RC_LEAD="$LEAD" python3 -c "
import os, sys
${_TRIFORGE_CLIS_PY}
${_CLI_FIELD_PY}
cli = os.environ['RC_LEAD']
for f in CLIS[cli]['lead']:
    print(f + '\t' + cli_value('resolve_lead_caps', cli, CLIS[cli], 'lead.' + f))
") || return 2
  KEY=$(_lead_session_key)
  CACHE="${TMPDIR:-/tmp}/triforge_lead_caps_${LEAD}_${KEY}"
  if [ -f "$CACHE" ]; then
    HOOKS=$(cat "$CACHE" 2>/dev/null || true)
  else
    HOOKS=$(_lead_hooks_detect "$LEAD") || HOOKS=""
    NEW=1
    if printf '%s\n' "$HOOKS" > "${CACHE}.tmp.$$" 2>/dev/null; then
      mv -f "${CACHE}.tmp.$$" "$CACHE" 2>/dev/null || true
    fi
  fi
  printf '%s\n' "$STATIC"
  # Absent hook events that share a reason (the usual case: one unmet
  # condition) are named together, the reason once.
  while IFS="$TAB" read -r N V R; do
    if [ -z "$N" ]; then continue; fi
    printf '%s\t%s\n' "$N" "$V"
    if [ "$V" = present ]; then continue; fi
    R=${R:-not detected}
    if [ -n "$GROUP" ] && [ "$R" = "$GR" ]; then
      GROUP="${GROUP}, ${N}"
    else
      if [ -n "$GROUP" ]; then HMISS="${HMISS}${HMISS:+, }${GROUP} (${GR})"; fi
      GROUP=$N
      GR=$R
    fi
  done <<LEAD_HOOKS_EOF
${HOOKS}
LEAD_HOOKS_EOF
  if [ -n "$GROUP" ]; then HMISS="${HMISS}${HMISS:+, }${GROUP} (${GR})"; fi
  if [ "$NEW" -eq 0 ]; then
    return 0
  fi
  while IFS="$TAB" read -r N V; do
    case "$V" in
      ""|false) if [ -n "$N" ]; then MISS="${MISS}${MISS:+, }${N}"; fi ;;
    esac
  done <<LEAD_STATIC_EOF
${STATIC}
LEAD_STATIC_EOF
  MISS="${MISS}${MISS:+${HMISS:+, }}${HMISS}"
  if [ -n "$MISS" ]; then
    LNAME=$(cli_field "$LEAD" name 2>/dev/null) || LNAME=$LEAD
    echo "resolve_lead_caps: NOTE the ${LNAME} lead runs without: ${MISS} — reported once per lead session (R44)" >&2
  fi
  return 0
}

# roster_write_lead <cli> [<model> [<effort>]] [--force]
# The single writer of [lead] (R1, R38), with roster_write_role's text surgery
# (_ROSTER_SPLICE_PY): the [lead] block is replaced in place (a trailing
# comment block kept) or appended, and the result must parse and load to the
# intended values before an atomic tmp+mv. Model left out: the CLI's registry model;
# effort left out: the lead default (xhigh for codex, the session default for
# claude); an explicit "" is written as given.
#
# It runs from either lead CLI's session, a terminal or the SELF seam, never
# from a worker or a lease root (_lead_only --any-host), and never from a
# shell with no stated origin (via=none) or with both leads' host markers
# (_lead_origin_match): switching the lead is the user's call in at-setup, and
# a lead-owned helper refused under the other CLI points here. A
# switch to another CLI refuses while the ledger holds an open lease (every
# state but merged and failed), naming each. --force hands them over: it runs
# only from the new lead or a terminal, stamps handover_from and handover_at on
# every open row (_lease_mark_handover, U10), writes the table, then runs U13's
# lead-exit sweep (lease_heartbeat_check --lead-exit) as the new lead, which
# adopts each live builder and collects each finished one with reason=lead-exit
# and requeue_count untouched; leases that are not building carry over as they
# are. The same CLI with a new model or effort is not a switch.
# rc: 0 written; 1 refused (open leases, a forced handover from elsewhere than
# the new lead, an unreadable ledger); 2 invalid argument; 3/4 roster
# unreadable; 45 a worker, a lease root, no stated origin or ambiguous host
# markers; 64 usage; after a write, the sweep's own rc.
roster_write_lead() {
  _lead_only roster_write_lead --any-host || return $?   # never from a worker or a lease root (KTD9)
  local CLI="" MODEL=__default__ EFFORT=__default__ FORCE=0 N=0 A TAB CAPABLE CUR RC=0 CUR_CLI="" ROSTER LEDGER OPEN="" SUMMARY="" IDS="" LIST="" NB=0 M=0 NL='
'
  local TRIFORGE_LEASE_ROOT="${TRIFORGE_LEASE_ROOT:-}"   # _lease_at_ledger_root may set it for the handover
  local USAGE="roster_write_lead: usage: roster_write_lead <cli> [<model> [<effort>]] [--force]"
  TAB=$(printf '\t')
  for A in "$@"; do
    case "$A" in
      --force) FORCE=1 ;;
      *)
        N=$((N + 1))
        case "$N" in
          1) CLI=$A ;;
          2) MODEL=$A ;;
          3) EFFORT=$A ;;
          *) echo "$USAGE" >&2; return 64 ;;
        esac
        ;;
    esac
  done
  if [ -z "$CLI" ]; then
    echo "$USAGE" >&2
    return 64
  fi
  CAPABLE=$(cli_table all lead 2>/dev/null | awk -F'\t' '$2 != "" { printf "%s%s", s, $1; s = " " }') || CAPABLE=""
  case " ${CAPABLE} " in
    *" ${CLI} "*) ;;
    *)
      echo "roster_write_lead: ERROR '${CLI}' cannot lead — the lead is one of: ${CAPABLE// /, } (the CLIs with enforceable headless hooks and permission control)" >&2
      return 2
      ;;
  esac
  case "$EFFORT" in
    __default__|""|low|medium|high|xhigh|max) ;;
    *)
      echo "roster_write_lead: ERROR effort must be one of low|medium|high|xhigh|max, or empty for the host default; got '${EFFORT}'" >&2
      return 2
      ;;
  esac
  # Where this runs (R38): either lead's session, a terminal or the SELF seam
  # may switch the lead (M 0 or 1); a forced handover with open leases needs
  # the new lead's (M 0, below).
  _lead_origin
  _lead_origin_match "$_LEAD_VIA" "$_LEAD_HOST" "$CLI" || M=$?
  case "$M" in
    3)
      echo "roster_write_lead: REFUSED — $(_lead_ambiguous_note) (R38, rc ${_RC_LEAD_ONLY})" >&2
      return "$_RC_LEAD_ONLY"
      ;;
    2)
      echo "roster_write_lead: REFUSED — via=none: no lead host markers (${_LEAD_HOST_MARKERS}), no terminal on stdin and no SELF seam, so nothing says a lead or the user is switching the lead; run it from either lead's tool shell or from a terminal (R38, rc ${_RC_LEAD_ONLY})" >&2
      return "$_RC_LEAD_ONLY"
      ;;
  esac
  CUR=$(roster_lead_entry 2>&1) || RC=$?
  case "$RC" in
    0) CUR_CLI=${CUR%%"$TAB"*} ;;
    5) echo "roster_write_lead: NOTE the current [lead] does not load ($(printf '%s' "$CUR" | tail -1)); this write replaces it" >&2 ;;
    *) printf '%s\n' "$CUR" >&2; return "$RC" ;;
  esac
  ROSTER=$(_lead_roster_path)
  if [ "$CLI" != "$CUR_CLI" ]; then
    LEDGER="${ROSTER%roster.toml}leases.toml"
    if ! OPEN=$(_lease_open_rows "$LEDGER"); then
      echo "roster_write_lead: REFUSED — the lead can't switch while the lease ledger can't be read (${OPEN}); fail closed (R38)" >&2
      return 1
    fi
    SUMMARY=${OPEN%%"$NL"*}
    IDS=${OPEN#"$SUMMARY"}
    IDS=${IDS#"$NL"}
    LIST=${SUMMARY%%"$TAB"*}
    NB=${SUMMARY#*"$TAB"}
    case "$NB" in ''|*[!0-9]*) NB=0 ;; esac
    if [ -n "$LIST" ] && [ "$FORCE" -eq 0 ]; then
      echo "roster_write_lead: REFUSED — switching the lead from ${CUR_CLI:-an invalid [lead]} to ${CLI} while leases are open: ${LIST}. Finish or reclaim them first, or hand them over with --force from the ${CLI} lead (R38)" >&2
      return 1
    fi
    if [ -n "$LIST" ] && [ "$M" -ne 0 ]; then
      echo "roster_write_lead: REFUSED — a forced handover runs from the new lead (${CLI}) or a terminal, so the new lead adopts the building leases; this shell runs under ${_LEAD_HOST} (R38)" >&2
      return 1
    fi
    if [ -n "$LIST" ]; then
      # Every open row records the handover before [lead] changes (U10, KTD2):
      # a lead-class pin made before it then needs the user's merge approval,
      # with no re-pin. A stamp that can't be written stops the switch. The
      # stamp and the lead-exit sweep below run under the lease root the
      # ledger was last written under, beside the lead's integrity anchors.
      _lease_ctx || return 1
      _lease_at_ledger_root roster_write_lead || return 1
      _lease_mark_handover "${CUR_CLI:-unknown}" "$CLI" "$IDS" || return 1
    fi
  fi
  WL_ROSTER="$ROSTER" WL_CLI="$CLI" WL_MODEL="$MODEL" WL_EFFORT="$EFFORT" python3 -c "
import json, os, re, sys
${_TRIFORGE_CLIS_PY}
${_LEAD_PY}
${_ROSTER_SPLICE_PY}
who = 'roster_write_lead'
tomllib = lead_toml(who)
path = os.environ['WL_ROSTER']
cli = os.environ['WL_CLI']
model = os.environ['WL_MODEL']
effort = os.environ['WL_EFFORT']
# cli and effort were checked above, before any handover stamp.
if model == '__default__':
    model = CLIS[cli]['model']
if effort == '__default__':
    effort = LEAD_DEFAULT_EFFORT.get(cli, '')

raw = ''
if os.path.isfile(path):
    with open(path, 'r') as f:
        raw = f.read()
    try:
        tomllib.loads(raw)
    except tomllib.TOMLDecodeError as exc:
        sys.stderr.write(who + ': ERROR malformed ' + path + ': ' + str(exc) + '\n')
        sys.exit(4)

block = ('[lead]\n'
         'cli = ' + json.dumps(cli) + '\n'
         'model = ' + json.dumps(model) + '\n'
         'effort = ' + json.dumps(effort) + '\n')
new_raw = splice_table(raw, r'^\[lead\][ \t]*$', block, True)

d = os.path.dirname(path)
if d:
    os.makedirs(d, exist_ok=True)
# The roster must still parse and load to these values: verify the tmp file
# BEFORE it replaces the live roster.
def fail(msg):
    raise ValueError(msg)
def verify(data):
    got = lead_load(data, fail)
    assert got == (cli, model, effort, True), 'the written [lead] loads as ' + repr(got)
write_verified(path, new_raw, verify, who)
sys.stderr.write(who + ': [lead] cli=' + cli + ' model=' + (model or '<host default>') + ' effort=' + (effort or '<host default>') + '\n')
" || return $?
  if [ "$FORCE" -eq 0 ]; then
    return 0
  fi
  if [ "$CLI" = "$CUR_CLI" ]; then
    echo "roster_write_lead: --force: the lead stays ${CLI}, nothing to hand over" >&2
    return 0
  elif [ -z "$LIST" ]; then
    echo "roster_write_lead: --force: no open lease to hand over" >&2
    return 0
  fi
  if [ "$NB" -eq 0 ]; then
    echo "roster_write_lead: --force: no lease is building; the open ones carry over to the ${CLI} lead as they are: ${LIST}" >&2
  else
    echo "roster_write_lead: --force: handing ${NB} building lease(s) over to the ${CLI} lead (lease_heartbeat_check --lead-exit); the open ones: ${LIST}" >&2
    lease_heartbeat_check --lead-exit || return $?
  fi
  return 0
}


# ---------------------------------------------------------------------------
# Enrollment (R37/R39) — onboarding optional roster members
# ---------------------------------------------------------------------------
#
# One routine serves both onboarding surfaces (AE6):
#   - R37 first-detection: hooks/handlers/session-start.sh, after optional-CLI
#     detection, calls roster_enroll_member <cli> headless for each newly
#     detected optional member. A hook cannot prompt, so headless silently
#     enrolls the shipped default (KTD-8); a later at-setup then shows the member
#     as already-enrolled instead of re-asking.
#   - R39 guided walk: skills/at-setup/SKILL.md drives the interactive ask (participate?
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
# Shipped optional defaults (KTD-8, session-settled) are the registry's model
# field (scripts/lib/registry.sh): opencode -> openrouter/z-ai/glm-5.3 ; kimi
# -> kimi-code/k3 ; cursor -> cursor-grok-4.6-xhigh (explicit suffixed pin —
# effort rides in the suffix — NEVER the Auto router). The core trio (tier
# "core" in the registry) is required, never enrolled. The binary per member
# is _registry_binary (cursor through _cursor_bin), and the official install
# command — PRINTED by setup for the user to run, never executed by Triforge —
# is the registry's install field (the surface /cli-watch re-checks each cycle).

# roster_member_default <cli> — print the shipped default model (D-020..D-025):
# the registry's model field; claude is intentionally empty (the claude -p
# lane runs Claude Code's own default model; the Fable/ladder override is the
# lead's spawn-time choice, not this lane's). rc 2 for an unknown cli.
roster_member_default() {
  local CLI=${1:?usage: roster_member_default <cli>} MODEL=""
  if ! MODEL=$(cli_field "$CLI" model 2>/dev/null); then
    echo "roster_member_default: ERROR unknown cli '${CLI}'" >&2
    return 2
  fi
  printf '%s\n' "$MODEL"
}

# _roster_is_core <cli> — 0 when the registry lists the CLI as tier "core".
_roster_is_core() {
  [ "$(cli_field "${1:-}" tier 2>/dev/null || true)" = "core" ]
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
# (for the at-setup role table), not which member would answer right now. The
# model column follows resolve_role's primary-model rule — an explicit role
# model always wins, and a cli-only override displays that CLI's member/shipped
# default (what dispatch would actually run), never the role-default model of a
# different CLI. Nonzero on unknown role (rc 2) or unparseable roster (rc 4).
roster_role_entry() {
  local ROLE=${1:?usage: roster_role_entry <role>}
  RE_ROLE="$ROLE" ROSTER_FILE="ops/roster.toml" python3 -c "
import os, sys, re
${_CURSOR_ID_PY}
${_TRIFORGE_CLIS_PY}
${_ROLE_DEFAULTS_PY}
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('roster_role_entry: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

# DEFAULTS is the spliced role table (_ROLE_DEFAULTS_PY); the per-CLI default
# model is the registry's model field — the same two sources resolve_role reads.
CLI_DEFAULT_MODEL = {c: e['model'] for c, e in CLIS.items()}
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
# Effort-only override on a default model: show the recomposed agy / Cursor
# suffix exactly as resolve_role dispatches it (explicit roster model wins).
if 'effort' in user and 'model' not in user and isinstance(entry['model'], str):
    e = str(entry['effort']); cli = str(entry['cli']); model = entry['model']
    if cli == 'antigravity':
        fam = re.sub(r'\s*\((Low|Medium|High)\)\s*$', '', model)
        sfx = {'low': 'Low', 'medium': 'Medium'}.get(e, 'High')
        if sfx == 'Medium' and '3.1 Pro' in fam:
            sfx = 'Low'
        entry['model'] = fam + ' (' + sfx + ')'
    elif cli == 'cursor':
        mm = cursor_grok_match(model)         # shared id format (_CURSOR_ID_PY, D-050)
        if mm:
            sfx = {'low': 'low', 'medium': 'medium', 'high': 'high'}.get(e, 'xhigh')
            entry['model'] = cursor_grok_id(mm.group(1), sfx, mm.group(3))
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
# written roster always still loads: unknown role/CLI rejected, the chain
# (cli + fallbacks) must terminate at a core-trio member, and the chain obeys
# the consent and role-limit rules (member_rules: devin as builder only with
# its recorded opt-in; all mirrored from resolve_role's load validation), plus writer-only checks resolve_role does
# not run at load — the effort enum (low|medium|high|xhigh|max) and the agy
# effort→(High)/(Low) model-suffix normalization below.
#
# When fallbacks-csv is omitted, the chain is derived from the role's CURRENT
# merged chain (read via roster_role_entry — the shared read surface, so this
# function carries no defaults copy of its own): the new primary is removed
# (the displaced primary becomes the first fallback) and 'claude' is appended
# if the result would not terminate at a core member. Model may be empty
# (the claude -p builder lane runs Claude Code's own default model by design).
roster_write_role() {
  _lead_only roster_write_role || return $?   # workers never write the roster (KTD9, common.sh)
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
${_CURSOR_ID_PY}
${_TRIFORGE_CLIS_PY}
${_LEAD_PY}
${_ROSTER_SPLICE_PY}
${_MEMBER_RULES_PY}
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('roster_write_role: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

# The known CLIs and the core set come from the spliced registry (CLIS), the
# same source resolve_role validates against; the effort enum is _LEAD_PY's
# (LEAD_EFFORTS), the one roster_write_lead writes against. Role names are
# validated by the roster_role_entry call in the shell wrapper; the current
# merged chain arrives via WR_CUR_* so no role-defaults copy lives here.
CORE_TRIO = tuple(c for c, e in CLIS.items() if e['tier'] == 'core')
KNOWN = tuple(CLIS)

path = os.environ['ROSTER_FILE']
role = os.environ['WR_ROLE']
cli = os.environ['WR_CLI']
model = os.environ['WR_MODEL'].strip()
effort = os.environ['WR_EFFORT']
fb_arg = os.environ['WR_FALLBACKS']

if cli not in KNOWN:
    sys.stderr.write('roster_write_role: ERROR unknown CLI ' + repr(cli) + ' (known: ' + ', '.join(KNOWN) + ')\n')
    sys.exit(2)
if effort not in LEAD_EFFORTS:
    sys.stderr.write('roster_write_role: ERROR effort must be one of ' + '|'.join(LEAD_EFFORTS) + ', got ' + repr(effort) + '\n')
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
    sys.stderr.write('roster_write_role: ERROR chain ' + repr(chain) + ' does not terminate at a core-trio member (' + ', '.join(CORE_TRIO) + ') — a chain resolving entirely to optional members cannot ship\n')
    sys.exit(2)
# Consent and role limits (R24): the load rule for this chain, so the devin
# builder without its opt-in is refused here, not at the next load.
def refuse(msg):
    sys.stderr.write('roster_write_role: ERROR ' + msg + '\n')
    sys.exit(2)
members = roster.get('members', {})
member_rules(members if isinstance(members, dict) else {}, {role: chain}, refuse)

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
# cursor-grok-4.6-low|medium|high|xhigh, grok-4.7-low|…. A bare Grok family
# name (grok-4.6) is composed into the suffixed id from effort; an explicit
# suffixed id is normalized to match the effort; anything else (composer-2.5,
# a non-Grok id) is written through untouched. Empty model -> the shipped
# default family. The cursor- prefix comes from the family, never from how
# the user typed it (D-050): cursor_grok_id in _CURSOR_ID_PY (cursor.sh).
# Sibling: _cursor_model_for_effort is the DISPATCH-time composer and keeps an
# explicit suffix as written — the two precedence rules are deliberate (writer
# normalizes the stored pin, dispatcher honors it). Both parse and prefix
# through the same _CURSOR_ID_PY helper.
if cli == 'cursor':
    sfx = {'low': 'low', 'medium': 'medium', 'high': 'high'}.get(effort, 'xhigh')
    m3 = cursor_grok_match(model or 'grok-4.6')
    if m3:
        fam, had, fast = m3.group(1), m3.group(2), m3.group(3) or ''
        new_model = cursor_grok_id(fam, sfx, fast)
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

# Trailing standalone comment/blank lines after the table's last key are
# documentation for what FOLLOWS (e.g. the optional-members guidance block
# after [roles.documenter]): they survive the replace.
new_raw = splice_table(raw, r'^\[roles\.' + re.escape(role) + r'\][ \t]*$', block, True)

# The roster MUST stay tomllib-parseable AND reflect our values after every
# write — verify the tmp file BEFORE it replaces the live roster.
def verify(data):
    r = data.get('roles', {}).get(role, {})
    assert isinstance(r, dict), 'roles.' + role + ' is not a table after write'
    assert r.get('cli') == cli, 'cli mismatch after write'
    assert str(r.get('model', '')) == model, 'model mismatch after write'
    assert r.get('effort') == effort, 'effort mismatch after write'
    assert r.get('fallbacks') == fallbacks, 'fallbacks mismatch after write'
write_verified(path, new_raw, verify, 'roster_write_role')
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

# roster_write_member <cli> <true|false> <model> [enrolled-tag] [--consent user] [--opt-in <role,...|none>]
# The SINGLE writer of [members.<cli>] in ops/roster.toml. Text-surgical so it
# preserves everything else in the file (roles, comments, promotion gate): it
# replaces an existing [members.<cli>] block in place, or appends a new one,
# then round-trip-verifies the result parses AND reflects the intended values
# before an atomic tmp+mv. Refuses unknown CLIs and refuses to disable a
# core-trio member (mirrors resolve_role's load-time rule so the roster stays
# resolvable). enrolled-tag defaults to today's date.
# Consent and opt-in (R24), for the CLIs whose registry entry asks for them:
#   --consent user   the user said yes to the egress (at-setup asked): records
#                    consent = "user <UTC> via=<origin>", the origin from
#                    _lead_origin as lease_approve stamps it (via=none and
#                    ambiguous markers are refused). Enabling a consent CLI
#                    without one, and with none already on record, is refused
#                    (rc 2); a rewrite that leaves the flag out keeps the record
#   --opt-in <roles> records opt_in = [...] (roles from the registry's
#                    opt_in_roles; none clears it); left out, the table keeps
#                    what it had
# A decline (enabled=false) drops both: re-enabling asks again.
roster_write_member() {
  _lead_only roster_write_member || return $?   # workers never write the roster (KTD9, common.sh)
  local USAGE="usage: roster_write_member <cli> <true|false> <model> [enrolled-tag] [--consent user] [--opt-in <role,...|none>]"
  local CLI=${1:?$USAGE}
  local ENABLED=${2:?$USAGE}
  local MODEL=${3-}
  local TAG="" CONSENT="" OPTIN="__keep__" STAMP=""
  shift 3 2>/dev/null || shift $#
  while [ $# -gt 0 ]; do
    case "$1" in
      --consent) CONSENT=${2-}; shift 2 2>/dev/null || { echo "roster_write_member: $USAGE" >&2; return 64; } ;;
      --opt-in)  OPTIN=${2-};   shift 2 2>/dev/null || { echo "roster_write_member: $USAGE" >&2; return 64; } ;;
      --*)       echo "roster_write_member: unknown option '$1' — $USAGE" >&2; return 64 ;;
      *)         TAG=$1; shift ;;
    esac
  done
  [ -n "$TAG" ] || TAG=$(date +%Y-%m-%d)
  if [ -n "$CONSENT" ]; then
    if [ "$CONSENT" != user ]; then
      echo "roster_write_member: ERROR --consent takes 'user' (the user said yes; a lead cannot consent for them), got '${CONSENT}'" >&2
      return 2
    fi
    _lead_origin
    case "$_LEAD_VIA" in
      ambiguous) echo "roster_write_member: REFUSED — $(_lead_ambiguous_note); a consent records where it was given" >&2; return 2 ;;
      none|"")   echo "roster_write_member: REFUSED — via=none: no lead host markers and no terminal, so the consent record could not say where it was given. Run it from the lead's tool shell or a terminal" >&2; return 2 ;;
    esac
    STAMP="user $(date -u +%Y-%m-%dT%H:%M:%SZ) via=${_LEAD_VIA}"
  fi
  mkdir -p ops
  ROSTER_FILE="ops/roster.toml" RW_CLI="$CLI" RW_ENABLED="$ENABLED" RW_MODEL="$MODEL" RW_TAG="$TAG" RW_STAMP="$STAMP" RW_OPTIN="$OPTIN" python3 -c "
import json, os, re, sys
${_TRIFORGE_CLIS_PY}
${_ROSTER_SPLICE_PY}
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
stamp = os.environ['RW_STAMP']
optin_arg = os.environ['RW_OPTIN']

# Known CLIs and the core set from the spliced registry (CLIS).
CORE = tuple(c for c, e in CLIS.items() if e['tier'] == 'core')
KNOWN = tuple(CLIS)
if cli not in KNOWN:
    sys.stderr.write('roster_write_member: ERROR unknown CLI ' + repr(cli) + ' (known: ' + ', '.join(KNOWN) + ')\n')
    sys.exit(2)
if enabled not in ('true', 'false'):
    sys.stderr.write('roster_write_member: ERROR enabled must be true|false, got ' + repr(enabled) + '\n')
    sys.exit(2)
if cli in CORE and enabled == 'false':
    sys.stderr.write('roster_write_member: ERROR [members.' + cli + '] enabled=false rejected — the core trio cannot be disabled\n')
    sys.exit(2)
e = CLIS[cli]
if stamp and not e['consent']:
    sys.stderr.write('roster_write_member: ERROR ' + cli + ' takes no consent record (only a registry entry with consent = True does)\n')
    sys.exit(2)

raw = ''
old = {}
if os.path.isfile(path):
    with open(path, 'r') as f:
        raw = f.read()
    try:
        old = tomllib.loads(raw).get('members', {}).get(cli, {})
    except tomllib.TOMLDecodeError as exc:
        sys.stderr.write('roster_write_member: ERROR malformed ' + path + ': ' + str(exc) + '\n')
        sys.exit(4)
    old = old if isinstance(old, dict) else {}

consent = ''
optin = []
if enabled == 'true':
    kept = old.get('consent') if old.get('enabled') is not False else None
    consent = stamp or (kept if isinstance(kept, str) and kept.strip() else '')
    if e['consent'] and not consent:
        sys.stderr.write('roster_write_member: REFUSED — enrolling ' + cli + ' needs the user consent on record: ' + e['name'] + ' sends prompts and code to ' + e['egress'] + ', and Cognition may train on them unless the account opts out. Ask the user; on a yes rerun with --consent user\n')
        sys.exit(2)
    if optin_arg == '__keep__':
        prev = old.get('opt_in', []) if old.get('enabled') is not False else []
        optin = [r for r in prev if isinstance(r, str)] if isinstance(prev, list) else []
    elif optin_arg not in ('', 'none'):
        optin = [r.strip() for r in optin_arg.split(',') if r.strip()]
    for r in optin:
        if r not in e['opt_in_roles']:
            sys.stderr.write('roster_write_member: ERROR ' + cli + ' offers no opt-in for ' + repr(r) + ' (opt-in roles: ' + (', '.join(e['opt_in_roles']) or 'none') + ')\n')
            sys.exit(2)

block = ('[members.' + cli + ']\n'
         'enabled = ' + enabled + '\n'
         'model = ' + json.dumps(model) + '\n'
         'enrolled = ' + json.dumps(tag) + '\n'
         + ('consent = ' + json.dumps(consent) + '\n' if consent else '')
         + ('opt_in = ' + json.dumps(optin) + '\n' if optin else ''))

# The whole old table goes, its trailing comment lines included.
new_raw = splice_table(raw, r'^\[members\.' + re.escape(cli) + r'\][ \t]*$', block, False)

# The roster MUST stay tomllib-parseable AND reflect our values after every
# write — verify the tmp file BEFORE it replaces the live roster.
def verify(data):
    m = data.get('members', {}).get(cli, {})
    assert isinstance(m, dict), 'members.' + cli + ' is not a table after write'
    assert m.get('enabled') == (enabled == 'true'), 'enabled mismatch after write'
    assert str(m.get('model', '')) == model, 'model mismatch after write'
    assert m.get('consent', '') == consent, 'consent mismatch after write'
    assert m.get('opt_in', []) == optin, 'opt_in mismatch after write'
write_verified(path, new_raw, verify, 'roster_write_member')
sys.stderr.write('roster_write_member: [members.' + cli + '] enabled=' + enabled + ' model=' + (model or '<none>') + ' enrolled=' + tag + (' consent=' + consent if consent else '') + (' opt_in=' + ','.join(optin) if optin else '') + '\n')
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
#   devin    -> devin auth status, its first line (it exits 0 logged out)
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
  # A core member's readiness is ensure_core_trio_live's job (registry tier).
  if _roster_is_core "$CLI"; then
    LINE="unknown: core member (readiness via ensure_core_trio_live)"
    printf '%s\n' "$LINE" > "$CACHE" 2>/dev/null || true
    printf '%s\n' "$LINE"
    return 2
  fi
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
    devin)
      # `devin auth status` exits 0 logged out too ("Not logged in."), so the
      # first line decides (_devin_auth_ready, devin.sh), never the exit code.
      if _devin_auth_ready; then
        LINE="ok"
      else
        LINE="auth-failed: run 'devin auth login' to sign in (\`devin auth status\` says Not logged in.)"; RC=1
      fi
      ;;
    *)
      LINE="unknown: cli '${CLI}'"; RC=2
      ;;
  esac
  printf '%s\n' "$LINE" > "$CACHE" 2>/dev/null || true
  printf '%s\n' "$LINE"
  return $RC
}

# roster_member_status <cli> — single-token status for the at-setup table:
#   core                 core-trio member present (required, never enrolled)
#   not-installed        binary absent from PATH
#   enrolled(<model>)    [members.<cli>] enabled=true
#   declined             [members.<cli>] enabled=false (shown "skipped" in table)
#   detected-unenrolled  binary present, no entry, readiness ok
#   auth-failed          binary present, no entry, readiness check failed
#   unsupported-version(<ver>)  OpenCode V2 binary, or <ver> = unreadable when
#                        `opencode --version` can't be read (D-049) — enrolled or not;
#                        every dispatch refuses it, so never shown as enrolled
# An enrolled member reports enrolled(model) regardless of current auth — the
# table carries a separate auth column for live readiness; enrollment records
# intent, not a live login.
roster_member_status() {
  local CLI=${1:?usage: roster_member_status <cli>}
  local BIN; BIN=$(_registry_binary "$CLI") || { echo "unknown-cli"; return 2; }
  if _roster_is_core "$CLI"; then
    if command -v "$BIN" >/dev/null 2>&1; then echo "core"; else echo "not-installed"; fi
    return 0
  fi
  if ! command -v "$BIN" >/dev/null 2>&1; then echo "not-installed"; return 0; fi
  if [ "$CLI" = opencode ] && ! _opencode_v2_check "$BIN"; then
    if [ "$_OPENCODE_CHECK" = unreadable ]; then
      echo "unsupported-version(unreadable)"
    else
      echo "unsupported-version(${_OPENCODE_VERSION:-2.x})"
    fi
    return 0
  fi
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
#                    (never run); at-setup shows the row as "not installed"
#   20 needs-ask     interactive + installed + unenrolled — the CALLER runs the
#                    participate?/which-model ask, then roster_write_member;
#                    also headless for a consent CLI (devin), which is never
#                    enrolled without the user's recorded yes
#   30 unsupported   installed but an unsupported line (OpenCode V2, D-049) —
#                    the V1 pin is PRINTED; nothing is recorded, never enrolled
roster_enroll_member() {
  local CLI=${1:?usage: roster_enroll_member <cli> <interactive|headless>}
  local MODE=${2:?usage: roster_enroll_member <cli> <interactive|headless>}
  local BIN DEFAULT
  BIN=$(_registry_binary "$CLI") || { echo "roster_enroll_member: unknown cli '${CLI}'" >&2; return 2; }
  if _roster_is_core "$CLI"; then
    echo "roster_enroll_member: '${CLI}' is core-trio (required, never enrolled) — nothing to do" >&2
    return 2
  fi
  case "$MODE" in
    interactive|headless) : ;;
    *) echo "roster_enroll_member: ERROR mode must be interactive|headless, got '${MODE}'" >&2; return 2 ;;
  esac
  DEFAULT=$(roster_member_default "$CLI")

  # OpenCode V2 (D-049): unsupported, so never offered for enrollment (and never
  # auto-enrolled headless). Checked before the idempotency gate so at-setup also
  # flags an already-enrolled V1 member whose binary was upgraded to V2 —
  # dispatches to it refuse until the V1 pin is restored. Nothing is recorded.
  if [ "$CLI" = "opencode" ] && command -v "$BIN" >/dev/null 2>&1 && ! _opencode_v2_check "$BIN"; then
    echo "unsupported: $(_opencode_v2_reason) Run the pin yourself — Triforge never runs installers. Until then every role's fallback chain skips opencode automatically, and direct dispatches to it refuse."
    return 30
  fi

  # Idempotency (AE6): any existing entry — enrolled OR declined — suppresses
  # the ask. This is what makes at-setup and first-detection re-runnable.
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
    echo "    $(cli_field "$CLI" install)"
    return 10
  fi

  # A CLI whose registry entry asks for consent (devin, R24) is never enrolled
  # headless: a hook cannot ask, and the record must carry the user's yes.
  # Interactive, the ask adds the consent question to participate/which model.
  local NEEDS_CONSENT=""
  NEEDS_CONSENT=$(cli_field "$CLI" consent 2>/dev/null) || NEEDS_CONSENT=""
  if [ "$MODE" = "headless" ] && [ "$NEEDS_CONSENT" = true ]; then
    echo "needs-consent: ${CLI} installed=yes — enrolling it needs the user's recorded consent ($(cli_field "$CLI" egress 2>/dev/null) sees the prompts and code); not enrolled headless. Run at-setup to ask."
    return 20
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
  if [ "$NEEDS_CONSENT" = true ]; then
    echo "  consent: required — $(cli_field "$CLI" egress 2>/dev/null) sees the prompts and code; ask the user before enrolling"
    echo "  enroll : roster_write_member ${CLI} true <model> --consent user   (recommended: ${DEFAULT})"
  else
    echo "  enroll : roster_write_member ${CLI} true <model>   (recommended: ${DEFAULT})"
  fi
  echo "  decline: roster_write_member ${CLI} false \"\""
  return 20
}
