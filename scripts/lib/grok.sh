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
# appends the prompt (like kimi). The probe rows GRK-01..GRK-12 and SELF-06g in
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
# (codex:review among them); a session starts the ~/.claude.json MCP servers
# that `grok inspect` reports off, and a project's .mcp.json servers. Only
# config-file keys turn these off (`[plugins] disabled`, a project
# `[mcp_servers.<name>]` with enabled = false), and the GROK_CONFIG overlay
# drops both. So every grok run starts from a worktree with its own
# .grok/config.toml (_grok_lease_config, never merged; GRK-06 and SELF-25): a
# lease in its lease worktree, invoke_grok in a scratch checkout of HEAD
# (_grok_scratch_wt), removed after the run. And grok injects the `env` block
# of ~/.claude/settings.json into its tool shell. Every run keeps that block
# out with a GROK_CONFIG overlay (_grok_shell_policy) and starts under the
# lease boundary's env -i allowlist (_adapter_env grok, invoke_grok included),
# so the tool shell keeps only the names the boundary passes.
#
# What the project supplies. Folder trust off ungates the project's own
# surfaces too (10-hooks.md): a .grok/hooks/ hook, a .grok/lsp.json server and
# an MCP server the project's .grok/config.toml declares each ran on a
# session/new with no prompt (measured on 1.0.34), and grok also reads project
# plugins from .grok/plugins/ and .claude/plugins/. A read-class run (a
# reviewer or analyst lease, and every invoke_grok run) never starts where the
# worktree holds one (_grok_project_guard), nor where `grok inspect` reports
# an active hook, LSP server or plugin from inside it (_grok_lease_config).
# The rest stay inert in the read class, each measured with a marker: Claude
# Code and Cursor project hooks and Cursor MCP servers are off with their
# GROK_CLAUDE_HOOKS / GROK_CURSOR_* switches; a .mcp.json server is shadowed
# like any other; grok reads no hooks from a project config.toml; agent
# definitions run only as subagents (--no-subagents); skills are prompt text;
# and a .grok/sandbox.toml can't redefine the built-in read-only profile. The
# edit class (a builder lease) keeps every project surface: it has a full
# shell in its worktree already.
#
# What the user tier supplies. Grok starts the user's own hooks
# (~/.grok/hooks/*.json, the [hooks] of its config layers), LSP servers
# (~/.grok/lsp.json), config-layer commands (an auth provider,
# ui.notifications.hooks) and MCP servers in every session, before any
# permission applies, and has no switch that turns a user hook or LSP server
# off for one project. The user tier belongs to the user, and the untrusted
# input is the project under review, so a read-class run lets these run, as
# they do whenever the user runs grok, and names each with its file in one
# NOTE line on stderr (_grok_lease_config; each surface measured alone on
# 1.0.34 from a scratch GROK_HOME): on lease_create's stderr, in the builder
# log at each dispatch of a reviewer or analyst lease (the check runs again
# there), and on invoke_grok's stderr. The user's MCP servers are still
# shadowed by name like any other; one in a requirements layer outranks the
# shadow and is named instead, and MCP tool calls are denied either way. A
# user plugin is disabled by name like a Claude Code one. A user config layer
# that does not parse is refused: rc 69 through invoke_grok, no lease at
# lease_create, rc 94 at a dispatch. A hook another worker plants under
# ~/.grok runs too (named in the NOTE), as does what neither inspect nor the
# TOML layers show (a ~/.grok/AGENTS.md, a replaced ~/.grok/bin/grok): that
# is AGENTS.md's same-user residual, detected rather than prevented. at-setup
# asks grok_read_isolation_check before it offers grok a read role. The edit
# class keeps the user's surfaces, but its sandbox profile
# (_GROK_EDIT_PROFILE) leaves a builder no way to plant one for a later run
# (_GROK_HOME_DENY).
#
# Roles. The registry gives grok builder, reviewer and analyst (role_limit),
# so a tester or documenter chain naming grok fails at roster load. invoke_grok
# runs the read class only and refuses the edit class (rc 69): outside a lease
# grok would edit the caller's checkout, where no provisioned config keeps the
# plugins and servers off. A grok builder runs through lease_dispatch.
#
# Permissions: --permission-mode dontAsk with explicit allow rules and the
# deny set _GROK_DENY (opencode's D-033 set in grok's rule syntax, plus every
# MCP tool). dontAsk alone is not a closed allowlist: grok imports
# permissions.allow from ~/.claude/settings*.json and the project's
# .claude/settings*.json (GROK_FOLDER_TRUST=0 lets the project's files load
# too), and from its own config.toml files. Deny always wins over an allow
# from any source, so the read class also denies Edit, Write and Bash
# (_GROK_READ_DENY), and both classes deny MCP tools in grok's two spellings
# (GRK-06 requires them where permission files load). A denied call goes back
# to the model as a failed tool call and the run still ends end_turn with
# exit 0 (GRK-08), so the extractor adds a note naming the denied commands. A
# deny rule matches a command's prefix or its whole text as a glob, so a push
# inside `sh ./script.sh` is not matched: the no-push git config _adapter_env
# sets stays the push guard (GRK-09).
#
# Classes: edit (a builder lease; tester and documenter map here too, though
# role_limit keeps them off grok) allows Read, Grep, Edit, Write and Bash
# under --sandbox triforge-edit (_GROK_EDIT_PROFILE, the worktree's
# .grok/sandbox.toml): grok's workspace profile, which lets the process write
# only the working directory, ~/.grok and the temp dirs, with the
# _GROK_HOME_DENY paths under ~/.grok closed to it (GRK-12 measures the
# denies; GRK-10: git status, diff and log work in a lease worktree; `git add`
# and commits fail when the lead's .git is outside the temp dirs, and builders
# commit nothing). read (reviewer,
# analyst, and an unnamed run) allows Read and Grep under --sandbox read-only
# and denies Edit, Write and Bash, so it has no shell at all, grok's built-in
# read-only commands included.
#
# Completion: --output-format streaming-json, one event per line, `end` last
# with stopReason. _grok_extract_text keeps the last model response (a
# response ends at its `usage` event) and adds a note when the run stopped
# short of end_turn or a call was denied. A turn-cap stop exits 1 with a
# max_turns_reached event and end.stopReason "cancelled" (GRK-07): invoke_grok
# fails it without a retry. invoke_grok fails any other end than end_turn too,
# and an end_turn with no answer text is report missing (rc 80). The lease
# lane takes a typed report only from a run that ended end_turn
# (_grok_lease_text): a turn-cap stop, another stopReason or no end event
# routes as report missing, like the claude lane's error_max_turns.
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
# The deny rules every run carries: D-033's set, as opencode carries it in
# OPENCODE_PERMISSION, then every MCP tool in grok's native spelling and in the
# Claude Code spelling grok rewrites onto the same matcher
# (22-permissions-and-safety.md, "MCP Rules").
_GROK_DENY=("Bash(git push*)" "Bash(git -c * push*)" "Bash(git -C * push*)"
            "Bash(rm -rf*)" "Bash(rm -fr*)" "Bash(rm -Rf*)" "Bash(rm -fR*)" "Bash(rm -r *)" "Bash(rm -R *)"
            "Bash(sudo*)" "Bash(command sudo*)" "Bash(doas *)"
            "MCPTool(*)" "mcp__*")
