#!/usr/bin/env bash
# scripts/lib/devin.sh — the Devin CLI lane (optional tier, R24): the argv composer the lease lane shares (_devin_argv), invoke_devin, the auth-status reader, the per-run config copy, the login-shell re-import flag setup reads
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
#         more) + devin-agents/config-read.json, which allows nothing and
#         denies the exec and edit tools, Write(**) and every MCP tool. No
#         command is allowed: git diff, log and show all take --output=<file>,
#         and Devin has no OS sandbox. A -p run ends at its first denied tool
#         call with no answer (DVN-05), so the read briefs say to use the
#         read, grep and glob tools only
#   edit  builder: --permission-mode dangerous (every tool approved, as the
#         cursor --force and kimi -p lanes) + devin-agents/config-edit.json,
#         which denies push, pull, fetch, commit, rebase, checkout and switch.
#         The no-push GIT_CONFIG backstop of the lease lane (_adapter_env)
#         stays the mechanical block
# --config replaces ~/.config/devin/config.json, so the user's own Devin hooks
# and settings never load in a worker. It does not replace
# ~/.config/devin/mcp_config.json: the read class also points XDG_CONFIG_HOME
# where nothing exists (_DEVIN_READ_XDG), so the user's MCP servers, and the
# skills and subagent profiles under ~/.config/devin, stay out of it.
# read_config_from keeps only agents_standard (AGENTS.md) and drops every
# other tool's config, which Devin imports by default (CLAUDE.md, .claude,
# .cursor, .windsurf hooks, MCP servers and skills; .windsurf/hooks.json ran
# with windsurf on and did not with it off, measured). agents_standard does
# not govern skills: .agents/skills, .devin/skills and ~/.agents/skills load
# with it off too.
# A project's own .devin/ and .cognition/ files still merge over the copy
# (permissions, hooks, MCP servers, required plugins), so a read-class run
# first passes _devin_project_guard.
# Devin WRITES into the file it is handed (org id, theme, mode 600), so every
# run gets a fresh copy (_devin_config_copy), never the shipped file. The copy
# seeds shell.setup_complete, which skips the first-run banner on stdout.
#
# Login-shell environment (R24): when $SHELL is set, Devin runs it as an
# interactive login shell once per session and imports every variable the
# user's profile exports into its exec tool, which defeats the env -i
# allowlist (KTD-14). With $SHELL unset it logs "login-shell env snapshot
# skipped" and imports nothing (DVN-04). Both lanes run Devin under
# _adapter_env devin (env -i, TRIFORGE_ENV_BASE, which has no SHELL, and the
# registry's env_keys, none for devin): the lease lane and invoke_devin alike,
# so a review run sees none of the lead's own exported variables either.
# devin_env_reimport reads DVN-04's verdict for setup's disclosure.
#
# Refusal fallback: DEVIN_REFUSAL_FALLBACK switches models when a provider
# refuses a request, so the served model could drift from the pinned one. It
# stays unset: env -i drops it on both lanes.
#
# Consent and role at dispatch: invoke_devin and lease_dispatch run
# _member_consent_ok and _member_role_ok (scripts/lib/roster.sh) before
# anything reaches Cognition, so a roster that enables devin without a
# recorded consent is refused even on a path that reads the table without
# loading the roster (at-review's optional lanes), and the edit class runs only
# while the builder opt-in is on record (a lease created before it was removed
# included).
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

# _devin_mode <read|edit> — the class's --permission-mode: dangerous for edit,
# auto for anything else.
_devin_mode() {
  case "${1:-}" in
    edit) echo dangerous ;;
    *) echo auto ;;
  esac
}

# The read class's XDG_CONFIG_HOME: a path under /dev/null, so nothing exists
# or can be created there. --config replaces only the user's config.json;
# Devin still reads ~/.config/devin/mcp_config.json beside it and starts those
# MCP servers with the session, plus the user's skills and subagent profiles
# under ~/.config/devin and ~/.config/cognition. With XDG_CONFIG_HOME here it
# finds none of them (measured on 3000.11.3: `devin mcp list` in a scratch
# HOME lists the HOME's server, and none with this set).
_DEVIN_READ_XDG=/dev/null/triforge-devin-read

