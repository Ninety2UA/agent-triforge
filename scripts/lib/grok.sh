#!/usr/bin/env bash
# scripts/lib/grok.sh — the Grok Build lane (optional tier): the env and permission set every grok run carries, the argv composer the lease lane shares (_grok_argv), invoke_grok, the streaming-json extractor and the failure classifier
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh and scripts/lib/registry.sh.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/grok.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Grok Build invocation (optional tier — a worker in any role the roster gives it)
# ---------------------------------------------------------------------------
#
# Grok Build (binary: grok, xAI; U16, R23) runs headless with -p <prompt>. The
# prompt is -p's VALUE, so every command line here ends in -p and the caller
# appends the prompt (like kimi). The probe rows GRK-01..GRK-11 and SELF-06g in
# scripts/probe-capabilities.sh are the evidence for each claim below.
#
# Model and effort: every run pins --model "${GROK_MODEL:-grok-4.7}" (GROK_MODEL
# is the roster override; grok's own default has differed between its docs and
# builds, so it is never left to the CLI) and passes the roster effort as
# --effort when one is set (_grok_effort: grok-4.7 takes low, medium, high —
# its default — and xhigh; max maps to xhigh).
#
# Isolation (R23). By default grok also reads Claude Code's and Cursor's
# configuration: skills, rules, CLAUDE.md, MCP servers, hooks, plugins and
# permission files. _GROK_ENV turns that discovery off for the process
# (GROK_CLAUDE_*_ENABLED=0 and GROK_CURSOR_*_ENABLED=0; GRK-04 reads the result
# with `grok inspect`), along with auto-update, telemetry and cross-session
# memory. GROK_FOLDER_TRUST=0 is process-scoped trust: a fresh lease worktree
# is untrusted, and untrusted grok loads none of the worktree's skills
# (SELF-06g); `--trust` would write ~/.grok/trusted_folders.toml instead.
# What no switch reaches (GRK-06). The Claude Code plugins under
# ~/.claude/plugins load, and the session offers their skills and commands
# (codex:review among them); and a session starts the ~/.claude.json MCP
# servers that `grok inspect` reports off. Only config-file keys turn these
# off (`[plugins] disabled`, a project `[mcp_servers.<name>]` with
# enabled = false), and the GROK_CONFIG overlay drops both. So a grok lease
# worktree gets its own .grok/config.toml (_grok_lease_config, written at
# provisioning and never merged; GRK-06 and SELF-25). invoke_grok has no
# worktree of its own and keeps them loaded: dontAsk denies MCP tools because
# no rule allows MCPTool, and --no-subagents drops plugin agents. And grok
# injects the `env` block of ~/.claude/settings.json into its tool shell; the
# lease lane keeps that block out with a GROK_CONFIG overlay
# (_grok_shell_policy), so the tool shell keeps only the names the lease
# boundary passes. invoke_grok runs from the lead's own shell and passes the
# lead's environment, like the other invoke_* helpers.
#
# Permissions: --permission-mode dontAsk with explicit allow rules (anything
# not allowed is denied, MCP tools included) and the deny set _GROK_DENY
# (opencode's D-033 set in grok's rule syntax). A denied call goes back to the
# model as a failed tool call and the run still ends end_turn with exit 0
# (GRK-08), so the extractor adds a note naming the denied commands. A deny
# rule matches a command's prefix or its whole text as a glob, so a push
# inside `sh ./script.sh` is not matched: the no-push git config _adapter_env
# sets stays the push guard (GRK-09).
#
# Classes: edit (builder, tester, documenter) allows Read, Grep, Edit, Write
# and Bash under --sandbox workspace, which lets the process write only the
# working directory, ~/.grok and the temp dirs (GRK-10: git status, diff and
# log work in a lease worktree; `git add` and commits fail when the lead's .git
# is outside the temp dirs, and builders commit nothing). read (reviewer,
# analyst, and an unnamed run) allows Read and Grep under --sandbox read-only,
# so its shell runs only grok's built-in read-only commands.
#
# Completion: --output-format streaming-json, one event per line, `end` last
# with stopReason. _grok_extract_text keeps the last model response (a
# response ends at its `usage` event) and adds a note when the run stopped
# short of end_turn or a call was denied. A turn-cap stop exits 1 with a
# max_turns_reached event and end.stopReason "cancelled" (GRK-07): invoke_grok
# fails it without a retry, and the lease lane routes it as report missing,
# like the claude lane's error_max_turns.
#
# Auth: a cached `grok login` (auth.json under $GROK_HOME, default ~/.grok,
# refreshed by grok itself; GRK-11 runs two refreshes in parallel) or
# XAI_API_KEY. Signed out, -p fails at once with "Not signed in" (rc 1, no
# model call), which _grok_classify reads as a deterministic auth failure.
#
# Failure taxonomy (KTD-9): _classify_invoke_failure, with grok's own shapes
# read first (_grok_classify: max turns, quota, signed out).