# The read class's own denies: every tool that writes (Edit, and Write, its
# alias) and the shell. Deny beats any imported allow rule.
_GROK_READ_DENY=(Edit Write Bash)
# The turn cap, as the claude lane's _CLAUDE_MAX_TURNS.
_GROK_MAX_TURNS=200
# The edit class's sandbox profile (_grok_sandbox_profile writes it into the
# worktree's .grok/sandbox.toml): grok's workspace profile plus a deny on each
# _GROK_HOME_DENY entry under $GROK_HOME. Workspace alone lets the process
# write all of $GROK_HOME except config.toml, managed_config.toml,
# requirements.toml, sandbox.toml, trusted_folders.toml, hooks/ and
# hooks-paths, which grok 1.0.34 already keeps unwritable (measured). The
# entries are what a later grok run, a reviewer's included, loads as code or
# instructions: LSP servers, the global rules, plugins and their sources,
# skills, agents, personas, commands, workflow scripts, the grok binary
# (bin/, downloads/), the ripgrep its Grep tool runs (vendor/), the bundled
# skills, memory, and the disabled-hooks list. A deny is kernel-enforced for
# read and write, path absent or not; grok reads its config layers again after
# the sandbox applies, so they can't be denied (a read-denied
# managed_config.toml stops grok at start, measured), and auth.json, sessions/
# and logs/ stay writable for the login refresh and the transcript.
_GROK_EDIT_PROFILE=triforge-edit
_GROK_HOME_DENY=(lsp.json AGENTS.md disabled-hooks plugins installed-plugins marketplace-cache skills agents personas
                 commands workflows rules bin downloads vendor bundled memory)
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

# _grok_shell_policy — the GROK_CONFIG overlay every grok run carries: the
# tool shell inherits what grok was started with (the env -i allowlist already
# filtered it) and keeps only TRIFORGE_ENV_BASE and _GROK_SHELL_KEEP, which
# drops the ~/.claude/settings.json env block grok injects (GRK-09 fails when a
# name of it gets through); login-shell capture is off, so a profile cannot add
# names back. The overlay accepts these shell_environment_policy fields, and
# `grok inspect` names them in its env_overlay layer (GRK-02;
# _grok_lease_config refuses when it reports the overlay ignored).
_grok_shell_policy() {
  GSP_KEEP="${TRIFORGE_ENV_BASE} ${_GROK_SHELL_KEEP}" python3 -c "${_PY_PRELUDE}"'
import json, os
keep = os.environ["GSP_KEEP"].split()
print(json.dumps({"shell_environment_policy": {"inherit": "all", "ignore_default_excludes": True, "exclude": [], "include_only": keep},
                  "toolset": {"bash": {"login_shell_capture": False}}}, separators=(",", ":")))
'
}

# _grok_argv <edit|read> <model> <effort> — set _GROK_ARGV to a grok run's
# command line up to the prompt: env with _GROK_ENV and the _grok_shell_policy
# overlay, then grok with the model pin, --effort when set, streaming-json,
# dontAsk, no subagents, no web search, the turn cap, the class's sandbox,
# allow rules and (read) denies, the deny set, and -p last. Any class but edit
# is read. The one composer: invoke_grok and _lease_lane_argv
# (scripts/lib/lease-wait.sh) both call it, and the probe rows read it through
# _lease_lane_argv.
_grok_argv() {
  local CLASS=$1 MODEL=$2 EFFORT="" POLICY="" R
  EFFORT=$(_grok_effort "${3:-}")
  POLICY=$(_grok_shell_policy) || return 1
  _GROK_ARGV=(env "${_GROK_ENV[@]}" "GROK_CONFIG=${POLICY}" grok --model "$MODEL")
  if [ -n "$EFFORT" ]; then _GROK_ARGV+=(--effort "$EFFORT"); fi
  _GROK_ARGV+=(--output-format streaming-json --permission-mode dontAsk --no-subagents --disable-web-search --max-turns "$_GROK_MAX_TURNS")
  if [ "$CLASS" = edit ]; then
    _GROK_ARGV+=(--sandbox "$_GROK_EDIT_PROFILE" --allow Read --allow Grep --allow Edit --allow Write --allow Bash)
  else
    _GROK_ARGV+=(--sandbox read-only --allow Read --allow Grep)
    for R in "${_GROK_READ_DENY[@]}"; do _GROK_ARGV+=(--deny "$R"); done
  fi
  for R in "${_GROK_DENY[@]}"; do _GROK_ARGV+=(--deny "$R"); done
  _GROK_ARGV+=(-p)
}

# The tail of every read-class refusal over what a project supplies
# (_grok_project_guard, _grok_lease_config).
_GROK_PROJECT_REFUSAL="A grok reviewer or analyst runs with folder trust off, so grok would start it before any permission applies: no read-class grok run starts here (R23). Fix: remove it from the project, or route the role to another roster member"

# _grok_project_guard <dir> — nothing and 0 when <dir> (the worktree root
# grok starts in) holds none of the project files from which grok starts code
# before any permission applies; else the file and the cause on stdout and 1.
# With folder trust off grok loads them from the project (measured on 1.0.34,
# each with a marker, on a session/new with no prompt):
#   .grok/hooks/        hooks, run as commands from session start
#   .grok/lsp.json      LSP servers, started with the session
#   .grok/config.toml   an MCP server it declares that is not enabled = false:
#                       started with the session (a provisioned shadow can't
#                       take a name the file already holds; the shadows
#                       themselves are disabled, so the dispatch-time check
#                       passes them)
#   .grok/plugins/,     project plugins, whose hooks and MCP and LSP servers
#   .claude/plugins/    grok reads (both are plugin directories to it)
# Fails closed too on a .grok or .grok/config.toml that is a symlink, a
# config.toml that does not parse, and no TOML parser. The read class only:
# _grok_lease_config runs it for a reviewer or analyst lease (at provisioning,
# and again at each dispatch through _lease_lane_argv) and invoke_grok's
# scratch. The edit class keeps them.
_grok_project_guard() {
  GPG_DIR="$1" GPG_TAIL="$_GROK_PROJECT_REFUSAL" python3 -c "${_READ_REGULAR_PY}"'
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None
d = os.environ["GPG_DIR"]
def refuse(rel, why):
    print("%s: %s. %s" % (os.path.join(d, rel), why, os.environ["GPG_TAIL"]))
    sys.exit(1)
for rel in (".grok", ".grok/config.toml"):
    if os.path.islink(os.path.join(d, rel)):
        refuse(rel, "a symlink, which grok would follow")
for rel, why in ((".grok/hooks", "project hooks, which grok runs as commands from session start"),
                 (".grok/lsp.json", "a project LSP server, which grok starts with the session"),
                 (".grok/plugins", "project plugins, whose hooks and MCP and LSP servers grok loads"),
                 (".claude/plugins", "project plugins (grok reads .claude/plugins/ as a plugin directory)")):
    if os.path.lexists(os.path.join(d, rel)):
        refuse(rel, why)
cfg = os.path.join(d, ".grok", "config.toml")
if os.path.lexists(cfg):
    if tomllib is None:
        refuse(".grok/config.toml", "no TOML parser to check it for MCP servers (Python 3.11+ tomllib, or pip install tomli)")
    try:
        t = tomllib.loads(read_regular(cfg).decode("utf-8", "replace"))
    except Exception as e:
        refuse(".grok/config.toml", "not valid TOML (%s)" % (str(e).splitlines() or ["parse error"])[0][:120])
    ms = t.get("mcp_servers")
    if ms is not None and not isinstance(ms, dict):
        refuse(".grok/config.toml", "it declares MCP servers of its own (mcp_servers is not a table)")
    on = sorted(n for n, v in (ms or {}).items() if not (isinstance(v, dict) and v.get("enabled") is False))
    if on:
        refuse(".grok/config.toml", "it declares MCP servers of its own (%s), which grok starts with the session" % ", ".join(on)[:120])
'
}

