#!/usr/bin/env bash
# Context Monitor — PostToolUse hook
# Detects analysis paralysis (excessive read-only ops without producing code)
# and warns when approaching context limits.
#
# Hook event: PostToolUse
# Configuration: registered in hooks/hooks.json (plugin)
#
# ON_CRASH: ALLOW — a crash must never block the tool call (R14/G7): this hook
#   is advisory only; the EXIT trap below turns any unexpected non-zero status
#   (set -e / set -u, e.g. an unwritable state dir) into a stderr notice +
#   exit 0, and every explicit exit path is `exit 0`.
# Exit codes: 0 ok · 2 hook deny (never used by Triforge handlers) · 64 usage ·
#   66 no-input · 69 unavailable · 70 internal · 80 degraded (documented only —
#   Triforge handlers always return 0).
# Hook stdout must never look like JSON: no stdout line may start with `{`
#   (Claude Code ≥ 2.1.246 rejects hook stdout that parses as JSON — D-031c).
#   Audited 2026-10-04: every stdout line starts "Context monitor:" /
#   "Consider:" / "Strongly consider:" / "If researching"; the one-per-session
#   NOTE goes to stderr.
#
# Tool vocabulary (KTD1, R21): which tool names are reads is the lead's
# registry data (lead.tool_vocab_read / lead.tool_vocab_action in
# scripts/lib/registry.sh, read through lead_field), never a list here. A name
# in the read list is a read; "<tool>(read)" there makes a call of <tool>
# whose command only reads (cat, sed -n, rg, git log, ...) a read — how a
# Codex lead's shell reads count, since its hook payload names exec_command
# Bash (CDX-21). Any other name is an action, so an unmapped tool never
# raises a false warning. A lead whose read vocabulary is empty, or a lead
# that can't be resolved, leaves the hook inert, said once per session on
# stderr (R21, R44).
#
# State lives outside the project, for either lead:
#   ${TMPDIR}/triforge-monitors-<uid>/<checkout>-<cksum>/<session_id>.context
# one file per session (the session_id in the hook payload), so a new session
# starts at zero and two sessions in one checkout never share a count; files
# older than three days are pruned when a session's first file is written. The
# lead's vocabulary is cached beside it (lead-vocab), keyed on the roster and
# the registry.

# Worker marker (KTD9, R34): in a lease worker or persona (TRIFORGE_LEASE_WORKER
# set by _adapter_env) this hook does nothing and prints nothing — a worker's
# CLI may load the plugin's hooks, and they must not write state into its
# worktree. The input is still read, so a large PostToolUse payload never
# meets a closed pipe.
if [ -n "${TRIFORGE_LEASE_WORKER:-}" ]; then
  [ -t 0 ] || cat > /dev/null 2>&1 || true
  exit 0
fi

set -euo pipefail

_cm_on_exit() {
  local RC=$?
  [ "$RC" -eq 0 ] && return 0
  echo "context-monitor: WARNING hook crashed (rc=${RC}) — advisory only, tool call continues (ON_CRASH: ALLOW)" >&2
  exit 0
}
trap _cm_on_exit EXIT

