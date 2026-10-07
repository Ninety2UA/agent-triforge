#!/usr/bin/env bash
# scripts/lib/lease-wait.sh — detached builders and the lead's wait (KTD10): the launcher and its launch record, the process fingerprint, the lane argv and the builder body, the group kill and lease_stop, the reconcile sweep, lease_heartbeat_check and lease_wait
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/roster.sh and before scripts/lib/lease.sh. The
# ledger, integrity and collect helpers these functions call live in lease.sh
# and resolve at call time; nothing here runs at source time but assignments.
# Split out of lease.sh (Phase 2a review) so the lease lifecycle and the
# process supervision each stay readable on their own.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/lease-wait.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Detached builders, lease_wait and the lead-exit reconcile (KTD10, R36, R38)
# ---------------------------------------------------------------------------
#
# A builder outlives the lead's turn. lease_dispatch starts it through
# _LEASE_LAUNCH_PY in its own session and process group (pid == pgid), stdin
# from /dev/null, stdout and stderr to <out>.log, so neither the end of the
# lead's tool call nor a closed terminal reaches it (U29: CC-09, CC-10, CDX-12,
# CDX-13 PASS on the reference host, so coordinate.sh holds no processes). The
# started process is a fresh /bin/bash that sources the loader and runs
# _lease_builder_run: the lane command under _adapter_env, the sweep of its own
# process group, then the exit record. The ledger row records pid, pgid and
# pid_started (the leader's start time, in the pinned form _lease_ps reads), so
# a pid the OS later gave to another process is never taken for the builder and
# never signalled; and lead_pid / lead_started, the lead process that
# dispatched it (_lease_lead_proc). The launcher writes the same fingerprint to
# <out>.launch before it releases the builder, so a builder an interrupted
# lease_dispatch started but never recorded is found and stopped by the next
# lease_dispatch or by lease_stop. The lead waits with lease_wait, the one
# waiting primitive; lease_heartbeat_check is the resume sweep; lease_stop
# stops a builder's whole process group. lease_wait and lease_heartbeat_check
# reconcile each building lease through _lease_sweep_one: a live builder keeps
# building; a finished one is collected; a dead one without an exit record
# takes the orphan path. When the recorded lead process is gone (it exited,
# was killed, or a forced handover says so), a live builder is adopted by the
# current lead and a finished one is collected normally, both with
# reason=lead-exit and lead_exit_at, and requeue_count untouched (R38).

# lease_wait's rc when its budget ran out with a watched lease still building
# (EX_TEMPFAIL: call it again).
_RC_WAIT_BUILDING=75

# The builder's own timeout sends TERM at the lease timeout and KILL this many
# seconds later to a CLI that ignores TERM, as _run_with_timeout (common.sh)
# does for the foreground lanes.
_LEASE_KILL_AFTER_S=10

# heartbeat_deadline = dispatch time + timeout + this slack. It covers the
# builder's kill-after and the exit sweep of its process group (two rounds of
# up to 2 s each, _LEASE_OWN_GROUP_PY) with room to spare, so a builder that
# ends near its timeout has written its exit record, and is collected, before
# the lead's expiry would kill it as hung. The expiry stays the backstop for a
# builder whose own timeout never fired.
_LEASE_DEADLINE_SLACK_S=30

# The field separator of _LEASE_WAIT_PY's lines (ASCII unit separator).
_LEASE_US=$'\037'

# The process fingerprint (pid_started, lead_started) is ps's start time read
# under one locale and zone, LC_ALL=C TZ=UTC0, and recorded with a " UTC"
# suffix. `ps -o lstart=` prints the caller's locale and zone (de_DE: "So.  4
# Okt. 17:57:37 2026"; TZ=Asia/Tokyo: the next calendar day), so a lead whose
# LANG or TZ differs from the dispatching one — a Codex lead adopting builders
# a Claude lead dispatched — would otherwise read a live builder as reused. The
# suffix marks the pinned form: a value without it is a row recorded before 4.0
# in the dispatching lead's local form, and is compared with the caller's local
# form, so it still matches in the same locale and zone. _lease_ps is the shell
# reader; _LEASE_PS_PY defines the same reader, ps(), for the two python ones
# (the launcher and _lease_lead_proc).
_lease_ps() { LC_ALL=C TZ=UTC0 ps "$@"; }
_LEASE_PS_PY='
import os, subprocess
def ps(fields, pid):
    try:
        return subprocess.run(["ps", "-o", fields, "-p", str(pid)], capture_output=True, text=True,
                              env=dict(os.environ, LC_ALL="C", TZ="UTC0")).stdout.split()
    except OSError:
        return []
'

# _LEASE_LAUNCH_PY <log> <argv...> — start argv in a new session with stdin
# /dev/null and stdout/stderr appended to <log>, write the launch record
# "<pid>\t<pgid>\t<start time> UTC" to <log minus .log>.launch (tmp, then
# rename), and print the same line. The child holds at a pipe (fd
# _TRIFORGE_GO_FD, read by _LEASE_BUILDER_SH) until its fingerprint is read and
# the record written, so the record is the live process's own even for a
# builder that finishes at once, and a builder the lead's tool call loses
# before the ledger write is still on disk for the next lease_dispatch to stop.
# When the launcher fails or dies first, the pipe closes unreleased and the
# child exits without running anything. The probe's survival rows (CC-09,
# CC-10, CDX-12, CDX-13) read it through the loader and start their test
# builder with it, so they test this launcher.
_LEASE_LAUNCH_PY="${_LEASE_PS_PY}"'
import sys
log, argv = sys.argv[1], sys.argv[2:]
launch = (log[:-4] if log.endswith(".log") else log) + ".launch"
r, w = os.pipe()
env = dict(os.environ, _TRIFORGE_GO_FD=str(r))
try:
    with open(log, "ab") as out:
        p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT,
                             start_new_session=True, close_fds=True, pass_fds=(r,), env=env)
except OSError as e:
    sys.stderr.write("lease_dispatch: could not start the builder: " + str(e) + "\n")
    sys.exit(1)
os.close(r)
info = ps("pgid=,lstart=", p.pid)
if len(info) < 2 or info[0] != str(p.pid):
    os.close(w)
    sys.stderr.write("lease_dispatch: the builder process " + str(p.pid) + " is not a session leader with a readable start time (ps: " + " ".join(info) + "); it was not released\n")
    sys.exit(1)
rec = str(p.pid) + "\t" + info[0] + "\t" + " ".join(info[1:]) + " UTC"
try:
    with open(launch + ".tmp", "w") as f:
        f.write(rec + "\n")
    os.replace(launch + ".tmp", launch)
except OSError as e:
    os.close(w)
    sys.stderr.write("lease_dispatch: could not write the launch record " + launch + " (" + str(e) + "); the builder was not released\n")
    sys.exit(1)
os.write(w, b"go\n")
os.close(w)
print(rec)
'

# _LEASE_BUILDER_SH — the script the launched /bin/bash runs (bash -c, $0 a
# label, $1 the loader, then _lease_builder_run's arguments): wait for the
# launcher's release, source the loader, run the builder.
_LEASE_BUILDER_SH='case "${_TRIFORGE_GO_FD:-}" in ""|*[!0-9]*) exit 1 ;; esac
_GO=""
IFS= read -r _GO <&"$_TRIFORGE_GO_FD" || true
eval "exec ${_TRIFORGE_GO_FD}<&-"
unset _TRIFORGE_GO_FD
if [ "$_GO" != go ]; then exit 1; fi
. "$1" || exit 97
shift
_lease_builder_run "$@"'

# _LEASE_OWN_GROUP_PY — run by _lease_builder_run once the lane command
# returned: TERM, then KILL, every other process left in its process group (a
# server the builder started, a child timeout --foreground does not time out),
# so nothing of the builder still runs when the exit record appears. Only when
# its parent is the group leader (the launched builder process); anywhere else
# it does nothing.
_LEASE_OWN_GROUP_PY='
import os, signal, subprocess, time
me = os.getppid()
grp = os.getpgid(0)
def members():
    try:
        p = subprocess.Popen(["ps", "-A", "-o", "pid=,pgid="], stdout=subprocess.PIPE, text=True)
        out = p.communicate()[0]
    except OSError:
        return []
    skip = {me, os.getpid(), p.pid}
    return [int(f[0]) for f in (l.split() for l in out.splitlines())
            if len(f) == 2 and f[1] == str(grp) and f[0].isdigit() and int(f[0]) not in skip]
if grp == me:
    for sig in (signal.SIGTERM, signal.SIGKILL):
        left = members()
        if not left:
            break
        for pid in left:
            try:
                os.kill(pid, sig)
            except OSError:
                pass
        end = time.time() + 2
        while time.time() < end and members():
            time.sleep(0.1)
'

# _lease_proc_state <pid> <recorded start> [recorded pgid] — "alive" when the
# pid runs (not a zombie) with the recorded start time and, when one is given,
# the recorded process group; "reused" when the pid runs as a different
# process; "gone" otherwise. The start time is read in the form it was recorded
# in (see _lease_ps): a " UTC" value against the pinned read, an older value
# against the caller's local form, both whitespace-collapsed. An empty recorded
# start (a row from before 3.3.3) is the plain liveness test; the 3.3.3 marker
# "exited-before-record" never matches. One awk reads ps and collapses the
# recorded start too (through ENVIRON), printed as the last field: the only one
# that can be empty, so the tab split keeps the others.
_lease_proc_state() {
  local P=${1:-} S=${2:-} G=${3:-} INFO="" ST="" NG="" NS="" FORM=local TAB
  TAB=$(printf '\t')
  case "$P" in ''|0|*[!0-9]*) printf 'gone\n'; return 0 ;; esac
  case "$S" in *" UTC") FORM=utc; S=${S% UTC} ;; esac
  INFO=$( { if [ "$FORM" = utc ]; then _lease_ps -o stat=,pgid=,lstart= -p "$P"; else ps -o stat=,pgid=,lstart= -p "$P"; fi; } 2>/dev/null \
          | PS_START="$S" awk 'NF >= 3 {
           s = $1; g = $2; $1 = ""; $2 = ""; sub(/^ +/, "")
           n = split(ENVIRON["PS_START"], w, " "); r = ""
           for (i = 1; i <= n; i++) r = r (i > 1 ? " " : "") w[i]
           print s "\t" g "\t" $0 "\t" r; exit }') || INFO=""
  if [ -z "$INFO" ]; then printf 'gone\n'; return 0; fi
  { IFS="$TAB" read -r ST NG NS S || true; } <<PROC_STATE_EOF