# The values every grok run carries (invoke_grok, the lease lane's argv).
_GROK_ENV=(GROK_DISABLE_AUTOUPDATER=1 GROK_TELEMETRY_ENABLED=0 GROK_MEMORY=0 GROK_FOLDER_TRUST=0
           GROK_CLAUDE_SKILLS_ENABLED=0 GROK_CLAUDE_RULES_ENABLED=0 GROK_CLAUDE_AGENTS_ENABLED=0
           GROK_CLAUDE_MCPS_ENABLED=0 GROK_CLAUDE_HOOKS_ENABLED=0
           GROK_CURSOR_SKILLS_ENABLED=0 GROK_CURSOR_RULES_ENABLED=0 GROK_CURSOR_AGENTS_ENABLED=0
           GROK_CURSOR_MCPS_ENABLED=0 GROK_CURSOR_HOOKS_ENABLED=0)
# The deny rules (D-033's set, as opencode carries it in OPENCODE_PERMISSION).
_GROK_DENY=("Bash(git push*)" "Bash(git -c * push*)" "Bash(git -C * push*)"
            "Bash(rm -rf*)" "Bash(rm -fr*)" "Bash(rm -Rf*)" "Bash(rm -fR*)" "Bash(rm -r *)" "Bash(rm -R *)"
            "Bash(sudo*)" "Bash(command sudo*)" "Bash(doas *)")
# The turn cap, as the claude lane's _CLAUDE_MAX_TURNS.
_GROK_MAX_TURNS=200
# The names _adapter_env sets beyond TRIFORGE_ENV_BASE that a lease worker's
# tool shell must keep: NO_COLOR, the worker marker and the no-push git config.
# A fixed name _adapter_env gains joins this list (GRK-02 and GRK-09 check it).
_GROK_SHELL_KEEP="NO_COLOR TRIFORGE_LEASE_WORKER GIT_CONFIG_*"

# _grok_effort <roster effort> — the --effort value grok-4.7 takes: low,
# medium, high and xhigh as they are, max as xhigh, nothing for no effort
# (grok's default, high). Any other value prints nothing and a warning: the
# run keeps the default rather than pass a level grok rejects.
_grok_effort() {
  case "${1:-}" in
    "") ;;
    low|medium|high|xhigh) printf '%s\n' "$1" ;;
    max) printf 'xhigh\n' ;;
    *) echo "grok: effort '${1}' is not a level grok-4.7 takes (low, medium, high, xhigh) — running at its default" >&2 ;;
  esac
}

# _grok_class <role> — the permission class of a grok run in <role>: edit for
# a builder, tester or documenter, read for anything else (invoke_grok's
# GROK_ROLE mapping; the lease lane reads it from the lease's role).
_grok_class() {
  case "${1:-}" in
    builder|tester|documenter) echo edit ;;
    *) echo read ;;
  esac
}