# _devin_argv <read|edit> <config> <model> — set _DEVIN_ARGV to a devin run's
# command line up to the prompt: for the read class `env XDG_CONFIG_HOME=`
# _DEVIN_READ_XDG first, then devin with the per-run config copy, the model
# pin, the class's --permission-mode (_devin_mode), workspace trust off (-p
# fails in an untrusted directory) and -p last. The edit class sets no
# XDG_CONFIG_HOME: both lanes run under _adapter_env devin, whose allowlist
# never passes the lead's, so Devin and the project's own commands in its
# tool shell use the default ~/.config (Devin's MCP servers, skills and
# subagent profiles under ~/.config/devin included). The one composer:
# invoke_devin and _lease_lane_argv (scripts/lib/lease-wait.sh) both call it.
_devin_argv() {
  _DEVIN_ARGV=(devin --config "$2" --model "$3" --permission-mode "$(_devin_mode "$1")" --respect-workspace-trust false -p)
  if [ "${1:-}" != edit ]; then
    _DEVIN_ARGV=(env "XDG_CONFIG_HOME=${_DEVIN_READ_XDG}" "${_DEVIN_ARGV[@]}")
  fi
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

# _devin_project_guard <dir> — nothing and 0 when no project file Devin loads
# from <dir> can widen a read-class run or run code as it starts; else the
# file and the cause on stdout and 1. Devin merges the config files of <dir>
# and of each parent up to the project root (the first with .git or .jj;
# every parent when none has one) over the --config copy, from .devin/ and
# from .cognition/, the legacy name it still reads in full. Measured on
# 3000.11.3 under the read-class argv:
#   allow      a project allow widens any tool the copy does not deny: a
#              Fetch(...) allow ran webfetch unprompted (an exec allow stayed
#              refused: the copy's deny wins), so any allow or ask is refused
#   hooks      run as commands at session start, before any permission check:
#              the "hooks" key of config.json and config.local.json,
#              hooks.v1.json, and hooks.json (its older name: a SessionStart
#              and a UserPromptSubmit hook there both ran in a read-class -p
#              run); any non-empty hooks*.json is refused
#   MCP        servers start with the session: mcp_config.json and
#              mcp_config.local.json, and (documented, not measured) the
#              legacy mcpServers key of config.json, migrated on startup
#   plugins    config.json's requiredPlugins: Devin fetches and installs each
#              one unasked, signed in or not, on any command that loads
#              skills, and activates its hooks, MCP servers, skills and
#              subagents for the session (a local plugin measured
#              model-free: active_plugins=1 hooks=1 mcp_servers=1).
#              optionalPlugins installs nothing and forbiddenPlugins only
#              blocks, so both pass
#   imports    a project read_config_from is a documented project setting;
#              claude = true was not honored, and any import but
#              agents_standard left on is refused anyway
#   unknown    Devin's docs omit names it honors (no requiredPlugins key, no
#              hooks.json file), so a key the guard does not know, in a config
#              file, its permissions or an MCP file, is refused, and so is any
#              other JSON file at the top of .devin/ or .cognition/ (skills/,
#              agents/ and other non-JSON entries pass)
# Fail closed too on a .devin or .cognition that is a symlink, a file that is
# a symlink or not a plain file, and text that is not JSON once // and /* */
# comments are dropped (Devin reads JSONC) or that repeats a key. Read class
# only: the edit class approves every tool already. Skills and subagent
# profiles are not refused here: the copy's deny wins over a skill's
# allowed-tools, and a skill that asks for a subagent is rejected (DVN rows,
# devin-agents/README.md).
_devin_project_guard() {
  # the heredoc is the program, run after _PY_PRELUDE (common.sh): invoke_devin
  # runs this from the project, where python3 - would import its json.py
  python3 -c "${_PY_PRELUDE}"'exec(compile(sys.stdin.read(), "<stdin>", "exec"))' "$1" <<'DEVIN_GUARD_PY'
import json, os, stat, sys

CONFIG_FILES = ("config.json", "config.local.json", "mcp_config.json", "mcp_config.local.json")
CONFIG_KEYS = ("permissions", "read_config_from", "hooks", "mcpServers", "requiredPlugins", "optionalPlugins", "forbiddenPlugins", "version", "$schema")
PERMISSION_KEYS = ("allow", "ask", "deny")
MCP_KEYS = ("mcpServers", "$schema")

def refuse(path, why):
    print("%s: %s. Devin merges a project's .devin/ and .cognition/ files over Triforge's read-only config, so no read-class Devin run starts here (R24). Fix: remove the entry, or route the role to another roster member" % (path, why))
    sys.exit(1)

def unknown(c, known):
    extra = sorted(k for k in c if k not in known)
    return "an unknown key %s (the guard passes only %s)" % (json.dumps(extra[0]), ", ".join(known)) if extra else ""

def jsonc(t):
    # // and /* */ comments outside strings dropped (the docs: Devin reads JSONC)
    out, i, n, q = [], 0, len(t), False
    while i < n:
        c = t[i]
        if q:
            if c == "\\":
                out.append(t[i:i + 2])
                i += 2
                continue
            if c == '"':
                q = False
        elif c == '"':
            q = True
        elif t.startswith("//", i):
            j = t.find("\n", i)
            i = n if j < 0 else j
            continue
        elif t.startswith("/*", i):
            j = t.find("*/", i + 2)
            if j < 0:
                raise ValueError("an unterminated /* comment")
            out.append(" ")
            i = j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)

def nodup(pairs):
    if len(pairs) != len(set(k for k, _ in pairs)):
        raise ValueError("a repeated key")
    return dict(pairs)

def load(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as e:
        raise ValueError("a symlink or unreadable (%s)" % e.strerror)
    with os.fdopen(fd, "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            raise ValueError("not a plain file")
        data = f.read(1048577)
    if len(data) > 1048576:
        raise ValueError("larger than 1 MiB")
    return json.loads(jsonc(data.decode("utf-8")), object_pairs_hook=nodup)

def widens(name, c):
    if name.startswith("hooks"):
        return "it declares hooks, which Devin runs as commands at session start" if c else ""
    if not isinstance(c, dict):
        return "not a JSON object"
    if name.startswith("mcp_config"):
        if c.get("mcpServers"):
            return "it declares MCP servers, which Devin starts with the session"
        return unknown(c, MCP_KEYS)
    why = unknown(c, CONFIG_KEYS)
    if why:
        return why
    perms = c.get("permissions") or {}
    if not isinstance(perms, dict):
        return "permissions is not an object"
    for k in ("allow", "ask"):
        if perms.get(k):
            return "permissions.%s %s widens the read class" % (k, json.dumps(perms[k])[:120])
    why = unknown(perms, PERMISSION_KEYS)
    if why:
        return "permissions has " + why
    if c.get("hooks"):
        return "it declares hooks, which Devin runs as commands at session start"
    if c.get("mcpServers"):
        return "it declares MCP servers (mcpServers), which Devin starts with the session"
    if c.get("requiredPlugins"):
        return "requiredPlugins %s: Devin installs those plugins unasked and starts their hooks and MCP servers with the session" % json.dumps(c["requiredPlugins"])[:120]
    rcf = c.get("read_config_from")
    if rcf is not None and not isinstance(rcf, dict):
        return "read_config_from is not an object"
    on = sorted(k for k, v in (rcf or {}).items() if k != "agents_standard" and v is not False)
    if on:
        return "read_config_from turns imports on (%s)" % ", ".join(on)
    return ""

d = os.path.realpath(sys.argv[1])
while True:
    for dname in (".devin", ".cognition"):
        dv = os.path.join(d, dname)
        if os.path.islink(dv):
            refuse(dv, "a symlink")
        if not os.path.isdir(dv):
            continue
        # Every JSON file at the top of the directory, by lowercased name (a
        # case-insensitive volume opens HOOKS.json for hooks.json): the config
        # files and any hooks*.json are checked, any other JSON file refused
        for entry in sorted(os.listdir(dv)):
            name, p = entry.lower(), os.path.join(dv, entry)
            if name in CONFIG_FILES or (name.startswith("hooks") and name.endswith(".json")):
                try:
                    c = load(p)
                except ValueError as e:
                    refuse(p, "could not be checked: %s" % e)
                why = widens(name, c)
                if why:
                    refuse(p, why)
            elif name.endswith((".json", ".jsonc", ".json5")):
                refuse(p, "a JSON file the guard does not know (Devin reads its config from this directory by file name, and its docs do not list every name it reads)")
    if os.path.lexists(os.path.join(d, ".git")) or os.path.lexists(os.path.join(d, ".jj")):
        break
    up = os.path.dirname(d)
    if up == d:
        break
    d = up
DEVIN_GUARD_PY
}

# _devin_auth_ready — 0 when `devin auth status` says "Logged in" on its first
# non-empty line. 15 s cap, fail-closed timeout wrapper.
_devin_auth_ready() {
  local OUT=""
  OUT=$(_run_with_timeout 15 devin auth status 2>&1) || true
  printf '%s\n' "$OUT" | awk 'NF {print; exit}' | grep -qE '^[[:space:]]*Logged in'
}

# devin_model_choices — the model ids this Devin account offers, one per line,
# in the order `devin models list --format json` lists them (each family's
# variants, model_uid), each once; an id that is not a plain token (letters,
# digits, . _ : / -) is skipped, since it lands in the roster and on Devin's
# command line. What setup offers for [members.devin] model, which
# roster_write_member devin true <id> records and every Devin role then runs
# (resolve_role); swe-1-6-slow, the registry model, stays the shipped pin, the
# one a Free account runs. Read-only, 30 s cap. rc 69, nothing on stdout and
# the reason on stderr, when devin is not on PATH, the call fails (signed
# out, no network) or it lists no model.
devin_model_choices() {
  local OUT="" RC=0
  if ! command -v devin >/dev/null 2>&1; then
    echo "devin_model_choices: devin is not on PATH — $(cli_install_fix devin 2>/dev/null || echo 'install Devin CLI')" >&2
    return 69
  fi
  OUT=$(_run_with_timeout 30 devin models list --format json < /dev/null 2>/dev/null) || RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "devin_model_choices: devin models list failed (rc ${RC}); it needs a login (devin auth login) and the network" >&2
    return 69
  fi
  if ! printf '%s' "$OUT" | python3 -c "${_PY_PRELUDE}"'
import json, re, sys
s = sys.stdin.read()
try:
    data = json.JSONDecoder().raw_decode(s[s.index("{"):])[0]
except ValueError:
    sys.exit(1)
seen = []
for fam in (data.get("families") if isinstance(data, dict) else None) or []:
    for v in (fam.get("variants") if isinstance(fam, dict) else None) or []:
        uid = v.get("model_uid") if isinstance(v, dict) else None
        if isinstance(uid, str) and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]*", uid) and uid not in seen:
            seen.append(uid)
if not seen:
    sys.exit(1)
print("\n".join(seen))
'; then
    echo "devin_model_choices: devin models list gave no model id (an empty list, or output that is not its JSON catalog)" >&2
    return 69
  fi
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
    latest_probe_record "$_TRIFORGE_PLUGIN_ROOT" 2>/dev/null || true
  fi)
REIMPORT_RECORDS
  case "$ROW" in
    *reimport=yes*) echo yes ;;
    *reimport=no*)  echo no ;;
    *)              echo unknown ;;
  esac
}