${INFO}
PROC_STATE_EOF
  case "$ST" in Z*) printf 'gone\n'; return 0 ;; esac
  if [ -n "$S" ] && [ "$S" != "$NS" ]; then printf 'reused\n'; return 0; fi
  if [ -n "$G" ] && [ "$G" != "$NG" ]; then printf 'reused\n'; return 0; fi
  printf 'alive\n'
}

# _lease_lead_proc — set _LEAD_PID and _LEAD_STARTED to the lead process and
# its start time in the pinned form (0 and "" when the start time can't be
# read): the process whose exit the lead-exit reconcile detects.
# TRIFORGE_LEAD_PID when set (a test, or a harness that knows its lead), else
# the parent of the current process group's leader, else this shell ($$,
# passed in: inside the $(...) below, python3's own parent is a subshell that
# is gone once it returns). A lead's shell tool starts each call as a group
# leader whose parent is the lead CLI (Claude Code on the reference host; U14
# verifies the Codex lead); a by-hand terminal session resolves to the
# terminal's shell. Call it directly, never in $(...), so the two globals land
# in the caller's shell.
_lease_lead_proc() {
  local OUT TAB
  TAB=$(printf '\t')
  _LEAD_PID=0
  _LEAD_STARTED=""
  OUT=$(LP_SHELL=$$ python3 -c "${_LEASE_PS_PY}"'
pid = os.environ.get("TRIFORGE_LEAD_PID", "")
if not pid.isdigit() or int(pid) <= 0:
    up = ps("ppid=", os.getpgid(0))
    pid = up[0] if up and up[0].isdigit() else os.environ.get("LP_SHELL", "")
start = " ".join(ps("lstart=", pid)) if pid.isdigit() else ""
if not start:
    raise SystemExit(1)
print(pid + "\t" + start + " UTC")
' 2>/dev/null) || OUT=""
  { IFS="$TAB" read -r _LEAD_PID _LEAD_STARTED || true; } <<LEAD_PROC_EOF
${OUT}
LEAD_PROC_EOF
  case "$_LEAD_PID" in ''|*[!0-9]*) _LEAD_PID=0; _LEAD_STARTED="" ;; esac
}

# _lease_signalable <pid> [pgid] — rc 0 when a recorded pid, and the recorded
# pgid when there is one (empty or 0: none, a row from before KTD10), can be a
# builder's at all: digits with no leading zero (ps prints none) and above 1.
# pid 1 is launchd (init), and `kill -- -1` reaches every process the user
# owns, so a row that says 1 is never signalled, whoever wrote it.
_lease_signalable() {
  case "${1:-}" in ''|0*|1|*[!0-9]*) return 1 ;; esac
  case "${2:-}" in ''|0) return 0 ;; 0*|1|*[!0-9]*) return 1 ;; esac
  return 0
}

# _lease_kill_builder <pid> <pgid> <recorded start> [term] — TERM a builder's
# process group, then KILL it a second later ("term": TERM only), and only
# while its leader still answers as the recorded process (_lease_proc_state
# alive): a reused pid is never signalled, and neither is the caller's own
# process group, a pid or pgid _lease_signalable refuses, or a row with no
# recorded start time (from before 3.3.3: its pid can only be tested for
# liveness, and by now it may be anyone's); each refusal is one stderr line.
# The KILL is re-validated first: it goes out while the leader still answers as
# the recorded process, or, with the leader gone, while members still carry
# the group id (they keep it reserved); never once the pid answers as another
# process. A row from before KTD10 (no pgid: an undetached subshell) keeps the
# old rule, the pid's own process tree, KILLed only while the pid still
# answers as the recorded process. rc 0 always.
_lease_kill_builder() {
  local P=${1:-} G=${2:-} S=${3:-} MODE=${4:-} OWN=""
  case "$P" in ''|0) return 0 ;; esac
  if ! _lease_signalable "$P" "$G"; then
    echo "lease: NOT signalling pid ${P} (process group ${G:-none}): 1 is launchd's and no ps prints a leading zero or a non-digit, so no detached builder has it — check the ledger row by hand" >&2
    return 0
  fi
  if [ -z "$S" ]; then
    echo "lease: NOT signalling pid ${P}: no start time is recorded for it (a row from before 3.3.3), so it can't be told from a reused pid — check \`ps -o pid,pgid,lstart,command -p ${P}\` and stop it by hand" >&2
    return 0
  fi
  if [ "$G" = 0 ]; then G=""; fi
  if [ "$(_lease_proc_state "$P" "$S" "$G")" != alive ]; then return 0; fi
  if [ -z "$G" ]; then
    _kill_tree "$P" TERM
    if [ "$MODE" = term ]; then return 0; fi
    sleep 1
    if [ "$(_lease_proc_state "$P" "$S" "")" = alive ]; then _kill_tree "$P" KILL; fi
    return 0
  fi
  OWN=$(ps -o pgid= -p "$$" 2>/dev/null | tr -d ' ') || OWN=""
  if [ "$G" = "$OWN" ]; then
    echo "lease: NOT signalling process group ${G}: it is this shell's own, never a detached builder's" >&2
    return 0
  fi
  kill -TERM -- "-${G}" 2>/dev/null || true
  if [ "$MODE" = term ]; then return 0; fi
  sleep 1
  case "$(_lease_proc_state "$P" "$S" "$G")" in
    alive) ;;
    reused) return 0 ;;
    *) if [ -z "$(_lease_group_members "$G")" ]; then return 0; fi ;;
  esac
  kill -KILL -- "-${G}" 2>/dev/null || true
  return 0
}

# _lease_group_members <pgid> — the pids (space-separated, zombies left out)
# still carrying the process group id <pgid>.
_lease_group_members() {
  ps -A -o pid=,pgid=,stat= 2>/dev/null | awk -v g="$1" '$2 == g && $3 !~ /^Z/ { printf "%s%s", sep, $1; sep = " " }' || true
}

# _lease_launch_read <out> — set _LL_PID, _LL_PGID and _LL_START from
# <out>.launch, the record _LEASE_LAUNCH_PY wrote before it released a
# builder; rc 1 when there is none or it does not read as one.
_lease_launch_read() {
  local L="" TAB
  TAB=$(printf '\t')
  _LL_PID=""; _LL_PGID=""; _LL_START=""
  [ -f "${1}.launch" ] || return 1
  { IFS= read -r L || true; } < "${1}.launch"
  { IFS="$TAB" read -r _LL_PID _LL_PGID _LL_START || true; } <<LAUNCH_READ_EOF
${L}
LAUNCH_READ_EOF
  case "${_LL_PID}:${_LL_PGID}" in *[!0-9:]*|:*|*:) return 1 ;; esac
  return 0
}

# _lease_stop_one <op> <task> <pid> <pgid> <start> <what> [quiet] — stop one
# builder for lease_stop and lease_dispatch: its process group, TERM and then
# KILL, through _lease_kill_builder, so only while the leader answers as the
# recorded process, and never a pid with no recorded start time. Afterwards,
# processes still carrying the group id while its leader is gone are named,
# never signalled (with the leader gone the group can't be told from a reused
# one). One stderr line; with quiet, none for a builder that was not running.
# rc 0 when nothing of it runs; 1 when something may (it still answers, there
# is no start time to tell it by, the pid or pgid is one _lease_signalable
# refuses, or group members are left).
_lease_stop_one() {
  local OP=$1 TASK=$2 P=$3 G=$4 S=$5 WHAT=$6 QUIET=${7:-} B N=0 LEFT=""
  case "$P" in
    ''|0)
      if [ -z "$QUIET" ]; then echo "${OP}: ${TASK}: no ${WHAT} pid recorded — nothing to stop" >&2; fi
      return 0
      ;;
  esac
  if ! _lease_signalable "$P" "$G"; then
    echo "${OP}: ${TASK}: the ${WHAT}'s recorded pid ${P} / process group ${G:-none} is no detached builder's (1 is launchd's; no ps prints a leading zero or a non-digit): NOT signalled — check the ledger row by hand" >&2
    return 1
  fi
  if [ "$G" = 0 ]; then G=""; fi
  B=$(_lease_proc_state "$P" "$S" "$G")
  if [ -z "$S" ] && [ "$B" != gone ]; then
    echo "${OP}: ${TASK}: pid ${P} runs, but no start time is recorded for the ${WHAT} (a row from before 3.3.3), so it can't be told from a reused pid: NOT signalled — check \`ps -o pid,pgid,lstart,command -p ${P}\` and stop it by hand" >&2
    return 1
  fi
  case "$B" in
    alive)
      _lease_kill_builder "$P" "$G" "$S"
      while [ "$N" -lt 20 ] && [ "$(_lease_proc_state "$P" "$S" "$G")" = alive ]; do sleep 0.1; N=$((N + 1)); done
      if [ "$(_lease_proc_state "$P" "$S" "$G")" = alive ]; then
        echo "${OP}: ${TASK}: the ${WHAT} (pid ${P}) still answers after TERM and KILL to process group ${G:-<none: its process tree>}" >&2
        return 1
      fi
      echo "${OP}: ${TASK}: stopped the ${WHAT} (pid ${P}, process group ${G:-<none: its process tree>})" >&2
      ;;
    reused)
      # The pid is another process's now; a group of that id is the stranger's.
      if [ -z "$QUIET" ]; then echo "${OP}: ${TASK}: the ${WHAT} is gone (pid ${P} now runs as another process, never signalled)" >&2; fi
      return 0
      ;;
    *)
      if [ -z "$QUIET" ]; then echo "${OP}: ${TASK}: the ${WHAT} (pid ${P}) is not running" >&2; fi
      ;;
  esac
  if [ -n "$G" ]; then
    N=0
    LEFT=$(_lease_group_members "$G")
    while [ -n "$LEFT" ] && [ "$N" -lt 10 ]; do sleep 0.1; N=$((N + 1)); LEFT=$(_lease_group_members "$G"); done
    if [ -n "$LEFT" ]; then
      echo "${OP}: ${TASK}: the ${WHAT}'s leader (pid ${P}) is gone, but pid(s) ${LEFT} still carry its process group ${G}: NOT signalled (with the leader gone the group can't be told from a reused one) — check \`ps -A -o pid,pgid,lstart,command\` for group ${G} and stop them by hand" >&2
      return 1
    fi
  fi
  return 0
}