# _grok_shell_policy — the GROK_CONFIG overlay a lease worker runs with: the
# tool shell inherits what grok was started with (the env -i allowlist already
# filtered it) and keeps only TRIFORGE_ENV_BASE and _GROK_SHELL_KEEP, which
# drops the ~/.claude/settings.json env block grok injects (GRK-09 fails when a
# name of it gets through); login-shell capture is off, so a profile cannot add
# names back. The overlay accepts these shell_environment_policy fields.
_grok_shell_policy() {
  GSP_KEEP="${TRIFORGE_ENV_BASE} ${_GROK_SHELL_KEEP}" python3 -c '
import json, os
keep = os.environ["GSP_KEEP"].split()
print(json.dumps({"shell_environment_policy": {"inherit": "all", "ignore_default_excludes": True, "exclude": [], "include_only": keep},
                  "toolset": {"bash": {"login_shell_capture": False}}}, separators=(",", ":")))
'
}

# _grok_argv <edit|read> <model> <effort> [lease] — set _GROK_ARGV to a grok
# run's command line up to the prompt: env with _GROK_ENV (and, for a lease
# worker, the _grok_shell_policy overlay), then grok with the model pin,
# --effort when set, streaming-json, dontAsk, no subagents, no web search, the
# turn cap, the class's sandbox and allow rules, the deny set, and -p last.
# The one composer: invoke_grok and _lease_lane_argv (scripts/lib/lease-wait.sh)
# both call it, and the probe rows read it through _lease_lane_argv.
_grok_argv() {
  local CLASS=$1 MODEL=$2 EFFORT="" POLICY="" R
  EFFORT=$(_grok_effort "${3:-}")
  _GROK_ARGV=(env "${_GROK_ENV[@]}")
  if [ "${4:-}" = lease ]; then
    POLICY=$(_grok_shell_policy) || return 1
    _GROK_ARGV+=("GROK_CONFIG=${POLICY}")
  fi
  _GROK_ARGV+=(grok --model "$MODEL")
  if [ -n "$EFFORT" ]; then _GROK_ARGV+=(--effort "$EFFORT"); fi
  _GROK_ARGV+=(--output-format streaming-json --permission-mode dontAsk --no-subagents --disable-web-search --max-turns "$_GROK_MAX_TURNS")
  if [ "$CLASS" = edit ]; then
    _GROK_ARGV+=(--sandbox workspace --allow Read --allow Grep --allow Edit --allow Write --allow Bash)
  else
    _GROK_ARGV+=(--sandbox read-only --allow Read --allow Grep)
  fi
  for R in "${_GROK_DENY[@]}"; do _GROK_ARGV+=(--deny "$R"); done
  _GROK_ARGV+=(-p)
}

