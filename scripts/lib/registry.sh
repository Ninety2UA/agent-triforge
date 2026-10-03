#!/usr/bin/env bash
# scripts/lib/registry.sh — data the other lanes read from one place (KTD7): the CLI registry (one literal per CLI — tier, binary, model, install hint, env allowlist keys, lane, egress, the KTD1 lead fields; R25/R41), the two protected-path lists and their match rule (KTD8), and the model ladder (KTD22)
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh and before scripts/lib/lease.sh.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/registry.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Protected paths (KTD8, R30)
# ---------------------------------------------------------------------------
#
# A diff touching a protected path forces the promotion gate on and needs the
# lead or the user as cross-reviewer, never an external-CLI-only review.
# Two lists:
#   FRAMEWORK_PROTECTED  Triforge's own control plane. Applies only in the
#                        Triforge checkout (.claude-plugin/plugin.json named
#                        agent-triforge), so a user project's own scripts/,
#                        skills/ or hooks/ are not force-gated.
#   PROJECT_PROTECTED    what governs the pool in ANY project: the roster, each
#                        CLI's permission/config tree, and every instruction
#                        file at any depth.
# Entries ending in "/" match everything under that directory AND the bare
# name itself (".claude/" also hits a changed path ".claude"), so a symlink or
# file committed in the directory's place cannot redirect a CLI config tree
# past the gate; ".clauder" or "claudeish" still do not match. Any other entry
# matches that exact path (or a directory of that name). *_ANY_DEPTH entries match a
# basename anywhere in the tree. Matching is case-folded, because the default
# macOS filesystem treats Hooks/handlers/x.sh and hooks/handlers/x.sh as one
# file. Callers feed BOTH sides of a rename (git diff --no-renames) and read
# any error as a hit — the scan fails closed (lease_promote: rc 42).
#
# _PROTECTED_PY is spliced into the python that classifies paths (the
# _CURSOR_ID_PY pattern in cursor.sh); SELF-10 checks the protected-path list
# in the root AGENTS.md against it. A new control-plane file joins the right
# list in the commit that creates it.
_PROTECTED_PY='
FRAMEWORK_PROTECTED = (
    # enforcement code: the helper, its lanes, the no-push hook, the outer loop,
    # the skill locator every at- skill carries a copy of (KTD6)
    "scripts/lib/", "scripts/lease-git-hooks/", "scripts/skill-locator/", "scripts/fixtures/", "scripts/invoke-external.sh", "scripts/coordinate.sh",
    # the probe harness and the release gates
    "scripts/probe-capabilities.sh", "scripts/probe-self-tests.sh",
    "scripts/validate-skills.sh", "scripts/validate-versions.sh", "scripts/release-notes.sh",
    # lifecycle hooks, the lead-facing workflows and the persona home
    "hooks/", "skills/", "commands/", "personas/",
    # shipped agent configs, one directory per CLI
    "agents/", "antigravity-agents/", "codex-agents/", "opencode-agents/", "kimi-agents/", "cursor-agents/",
    # manifests, plugin settings, and the templates copied into user projects
    ".claude-plugin/", "settings.json", "templates/",
    # CI plumbing (.gitmodules is on PROJECT_PROTECTED: every project)
    ".github/",
)
FRAMEWORK_PROTECTED_ANY_DEPTH = (".gitattributes",)
PROJECT_PROTECTED = (
    "ops/roster.toml",
    # each CLI project-tier config / permission tree (agy reads .agents/hooks.json
    # and .agents/agents/, so .agents/ is protected whole, skills included)
    ".claude/", ".codex/", ".agents/", ".antigravity/", ".gemini/", ".opencode/", ".kimi-code/", ".cursor/",
    # project-root config files outside those trees: OpenCode reads its permission
    # config from opencode.json / opencode.jsonc, and Cursor still reads the
    # legacy root instruction file .cursorrules
    "opencode.json", "opencode.jsonc", ".cursorrules",
    # .gitmodules names the URL `git submodule update` pulls into any path a
    # nested repo was recorded at (a builder can record one at .claude/)
    ".gitmodules",
)
PROJECT_PROTECTED_ANY_DEPTH = ("agents.md", "agents.override.md", "claude.md", "claude.local.md", ".mcp.json")

def _protected_hit(folded, base, entries, any_depth):
    if base in any_depth:
        return True
    for e in entries:
        e = e.casefold()
        if e.endswith("/"):
            if folded.startswith(e) or folded == e[:-1]:
                return True
        elif folded == e or folded.startswith(e + "/"):
            return True
    return False

