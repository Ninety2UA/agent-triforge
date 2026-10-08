#!/usr/bin/env bash
# Session Start — SessionStart hook
# Scans for existing state, pending tasks, and available context; runs the
# project bootstrap (triforge_bootstrap, scripts/lib/bootstrap.sh: ops/ +
# per-CLI files, skills refresh, Antigravity pack reinstall, Codex file moves,
# the plugin-root pointer) and prints its notices, one per step that acted.
# Provides orientation for the new session.
#
# Hook event: SessionStart
# Configuration: registered in hooks/hooks.json (plugin)
#
# ON_CRASH: ALLOW — a crash must never block the session (R14/G7): the EXIT trap
#   below turns any unexpected non-zero status (set -e / set -u) into a stderr
#   notice + exit 0, and every explicit exit path is `exit 0`. Degraded states
#   are reported as notices, never as exit codes.
# Exit codes: 0 ok · 2 hook deny (never used by Triforge handlers) · 64 usage ·
#   66 no-input · 69 unavailable · 70 internal · 80 degraded (documented only —
#   Triforge handlers always return 0).
# Hook stdout must never look like JSON: no stdout line may start with `{`
#   (Claude Code ≥ 2.1.246 rejects hook stdout that parses as JSON — D-031c).
#   Audited 2026-10-01: every stdout line is prose ("Multi-agent framework
#   ready.", "session-start: …", "Roster …", "WARNING: …", "Tip: …",
#   "Lead workflows: …");
#   every external-CLI capture (claude --version here; agy plugin list / agy
#   agents inside triforge_bootstrap) is consumed and never echoed — the floor
#   warning prints only the X.Y.Z digits parsed out of it — and each line
#   triforge_bootstrap prints starts with the "session-start: " prefix this hook
#   passes it, control characters already dropped. Re-audited 2026-10-07
#   (Phase 3 round 4, B8): the orientation is printed with printf %s, never %b,
#   and every value read from disk or the environment (roster pins, paths, the
#   loader's error) passes _ss_prose and sits behind fixed prose.
# Bash 3.2 compatible (macOS /bin/bash): no associative arrays, no mapfile, no
#   "${arr[@]}" expansion of a possibly-empty array under set -u.

# Worker marker (KTD9, R34): in a lease worker or persona (TRIFORGE_LEASE_WORKER
# set by _adapter_env) this hook does nothing and prints nothing — a worker's
# CLI may load the plugin's hooks, and they must not write state into its
# worktree.
if [ -n "${TRIFORGE_LEASE_WORKER:-}" ]; then
  exit 0
fi

set -euo pipefail

_ss_on_exit() {
  local RC=$?
  [ "$RC" -eq 0 ] && return 0
  echo "session-start: WARNING hook crashed (rc=${RC}) — session continues; bootstrap steps after the crash did not run (ON_CRASH: ALLOW)" >&2
  echo "Multi-agent framework ready (session-start hook degraded — see stderr)."
  exit 0
}
trap _ss_on_exit EXIT

# The project anchor: the nearest directory, from the session's working
# directory up, holding a .git entry (where _lead_roster_path and the lease
# helpers put ops/), else the working directory. The hook runs there, as
# triforge_bootstrap does, so a session
# opened in a monorepo subdirectory reads and writes the one ops/, roster and
# runtime state the helpers use. Only the instruction-file notices (R40) and
# triforge_bootstrap's warning about a 3.x roster left in a subdirectory look
# at the directory the session started in: Claude Code reads CLAUDE.md and
# AGENTS.md from there, and the warning walks up from it (the bootstrap is
# called from there and anchors itself). Inline, not the helper's
# _lead_roster_path: it must work when the helper does not load.
SS_START_DIR=$(pwd -P 2>/dev/null || pwd)
# The instruction-file library (R9, R40) from this hook's own tree, sourced on
# its own for the upgrade notices below, so they hold when the full loader
# fails; found here, before the hook leaves the directory a relative path to
# this file starts from.
SS_INSTR_LIB=""
SS_HOOK_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." 2>/dev/null && pwd -P) || SS_HOOK_ROOT=""
if [ -n "$SS_HOOK_ROOT" ]; then
  SS_INSTR_LIB="${SS_HOOK_ROOT}/scripts/lib/instructions.sh"