# _grok_lease_config <worktree> — the .grok/config.toml a grok lease worktree
# runs with, the one place grok reads per project that reaches plugins and MCP
# servers (GRK-06; the env switches and the GROK_CONFIG overlay do not, and a
# session starts the ~/.claude.json servers that `grok inspect` reports off):
#   [plugins] disabled  every plugin `grok inspect --json` finds from the
#                       worktree under _GROK_ENV, plus every Claude Code plugin
#                       ~/.claude/plugins/installed_plugins.json names (so the
#                       list survives an inspect that fails): none of their
#                       skills, commands, hooks, MCP servers or agents load.
#                       Grok matches names; it has no wildcard
#   [mcp_servers."<n>"] enabled = false for every server inspect lists that
#                       grok's own config.toml files do not define, plus the
#                       ~/.claude.json mcpServers: a project entry shadows the
#                       server by name, so none starts
# A project's own .grok/config.toml gets these appended, unless it already
# declares plugins (then it stays as it is, with a warning: one more table
# would make it invalid) or MCP servers (then no server is shadowed). A .grok
# or config.toml that is a symlink, or a .grok resolving outside the worktree,
# is never written through. Grok's own skills, .agents/skills included, are
# not plugins and stay. _lease_provision records the file as provisioned, so
# the snapshot never carries it (KTD9).
_grok_lease_config() {
  local WT=$1 INSPECT=""
  if command -v grok >/dev/null 2>&1; then
    INSPECT=$(cd "$WT" && _run_with_timeout 30 "${_HOST_SCRUB[@]}" "${_GROK_ENV[@]}" grok inspect --json < /dev/null 2>/dev/null) || INSPECT=""
  fi
  printf '%s' "$INSPECT" | GLC_WT="$WT" python3 -c '
import json, os, re, sys
wt = os.environ["GLC_WT"]
plugins, servers = set(), set()
try:
    d = json.loads(sys.stdin.read() or "{}")
except ValueError:
    d = {}
if not isinstance(d, dict):
    d = {}
for p in d.get("plugins") or []:
    if isinstance(p, dict) and isinstance(p.get("name"), str) and p["name"]:
        plugins.add(p["name"])
for m in d.get("mcpServers") or []:
    if isinstance(m, dict) and isinstance(m.get("name"), str) and m["name"] and ".grok/config.toml" not in json.dumps(m.get("source")):
        servers.add(m["name"])
for path, key, names in (("~/.claude/plugins/installed_plugins.json", "plugins", plugins), ("~/.claude.json", "mcpServers", servers)):
    try:
        names.update(n for n in (str(k).split("@", 1)[0] for k in (json.load(open(os.path.expanduser(path), encoding="utf-8")).get(key) or {})) if n)
    except Exception:
        pass
gdir, real = os.path.join(wt, ".grok"), os.path.realpath(wt)
cfg = os.path.join(gdir, "config.toml")
if os.path.islink(gdir) or (os.path.lexists(gdir) and not os.path.isdir(gdir)) or not os.path.realpath(gdir).startswith(real + os.sep) \
        or os.path.islink(cfg) or (os.path.lexists(cfg) and not os.path.isfile(cfg)):
    print("lease: WARNING %s is a symlink or not a plain directory and file inside the worktree: not written, so Claude Code plugins and MCP servers load for the grok worker (GRK-06)" % cfg)
    sys.exit(0)
text = open(cfg, encoding="utf-8", errors="replace").read() if os.path.lexists(cfg) else ""
def declares(key):
    return re.search(r"(?m)^\s*(\[{1,2}\s*[\"\x27]?%s[\"\x27]?\s*[\].]|[\"\x27]?%s[\"\x27]?\s*[.=])" % (key, key), text)
if declares("plugins"):
    print("lease: WARNING %s already declares plugins: left as it is, so Claude Code plugins and MCP servers may load for the grok worker (GRK-06)" % cfg)
    sys.exit(0)
block = ("# Agent Triforge: this lease worktree only, never merged. No plugin and no MCP server outside grok loads for the grok worker (GRK-06).\n"
         "[plugins]\ndisabled = [" + ", ".join(json.dumps(n) for n in sorted(plugins)) + "]\n")
if declares("mcp_servers"):
    if servers:
        print("lease: WARNING %s already declares MCP servers: none shadowed, so %s may start for the grok worker (GRK-06)" % (cfg, ", ".join(sorted(servers))))
else:
    block += "".join("\n[mcp_servers.%s]\ncommand = \"false\"\nenabled = false\n" % json.dumps(n) for n in sorted(servers))
if text:
    with open(cfg, "a", encoding="utf-8") as f:
        f.write(("" if text.endswith("\n") else "\n") + "\n" + block)
else:
    os.makedirs(gdir, exist_ok=True)
    with open(cfg, "w", encoding="utf-8") as f:
        f.write(block)
' >&2 || echo "lease: WARNING could not write ${WT}/.grok/config.toml (Claude Code plugins and MCP servers load for the grok worker, GRK-06)" >&2
  return 0
}