# lease_stop <task_id> — the lead's way to stop a lease's builder (KTD10): its
# whole process group, TERM and then KILL a second later, through
# _lease_kill_builder, so only while the group's leader still answers as the
# recorded process (pid, pgid and start time). A reused pid is never
# signalled, and a row without a recorded start time (from before 3.3.3) is
# never signalled at all. Signalling the recorded pid alone does not stop a
# detached builder: that pid is the wrapper bash, and the CLI runs on below it
# in the same group. Also stops a builder an interrupted lease_dispatch
# started but never recorded (<out>.launch). Leaves the ledger as it is: the
# caller's next step (lease_reclaim, lease_requeue, lease_rebaseline …)
# decides the state. Like every reader of a row it trusts the ledger it reads:
# a forged row can only make it signal a process whose pid, pgid and start
# time the forger copied, which the forger could signal itself. stderr: one
# line per builder it looked at; stdout: nothing. rc 0: nothing of the builder
# runs any more (stopped now, or already gone); 1: no lease row or no readable
# ledger, or something may still run (it answers after the KILL, the row has
# no start time to check it by or a pid / pgid no builder has, such as 1, or
# processes still carry its group id after its leader is gone; the line says
# which); 45: refused (a worker, or inside
# the lease root); 64: usage.
lease_stop() {
  _lead_only lease_stop || return $?
  if [ "$#" -ne 1 ] || ! _lease_valid_task_id "${1:-}"; then
    echo "lease_stop: usage: lease_stop <task_id>" >&2
    return 64
  fi
  local TASK=$1 ROW P="" G="" S="" OUT="" RC=0
  _lease_ctx || return 1
  ROW=$(_ledger_get_row "$TASK" pid pgid pid_started output_file) || {
    echo "lease_stop: ERROR no lease row for '${TASK}' in ${_LEASE_LEDGER} (or the ledger can't be read)" >&2
    return 1
  }
  { IFS= read -r P || true; IFS= read -r G || true; IFS= read -r S || true; IFS= read -r OUT || true; } <<STOP_ROW_EOF
${ROW}
STOP_ROW_EOF
  # output_file is recorded at dispatch; a row still leased uses the path
  # lease_dispatch launches with.
  [ -n "$OUT" ] || OUT="${_LEASE_ROOT}/${TASK}.out"
  _lease_stop_one lease_stop "$TASK" "$P" "$G" "$S" "builder" || RC=1
  if _lease_launch_read "$OUT" && [ "$_LL_PID" != "$P" ]; then
    _lease_stop_one lease_stop "$TASK" "$_LL_PID" "$_LL_PGID" "$_LL_START" "builder an interrupted lease_dispatch started (${OUT}.launch)" || RC=1
  fi
  return "$RC"
}

# The claude -p lane (KTD16): a builder's turn cap, the explicit tool sets of
# its two classes, and the credential paths no claude worker reads. The tool
# sets name built-in tools only (--tools; anything else, the Agent tool and the
# web tools included, is not offered) and approve without a prompt only what
# needs approving: edits inside the working directory ride acceptEdits, and an
# unscoped Edit, Write or Read rule would approve them anywhere.
_CLAUDE_MAX_TURNS=200
_CLAUDE_TOOLS_EDIT="Bash,Read,Edit,Write,Glob,Grep,NotebookEdit,Skill"
_CLAUDE_ALLOW_EDIT="Bash,Skill"
_CLAUDE_TOOLS_READ="Read,Grep,Glob"
# Devin CLI 3000.x keeps its token in its XDG data dir, credentials.toml
# (~/.local/share/devin; `devin auth status` names the file; CC-25)
_CLAUDE_CRED_PATHS="~/.ssh ~/.aws ~/.gnupg ~/.netrc ~/.git-credentials ~/.config/gh ~/.config/gcloud ~/.azure ~/.kube ~/.docker/config.json ~/.codex ~/.gemini ~/.kimi-code ~/.local/share/opencode ~/.cursor ~/.grok ~/.devin ~/.config/devin ~/.claude/.credentials.json ~/.local/share/devin"

# _claude_sandbox_floor_ok — 0 when the claude worker lane may run here: its
# sandbox is off (TRIFORGE_CLAUDE_SANDBOX=off: no OS confinement, the
# disclosed opt-out), or `claude --version` reads at or above
# TRIFORGE_CLAUDE_SANDBOX_FLOOR (registry.sh), the first build that ignores a
# repository's sandbox-loosening settings under the lane's --settings. Below
# it, or when the version can't be read (no timeout tool, a hang past 10 s,
# no X.Y.Z in the answer), rc 1, and _claude_sandbox_refusal words why. The
# version is read once per process for the claude on PATH (_CLAUDE_SBX_BIN /
# _CLAUDE_SBX_VER), bounded like session start's probe.
_CLAUDE_SBX_BIN=""
_CLAUDE_SBX_VER=""
_claude_sandbox_floor_ok() {
  local BIN TO A B C X Y Z
  case "${TRIFORGE_CLAUDE_SANDBOX:-on}" in off|0|false|no) return 0 ;; esac
  BIN=$(command -v claude 2>/dev/null) || BIN=""
  if [ -z "$BIN" ] || [ "$BIN" != "$_CLAUDE_SBX_BIN" ]; then
    _CLAUDE_SBX_BIN=$BIN
    _CLAUDE_SBX_VER=""
    if [ -n "$BIN" ] && TO=$(_timeout_tool 2>/dev/null); then
      _CLAUDE_SBX_VER=$("$TO" -k 2s 10s "$BIN" --version < /dev/null 2>/dev/null | head -1 \
        | LC_ALL=C grep -Eo '[0-9]{1,6}\.[0-9]{1,6}\.[0-9]{1,6}' | head -1) || _CLAUDE_SBX_VER=""
    fi
  fi
  case "$_CLAUDE_SBX_VER" in ''|*[!0-9.]*) return 1 ;; esac
  IFS=. read -r A B C <<SBX_VER_EOF
$_CLAUDE_SBX_VER
SBX_VER_EOF
  IFS=. read -r X Y Z <<SBX_FLOOR_EOF
$TRIFORGE_CLAUDE_SANDBOX_FLOOR
SBX_FLOOR_EOF
  if [ "$((10#$A))" -ne "$((10#$X))" ]; then [ "$((10#$A))" -gt "$((10#$X))" ]; return $?; fi
  if [ "$((10#$B))" -ne "$((10#$Y))" ]; then [ "$((10#$B))" -gt "$((10#$Y))" ]; return $?; fi
  [ "$((10#$C))" -ge "$((10#$Z))" ]
}

# _claude_sandbox_refusal <caller> — the one wording of that refusal: the
# version read (or that none was), the floor, the upgrade, and the explicit
# opt-out with what it costs.
_claude_sandbox_refusal() {
  local WHAT
  if [ -n "$_CLAUDE_SBX_VER" ]; then
    WHAT="Claude Code ${_CLAUDE_SBX_VER} is below ${TRIFORGE_CLAUDE_SANDBOX_FLOOR}"
  else
    WHAT="Claude Code's version could not be read (\`claude --version\` failed, timed out, or printed no X.Y.Z), so it can't be confirmed at ${TRIFORGE_CLAUDE_SANDBOX_FLOOR} or later"
  fi
  echo "${1:-claude}: ERROR ${WHAT} — the claude worker lane's sandbox needs ${TRIFORGE_CLAUDE_SANDBOX_FLOOR}, the first build that ignores a repository's sandbox-loosening settings (excludedCommands, network.allowedDomains, filesystem.allowWrite) under the lane's --settings; on an older build a repository's .claude/settings.json can run commands outside the sandbox. Fix: update Claude Code (\`claude update\`), or set TRIFORGE_CLAUDE_SANDBOX=off in the lead's environment, and the claude worker's Bash then runs without OS confinement. No retry (deterministic)."
}

# _claude_lane_argv <edit|read> <model> <effort> <resume-id> <deny-write>... —
# set _LEASE_LANE_ARGV to a claude -p worker's command line up to the prompt,
# which the caller appends (KTD16). One JSON envelope (--output-format json:
# subtype, is_error, session_id; _lease_claude_envelope reads it), project and
# local settings only (the user's own hooks, plugins and env stay out), no MCP
# server, and an explicit tool set: edit (a lease builder, a tester, a
# documenter) adds the edit tools under acceptEdits; read (a reviewer, an
# analyst) runs dontAsk, so nothing outside the read set runs. --settings
# carries the confinement, and a --settings file outranks the project's own
# sandbox settings: Bash runs in Claude Code's sandbox (row CC-15: writes stay
# in the working directory, no network), fail-closed when the sandbox can't
# start, with no unsandboxed retry; <deny-write> (the lead's git common dir,
# which the sandbox otherwise opens to a worktree's git; for the read class
# the working directory itself) and the credential paths are blocked, the
# latter also for the Read tool. TRIFORGE_CLAUDE_SANDBOX=off runs Bash without
# the sandbox, and then a claude worker with Bash has no OS confinement; the
# read class drops Bash there. --model and --effort ride only when the roster
# set them (the ladder and the Fable override are the lead's spawn choice,
# never this lane's); --resume only for a UUID-shaped session id (the fix
# cycle resumes the builder's session); --max-turns comes last, so the prompt
# after it is never read as one more tool name.
_claude_lane_argv() {
  local CLASS=$1 MODEL=$2 EFFORT=$3 RESUME=$4 SBX=on TOOLS ALLOW MODE SETTINGS
  shift 4
  case "${TRIFORGE_CLAUDE_SANDBOX:-on}" in off|0|false|no) SBX=off ;; esac
  if [ "$CLASS" = edit ]; then
    TOOLS=$_CLAUDE_TOOLS_EDIT ALLOW=$_CLAUDE_ALLOW_EDIT MODE=acceptEdits
  else
    TOOLS=$_CLAUDE_TOOLS_READ ALLOW=$_CLAUDE_TOOLS_READ MODE=dontAsk
    if [ "$SBX" = on ]; then TOOLS="${TOOLS},Bash" ALLOW="${ALLOW},Bash"; fi
  fi
  SETTINGS=$(CL_SBX="$SBX" CL_CRED="$_CLAUDE_CRED_PATHS" python3 -c '
import json, os, sys
cred = os.environ["CL_CRED"].split()
deny = []
for p in cred:
    deny += ["Read(" + p + ")", "Read(" + p + "/**)"]
s = {"permissions": {"deny": deny}}
if os.environ["CL_SBX"] == "on":
    s["sandbox"] = {"enabled": True, "failIfUnavailable": True, "allowUnsandboxedCommands": False,
                    "autoAllowBashIfSandboxed": True,
                    "filesystem": {"denyRead": cred, "denyWrite": [d for d in sys.argv[1:] if d]}}
else:
    s["sandbox"] = {"enabled": False}
print(json.dumps(s, separators=(",", ":")))
' "$@") || return 1
  _LEASE_LANE_ARGV=(claude -p --output-format json --setting-sources project,local --strict-mcp-config
                    --permission-mode "$MODE" --tools "$TOOLS" --allowedTools "$ALLOW" --settings "$SETTINGS")
  if [ -n "$MODEL" ]; then _LEASE_LANE_ARGV+=(--model "$MODEL"); fi
  if [ -n "$EFFORT" ]; then _LEASE_LANE_ARGV+=(--effort "$EFFORT"); fi
  if _claude_session_ok "$RESUME"; then _LEASE_LANE_ARGV+=(--resume "$RESUME"); fi
  _LEASE_LANE_ARGV+=(--max-turns "$_CLAUDE_MAX_TURNS")
  return 0
}