# _grok_sandbox_profile <worktree> — write <worktree>/.grok/sandbox.toml, the
# edit class's profile (_GROK_EDIT_PROFILE: workspace plus a deny on each
# _GROK_HOME_DENY entry under $GROK_HOME, default ~/.grok, by its real path).
# The file holds that profile alone and replaces whatever the worktree had, a
# project's own profiles included (the run selects this one by name), so a
# builder that rewrote it during one run gets it back for the next.
# _grok_lease_config writes it when it provisions a builder lease, and
# lease_dispatch again before every edit-class run. rc 1, nothing written, the
# reason on stderr: .grok or the file a symlink or not a plain directory and
# file inside the worktree; $GROK_HOME a symlink (grok refuses to sandbox
# one); no TOML parser; the user's own $GROK_HOME/sandbox.toml unparsable or
# defining a profile of the same name (grok runs the user's copy of a name
# both files define).
_grok_sandbox_profile() {
  GSP_WT="$1" GSP_NAME="$_GROK_EDIT_PROFILE" GSP_DENY="${_GROK_HOME_DENY[*]}" python3 -c "${_PY_PRELUDE}"'
import json, os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None
wt, name = os.environ["GSP_WT"], os.environ["GSP_NAME"]
gdir, real = os.path.join(wt, ".grok"), os.path.realpath(wt)
f = os.path.join(gdir, "sandbox.toml")
gh = os.environ.get("GROK_HOME") or os.path.join(os.path.expanduser("~"), ".grok")
user = os.path.join(gh, "sandbox.toml")
def refuse(why):
    print("grok: ERROR %s: %s. A grok builder never runs without its sandbox profile (R23)" % (f, why))
    sys.exit(1)
if os.path.islink(gdir) or (os.path.lexists(gdir) and not os.path.isdir(gdir)) or not os.path.realpath(gdir).startswith(real + os.sep) \
        or os.path.islink(f) or (os.path.lexists(f) and not os.path.isfile(f)):
    refuse("a symlink, or not a plain directory and file inside the worktree, so it is never written through")
if os.path.islink(gh.rstrip(os.sep) or os.sep):
    refuse("GROK_HOME %s is a symlink, and grok refuses a sandbox there" % gh)
if tomllib is None:
    refuse("no TOML parser to check %s (Python 3.11+ tomllib, or pip install tomli)" % user)
if os.path.lexists(user):
    try:
        u = tomllib.loads(open(user, encoding="utf-8", errors="replace").read())
    except Exception as e:
        refuse("the user profile file %s does not parse (%s)" % (user, (str(e).splitlines() or ["parse error"])[0][:120]))
    if isinstance(u.get("profiles"), dict) and name in u["profiles"]:
        refuse("the user profile file %s defines [profiles.%s], which grok would run in place of this one" % (user, name))
deny = [os.path.join(os.path.realpath(gh), n) for n in os.environ["GSP_DENY"].split()]
text = ("# Agent Triforge: this worktree only, never merged. The grok builder sandbox (R23): the workspace profile, with\n"
        "# no read or write of what a later grok run loads from GROK_HOME as code or instructions.\n"
        "[profiles.%s]\nextends = \"workspace\"\ndeny = [%s]\n" % (name, ", ".join(json.dumps(p) for p in deny)))
if tomllib.loads(text)["profiles"][name]["deny"] != deny:
    refuse("the profile does not read back as written")
os.makedirs(gdir, exist_ok=True)
try:
    fd = os.open(f, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o644)
except OSError as e:
    refuse("could not be written without following a link (%s)" % e.strerror)
with os.fdopen(fd, "w", encoding="utf-8") as out:
    out.write(text)
' >&2 || return 1
}