# Read hook input from stdin (each lead delivers PostToolUse data as JSON on stdin)
HOOK_INPUT=$(cat)
CM_PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# _monitor_root — print the checkout this session works in: the nearest
# ancestor holding .git (where ops/roster.toml names the lead), else the
# working directory.
# _monitor_state_dir <root> — print that checkout's monitor state dir,
# created under a per-user base of mode 700; rc 1 when the base is not a
# directory this user owns (a planted symlink, another user's directory): the
# hook then stays inert. Both kept in step with tool-failure-monitor.sh.
_monitor_root() {
  local ROOT D
  ROOT=$(pwd -P 2>/dev/null) || ROOT=$PWD
  D=$ROOT
  while [ -n "$D" ] && [ "$D" != "/" ]; do
    if [ -e "$D/.git" ]; then
      ROOT=$D
      break
    fi
    D=${D%/*}
  done
  printf '%s\n' "$ROOT"
}
_monitor_state_dir() {
  local BASE D
  BASE="${TMPDIR:-/tmp}"
  BASE="${BASE%/}/triforge-monitors-$(id -u)"
  mkdir -p -m 700 "$BASE" 2>/dev/null || return 1
  if [ -L "$BASE" ] || [ ! -O "$BASE" ]; then
    return 1
  fi
  D="${BASE}/$(basename "$1")-$(printf '%s' "$1" | cksum | cut -d' ' -f1)"
  mkdir -p "$D" 2>/dev/null || return 1
  printf '%s\n' "$D"
}

CM_ROOT=$(_monitor_root)
if ! STATE_DIR=$(_monitor_state_dir "$CM_ROOT"); then
  echo "context-monitor: NOTE no private state directory under ${TMPDIR:-/tmp} (not owned by this user, or a symlink) — paralysis detection is off (R21)" >&2
  exit 0
fi

# The lead's vocabulary: "<name><TAB><read><TAB><action>", cached in
# lead-vocab under a key of the roster's and the registry's bytes; empty when
# the lead can't be resolved.
VOCAB_KEY="$( { cat "${CM_ROOT}/ops/roster.toml" "${CM_PLUGIN_ROOT}/scripts/lib/registry.sh" 2>/dev/null || true; } | cksum | cut -d' ' -f1)|${CM_PLUGIN_ROOT}"
VOCAB=""
VOCAB_HIT=0
if [ -f "${STATE_DIR}/lead-vocab" ]; then
  { IFS= read -r CACHED_KEY && IFS= read -r CACHED_VOCAB; } < "${STATE_DIR}/lead-vocab" 2>/dev/null || CACHED_KEY=""
  if [ "${CACHED_KEY:-}" = "$VOCAB_KEY" ]; then
    VOCAB=${CACHED_VOCAB:-}
    VOCAB_HIT=1
  fi
fi
if [ "$VOCAB_HIT" -eq 0 ]; then
  VOCAB=$( (
    # shellcheck source=/dev/null
    source "${CM_PLUGIN_ROOT}/scripts/invoke-external.sh" >/dev/null 2>&1 && lead_field name lead.tool_vocab_read lead.tool_vocab_action 2>/dev/null
  ) ) || VOCAB=""
  printf '%s\n%s\n' "$VOCAB_KEY" "$VOCAB" > "${STATE_DIR}/lead-vocab.tmp.$$" && mv -f "${STATE_DIR}/lead-vocab.tmp.$$" "${STATE_DIR}/lead-vocab"
fi
TAB=$(printf '\t')
LEAD_NAME=${VOCAB%%"$TAB"*}
VOCAB_REST=${VOCAB#*"$TAB"}
VOCAB_READ=${VOCAB_REST%%"$TAB"*}

# Classify the call: "<session><TAB><read|action><TAB><tool>". A
# "<tool>(read)" entry reads the call's command (tool_input.command: a string,
# or an argv list) and counts it as a read only when every command in it is a
# known reader with no write flag, no output redirection other than to
# /dev/null or a stream, and no substitution or subshell; anything it can't
# parse is an action.
PARSED=$(printf '%s' "$HOOK_INPUT" | CM_READ="$VOCAB_READ" python3 -c '
import json, os, re, shlex, sys

READERS = {"cat", "head", "tail", "less", "more", "grep", "egrep", "fgrep", "rg", "ag", "ls", "tree", "wc", "nl",
           "file", "stat", "du", "df", "pwd", "which", "type", "cut", "uniq", "diff", "cmp", "comm", "jq",
           "basename", "dirname", "realpath", "readlink", "column", "od", "xxd", "hexdump", "strings", "fd",
           "echo", "printf", "true", "cd", "find", "sed", "awk", "sort", "git"}
GIT_READS = {"status", "log", "show", "diff", "blame", "grep", "ls-files", "ls-tree", "rev-parse", "describe",
             "cat-file", "shortlog"}
FIND_WRITES = {"-delete", "-exec", "-execdir", "-ok", "-okdir", "-fprint", "-fprint0", "-fprintf", "-fls"}
SEPARATORS = {"|", "||", "&&", ";", "&", "|&", ";;"}
REDIRECTS = {">", ">>", ">|", "&>", "&>>", ">&"}
SAFE_TARGETS = {"/dev/null", "&1", "&2", "1", "2"}

def reads_only(cmd, depth=0):
    if isinstance(cmd, list):
        if len(cmd) >= 3 and os.path.basename(str(cmd[0])) in ("bash", "sh", "zsh") and str(cmd[1]) in ("-c", "-lc"):
            return reads_only(str(cmd[2]), depth + 1)
        cmd = " ".join(shlex.quote(str(w)) for w in cmd)
    if not isinstance(cmd, str) or not cmd.strip() or depth > 2 or "`" in cmd or "$(" in cmd:
        return False
    try:
        lex = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        toks = list(lex)
    except ValueError:
        return False
    segs, cur, i = [], [], 0
    while i < len(toks):
        t = toks[i]
        if t in SEPARATORS:
            segs.append(cur)
            cur = []
        elif t in REDIRECTS:
            target = toks[i + 1] if i + 1 < len(toks) else ""
            if t != ">&" and target not in SAFE_TARGETS:
                return False
            i += 1
        elif t in ("<", "<<", "<<<"):
            i += 1
        elif t in ("(", ")") or set(t) <= set("();<>|&"):
            return False
        else:
            cur.append(t)
        i += 1
    segs.append(cur)
    segs = [s for s in segs if s]
    if not segs:
        return False
    for s in segs:
        while s and re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", s[0]):
            s = s[1:]
        if not s:
            continue
        name, args = os.path.basename(s[0]), s[1:]
        if name in ("bash", "sh", "zsh") and len(args) >= 2 and args[0] in ("-c", "-lc"):
            if not reads_only(args[1], depth + 1):
                return False
            continue
        if name not in READERS:
            return False
        if name == "sed" and any(a.startswith("-i") or a.startswith("--in-place") for a in args):
            return False
        if name == "sort" and any(a.startswith("-o") or a.startswith("--output") for a in args):
            return False
        if name == "find" and any(a in FIND_WRITES for a in args):
            return False
        if name == "awk" and any(">" in a or "system" in a for a in args):
            return False
        if name == "git":
            while len(args) >= 2 and args[0] in ("-C", "-c"):
                args = args[2:]
            sub = [a for a in args if not a.startswith("-")]
            if not sub or sub[0] not in GIT_READS:
                return False
    return True

try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
if not isinstance(d, dict):
    d = {}
tool = str(d.get("tool_name") or "unknown")
sid = re.sub(r"[^A-Za-z0-9._-]", "_", str(d.get("session_id") or ""))[:80] or "session"
vocab = os.environ.get("CM_READ", "").split()
cls = "action"
if tool in vocab:
    cls = "read"
elif tool + "(read)" in vocab:
    ti = d.get("tool_input")
    if isinstance(ti, dict) and reads_only(ti.get("command")):
        cls = "read"
print(sid + "\t" + cls + "\t" + re.sub(r"\s", "_", tool)[:80])
' 2>/dev/null) || PARSED="session${TAB}action${TAB}unknown"
SESSION=${PARSED%%"$TAB"*}
PARSED_REST=${PARSED#*"$TAB"}
CLASS=${PARSED_REST%%"$TAB"*}

# R21/R44: a lead whose vocabulary maps nothing leaves the hook inert, said
# once per session.
if [ -z "$VOCAB_READ" ]; then
  if [ ! -f "${STATE_DIR}/${SESSION}.vocab-noted" ]; then
    : > "${STATE_DIR}/${SESSION}.vocab-noted"
    echo "context-monitor: NOTE the ${LEAD_NAME:-current} lead's tool vocabulary is empty or the lead could not be resolved (lead.tool_vocab_read in scripts/lib/registry.sh) — paralysis detection is off this session (R21, R44)" >&2
  fi
  exit 0
fi

STATE_FILE="${STATE_DIR}/${SESSION}.context"

# Initialize state file if it doesn't exist (a new session: prune old ones)
if [ ! -f "$STATE_FILE" ]; then
  find "$STATE_DIR" -type f -mtime +2 -delete 2>/dev/null || true
  cat > "$STATE_FILE" << 'EOF'
---
total_calls: 0
consecutive_reads: 0
last_write_at: 0
---
EOF
fi

# Read current state (POSIX-compatible — PCRE grep is unavailable on BSD/macOS)
TOTAL=$(sed -n 's/^total_calls: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
TOTAL="${TOTAL:-0}"
READS=$(sed -n 's/^consecutive_reads: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
READS="${READS:-0}"
LAST_WRITE=$(sed -n 's/^last_write_at: \([0-9]*\).*/\1/p' "$STATE_FILE" 2>/dev/null)
LAST_WRITE="${LAST_WRITE:-0}"

# Increment total
NEW_TOTAL=$((TOTAL + 1))

# A read extends the run; anything else (an action, or a tool the lead's
# vocabulary does not name) resets it, so unknown tools never raise a warning.
if [ "$CLASS" = "read" ]; then
  NEW_READS=$((READS + 1))
else
  NEW_READS=0
  LAST_WRITE=$NEW_TOTAL
fi

# Update state file (atomic write via temp file + mv)
TEMP_FILE="${STATE_FILE}.tmp.$$"
cat > "$TEMP_FILE" << EOF
---
total_calls: $NEW_TOTAL
consecutive_reads: $NEW_READS
last_write_at: $LAST_WRITE
---
EOF
mv "$TEMP_FILE" "$STATE_FILE"

# Analysis paralysis detection: 8+ consecutive read-only ops
if [ "$NEW_READS" -ge 8 ]; then
  echo "Context monitor: $NEW_READS consecutive read-only operations without writing code."
  echo "Consider: Are you stuck? Either write code, report a blocker, or spawn a subagent."
  echo "If researching intentionally, continue — but be aware of context usage."
fi

# Context usage warnings
if [ "$NEW_TOTAL" -ge 200 ]; then
  echo "Context monitor: CRITICAL — $NEW_TOTAL tool calls. Context window is likely near capacity."
  echo "Strongly consider: save state (ops/STATE.md), wrap session, spawn subagents for remaining work."
elif [ "$NEW_TOTAL" -ge 150 ]; then
  echo "Context monitor: WARNING — $NEW_TOTAL tool calls. Consider spawning subagents for intensive operations."
fi

# Always exit 0 — this hook is advisory only, never blocks
exit 0