fi
SS_ANCHOR=$SS_START_DIR
SS_D=$SS_START_DIR
while [ -n "$SS_D" ]; do
  if [ -e "${SS_D}/.git" ] || [ -L "${SS_D}/.git" ]; then
    SS_ANCHOR=$SS_D
    break
  fi
  if [ "$SS_D" = "/" ]; then
    break
  fi
  SS_D=${SS_D%/*}
  if [ -z "$SS_D" ]; then SS_D=/; fi
done
case "${CLAUDE_PLUGIN_ROOT:-}" in
  ""|/*) ;;
  *) CLAUDE_PLUGIN_ROOT="${SS_START_DIR}/${CLAUDE_PLUGIN_ROOT}" ;;   # a relative root names the start directory's child
esac
cd "$SS_ANCHOR" 2>/dev/null || SS_ANCHOR=$SS_START_DIR

# A home directory is not a project (Phase 3 round 3, R1): when the anchor is
# the home directory or contains it (a session opened in ~, or below a home
# directory that is itself a repository), the hook writes nothing there. The
# bootstrap, the runtime file, enrollment and the .claude cleanup are skipped,
# and one standing WARNING says why: .claude, .codex and the rest of a home
# directory are each CLI's user-tier config. Inline, like the anchor, and like
# the bootstrap's _tb_home_anchor compared by filesystem identity (test -ef),
# never by spelling (Phase 3 round 4, B1): bash's pwd -P keeps the case the
# shell was handed, so on a case-insensitive volume /users/me is HOME too.
SS_AT_HOME=""
SS_HOME_P=""
if [ -n "${HOME:-}" ]; then
  SS_HOME_P=$(cd "$HOME" 2>/dev/null && env pwd -P 2>/dev/null || true)
fi
# _ss_home_or_above <dir> — 0 when <dir> is the home directory or one of its
# ancestors (test -ef against the physical HOME and each directory above it);
# 1 otherwise, or when HOME does not resolve. The instruction-file notices
# below use it too: a file at that level is read for every project under it.
_ss_home_or_above() {
  local D=$SS_HOME_P
  while [ -n "$D" ]; do
    if [ "$1" -ef "$D" ]; then
      return 0
    fi
    if [ "$D" = "/" ]; then
      return 1
    fi
    D=${D%/*}
    if [ -z "$D" ]; then D=/; fi
  done
  return 1
}
if _ss_home_or_above "$SS_ANCHOR"; then
  SS_AT_HOME=yes
fi

# _ss_claude_dir — 0 when .claude is a real directory of the project (not a
# symlink, not a file): only then does the hook touch anything under it. A
# .claude linked elsewhere holds another place's files.
_ss_claude_dir() {
  [ -d .claude ] && [ ! -L .claude ] || return 1
}

# The orientation message is lines joined by real newlines and printed with
# printf %s, so no escape sequence in it is ever interpreted, and every piece
# that carries data (a path, a model pin read from the roster, a loader's
# error, a bootstrap notice) goes through _ss_prose first (Phase 3 round 4,
# B8): a newline or an escape in a value can't make a line of its own, and no
# stdout line can start with "{".
SS_NL='
'
# _ss_prose <text> — the text as one line: control characters dropped.
_ss_prose() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'
}

# SS_PY_PRELUDE — python: the first lines of every program this hook runs.
# They run from the project root, and python3 -c puts the working directory
# first on sys.path: these lines drop it (and every relative entry) before
# anything is imported, so a tomllib.py or json.py planted there never runs
# (Phase 6, S1). SS_READ_PY — python: the prelude, then read_regular(path[,
# text]), the bytes of a regular file, opened O_NONBLOCK: a FIFO planted at
# ops/roster.toml or ops/leases.toml fails at once instead of blocking session
# start (Phase 3 round 5, G3). The same lines as _PY_PRELUDE and
# _READ_REGULAR_PY in scripts/lib/common.sh, inline because this hook also
# runs without the helper; SELF-27 compares the copies.
SS_PY_PRELUDE='
import os, sys
try:
    _tf_here = os.path.realpath(os.getcwd())
except OSError:
    _tf_here = None
sys.path[:] = [_p for _p in sys.path if os.path.isabs(_p) and os.path.realpath(_p) != _tf_here]
del _tf_here
'
SS_READ_PY="${SS_PY_PRELUDE}"'
def read_regular(p, text=False):
    import os, stat
    fd = os.open(p, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
    with os.fdopen(fd, "r" if text else "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            raise OSError("not a regular file: " + p)
        return f.read()
'

# _ss_tmp_ok <dir> — 0 when no other user can rename entries in <dir>: it is
# owned by this user or root, and has no group or other write unless the
# sticky bit is set — the rule monitors.py, coordinate.sh and the lease root
# apply (Phase 3 round 4, B5). In a shared directory without the sticky bit a
# second user could move a private temp dir aside and put one holding links
# in its place, and the hook's next redirect would follow them.
_ss_tmp_ok() {
  [ -d "$1" ] || return 1
  if [ ! -O "$1" ] && [ -z "$(find -H "$1" -maxdepth 0 -user 0 2>/dev/null)" ]; then
    return 1
  fi
  [ -z "$(find -H "$1" -maxdepth 0 \( -perm -020 -o -perm -002 \) ! -perm -1000 2>/dev/null)" ]
}

# _ss_claude_private — 0 when the project's .claude can hold the hook's private
# temp dirs (Phase 3 round 5, G2): a real directory (not a symlink) owned by
# this user, with no group or other write unless the sticky bit is set, in a
# project directory that passes _ss_tmp_ok. Then no other user can rename the
# temp dir, or .claude itself, and plant links for the hook's redirects to
# follow. The hook still reaches the temp dir by its path afterwards (bash has
# no openat), so a process of this same user could swap it in between: a
# same-user residual, like every other path this user's own processes can
# change.
_ss_claude_private() {
  [ -d "${SS_ANCHOR}/.claude" ] && [ ! -L "${SS_ANCHOR}/.claude" ] && [ -O "${SS_ANCHOR}/.claude" ] || return 1
  [ -z "$(find "${SS_ANCHOR}/.claude" -maxdepth 0 \( -perm -020 -o -perm -002 \) ! -perm -1000 2>/dev/null)" ] || return 1
  _ss_tmp_ok "$SS_ANCHOR"
}

# _ss_private_tmp — print a private temp dir (mktemp -d: a random name, mode
# 0700) under TMPDIR when no other user can rename entries in it (_ss_tmp_ok,
# B5), else under the project's own .claude (at the anchor, wherever the hook
# stands) when no other user can rename entries there either
# (_ss_claude_private, G2); .claude is created here, without group or other
# write, when it is missing. On failure, a nonzero rc and one line saying why (or
# mktemp's error): the caller skips the step that needed the temp dir and
# shows that line in its notice.
_ss_private_tmp() {
  local T="${TMPDIR:-/tmp}"
  if _ss_tmp_ok "$T" && mktemp -d "${T}/triforge-session-start.XXXXXX" 2>/dev/null; then
    return 0
  fi
  if [ -n "$SS_AT_HOME" ]; then
    echo "no private temp dir: TMPDIR ${T} is shared, and a home directory's .claude is never used"
    return 1   # never under a home directory's .claude (R1)
  fi
  if [ ! -e "${SS_ANCHOR}/.claude" ] && [ ! -L "${SS_ANCHOR}/.claude" ]; then
    # the user's umask, with group and other write taken off it
    ( umask "$(printf '%04o' $(( 8#$(umask) | 8#022 )))" && mkdir "${SS_ANCHOR}/.claude" ) 2>/dev/null || true
  fi
  if ! _ss_claude_private; then
    echo "no private temp dir: TMPDIR ${T} is shared (another user could rename entries in it), and so is ${SS_ANCHOR}/.claude or the project directory (a symlink, another user's, or group or other writable without the sticky bit)"
    return 1
  fi
  mktemp -d "${SS_ANCHOR}/.claude/triforge-session-start.XXXXXX" 2>&1
}

# Clean stale state files from previous sessions (the context monitor keeps
# its state under TMPDIR now; this removes a copy an older version left).
if [ -z "$SS_AT_HOME" ] && _ss_claude_dir; then
  rm -f .claude/context-monitor.local.md
fi

# Timeout binary (GNU coreutils `timeout`, or `gtimeout` on macOS). The
# optional-CLI version probes and `claude --version` below run under it, or
# under a watchdog without one (_ss_bounded), so a CLI that never answers is
# given up on either way.
# triforge_bootstrap and _cursor_bin find their own: without one the agy pack
# check is skipped and the Cursor `agent` probes refuse (fail-closed, as
# invoke-external.sh is — a hung CLI must not stall session start), and the
# warning is appended to the orientation message.
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
[ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="gtimeout"
TIMEOUT_MISSING_WARNING=""
if [ -z "$TIMEOUT_BIN" ]; then
  TIMEOUT_MISSING_WARNING="WARNING: neither \`timeout\` nor \`gtimeout\` found on PATH — invoke-external.sh is fail-closed and will refuse to run Antigravity/Codex invocations (this hook also skipped its agy and cursor probes). On macOS, install with: brew install coreutils"
fi

# _ss_bounded <seconds> <dir> <command…> — the command's stdout, the command
# given up on after <seconds>: under the timeout binary when there is one, and
# on a host without one (stock macOS) under a watchdog — the command runs in
# the background, a second background subshell kills it when the time is up,
# and the watchdog is killed as soon as the command returns. The answer
# travels through a file in <dir>, a private temp dir the caller made
# (_ss_private_tmp: never one other users can rename entries in, B5, G2) and
# this removes; the watchdog's stdio is /dev/null, so nothing a killed command
# leaves running holds the caller's command substitution open; each `wait`
# swallows bash's "Terminated" or "Killed" line. Giving up is a SIGTERM, then
# a SIGKILL 2 s later if the command is still running (`-k 2s`, or the
# watchdog's second kill), so the call returns within <seconds> + 2 s even
# when the command ignores SIGTERM. timeout sends its SIGKILL to its whole
# process group, itself included; the braces around it swallow the "Killed"
# line bash prints for that.
_ss_bounded() {
  local SECS="$1" OUT_DIR="$2" OUT CMD_PID DOG_PID
  shift 2
  if [ -n "$TIMEOUT_BIN" ]; then
    { "$TIMEOUT_BIN" -k 2s "${SECS}s" "$@"; } 2>/dev/null || true
    return 0
  fi
  OUT="${OUT_DIR}/out"
  "$@" </dev/null >"$OUT" 2>/dev/null &
  CMD_PID=$!
  ( sleep "$SECS"; kill "$CMD_PID" && sleep 2 && kill -9 "$CMD_PID" || true ) </dev/null >/dev/null 2>&1 &
  DOG_PID=$!
  wait "$CMD_PID" 2>/dev/null || true
  kill "$DOG_PID" 2>/dev/null || true
  wait "$DOG_PID" 2>/dev/null || true
  cat "$OUT" 2>/dev/null || true
  rm -rf "$OUT_DIR"
}

# _ss_cli_version <seconds> <binary> — the first line the binary prints for
# --version, or for -V when --version prints nothing. Each call goes through
# _ss_bounded (given up on after <seconds>, killed 2 s later if it ignores
# SIGTERM); without a timeout binary each call gets a private temp dir of its
# own, since _ss_bounded removes the one it is given. Nothing when neither
# call answers; a call with no private temp dir for it is skipped.
_ss_cli_version() {
  local SECS="$1" BIN="$2" FLAG DIR V=""
  for FLAG in --version -V; do
    DIR=""
    if [ -n "$TIMEOUT_BIN" ] || DIR=$(_ss_private_tmp); then
      V=$(_ss_bounded "$SECS" "$DIR" "$BIN" "$FLAG" | head -1 || true)
    fi
    if [ -n "$V" ]; then
      break
    fi
  done
  printf '%s' "$V"
}

# _ss_run — the rest of this hook, from the project bootstrap to the orientation
# message, as one function: it runs inside the subshell that sources the helper
# (the block at the end of this file) or, when the helper does not load, in the
# hook's own shell with SS_HELPER empty. The body is the hook's linear flow and
# stays at column 0.
_ss_run() {

# Bootstrap (KTD11, R37): the ops/ skeleton, the .agents/skills refresh, the
# Antigravity agent pack, the per-CLI files and the plugin-root pointer are
# triforge_bootstrap's (scripts/lib/bootstrap.sh), the same helper at-setup,
# at-build and at-review call, so a project whose hooks never ran (a Codex
# lead before the user trusts them) is set up the same way. It runs first,
# so the state checks below see what it wrote, and in this shell: a Cursor
# binary its _cursor_bin call resolves stays exported (TRIFORGE_CURSOR_BIN),
# so the detection loop below looks it up instead of probing again. Its
# notices, one per line on stderr with this hook's "session-start: " prefix,
# are collected in SS_BOOT_LOG and printed with the migration notices; its
# rc (0, or 80 when a step degraded) adds nothing the notices do not say.
# Without the helper nothing is bootstrapped, and SS_HELPER_NOTICE says so.
# It is called from the start directory, so its walk up from there finds a
# 3.x roster left in a subdirectory; the log is opened here first, at the
# anchor, which a relative TMPDIR is relative to.
SS_BOOT_LOG=""
if [ -n "$SS_HELPER" ] && [ -z "$SS_AT_HOME" ]; then
  SS_BOOT_LOG="${SS_HELPER_TMP}/bootstrap"
  { cd "$SS_START_DIR" 2>/dev/null || true
    triforge_bootstrap --prefix "session-start: " || true
    cd "$SS_ANCHOR" 2>/dev/null || true; } 2> "$SS_BOOT_LOG" || true
fi

# Optional-CLI detection (roster tier): presence + version for every optional
# member of the CLI registry (cli_table optional — opencode / kimi / cursor /
# devin / grok today), written to .claude/roster-detected.local.md (runtime state,
# regenerated each session start; .claude/*.local.md is gitignored).
# Line format: cli|version|detected-date, plus one interactive=yes|no signal
# line the enrollment unit keys off, plus `<cli>_bin=<resolved path>` for a
# member whose registry entry names a resolver (cursor: `cursor_bin=` from
# _cursor_bin, since the binary that answered may be an `agent`, not the name).
# [ -t 0 ] at hook time is best-effort — hooks often run with stdin piped —
# documented as such; the enrollment branch treats "no" as headless and enrolls
# shipped defaults silently. With no helper loaded nothing is detected, no
# file is written, and SS_HELPER_NOTICE says so — whether the loader failed or
# CLAUDE_PLUGIN_ROOT named no loader at all (unset, or a root without
# scripts/invoke-external.sh). The content is built here and written once,
# through the helper's _tb_write: an exclusive temp file renamed into place,
# refused when .claude is a symlink or a file, so neither a link planted at a
# temp name nor a linked .claude can redirect the write.
ROSTER_DETECTED=".claude/roster-detected.local.md"
ROSTER_DETECTED_NOTICE=""
OPTIONAL_DETECTED_COUNT=0
DETECTED_OPTIONAL=()
# The detected CLIs whose registry entry asks for consent (devin, R24),
# space-padded: " devin ".
SS_CONSENT_CLIS=" "
if [ -t 0 ]; then INTERACTIVE_SIGNAL="yes"; else INTERACTIVE_SIGNAL="no"; fi
SS_DETECTED="<!-- runtime state: optional roster CLI detection, regenerated each session start -->
interactive=${INTERACTIVE_SIGNAL}"
SS_OPTIONAL_ROWS=""
if [ -n "$SS_HELPER" ]; then
  SS_OPTIONAL_ROWS=$(cli_table optional binary consent resolver 2>/dev/null || true)
fi
# One registry read for the tier (cli_table: name, binary, consent, resolver
# per line); each member's binary is then resolved from its own row
# (_registry_binary, no further read) and probed with command -v before
# anything else runs. resolver stays last: it is empty for most CLIs, and
# IFS=$'\t' folds an empty middle field into the next (consent always prints
# true or false). The rows arrive on fd 3, not stdin, so a version probe
# that reads its stdin can't consume them.
while IFS=$'\t' read -r -u 3 CLI_NAME CLI_BIN CLI_CONSENT CLI_RESOLVER; do
  [ -n "$CLI_NAME" ] || continue
  CLI_BIN=$(_registry_binary "$CLI_NAME" "$CLI_BIN" "$CLI_RESOLVER" 2>/dev/null || true)
  [ -n "$CLI_BIN" ] || continue
  if command -v "$CLI_BIN" >/dev/null 2>&1; then
    # Version capture is best-effort (_ss_cli_version): --version first, -V
    # fallback, each given up on after 10 s and killed 2 s later if it
    # ignores SIGTERM, timeout binary or not; a CLI that answers neither is
    # still recorded as present.
    CLI_VERSION=$(_ss_cli_version 10 "$CLI_BIN" || true)
    [ -z "$CLI_VERSION" ] && CLI_VERSION="unknown"
    SS_DETECTED="${SS_DETECTED}
${CLI_NAME}|${CLI_VERSION}|$(date +%Y-%m-%d)"
    if [ -n "$CLI_RESOLVER" ]; then
      SS_DETECTED="${SS_DETECTED}
${CLI_NAME}_bin=${CLI_BIN}"
    fi
    OPTIONAL_DETECTED_COUNT=$((OPTIONAL_DETECTED_COUNT + 1))
    DETECTED_OPTIONAL+=("$CLI_NAME")
    if [ "$CLI_CONSENT" = true ]; then SS_CONSENT_CLIS="${SS_CONSENT_CLIS}${CLI_NAME} "; fi
  fi
done 3<<SS_OPTIONAL_EOF
${SS_OPTIONAL_ROWS}
SS_OPTIONAL_EOF
if [ -n "$SS_HELPER" ] && [ -z "$SS_AT_HOME" ]; then
  SS_W_RC=0
  printf '%s\n' "$SS_DETECTED" | _tb_write replace . "$ROSTER_DETECTED" > /dev/null || SS_W_RC=$?
  if [ "$SS_W_RC" -eq 3 ]; then
    # .claude, the file's only directory, is a symlink or a file. A standing
    # state (it repeats until fixed), so no "session-start:" prefix.
    ROSTER_DETECTED_NOTICE="WARNING: ${ROSTER_DETECTED} not written: .claude is a symlink or not a directory, so the file would land outside this project, and the hook writes only inside it."
  fi
fi

# First-detection enrollment trigger (R37). For each optional CLI detected THIS
# session with no [members.<cli>] entry yet:
#   headless (interactive=no) -> silently enroll its shipped default now (a hook
#     cannot prompt); the lease layer records the resolved model at dispatch.
#     A consent CLI (devin, R24) is the exception: roster_enroll_member never
#     enrolls it headless (rc 20), and the interactive notice says it needs the
#     user's consent.
#   interactive (=yes)        -> emit an orientation line pointing at /at-setup.
# All writes go through the single-writer roster writer (roster_write_member) in
# the helper sourced above — never a hand-rolled write here. Fast: headless
# enrollment does no live auth probe; each helper call is tomllib-only.
ENROLLMENT_NOTICES=""
if [ -n "$SS_HELPER" ] && [ -z "$SS_AT_HOME" ] && [ "${#DETECTED_OPTIONAL[@]}" -gt 0 ]; then
  for CLI_NAME in "${DETECTED_OPTIONAL[@]}"; do
    CLI_CONSENT=false
    case "$SS_CONSENT_CLIS" in *" ${CLI_NAME} "*) CLI_CONSENT=true ;; esac
    # Headless never enrolls a consent CLI (roster_enroll_member returns 20
    # and writes nothing), so it is skipped before any roster read.
    if [ "$INTERACTIVE_SIGNAL" = "no" ] && [ "$CLI_CONSENT" = true ]; then
      continue
    fi
    ENROLL_HAS_RC=0
    roster_has_member "$CLI_NAME" || ENROLL_HAS_RC=$?
    [ "$ENROLL_HAS_RC" -eq 0 ] && continue   # already enrolled or declined — never re-ask (AE6)
    [ "$ENROLL_HAS_RC" -eq 2 ] && continue   # roster unparseable — leave it to resolve_role to surface loudly
    if [ "$INTERACTIVE_SIGNAL" = "no" ]; then
      # A refused or failed write (rc 6: ops/ or the roster is a symlink or not
      # a regular file; rc 45: this shell may not write the roster) gets one
      # standing line naming the refusal, its first line sanitized (G6); rc 30
      # is OpenCode V2, which is never enrolled and says so in at-setup.
      ENROLL_RC=0
      ENROLL_ERR=$(roster_enroll_member "$CLI_NAME" headless 2>&1 >/dev/null) || ENROLL_RC=$?
      if [ "$ENROLL_RC" -ne 0 ] && [ "$ENROLL_RC" -ne 30 ]; then
        ENROLL_ERR=$(printf '%s\n' "$ENROLL_ERR" | grep -v '^[[:space:]]*$' | head -1 | cut -c1-300 || true)
        ENROLLMENT_NOTICES="${ENROLLMENT_NOTICES}${SS_NL}$(_ss_prose "WARNING: ${CLI_NAME} was detected but not enrolled (rc ${ENROLL_RC}): ${ENROLL_ERR:-no reason given}")"
      fi
    elif [ "$CLI_CONSENT" = true ]; then
      # A consent CLI (devin, R24) never enrolls headless: say so.
      ENROLLMENT_NOTICES="${ENROLLMENT_NOTICES}${SS_NL}$(_ss_prose "New optional CLI detected: ${CLI_NAME} (unenrolled). It needs your consent before it joins the roster, so it is never enrolled on its own. Run /at-setup to enroll it.")"
    else
      ENROLL_DEF=$(roster_member_default "$CLI_NAME" 2>/dev/null || true)
      ENROLLMENT_NOTICES="${ENROLLMENT_NOTICES}${SS_NL}$(_ss_prose "New optional CLI detected: ${CLI_NAME} (unenrolled). Run /at-setup to enroll, or it enrolls with its shipped default (${ENROLL_DEF}) on first headless use.")"
    fi
  done
fi

# Enrolled count = [members.*] entries in ops/roster.toml when present
# (tolerant: a malformed roster must not break session start — it reports 0
# here and resolve_role raises the loud parse error at first use).
ENROLLED_COUNT=0
if [ -f "ops/roster.toml" ]; then
  ENROLLED_COUNT=$(python3 -c "${SS_READ_PY}
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print(0); sys.exit(0)
try:
    data = tomllib.loads(read_regular('ops/roster.toml').decode('utf-8'))
    members = data.get('members', {})
    print(sum(1 for v in members.values() if isinstance(v, dict)) if isinstance(members, dict) else 0)
except Exception:
    print(0)
" 2>/dev/null || echo 0)
fi
case "$ENROLLED_COUNT" in ''|*[!0-9]*) ENROLLED_COUNT=0 ;; esac   # a count, nothing else, reaches the orientation

# Roster pin drift (informational): persisted [members.*].model / [roles.*].model
# values that differ from the shipped defaults. An upgraded project keeps
# whatever its roster carries — a pin is never rewritten here — so one line per
# differing pin points at /at-setup. The shipped defaults are read from the two
# literals the helper exports — the CLI registry (_TRIFORGE_CLIS_PY,
# scripts/lib/registry.sh: per-CLI model) and the role table (_ROLE_DEFAULTS_PY,
# scripts/lib/roster.sh: role -> cli) — handed to python as environment
# variables and exec'd, so this hook carries no copy (validate-versions.sh
# check 3 fails one that creeps back). An effort variant of the default is NOT
# drift: the agy `(Low|Medium|High)` suffix and the Cursor
# `-low|-medium|-high|-xhigh` suffix are effort controls (KTD3, KTD6), so both
# sides are compared with that suffix stripped. Tolerant: a malformed roster
# prints nothing (resolve_role raises the loud error later); skipped without
# the helper.
ROSTER_DRIFT_NOTICES=""
if [ -n "$SS_HELPER" ] && [ -f "ops/roster.toml" ]; then
  ROSTER_DRIFT_NOTICES=$(TRIFORGE_CLIS_PY="${_TRIFORGE_CLIS_PY:-}" TRIFORGE_ROLE_DEFAULTS_PY="${_ROLE_DEFAULTS_PY:-}" python3 -c "$SS_READ_PY"'
import os, re, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
ns = {}
exec(os.environ["TRIFORGE_CLIS_PY"], ns)
exec(os.environ["TRIFORGE_ROLE_DEFAULTS_PY"], ns)
SHIPPED = {cli: e["model"] for cli, e in ns["CLIS"].items() if e["model"]}
ROLE_CLI = {role: d["cli"] for role, d in ns["DEFAULTS"].items()}
def norm(cli, model):
    if cli == "antigravity":
        return re.sub(r"\s*\((Low|Medium|High)\)\s*$", "", model)
    if cli == "cursor":
        return re.sub(r"-(low|medium|high|xhigh)$", "", model)
    return model
# a value read from the roster, as one line (B8): a TOML string may hold a
# newline, and the hook prints every line it gets
def one(value):
    return re.sub(r"[\x00-\x1f\x7f]", "", str(value))[:200]
try:
    data = tomllib.loads(read_regular("ops/roster.toml").decode("utf-8"))
    lines = []
    members = data.get("members", {})
    if isinstance(members, dict):
        for name in sorted(members):
            entry = members[name]
            if not isinstance(entry, dict) or name not in SHIPPED:
                continue
            model = str(entry.get("model", "") or "")
            if model and norm(name, model) != norm(name, SHIPPED[name]):
                lines.append("Roster pin differs from the shipped default: members.%s.model=%s (shipped: %s) — run /at-setup to re-enroll, or edit ops/roster.toml" % (one(name), one(model), one(SHIPPED[name])))
    roles = data.get("roles", {})
    if isinstance(roles, dict):
        for name in sorted(roles):
            entry = roles[name]
            if not isinstance(entry, dict):
                continue
            cli = str(entry.get("cli", "") or ROLE_CLI.get(name, ""))
            model = str(entry.get("model", "") or "")
            shipped = SHIPPED.get(cli)
            if model and shipped is not None and norm(cli, model) != norm(cli, shipped):
                lines.append("Roster pin differs from the shipped default: roles.%s.model=%s (shipped: %s) — run /at-setup roles to re-default" % (one(name), one(model), one(shipped)))
    for line in lines:
        print(line)
except Exception:
    pass
' 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# Upgrade notices (R40). Triforge 4 ships AGENTS.md only — no CLAUDE.md, no
# template for one. Claude Code reads AGENTS.md from 2.1.277, and only while no
# CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md exists in the working
# directory or above it (the user-tier ~/.claude/CLAUDE.md does not count); a
# CLAUDE.md that imports it (`@AGENTS.md`) loads it on every build. Four
# states leave a Claude lead without it, and each gets one line:
#   floor   `claude --version` below 2.1.277
#   stale   ./CLAUDE.md or ./.claude/CLAUDE.md is a 3.x copy of the retired
#           templates/CLAUDE.md that does not import AGENTS.md
#   own     ./CLAUDE.md, ./.claude/CLAUDE.md or ./CLAUDE.local.md is the
#           user's own file (no 3.x copy) and nothing in the chain imports
#           the project's AGENTS.md: the line names at-setup, which offers
#           the import and asks first
#   above   a CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md in a directory
#           above the project, with no import of the project's AGENTS.md
#           anywhere in the chain: the line offers a CLAUDE.md in the project
#           first (it loads AGENTS.md for this project only), then the import
#           into that file, which every project under it loads too, then
#           removing the file; for a file in HOME or a directory above it
#           (_ss_home_or_above), the project's own CLAUDE.md alone: that file
#           is read for every project under it, and the writers refuse it;
#           for a file with no import line that reads back as the project's
#           (the import column "-": the path down to the project holds
#           whitespace or a #, where an import path ends, starts with ~,
#           which an import reads as HOME, or holds another character Claude
#           Code does not read as written there), the project's own
#           CLAUDE.md or removing the file; the writer refuses that import
# A session started in HOME or a directory above it gets none of the file
# lines and no tip (SS_NO_PROJECT): that is no project, as the home-directory
# warning says, and every file there is one the writers refuse.
# These describe a standing state, not a one-time action: they print on every
# session start until the state is fixed, and so — like the roster-pin and
# timeout lines — carry no "session-start:" prefix (that prefix marks a step
# that acted once; SELF-08 counts it for idempotence). Nothing here edits a
# file: each line names the edit and leaves it to the user. The files are
# found by instruction_files_detect (scripts/lib/instructions.sh, sourced
# here on its own, so the notices hold when the full loader fails).
CLAUDE_FLOOR="2.1.277"
INSTRUCTION_NOTICES=""
# These notices are about the directory the session started in (see the
# anchor at the top); the hook goes back to the anchor after the tip below.
cd "$SS_START_DIR" 2>/dev/null || true

# _ss_xyz <text> — the first X.Y.Z in the text, or nothing.
_ss_xyz() {
  printf '%s\n' "$1" | LC_ALL=C grep -Eo '[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}' | head -1 || true
}

# _ss_xyz_key <X.Y.Z> — one integer that orders versions (fields ≤ 6 digits).
_ss_xyz_key() {
  local A B C
  IFS=. read -r A B C <<SS_XYZ_EOF
$1
SS_XYZ_EOF
  echo $(( 10#$A * 1000000000000 + 10#$B * 1000000 + 10#$C ))
}

# Floor. The answer is read with a 10 s bound (12 s for a `claude` that
# ignores SIGTERM: SIGKILL follows 2 s later), timeout binary or not — a hung
# `claude` must not stall session start. A missing `claude`, one that does not
# answer in time, or an answer with no X.Y.Z in it warns about nothing.
if command -v claude >/dev/null 2>&1; then
  SS_CLAUDE_XYZ=""
  SS_BOUND_DIR=""
  if [ -n "$TIMEOUT_BIN" ] || SS_BOUND_DIR=$(_ss_private_tmp); then
    SS_CLAUDE_XYZ=$(_ss_xyz "$(_ss_bounded 10 "$SS_BOUND_DIR" claude --version | head -1 || true)")
  else
    # no timeout binary and no private temp dir for the watchdog's answer
    # (G2): the check is skipped, and the line says why
    INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}${SS_NL}$(_ss_prose "WARNING: the Claude Code version check was skipped (${SS_BOUND_DIR}).")"
  fi
  if [ -n "$SS_CLAUDE_XYZ" ] && [ "$(_ss_xyz_key "$SS_CLAUDE_XYZ")" -lt "$(_ss_xyz_key "$CLAUDE_FLOOR")" ]; then
    INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}${SS_NL}WARNING: Claude Code ${SS_CLAUDE_XYZ} is below Triforge's floor ${CLAUDE_FLOOR}, the first build that reads AGENTS.md — Triforge's only instruction file, which older builds do not read. Update Claude Code (\`claude update\`)."
  fi
fi

# The instruction files: one read-only pass of instruction_files_detect over
# the start directory, every directory above it up to / and the user tier, a
# tab-separated line each (kind, where, state, path, the import line that
# would load this project's AGENTS.md from that file). The user-tier
# ~/.claude/CLAUDE.md is a "user" line, compared by identity, never "above".
# One import of the project's AGENTS.md anywhere in the chain (the user-tier
# file included: Claude Code always loads it) loads it, so it silences the
# own and above lines; a 3.x copy without the import is named whatever else
# imports it, since its Triforge text is stale. Only CLAUDE.md and
# .claude/CLAUDE.md are fingerprinted (the 3.x template was never a
# CLAUDE.local.md). A file that is not a readable regular file (a FIFO, a
# dangling link) is "unreadable" and named in no line. A library that cannot
# load or run (no python3) costs these lines and gets one WARNING instead.
SS_CHAIN_IMPORTS=""
SS_OWN_NOTICES=""
SS_ABOVE_NOTICES=""
SS_FOUND=""
SS_FOUND_RC=0
# A start directory that is HOME or above it is no project: no file is checked
# there and no tip printed, since each line would name a file there, which
# every project under it reads and the writers refuse. The anchor is then
# HOME or above it too, so the home-directory warning below says it all.
SS_NO_PROJECT=""
if _ss_home_or_above "$SS_START_DIR"; then
  SS_NO_PROJECT=yes
fi
# shellcheck source=/dev/null
if [ -n "$SS_NO_PROJECT" ]; then
  :
elif [ -f "$SS_INSTR_LIB" ] && source "$SS_INSTR_LIB" >/dev/null 2>&1; then
  SS_FOUND=$(instruction_files_detect "$SS_START_DIR" 2>/dev/null) || SS_FOUND_RC=$?
else
  SS_FOUND_RC=69
fi
if [ "$SS_FOUND_RC" -ne 0 ]; then
  INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}${SS_NL}$(_ss_prose "WARNING: the instruction-file check did not finish (instruction_files_detect in ${SS_INSTR_LIB}, rc ${SS_FOUND_RC}; it needs python3), so the CLAUDE.md and 3.x template notices may be missing this session.")"
fi
while IFS=$'\t' read -r SS_KIND SS_WHERE SS_STATE SS_FILE SS_IMPORT; do
  case "$SS_KIND" in
    CLAUDE.md|.claude/CLAUDE.md|CLAUDE.local.md) ;;
    *) continue ;;
  esac
  case ",${SS_STATE}," in
    *,unreadable,*) continue ;;
    *,imports,*) SS_CHAIN_IMPORTS="yes"; continue ;;
  esac
  case "${SS_WHERE},${SS_STATE}," in
    project,*,stale-3x-*)
      INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}${SS_NL}WARNING: ${SS_KIND} is a Triforge 3.x project template (a copy of the retired templates/CLAUDE.md). Triforge 4 ships AGENTS.md only, and Claude Code does not read AGENTS.md while this file exists without importing it. Add the line $(_ss_prose "$SS_IMPORT") to it, or replace its Triforge content with the pointer block in the plugin's templates/AGENTS.md — session start never edits this file."
      ;;
    project,*,user-owned,*)
      SS_OWN_NOTICES="${SS_OWN_NOTICES}${SS_NL}WARNING: ${SS_KIND} in this project does not import AGENTS.md, so Claude Code reads it and skips AGENTS.md, Triforge's only instruction file. Run /at-setup to add the line $(_ss_prose "$SS_IMPORT") to it (setup asks first), or add it yourself — session start never edits this file."
      ;;
    above,*)
      SS_LEVEL=${SS_FILE%/*}
      if [ "$SS_KIND" = .claude/CLAUDE.md ]; then SS_LEVEL=${SS_LEVEL%/*}; fi
      SS_ABOVE_LINE="WARNING: AGENTS.md is not loaded under a Claude lead: $(_ss_prose "$SS_FILE") sits above this project, and Claude Code reads AGENTS.md only while no CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md exists in the working directory or above it. Add a CLAUDE.md holding the line @AGENTS.md to this project: it loads AGENTS.md for this project only."
      if _ss_home_or_above "${SS_LEVEL:-/}"; then
        SS_ABOVE_LINE="${SS_ABOVE_LINE} That file is in your home directory or above it and is read for every project under it, so the fix belongs in this project, not there."
      elif [ "$SS_IMPORT" = "-" ]; then
        SS_ABOVE_LINE="${SS_ABOVE_LINE} No import line in that file can name this project's AGENTS.md: the path from there to this project holds whitespace or a #, where an import path ends, starts with ~, which an import reads as your home directory, or holds another character Claude Code does not read as written in an import path. Or remove the file."
      else
        SS_ABOVE_LINE="${SS_ABOVE_LINE} Or add the line $(_ss_prose "$SS_IMPORT") to that file (an import path is relative to the file that holds it), which loads this project's AGENTS.md in every project under that directory too, or remove the file."
      fi
      SS_ABOVE_NOTICES="${SS_ABOVE_NOTICES}${SS_NL}${SS_ABOVE_LINE}"
      ;;
  esac
done <<SS_FOUND_EOF
${SS_FOUND}
SS_FOUND_EOF
if [ -z "$SS_CHAIN_IMPORTS" ]; then
  INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}${SS_OWN_NOTICES}${SS_ABOVE_NOTICES}"
fi

# Pointer-block tip: a project with no root AGENTS.md carries nothing that
# tells an agent Triforge runs here. A standing tip, printed until the file
# exists; session start does not create it.
AGENTS_MD_TIP=""
if [ -z "$SS_NO_PROJECT" ] && [ ! -e "AGENTS.md" ] && [ ! -L "AGENTS.md" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/AGENTS.md" ]; then
  AGENTS_MD_TIP="${SS_NL}Tip: No AGENTS.md in this project. Triforge's pointer block (the short section that tells every agent this project runs the framework) ships as the plugin's templates/AGENTS.md. Copy it: cp \"$(_ss_prose "$CLAUDE_PLUGIN_ROOT")/templates/AGENTS.md\" ./AGENTS.md"
fi
cd "$SS_ANCHOR" 2>/dev/null || true   # back to the anchor (see the top): ops/ and the rest live there

# Check for existing state
HAS_STATE=""
HAS_TASKS=""
HAS_GOALS=""
HAS_AGENTS=""
HAS_REVIEWS=""
BLOCKED_COUNT=0
PENDING_COUNT=0
IN_PROGRESS_COUNT=0
SOLUTION_COUNT=0

if [ -f "ops/STATE.md" ]; then
  HAS_STATE="yes"
fi

if [ -f "ops/TASKS.md" ]; then
  HAS_TASKS="yes"
  # `grep -c` already prints 0 when there are no matches (exiting 1); `|| true`
  # avoids set -e termination without duplicating the 0 via `echo "0"`.
  # Anchor to the checkbox-row shape (matches hooks/handlers/pre-compact.sh) so
  # the two hand-maintained counters agree and bracket tokens inside a task's
  # prose description are never miscounted as rows.
  BLOCKED_COUNT=$(grep -c '^[[:space:]]*- \[B\]' ops/TASKS.md 2>/dev/null || true)
  PENDING_COUNT=$(grep -c '^[[:space:]]*- \[ \]' ops/TASKS.md 2>/dev/null || true)
  IN_PROGRESS_COUNT=$(grep -c '^[[:space:]]*- \[-\]' ops/TASKS.md 2>/dev/null || true)
fi

if [ -f "ops/GOALS.md" ]; then
  HAS_GOALS="yes"
fi

if [ -f "ops/AGENTS.md" ]; then
  HAS_AGENTS="yes"
fi

if [ -f "ops/REVIEW_ANTIGRAVITY.md" ] || [ -f "ops/REVIEW_CODEX.md" ] || [ -f "ops/TEST_RESULTS.md" ]; then
  HAS_REVIEWS="yes"
fi

SOLUTION_COUNT=$(find ops/solutions -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || true)

# Build orientation message
MSG=""

# Where ops/ is (Phase 3 round 3, R7): a session started below the project
# root reads ops/ from the root, and the lead's own cwd-relative reads would
# miss it, so the root is named once.
if [ "$SS_START_DIR" != "$SS_ANCHOR" ]; then
  MSG="${MSG}${SS_NL}Project root: $(_ss_prose "$SS_ANCHOR") (ops/ lives there; this session started in $(_ss_prose "$SS_START_DIR"))."
fi
if [ -n "$SS_AT_HOME" ]; then
  MSG="${MSG}${SS_NL}WARNING: this session's project directory, $(_ss_prose "$SS_ANCHOR"), is your home directory or contains it, so Triforge set nothing up and wrote nothing there: the project files would be each CLI's user-tier config. Start the session in a project directory; when your home directory is itself a git repository (a dotfiles repo), run git init in the project first, so the project is its own repository."
fi

if [ "$HAS_STATE" = "yes" ]; then
  MSG="${MSG}${SS_NL}Previous session state found (ops/STATE.md). Use /at-resume to continue."
fi

if [ "$HAS_TASKS" = "yes" ]; then
  MSG="${MSG}${SS_NL}Active sprint found (ops/TASKS.md): $PENDING_COUNT pending, $IN_PROGRESS_COUNT in progress, $BLOCKED_COUNT blocked."
fi

if [ "$HAS_GOALS" = "yes" ]; then
  MSG="${MSG}${SS_NL}Project goals found (ops/GOALS.md)."
fi

if [ "$HAS_AGENTS" = "yes" ]; then
  MSG="${MSG}${SS_NL}Agent protocol found (ops/AGENTS.md)."
fi

if [ "$HAS_REVIEWS" = "yes" ]; then
  MSG="${MSG}${SS_NL}Unprocessed review files found. Consider running /at-review to process them."
fi

if [ "$SOLUTION_COUNT" -gt "0" ]; then
  MSG="${MSG}${SS_NL}Institutional knowledge: $SOLUTION_COUNT documented solutions in ops/solutions/."
fi

# Check for external agent definitions
HAS_ANTIGRAVITY_AGENTS=""
HAS_CODEX_AGENTS=""
ANTIGRAVITY_AGENT_COUNT=0
CODEX_AGENT_COUNT=0

# Count the shipped Antigravity definitions — these are the operative agents
# in both lanes (native `--agent` via the installed pack, or injection of the
# same file's body; which lane runs is TRIFORGE_AGY_MODE's call, KTD10).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents" ]; then
  ANTIGRAVITY_AGENT_COUNT=$(find "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || true)
  if [ "$ANTIGRAVITY_AGENT_COUNT" -gt "0" ]; then
    HAS_ANTIGRAVITY_AGENTS="yes"
  fi
fi

if [ -f ".codex/triforge-agents.toml" ]; then
  # Use tomllib/tomli to count real agent entries; fall back to grep if Python unavailable.
  CODEX_AGENT_COUNT=$(python3 -c "${SS_PY_PRELUDE}
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(3)    # no TOML parser: nonzero so the grep fallback below counts instead
with open('.codex/triforge-agents.toml','rb') as f:
    data = tomllib.load(f)
# Filter to dict values only — [agents] also holds scalar Triforge-internal
# declarations (max_depth, max_threads, default_subagent_*) alongside the
# agent subtables.
print(sum(1 for v in data.get('agents', {}).values() if isinstance(v, dict)))
" 2>/dev/null || grep -c '^\[agents\.' .codex/triforge-agents.toml 2>/dev/null || true)
  # A count that is empty or not a number (a parser that printed nothing)
  # reads as 0 rather than breaking the integer test below.
  case "$CODEX_AGENT_COUNT" in ''|*[!0-9]*) CODEX_AGENT_COUNT=0 ;; esac
  if [ "$CODEX_AGENT_COUNT" -gt "0" ]; then
    HAS_CODEX_AGENTS="yes"
  fi
fi

if [ "$HAS_ANTIGRAVITY_AGENTS" = "yes" ] || [ "$HAS_CODEX_AGENTS" = "yes" ]; then
  AGENT_PARTS=""
  [ "$HAS_ANTIGRAVITY_AGENTS" = "yes" ] && AGENT_PARTS="${ANTIGRAVITY_AGENT_COUNT} Antigravity"
  [ "$HAS_CODEX_AGENTS" = "yes" ] && AGENT_PARTS="${AGENT_PARTS:+${AGENT_PARTS} + }${CODEX_AGENT_COUNT} Codex"
  MSG="${MSG}${SS_NL}External agent definitions loaded: ${AGENT_PARTS}."
fi

# Roster orientation (KTD-2): optional members detected this session, and how
# many carry [members.*] enrollment entries in ops/roster.toml.
MSG="${MSG}${SS_NL}Roster: core trio + ${OPTIONAL_DETECTED_COUNT} optional member(s) detected (${ENROLLED_COUNT} enrolled)."
MSG="$MSG${ENROLLMENT_NOTICES:-}"
# The pin lines carry model values read from the roster (B8): each line is
# made one line again and keeps its fixed prose start ("Roster pin differs");
# a line without it (the tail of a value the python split) gets "Roster: ".
if [ -n "$ROSTER_DRIFT_NOTICES" ]; then
  while IFS= read -r SS_LINE; do
    [ -n "$SS_LINE" ] || continue
    case "$SS_LINE" in
      "Roster pin differs from the shipped default: "*) ;;
      *) SS_LINE="Roster: ${SS_LINE}" ;;
    esac
    MSG="${MSG}${SS_NL}$(_ss_prose "$SS_LINE")"
  done <<SS_DRIFT_EOF
${ROSTER_DRIFT_NOTICES}
SS_DRIFT_EOF
fi
if [ -n "$SS_HELPER_NOTICE" ]; then
  MSG="${MSG}${SS_NL}$(_ss_prose "$SS_HELPER_NOTICE")"
fi
if [ -n "$ROSTER_DETECTED_NOTICE" ]; then
  MSG="${MSG}${SS_NL}${ROSTER_DETECTED_NOTICE}"
fi

# Migration notices: triforge_bootstrap's, in the order it printed them (one
# per step that acted this session, silent otherwise; a state it left alone on
# purpose repeats until fixed). Every captured line is sanitized on its own
# (Phase 3 round 3, R5): _ss_prose drops control characters (and the message
# is printed with %s, which interprets nothing), and a line that does not
# carry this hook's "session-start: " prefix (a refusal from a lead-only
# check, or the tail of a message some name split) gets the fixed prose
# prefix "Bootstrap: ", so no stdout line can start with "{".
if [ -n "$SS_BOOT_LOG" ] && [ -s "$SS_BOOT_LOG" ]; then
  while IFS= read -r SS_LINE; do
    [ -n "$SS_LINE" ] || continue
    case "$SS_LINE" in
      "session-start: "*) ;;
      *) SS_LINE="Bootstrap: ${SS_LINE}" ;;
    esac
    MSG="${MSG}${SS_NL}$(_ss_prose "$SS_LINE")"
  done < "$SS_BOOT_LOG"
fi

# Upgrade notices (R40): standing states, repeated every session until fixed.
MSG="$MSG${INSTRUCTION_NOTICES:-}"

# Lease-ledger resume orientation (KTD-4/U9): report active leases left by a
# previous session. Deliberately NO auto-prune here — a session-start hook
# must never delete worktrees; at-resume or the wave protocol runs
# lease_heartbeat_check, whose safe-prune path does the reclamation.
ACTIVE_LEASES=0
if [ -f "ops/leases.toml" ]; then
  ACTIVE_LEASES=$(python3 -c "${SS_READ_PY}
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print(0)
        sys.exit(0)
try:
    data = tomllib.loads(read_regular('ops/leases.toml').decode('utf-8'))
    leases = data.get('lease', {})
    active = ('building', 'leased', 'orphaned')
    print(sum(1 for v in (leases.values() if isinstance(leases, dict) else [])
              if isinstance(v, dict) and v.get('state') in active))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
fi
if [ "${ACTIVE_LEASES:-0}" -gt 0 ] 2>/dev/null; then
  MSG="${MSG}${SS_NL}Lease ledger: ${ACTIVE_LEASES} active lease(s) from a previous session — run lease_heartbeat_check (or /at-resume) to reclaim orphans."
fi

if [ "$HAS_TASKS" != "yes" ] && [ "$HAS_STATE" != "yes" ]; then
  MSG="${MSG}${SS_NL}No active sprint. Use /at-plan <goal> to start or /at-ship <goal> for full autonomous mode."
fi

# Append timeout-missing warning if set
if [ -n "${TIMEOUT_MISSING_WARNING}" ]; then
  MSG="${MSG}${SS_NL}${TIMEOUT_MISSING_WARNING}"
fi

# Append the pointer-block tip if set
MSG="$MSG${AGENTS_MD_TIP:-}"

printf '%s\n' "Multi-agent framework ready.${MSG}"
echo ""
echo 'Lead workflows (/at-<name> here, $agent-triforge:at-<name> in a Codex prompt): at-setup at-ship at-plan at-build at-review at-test at-debug at-quick at-deep-research at-analyze at-coordinate at-resolve-pr at-status at-pause at-resume at-wrap at-compound'

exit 0
}

# The helper (scripts/invoke-external.sh) — sourced ONCE, in the subshell that
# then runs _ss_run, so the hook reads the CLI registry (scripts/lib/registry.sh,
# KTD7) for the optional members, their binaries and shipped models, and the
# roster helpers for enrollment, and runs triforge_bootstrap, instead of
# carrying copies. Degraded, never fatal: a loader that `exit`s rather than
# `return`s, or trips set -u, ends only that subshell. Its stdout and stderr
# land in one file in a private temp dir (the source's stdout is never the
# hook's: a loader that prints a JSON-shaped line before failing must not start
# a stdout line with `{`) beside the `loaded` marker the subshell writes once
# the source succeeded, and the bootstrap's notices land beside them
# (SS_BOOT_LOG; plain files, no extra fd: a descriptor would be inherited by
# every child, and a probe the watchdog in _ss_bounded leaves behind must not
# hold the hook's stdout). No marker: the helper did not load, so _ss_run runs
# below in this shell with SS_HELPER empty — the project bootstrap,
# optional-CLI detection, enrollment and the roster pin check are skipped and
# one standing WARNING line (no "session-start:" prefix — it repeats until
# fixed) names the cause (the loader's first output line, or mktemp's when no
# temp dir could be made under TMPDIR or, failing that, under the hook's own
# .claude/ runtime dir). Marker: the helper loaded and _ss_run ran; a nonzero
# status is a crash inside _ss_run, re-raised here so the EXIT trap reports it
# as it would at top level.
SS_HELPER=""
SS_HELPER_NOTICE=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh" ]; then
  SS_HELPER_RC=0
  SS_HELPER_ERR=""
  SS_HELPER_TMP=$(_ss_private_tmp) || SS_HELPER_RC=$?
  if [ "$SS_HELPER_RC" -eq 0 ]; then
    set +e
    ( set -e
      # shellcheck source=/dev/null
      source "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh" >"${SS_HELPER_TMP}/err" 2>&1 || exit $?
      : > "${SS_HELPER_TMP}/loaded"
      SS_HELPER="yes"
      _ss_run )
    SS_HELPER_RC=$?
    set -e
    if [ -f "${SS_HELPER_TMP}/loaded" ]; then
      rm -rf "$SS_HELPER_TMP"
      exit "$SS_HELPER_RC"
    fi
    SS_HELPER_ERR=$(head -1 "${SS_HELPER_TMP}/err" 2>/dev/null | cut -c1-160 || true)
    rm -rf "$SS_HELPER_TMP"
    SS_HELPER_NOTICE="WARNING: the Triforge helper did not load (${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh exited ${SS_HELPER_RC}: ${SS_HELPER_ERR}) — the project bootstrap, optional-CLI detection, enrollment and the roster pin check were skipped this session. Reinstall the plugin: claude plugin install agent-triforge@agent-triforge"
  else
    # No private temp dir for the loader's output (G2): the helper is not
    # sourced at all, and the notice names the cause and its fix.
    SS_HELPER_ERR=$(printf '%s' "$SS_HELPER_TMP" | head -1 | cut -c1-400)
    SS_HELPER_NOTICE="WARNING: the Triforge helper was not loaded (${SS_HELPER_ERR}) — the project bootstrap, optional-CLI detection, enrollment and the roster pin check were skipped this session. Set TMPDIR to a directory only you can write to, or remove group and other write from .claude, then start a new session."
  fi
else
  # No loader to source: the plugin host did not export CLAUDE_PLUGIN_ROOT, or
  # it names a tree without scripts/invoke-external.sh. Same standing WARNING,
  # same degraded run (the orientation then reports 0 optional members).
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    SS_ROOT_STATE="set to '${CLAUDE_PLUGIN_ROOT}' but has no scripts/invoke-external.sh"
  else
    SS_ROOT_STATE="unset"
  fi
  SS_HELPER_NOTICE="WARNING: the Triforge helper did not load (CLAUDE_PLUGIN_ROOT is ${SS_ROOT_STATE}) — the project bootstrap, optional-CLI detection, enrollment and the roster pin check were skipped this session. Run this hook through the installed plugin: claude plugin install agent-triforge@agent-triforge"
fi
_ss_run