def protected_match(path, framework):
    """The list a changed path hits ("project" / "framework"), or None."""
    p = path
    while p.startswith("./"):
        p = p[2:]
    p = p.lstrip("/")
    folded = p.casefold()
    base = folded.rsplit("/", 1)[-1]
    if _protected_hit(folded, base, PROJECT_PROTECTED, PROJECT_PROTECTED_ANY_DEPTH):
        return "project"
    if framework and _protected_hit(folded, base, FRAMEWORK_PROTECTED, FRAMEWORK_PROTECTED_ANY_DEPTH):
        return "framework"
    return None
'

# _protected_classify <framework:0|1> < NUL-separated paths — print
# "<list><TAB><path>" for every protected path on stdin (git diff -z output).
# Nonzero, with the python error on stderr, when the classifier itself fails:
# callers treat that as a hit (fail closed), never as "nothing protected".
_protected_classify() {
  PC_FRAMEWORK="${1:-0}" python3 -c "
import os, sys
${_PROTECTED_PY}
framework = os.environ['PC_FRAMEWORK'] == '1'
raw = sys.stdin.buffer.read()
for item in raw.split(b'\0'):
    if not item:
        continue
    path = item.decode('utf-8', 'surrogateescape')
    hit = protected_match(path, framework)
    if hit:
        sys.stdout.write(hit + '\t' + path.encode('utf-8', 'surrogateescape').decode('utf-8', 'replace') + '\n')
"
}

# ---------------------------------------------------------------------------
# Model ladder (KTD22, R26)
# ---------------------------------------------------------------------------
#
# The one definition of the downgrade ladder for narrow runtime tasks. The
# instruction file (the root AGENTS.md), agents/team-lead.md and
# skills/wave-orchestration/SKILL.md point here with a one-line summary
# instead of restating the rungs; scripts/validate-versions.sh (check 2) fails
# when any other shipped file carries the phrase, a colon, and the rung list
# again. The `opus` rung names Opus 5.5 with its Claude Code floor (D-037).
# Callers print the text with triforge_ladder.
TRIFORGE_MODEL_LADDER='Downgrade ladder for narrow runtime tasks: `fable`+`max` (lead + never-downgrade tier when available; otherwise latest `opus` at `max` — the model steps down, the effort does not) → `opus` (Opus 5.5, Claude Code ≥ 2.1.280) + `xhigh` → `opus`+`high` → `sonnet` (Sonnet 5) + `high`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.'

# triforge_ladder — print the ladder text (one line, newline-terminated).
triforge_ladder() {
  printf '%s\n' "$TRIFORGE_MODEL_LADDER"
}