# _claude_session_ok <id> — 0 when <id> has a Claude Code session id's shape
# (a UUID). The id comes back in a worker's envelope, so it is checked before
# it reaches the ledger (lease_collect) or a command line (--resume).
_claude_session_ok() {
  case "${1:-}" in
    *[!0-9a-fA-F-]* | *-*-*-*-*-*) return 1 ;;
    ????????-????-????-????-????????????) return 0 ;;
  esac
  return 1
}

# _lease_lane_argv <cli> <model> <effort> <dispatch-model> <lane-arg>
#   <cursor-bin> <worktree> <timeout-s> [<git-common-dir> <resume-id>] — set
# _LEASE_LANE_ARGV to the lane's command line up to the prompt, which the
# caller appends (agy and kimi end in
# -p, whose value it is; the others take it as the trailing positional); rc 3
# for a CLI with no arm, any other nonzero when an arm could not compose its
# command (the devin arm names the cause in _LEASE_LANE_ERR). <lane-arg> is
# the lane's own value from
# lease_dispatch: kimi's agent file, devin's config copy, grok's class. The
# one place each lane's argv is composed:
# _lease_builder_run runs it under _adapter_env, and the probe's worker-marker
# rows (CC-13, AGY-17, OC-09, KIMI-10, CUR-13, and CDX-16, CDX-17 and SELF-15c
# through the codex flags; the GRK rows and SELF-06g) read it through the
# loader, so they run the lane's own flags. The invoke_* helpers are shell
# functions and can't cross env -i, so each arm composes the adapter's command
# core directly, and the role brief rides in the prompt (lease_dispatch) for
# every lane but kimi.
#   claude       the edit class of _claude_lane_argv (cwd IS the worktree, so
#                no --add-dir): the lead's <git-common-dir> unwritable, the
#                session <resume-id> on a fix cycle
#   codex        exec in the workspace-write sandbox with approval never, plus
#                two sandbox_workspace_write excludes that drop codex's default
#                temp-dir write allowance: lease worktrees live under TMPDIR,
#                so without them a builder could cross into sibling worktrees
#                or the lease root (R35: writes restricted to the lease
#                worktree); the tool shell's env policy pinned to pass on
#                everything codex was started with (the env -i allowlist is
#                the filter), so neither the user's config.toml nor a default
#                that drops *KEY* names can strip the worker marker or the
#                no-push GIT_CONFIG_KEY_n (CDX-19); -m and
#                model_reasoning_effort only when set
#   antigravity  always the model pin (AE2: agy's own default is a Medium
#                variant), --add-dir the worktree, --print-timeout, the JSON
#                envelope (KTD2, D-032), -p
#   opencode     run --format json -m <model>, and --variant <effort> when an
#                effort is set (OC-05, best effort). No --auto (OC-06: the
#                denies do not survive it); _adapter_env opencode forwards only
#                OPENROUTER_API_KEY (KTD-14)
#   kimi         telemetry off (R25) through env, stream-json, -m, the builder
#                definition as --agent-file (the absolute plugin path, composed
#                lead-side so it survives env -i; no --skills-dir: it would
#                replace Kimi's native .agents/skills discovery, KIMI-04), -p
#                last (commander.js takes the next token as -p's value)
#   cursor       the binary _cursor_bin resolved lead-side, -p (a boolean flag:
#                the prompt is the trailing positional), stream-json, the
#                effort-suffixed model (D-025, never Auto: the ledger needs a
#                named model), --trust (the headless trust prompt, CUR-04) and
#                --force (edits without confirmation, inside the worktree).
#                Confinement is the worktree and the env allowlist, not
#                --sandbox (CUR-07: an absolute-path write escaped it)
#   devin        _devin_argv (scripts/lib/devin.sh): --config <the lane arg,
#                the per-dispatch copy>, the model pin, --permission-mode by
#                the copy's class (dangerous for .edit.json, an opted-in
#                builder; auto, read-only tools only, for a reviewer or
#                analyst lease), workspace trust off
#                (-p fails in an untrusted directory), -p last. SHELL never
#                crosses env -i, so Devin imports no login-shell exports
#                (DVN-04). A missing copy is a compose failure, never a run,
#                and so is a read-class worktree whose .devin/ files would
#                widen it (_devin_project_guard names the file);
#                _lease_builder_run logs the command line and removes the
#                copy after the run (Devin writes its org id into it)
#   grok         _grok_argv (scripts/lib/grok.sh) in the class the lane arg
#                carries (lease_dispatch: _grok_class of the lease role):
#                edit, the workspace sandbox and the edit tools, for a builder,
#                tester or documenter lease; read, the read-only sandbox with
#                Read and Grep only and Edit, Write and Bash denied, for
#                anything else. Either way the env prefix that turns grok's
#                Claude Code and Cursor discovery off, the model pin, --effort
#                when set, streaming-json, dontAsk with the allow and deny sets
#                (every MCP tool denied), and the GROK_CONFIG overlay that
#                keeps the tool shell to the boundary's names; -p last (the
#                prompt is its value)
_lease_lane_argv() {
  local CLI=$1 MODEL=$2 EFFORT=$3 DMODEL=$4 LANE_ARG=$5 CBIN=$6 WT=$7 TIMEOUT=$8
  case "$CLI" in
    claude)
      _claude_lane_argv edit "$MODEL" "$EFFORT" "${10:-}" "${9:-}" || return 1
      ;;
    codex)
      _LEASE_LANE_ARGV=(codex exec -s workspace-write -c 'approval_policy="never"'
                        -c 'sandbox_workspace_write.exclude_tmpdir_env_var=true'
                        -c 'sandbox_workspace_write.exclude_slash_tmp=true'
                        -c 'shell_environment_policy.inherit="all"' -c 'shell_environment_policy.ignore_default_excludes=true'
                        -c 'shell_environment_policy.exclude=[]' -c 'shell_environment_policy.include_only=[]'
                        -c 'shell_environment_policy.set={}')
      if [ -n "$MODEL" ]; then _LEASE_LANE_ARGV+=(-m "$MODEL"); fi
      if [ -n "$EFFORT" ]; then _LEASE_LANE_ARGV+=(-c "model_reasoning_effort=\"${EFFORT}\""); fi
      ;;
    antigravity)
      _LEASE_LANE_ARGV=(agy --model "$DMODEL" --add-dir "$WT" --print-timeout "${TIMEOUT}s" --output-format json -p)
      ;;
    opencode)
      _LEASE_LANE_ARGV=(opencode run --format json -m "$DMODEL")
      if [ -n "$EFFORT" ]; then _LEASE_LANE_ARGV+=(--variant "$EFFORT"); fi
      ;;
    kimi)
      _LEASE_LANE_ARGV=(env KIMI_DISABLE_TELEMETRY=1 kimi --output-format stream-json -m "$DMODEL")
      if [ -n "$LANE_ARG" ]; then _LEASE_LANE_ARGV+=(--agent-file "$LANE_ARG"); fi
      _LEASE_LANE_ARGV+=(-p)
      ;;
    cursor)
      _LEASE_LANE_ARGV=("$CBIN" -p --output-format stream-json --model "$DMODEL" --trust --force)
      ;;
    devin)
      # <lane-arg> is the per-dispatch config copy (lease_dispatch); an
      # .edit.json copy is the builder class, anything else read-only. No
      # copy, no run: Devin never starts on a config the lane did not write
      if [ -z "$LANE_ARG" ] || [ ! -f "$LANE_ARG" ]; then
        _LEASE_LANE_ERR="devin config copy missing (${LANE_ARG:-none named}); lease_dispatch writes one per dispatch"
        return 1
      fi
      case "$LANE_ARG" in
        *.edit.json) _devin_argv edit "$LANE_ARG" "$DMODEL" ;;
        *)
          # Devin merges the worktree's .devin/ files over the copy, so a
          # read-class lease never starts on one that widens it
          if ! _LEASE_LANE_ERR=$(_devin_project_guard "$WT"); then
            _LEASE_LANE_ERR=${_LEASE_LANE_ERR:-"the worktree's .devin/ check failed to run"}
            return 1
          fi
          _devin_argv read "$LANE_ARG" "$DMODEL"
          ;;
      esac
      _LEASE_LANE_ARGV=("${_DEVIN_ARGV[@]}")
      ;;
    grok)
      # <lane-arg> is the class; an empty or unknown one runs read-only
      _grok_argv "${LANE_ARG:-read}" "$DMODEL" "$EFFORT" || return 1
      _LEASE_LANE_ARGV=("${_GROK_ARGV[@]}")
      ;;
    *)
      return 3   # no arm (_lease_builder_run: not integrated)
      ;;
  esac
  return 0
}