# invoke_grok <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
# The class comes from GROK_ROLE (dispatch_role sets it from the roster role),
# else from the agent name: *review* and *analy* read, *build*, *test* and
# *doc* edit, anything else read. The grok-agents/<agent-name>.md brief, when
# one exists, is prefixed onto the prompt (grok's --agent takes a profile, not
# a role brief).
invoke_grok() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/grok_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${GROK_EFFORT:-}}
  local MODEL="${GROK_MODEL:-grok-4.7}"
  local CLASS="" MODE="raw" EXIT_CODE=0 STOP="" BODY="" AVAILABLE=""
  local RAW="${OUTPUT_FILE}.raw"
  local ERR="${OUTPUT_FILE}.err"

  INVOKE_FAILURE_CLASS="none"
  _INVOKE_FAILURE_REASON=""

  # Deterministic preflight (KTD-9): a missing binary never succeeds on retry.
  if ! command -v grok >/dev/null 2>&1; then
    echo "invoke_grok: ERROR \`grok\` (Grok Build) not found on PATH — cannot invoke agent '${AGENT_NAME}'. Fix: $(cli_install_fix grok 2>/dev/null || echo 'install Grok Build'). No retry (deterministic)." >&2
    # The guidance goes to OUTPUT_FILE too: a caller that only reads the file
    # must not mistake an empty file for "no findings".
    echo "invoke_grok: grok CLI not on PATH — $(cli_install_fix grok 2>/dev/null || echo 'install Grok Build')" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="binary-missing"
    return 127
  fi

  case "${GROK_ROLE:-}" in
    builder|tester|documenter|reviewer|analyst) CLASS=$(_grok_class "$GROK_ROLE") ;;
    *)
      case "$AGENT_NAME" in
        *review*|*analy*)    CLASS=read ;;
        *build*|*test*|*doc*) CLASS=edit ;;
        *)                   CLASS=read ;;
      esac
      ;;
  esac

  local FULL_PROMPT="$PROMPT"
  if [ -n "$AGENT_NAME" ] && [ -f "${_TRIFORGE_PLUGIN_ROOT}/grok-agents/${AGENT_NAME}.md" ]; then
    BODY=$(_brief_body "${_TRIFORGE_PLUGIN_ROOT}/grok-agents/${AGENT_NAME}.md")
    FULL_PROMPT="${BODY}

${PROMPT}"
    MODE="injection"
  elif [ -n "$AGENT_NAME" ]; then
    AVAILABLE=$(_list_plugin_briefs grok-agents | paste -sd, - 2>/dev/null || echo "")
    echo "invoke_grok: WARNING agent '${AGENT_NAME}' not found in plugin grok-agents/; running the raw prompt (no role brief applied). Available briefs: ${AVAILABLE:-<none>}" >&2
  fi

  _grok_argv "$CLASS" "$MODEL" "$EFFORT" || return 1
  echo "invoke_grok: agent=${AGENT_NAME:-<none>} mode=${MODE} class=${CLASS} model=${MODEL} effort=${EFFORT:-default}" >&2

  # stdout -> RAW (the event stream), stderr -> ERR (grok's own messages).
  _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${_GROK_ARGV[@]}" "$FULL_PROMPT" > "$RAW" 2>"$ERR" || EXIT_CODE=$?

  # A clean exit is complete only when the stream ended with end_turn: any
  # other stop (refusal, max_tokens, cancelled) fails here, deterministically.
  if [ "$EXIT_CODE" -eq 0 ]; then
    STOP=$(_grok_stop "$RAW")
    case "$STOP" in
      end_turn) : ;;
      *) EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="stopped:${STOP}" ;;
    esac
  else
    _grok_classify "$EXIT_CODE" "$RAW" "$ERR"
  fi

  if [ "$INVOKE_FAILURE_CLASS" = retryable ]; then
    # Single retry: the raw prompt with the same command line (class, sandbox
    # and rules kept; only the brief is shed, as the sibling helpers do).
    echo "invoke_grok: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable), retrying once with the raw prompt" >&2
    EXIT_CODE=0
    _run_with_timeout "${TIMEOUT}" "${_HOST_SCRUB[@]}" "${_GROK_ARGV[@]}" "$PROMPT" > "$RAW" 2>"$ERR" || EXIT_CODE=$?
    if [ "$EXIT_CODE" -eq 0 ]; then
      INVOKE_FAILURE_CLASS="none"
      STOP=$(_grok_stop "$RAW")
      case "$STOP" in
        end_turn) : ;;
        *) EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="stopped:${STOP}" ;;
      esac
    else
      _grok_classify "$EXIT_CODE" "$RAW" "$ERR"
      echo "invoke_grok: agent=${AGENT_NAME} retry also failed, exit=${EXIT_CODE} class=${INVOKE_FAILURE_CLASS}" >&2
    fi
  fi

  if [ "$EXIT_CODE" -ne 0 ]; then
    case "$INVOKE_FAILURE_CLASS:$_INVOKE_FAILURE_REASON" in
      deterministic:auth)
        echo "invoke_grok: agent=${AGENT_NAME} exit=${EXIT_CODE} auth failure — grok is not signed in. Fix: run \`grok login\` (\`grok login --device-code\` without a browser), or set XAI_API_KEY. No retry (deterministic)." >&2 ;;
      deterministic:quota)
        echo "invoke_grok: agent=${AGENT_NAME} exit=${EXIT_CODE} the Grok Build usage limit is reached — wait for it to reset or raise the plan; until then, roster_write_member grok false \"\" makes every role chain fall back past grok. No retry (deterministic)." >&2 ;;
      deterministic:max-turns)
        echo "invoke_grok: agent=${AGENT_NAME} exit=${EXIT_CODE} stopped at the turn cap (--max-turns ${_GROK_MAX_TURNS}) before a final answer. No retry (deterministic)." >&2 ;;
      deterministic:stopped:*)
        echo "invoke_grok: agent=${AGENT_NAME} the run ended with stopReason=${_INVOKE_FAILURE_REASON#stopped:}, not end_turn — the answer is incomplete. No retry (deterministic)." >&2 ;;
      timeout:*)
        echo "invoke_grok: agent=${AGENT_NAME} timed out after ${TIMEOUT}s (exit=${EXIT_CODE}). Requeue policy belongs to the caller (lease layer), not this helper." >&2 ;;
      *)
        echo "invoke_grok: agent=${AGENT_NAME} exit=${EXIT_CODE} failed (class=${INVOKE_FAILURE_CLASS}${_INVOKE_FAILURE_REASON:+, ${_INVOKE_FAILURE_REASON}})." >&2 ;;
    esac
    # Whatever the run produced goes to OUTPUT_FILE, never an empty file: the
    # partial answer with its note when there is one, else the raw streams.
    if ! _grok_extract_text "$RAW" "$OUTPUT_FILE"; then
      cat "$ERR" "$RAW" > "$OUTPUT_FILE" 2>/dev/null || true
    fi
    if [ "$_INVOKE_FAILURE_REASON" = auth ]; then
      echo "invoke_grok: grok is not signed in — run: grok login (or set XAI_API_KEY)" >> "$OUTPUT_FILE" 2>/dev/null || true
    fi
    rm -f "$RAW" "$ERR"
    return "$EXIT_CODE"
  fi

  if ! _grok_extract_text "$RAW" "$OUTPUT_FILE"; then
    echo "invoke_grok: WARNING could not extract the answer from grok's stream — preserving the raw stream in ${OUTPUT_FILE}" >&2
    cat "$RAW" "$ERR" > "$OUTPUT_FILE" 2>/dev/null || cp "$RAW" "$OUTPUT_FILE" 2>/dev/null || true
  fi
  rm -f "$RAW" "$ERR"
  return 0
}