# _devin_gate <role> <class> <output-file> <err-file> — the rules a Devin run
# passes before anything is sent (R24), against the roster and this directory
# as they are now: the recorded consent (_member_consent_ok, reason consent)
# and the role (_member_role_ok, reason role: the builder needs its opt-in on
# record), each rc 5; then, for the read class, the project's .devin/ and
# .cognition/ files (_devin_project_guard, rc 1, reason project-config). 0 when
# all pass; else the refusal on stderr and in <output-file> (a caller that
# reads only the file sees why) and class deterministic. invoke_devin runs it
# before every attempt, so a retry never rides the first attempt's checks.
_devin_gate() {
  local CRC=0 GUARD=""
  _INVOKE_FAILURE_REASON="consent"
  _member_consent_ok devin 2> "$4" || CRC=$?
  if [ "$CRC" -eq 0 ]; then
    _INVOKE_FAILURE_REASON="role"
    _member_role_ok devin "$1" 2> "$4" || CRC=$?
  fi
  if [ "$CRC" -ne 0 ]; then
    cat "$4" >&2
    cat "$4" > "$3" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    return "$CRC"
  fi
  _INVOKE_FAILURE_REASON=""
  # Devin starts in this directory, so its .devin/ and .cognition/ files must
  # not widen the read class
  if [ "$2" = read ] && ! GUARD=$(_devin_project_guard "$PWD"); then
    GUARD="invoke_devin: ERROR ${GUARD:-the project .devin/ and .cognition/ check failed to run}. No retry (deterministic)."
    echo "$GUARD" >&2
    echo "$GUARD" > "$3" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="project-config"
    return 1
  fi
  return 0
}