# _lease_builder_run <cli> <model> <effort> <dispatch-model> <lane-arg>
#   <cursor-bin> <timeout-bin> <timeout-s> <out> <worktree> <env-keys>
#   <test-builder> <prompt> [<git-common-dir> <resume-id>]
# The detached builder's body: from the worktree, the lane command for <cli>
# (_lease_lane_argv) under _adapter_env's per-CLI allowlist (or the
# TRIFORGE_TEST_BUILDER script <test-builder>), output in <out>; then the sweep
# of its own process group (_LEASE_OWN_GROUP_PY) and the exit record:
# <out>.class, then <out>.rc, the file the lead waits for. It runs only in the
# process _LEASE_LAUNCH_PY started, never in the lead's shell, and never writes
# the ledger (KTD-4). A live build of a lane whose CLI is not signed in
# AUTH-FAILs; that failure is deterministic, and the lead sees it in
# <out>.class (no requeue). The claude lane's JSON envelope, the seam's
# included, is split by _lease_claude_envelope into the result text (<out>)
# and the record lease_collect reads (<out>.envelope); with no envelope, the
# run's stderr is appended to <out>. Before any run: rc 95 for a CLI with no
# lane arm (not integrated), rc 94 (deterministic) for an arm that could not
# compose its command, each with its own line in <out>.
_lease_builder_run() {
  local CLI=$1 MODEL=$2 EFFORT=$3 DISPATCH_MODEL=$4 LANE_ARG=$5 CBIN=$6 TOBIN=$7 TIMEOUT=$8 OUT=$9
  local WT=${10} TEST_BUILDER=${12} FULL_PROMPT=${13} COMMON=${14:-} RESUME=${15:-} RC=0 CLASS_SET=0 AGY_PRC=0 SBX_REFUSED=0 LRC=0
  local -a TO
  _ADAPTER_ENV_KEYS=${11}   # the registry read lease_dispatch did; _adapter_env reads none
  cd "$WT" || return 97
  # --foreground keeps the builder's whole tree in this process group (GNU
  # timeout otherwise moves into a group of its own), so the lead's kill of the
  # group and the sweep below reach every process it started; the children
  # timeout itself leaves running at expiry are the sweep's. -k: a CLI that
  # ignores TERM is killed _LEASE_KILL_AFTER_S later, so the builder enforces
  # its own deadline even with no lead around.
  TO=("$TOBIN" --foreground -k "${_LEASE_KILL_AFTER_S}s" "${TIMEOUT}s")
  if [ -z "$TEST_BUILDER" ]; then
    _LEASE_LANE_ERR=""
    _lease_lane_argv "$CLI" "$MODEL" "$EFFORT" "$DISPATCH_MODEL" "$LANE_ARG" "$CBIN" "$WT" "$TIMEOUT" "$COMMON" "$RESUME" || LRC=$?
  fi
  if [ -n "$TEST_BUILDER" ]; then
    # Test seam (see lease_dispatch): deterministic fake builder.
    _adapter_env "$CLI" "${TO[@]}" "$TEST_BUILDER" "$FULL_PROMPT" > "$OUT" 2>&1 || RC=$?
  elif [ "$LRC" -eq 3 ]; then
    echo "lease_dispatch: ERROR builder CLI '${CLI}' has no dispatch arm here — not integrated. Registered CLIs: $(_known_clis '<registry unreadable>')." > "$OUT"
    RC=95
  elif [ "$LRC" -ne 0 ]; then
    # An arm that could not compose its command: its own cause (rc 94,
    # deterministic), never "not integrated"; nothing ran
    echo "lease_dispatch: ERROR the ${CLI} lane could not compose its command: ${_LEASE_LANE_ERR:-its argv composer failed (see ${OUT}.log)} — nothing ran" > "$OUT"
    RC=94; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1
  else
    case "$CLI" in
      antigravity)
        # JSON envelope (KTD2, D-032): exit 0 is not a completion signal on
        # agy >= 1.1.20 — parse status/response/denied_actions instead. The
        # prose lands in $OUT (what lease_collect prints), the streams in
        # $OUT.raw / $OUT.err, the verdict in $OUT.status / $OUT.denied.
        _adapter_env antigravity "${TO[@]}" "${_LEASE_LANE_ARGV[@]}" "$FULL_PROMPT" < /dev/null > "${OUT}.raw" 2> "${OUT}.err" || RC=$?
        if [ "$RC" -eq 0 ]; then
          _agy_parse_envelope "${OUT}.raw" "$OUT" || AGY_PRC=$?
          case "$AGY_PRC" in
            0|12) : ;;
            10) RC=1; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1
                echo "lease_dispatch: agy builder returned an empty response with denied actions: $(paste -sd, "${OUT}.denied" 2>/dev/null) — add the matching permissions.allow rule to ~/.gemini/antigravity-cli/settings.json (user tier)" >> "$OUT" ;;
            *)  RC=1; INVOKE_FAILURE_CLASS="retryable"; CLASS_SET=1
                echo "lease_dispatch: agy builder returned an empty response (status=$(cat "${OUT}.status" 2>/dev/null)) — treated as failure, not review-ready" >> "$OUT" ;;
          esac
        else
          cat "${OUT}.err" "${OUT}.raw" > "$OUT" 2>/dev/null || true
        fi
        ;;
      opencode)
        # OpenCode V2 guard (D-049): V2 ignores OPENCODE_PERMISSION and runs a
        # shared background service outside env -i, so a V2 binary (or one
        # whose version can't be read — fail-closed) never dispatches: a
        # deterministic refusal naming the V1 pin, recorded in <out>.class like
        # the agy denied-actions arm (no requeue). The lease path has no retry,
        # so a provider that rejects the --variant surfaces as a
        # KTD-9-classified failure the lead requeues, like any other lane.
        if ! _opencode_v2_check opencode; then
          _opencode_v2_refusal lease_dispatch > "$OUT"
          RC=1; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1
        else
          _adapter_env opencode "${TO[@]}" "${_LEASE_LANE_ARGV[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        fi
        ;;
      claude)
        # The envelope alone on stdout (KTD16); stderr beside it, folded into
        # $OUT below only when no envelope came back. A Claude Code below the
        # sandbox floor never starts (deterministic, like the opencode arm).
        if ! _claude_sandbox_floor_ok; then
          _claude_sandbox_refusal lease_dispatch > "$OUT"
          RC=1; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1
        else
          _adapter_env claude "${TO[@]}" "${_LEASE_LANE_ARGV[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2> "${OUT}.err" || RC=$?
          if [ "$RC" -ne 0 ] && grep -q 'without a working sandbox' "${OUT}.err" "$OUT" 2>/dev/null; then
            RC=1; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1; SBX_REFUSED=1
          fi
        fi
        ;;
      grok)
        # A turn-cap stop exits 1 with max_turns_reached (GRK-07). Like the
        # claude lane's error_max_turns it is the lane's cap, not a crash: the
        # work so far stays in the worktree and the run routes as a clean exit
        # without a report (report missing): the extractor
        # (_lease_extract_stream: _grok_lease_text) takes a report only from a
        # run that ended end_turn, so a Status line written before the cap, a
        # max_tokens or any other end never makes the lease review-ready. Any
        # other failure is classified here, where grok's own words are read
        # (signed out, quota).
        _adapter_env grok "${TO[@]}" "${_LEASE_LANE_ARGV[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        if [ "$RC" -ne 0 ]; then
          _grok_classify "$RC" "$OUT"
          if [ "$_INVOKE_FAILURE_REASON" = max-turns ]; then
            RC=0
          else
            CLASS_SET=1
          fi
        fi
        ;;
      devin)
        # The command line goes to the builder log (<out>.log) first: it
        # names the class (--config's .read/.edit copy, --permission-mode),
        # and the copy itself is removed after the run (below)
        echo "lease_dispatch: devin lane: ${_LEASE_LANE_ARGV[*]}" >&2
        _adapter_env devin "${TO[@]}" "${_LEASE_LANE_ARGV[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        ;;
      *)
        _adapter_env "$CLI" "${TO[@]}" "${_LEASE_LANE_ARGV[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        ;;
    esac
  fi
  case "$CLI" in
    claude)
      _lease_claude_envelope "$OUT" "${OUT}.err" || true
      if [ "$SBX_REFUSED" -eq 1 ]; then
        echo "lease_dispatch: the claude builder refused to start without Claude Code's sandbox (KTD16) — on Linux install bubblewrap and socat; or set TRIFORGE_CLAUDE_SANDBOX=off in the lead's environment, and the claude builder's Bash then runs without OS confinement" >> "$OUT"
      fi
      ;;
    devin)
      # Devin wrote its org id into the per-dispatch config copy: it goes,
      # as invoke_devin's own copy does after its run
      if [ -n "$LANE_ARG" ]; then rm -f "$LANE_ARG"; fi
      ;;
  esac
  python3 -c "$_LEASE_OWN_GROUP_PY" 2>/dev/null || true
  # Only a nonzero exit has a failure class (matches invoke_antigravity /
  # invoke_codex): a clean run is class=none, so lease_collect never reads a
  # spurious 'retryable' off a builder that actually succeeded.
  if [ "$RC" -eq 0 ]; then
    INVOKE_FAILURE_CLASS="none"
    # The opencode / kimi / cursor / grok lanes answer as a JSON event stream; the
    # typed `Status:` report (KTD11) lives inside it as escaped text, so a
    # line-anchored parser can never see it. Extract the prose into $OUT
    # (raw stream kept in ${OUT}.raw); an extraction miss leaves $OUT as is.
    _lease_extract_stream "$CLI" "$OUT"
  elif [ "$CLASS_SET" -ne 1 ]; then
    _classify_invoke_failure "$RC" "$OUT"
  fi
  # The class first, then the rc file the lead waits for (whole, via rename),
  # so a lead that sees <out>.rc also sees the class.
  printf '%s\n' "${INVOKE_FAILURE_CLASS:-none}" > "${OUT}.class"
  printf '%s\n' "$RC" > "${OUT}.rc.tmp"
  mv -f "${OUT}.rc.tmp" "${OUT}.rc"
  return "$RC"
}