# _grok_lease_config <worktree> [edit|read] [supervised] — the
# .grok/config.toml a grok worker's worktree runs with (a lease worktree, or
# invoke_grok's scratch one, which passes "supervised": its inspect then runs
# under the run supervisor, below), the one place grok reads per project that
# reaches plugins and MCP servers (GRK-06; the env switches and the
# GROK_CONFIG overlay do not, and a session starts the ~/.claude.json servers
# that `grok inspect` reports off):
#   [plugins] disabled  every plugin `grok inspect --json` finds from the
#                       worktree under _GROK_ENV and the overlay, plus every
#                       Claude Code plugin ~/.claude/plugins/installed_plugins.json
#                       names: none of their skills, commands, hooks, MCP
#                       servers or agents load. Grok matches names; it has no
#                       wildcard
#   [mcp_servers."<n>"] enabled = false for every server inspect lists, the
#                       user's ~/.grok/config.toml ones included, plus the
#                       ~/.claude.json mcpServers and the worktree's .mcp.json
#                       ones: a project entry shadows the server by name, so
#                       none starts. A server the project file defines itself
#                       gets no shadow (inspect files it under
#                       ~/.grok/config.toml, and it replaces a user server of
#                       the same name); one it shares with ~/.claude.json,
#                       .mcp.json or a plugin still does, and collides
# The inspect is the evidence: no inspect, no file and no run. A missing
# grok, a failed or timed-out inspect, output that is empty or not a JSON
# object, or one without configSources.layers or the plugin and MCP server
# lists (for the read class, the hook and LSP server lists too) is refused;
# the names read from ~/.claude and .mcp.json only add to a good inspect. A
# project's own .grok/config.toml keeps its lines, and the tables follow them.
# Run again over a file it wrote (a read-class lease runs it again before
# every launch: _lease_lane_argv), it builds its tables anew from a fresh
# inspect and keeps every plugin and server the earlier tables named, since
# inspect no longer lists a server they shadow; tables that no longer parse
# are refused.
# The result is proven with tomllib before it is written: valid TOML,
# plugins.disabled naming every plugin, enabled = false on every shadowed
# server. A project file that declares [plugins], or an MCP server table the
# shadows can't join (an inline mcp_servers table, a collision), fails that
# proof. The read class (the default; a reviewer or analyst) first passes
# _grok_project_guard, and runs no startup code the project supplies:
# refused when inspect reports a project plugin, or a hook, LSP server or
# plugin from inside the worktree (what a grok version loads from a place the
# guard does not know yet). What the user tier starts runs, as in any grok
# session the user starts, and once the file is written one NOTE line on
# stderr names each surface with its file: a hook or LSP server inspect
# reports that is not disabled and comes from anywhere but a plugin these
# tables disable (~/.grok/hooks/, named by its *.json files; a config-layer
# [hooks] table; ~/.grok/lsp.json; an unlisted plugin's), and what a user
# config layer ($GROK_HOME's config.toml, managed_config.toml and
# requirements.toml, /etc/grok's two) sets that inspect does not list (an
# auth-provider command, ui.notifications.hooks, [hooks], MCP servers in a
# requirements layer, which outranks the project file). Fails closed — rc 1,
# nothing written, the file and the reason on stderr, so the caller
# dispatches nothing — on any of the project refusals, a read-class config
# layer that does not parse, no TOML parser, a .grok or config.toml that is
# a symlink or not a plain directory and file inside the worktree, and an
# inspect whose env_overlay layer does not name the GROK_CONFIG overlay's
# sections (grok reports a malformed overlay "set but ignored"; the inspect
# runs with the overlay, so the check costs no extra grok process). Grok's
# own skills, .agents/skills included, are not plugins and stay. The edit
# class (a builder lease) prints no NOTE, then writes its sandbox profile
# (_grok_sandbox_profile); rc 1 when that fails, the config written. A
# supervised inspect whose leftovers its supervisor could not stop is refused
# with rc 80: one of them may still run in <worktree>, which the caller then
# leaves in place.
# _lease_provision records both files as provisioned, so the snapshot never
# carries them (KTD9).
_grok_lease_config() {
  local WT=$1 CLASS=read INSPECT="" POLICY="" GUARD="" IRC=0 TOBIN=""
  if [ "${2:-}" = edit ]; then CLASS=edit; fi
  if [ "$CLASS" = read ] && ! GUARD=$(_grok_project_guard "$WT"); then
    echo "grok: ERROR ${GUARD:-the project check of ${WT} failed to run}" >&2
    return 1
  fi
  POLICY=$(_grok_shell_policy) || return 1
  # timeout --foreground keeps the inspect in the caller's process group, so
  # an interrupt, or a stop of a lease builder's group, that reaches the
  # caller stops it too. "supervised" (invoke_grok's scratch, from the lead's
  # own shell, where no group stop follows) runs it as invoke_grok runs grok:
  # under the run supervisor (_PERSONA_RUN_PY) with a timeout that is not
  # --foreground, so whatever the inspect leaves running in its process group
  # or below it is stopped when it ends, at the deadline too, before the
  # scratch goes (an unresolved stop: refused, rc 80)
  if ! command -v grok >/dev/null 2>&1; then
    IRC=127
  elif ! TOBIN=$(_timeout_tool); then
    IRC=$_RC_NO_TIMEOUT_TOOL
  elif [ "${3:-}" = supervised ]; then
    INSPECT=$(cd "$WT" && "${_HOST_SCRUB[@]}" "${_GROK_ENV[@]}" "GROK_CONFIG=${POLICY}" python3 -c "$_PERSONA_RUN_PY" 5 "$TOBIN" -k 10s 30s grok inspect --json < /dev/null 2>/dev/null) || IRC=$?
    if [ "$IRC" -eq 80 ]; then IRC=unresolved; fi
  else
    INSPECT=$(cd "$WT" && "$TOBIN" --foreground -k 10s 30s "${_HOST_SCRUB[@]}" "${_GROK_ENV[@]}" "GROK_CONFIG=${POLICY}" grok inspect --json < /dev/null 2>/dev/null) || IRC=$?
  fi
  printf '%s' "$INSPECT" | GLC_WT="$WT" GLC_CLASS="$CLASS" GLC_IRC="$IRC" GLC_TAIL="$_GROK_PROJECT_REFUSAL" python3 -c "${_READ_REGULAR_PY}"'
import json, os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        tomllib = None
wt, cls, irc = os.environ["GLC_WT"], os.environ["GLC_CLASS"], os.environ["GLC_IRC"]
gdir, real = os.path.join(wt, ".grok"), os.path.realpath(wt)
cfg = os.path.join(gdir, "config.toml")
def refuse(why):
    print("grok: ERROR %s: %s. Nothing is dispatched to grok from %s: Claude Code plugins or MCP servers from outside grok could load for it (R23, GRK-06)" % (cfg, why, wt))
    sys.exit(1)
def inside(p):
    p = os.path.realpath(str(p)) if p else ""
    return p == real or p.startswith(real + os.sep)
raw = sys.stdin.read()
if irc != "0":
    why = {"127": "could not run: grok is not on PATH", "96": "could not run: neither timeout nor gtimeout is on PATH (brew install coreutils)",
           "unresolved": "left processes its run supervisor could not stop or list (rc 80)"}.get(irc, "failed or timed out (rc %s)" % irc)
    refuse("grok inspect --json %s, so nothing proves which plugins and MCP servers would load" % why)
try:
    d = json.loads(raw)
except ValueError:
    d = None
if not isinstance(d, dict):
    refuse("grok inspect --json gave %s, so nothing proves which plugins and MCP servers would load" % ("no output" if not raw.strip() else "output that is not a JSON object"))
src = d.get("configSources")
lacks = [k for k in ["plugins", "mcpServers"] + (["hooks", "lspServers"] if cls == "read" else []) if not isinstance(d.get(k), list)]
if not (isinstance(src, dict) and isinstance(src.get("layers"), list)):
    lacks.insert(0, "configSources.layers")
if lacks:
    refuse("grok inspect --json lacks %s, so nothing proves which plugins and MCP servers would load" % ", ".join(lacks))
notes = [str(l.get("note") or "") for l in src["layers"] if isinstance(l, dict) and l.get("role") == "env_overlay"]
if not notes or not all(s in " ".join(notes) for s in ("shell_environment_policy", "toolset")):
    refuse("grok inspect reports the GROK_CONFIG overlay %s, so the tool shell would keep the whole environment" % (("as \"%s\"" % "; ".join(notes)) if notes else "absent"))
if os.path.islink(gdir) or (os.path.lexists(gdir) and not os.path.isdir(gdir)) or not os.path.realpath(gdir).startswith(real + os.sep) \
        or os.path.islink(cfg) or (os.path.lexists(cfg) and not os.path.isfile(cfg)):
    refuse("a symlink, or not a plain directory and file inside the worktree, so it is never written through")
if tomllib is None:
    refuse("no TOML parser to prove the file valid (Python 3.11+ tomllib, or pip install tomli)")
text = read_regular(cfg).decode("utf-8", "replace") if os.path.lexists(cfg) else ""
# A file this function wrote before (at provisioning, then at each read-class
# dispatch) ends in its own tables, from the marker line on. They are built
# again, and every plugin and server they named stays named: an inspect run
# over them no longer lists a server they shadow.
MARK = "# Agent Triforge: this worktree only, never merged."
oldp, olds = set(), set()
at = text.find(MARK)
while at > 0 and text[at - 1] != "\n":
    at = text.find(MARK, at + 1)
if at >= 0:
    try:
        old = tomllib.loads(text[at:])
    except Exception as e:
        refuse("the tables an earlier provisioning wrote do not parse any more: %s" % (str(e).splitlines() or ["invalid TOML"])[0][:160])
    op, om = old.get("plugins"), old.get("mcp_servers")
    if isinstance(op, dict) and isinstance(op.get("disabled"), list):
        oldp.update(n for n in op["disabled"] if isinstance(n, str) and n)
    if isinstance(om, dict):
        olds.update(n for n, v in om.items() if isinstance(v, dict) and v.get("enabled") is False)
    text = text[:at]
    if text.endswith("\n\n"):
        text = text[:-1]
try:
    own = tomllib.loads(text).get("mcp_servers")
    own = set(own) if isinstance(own, dict) else set()
except Exception:
    own = set()   # the proof below refuses a file that does not parse
plugins, servers = set(), set()
for p in d["plugins"]:
    if isinstance(p, dict) and isinstance(p.get("name"), str) and p["name"]:
        plugins.add(p["name"])
try:
    plugins.update(n for n in (str(k).split("@", 1)[0] for k in (json.load(open(os.path.expanduser("~/.claude/plugins/installed_plugins.json"), encoding="utf-8")).get("plugins") or {})) if n)
except Exception:
    pass
plugins.update(oldp)
# What the user tier starts in a read-class session, by file: {file: {kind:
# [names]}}, named in one NOTE line once the file is written
found = {}
def note(where, kind, what=""):
    names = found.setdefault(where, {}).setdefault(kind, [])
    if what and what not in names:
        names.append(what)
def hook_files(where):
    # inspect reports a ~/.grok/hooks hook by its directory: name the JSON
    # files grok loads from it
    try:
        js = sorted(n for n in os.listdir(where) if n.endswith(".json")) if where and os.path.isdir(where) else []
    except OSError:
        js = []
    return ", ".join(os.path.join(where, n) for n in js[:10]) + (", and %d more" % (len(js) - 10) if len(js) > 10 else "") if js else where
if cls == "read":
    # Everything inspect reports that grok starts as a session opens: a hook
    # or LSP server from the project (refused), from the user (~/.grok/hooks,
    # lsp.json, the config layers) or a plugin the tables below do not
    # disable (named in the note)
    for kind, items in (("hook", d["hooks"]), ("LSP server", d["lspServers"]), ("plugin", d["plugins"])):
        for e in items:
            if not isinstance(e, dict) or e.get("disabled") is True:
                continue
            s = e.get("source") if isinstance(e.get("source"), dict) else {}
            where = s.get("path") or e.get("path") or ""
            what = str(e.get("name") or e.get("event") or "unnamed")[:80]
            if s.get("type") == "project" or e.get("scope") == "project" or inside(where):
                print("grok: ERROR %s: grok inspect reports a project %s from it (%s). %s" % (where or wt, kind, what, os.environ["GLC_TAIL"]))
                sys.exit(1)
            if kind == "plugin" or (s.get("type") == "plugin" and s.get("plugin_name") in plugins):
                continue
            label = "plugin %s " % s["plugin_name"] if s.get("type") == "plugin" and s.get("plugin_name") else ""
            if kind == "hook":
                note(hook_files(where) or "grok inspect", label + "hooks", what)
            else:
                note(where or "grok inspect", label + "LSP server", what)
    # What inspect does not list: a command a user-tier config layer runs at
    # login or on an event, and MCP servers in a requirements layer, which
    # outranks the project file the shadows go into (MCP tool calls stay
    # denied). A layer that does not parse is refused: nothing shows what it
    # starts
    gh = os.environ.get("GROK_HOME") or os.path.join(os.path.expanduser("~"), ".grok")
    for path in [os.path.join(gh, n) for n in ("config.toml", "managed_config.toml", "requirements.toml")] + ["/etc/grok/managed_config.toml", "/etc/grok/requirements.toml"]:
        if not os.path.lexists(path):
            continue
        try:
            t = tomllib.loads(open(path, encoding="utf-8", errors="replace").read())
        except Exception as e:
            print("grok: ERROR %s: the file does not parse or read (%s), so nothing shows which commands grok would start from it. A grok reviewer or analyst does not start on a broken grok configuration (R23). Fix: repair the file, or route the role to another roster member" % (path, (str(e).splitlines() or ["error"])[0][:80]))
            sys.exit(1)
        sect = lambda o, k: o.get(k) if isinstance(o.get(k), dict) else {}
        for k in ("auth", "grok_com_config"):
            if sect(t, k).get("auth_provider_command"):
                note(path, "%s.auth_provider_command" % k)
        for n, v in sect(t, "auth_provider").items():
            if isinstance(v, dict) and v.get("command"):
                note(path, "auth_provider.%s.command" % n)
        if sect(sect(t, "ui"), "notifications").get("hooks"):
            note(path, "ui.notifications.hooks")
        for n in sorted(sect(t, "hooks")):
            note(path, "hooks", str(n)[:80])
        if path.endswith("requirements.toml"):
            for n in sorted(n for n, v in sect(t, "mcp_servers").items() if not (isinstance(v, dict) and v.get("enabled") is False)):
                note(path, "MCP servers in the requirements layer", str(n)[:80])
# Every MCP server, shadowed by name (enabled = false in the project file):
# what inspect lists, the ~/.claude.json servers (inspect reports them off,
# yet a session starts them) and the worktree .mcp.json ones. A server the
# project file defines itself is left to it: inspect files a project server
# under ~/.grok/config.toml, and a project entry replaces a user one of the
# same name. A name the project file shares with ~/.claude.json, .mcp.json or
# a plugin stays a shadow, so the proof below refuses that collision.
for m in d["mcpServers"]:
    if isinstance(m, dict) and isinstance(m.get("name"), str) and m["name"]:
        s = m.get("source") if isinstance(m.get("source"), dict) else {}
        if not (m["name"] in own and s.get("type") in ("configToml", "project", "user")):
            servers.add(m["name"])
for path in ("~/.claude.json", os.path.join(wt, ".mcp.json")):
    try:
        servers.update(str(k) for k in (json.load(open(os.path.expanduser(path), encoding="utf-8")).get("mcpServers") or {}) if str(k))
    except Exception:
        pass
servers.update(olds)
block = (MARK + " No plugin and no MCP server outside grok loads for the grok worker (GRK-06).\n"
         "[plugins]\ndisabled = [" + ", ".join(json.dumps(n) for n in sorted(plugins)) + "]\n"
         + "".join("\n[mcp_servers.%s]\ncommand = \"false\"\nenabled = false\n" % json.dumps(n) for n in sorted(servers)))
new = (text + ("" if text.endswith("\n") else "\n") + "\n" + block) if text else block
try:
    t = tomllib.loads(new)
except Exception as e:
    refuse("the project file cannot take the tables (it declares [plugins], or an MCP server table the shadows collide with): %s" % (str(e).splitlines() or ["invalid TOML"])[0][:160])
p, ms = t.get("plugins"), t.get("mcp_servers")
if not isinstance(p, dict) or not isinstance(p.get("disabled"), list) or not plugins <= set(p["disabled"]):
    refuse("plugins.disabled does not name every plugin once the tables are added")
for n in sorted(servers):
    if not isinstance(ms, dict) or not isinstance(ms.get(n), dict) or ms[n].get("enabled") is not False:
        refuse("MCP server %s is not shadowed once the tables are added" % json.dumps(n))
os.makedirs(gdir, exist_ok=True)
with open(cfg, "w", encoding="utf-8") as f:
    f.write(new)
if found:
    print("grok: NOTE this grok reviewer or analyst session runs these user-level grok settings, as every grok session on this machine does: %s. Project-level hooks, LSP servers, plugins and MCP servers stay refused, and MCP tools denied (R23)"
          % "; ".join("%s (%s)" % (w, "; ".join(k + (": " + ", ".join(v) if v else "") for k, v in found[w].items())) for w in sorted(found)))
' >&2 || { if [ "$IRC" = unresolved ]; then return 80; fi; return 1; }
  # The edit class runs under its own sandbox profile (_grok_argv edit)
  if [ "$CLASS" = edit ]; then
    _grok_sandbox_profile "$WT" || return 1
  fi
  return 0
}