# invoke_devin <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
# The role comes from DEVIN_ROLE (dispatch_role sets it), else the agent name.
# Runs under _adapter_env devin, the lease lane's allowlist. Returns devin's
# exit code; 80 when a clean run printed no Status line (report missing, never
# "no findings"); 1 when it printed nothing at all; rc 5 (deterministic) when
# the roster records no consent (_member_consent_ok, reason consent) or does
# not allow devin the role now (_member_role_ok, reason role: the builder
# without its opt-in), and 1 (deterministic, project-config) when a project
# file here would widen the read class, all before anything is sent and again
# before the retry (_devin_gate); 129, 130 or 143 (deterministic, reason
# interrupted, no retry) when a signal stopped the run.
invoke_devin() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/devin_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${DEVIN_EFFORT:-}}
  local MODEL="${DEVIN_MODEL:-swe-1-6-slow}"
  local ROLE=${DEVIN_ROLE:-$AGENT_NAME}
  local ERR="${OUTPUT_FILE}.err" CLASS MODE BRIEF_FILE="" BODY="" FULL_PROMPT CFG="" EXIT_CODE=0 ATTEMPT=1 TOBIN CRC=0

  INVOKE_FAILURE_CLASS="none"
  _INVOKE_FAILURE_REASON=""

  CLASS=$(_devin_class "$ROLE")
  MODE=$(_devin_mode "$CLASS")

  # The consent, role and project rules at dispatch (R24): the builder class
  # needs the opt-in on record now, whoever calls, and the read class a
  # directory whose .devin/ and .cognition/ files do not widen it
  _devin_gate "$ROLE" "$CLASS" "$OUTPUT_FILE" "$ERR" || CRC=$?
  if [ "$CRC" -ne 0 ]; then
    return "$CRC"
  fi

  if ! command -v devin >/dev/null 2>&1; then
    echo "invoke_devin: ERROR \`devin\` (Devin CLI) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: $(cli_install_fix devin 2>/dev/null || echo 'install Devin CLI, then run devin auth login'). No retry (deterministic)." >&2
    echo "invoke_devin: devin CLI not on PATH — $(cli_install_fix devin 2>/dev/null || echo 'install Devin CLI')" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="binary-missing"
    return 127
  fi
  # env -i execs commands only, so the timeout runs as a binary (_timeout_tool)
  TOBIN=$(_timeout_tool) || { INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="timeout-tool-missing"; return "$_RC_NO_TIMEOUT_TOOL"; }

  # The brief: the agent's own (devin-agents/<agent>.md), else the role's —
  # it carries the typed report contract, so a persona name without a Devin
  # brief still gets it — else the raw prompt with a warning.
  if [ -n "$AGENT_NAME" ] && [ -f "${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${AGENT_NAME}.md" ]; then
    BRIEF_FILE="${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${AGENT_NAME}.md"
  elif [ -n "$ROLE" ] && [ -f "${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${ROLE}.md" ]; then
    BRIEF_FILE="${_TRIFORGE_PLUGIN_ROOT}/devin-agents/${ROLE}.md"
  elif [ -n "$AGENT_NAME" ]; then
    echo "invoke_devin: WARNING no devin-agents/ brief for '${AGENT_NAME}' or role '${ROLE}' (Devin has no headless agent selector — injection only); raw prompt. Available briefs: $(_list_plugin_briefs devin-agents | paste -sd, - 2>/dev/null || true)" >&2
  fi
  if [ -n "$BRIEF_FILE" ]; then
    BODY=$(_brief_body "$BRIEF_FILE")
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
    _devin_argv "$CLASS" "$CFG" "$MODEL"
    # The lease lane's allowlist (KTD-14): no SHELL, no DEVIN_* override, none
    # of the lead's own exported variables
    _adapter_env devin "$TOBIN" -k 10s "${TIMEOUT}s" "${_DEVIN_ARGV[@]}" "$FULL_PROMPT" \
      < /dev/null > "$OUTPUT_FILE" 2> "$ERR" || EXIT_CODE=$?
    rm -f "$CFG"
    # A signal stopped the run (129 HUP, 130 INT, 143 TERM): it is over, and
    # nothing starts again, the builder class least of all
    case "$EXIT_CODE" in
      129|130|143)
        echo "invoke_devin: agent=${AGENT_NAME:-<none>} interrupted (exit ${EXIT_CODE}). No retry (deterministic)." >&2
        echo "invoke_devin: interrupted (exit ${EXIT_CODE}) — no answer" > "$OUTPUT_FILE" 2>/dev/null || true
        rm -f "$ERR"
        INVOKE_FAILURE_CLASS="deterministic"
        _INVOKE_FAILURE_REASON="interrupted"
        return "$EXIT_CODE"
        ;;
    esac
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
    elif grep -qiE "$_PLAN_LIMIT_RE" "$ERR" "$OUTPUT_FILE" 2>/dev/null; then
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
      # The rules again, against the roster and this directory as the first
      # attempt left them
      _devin_gate "$ROLE" "$CLASS" "$OUTPUT_FILE" "$ERR" || CRC=$?
      if [ "$CRC" -ne 0 ]; then
        return "$CRC"
      fi
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