# _lease_sweep_one <op> <task> <lead-exit 0|1> <mode> [<row>] — one building
# lease's reconcile, shared by lease_wait and lease_heartbeat_check (KTD10).
# Builder alive = its pid answers as the recorded process (_lease_proc_state:
# pid, pgid and start time). Then:
#   alive, before heartbeat_deadline  keeps building; when the lead that
#                                     dispatched it is gone, the current lead
#                                     adopts it (lead_pid / lead_started),
#                                     reason=lead-exit + lead_exit_at
#   alive past heartbeat_deadline     hung: its process group is killed (never
#                                     for a row with no start time), then
#                                     the orphan path
#   not alive, <out>.rc present       finished: lease_collect (normal routing:
#                                     review, report-missing, escalated,
#                                     failed, orphan); when its lead is gone,
#                                     reason=lead-exit + lead_exit_at first —
#                                     requeue_count is never touched here
#   not alive, no exit record         output written within the grace window
#                                     (TRIFORGE_HEARTBEAT_GRACE, default 60 s)
#                                     keeps building; otherwise orphaned and
#                                     straight into lease_reclaim (KTD-9)
# "Its lead is gone" = the recorded lead_pid no longer answers as the recorded
# process, or <lead-exit> is 1 (a forced handover, U9). The lead's liveness is
# tested once per pass: the answer is kept in _LS_LEAD_KEY / _LS_LEAD_ST, which
# lease_wait clears before each pass and lease_heartbeat_check on entry.
# <mode>: sweep (lease_heartbeat_check: prints the still-building notes and the
# unverifiable one); poll (lease_wait: quiet, and runs the integrity check
# before acting on the row — adopt, kill, orphan — then sweeps it again as
# polled); polled (quiet, no check: that second sweep, from the verified
# ledger, KTD18). In poll and polled mode no action (collect, expire, adopt,
# orphan) starts at or after the epoch ms _LS_ACT_STOP_MS (lease_wait's; 0 or
# unset: no limit): the row is left building as "deferred". Polled tests it
# again because the integrity check before it takes time. lease_collect runs
# its own check, right as it starts, and is never cut off once started (a
# killed collect leaves a half-made snapshot). <row> is the task's line from
# _lease_states_read (task, state,
# then the fields below); without one (polled) it is read the same way here,
# so a row deleted since is "left" and a ledger that no longer reads is
# "unverified". The exit record is tested after the liveness test, never taken
# from <row>: a builder that exits in between has written it by then, and a
# stale "absent" would orphan a finished builder. Sets _LS_RESULT: building |
# collected | orphaned | unverified | deferred | left (no longer building).
# Returns 0, or the rc of an integrity check / ledger write that failed, or
# of a collect that failed and left the row building.
_lease_sweep_one() {
  local OP=$1 TASK=$2 LEAD_EXIT=${3:-0} MODE=${4:-sweep} ROW=${5:-}
  local T="" ST="" PID="" PGID="" STARTED="" OUT="" DEADLINE="" LPID="" LSTARTED="" B ACTION LEAD_GONE=0
  local NOW AGE=999999 GRACE RC=0 STAMP NL='
'
  _LS_RESULT=""
  GRACE=${TRIFORGE_HEARTBEAT_GRACE:-60}
  case "$GRACE" in ''|*[!0-9]*) GRACE=60 ;; esac
  if [ -z "$ROW" ]; then
    ROW=$(_lease_states_read "$TASK" 2>/dev/null) || ROW=""
    ROW=${ROW%%"$NL"*}
  fi
  { IFS="$_LEASE_US" read -r T ST PID PGID STARTED OUT DEADLINE LPID LSTARTED || true; } <<SWEEP_LINE_EOF
${ROW}
SWEEP_LINE_EOF
  if [ -n "$ROW" ] && [ "$ST" != building ]; then
    _LS_RESULT=left
    return 0
  fi
  if [ -z "$PID" ] || [ -z "$OUT" ]; then
    # Could not verify: a building row with no pid/output to judge liveness
    # by (ledger written by an older version, or a hand edit). Leave it alone
    # — never guess. lease_wait names these once, in its own line.
    if [ "$MODE" = sweep ]; then
      echo "${OP}: ${TASK} building but pid/output_file missing from the ledger — cannot verify liveness (degraded); inspect and reclaim by hand" >&2
    fi
    _LS_RESULT=unverified
    return 0
  fi
  case "$DEADLINE" in ''|*[!0-9]*) DEADLINE=0 ;; esac
  B=$(_lease_proc_state "$PID" "$STARTED" "$PGID")
  if [ "$LEAD_EXIT" = 1 ]; then
    LEAD_GONE=1
  else
    case "$LPID" in
      ''|0|*[!0-9]*) ;;
      *)
        if [ "${_LS_LEAD_KEY:-}" != "${LPID}|${LSTARTED}" ]; then
          _LS_LEAD_ST=$(_lease_proc_state "$LPID" "$LSTARTED")
          _LS_LEAD_KEY="${LPID}|${LSTARTED}"
        fi
        if [ "$_LS_LEAD_ST" != alive ]; then LEAD_GONE=1; fi
        ;;
    esac
  fi
  NOW=$(date +%s)
  if [ "$B" = alive ]; then
    if [ "$NOW" -gt "$DEADLINE" ]; then ACTION=expire
    elif [ "$LEAD_GONE" -eq 1 ]; then ACTION=adopt
    else ACTION=wait; fi
  elif [ -f "${OUT}.rc" ]; then
    ACTION=collect
  else
    if [ -f "$OUT" ]; then
      AGE=$(OUT_FILE="$OUT" python3 -c "
import os, time
print(max(0, int(time.time() - os.path.getmtime(os.environ['OUT_FILE']))))
" 2>/dev/null || echo 999999)
      case "$AGE" in ''|*[!0-9]*) AGE=999999 ;; esac
    fi
    if [ "$AGE" -lt "$GRACE" ]; then ACTION=grace; else ACTION=orphan; fi
  fi
  case "$ACTION" in
    adopt|expire|orphan|collect)
      if [ "$MODE" != sweep ] && [ "${_LS_ACT_STOP_MS:-0}" -gt 0 ] \
         && [ "$(python3 -c 'import time; print(int(time.time() * 1000))')" -ge "$_LS_ACT_STOP_MS" ]; then
        _LS_RESULT=deferred
        return 0
      fi
      ;;
  esac
  case "$ACTION" in
    adopt|expire|orphan)
      if [ "$MODE" = poll ]; then
        _lead_integrity_check "$OP" || return $?
        _lease_sweep_one "$OP" "$TASK" "$LEAD_EXIT" polled
        return $?
      fi
      ;;
  esac
  case "$ACTION" in
    wait)
      if [ "$MODE" = sweep ]; then
        echo "${OP}: ${TASK} building (pid ${PID} alive, deadline in $((DEADLINE - NOW))s)" >&2
      fi
      _LS_RESULT=building
      return 0
      ;;
    grace)
      if [ "$MODE" = sweep ]; then
        echo "${OP}: ${TASK} pid ${PID} gone but output active ${AGE}s ago (grace ${GRACE}s) — leaving as building" >&2
      fi
      _LS_RESULT=building
      return 0
      ;;
    adopt)
      _lease_lead_proc
      STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      _ledger_update "$TASK" lead_pid="$_LEAD_PID" lead_started="$_LEAD_STARTED" reason=lead-exit lead_exit_at="$STAMP" >/dev/null || return $?
      echo "${OP}: ${TASK} building — the builder outlived the lead that dispatched it (pid ${PID} alive); adopted by this lead, reason=lead-exit, requeue budget untouched" >&2
      _LS_RESULT=building
      return 0
      ;;
    collect)
      if [ "$LEAD_GONE" -eq 1 ]; then
        STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
        _ledger_update "$TASK" reason=lead-exit lead_exit_at="$STAMP" >/dev/null || return $?
        echo "${OP}: ${TASK} builder finished (rc=$(cat "${OUT}.rc" 2>/dev/null || true)) while the lead that dispatched it was gone — collecting it, reason=lead-exit, requeue budget untouched" >&2
      else
        echo "${OP}: ${TASK} builder exited (rc=$(cat "${OUT}.rc" 2>/dev/null || true)) — collecting" >&2
      fi
      lease_collect "$TASK" >&2 || RC=$?
      if [ "$RC" -eq "$_RC_LEASE_INTEGRITY" ]; then return "$RC"; fi
      # A collect that failed and left the row building collected nothing (it
      # refused, 45, or a ledger write failed): the sweep stops with its rc.
      # Its routed outcomes all leave building (review, leased on a missing
      # report, escalated, failed, orphaned).
      if [ "$RC" -ne 0 ] && [ "$(_ledger_get "$TASK" state 2>/dev/null || true)" = building ]; then
        return "$RC"
      fi
      _LS_RESULT=collected
      return 0
      ;;
    expire)
      # Hung past its window: still breathing after its own timeout, kill-after
      # and exit sweep should have ended it — kill its process group, then
      # orphan (the belt to that suspender). A row with no recorded start time
      # (from before 3.3.3) only says the pid runs, maybe as another process
      # by now, so it is orphaned unsignalled, as lease_stop leaves it.
      if [ -z "$STARTED" ]; then
        echo "${OP}: ${TASK} EXPIRED — pid ${PID} runs past heartbeat_deadline, but no start time is recorded for the builder (a row from before 3.3.3), so it can't be told from a reused pid: NOT signalled — check \`ps -o pid,pgid,lstart,command -p ${PID}\` and stop it by hand; orphaning" >&2
      else
        echo "${OP}: ${TASK} EXPIRED — pid ${PID} alive past heartbeat_deadline; killing the builder's process group and orphaning" >&2
        _lease_kill_builder "$PID" "$PGID" "$STARTED"
      fi
      ;;
    orphan)
      echo "${OP}: ${TASK} ORPHANED — pid ${PID} dead (or now another process), no exit record, output stale; reclaiming" >&2
      ;;
  esac
  _ledger_update "$TASK" state=orphaned || return $?
  lease_reclaim "$TASK" || true
  _LS_RESULT=orphaned
  return 0
}

# _lease_root_notice <op> — one stderr note per open lease recorded under a
# lease root other than the one this shell resolves (TMPDIR or
# TRIFORGE_LEASE_ROOT changed since lease_create). The recorded root is a hint,
# never a source: the lease root holds the lead's integrity anchors, so it is
# not taken from the ledger, and the note is no ready-to-paste export line.
# Callers run it only after their integrity check passed (the ledger is the
# lead's own write), and the values are printed escaped (\xNN for a character
# that does not print, and for the backslash), so a forged field can't put a
# line break or a terminal escape into the lead's output.
_lease_root_notice() {
  LR_LEDGER="$_LEASE_LEDGER" LR_ROOT="$_LEASE_ROOT" LR_OP="$1" python3 -c '
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
def esc(s):
    out = []
    for c in str(s):
        o = ord(c)
        if c.isprintable() and c != "\\":
            out.append(c)
        elif o < 0x100:
            out.append("\\x%02x" % o)
        elif o < 0x10000:
            out.append("\\u%04x" % o)
        else:
            out.append("\\U%08x" % o)
    return "".join(out)
try:
    with open(os.environ["LR_LEDGER"], "rb") as f:
        leases = tomllib.load(f).get("lease", {})
except Exception:
    sys.exit(0)
for t, r in sorted(leases.items() if isinstance(leases, dict) else []):
    if not isinstance(r, dict) or r.get("state") not in ("leased", "building", "review"):
        continue
    root = str(r.get("lease_root", ""))
    if root and os.path.realpath(root) != os.environ["LR_ROOT"]:
        sys.stderr.write(esc(os.environ["LR_OP"]) + ": NOTE lease " + esc(t) + " was created under the lease root " + esc(root)
                         + ", but this shell resolves " + esc(os.environ["LR_ROOT"]) + " (TMPDIR or TRIFORGE_LEASE_ROOT changed since lease_create)."
                         + " Before pointing TRIFORGE_LEASE_ROOT at that directory, check it is the one you created: the lease root holds the lead integrity anchors\n")
' || true
}