# ---------------------------------------------------------------------------
# CLI registry (KTD7, R25, R41)
# ---------------------------------------------------------------------------
#
# ONE literal per CLI. Adding a CLI is one entry here plus its lane file, probe
# rows, setup entry and egress line (R25); nothing else carries a copy:
# scripts/lib/roster.sh (resolution, enrollment, the core-trio set, install
# hints), scripts/lib/lease.sh (_adapter_env, dispatch defaults),
# scripts/lib/common.sh (_is_known_cli), hooks/handlers/session-start.sh (the
# optional-CLI detection and the roster-pin notice), scripts/validate-versions.sh
# (check 3 — the drift check parses this literal and compares every remaining
# copy with it) and scripts/probe-capabilities.sh (_lane_run, the live gates)
# all read it. Python source, like _PROTECTED_PY and _CURSOR_ID_PY: spliced
# into the python that resolves roles and writes the roster, and read by the
# shell accessors below through python3. Single-quoted: strings inside use
# double quotes only, never a '; a value containing " escapes it as \" (the
# codex launch line). The validator parses it with ast.literal_eval, so it
# must stay a pure literal — comments are fine, expressions are not.
#
# Fields — every entry carries all of them (check 3 enforces the shape):
#   name        display name for messages ("Antigravity CLI")
#   tier        "core" (required, never disabled, every fallback chain ends at
#               one) | "optional" (enrolled via setup; skipped clean when absent)
#   binary      the executable looked up on PATH
#   binary_env  variable that, when set, replaces `binary` with a resolved
#               absolute path ("" = none): cursor's TRIFORGE_CURSOR_BIN, which
#               _cursor_bin exports after accepting an `agent` whose --version
#               matches version_re
#   resolver    shell function that resolves the binary ("" = plain `binary`);
#               _registry_binary calls it when it is defined
#   version_re  the --version shape an alternate binary name must match ("")
#   model       shipped default model; "" for claude (the shell lane runs the
#               host default, the ladder is an Agent-tool concern — see
#               TRIFORGE_MODEL_LADDER)
#   model_env   the override variable the CLI's dispatch lane honors ("" for
#               claude: the ladder, never the roster, picks its model)
#   install     the official install command — PRINTED for the user, never run
#               (R18/R21); `login` is the step printed after it ("" when none)
#   env_keys    variables _adapter_env forwards into a lease besides the base
#               allowlist TRIFORGE_ENV_BASE: EXACT names only; the one
#               documented wildcard is kimi's "KIMI_*" (check 3 fails any other)
#   lane        how a role dispatch reaches the CLI: "shell" (its invoke_*
#               helper, or a command composed under env -i in lease_dispatch)
#               | "subagent" (a native Agent-tool subagent — review and test
#               work on the claude lane; dispatch_role returns 40)
#   egress      the model provider that receives the prompt and the code (R36)
#   lead        the KTD1 static lead fields, or {} for a CLI that cannot lead
#               (Key Decision: Claude Code or Codex only). launch_argv is the
#               launch line setup prints and the human types; wait_budget_s the
#               longest single wait the lead's shell tool allows; the two
#               tool_vocab_* lists are the lead's own read and action tool
#               names (what a paralysis monitor classifies); goal_gate the
#               completion-gate command ("" = none, the ops/.sprint-complete
#               sentinel alone); ask_user the question tool ("" = none);
#               plugin_root_env the variable the host exports for the plugin
#               root ("" = none — the skill locator finds it). hooks_trusted
#               is runtime (detected per session), not registry data.
_TRIFORGE_CLIS_PY='
CLIS = {
    "claude": {
        "name": "Claude Code",
        "tier": "core",
        "binary": "claude",
        "binary_env": "",
        "resolver": "",
        "version_re": "",
        "model": "",
        "model_env": "",
        "install": "npm install -g @anthropic-ai/claude-code",
        "login": "run `claude` once and /login",
        "env_keys": [],
        "lane": "subagent",
        "egress": "Anthropic",
        "lead": {
            "launch_argv": "claude",
            "wait_budget_s": 600,
            "tool_vocab_read": "Read Grep Glob WebFetch",
            "tool_vocab_action": "Edit Write Bash",
            "goal_gate": "/goal",
            "ask_user": "AskUserQuestion",
            "native_subagents_enforced_tools": True,
            "agent_teams": True,
            "plugin_root_env": "CLAUDE_PLUGIN_ROOT",
        },
    },
    "antigravity": {
        "name": "Antigravity CLI",
        "tier": "core",
        "binary": "agy",
        "binary_env": "",
        "resolver": "",
        "version_re": "",
        "model": "Gemini 3.8 Flash (High)",
        "model_env": "AGY_MODEL",
        "install": "curl -fsSL https://antigravity.google/cli/install.sh | bash",
        "login": "run `agy` interactively once to complete login",
        "env_keys": [],
        "lane": "shell",
        "egress": "Google",
        "lead": {},
    },
    "codex": {
        "name": "Codex CLI",
        "tier": "core",
        "binary": "codex",
        "binary_env": "",
        "resolver": "",
        "version_re": "",
        "model": "gpt-6-astra",
        "model_env": "CODEX_MODEL",
        "install": "npm install -g @openai/codex (or brew install codex)",
        "login": "run `codex login`",
        "env_keys": [],
        "lane": "shell",
        "egress": "OpenAI",
        "lead": {   # D-047 profile; tool names — verified: U14
            "launch_argv": "codex exec -s danger-full-access -c approval_policy=\"never\" -c background_terminal_max_timeout=900000",
            "wait_budget_s": 900,
            "tool_vocab_read": "read_file exec_command(read)",
            "tool_vocab_action": "exec_command apply_patch",
            "goal_gate": "",
            "ask_user": "",
            "native_subagents_enforced_tools": False,
            "agent_teams": False,
            "plugin_root_env": "",
        },
    },
    "opencode": {
        "name": "OpenCode",
        "tier": "optional",
        "binary": "opencode",
        "binary_env": "",
        "resolver": "",
        "version_re": "",
        "model": "openrouter/z-ai/glm-5.3",
        "model_env": "OPENCODE_MODEL",
        "install": "curl -fsSL https://opencode.ai/install | bash",
        "login": "set OPENROUTER_API_KEY, or run `opencode auth login` and connect the openrouter provider",
        "env_keys": ["OPENROUTER_API_KEY"],
        "lane": "shell",
        "egress": "Zhipu / Z.ai, through OpenRouter (which also sees the traffic)",
        "lead": {},
    },
    "kimi": {
        "name": "Kimi Code",
        "tier": "optional",
        "binary": "kimi",
        "binary_env": "",
        "resolver": "",
        "version_re": "",
        "model": "kimi-code/k3",
        "model_env": "KIMI_MODEL",
        "install": "curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash",
        "login": "run `kimi login`",
        "env_keys": ["KIMI_*"],
        "lane": "shell",
        "egress": "Moonshot",
        "lead": {},
    },
    "cursor": {
        "name": "Cursor CLI",
        "tier": "optional",
        "binary": "cursor-agent",
        "binary_env": "TRIFORGE_CURSOR_BIN",
        "resolver": "_cursor_bin",
        "version_re": "^[0-9]{4}\\.[0-9]{2}\\.[0-9]{2}-[0-9a-f]+",
        "model": "cursor-grok-4.6-xhigh",
        "model_env": "CURSOR_MODEL",
        "install": "curl https://cursor.com/install -fsS | bash",
        "login": "run `cursor-agent login`",
        "env_keys": ["CURSOR_API_KEY"],
        "lane": "shell",
        "egress": "xAI (Grok, via Cursor)",
        "lead": {},
    },
}
'