# _grok_extract_text <stream-file> <output-file> — the final answer of a grok
# streaming-json capture into <output-file>: the text of the last model
# response, then a note line for each thing the lead must see: denied tool
# calls (with their commands), a turn-cap stop, an end other than end_turn.
# Also reads grok's one-object json format. Non-JSON lines (stderr mixed into
# a lease capture) are skipped. Exits nonzero, writing nothing, when there is
# no answer text, so the caller keeps the raw stream. Shared by invoke_grok and
# the lease lane (_lease_extract_stream), where the typed `Status:` report is
# parsed from the result.
_grok_extract_text() {
  G_RAW="$1" G_OUT="$2" python3 -c '
import json, os, sys
responses, cur, calls, denied = [], [], {}, []
stop, capped = None, False
for line in open(os.environ["G_RAW"], encoding="utf-8", errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if not isinstance(e, dict):
        continue
    t = e.get("type")
    if t == "text" and isinstance(e.get("data"), str):
        cur.append(e["data"])
    elif t == "usage":
        if "".join(cur).strip():
            responses.append("".join(cur))
        cur = []
    elif t == "tool_call":
        ri = e.get("rawInput") if isinstance(e.get("rawInput"), dict) else {}
        calls[e.get("toolCallId")] = str(ri.get("command") or ri.get("path") or e.get("title") or "tool call")
    elif t == "tool_call_update" and e.get("status") == "failed":
        if "Denied by permission policy" in json.dumps(e.get("content")):
            denied.append(calls.get(e.get("toolCallId"), "tool call"))
    elif t == "max_turns_reached":
        capped = True
    elif t == "end":
        stop = e.get("stopReason")
    elif t is None and isinstance(e.get("text"), str) and "stopReason" in e:
        responses.append(e["text"])
        stop = e.get("stopReason")
if "".join(cur).strip():
    responses.append("".join(cur))
final = responses[-1].strip() if responses else ""
if not final:
    sys.stderr.write("no answer text in the grok stream\n")
    sys.exit(3)
notes = []
if denied:
    notes.append("[grok] %d tool call(s) denied by the permission rules: %s" % (len(denied), "; ".join(d.replace("\n", " ")[:80] for d in denied[:5])))
if capped:
    notes.append("[grok] the run hit its turn cap (max_turns_reached) before a final answer: the text above is partial")
elif stop not in (None, "end_turn"):
    notes.append("[grok] the run ended with stopReason=%s, not end_turn: the text above may be incomplete" % stop)
with open(os.environ["G_OUT"], "w", encoding="utf-8") as f:
    f.write(final + "\n" + ("\n" + "\n".join(notes) + "\n" if notes else ""))
' 2>/dev/null
}

# _grok_stop <stream-file> — how a grok run ended: max-turns when it hit the
# turn cap, else end.stopReason (end_turn, max_tokens, refusal, cancelled, ...),
# error for an error event with no end, none when the stream has neither.
_grok_stop() {
  G_RAW="$1" python3 -c '
import json, os
stop, capped, err = None, False, False
try:
    lines = open(os.environ["G_RAW"], encoding="utf-8", errors="replace").read().splitlines()
except OSError:
    lines = []
for line in lines:
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        e = json.loads(line)
    except ValueError:
        continue
    if not isinstance(e, dict):
        continue
    t = e.get("type")
    if t == "max_turns_reached":
        capped = True
    elif t == "end":
        stop = str(e.get("stopReason"))
    elif t == "error":
        err = True
    elif t is None and "stopReason" in e:
        stop = str(e.get("stopReason"))
print("max-turns" if capped else (stop or ("error" if err else "none")))
' 2>/dev/null || echo none
}

# _grok_classify <rc> <file>... — set INVOKE_FAILURE_CLASS and
# _INVOKE_FAILURE_REASON for a failed grok run: a turn-cap stop
# (max_turns_reached), quota and signed out are deterministic; anything else is
# _classify_invoke_failure's call (timeout, retryable). Only grok's own words
# are read — error events and the non-JSON (stderr) lines — never tool output,
# so a test that prints "401" is not an auth failure.
_grok_classify() {
  local RC=$1 WHY=""
  shift
  WHY=$(python3 -c '
import json, re, sys
capped, said = False, []
for path in sys.argv[1:]:
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        continue
    for line in lines:
        s = line.strip()
        if not s:
            continue
        if s.startswith("{"):
            try:
                e = json.loads(s)
            except ValueError:
                said.append(s)
                continue
            if isinstance(e, dict) and e.get("type") == "max_turns_reached":
                capped = True
            elif isinstance(e, dict) and e.get("type") == "error":
                said.append(str(e.get("message", "")))
        else:
            said.append(s)
text = "\n".join(said)
if capped or re.search(r"max turns reached", text, re.I):
    print("max-turns")
elif re.search(r"usage limit|quota (exceeded|exhausted|reached)|reached your (monthly|daily|usage)|billing cycle|purchase extra usage|insufficient (credit|balance|quota)", text, re.I):
    print("quota")
elif re.search(r"not signed in|grok login|not logged in|unauthorized|\b401\b|invalid api key|authentication (failed|required|expired)", text, re.I):
    print("auth")
' "$@" 2>/dev/null) || WHY=""
  case "$WHY" in
    max-turns|quota|auth)
      INVOKE_FAILURE_CLASS="deterministic"
      _INVOKE_FAILURE_REASON=$WHY
      ;;
    *)
      _classify_invoke_failure "$RC"
      ;;
  esac
}