# lease_heartbeat_check [--lead-exit] [task_id] — the resume sweep: every
# building lease (or just one) through _lease_sweep_one, between two integrity
# checks, on entry and on return (KTD18: a change is escalated and returns 44),
# with the lease-root note after the first. A live builder keeps building; a
# finished one is collected
# (lease_collect's stdout goes to stderr here); a dead one with no exit record
# is orphaned and reclaimed (KTD-9); a lease whose dispatching lead is gone is
# adopted or collected with reason=lead-exit and its requeue budget untouched.
# --lead-exit treats every swept lease's lead as gone: the forced handover (U9)
# calls it. rc 0; _RC_DEGRADED when a row could not be verified; 44 from either
# integrity check, and a collect's 44 passes through; a failed ledger write,
# or a collect that fails and leaves the row building (a refused one, 45),
# stops the sweep with its rc and is not counted as collected.
lease_heartbeat_check() {
  _lead_only lease_heartbeat_check || return $?
  local ONLY="" LEAD_EXIT=0 LEDGER ROWS ROW TASK SWEPT=0 COLLECTED=0 ORPHANED=0 UNVERIFIED=0 RC=0
  _LS_LEAD_KEY=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --lead-exit) LEAD_EXIT=1 ;;
      *) ONLY=$1 ;;
    esac
    shift
  done
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  if [ ! -f "$LEDGER" ]; then
    echo "lease_heartbeat_check: no lease ledger at ${LEDGER} — nothing to sweep" >&2
    return 0
  fi
  _lead_integrity_check lease_heartbeat_check || return $?
  _lease_root_notice lease_heartbeat_check
  # Every building lease's row, one line each, in one ledger read; a ledger
  # that does not parse shows on stderr and sweeps nothing.
  ROWS=$(_lease_states_read "") || ROWS=""
  # $ROWS is NEWLINE-separated. Iterate with read, NOT `for ROW in $ROWS`:
  # under zsh (the caller's shell on macOS) an unquoted $ROWS is not
  # word-split, so `for` would run once on the whole blob and corrupt the
  # sweep for 2+ concurrent leases — the parallel-wave case. The heredoc (not
  # a `printf | while` pipe) keeps the loop in THIS shell so the counters
  # persist. It arrives on fd 3, so each sweep keeps the caller's stdin: the
  # lead-only helpers nested in it (lease_collect, _ledger_update,
  # lease_reclaim) see the terminal this pass passed the host check on.
  while IFS= read -r ROW <&3; do
    TASK=${ROW%%"$_LEASE_US"*}
    case "$TASK" in ""|@now) continue ;; esac
    if [ -n "$ONLY" ] && [ "$TASK" != "$ONLY" ]; then continue; fi
    SWEPT=$((SWEPT + 1))
    _lease_sweep_one lease_heartbeat_check "$TASK" "$LEAD_EXIT" sweep "$ROW" || RC=$?
    if [ "$RC" -ne 0 ]; then break; fi
    case "$_LS_RESULT" in
      collected)  COLLECTED=$((COLLECTED + 1)) ;;
      orphaned)   ORPHANED=$((ORPHANED + 1)) ;;
      unverified) UNVERIFIED=$((UNVERIFIED + 1)) ;;
    esac
  done 3<<HEARTBEAT_ROWS
$ROWS
HEARTBEAT_ROWS
  # Every return runs the integrity check (KTD10), as lease_wait's does: a
  # builder that changed git state or the ledger during the sweep is restored
  # and escalated here.
  if [ "$RC" -eq 0 ]; then _lead_integrity_check lease_heartbeat_check || RC=$?; fi
  echo "lease_heartbeat_check: swept ${SWEPT} building lease(s), collected ${COLLECTED}, orphaned ${ORPHANED}, unverifiable ${UNVERIFIED}" >&2
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  if [ "$UNVERIFIED" -gt 0 ]; then return "$_RC_DEGRADED"; fi
  return 0
}

# _lease_ledger_check — rc 0 when the ledger exists and parses; else rc 1 and
# the problem on stdout.
_lease_ledger_check() {
  if [ ! -f "$_LEASE_LEDGER" ]; then
    printf 'no lease ledger at %s (no lease was created from this checkout)\n' "$_LEASE_LEDGER"
    return 1
  fi
  LC_LEDGER="$_LEASE_LEDGER" python3 -c '
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("no TOML parser available (use Python 3.11+, or pip install tomli)")
        sys.exit(1)
try:
    with open(os.environ["LC_LEDGER"], "rb") as f:
        data = tomllib.load(f)
except Exception as e:
    print(os.environ["LC_LEDGER"] + " does not parse: " + " ".join(str(e).split()))
    sys.exit(1)
if not isinstance(data.get("lease", {}), dict):
    print(os.environ["LC_LEDGER"] + " has a lease key that is not a table of leases")
    sys.exit(1)
'
}

# _LEASE_WAIT_PY — the ledger read of lease_wait, lease_heartbeat_check and
# _lease_sweep_one: one line per task in LW_NAMES (space-separated), or per
# building lease when LW_NAMES is empty — task, state (whitespace-collapsed;
# "@missing" for a task with no row), then the row fields _lease_sweep_one
# needs: pid, pgid, pid_started, output_file, heartbeat_deadline, lead_pid,
# lead_started; then "@now" and the epoch ms. Fields are separated by _LEASE_US
# (\037), which, unlike a tab, keeps an empty field in place under `read`. A
# row whose fields hold a line break or that separator keeps only its state
# (the sweep then finds no pid and reports it unverifiable), and a ledger key
# holding one is not listed as building.
_LEASE_WAIT_PY='
import os, time
try:
    import tomllib
except ImportError:
    import tomli as tomllib
US = "\x1f"
BAD = ("\n", "\r", US)
KEYS = ("pid", "pgid", "pid_started", "output_file", "heartbeat_deadline", "lead_pid", "lead_started")
with open(os.environ["LW_LEDGER"], "rb") as f:
    leases = tomllib.load(f).get("lease", {})
leases = leases if isinstance(leases, dict) else {}
names = os.environ.get("LW_NAMES", "").split()
if not names:
    names = sorted(t for t, r in leases.items() if isinstance(r, dict) and r.get("state") == "building"
                   and not any(c in t for c in BAD))
for t in names:
    r = leases.get(t)
    if not isinstance(r, dict):
        print(t + US + "@missing")
        continue
    vals = [str(r.get(k, "")) for k in KEYS]
    if any(c in v for v in vals for c in BAD):
        vals = [""] * len(KEYS)
    print(US.join([t, " ".join(str(r.get("state", "")).split())] + vals))
print("@now" + US + str(int(time.time() * 1000)))
'

# _lease_states_read "<task ...>" — _LEASE_WAIT_PY over the ledger (no task:
# every building lease). A ledger that does not parse is a nonzero rc with
# Python's error on stderr; lease_wait drops that stream, the heartbeat shows it.
_lease_states_read() {
  LW_LEDGER="$_LEASE_LEDGER" LW_NAMES="${1:-}" python3 -c "$_LEASE_WAIT_PY"
}

# _lease_wait_parse <read> — split a _LEASE_WAIT_PY answer into _LW_NOW (epoch
# ms), _LW_STILL (the building tasks, space-separated), _LW_ROWS (their lines,
# for the next pass of _lease_sweep_one), _LW_LEFT ("<task> <state>" lines of
# the others) and _LW_MISSING.
_lease_wait_parse() {
  local L T S
  _LW_NOW=0; _LW_STILL=""; _LW_ROWS=""; _LW_LEFT=""; _LW_MISSING=""
  while IFS= read -r L; do
    T=${L%%"$_LEASE_US"*}
    S=${L#*"$_LEASE_US"}
    S=${S%%"$_LEASE_US"*}
    case "$T" in
      "") ;;
      @now) _LW_NOW=$S ;;
      *)
        case "$S" in
          building)
            _LW_STILL="${_LW_STILL}${_LW_STILL:+ }${T}"
            _LW_ROWS="${_LW_ROWS}${L}
"
            ;;
          @missing) _LW_MISSING="${_LW_MISSING}${_LW_MISSING:+ }${T}" ;;
          *) _LW_LEFT="${_LW_LEFT}${T} ${S}
" ;;
        esac
        ;;
    esac
  done <<LW_PARSE_EOF
${1}
LW_PARSE_EOF
  case "$_LW_NOW" in ''|*[!0-9]*) _LW_NOW=0 ;; esac
}

# _lease_wait_print [none] — lease_wait's stdout from the last parse: a
# "<task> <state>" line for each watched lease that left building, then
# "still building: <task>..." when any still is; with "none", "no lease
# building" when neither.
_lease_wait_print() {
  if [ -n "$_LW_LEFT" ]; then printf '%s' "$_LW_LEFT"; fi
  if [ -n "$_LW_STILL" ]; then printf 'still building: %s\n' "$_LW_STILL"; fi
  if [ "${1:-}" = none ] && [ -z "$_LW_LEFT" ] && [ -z "$_LW_STILL" ]; then printf 'no lease building\n'; fi
  return 0
}

# _lease_wait_close "<task ...>" — lease_wait's stdout when its entry integrity
# check found a change: the named leases' states (none named: those still
# building) from the restored ledger, as the closing print gives them.
_lease_wait_close() {
  local READ
  READ=$(_lease_states_read "${1:-}" 2>/dev/null) || READ=""
  _lease_wait_parse "$READ"
  _lease_wait_print
}

# _lease_wait_all_in "<task ...>" "<task ...>" — rc 0 when every task of the
# first list is in the second. Split with tr, not an unquoted expansion, which
# zsh does not word-split.
_lease_wait_all_in() {
  local T
  while IFS= read -r T; do
    [ -n "$T" ] || continue
    case " $2 " in *" ${T} "*) ;; *) return 1 ;; esac
  done <<ALL_IN_EOF
$(printf '%s\n' "$1" | tr ' ' '\n')
ALL_IN_EOF
  return 0
}