# grok_read_isolation_check — whether a grok reviewer or analyst can start on
# this machine, asked by at-setup before it offers grok a read role: the
# read-class check (_grok_lease_config <dir> read) run from an empty scratch
# directory, so only the user tier counts, and nothing outside that
# directory, removed afterwards, is written. rc 0 and an OK line on stdout
# when a read-class run can start, after the check's NOTE line when the
# user's own grok configuration has hooks, LSP servers or config-layer
# commands that run in every grok session (each named with its file); else
# rc 1 and the refusal on stdout: a user config layer that does not parse,
# grok absent, or an inspect that fails, since no read-class run would start
# then either. It runs `grok inspect --json` and reads the config layers; it
# never writes under GROK_HOME.
grok_read_isolation_check() {
  local D OUT="" RC=0
  D=$(mktemp -d "${TMPDIR:-/tmp}/triforge-grok-check.XXXXXX") || {
    echo "grok: could not make a scratch directory under ${TMPDIR:-/tmp} to run the check from"
    return 1
  }
  OUT=$(_grok_lease_config "$D" read 2>&1) || RC=$?
  rm -rf "$D"
  if [ "$RC" -ne 0 ]; then
    printf '%s\n' "${OUT:-grok: the read-class check failed to run}"
    return 1
  fi
  if [ -n "$OUT" ]; then
    printf '%s\n' "$OUT"
    echo "grok: OK — a grok reviewer or analyst can start here; the NOTE above names the user-level grok settings it runs"
    return 0
  fi
  echo "grok: OK — a grok reviewer or analyst can start here"
  return 0
}

# _grok_scratch_wt <dir> <sha> — invoke_grok's working directory (R23):
# <dir>/wt, a checkout of <sha> (the lead's HEAD) in the empty <dir> the
# caller made, provisioned for the read class (_grok_lease_config <dir>/wt
# read). The checkout is a fresh repository (git init with no template) that
# borrows the lead's object store through objects/info/alternates, made by the
# lead's hardened git (_lead_git) with an empty file for its global config:
# git reads the new repository's own config and nothing else, so no filter
# driver, hook or fsmonitor named in the lead's .git/config or the user's git
# config runs (a .gitattributes filter runs only where a config defines it),
# and the lead's .git records no worktree. The provisioning's inspect runs
# supervised (_grok_lease_config <dir>/wt read supervised). rc 1, the reason on
# stderr, when it can't be made or provisioned; the caller removes <dir>
# (_grok_scratch_drop). rc 80 when what the inspect left could not be stopped:
# the caller leaves <dir> (_grok_scratch_left). Runs after _lease_ctx (it reads
# _LEASE_COMMON and _LEASE_REPO).
_grok_scratch_wt() {
  local D=$1 SHA=$2 RC=0 _LEAD_CFG="${1}/gitconfig"
  case "$SHA" in
    ""|*[!0-9a-f]*)
      echo "invoke_grok: ERROR no commit to check out into the scratch checkout ('${SHA}')" >&2
      return 1
      ;;
  esac
  : > "$_LEAD_CFG" || return 1
  if [ "${#SHA}" -eq 64 ]; then
    _lead_git init -q --template= --object-format=sha256 "${D}/wt" >/dev/null 2>&1 || RC=1
  else
    _lead_git init -q --template= "${D}/wt" >/dev/null 2>&1 || RC=1
  fi
  if [ "$RC" -eq 0 ]; then
    printf '%s\n' "${_LEASE_COMMON}/objects" > "${D}/wt/.git/objects/info/alternates" || RC=1
  fi
  if [ "$RC" -eq 0 ]; then
    _lead_git -C "${D}/wt" checkout -q --detach "$SHA" >/dev/null 2>&1 || RC=1
  fi
  if [ "$RC" -ne 0 ]; then
    echo "invoke_grok: ERROR could not check ${_LEASE_REPO} out at ${SHA} into the scratch checkout ${D}/wt" >&2
    return 1
  fi
  _grok_lease_config "${D}/wt" read supervised
}