# The base env allowlist every lease builder gets (KTD-14) — identity and
# terminal, no credentials: USER is what lets `claude -p` find its keychain
# account under env -i. _adapter_env (scripts/lib/lease.sh) and its mirror
# _lane_run (scripts/probe-capabilities.sh) both read this list; a CLI's own
# credential variables are its env_keys entry above.
TRIFORGE_ENV_BASE="HOME PATH TMPDIR TERM LANG COLORTERM USER"

# cli_list [core|optional|all] — the registered CLI names, registry order,
# space-separated on one line (default: all).
cli_list() {
  CL_TIER="${1:-all}" python3 -c "
import os
${_TRIFORGE_CLIS_PY}
t = os.environ['CL_TIER']
print(' '.join(c for c, e in CLIS.items() if t == 'all' or e['tier'] == t))
"
}

# cli_field <cli> <field>[.<subfield>] — print one registry value: a list
# space-joined, a boolean as true|false, a table as its key names (cli_field
# codex lead -> the KTD1 field names; an empty table prints nothing). rc 2 with
# a message for an unknown CLI or field, so a typo never reads as "".
cli_field() {
  CF_CLI="${1:?usage: cli_field <cli> <field>[.<subfield>]}" CF_FIELD="${2:?usage: cli_field <cli> <field>[.<subfield>]}" python3 -c "
import os, sys
${_TRIFORGE_CLIS_PY}
cli = os.environ['CF_CLI']
field = os.environ['CF_FIELD']
if cli not in CLIS:
    sys.stderr.write('cli_field: unknown cli ' + repr(cli) + ' (registered: ' + ' '.join(CLIS) + ')\n')
    sys.exit(2)
v = CLIS[cli]
for k in field.split('.'):
    if not isinstance(v, dict) or k not in v:
        sys.stderr.write('cli_field: ' + cli + ' has no field ' + repr(field) + '\n')
        sys.exit(2)
    v = v[k]
if isinstance(v, bool):
    print('true' if v else 'false')
elif isinstance(v, (list, tuple)):
    print(' '.join(str(x) for x in v))
elif isinstance(v, dict):
    print(' '.join(v))
else:
    print(v)
"
}

# cli_install_fix <cli> — the one-line install-then-login fix the helpers print
# on a deterministic failure (R21 wording): "install <name> (<install>), then
# <login>". resolve_role composes the same line in python for its
# chain-exhausted error.
cli_install_fix() {
  CF_CLI="${1:?usage: cli_install_fix <cli>}" python3 -c "
import os, sys
${_TRIFORGE_CLIS_PY}
cli = os.environ['CF_CLI']
if cli not in CLIS:
    sys.stderr.write('cli_install_fix: unknown cli ' + repr(cli) + '\n')
    sys.exit(2)
e = CLIS[cli]
print('install ' + e['name'] + ' (' + e['install'] + ')' + (', then ' + e['login'] if e['login'] else ''))
"
}

# _registry_binary <cli> — the binary to look up on PATH: the entry's
# resolver's answer when the registry names one and the function is defined
# (cursor: _cursor_bin, which prints the verified absolute path), else the
# plain `binary` name. rc 2 for an unknown CLI.
_registry_binary() {
  local CLI=${1:?usage: _registry_binary <cli>} BIN="" RESOLVER="" OUT=""
  BIN=$(cli_field "$CLI" binary) || return 2
  RESOLVER=$(cli_field "$CLI" resolver) || return 2
  if [ -n "$RESOLVER" ] && command -v "$RESOLVER" >/dev/null 2>&1 && OUT=$("$RESOLVER" 2>/dev/null) && [ -n "$OUT" ]; then
    printf '%s\n' "$OUT"
    return 0
  fi
  printf '%s\n' "$BIN"
}

# The registered CLI names as one space-separated string, for the identity
# checks (_is_known_cli in common.sh) and the "one of: …" error messages in
# lease.sh. Set once at load from the literal above; empty (so every identity
# check fails closed) only when python3 is missing, which resolve_role refuses
# on anyway.
_KNOWN_CLIS=$(cli_list all 2>/dev/null) || _KNOWN_CLIS=""