# lease_wait [task_id...] [--budget <seconds>] — the lead's one waiting
# primitive (KTD10, R36). Blocks until at least one of the named leases (none
# named: every lease building at the call) leaves `building`, or the budget
# runs out. While it waits it reconciles each watched lease once a second
# through _lease_sweep_one (a finished builder is collected, a hung one
# killed and orphaned, one whose lead is gone adopted or collected with
# reason=lead-exit) and runs the integrity check every 15 s; it never polls
# faster. Each poll reads the ledger once (_lease_states_read): the states it
# returns on and the rows the next pass sweeps. The budget never exceeds the
# lead's lead.wait_budget_s from the CLI registry (claude 600, codex 900; the
# lead is [lead] in the roster, read through lead_field, and _lead_only has
# already checked this shell runs it; TRIFORGE_LEAD_WAIT_BUDGET_S may only
# lower it): the default and the cap are that value minus a quarter of
# it, at most 15 s, so the call returns inside the lead's shell-tool limit.
# The budget counts from the call's start, and the polling stops a second
# before it, so the closing integrity check fits inside it too. No action
# (collect, expiry, adoption, orphaning) starts once the budget is spent,
# however many one pass has to take: the pass stops there and the next call
# takes the rest. The default budget leaves that quarter (at most 15 s) before
# the lead's limit for the last action to finish; a smaller --budget, from a
# lead whose tool limit is lower, bounds the actions the same way. Under a
# Claude lead, pass the Bash tool timeout explicitly: wait_budget_s x 1000 ms.
# stdout: "<task> <state>" for each watched lease that left building, then
# "still building: <task>..." when any still is, or "no lease building".
# rc 0: a lease left building, or none was building; _RC_WAIT_BUILDING (75):
# the budget ran out with everything watched still building, or before an
# action the last pass still had;
# _RC_DEGRADED (80): every lease still building has a row with no pid or
# output_file, so its liveness can't be verified and waiting can't change
# that (one stderr line names them; lease_heartbeat_check's rc for such a row
# too); 44: the integrity check found a change, on entry, mid-wait or on return
# (restored and escalated, as in every lease helper; stdout still gives the
# watched leases' states); 1: ledger error (missing, unparseable) or an
# unknown task; 64: usage; 45: run by a worker or from inside the lease root,
# or a collect inside the wait refused (any collect that fails and leaves the
# row building returns its rc).
# Loop it in bounded slices until it prints no "still building:" line or
# returns 80, each repeat naming only the leases on that line (or none): a
# named lease that already left building returns at once.
lease_wait() {
  _lead_only lease_wait || return $?
  local BUDGET="" NAMES="" ERR WAIT_LEAD LF TAB CAP HEADROOM EFF READ WATCH ROW START_MS STOP_MS CHECK_MS REM RC=0
  local T UNVER="" DEFER=0
  # The budget counts from the call's start, so the checks before the wait
  # are inside it too.
  START_MS=$(python3 -c 'import time; print(int(time.time() * 1000))')
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --budget)
        if [ "$#" -lt 2 ]; then echo "lease_wait: usage: lease_wait [task_id...] [--budget <seconds>]" >&2; return 64; fi
        BUDGET=$2
        shift 2
        ;;
      --budget=*) BUDGET=${1#--budget=}; shift ;;
      *)
        if ! _lease_valid_task_id "$1"; then
          echo "lease_wait: usage: lease_wait [task_id...] [--budget <seconds>] ('${1}' is not a task id)" >&2
          return 64
        fi
        NAMES="${NAMES}${NAMES:+ }$1"
        shift
        ;;
    esac
  done
  case "$BUDGET" in
    "") ;;
    *[!0-9]*|0*) echo "lease_wait: usage: --budget takes a whole number of seconds above 0, got '${BUDGET}'" >&2; return 64 ;;
  esac
  _lease_ctx || return 1
  # A missing or unparseable ledger is a ledger error — unless the lead wrote
  # one here before (its copy and digest exist): then it is a change the
  # integrity check restores from the lead's copy and escalates (KTD18).
  if ! ERR=$(_lease_ledger_check); then
    if [ -e "${_LEASE_STATE}/ledger.copy" ] || [ -e "${_LEASE_STATE}/ledger.sha256" ]; then
      _lead_integrity_check lease_wait || { RC=$?; _lease_wait_close "$NAMES"; return "$RC"; }
      ERR=$(_lease_ledger_check) || { echo "lease_wait: LEDGER ERROR — ${ERR}" >&2; return 1; }
    else
      echo "lease_wait: LEDGER ERROR — ${ERR}; nothing to wait on" >&2
      return 1
    fi
  fi
  _lead_integrity_check lease_wait || { RC=$?; _lease_wait_close "$NAMES"; return "$RC"; }
  _lease_root_notice lease_wait
  # The lead's shell-tool limit is a registry field of the lead (KTD1: read the
  # field, never the lead's name); one that can't be read keeps the shorter
  # limit, Claude's 600 s.
  TAB=$(printf '\t')
  LF=$(lead_field name lead.wait_budget_s 2>/dev/null) || LF=""
  case "$LF" in
    *"$TAB"*) WAIT_LEAD=${LF%%"$TAB"*}; CAP=${LF#*"$TAB"} ;;
    *) WAIT_LEAD="the"; CAP="" ;;
  esac
  case "$CAP" in ''|*[!0-9]*|0*) CAP=600 ;; esac
  case "${TRIFORGE_LEAD_WAIT_BUDGET_S:-}" in
    ''|*[!0-9]*|0*) ;;
    *) if [ "$TRIFORGE_LEAD_WAIT_BUDGET_S" -lt "$CAP" ]; then CAP=$TRIFORGE_LEAD_WAIT_BUDGET_S; fi ;;
  esac
  HEADROOM=$((CAP / 4))
  if [ "$HEADROOM" -gt 15 ]; then HEADROOM=15; fi
  if [ "$HEADROOM" -lt 1 ]; then HEADROOM=1; fi
  EFF=$((CAP - HEADROOM))
  if [ "$EFF" -lt 1 ]; then EFF=1; fi
  if [ -z "$BUDGET" ]; then
    BUDGET=$EFF
  elif [ "$BUDGET" -gt "$EFF" ]; then
    echo "lease_wait: budget capped at ${EFF}s (${WAIT_LEAD} lead: wait_budget_s ${CAP}s, the wait returns ${HEADROOM}s inside it)" >&2
    BUDGET=$EFF
  fi
  READ=$(_lease_states_read "$NAMES" 2>/dev/null) || READ=""
  if [ -z "$READ" ]; then echo "lease_wait: LEDGER ERROR — ${_LEASE_LEDGER} could not be read" >&2; return 1; fi
  _lease_wait_parse "$READ"
  if [ -n "$_LW_MISSING" ]; then
    echo "lease_wait: ERROR no lease row for: ${_LW_MISSING}" >&2
    return 1
  fi
  if [ -n "$_LW_LEFT" ] || [ -z "$_LW_STILL" ]; then
    # Nothing to wait for: a named lease already left building, or none builds.
    _lease_wait_print none
    return 0
  fi
  WATCH=$_LW_STILL
  # Polling stops short of the budget (a second; half of a 1 s budget), the
  # room the closing integrity check needs. An action (_lease_sweep_one, poll
  # mode) starts only inside the budget (BUDGET from the call's start, never
  # past EFF): with the default budget at least HEADROOM is left before the
  # lead's limit, so one that starts finishes inside it.
  STOP_MS=$((START_MS + BUDGET * 1000 - 500))
  if [ "$BUDGET" -ge 2 ]; then STOP_MS=$((STOP_MS - 500)); fi
  _LS_ACT_STOP_MS=$((START_MS + BUDGET * 1000))
  CHECK_MS=$((START_MS + 15000))
  while :; do
    # One pass over the leases still building, from the rows of the last read
    # (on fd 3, so each sweep keeps the caller's stdin, as in
    # lease_heartbeat_check).
    _LS_LEAD_KEY=""
    UNVER=""
    while IFS= read -r ROW <&3; do
      if [ -z "$ROW" ]; then continue; fi
      T=${ROW%%"$_LEASE_US"*}
      _lease_sweep_one lease_wait "$T" 0 poll "$ROW" || RC=$?
      if [ "$RC" -ne 0 ]; then break; fi
      case "$_LS_RESULT" in
        unverified) UNVER="${UNVER}${UNVER:+ }${T}" ;;
        deferred) DEFER=1; break ;;
      esac
    done 3<<LEASE_WAIT_EOF
${_LW_ROWS}
LEASE_WAIT_EOF
    if [ "$RC" -ne 0 ]; then break; fi
    READ=$(_lease_states_read "$WATCH" 2>/dev/null) || READ=""
    if [ -z "$READ" ]; then
      # The ledger stopped parsing mid-wait: the integrity check restores it
      # from the lead's copy (and escalates; the closing print then reads the
      # restored ledger), or there is nothing left to trust.
      _lead_integrity_check lease_wait || { RC=$?; break; }
      echo "lease_wait: LEDGER ERROR — ${_LEASE_LEDGER} could not be read" >&2
      return 1
    fi
    _lease_wait_parse "$READ"
    if [ -n "$_LW_LEFT" ] || [ -z "$_LW_STILL" ] || [ "$DEFER" -eq 1 ] || [ "$_LW_NOW" -ge "$STOP_MS" ]; then break; fi
    # Every lease still building is one the sweep can't verify: waiting can't
    # change that, so return degraded (below) rather than poll to the budget.
    if [ -n "$UNVER" ] && _lease_wait_all_in "$_LW_STILL" "$UNVER"; then break; fi
    if [ "$_LW_NOW" -ge "$CHECK_MS" ]; then
      _lead_integrity_check lease_wait || { RC=$?; break; }
      CHECK_MS=$((_LW_NOW + 15000))
    fi
    REM=$((STOP_MS - _LW_NOW))
    if [ "$REM" -ge 1000 ]; then sleep 1; else sleep "$(printf '0.%03d' "$REM")"; fi
  done
  _LS_ACT_STOP_MS=0
  # Every return runs the integrity check (KTD10): a builder that changed git
  # state or the ledger while the lead waited is restored and escalated here,
  # and the states printed below are read from the verified ledger.
  if [ "$RC" -eq 0 ]; then _lead_integrity_check lease_wait || RC=$?; fi
  READ=$(_lease_states_read "$WATCH" 2>/dev/null) || READ=""
  _lease_wait_parse "$READ"
  _lease_wait_print
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  if [ -n "$_LW_LEFT" ] || [ -z "$_LW_STILL" ]; then return 0; fi
  if [ -n "$UNVER" ] && _lease_wait_all_in "$_LW_STILL" "$UNVER"; then
    echo "lease_wait: ${_LW_STILL}: building, but the ledger row has no pid or output_file, so the builder's liveness can't be verified (a row from an older version, or a hand edit) — degraded, rc ${_RC_DEGRADED}; waiting can't change that: inspect and reclaim by hand" >&2
    return "$_RC_DEGRADED"
  fi
  if [ "$DEFER" -eq 1 ]; then
    echo "lease_wait: stopped before an action: the ${BUDGET}s budget was spent; still building: ${_LW_STILL} — call lease_wait again" >&2
  else
    echo "lease_wait: the ${BUDGET}s budget ran out; still building: ${_LW_STILL}${UNVER:+ (liveness not verifiable: ${UNVER})} — call lease_wait again" >&2
  fi
  return "$_RC_WAIT_BUILDING"
}