# _grok_scratch_drop <dir> — remove a scratch directory _grok_run_in made.
# Only a triforge-grok.* path is removed; anything else, "" included, is left.
_grok_scratch_drop() {
  case "${1:-}" in
    */triforge-grok.*) rm -rf "$1" ;;
  esac
  return 0
}

# _grok_run_in <sha> <timeout-bin> <seconds> <prompt> <ready-file> — one
# invoke_grok run in a subshell that owns its scratch from the first step: its
# INT, TERM and HUP traps (_grok_run_end) are set before the scratch directory
# exists, so an interrupt while the checkout is made, while provisioning waits
# on `grok inspect` (up to 30 s) or while grok runs stops the step (the process
# tree under it, _grok_run_stop) and removes the directory, and the subshell
# exits 130, 143 or 129 (_grok_interrupted). Each step is a background job the
# subshell waits for: a trapped signal ends a `wait` at once, while a
# foreground child would hold the trap until it exited. The inspect and the
# run each go through the run supervisor the persona lane starts its CLIs
# under (_PERSONA_RUN_PY), with a timeout that is not --foreground: timeout
# puts itself and grok in a process group of their own, and once grok ends, on
# its own or at the deadline, the supervisor stops what it left running there
# or below it (a hook, an LSP server, a tool shell; timeout --foreground would
# time out grok alone, and they would outlive the scratch) before the step
# returns, so before C is cleared and the directory goes. Being out of the
# caller's group, grok gets no terminal interrupt itself: the subshell gets
# it, and its traps stop the step, as in the persona lane. The subshell makes
# a fresh triforge-grok.XXXXXX directory under TMPDIR, the scratch in it
# (_grok_scratch_wt <dir> <sha>), then <ready-file>, which holds what the
# provisioning printed (the user-tier NOTE line, or nothing), then runs
# _GROK_ARGV and <prompt> from the scratch under the lease boundary's env
# (_adapter_env grok: env -i with the base allowlist, grok's own keys, the
# worker marker and the no-push config), and removes the directory. Its exit
# code is grok's (124, or 137 after the KILL, at the deadline), or the
# supervisor's 80 when it could not stop or list what grok left: then, as when
# a trap's stop leaves something running, the directory stays and is named on
# stderr (_grok_scratch_left), never removed under a live process. grok's own
# exit 80 would read the same, and keeping the directory is the safe reading.
# No <ready-file> afterwards means grok never ran; the reason is on stderr.
# The caller's own traps are untouched.
_grok_run_in() {
  (
    D=""
    C=""
    trap '_grok_run_end 130 "$C" "$D"' INT
    trap '_grok_run_end 143 "$C" "$D"' TERM
    trap '_grok_run_end 129 "$C" "$D"' HUP
    D=$(mktemp -u "${TMPDIR:-/tmp}/triforge-grok.XXXXXX") || D=""
    if [ -z "$D" ] || ! mkdir -m 700 "$D" 2>/dev/null; then
      D=""
      echo "invoke_grok: ERROR could not make a scratch directory under ${TMPDIR:-/tmp}" >&2
      exit 1
    fi
    _grok_scratch_wt "$D" "$1" 2> "${D}/provision.err" &
    C=$!
    R=0
    wait "$C" || R=$?
    C=""
    if [ "$R" -ne 0 ] || ! cat "${D}/provision.err" > "$5"; then
      cat "${D}/provision.err" >&2 2>/dev/null || true
      rm -f "$5"
      if [ "$R" -eq 80 ]; then _grok_scratch_left "$D"; else _grok_scratch_drop "$D"; fi
      exit 1
    fi
    cd "${D}/wt" || { _grok_scratch_drop "$D"; exit 1; }
    _adapter_env grok python3 -c "$_PERSONA_RUN_PY" 5 "$2" -k 10s "${3}s" "${_GROK_ARGV[@]}" "$4" < /dev/null &
    C=$!
    R=0
    wait "$C" || R=$?
    C=""
    cd / || true
    if [ "$R" -eq 80 ]; then _grok_scratch_left "$D"; else _grok_scratch_drop "$D"; fi
    exit "$R"
  )
}

# _grok_run_end <rc> <pid> <dir> — _grok_run_in's INT, TERM and HUP trap: stop
# the step <pid> still running ("" for none, _grok_run_stop), then remove
# <dir>, or leave it, named on stderr, when the stop left something running
# (_grok_scratch_left), and exit <rc>.
_grok_run_end() {
  if _grok_run_stop "$2"; then
    _grok_scratch_drop "$3"
  else
    _grok_scratch_left "$3"
  fi
  exit "$1"
}

# _grok_run_stop <pid> — stop a _grok_run_in step and every process under it,
# for a signal that reached the subshell alone (a background step ignores
# INT, and the provisioning's timeout sits below a command substitution), as
# the persona lane's cleanup stops its CLI (_persona_stop_tree): TERM to the
# tree, up to 5 s for all of it to end, then KILL to what is left and to what
# it started meanwhile, each pid checked by its start time. A run supervisor
# in the tree (the run's or the inspect's) takes the TERM as its cue to stop
# grok's process group (3 s, then its KILL), which the 5 s leave room for. One
# process that ignores TERM would otherwise keep running against the scratch
# directory the trap removes next. 0 when nothing of the tree runs any more,
# "" included; 1 when something may (a pid still running after the KILL, or
# ps unreadable).
_grok_run_stop() {
  if [ -z "${1:-}" ]; then return 0; fi
  _persona_stop_tree "$1" "" "" 5 >/dev/null
}

# _grok_scratch_left <dir> — a scratch directory a process of the run may
# still use (the run supervisor's sweep, or a trap's stop, could not stop or
# list everything): left in place and named on stderr for removal by hand, as
# the persona lane leaves its own. No-op for "".
_grok_scratch_left() {
  if [ -n "${1:-}" ]; then
    echo "invoke_grok: unresolved cleanup — a process of the grok run may still be running, so its scratch directory ${1} stays; remove it (rm -rf) once ps shows that process has ended" >&2
  fi
  return 0
}

# _grok_interrupted <agent-name> <output-file> <rc> <stderr-file> — 0 when
# <rc> is the exit of a _grok_run_in subshell a signal stopped (129 HUP, 130
# INT, 143 TERM; a grok a signal killed exits the same way): the run is over,
# so invoke_grok returns <rc> and never retries (class deterministic, reason
# interrupted); the line goes to stderr and to <output-file>. Its scratch is
# removed, unless the stop left something running: then the subshell's line
# naming it (_grok_scratch_left, in <stderr-file>) goes to stderr first. 1
# for any other <rc>.
_grok_interrupted() {
  case "$3" in
    129|130|143) ;;
    *) return 1 ;;
  esac
  if grep '^invoke_grok: unresolved cleanup' "${4:-/dev/null}" >&2 2>/dev/null; then
    echo "invoke_grok: agent=${1:-<none>} interrupted (exit ${3}); its scratch checkout stays (above). No retry." >&2
  else
    echo "invoke_grok: agent=${1:-<none>} interrupted (exit ${3}); its scratch checkout is removed. No retry." >&2
  fi
  echo "invoke_grok: interrupted (exit ${3}) — no answer" > "$2" 2>/dev/null || true
  INVOKE_FAILURE_CLASS="deterministic"
  _INVOKE_FAILURE_REASON="interrupted"
  return 0
}

