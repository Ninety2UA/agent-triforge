#!/usr/bin/env bash
# scripts/lib/roster.sh — roster resolution (KTD-2) and enrollment (R37/R39): resolve_role, dispatch_role, ensure_core_trio_live, latest_probe_record, roster_* helpers. scripts/validate-versions.sh parses the DEFAULTS / CLI_DEFAULT_MODEL literals here
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
import os, re, shutil, sys
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
            mm = re.match(r'^(?:cursor-)?(grok-[0-9][0-9.]*?)(?:-(low|medium|high|xhigh))?(-fast)?$', model)
            if mm:
                sfx = {'low': 'low', 'medium': 'medium', 'high': 'high'}.get(e, 'xhigh')
                model = 'cursor-' + mm.group(1) + '-' + sfx + (mm.group(3) or '')
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
import os, sys, re
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
        mm = re.match(r'^(?:cursor-)?(grok-[0-9][0-9.]*?)(?:-(low|medium|high|xhigh))?(-fast)?$', model)
        if mm:
            sfx = {'low': 'low', 'medium': 'medium', 'high': 'high'}.get(e, 'xhigh')
            entry['model'] = 'cursor-' + mm.group(1) + '-' + sfx + (mm.group(3) or '')
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