# _grok_recheck <agent-name> <role> <output-file> — what invoke_grok checks
# before each attempt, against the roster and the lead's git state as they
# are now, so a retry never rides the first attempt's checks: the recorded
# consent (_member_consent_ok; grok asks none today) and the role rule
# (_member_role_ok: a member the roster declines takes no role), each rc 5 and
# reason consent or role; then the lead's integrity check, as lease_create
# runs it before a carve (_lead_integrity_check: rc 44 when a git state
# changed outside the lead's operations, reason integrity; with no ledger
# there is nothing to compare and nothing is written). 0 when all pass; else
# the refusal on stderr and in <output-file>, class deterministic, and the
# check's rc. Runs after _lease_ctx (the roster is the lead checkout's).
_grok_recheck() {
  local RC=0 ROSTER="${_LEASE_REPO}/ops/roster.toml"
  _INVOKE_FAILURE_REASON="consent"
  _member_consent_ok grok "$ROSTER" 2> "${3}.gate" || RC=$?
  if [ "$RC" -eq 0 ]; then
    _INVOKE_FAILURE_REASON="role"
    _member_role_ok grok "$2" "$ROSTER" 2> "${3}.gate" || RC=$?
  fi
  if [ "$RC" -ne 0 ]; then
    cat "${3}.gate" >&2
    cat "${3}.gate" > "$3" 2>/dev/null || true
    rm -f "${3}.gate"
    INVOKE_FAILURE_CLASS="deterministic"
    return "$RC"
  fi
  rm -f "${3}.gate"
  _INVOKE_FAILURE_REASON=""
  _lead_integrity_check invoke_grok || RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "invoke_grok: agent=${1:-<none>} not dispatched: the lead's git state failed the integrity check (above), so nothing is checked out for grok (KTD18). No retry (deterministic)." >&2
    echo "invoke_grok: not dispatched — the lead's git state failed the integrity check (rc ${RC}; see the lead's stderr)" > "$3" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="integrity"
    return "$RC"
  fi
  return 0
}

# _grok_unisolated <agent-name> <output-file> <why> — invoke_grok's refusal
# when grok can't start isolated: <why> on stderr and in <output-file> (never
# an empty file a caller could read as "no findings"), class deterministic,
# reason isolation. The caller returns 69.
_grok_unisolated() {
  echo "invoke_grok: agent=${1:-<none>} not dispatched: ${3} No retry (deterministic)." >&2
  echo "invoke_grok: not dispatched — ${3}" > "$2" 2>/dev/null || true
  INVOKE_FAILURE_CLASS="deterministic"
  _INVOKE_FAILURE_REASON="isolation"
}

# invoke_grok <agent-name> <prompt> [output-file] [timeout-seconds] [effort]
# The class comes from GROK_ROLE (dispatch_role sets it from the roster role),
# else from the agent name: *review* and *analy* read, *build*, *test* and
# *doc* edit, anything else read. invoke_grok runs the read class only: the
# edit class is refused (rc 69, deterministic, reason edit-outside-lease,
# grok never run), because outside a lease grok would edit the caller's
# checkout with nothing keeping the plugins and servers off; a grok builder
# runs through lease_create and lease_dispatch. The grok-agents/<agent-name>.md
# brief, when one exists, is prefixed onto the prompt (grok's --agent takes a
# profile, not a role brief; dispatch_role hands a reviewer or analyst whose
# persona name has none here the reviewer brief's name, _dispatch_role_brief),
# else the prompt runs raw with a warning. Before each attempt, the first and
# the retry, nothing is checked out until _grok_recheck passes: the roster's
# consent and role rules now (rc 5, reason consent or role: a declined member
# runs no more) and the lead's integrity check, as lease_create runs it before it
# carves (_lead_integrity_check: a git state changed outside the lead's
# operations returns its rc, 44, and nothing runs; with no ledger there is
# nothing to compare and nothing is written). Each run then starts from its
# own scratch checkout of HEAD (_grok_run_in, _grok_scratch_wt, the project
# checks included, and the NOTE line naming the user's own grok
# configuration that runs, passed on to stderr; a retry gets a fresh one),
# removed afterwards, once what grok left running is stopped, under the lease
# boundary's env, and the prompt names the caller's checkout for anything HEAD
# lacks (uncommitted changes, an untracked ops/). rc 69 (deterministic, reason
# isolation, nothing dispatched) when the scratch can't be made or
# provisioned; rc 80 when a clean end_turn run gave no answer text (report
# missing), and rc 80 (deterministic, reason unresolved-cleanup, no retry) when
# what grok left running could not be stopped or listed: the scratch checkout
# stays, named on stderr, and the answer written to <output-file> is untrusted.
invoke_grok() {
  local AGENT_NAME=$1
  local PROMPT=$2
  local OUTPUT_FILE=${3:-"${TMPDIR:-/tmp}/grok_output_$$_$(date +%s).txt"}
  local TIMEOUT=${4:-600}
  local EFFORT=${5:-${GROK_EFFORT:-}}
  local MODEL="${GROK_MODEL:-grok-4.7}"
  local ROLE=${GROK_ROLE:-$AGENT_NAME}
  local CLASS="" MODE="raw" EXIT_CODE=0 STOP="" BODY="" AVAILABLE="" TOBIN="" SHA="" NOTE="" RC=0
  local RAW="${OUTPUT_FILE}.raw"
  local ERR="${OUTPUT_FILE}.err"
  local READY="${OUTPUT_FILE}.ready"

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
  if [ "$CLASS" = edit ]; then
    echo "invoke_grok: ERROR agent=${AGENT_NAME:-<none>} role=${GROK_ROLE:-<none; read from the agent name>} is grok's edit class, which runs only in a lease worktree: lease_create <task> builder, then lease_dispatch. Here it would edit the caller's checkout, where no provisioned config keeps the Claude Code plugins, their hooks and the MCP servers off (R23). Not dispatched. No retry (deterministic)." >&2
    echo "invoke_grok: not dispatched — grok edits only in a lease worktree (lease_create, then lease_dispatch)" > "$OUTPUT_FILE" 2>/dev/null || true
    INVOKE_FAILURE_CLASS="deterministic"
    _INVOKE_FAILURE_REASON="edit-outside-lease"
    return 69
  fi

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

  TOBIN=$(_timeout_tool) || {
    INVOKE_FAILURE_CLASS="deterministic"
    return "$_RC_NO_TIMEOUT_TOOL"
  }
  _grok_argv "$CLASS" "$MODEL" "$EFFORT" || return 1
  # The lead's checkout, and its git state as lease_create checks it before a
  # carve (R1, KTD18), before any checkout is made
  if ! _lease_ctx 2>/dev/null; then
    if [ "${_LEASE_CTX_WHY:-}" = home ]; then
      _grok_unisolated "$AGENT_NAME" "$OUTPUT_FILE" "a grok reviewer or analyst runs from a scratch checkout of HEAD, and ${PWD} is in a checkout that is your home directory or contains it, which is no project."
    else
      _grok_unisolated "$AGENT_NAME" "$OUTPUT_FILE" "a grok reviewer or analyst runs from a scratch checkout of HEAD, and ${PWD} is not inside a git checkout."
    fi
    return 69
  fi
  _grok_recheck "$AGENT_NAME" "$ROLE" "$OUTPUT_FILE" || RC=$?
  if [ "$RC" -ne 0 ]; then
    return "$RC"
  fi
  SHA=$(_lgr rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) || SHA=""
  if [ -z "$SHA" ]; then
    _grok_unisolated "$AGENT_NAME" "$OUTPUT_FILE" "a grok reviewer or analyst runs from a scratch checkout of HEAD, and ${_LEASE_REPO} has no commit."
    return 69
  fi
  NOTE="

(Your working directory is a scratch copy of the project at HEAD. The lead's checkout, with its uncommitted changes and ops/, is ${_LEASE_REPO}: read files there by absolute path. Change nothing in either.)"
  echo "invoke_grok: agent=${AGENT_NAME:-<none>} mode=${MODE} class=${CLASS} model=${MODEL} effort=${EFFORT:-default} dir=<a scratch checkout of ${_LEASE_REPO} at ${SHA}>" >&2

  # stdout -> RAW (the event stream), stderr -> ERR (grok's own messages and
  # the scratch's); no READY afterwards: the scratch was refused, grok never ran
  rm -f "$READY"
  _grok_run_in "$SHA" "$TOBIN" "$TIMEOUT" "${FULL_PROMPT}${NOTE}" "$READY" > "$RAW" 2>"$ERR" || EXIT_CODE=$?
  if _grok_interrupted "$AGENT_NAME" "$OUTPUT_FILE" "$EXIT_CODE" "$ERR"; then
    rm -f "$RAW" "$ERR" "$READY"
    return "$EXIT_CODE"
  fi
  if [ ! -f "$READY" ]; then
    cat "$ERR" >&2 2>/dev/null || true
    rm -f "$RAW" "$ERR"
    _grok_unisolated "$AGENT_NAME" "$OUTPUT_FILE" "grok's isolation could not be set up (see the lead's stderr)."
    return 69
  fi
  # The provisioning's NOTE line, when the user's own grok configuration
  # runs in the session
  cat "$READY" >&2 2>/dev/null || true
  rm -f "$READY"

  # A clean exit is complete only when the stream ended with end_turn: any
  # other stop (refusal, max_tokens, cancelled) fails here, deterministically.
  if [ "$EXIT_CODE" -eq 0 ]; then
    STOP=$(_grok_stop "$RAW")
    case "$STOP" in
      end_turn) : ;;
      *) EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="stopped:${STOP}" ;;
    esac
  elif [ "$EXIT_CODE" -eq 80 ]; then
    # _grok_run_in's 80: what grok left runs on, beside its scratch checkout;
    # a retry would start another grok next to it
    INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="unresolved-cleanup"
  else
    _grok_classify "$EXIT_CODE" "$RAW" "$ERR"
  fi

  if [ "$INVOKE_FAILURE_CLASS" = retryable ]; then
    # Single retry: the raw prompt with the same command line (class, sandbox
    # and rules kept; only the brief is shed, as the sibling helpers do), from
    # a fresh scratch checkout
    echo "invoke_grok: agent=${AGENT_NAME} exit=${EXIT_CODE} (retryable), retrying once with the raw prompt" >&2
    # The roster and the lead's git state as they are now (_grok_recheck);
    # the fresh scratch runs the project checks and inspect again
    _grok_recheck "$AGENT_NAME" "$ROLE" "$OUTPUT_FILE" || RC=$?
    if [ "$RC" -ne 0 ]; then
      rm -f "$RAW" "$ERR"
      return "$RC"
    fi
    EXIT_CODE=0
    _grok_run_in "$SHA" "$TOBIN" "$TIMEOUT" "${PROMPT}${NOTE}" "$READY" > "$RAW" 2>"$ERR" || EXIT_CODE=$?
    if _grok_interrupted "$AGENT_NAME" "$OUTPUT_FILE" "$EXIT_CODE" "$ERR"; then
      rm -f "$RAW" "$ERR" "$READY"
      return "$EXIT_CODE"
    fi
    if [ ! -f "$READY" ]; then
      cat "$ERR" >&2 2>/dev/null || true
      rm -f "$RAW" "$ERR"
      _grok_unisolated "$AGENT_NAME" "$OUTPUT_FILE" "grok's isolation could not be set up for the retry (see the lead's stderr)."
      return 69
    fi
    cat "$READY" >&2 2>/dev/null || true
    rm -f "$READY"
    if [ "$EXIT_CODE" -eq 0 ]; then
      INVOKE_FAILURE_CLASS="none"
      STOP=$(_grok_stop "$RAW")
      case "$STOP" in
        end_turn) : ;;
        *) EXIT_CODE=1; INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="stopped:${STOP}" ;;
      esac
    elif [ "$EXIT_CODE" -eq 80 ]; then
      INVOKE_FAILURE_CLASS="deterministic"; _INVOKE_FAILURE_REASON="unresolved-cleanup"
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
      deterministic:unresolved-cleanup)
        grep 'unresolved cleanup' "$ERR" >&2 2>/dev/null || true
        echo "invoke_grok: agent=${AGENT_NAME} exit=${EXIT_CODE} grok left processes its run supervisor could not stop or list (above), so its scratch checkout stays and its answer in ${OUTPUT_FILE} is untrusted. No retry (deterministic)." >&2 ;;
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

  # A clean end_turn with no answer text is no answer: report missing (rc 80,
  # as invoke_devin's missing Status line), never success with an empty review.
  if ! _grok_extract_text "$RAW" "$OUTPUT_FILE"; then
    echo "invoke_grok: agent=${AGENT_NAME} exit=0, stopReason=end_turn, but the stream holds no answer text — report missing, not review-ready (rc ${_RC_DEGRADED}); grok's own output is in ${OUTPUT_FILE}" >&2
    { echo "invoke_grok: the run ended end_turn with no answer text — report missing"; cat "$ERR" "$RAW"; } > "$OUTPUT_FILE" 2>/dev/null || true
    rm -f "$RAW" "$ERR"
    INVOKE_FAILURE_CLASS="retryable"
    _INVOKE_FAILURE_REASON="no-answer"
    return "$_RC_DEGRADED"
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
# the lease lane (through _grok_lease_text), where the typed `Status:` report
# is parsed from the result.
_grok_extract_text() {
  G_RAW="$1" G_OUT="$2" python3 -c "${_READ_REGULAR_PY}"'
import json, os, sys
responses, cur, calls, denied = [], [], {}, []
stop, capped = None, False
for line in read_regular(os.environ["G_RAW"]).decode("utf-8", "replace").split("\n"):
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
  G_RAW="$1" python3 -c "${_READ_REGULAR_PY}"'
import json, os
stop, capped, err = None, False, False
try:
    lines = read_regular(os.environ["G_RAW"]).decode("utf-8", "replace").splitlines()
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

# _grok_lease_text <stream-file> <output-file> — the lease lane's extractor
# (_lease_extract_stream): the answer of a run that ended end_turn, as
# _grok_extract_text gives it. Any other end (a turn-cap stop, max_tokens,
# refusal, cancelled, no end event) writes one line naming it and no Status
# line, so lease_collect routes the run as report missing and never takes a
# typed report from a partial answer; the stream stays in <stream-file>. A
# capture with no JSON event at all is not a grok stream (the
# TRIFORGE_TEST_BUILDER seam): rc 1, nothing written, as any extraction miss.
_grok_lease_text() {
  local STOP
  if ! grep -q '^[[:space:]]*{' "$1" 2>/dev/null; then return 1; fi
  STOP=$(_grok_stop "$1")
  if [ "$STOP" = end_turn ]; then
    _grok_extract_text "$1" "$2"
    return
  fi
  printf 'lease_dispatch: the grok run ended with %s, not end_turn: incomplete, so no report is taken from it (report missing). Its stream: %s\n' "$STOP" "$1" > "$2"
}

# _grok_classify <rc> <file>... — set INVOKE_FAILURE_CLASS and
# _INVOKE_FAILURE_REASON for a failed grok run: a turn-cap stop
# (max_turns_reached), quota and signed out are deterministic; anything else is
# _classify_invoke_failure's call (timeout, interrupted, retryable). Only grok's own words
# are read — error events and the non-JSON (stderr) lines — never tool output,
# so a test that prints "401" is not an auth failure.
_grok_classify() {
  local RC=$1 WHY=""
  shift
  WHY=$(python3 -c "${_READ_REGULAR_PY}"'
import json, re, sys
capped, said = False, []
for path in sys.argv[1:]:
    try:
        lines = read_regular(path).decode("utf-8", "replace").splitlines()
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
