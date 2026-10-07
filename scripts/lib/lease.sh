#!/usr/bin/env bash
# scripts/lib/lease.sh — the lease lifecycle (KTD-4): ledger, per-adapter env allowlist (+ no-push backstop, worker marker), lease_create/dispatch/collect/merge/promote, the typed-report parser (KTD11); detached builders, lease_wait, lease_stop and the lead-exit reconcile (KTD10) live in scripts/lib/lease-wait.sh
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh and scripts/lib/lease-wait.sh (whose
# launcher, builder body and group kill lease_dispatch and lease_collect call,
# at call time). Every function keeps the name and contract it had when this
# code lived in invoke-external.sh; the split (review finding #15 on the
# v3.3.0 branch) is by lane, not by behavior.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/lease.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Lease lifecycle (KTD-4) — the builder pool's spine
# ---------------------------------------------------------------------------
#
# Every non-lead build runs under a per-task lease in an isolated git
# worktree (R8, R20, R35). The ledger at ops/leases.toml is LEAD-OWNED and
# single-writer (KTD-4): builders NEVER write it — status flows back through
# the captured exit code and KTD-9 class the launcher drops beside the
# output file (<out>.rc / <out>.class). Runtime state, gitignored.
#
# State machine (mirrors the plan's lease lifecycle diagram):
#
#   [*] -> leased -> building -> review -> merged -> [*]
#              ^         |          |
#              |         |          +-> building   findings, cycle < 3 (U10)
#              |         |          +-> escalated  cycle 3 / no non-author reviewer
#              |         +-> orphaned   heartbeat expiry or silent death
#              |         |       +-> requeued   worktree pruned; once (KTD-9)
#              |         |       +-> escalated  second failure
#              |         +-> failed     deterministic (auth / absent CLI)
#              |                 +-> escalated  fail fast with guidance, no requeue
#              +-------- requeued (re-leased to a DIFFERENT builder)
#
# Contract (KTD-3, KTD-14, R35): builders never read or write the canonical
# ops/ tree — required context is injected into the dispatch prompt; the
# builder runs with cwd = its worktree under a per-adapter env allowlist
# (_adapter_env) so no cross-provider credential leaks; shared-file mutations
# happen lead-side at collect/merge time on the main tree.

# Confinement, stated honestly (R4, R46): the worktree limits where a builder
# STARTS, not where it writes. A builder with a shell and no OS sandbox can
# write anything the user can — the lead's .git/config and hooks, the ledger,
# other branches. Triforge does not prevent that; it makes its OWN git calls
# ignore worker-writable settings (_lead_git), detects changes the lead did not
# make at the next check (_lead_integrity_check: collect, merge, promote,
# create, dispatch, pin, requeue, heartbeat), restores .git/config, .git/hooks,
# the lead's trusted git config and the ledger from the lead's copies (keeping
# the changed version beside them), escalates, and merges only
# the lead's own recorded snapshot of each lease (KTD19). Other git callers —
# the harness's own git, ad-hoc git the lead model runs, other builders — are
# covered only by that detection. All of it is detection, not prevention.

# Worker marker (KTD9, R34): _RC_LEAD_ONLY, _lead_only and _lease_root_above
# live in scripts/lib/common.sh (roster.sh calls _lead_only too, and loads
# before this file); _adapter_env below sets the marker.

# ---------------------------------------------------------------------------
# Lead context and hardened lead-side git (KTD18)
# ---------------------------------------------------------------------------

# _lease_ctx — resolve, and cache for the current directory, the lead's
# checkout (_LEASE_REPO), its git dir (_LEASE_GITDIR) and common dir
# (_LEASE_COMMON), the ledger (_LEASE_LEDGER), the lease root (_LEASE_ROOT),
# the lead state directory (_LEASE_STATE = <root>/lead) and the trusted git
# config _lead_git reads
# (_LEAD_CFG, captured on first use). Found WITHOUT git: a planted
# core.worktree in .git/config would make `git rev-parse --show-toplevel`
# answer with a path the worker chose, and with it the ledger path and the
# lease root. The walk-up mirrors git's own discovery (nearest ancestor holding
# .git). Lease root: TRIFORGE_LEASE_ROOT, else
# ${TMPDIR:-/tmp}/triforge-leases/<repo-basename>-<git-blob-hash-of-root-path>
# (the same 12 hex chars `git hash-object --stdin` gave before 3.3.3, so open
# 3.3.x leases keep their root). Every stored worktree path is canonical from
# birth, which is what lets lease_reclaim compare stored vs canonical. The
# root, its lead/ dir and (derived) triforge-leases/ must be this user's
# directories (group and other write are taken away), and a derived root
# needs a TMPDIR no other user can rename entries in: else rc 1 with a
# refusal, since whoever can swap those directories chooses the trusted git
# config every lead-side git call reads (Phase 3 round 4, B5).
_lease_ctx() {
  local KEY="${PWD}|${TRIFORGE_LEASE_ROOT:-}|${TMPDIR:-}"
  if [ "${_LEASE_CTX_KEY:-}" = "$KEY" ] && [ -n "${_LEAD_CFG:-}" ] && [ -f "${_LEAD_CFG}" ]; then
    return 0
  fi
  local OUT RC=0
  OUT=$(LC_ROOT="${TRIFORGE_LEASE_ROOT:-}" LC_TMP="${TMPDIR:-/tmp}" python3 -c '
import hashlib, os, stat, sys
# shared(p): another user could rename entries in directory p (owned by
# someone else than this user or root, or group/other write without the
# sticky bit), and with them swap the lease root and its trusted git config
# (Phase 3 round 4, B5; the rule monitors.py applies to its own TMPDIR).
def shared(p):
    st = os.stat(p)
    return st.st_uid not in (os.getuid(), 0) or bool(st.st_mode & 0o022 and not st.st_mode & stat.S_ISVTX)
# private(p): p is a directory of this user, group and other write taken away.
def private(p):
    st = os.lstat(p)
    if not stat.S_ISDIR(st.st_mode) or st.st_uid != os.getuid():
        print("the lease directory " + p + " is not a directory of this user")
        sys.exit(3)
    if st.st_mode & 0o022:
        os.chmod(p, stat.S_IMODE(st.st_mode) & ~0o022)
d = os.path.realpath(os.getcwd())
while not os.path.lexists(os.path.join(d, ".git")):
    parent = os.path.dirname(d)
    if parent == d:
        sys.exit(1)
    d = parent
repo, dotgit = d, os.path.join(d, ".git")
if os.path.isdir(dotgit) and not os.path.islink(dotgit):
    gitdir = dotgit
else:
    try:
        line = open(dotgit, encoding="utf-8").read().strip()
    except OSError:
        sys.exit(2)
    if not line.startswith("gitdir:"):
        sys.exit(2)
    gitdir = os.path.join(repo, line[len("gitdir:"):].strip())
common = gitdir
if os.path.isfile(os.path.join(gitdir, "commondir")):
    common = os.path.join(gitdir, open(os.path.join(gitdir, "commondir"), encoding="utf-8").read().strip())
root = os.environ.get("LC_ROOT", "")
mine = []
if not root:
    tmp = os.environ.get("LC_TMP") or "/tmp"
    if shared(tmp):
        print("TMPDIR " + tmp + " lets another user rename entries in it (group or other write without the sticky bit, or another user owns it)")
        sys.exit(3)
    b = repo.encode("utf-8", "surrogateescape")
    h = hashlib.sha1(b"blob " + str(len(b)).encode() + b"\0" + b).hexdigest()[:12]
    root = os.path.join(tmp, "triforge-leases", os.path.basename(repo) + "-" + h)
    mine.append(os.path.dirname(root))
os.makedirs(os.path.join(root, "lead"), exist_ok=True)
for p in mine + [root, os.path.join(root, "lead")]:
    private(os.path.realpath(p))
for p in (repo, os.path.realpath(gitdir), os.path.realpath(common), os.path.realpath(root)):
    print(p)
' 2>/dev/null) || RC=$?
  if [ "$RC" -eq 3 ]; then
    echo "lease: ERROR $(printf '%s' "$OUT" | LC_ALL=C tr -d '\000-\037\177') — the lease root and the lead's trusted git config would sit where another user can swap them, so no lease runs here. Set TMPDIR to a private directory (or TRIFORGE_LEASE_ROOT to one of yours) and rerun." >&2
    return 1
  fi
  if [ "$RC" -ne 0 ]; then
    echo "lease: ERROR not inside a git repository — worktree leases require one (outside git the builder pool degrades to lead-only in-place execution)." >&2
    return 1
  fi
  _LEASE_REPO=$(printf '%s\n' "$OUT" | sed -n 1p)
  _LEASE_GITDIR=$(printf '%s\n' "$OUT" | sed -n 2p)
  _LEASE_COMMON=$(printf '%s\n' "$OUT" | sed -n 3p)
  _LEASE_ROOT=$(printf '%s\n' "$OUT" | sed -n 4p)
  _LEASE_STATE="${_LEASE_ROOT}/lead"
  _LEASE_LEDGER="${_LEASE_REPO}/ops/leases.toml"
  _LEAD_CFG="${_LEASE_STATE}/gitconfig"
  if [ ! -f "$_LEAD_CFG" ] && ! _lead_gitconfig_capture "$_LEAD_CFG"; then
    echo "lease: ERROR could not capture the trusted git config into ${_LEAD_CFG}" >&2
    _LEAD_CFG=""
    return 1
  fi
  _LEASE_CTX_KEY=$KEY
}

# _lead_gitconfig_capture <dest> — build the trusted "global" config _lead_git
# uses (KTD18): the user's identity, LFS filter, ignore-file, line-ending and
# safe.directory settings, read once from the system and global config files.
# The only git this file runs outside _lead_git: `git -C <lead checkout> config
# --<scope> --includes` reads that one scope and the files it includes, and
# executes nothing. Includes are on (a named scope turns them off by default)
# and the read runs from the lead checkout (_LEASE_REPO, set by _lease_ctx
# before it calls this) so [include] and [includeIf "gitdir:..."] files resolve:
# a user.name/user.email kept in one would otherwise be dropped, and every lead
# commit would carry the wrong identity. Captured before any builder runs, so a
# later worker edit to ~/.gitconfig never reaches the lead's git (and the
# integrity check reports it); the capture itself is a digested, restorable
# integrity surface (lead_gitconfig). Its first line starts with
# _LEAD_GITCONFIG_SIGNATURE (scripts/lib/common.sh), which is how
# _is_lease_root recognizes a lease root (KTD9): keep it.
_lead_gitconfig_capture() {
  local DEST=$1 TMP="${1}.tmp.$$" SCOPE K V LIST
  mkdir -p "$(dirname "$DEST")" || return 1
  printf '%s (KTD18) — captured from your system/global git config on\n# first use. The lead-side git calls in scripts/lib/lease.sh read ONLY this file as global\n# config. The integrity check digests it: to re-capture, delete it and run lease_rebaseline.\n' "$_LEAD_GITCONFIG_SIGNATURE" > "$TMP" || return 1
  for SCOPE in --system --global; do
    LIST=$(env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_DIR -u GIT_WORK_TREE \
             git -C "$_LEASE_REPO" config "$SCOPE" --includes --null --get-regexp '^(user\.(name|email)|core\.(excludesfile|autocrlf|eol)|init\.defaultbranch|safe\.directory|filter\.lfs\..*)$' 2>/dev/null \
           | python3 -c '
import sys
for item in sys.stdin.buffer.read().split(b"\0"):
    k, _, v = item.decode("utf-8", "replace").partition("\n")
    if k and "\t" not in v and "\n" not in v:
        print(k + "\t" + v)
') || LIST=""
    while IFS="$(printf '\t')" read -r K V; do
      [ -n "$K" ] || continue
      GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git config --file "$TMP" --add "$K" "$V" 2>/dev/null || true
    done <<CAPTURE_EOF
${LIST}
CAPTURE_EOF
  done
  mv -f "$TMP" "$DEST"
}

# _lead_git <git args...> — every git call the lease lifecycle makes (KTD18).
# Worker-writable settings can't change what it runs: system config off
# (GIT_CONFIG_NOSYSTEM), global config = the trusted capture (_LEAD_CFG), and
# per-invocation overrides for hooks (core.hooksPath=/dev/null), fsmonitor,
# the global attributes file, signing, pager and editor, plus gc/maintenance
# off. .git/config itself can't be switched off, so it (and .git/hooks,
# .git/info, and the trusted capture itself) is digest-checked before these
# calls run. Inherited GIT_* that
# would redirect the call are unset; _LEAD_GIT_INDEX, when set, becomes
# GIT_INDEX_FILE (the temporary index a snapshot is built in).
_lead_git() {
  if [ -z "${_LEAD_CFG:-}" ] || [ ! -f "${_LEAD_CFG}" ]; then
    _lease_ctx || return 1
  fi
  local -a E=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY
              -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_EXTERNAL_DIFF
              GIT_CONFIG_NOSYSTEM=1 "GIT_CONFIG_GLOBAL=${_LEAD_CFG}" GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat GIT_EDITOR=true GIT_OPTIONAL_LOCKS=0 GIT_NO_REPLACE_OBJECTS=1)
  [ -n "${_LEAD_GIT_INDEX:-}" ] && E+=("GIT_INDEX_FILE=${_LEAD_GIT_INDEX}")
  "${E[@]}" git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c core.attributesFile=/dev/null \
    -c commit.gpgSign=false -c tag.gpgSign=false -c core.pager=cat -c core.editor=true \
    -c gc.auto=0 -c maintenance.auto=false "$@"
}

# _lgr <git args...> — _lead_git on the lead's own checkout, bound by explicit
# --git-dir/--work-tree (a planted core.worktree can't move it).
_lgr() {
  _lead_git -C "$_LEASE_REPO" --git-dir="$_LEASE_GITDIR" --work-tree="$_LEASE_REPO" "$@"
}

# _lgw <worktree> <admin-dir> <git args...> — _lead_git on a lease worktree
# through the admin dir RECORDED at create (.git/worktrees/<name>), never the
# worktree's own .git pointer file, which the builder can rewrite (KTD18).
_lgw() {
  local W=$1 A=$2
  shift 2
  _lead_git -C "$W" --git-dir="$A" --work-tree="$W" "$@"
}

# BSD-portable realpath (no readlink -f on stock macOS).
_lease_realpath() {
  RP_TARGET="$1" python3 -c "
import os
print(os.path.realpath(os.environ['RP_TARGET']))
"
}

# Repo default branch (KTD-5). origin/HEAD's target when set, else the first of
# main/master that exists locally, else empty (a single-branch or detached repo
# with no default-branch concept). Printed WITHOUT the refs/remotes/origin/
# prefix. Tolerant: every probe is guarded so a repo with no remote still works.
_lease_default_branch() {
  local REF="" B
  _lease_ctx || return 0
  REF=$(_lgr symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || REF=""
  if [ -n "$REF" ]; then
    printf '%s\n' "${REF#refs/remotes/origin/}"
    return 0
  fi
  for B in main master; do
    if _lgr show-ref --verify --quiet "refs/heads/${B}" 2>/dev/null; then
      printf '%s\n' "$B"
      return 0
    fi
  done
  return 0
}

# _lease_default_ref — set _LEASE_DEF (the default branch, or empty) and
# _LEASE_DEF_SHA (its commit, or empty): what the integrity baseline records.
_lease_default_ref() {
  _LEASE_DEF=$(_lease_default_branch)
  _LEASE_DEF_SHA=""
  if [ -n "$_LEASE_DEF" ]; then
    _LEASE_DEF_SHA=$(_lgr rev-parse --verify --quiet "refs/heads/${_LEASE_DEF}^{commit}" 2>/dev/null || true)
  fi
}

# Current checked-out branch of the main tree, or empty on detached HEAD.
_lease_current_branch() {
  _lease_ctx || return 0
  _lgr symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

# _lease_root / _lease_ledger_path — print the lease root / the ledger path.
# Kept for callers outside this file; inside it, _lease_ctx sets _LEASE_ROOT and
# _LEASE_LEDGER in the caller's shell, so no subshell is needed.
_lease_root() {
  _lease_ctx || return 1
  printf '%s\n' "$_LEASE_ROOT"
}

_lease_ledger_path() {
  _lease_ctx || return 1
  printf '%s\n' "$_LEASE_LEDGER"
}

# task_id doubles as a directory and branch component — constrain it before
# it can constrain us (first char alphanumeric, then [A-Za-z0-9._-]).
_lease_valid_task_id() {
  case "$1" in
    ""|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) return 1 ;;
  esac
  return 0
}

# _ledger_update <task_id> key=value...
# The ONLY writer of ops/leases.toml (KTD-4). Read-modify-write: parse with
# tomllib (read-only stdlib), apply updates, re-serialize with a small flat
# emitter (values stay flat strings/ints so the round trip is trivial),
# round-trip-verify the tmp file, then atomic tmp+mv. `updated` is stamped
# on every call. Int keys: pid, pgid, lead_pid, created, updated,
# heartbeat_deadline, requeue_count, review_cycle, report_missing_count.
# Refuses in a worker context (_lead_only, KTD9) — the backstop behind the
# lease_* entry points' own refusal. The write itself is _ledger_write, whose
# guard skips only the lead host check (_lead_only --any-host): the two
# writers exempt from that check write through it directly, lease_approve
# (KTD4) and the forced handover's stamp (_lease_mark_handover, called by
# roster_write_lead). Both first move to the lease root the ledger was last
# written under (_lease_at_ledger_root): every write stamps that root in
# [baseline].lease_root, next to the anchors it updates.
#
# The reserved id @baseline (never a valid task id) writes the [baseline]
# table instead of a lease row: the lead's last verified git state (KTD18) —
# digests of .git/config, .git/hooks, .git/info, the global git config, the
# lead's trusted git config and the lead checkout's .git, the default branch
# and its SHA, the integration branch and its SHA — plus the lease_rebaseline
# audit (last_rebaseline, rebaseline_log).
#
# Integrity (KTD18): after every write the ledger's digest and a copy of it are
# kept in the lead state dir (<lease root>/lead/ledger.sha256, ledger.copy).
# Before a write, a ledger that no longer matches the lead's last write was
# changed by someone else: the write starts from the lead's copy instead
# (restoring it) and sets [baseline].ledger_alert, which the next
# _lead_integrity_check escalates. The digest is lstat-aware — a symlink
# digests as "link:<target>", never through the link — so a ledger replaced
# by a symlink counts as changed, and os.replace puts a regular file back over
# the link itself. This is the ONE place that rule is decided, always under the
# ledger lock: _lead_integrity_check and lease_rebaseline start with a no-op
# `_ledger_update @baseline` to run it, which writes nothing while the ledger
# and its copy match the recorded digest and a [baseline] exists (otherwise it
# writes, stamping `updated`, and so restores, alerts or re-anchors).
_ledger_update() {
  _lead_only _ledger_update || return $?
  _ledger_write "$@"
}

_ledger_write() {
  _lead_only _ledger_write --any-host || return $?
  local TASK_ID=$1
  shift
  local LEDGER LOCK RC=0 TRIES=0
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  mkdir -p "$(dirname "$LEDGER")"
  # Serialize the read-modify-write on the lead-owned ledger (KTD-4). The
  # documented wave keeps writes lead-serial, but a mkdir-lock (portable —
  # flock is not on macOS) makes the single-writer guarantee hold even under
  # accidental concurrency (e.g. a dynamic-workflow parallel group). Atomic
  # create; bounded wait with one stale-lock reclaim so a crashed writer can't
  # wedge the ledger forever.
  LOCK="${LEDGER}.lock"
  while ! mkdir "$LOCK" 2>/dev/null; do
    TRIES=$((TRIES + 1))
    if [ "$TRIES" -gt 200 ]; then
      # ~10s of contention. Reclaim ONLY if the recorded holder is provably dead
      # (kill -0 fails). Never steal a LIVE holder's lock — that silently loses a
      # concurrent writer's lease transition. If the holder is alive, or reclaim
      # still cannot acquire, FAIL CLOSED (never write unlocked): surface the
      # wedged ledger instead of racing it. (PID reuse could in theory mark a
      # dead holder as live and block once more — accepted: the lock is normally
      # held <1s and fail-closed-then-retry is safe; a truly wedged lock is
      # removed manually per the message.)
      local HOLDER=""
      [ -f "${LOCK}/pid" ] && HOLDER=$(cat "${LOCK}/pid" 2>/dev/null || true)
      if [ -n "$HOLDER" ] && kill -0 "$HOLDER" 2>/dev/null; then
        echo "_ledger_update: ERROR ledger lock held by LIVE pid ${HOLDER} after ~10s (${LOCK}) — refusing to write unlocked. Another writer is active; retry, or if it is wedged remove ${LOCK} and retry." >&2
        return 1
      fi
      rm -rf "$LOCK" 2>/dev/null || true        # holder absent/dead — reclaim once
      if mkdir "$LOCK" 2>/dev/null; then break; fi
      echo "_ledger_update: ERROR could not acquire ledger lock after ~10s (${LOCK}) — refusing to write unlocked (fail-closed)." >&2
      return 1
    fi
    sleep 0.05
  done
  printf '%s\n' "$$" > "${LOCK}/pid" 2>/dev/null || true
  LEDGER_FILE="$LEDGER" LEDGER_TASK="$TASK_ID" LEDGER_STATE="$_LEASE_STATE" LEDGER_ROOT="$_LEASE_ROOT" python3 -c "
import hashlib, json, os, shutil, sys, time
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('_ledger_update: ERROR no TOML parser available. Fix: use Python 3.11+ (tomllib) or run: pip install tomli\n')
        sys.exit(3)

path = os.environ['LEDGER_FILE']
task = os.environ['LEDGER_TASK']
state = os.environ['LEDGER_STATE']
digest_file = os.path.join(state, 'ledger.sha256')
copy_file = os.path.join(state, 'ledger.copy')
def _sha(p):
    try:
        if os.path.islink(p):
            return 'link:' + os.readlink(p)
        with open(p, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return 'absent'
recorded = ''
if os.path.isfile(digest_file):
    recorded = open(digest_file).read().strip()
source, alert = path, ''
stamp = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
if recorded and _sha(path) != recorded:
    if os.path.isfile(copy_file) and _sha(copy_file) == recorded:
        source = copy_file
        alert = stamp + ' ops/leases.toml changed outside the lead writes (restored from the lead copy before a write)'
    else:
        alert = stamp + ' ops/leases.toml changed outside the lead writes (no intact lead copy to restore from)'
elif not recorded and os.path.isfile(copy_file):
    # The digest is written right after the copy on every lead write, so a
    # copy with no digest means the digest file was deleted (or a crash fell
    # between the two writes): the rule can not run, and the current ledger
    # is adopted unverified. Fail closed: alert, never a silent first use.
    alert = stamp + ' the ledger digest ' + digest_file + ' is missing while the lead copy exists: an integrity anchor was deleted, and ops/leases.toml was adopted UNVERIFIED (compare it with ' + copy_file + ')'
data = {}
if os.path.isfile(source):
    with open(source, 'rb') as f:
        data = tomllib.load(f)
# The integrity check's no-op @baseline call on a ledger that matches the lead's
# last write and its copy, with a [baseline] in place: nothing to restore or
# record, so nothing is rewritten (a write would only stamp [baseline].updated,
# which nothing reads). Loaded first, so a ledger that no longer parses still
# fails closed; any alert, update, missing anchor or lease_root that is not
# this root's still writes.
if (task == '@baseline' and len(sys.argv) == 1 and not alert and recorded and isinstance(data.get('baseline'), dict)
        and data['baseline'].get('lease_root') == os.environ['LEDGER_ROOT']
        and os.path.isfile(copy_file) and _sha(copy_file) == recorded):
    sys.exit(0)
leases = data.get('lease', {})
leases = leases if isinstance(leases, dict) else {}
baseline = data.get('baseline', {})
baseline = dict(baseline) if isinstance(baseline, dict) else {}
if alert:
    baseline['ledger_alert'] = alert
# The lease root whose lead state dir holds the anchors this write updates:
# where the any-host writers write next (_lease_at_ledger_root).
baseline['lease_root'] = os.environ['LEDGER_ROOT']
if task == '@baseline':
    row = baseline
else:
    row = dict(leases.get(task, {})) if isinstance(leases.get(task, {}), dict) else {}
INT_KEYS = ('pid', 'pgid', 'lead_pid', 'created', 'updated', 'heartbeat_deadline', 'requeue_count', 'review_cycle', 'report_missing_count')
for arg in sys.argv[1:]:
    k, sep, v = arg.partition('=')
    if not sep or not k:
        sys.stderr.write('_ledger_update: ERROR malformed update ' + repr(arg) + ' (want key=value)\n')
        sys.exit(2)
    if k in INT_KEYS:
        try:
            row[k] = int(v)
        except ValueError:
            sys.stderr.write('_ledger_update: ERROR ' + k + ' must be an integer, got ' + repr(v) + '\n')
            sys.exit(2)
    else:
        row[k] = str(v)
row['updated'] = int(time.time())
if task != '@baseline':
    leases[task] = row

# Flat serializer: only ints, bools, and strings ever land in a row.
# json.dumps escaping is valid TOML for basic strings and quoted keys.
lines = ['# ops/leases.toml — lead-owned lease ledger (KTD-4). Runtime state,',
         '# gitignored. Single writer: the lead, via _ledger_update in',
         '# scripts/lib/lease.sh. Builders never write this file; a change the',
         '# lead did not make is restored from its copy and escalated (KTD18).',
         '']
def emit(r):
    for k in sorted(r):
        v = r[k]
        if isinstance(v, bool):
            lines.append(k + ' = ' + ('true' if v else 'false'))
        elif isinstance(v, int):
            lines.append(k + ' = ' + str(v))
        else:
            lines.append(k + ' = ' + json.dumps(str(v)))
    lines.append('')
if baseline:
    lines.append('[baseline]')
    emit(baseline)
for t in sorted(leases):
    r = leases[t]
    if not isinstance(r, dict):
        continue
    lines.append('[lease.' + json.dumps(str(t)) + ']')
    emit(r)

tmp = path + '.tmp.' + str(os.getpid())
with open(tmp, 'w') as f:
    f.write('\n'.join(lines))
# The ledger MUST stay tomllib-parseable after every transition: verify the
# tmp file round-trips BEFORE it replaces the live ledger.
try:
    with open(tmp, 'rb') as f:
        tomllib.load(f)
except Exception as exc:
    os.unlink(tmp)
    sys.stderr.write('_ledger_update: ERROR serialized ledger failed round-trip parse: ' + str(exc) + '\n')
    sys.exit(4)
os.replace(tmp, path)
# The lead's own write is the new baseline for the ledger itself.
os.makedirs(state, exist_ok=True)
shutil.copyfile(path, copy_file + '.tmp')
os.replace(copy_file + '.tmp', copy_file)
with open(digest_file + '.tmp', 'w') as f:
    f.write(_sha(path) + '\n')
os.replace(digest_file + '.tmp', digest_file)
if alert:
    sys.stderr.write('_ledger_update: WARNING ' + alert + '\n')
" "$@"
  RC=$?
  rm -rf "$LOCK" 2>/dev/null || true   # lock dir now carries a pid file — rm -rf, not rmdir
  return $RC
}

# _ledger_get <task_id> <key> — print the value ('' when the key is unset);
# nonzero when the ledger or the lease row is missing entirely.
_ledger_get() {
  local LEDGER
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  [ -f "$LEDGER" ] || return 1
  LEDGER_FILE="$LEDGER" LEDGER_TASK="$1" LEDGER_KEY="$2" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(1)
with open(os.environ['LEDGER_FILE'], 'rb') as f:
    data = tomllib.load(f)
task = os.environ['LEDGER_TASK']
row = data.get('baseline') if task == '@baseline' else data.get('lease', {}).get(task)
if not isinstance(row, dict):
    sys.exit(1)
print(row.get(os.environ['LEDGER_KEY'], ''))
"
}

# _ledger_get_row <task_id> <key...> — several keys of one row in one ledger
# read, printed one value per line in the order asked ('' for an unset key).
# The reserved id @baseline reads the [baseline] table, as in _ledger_get.
# Nonzero when the ledger or the row is missing, or when a value spans lines
# (one line per key could not carry it). Callers read the lines with
# `IFS= read -r VAR || true`.
_ledger_get_row() {
  local T=$1
  shift
  _lease_ctx || return 1
  [ -f "$_LEASE_LEDGER" ] || return 1
  LEDGER_FILE="$_LEASE_LEDGER" LEDGER_TASK="$T" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(1)
with open(os.environ['LEDGER_FILE'], 'rb') as f:
    data = tomllib.load(f)
task = os.environ['LEDGER_TASK']
row = data.get('baseline') if task == '@baseline' else data.get('lease', {}).get(task)
if not isinstance(row, dict):
    sys.exit(1)
vals = [str(row.get(k, '')) for k in sys.argv[1:]]
if any('\n' in v for v in vals):
    sys.exit(1)
print('\n'.join(vals))
" "$@"
}

# ---------------------------------------------------------------------------
# Integrity detection (KTD18) — the lead's verified git state and its check
# ---------------------------------------------------------------------------
#
# The baseline is the lead's last verified state:
#   [baseline] in the ledger  digests of .git/config, .git/hooks/, .git/info/
#                             (info/refs left out: git gc/repack rewrites it),
#                             the global git config files, the lead's trusted
#                             git config (<lease root>/lead/gitconfig, which
#                             every _lead_git call reads) and the lead
#                             checkout's own .git (a linked-worktree checkout's
#                             pointer file could be redirected); the default
#                             branch and its SHA; the integration branch and
#                             its SHA (updated after each of the lead's merges,
#                             cleared by a promotion)
#   each lease row            its worktree's .git pointer file and admin dir
#                             (.git/worktrees/<name>: HEAD, gitdir, commondir,
#                             config.worktree), base_sha, and the collect
#                             snapshot (snapshot_sha, snapshot_tree)
#   <lease root>/lead/        copies of .git/config (config.copy), .git/hooks
#                             (hooks.copy) and the trusted git config
#                             (gitconfig.copy), for restoring; plus the
#                             ledger's copy and digest (ledger.copy,
#                             ledger.sha256), which only _ledger_update writes
# _lead_integrity_check runs at lease_create, lease_dispatch, lease_pin_reviewer,
# lease_collect, lease_merge, lease_promote, lease_requeue,
# lease_heartbeat_check and lease_wait (on entry, every 15 s while it waits,
# before it acts on a row, and on return). A change the lead did not make
# restores what can be restored (.git/config, .git/hooks, the trusted git
# config) — only from a lead copy whose digest still equals the baseline, and
# only after saving the changed version as <lease root>/lead/<name>.changed-<UTC
# time> (it may have been the lead's or the user's: git remote add, pre-commit
# install) — escalates, names the changed surface, and returns
# _RC_LEASE_INTEGRITY (44). The ledger is not compared here: the check first
# runs _ledger_update's own rule under the ledger lock (a no-op @baseline write
# that restores a changed ledger from its copy and sets [baseline].ledger_alert),
# then reports the alert. .git/info, the global git config and the lead
# checkout's .git are detect-only. A repo-wide change escalates every
# building/review lease (any of their builders could have made it); a
# per-lease change escalates that lease. lease_rebaseline accepts a
# change the lead or user made to any surface but the ledger (a ledger change
# is never accepted; its alert waits for the next check), resumes the named
# leases the check escalated, and records each acceptance in [baseline]
# (last_rebaseline, rebaseline_log) — an audit trail, not prevention.
_RC_LEASE_INTEGRITY=44

_LEAD_INTEGRITY_PY='
import hashlib, os, secrets, shutil, stat, sys, time
try:
    import tomllib
except ImportError:
    import tomli as tomllib

def _sha(b):
    return hashlib.sha256(b).hexdigest()

# read_regular <path> — the bytes of a regular file. Opened O_NONBLOCK, so a
# FIFO a worker planted on a surface fails here (OSError) instead of blocking
# the check before its type is known (Phase 3 round 4, B6).
def read_regular(p):
    fd = os.open(p, os.O_RDONLY | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_CLOEXEC", 0))
    with os.fdopen(fd, "rb") as f:
        if not stat.S_ISREG(os.fstat(f.fileno()).st_mode):
            raise OSError("not a regular file: " + p)
        return f.read()

def file_digest(p):
    try:
        if os.path.islink(p):
            return "link:" + os.readlink(p)
        if os.path.isdir(p):
            return "dir:" + tree_digest(p)
        return _sha(read_regular(p))
    except FileNotFoundError:
        return "absent"
    except OSError as e:
        return "unreadable:" + type(e).__name__

# ignore: top-level entry names left out of the digest. Only .git/info uses it
# (refs: git gc and repack rewrite info/refs through update-server-info during
# normal use, and would otherwise escalate every lease).
def tree_digest(p, ignore=()):
    if os.path.islink(p):
        return "link:" + os.readlink(p)
    if not os.path.isdir(p):
        return file_digest(p) if os.path.lexists(p) else "absent"
    entries = []
    for root, dirs, files in os.walk(p):
        if ignore and root == p:
            dirs[:] = [n for n in dirs if n not in ignore]
            files = [n for n in files if n not in ignore]
        dirs.sort()
        for n in dirs + files:
            full = os.path.join(root, n)
            rel = os.path.relpath(full, p)
            try:
                st = os.lstat(full)
            except OSError:
                continue
            if stat.S_ISLNK(st.st_mode):
                entries.append((rel, "L", os.readlink(full)))
            elif stat.S_ISDIR(st.st_mode):
                entries.append((rel, "D", ""))
            else:
                try:
                    entries.append((rel, "F%o" % (st.st_mode & 0o111), _sha(read_regular(full))))
                except OSError:
                    entries.append((rel, "U", ""))
    h = hashlib.sha256()
    for e in sorted(entries):
        h.update(("\0".join(e) + "\n").encode("utf-8", "surrogateescape"))
    return h.hexdigest()

def admin_digest(admin):
    parts = [n + "=" + file_digest(os.path.join(admin, n)) for n in ("HEAD", "commondir", "gitdir", "config.worktree")]
    return _sha("\n".join(parts).encode("utf-8", "surrogateescape"))

def global_digest():
    home = os.environ.get("HOME", "")
    xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(home, ".config")
    files = [os.path.join(home, ".gitconfig"), os.path.join(xdg, "git", "config")]
    return _sha("\n".join(f + "=" + file_digest(f) for f in files).encode("utf-8", "surrogateescape"))

# The .git of the lead checkout: "dir" for a real directory, "link:<target>"
# for a symlink, else the digest of the pointer file of a linked-worktree
# checkout (a builder could point it at a lease admin dir, and _lease_ctx would
# bind every _lgr call to it).
def checkout_digest(repo):
    p = os.path.join(repo, ".git")
    try:
        if os.path.islink(p):
            return "link:" + os.readlink(p)
        if os.path.isdir(p):
            return "dir"
        return _sha(read_regular(p))
    except FileNotFoundError:
        return "absent"
    except OSError as e:
        return "unreadable:" + type(e).__name__

def repo_surfaces(common, state, repo, gitdir):
    # config.worktree lives in the gitdir of the checkout (== common for a
    # plain checkout; .git/worktrees/<name> for a linked-worktree lead) and is
    # read after .git/config once extensions.worktreeConfig is on, so a
    # driver or hook setting planted there reaches every _lgr call.
    cur = {"config": file_digest(os.path.join(common, "config")),
           "config_worktree": file_digest(os.path.join(gitdir, "config.worktree")),
           "hooks": tree_digest(os.path.join(common, "hooks")),
           "info": tree_digest(os.path.join(common, "info"), ("refs",)),
           "global_gitconfig": global_digest(),
           "lead_gitconfig": file_digest(os.path.join(state, "gitconfig")),
           "lease_record": file_digest(os.path.join(gitdir, RECORD_NAME))}
    if repo:
        cur["checkout"] = checkout_digest(repo)
    return cur

# The lease-root record (Phase 3 round 4, B4): <gitdir>/triforge-lease-root,
# in the git dir of the lead checkout (its own for a linked worktree, so two
# checkouts of one repository keep two records), names the lease root whose
# lead state dir holds the integrity anchors of this checkout. It lives outside
# TMPDIR and outside the ledger, so deleting ops/leases.toml no longer deletes
# the only reference to the anchors: a shell under another TMPDIR moves to the
# recorded root (_lease_at_ledger_root), and with the ledger gone the record
# is the evidence that refuses a fresh start (_lead_integrity_check). Written
# when the lead records its baseline (and, once, by the first check of a
# baseline recorded before it existed), and digested with the baseline
# (lease_record, detect-only), so a change or a removal is reported like any
# other surface.
RECORD_NAME = "triforge-lease-root"
RECORD_HEAD = "# Agent Triforge lease root of this checkout (KTD18): its lead/ dir holds the integrity anchors. Written by the lead; remove it only together with the lease ledger and that dir."

def read_text(p):
    return read_regular(p).decode("utf-8", "replace")

def read_record(gitdir):
    try:
        for line in read_text(os.path.join(gitdir, RECORD_NAME)).splitlines():
            if line.strip() and not line.startswith("#"):
                return line.strip()
    except OSError:
        pass
    return ""

def write_record(gitdir, root):
    if not root or read_record(gitdir) == root and os.path.isfile(os.path.join(gitdir, RECORD_NAME)) \
            and not os.path.islink(os.path.join(gitdir, RECORD_NAME)):
        return
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    for _ in range(8):
        tmp = os.path.join(gitdir, ".triforge-tmp-" + secrets.token_hex(8))
        try:
            fd = os.open(tmp, flags, 0o644)
        except FileExistsError:
            continue
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(RECORD_HEAD + "\n" + root + "\n")
        os.replace(tmp, os.path.join(gitdir, RECORD_NAME))
        return

def _remove(p):
    if os.path.islink(p) or os.path.isfile(p):
        os.unlink(p)
    elif os.path.isdir(p):
        shutil.rmtree(p)

mode = os.environ["LI_MODE"]
common = os.environ.get("LI_COMMON", "")
state = os.environ.get("LI_STATE", "")
repo = os.environ.get("LI_REPO", "")
gitdir = os.environ.get("LI_GITDIR", "") or common

# The restorable surfaces: name -> (live path, digest of that kind). The lead
# copy is <state>/<stem>.copy and a changed version kept before a restore is
# <state>/<stem>.changed-<UTC time>, where stem is the live basename (config,
# config.worktree, hooks, gitconfig). .git/config and .git/hooks live under the
# common dir, config.worktree under the gitdir of the checkout, the trusted git
# config under the lead state dir. Everything else is detect-only: .git/info
# (KTD18 restores config and hooks only), the global git config (a user file)
# and the .git of the lead checkout.
LIVE = {"config": (os.path.join(common, "config"), file_digest),
        "config_worktree": (os.path.join(gitdir, "config.worktree"), file_digest),
        "hooks": (os.path.join(common, "hooks"), tree_digest),
        "lead_gitconfig": (os.path.join(state, "gitconfig"), file_digest)}
RESTORABLE = tuple(sorted(LIVE))
NAMES = {"config": ".git/config", "config_worktree": ".git/config.worktree", "hooks": ".git/hooks/", "info": ".git/info/",
         "global_gitconfig": "the global git config (~/.gitconfig, ~/.config/git/config)",
         "lead_gitconfig": "the lead trusted git config (" + os.path.join(state, "gitconfig") + ")",
         "lease_record": "the lease-root record (" + os.path.join(gitdir, RECORD_NAME) + ")",
         "checkout": "the .git pointer of the lead checkout (" + os.path.join(repo, ".git") + ")"}

def _copy_path(name):
    return os.path.join(state, os.path.basename(LIVE[name][0]) + ".copy")

def save_copies():
    _remove(os.path.join(state, "info.copy"))    # left by builds that still restored .git/info
    for name in RESTORABLE:
        src, dst = LIVE[name][0], _copy_path(name)
        _remove(dst)
        if os.path.islink(src):
            continue
        if os.path.isdir(src):
            shutil.copytree(src, dst, symlinks=True)
        elif os.path.isfile(src):
            shutil.copyfile(src, dst)

# save_changed <name> — keep the changed surface before a restore overwrites
# it: the change may have been made by the lead or the user (git remote add,
# git push -u, pre-commit install), and lease_rebaseline can only accept what
# still exists.
# Returns the saved path, or "" when there is nothing to save (deleted).
def save_changed(name):
    live = LIVE[name][0]
    if not os.path.lexists(live):
        return ""
    base = os.path.join(state, os.path.basename(live) + ".changed-" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()))
    dst, n = base, 1
    while os.path.lexists(dst):
        n += 1
        dst = base + "-" + str(n)
    if os.path.islink(live):
        os.symlink(os.readlink(live), dst)
    elif os.path.isdir(live):
        shutil.copytree(live, dst, symlinks=True)
    else:
        shutil.copyfile(live, dst)
    return dst

# restore <name> <baseline digest> — put the surface back as the baseline
# recorded it, and say how. Only from a lead copy whose digest (of the same
# kind as the live one) still equals the baseline: the copy sits in the
# worker-writable lead state dir too. A surface absent at the baseline is
# restored by removing it. The changed version is saved first; a surface that
# can not be saved is not overwritten.
def restore(name, base_digest):
    live, digest = LIVE[name]
    copy = _copy_path(name)
    inspect = ", so it was NOT restored; inspect before lease_rebaseline"
    if base_digest != "absent":
        if not os.path.lexists(copy):
            return "no lead copy to restore from" + inspect
        if digest(copy) != base_digest:
            return "the lead copy also changed" + inspect
    try:
        saved = save_changed(name)
    except OSError as e:
        return "the changed version could not be saved (" + type(e).__name__ + ")" + inspect
    try:
        if base_digest == "absent":
            _remove(live)
            how = "removed: it did not exist at the baseline"
        else:
            tmp = live + ".triforge-restore"
            _remove(tmp)
            if os.path.isdir(copy) and not os.path.islink(copy):
                shutil.copytree(copy, tmp, symlinks=True)
                _remove(live)
            else:
                shutil.copyfile(copy, tmp)
                if os.path.isdir(live) and not os.path.islink(live):
                    shutil.rmtree(live)
            os.replace(tmp, live)
            how = "restored from the lead copy"
    except OSError as e:
        how = "the restore failed (" + type(e).__name__ + ")" + inspect
    return how + ("; the changed version is saved at " + saved if saved else "")

def admin_from_pointer(wt, common):
    try:
        line = read_text(os.path.join(wt, ".git")).strip()
    except OSError:
        return ""
    if not line.startswith("gitdir:"):
        return ""
    admin = os.path.realpath(os.path.join(wt, line[len("gitdir:"):].strip()))
    return admin if os.path.dirname(admin) == os.path.realpath(os.path.join(common, "worktrees")) else ""

if mode == "record":
    write_record(gitdir, os.environ.get("LI_ROOT", ""))
    save_copies()
    for k, v in sorted(repo_surfaces(common, state, repo, gitdir).items()):
        print(k + "=" + v)
    sys.exit(0)

# mode == "evidence": no ledger here — print what says this checkout had leases
# anyway (B4), one line each: the lease-root record, and lease worktrees git
# still lists for it (a lease/ branch checked out in a directory named like
# the lease root of this checkout, or the recorded one). Nothing printed: a fresh
# checkout.
if mode == "evidence":
    found = []
    rec_path = os.path.join(gitdir, RECORD_NAME)
    if os.path.lexists(rec_path):
        rec = read_record(gitdir)
        found.append("the lease-root record " + rec_path + (" (naming " + rec + ")" if rec else ""))
    names = set(n for n in (os.path.basename(os.environ.get("LI_ROOT", "")), os.path.basename(read_record(gitdir))) if n)
    wts = os.path.join(common, "worktrees")
    for n in (sorted(os.listdir(wts)) if os.path.isdir(wts) else []):
        try:
            head = read_text(os.path.join(wts, n, "HEAD")).strip()
            wt = os.path.dirname(read_text(os.path.join(wts, n, "gitdir")).strip())
        except OSError:
            continue
        if head.startswith("ref: refs/heads/lease/") and os.path.basename(os.path.dirname(wt)) in names:
            found.append("the lease worktree " + wt + " (" + head[len("ref: refs/heads/"):] + ")")
    for line in found[:6]:
        print("".join(c for c in line if c >= " " and c != "\x7f"))
    sys.exit(0)

if mode == "lease":
    wt, admin = os.environ["LI_WT"], os.environ.get("LI_ADMIN", "")
    admin = admin or admin_from_pointer(wt, common)
    print(file_digest(os.path.join(wt, ".git")) + "\t" + admin_digest(admin) + "\t" + admin)
    sys.exit(0)

# mode == "check": compare, restore (LI_RESTORE=1), report one line per finding.
# The ledger itself is not compared here: the caller ran _ledger_update first,
# which decides that rule under the ledger lock and leaves [baseline].ledger_alert
# set when it had to restore; reported even without a baseline, so an alert on a
# ledger that lost its [baseline] is not recorded away as a first use.
restoring = os.environ.get("LI_RESTORE") == "1"
force_record = os.environ.get("LI_FORCE_RECORD") == "1"
ledger = os.environ["LI_LEDGER"]
out = []
data = {}
if os.path.isfile(ledger):
    with open(ledger, "rb") as f:
        data = tomllib.load(f)
base = data.get("baseline")
leases = data.get("lease", {})
leases = leases if isinstance(leases, dict) else {}
if isinstance(base, dict) and base.get("ledger_alert"):
    out.append(("REPO", "ledger_alert", str(base["ledger_alert"])))
if not isinstance(base, dict) or not base.get("config"):
    # No [baseline]: first use, or a pre-3.3.3 ledger — unless the rows carry
    # keys only a 3.3.3 lead writes with a baseline in place: then the table
    # was removed from the ledger (and the digest anchors with it, or the
    # ledger rule would have restored it). That is a change, never a first use.
    stamped = sorted(t for t, r in leases.items() if isinstance(r, dict)
                     and any(k in r for k in ("pointer_digest", "admin_digest", "admin_dir", "snapshot_sha", "integrity_prev_state")))
    anchors = [n for n in ("config.copy", "hooks.copy", "ledger.copy") if os.path.lexists(os.path.join(state, n))]
    if stamped or anchors:
        why = ("lease row(s) " + ", ".join(stamped[:5]) + " were written with it in place") if stamped \
              else ("the lead state dir holds " + ", ".join(anchors) + ", saved when that table was recorded")
        out.append(("REPO", "baseline_missing", "the [baseline] table of the ledger is missing, but " + why
                    + ": ops/leases.toml was edited outside the lead writes (not restored: no verified copy; compare it with "
                    + os.path.join(state, "ledger.copy") + " and restore it yourself, then lease_rebaseline)"))
    else:
        out.append(("NOBASELINE", "", ""))
    base = None
else:
    if not base.get("lease_record"):
        # a baseline recorded before the lease-root record existed: write the
        # record now, once, and have the caller add its digest to [baseline]
        write_record(gitdir, os.environ.get("LI_ROOT", ""))
        out.append(("BASEREC", "lease_record", file_digest(os.path.join(gitdir, RECORD_NAME))))
    cur = repo_surfaces(common, state, repo, gitdir)
    for k in sorted(cur):
        b = str(base.get(k, ""))
        if b and cur[k] != b:
            if restoring and k in RESTORABLE:
                how = restore(k, b)
            elif k == "global_gitconfig":
                how = "not restored: a user file"
            else:
                how = "detected; not restored"
            out.append(("REPO", k, NAMES[k] + " changed (" + how + ")"))
    dname, dsha = os.environ.get("LI_DEF", ""), os.environ.get("LI_DEF_SHA", "")
    bname, bsha = str(base.get("default_branch", "")), str(base.get("default_sha", ""))
    if bname and dname != bname:
        out.append(("REPO", "default_branch", "the default branch now resolves to \"" + dname + "\" (was \"" + bname + "\"; origin/HEAD or the local main/master refs changed)"))
    elif bname and bsha and dsha != bsha:
        out.append(("REPO", "default_sha", "refs/heads/" + bname + " moved " + bsha[:12] + " -> " + (dsha[:12] or "<deleted>")))
for t in sorted(leases):
    r = leases[t]
    if not isinstance(r, dict):
        continue
    st = str(r.get("state", ""))
    if st in ("building", "review"):
        out.append(("OPEN", t, st))
    wt = str(r.get("worktree", ""))
    if st not in ("leased", "building", "review") and not (force_record and st == "escalated"):
        continue
    if not wt or not os.path.isdir(wt):
        continue
    admin = str(r.get("admin_dir", "")) or admin_from_pointer(wt, common)
    if not admin:
        continue
    pointer, adm = file_digest(os.path.join(wt, ".git")), admin_digest(admin)
    if force_record or not r.get("pointer_digest") or not r.get("admin_digest"):
        out.append(("RECORD", t, pointer, adm, admin))
        continue
    if pointer != str(r.get("pointer_digest")):
        out.append(("LEASE", t, st, wt + "/.git (the worktree pointer file) changed"))
    if adm != str(r.get("admin_digest")):
        out.append(("LEASE", t, st, admin + " (HEAD, gitdir, commondir or config.worktree) changed"))
for row in out:
    print("\t".join(row))
'

# _lead_baseline_record — record the lead's verified repo-wide state (the
# [baseline] digests + the copies in the lead state dir). Callers run it only
# on a state they just verified or explicitly accept (lease_rebaseline). It
# leaves [baseline].ledger_alert alone: only _lead_integrity_check clears it,
# after escalating it, so a rebaseline can't accept a ledger change. [writer]
# is _ledger_update unless lease_approve, which writes through _ledger_write,
# names that (a first promotion approval in a checkout with no baseline yet).
_lead_baseline_record() {
  local L WRITER=${1:-_ledger_update}
  local -a ARGS=()
  _lease_ctx || return 1
  _lease_default_ref
  while IFS= read -r L; do
    if [ -n "$L" ]; then ARGS+=("$L"); fi
  done <<BASELINE_EOF
$(LI_MODE=record LI_COMMON="$_LEASE_COMMON" LI_GITDIR="$_LEASE_GITDIR" LI_STATE="$_LEASE_STATE" LI_REPO="$_LEASE_REPO" LI_ROOT="$_LEASE_ROOT" python3 -c "$_LEAD_INTEGRITY_PY")
BASELINE_EOF
  # config, config_worktree, hooks, info, global_gitconfig, lead_gitconfig,
  # lease_record, checkout.
  if [ "${#ARGS[@]}" -lt 8 ]; then
    echo "lease: ERROR could not record the integrity baseline (KTD18)" >&2
    return 1
  fi
  "$WRITER" @baseline "${ARGS[@]}" default_branch="$_LEASE_DEF" default_sha="$_LEASE_DEF_SHA" \
    recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# _lead_lease_digests <worktree> [admin-dir] — "<pointer-digest>\t<admin-digest>\t<admin-dir>"
# for a lease worktree (the admin dir is derived from the pointer when not given
# — only right after the lead itself created the worktree).
_lead_lease_digests() {
  _lease_ctx || return 1
  LI_MODE=lease LI_COMMON="$_LEASE_COMMON" LI_WT="$1" LI_ADMIN="${2:-}" python3 -c "$_LEAD_INTEGRITY_PY"
}

# _lead_lease_evidence <op> — 0 when this checkout shows no lease history
# beyond its ledger: no lease-root record in its git dir and no lease worktree
# git lists for it (the "evidence" mode of _LEAD_INTEGRITY_PY). 1 otherwise,
# after the refusal on stderr, which names the evidence, where the lead's
# anchors are, and the deliberate reset; and 1 when the evidence can't be read
# (fail closed). Called with no ledger and no anchors in this lease root.
_lead_lease_evidence() {
  local OP=${1:-lease} EV="" RC=0 SHOWN=""
  EV=$(LI_MODE=evidence LI_COMMON="$_LEASE_COMMON" LI_GITDIR="$_LEASE_GITDIR" LI_ROOT="$_LEASE_ROOT" python3 -c "$_LEAD_INTEGRITY_PY" 2>/dev/null) || RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "${OP}: INTEGRITY CHECK COULD NOT RUN — ${_LEASE_LEDGER} is missing and whether this checkout had leases could not be read; treated as a change (fail closed, KTD18)." >&2
    return 1
  fi
  [ -n "$EV" ] || return 0
  SHOWN=$(printf '%s\n' "$EV" | sed 's/^/    /')
  echo "${OP}: INTEGRITY — ${_LEASE_LEDGER} is missing, but this checkout has lease history, and this shell's lease root ${_LEASE_ROOT} holds no anchors for it (KTD18; detection, not prevention):" >&2
  printf '%s\n' "$SHOWN" >&2
  echo "  The ledger was deleted, or this shell resolves another lease root than the lead's (another TMPDIR). Nothing was checked, merged or promoted, and no session starts on it. If the lead's lease root still exists, point this shell at it (export TRIFORGE_LEASE_ROOT=<that root>, named in the record) and rerun: its check restores the ledger from the lead's copy and reports the change. If you removed the ledger on purpose, remove that evidence too (the record, and each lease worktree: git worktree remove --force <path>, then git branch -D lease/<task>), then rerun." >&2
  return 1
}

# _lead_integrity_check <op> — compare the git state with the lead's baseline.
# 0 when nothing changed (or no ledger exists yet); _RC_LEASE_INTEGRITY after
# restoring and escalating (see the section comment). Fails closed: a check
# that can't run is reported as a change.
_lead_integrity_check() {
  local OP=${1:-lease} LEDGER OUT RC=0 KIND A B C D TAB NL LU_ERR LU_RC=0
  local REPO_DESC="" OPEN="" LEASE_HITS="" ALERT=0 NOBASE=0 SAVED=0 T S ESCALATED=""
  TAB=$(printf '\t'); NL='
'
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  if [ ! -f "$LEDGER" ] && [ ! -f "${_LEASE_STATE}/ledger.sha256" ]; then
    # No ledger and no ledger digest: nothing to compare against — unless the
    # lead state dir still holds the copies the lead saved for earlier leases.
    # Then a ledger existed and was deleted together with its digest, which
    # is a change, not a first use (fail closed, KTD18).
    if [ -e "${_LEASE_STATE}/ledger.copy" ] || [ -e "${_LEASE_STATE}/config.copy" ] || [ -e "${_LEASE_STATE}/hooks.copy" ]; then
      echo "${OP}: INTEGRITY — ${LEDGER} and its digest are gone, but the lead state dir ${_LEASE_STATE} holds copies saved for earlier leases: the ledger was deleted outside the lead's writes (KTD18; detection, not prevention). Nothing was merged or promoted. Inspect; to recover, copy ${_LEASE_STATE}/ledger.copy back to ${LEDGER} and run lease_rebaseline — or, if you removed the ledger on purpose, remove ${_LEASE_STATE} and ${_LEASE_GITDIR}/triforge-lease-root too." >&2
      return "$_RC_LEASE_INTEGRITY"
    fi
    # Nor does this lease root hold anything, but the checkout may still have
    # lease history elsewhere (Phase 3 round 4, B4): the lease-root record in
    # its git dir, or lease worktrees git lists for it. A ledger deleted while
    # the lead's anchors sit under another TMPDIR looks like a fresh checkout
    # from here; that evidence says it is not, so this refuses rather than
    # start over (fail closed). A fresh checkout has none of it.
    _lead_lease_evidence "$OP" || return "$_RC_LEASE_INTEGRITY"
    return 0
  fi
  # The ledger first, before anything reads a value from it, by its one guarded
  # writer (KTD18): a no-op @baseline write compares it with the lead's last
  # write under the ledger lock, restores it from the lead copy when it changed
  # and sets [baseline].ledger_alert, which the check below reports. On a ledger
  # with no [baseline] yet it writes one holding only `updated`, which the check
  # still reads as NOBASELINE. A write that can't run (a held lock, a ledger
  # with no intact copy that no longer parses) leaves the ledger unverified, so
  # it fails closed like a check that can't run.
  LU_ERR=$(_ledger_update @baseline 2>&1 >/dev/null) || LU_RC=$?
  if [ "$LU_RC" -eq "$_RC_LEAD_ONLY" ]; then
    # The writer's own lead-only guard refused this shell (a worker, a lease
    # root, not the lead's shell): a refusal, not a change; it still stops
    # the caller, with its own rc and message.
    printf '%s\n' "$LU_ERR" >&2
    return "$_RC_LEAD_ONLY"
  fi
  if [ "$LU_RC" -ne 0 ]; then
    echo "${OP}: INTEGRITY CHECK COULD NOT RUN — the ledger could not be verified under its lock; treated as a change (fail closed, KTD18): $(printf '%s' "$LU_ERR" | tail -3 | tr '\n' ' ' | cut -c1-300)" >&2
    return "$_RC_LEASE_INTEGRITY"
  fi
  _lease_default_ref
  OUT=$(LI_MODE=check LI_RESTORE=1 LI_COMMON="$_LEASE_COMMON" LI_GITDIR="$_LEASE_GITDIR" LI_STATE="$_LEASE_STATE" LI_REPO="$_LEASE_REPO" LI_LEDGER="$LEDGER" \
        LI_ROOT="$_LEASE_ROOT" LI_DEF="$_LEASE_DEF" LI_DEF_SHA="$_LEASE_DEF_SHA" python3 -c "$_LEAD_INTEGRITY_PY" 2>&1) || RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "${OP}: INTEGRITY CHECK COULD NOT RUN — treated as a change (fail closed, KTD18): $(printf '%s' "$OUT" | tail -3 | tr '\n' ' ' | cut -c1-300)" >&2
    return "$_RC_LEASE_INTEGRITY"
  fi
  while IFS="$TAB" read -r KIND A B C D; do
    case "$KIND" in
      NOBASELINE) NOBASE=1 ;;
      REPO)
        REPO_DESC="${REPO_DESC}${REPO_DESC:+${NL}}    ${B}"
        if [ "$A" = "ledger_alert" ]; then ALERT=1; fi
        case "$B" in *"the changed version is saved at "*) SAVED=1 ;; esac
        ;;
      OPEN) OPEN="${OPEN}${A}${TAB}${B}${NL}" ;;
      LEASE) LEASE_HITS="${LEASE_HITS}${A}${TAB}${B}${TAB}${C}${NL}" ;;
      RECORD) _ledger_update "$A" pointer_digest="$B" admin_digest="$C" admin_dir="$D" >/dev/null || return 1 ;;
      BASEREC) _ledger_update @baseline "${A}=${B}" >/dev/null || return 1 ;;   # the lease-root record, first written now
    esac
  done <<CHECK_EOF
${OUT}
CHECK_EOF
  if [ "$NOBASE" -eq 1 ]; then
    _lead_baseline_record || return 1
    echo "${OP}: NOTE integrity baseline recorded now (first use or a pre-3.3.3 ledger); changes made before this point can't be detected (KTD18)." >&2
  fi
  if [ -z "$REPO_DESC" ] && [ -z "$LEASE_HITS" ]; then return 0; fi
  if [ -n "$REPO_DESC" ]; then
    while IFS="$TAB" read -r T S; do
      [ -n "$T" ] || continue
      _ledger_update "$T" state=escalated integrity_prev_state="$S" reason="integrity (${OP}): git state changed outside the lead's operations" >/dev/null || true
      ESCALATED="${ESCALATED} ${T}"
    done <<OPEN_EOF
${OPEN}
OPEN_EOF
    if [ "$ALERT" -eq 1 ]; then _ledger_update @baseline ledger_alert="" >/dev/null || true; fi
  fi
  while IFS="$TAB" read -r T S C; do
    [ -n "$T" ] || continue
    case " ${ESCALATED} " in *" ${T} "*) continue ;; esac
    _ledger_update "$T" state=escalated integrity_prev_state="$S" reason="integrity (${OP}): ${C}" >/dev/null || true
    ESCALATED="${ESCALATED} ${T}"
  done <<LEASE_EOF
${LEASE_HITS}
LEASE_EOF
  echo "${OP}: INTEGRITY — git state changed outside the lead's own operations (KTD18; this is detection, not prevention):" >&2
  if [ -n "$REPO_DESC" ]; then printf '%s\n' "$REPO_DESC" >&2; fi
  printf '%s' "$LEASE_HITS" | while IFS="$TAB" read -r T S C; do
    if [ -n "$T" ]; then echo "    lease ${T}: ${C}" >&2; fi
  done
  echo "  escalated:${ESCALATED:- (no open lease)}. Nothing was merged or promoted. Inspect the change; a worker without an OS sandbox can write anything the user can. If you (the lead or the user) made it, accept it with: lease_rebaseline${ESCALATED}" >&2
  if [ "$SAVED" -eq 1 ]; then
    echo "  A restored surface's changed version is saved in the lead state dir (${_LEASE_STATE}/<name>.changed-<UTC time>): if the change was the lead's or the user's, copy that saved version back over the original, then run lease_rebaseline${ESCALATED}." >&2
  fi
  return "$_RC_LEASE_INTEGRITY"
}

# _lead_branch_switched <op> <recorded-branch> <recorded-sha> <current-branch>
# — print the refusal for a lead checkout that is no longer on the integration
# branch the lead recorded (KTD18): a builder shares .git and can check out
# another branch (or detach HEAD) in the lead's checkout, and the next merge,
# promotion or carve would then build on commits the lead never verified.
_lead_branch_switched() {
  local OP=$1 IB=$2 ISHA=$3 CUR=${4:-}
  echo "${OP}: REFUSED — the lead's integration branch is '${IB}' (at ${ISHA:0:12}) but the checkout is on '${CUR:-<detached HEAD>}' — a builder shares .git and can switch the lead's checkout; if you switched it yourself, run lease_rebaseline (it records the current branch) and rerun (KTD18)." >&2
}

# _lead_integration_check <op> — lease_merge and lease_promote build on the
# integration branch only from a state the lead verified: the checkout must be
# on the integration branch the lead recorded, and its tip must equal the SHA
# recorded after the lead's last merge (a builder can switch the checkout or
# move the branch, since it shares .git). Only when no integration branch is
# recorded yet (a new sprint, or the first merge after a promotion cleared it)
# is the current branch recorded as found. The default branch is never an
# integration branch: on it this check neither records nor refuses — lease_merge
# refuses to merge there on its own, lease_promote refuses to run from it, and
# the default branch's SHA is in the integrity baseline.
_lead_integration_check() {
  local OP=$1 IB="" ISHA="" CUR HEAD_SHA LOG ROW
  CUR=$(_lease_current_branch)
  if [ -n "$CUR" ] && [ "$CUR" = "$(_lease_default_branch)" ]; then
    return 0
  fi
  ROW=$(_ledger_get_row @baseline integration_branch integration_sha 2>/dev/null) || ROW=""
  { IFS= read -r IB || true; IFS= read -r ISHA || true; } <<INTEGRATION_ROW_EOF
${ROW}
INTEGRATION_ROW_EOF
  if [ -z "$IB" ] || [ -z "$ISHA" ]; then
    if [ -n "$CUR" ]; then
      HEAD_SHA=$(_lgr rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null || true)
      _ledger_update @baseline integration_branch="$CUR" integration_sha="$HEAD_SHA" >/dev/null || return 1
    fi
    return 0
  fi
  if [ "$IB" != "$CUR" ]; then
    _lead_branch_switched "$OP" "$IB" "$ISHA" "$CUR"
    return "$_RC_LEASE_INTEGRITY"
  fi
  HEAD_SHA=$(_lgr rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null || true)
  if [ "$ISHA" = "$HEAD_SHA" ]; then return 0; fi
  LOG=$(_lgr log --format='%h %s' "${ISHA}..${HEAD_SHA}" 2>/dev/null | head -5 | _scrub | cut -c1-100 | sed 's/^/      /' || true)
  echo "${OP}: REFUSED — the integration branch '${CUR}' moved since the lead's last merge (${ISHA:0:12} -> ${HEAD_SHA:0:12}). A builder shares .git and can move it, so Triforge merges and promotes only on top of a state it recorded (KTD18). New commits:" >&2
  if [ -n "$LOG" ]; then printf '%s\n' "$LOG" >&2; else echo "      (${ISHA:0:12} is no longer an ancestor — history was rewritten)" >&2; fi
  echo "  If these are your own commits, accept them with: lease_rebaseline — then rerun." >&2
  return "$_RC_LEASE_INTEGRITY"
}

# lease_rebaseline [task_id...] — accept the current git state as the lead's
# verified baseline: the repo-wide digests and copies, the default and
# integration branch SHAs, and every open lease's pointer/admin digests. Named
# leases that an integrity check escalated return to the state they were in.
# Run it only after inspecting what it prints; it is the lead's or the user's
# acceptance, never a worker's. Each acceptance is recorded (audit, not
# prevention — a worker can call this too): [baseline].last_rebaseline gets
# "<UTC ISO> by <user> via tty|non-tty; accepted: <surface keys that differed,
# or none>; resumed: <tasks, or none>", and the same line is appended to
# [baseline].rebaseline_log (the last 20, joined with " || "; ledger values
# are flat strings). A detached checkout or the default branch clears the
# integration branch (the default branch is never one, KTD18), so the next
# sprint branch the lead leases or merges on is recorded as found. The ledger
# itself is never accepted: a no-op @baseline write first runs _ledger_update's
# own rule, so a changed ledger is restored from the lead copy before the check
# reads a worktree or admin dir from it, and [baseline].ledger_alert stays set
# (reported here as NOT accepted) for the next _lead_integrity_check to escalate.
lease_rebaseline() {
  _lead_only lease_rebaseline || return $?
  local LEDGER OUT KIND A B C D TAB T PREV CUR NEW_IB="" IB_DESC HEAD_SHA="" IB="" ISHA="" ROW LU_ERR LU_RC=0 ACCEPTED="" RESUMED="" VIA LINE LOG
  TAB=$(printf '\t')
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  if [ ! -f "$LEDGER" ]; then
    echo "lease_rebaseline: no lease ledger (${LEDGER}) — nothing to rebaseline" >&2
    return 0
  fi
  LU_ERR=$(_ledger_update @baseline 2>&1 >/dev/null) || LU_RC=$?
  if [ "$LU_RC" -ne 0 ]; then
    echo "lease_rebaseline: ERROR the ledger could not be verified under its lock — nothing accepted: $(printf '%s' "$LU_ERR" | tail -3 | tr '\n' ' ' | cut -c1-300)" >&2
    return 1
  fi
  _lease_default_ref
  OUT=$(LI_MODE=check LI_RESTORE=0 LI_FORCE_RECORD=1 LI_COMMON="$_LEASE_COMMON" LI_GITDIR="$_LEASE_GITDIR" LI_STATE="$_LEASE_STATE" LI_REPO="$_LEASE_REPO" LI_LEDGER="$LEDGER" \
        LI_DEF="$_LEASE_DEF" LI_DEF_SHA="$_LEASE_DEF_SHA" python3 -c "$_LEAD_INTEGRITY_PY") || { echo "lease_rebaseline: ERROR the integrity check could not run" >&2; return 1; }
  while IFS="$TAB" read -r KIND A B C D; do
    case "$KIND" in
      REPO)
        if [ "$A" = "ledger_alert" ]; then
          echo "lease_rebaseline: NOT accepting — ${B}: a ledger change is never accepted; the alert stays set, so the next lease_* call escalates the open leases (KTD18)" >&2
        elif [ "$A" = "baseline_missing" ]; then
          # The table is re-recorded below from the current state; the edit
          # itself is on record here, not accepted as a verified ledger.
          echo "lease_rebaseline: recording a new baseline over an edited ledger — ${B}" >&2
          ACCEPTED="${ACCEPTED:+${ACCEPTED},}baseline_missing"
        else
          echo "lease_rebaseline: accepting — ${B}" >&2
          case ",${ACCEPTED}," in
            *",${A},"*) ;;
            *) ACCEPTED="${ACCEPTED:+${ACCEPTED},}${A}" ;;
          esac
        fi
        ;;
      RECORD) _ledger_update "$A" pointer_digest="$B" admin_digest="$C" admin_dir="$D" >/dev/null || return 1 ;;
    esac
  done <<REBASE_EOF
${OUT}
REBASE_EOF
  _lead_baseline_record || return 1
  ROW=$(_ledger_get_row @baseline integration_branch integration_sha 2>/dev/null) || ROW=""
  { IFS= read -r IB || true; IFS= read -r ISHA || true; } <<REBASE_ROW_EOF
${ROW}
REBASE_ROW_EOF
  CUR=$(_lease_current_branch)
  if [ -n "$CUR" ] && [ "$CUR" != "$_LEASE_DEF" ]; then
    NEW_IB=$CUR
    HEAD_SHA=$(_lgr rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null || true)
  fi
  IB_DESC=$NEW_IB
  if [ -z "$NEW_IB" ]; then
    if [ -n "$CUR" ]; then IB_DESC="<none: ${CUR} is the default branch>"; else IB_DESC="<none: detached HEAD>"; fi
  fi
  if [ -n "$IB" ] && [ -n "$ISHA" ] && { [ "$IB" != "$NEW_IB" ] || [ "$ISHA" != "$HEAD_SHA" ]; }; then
    echo "lease_rebaseline: accepting — the integration branch ${IB} ${ISHA:0:12} -> ${IB_DESC} ${HEAD_SHA:0:12}" >&2
    ACCEPTED="${ACCEPTED:+${ACCEPTED},}integration"
  fi
  _ledger_update @baseline integration_branch="$NEW_IB" integration_sha="$HEAD_SHA" >/dev/null || return 1
  for T in "$@"; do
    PREV=$(_ledger_get "$T" integrity_prev_state 2>/dev/null || true)
    if [ -n "$PREV" ] && [ "$(_ledger_get "$T" state 2>/dev/null || true)" = "escalated" ]; then
      _ledger_update "$T" state="$PREV" integrity_prev_state="" reason="" >/dev/null || return 1
      echo "lease_rebaseline: ${T} back to '${PREV}'" >&2
      RESUMED="${RESUMED:+${RESUMED},}${T}"
    else
      echo "lease_rebaseline: ${T} was not escalated by an integrity check — state unchanged" >&2
    fi
  done
  if [ -t 0 ]; then VIA=tty; else VIA=non-tty; fi
  LINE="$(date -u +%Y-%m-%dT%H:%M:%SZ) by ${USER:-unknown} via ${VIA}; accepted: ${ACCEPTED:-none}; resumed: ${RESUMED:-none}"
  LOG=$(_ledger_get @baseline rebaseline_log 2>/dev/null || true)
  LOG=$(RB_LOG="$LOG" RB_LINE="$LINE" python3 -c '
import os
log = [e for e in os.environ["RB_LOG"].split(" || ") if e.strip()]
log.append(os.environ["RB_LINE"])
print(" || ".join(log[-20:]))
') || LOG=$LINE
  _ledger_update @baseline last_rebaseline="$LINE" rebaseline_log="$LOG" >/dev/null || return 1
  echo "lease_rebaseline: baseline recorded (default ${_LEASE_DEF:-<none>} ${_LEASE_DEF_SHA:0:12}, integration ${IB_DESC} ${HEAD_SHA:0:12}); ${LINE}" >&2
}

# _adapter_env <cli> <cmd...> — run an external command under the per-adapter
# environment allowlist (KTD-14): the base allowlist TRIFORGE_ENV_BASE (HOME
# PATH TMPDIR TERM LANG COLORTERM USER — scripts/lib/registry.sh; USER is
# identity, not a secret: Claude Code resolves its keychain account from it, so
# without it `claude -p` under env -i answers "Not logged in" on every macOS
# host — live bisect 2026-09-11, LOGNAME alone does not help) + NO_COLOR=1 +
# the worker marker TRIFORGE_LEASE_WORKER (KTD9) + the GIT_CONFIG_* no-push
# backstop (CS1), plus ONLY the invoked CLI's own
# credential variables: its registry entry's env_keys (opencode:
# OPENROUTER_API_KEY; kimi: KIMI_*; cursor: CURSOR_API_KEY). claude, codex,
# and antigravity list none — they authenticate via HOME-based stores and get
# nothing extra — no cross-provider leakage; a CLI the registry does not know
# gets the base allowlist alone. Two lanes add fixed values of their own:
# claude _ADAPTER_ENV_CLAUDE, opencode its OPENCODE_PERMISSION deny set. env -i
# execs external commands only; shell functions cannot cross it, which is why
# the lease lane composes direct CLI commands (_lease_lane_argv,
# scripts/lib/lease-wait.sh) instead of calling the invoke_* helpers. Mirrored
# by _lane_run in scripts/probe-capabilities.sh, which reads the same base
# list, and by _lane_run_claude there, which reads _ADAPTER_ENV_CLAUDE.
# The env_keys are one registry read here unless lease_dispatch, which already
# read them together with the model, hands them over in _ADAPTER_ENV_KEYS (set
# inside the detached builder process only, so the lead's shell never carries it).
#
# _adapter_env_forward <NAME> — append NAME=value to the caller's PAIRS when the
# variable is set (set-and-empty included): the one rule for the base allowlist
# and for a CLI's exact-named credential keys. Read through eval rather than
# ${!V} indirect expansion: this file is `source`d under the CALLER's shell (the
# commands do a plain `source`, which ignores the bash shebang), and on macOS
# that is zsh, where ${!V} raises "bad substitution" and would kill every lease
# dispatch. Every NAME is a registry literal (scripts/validate-versions.sh
# check 3 keeps them to [A-Z_][A-Z0-9_]*), and the guard below is the eval's
# own gate: a name that is not a variable name is dropped with a notice and
# rc 0 (the caller runs under set -e), so nothing a shell expansion or a
# registry edit produces can reach the eval. The letters are spelled out
# because bash collates a [A-Z] range by locale (de_DE.UTF-8 lets É through).
_adapter_env_forward() {
  local _SET="" _VAL=""
  case "$1" in
    "" | [0123456789]* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_]*)
      echo "_adapter_env: not a variable name, not forwarded: '${1}'" >&2
      return 0
      ;;
  esac
  eval "_SET=\${${1}+x}"
  if [ -n "$_SET" ]; then
    eval "_VAL=\${${1}}"
    PAIRS+=("${1}=${_VAL}")
  fi
}
# The claude lane's own values (KTD16): no background task outlives a worker's
# turn (a headless `claude -p` that ends its turn waiting on one dies with it),
# and a worker never updates the user's Claude Code install. _lane_run's claude
# rows in scripts/probe-capabilities.sh read this array through the loader.
_ADAPTER_ENV_CLAUDE=(CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1 DISABLE_AUTOUPDATER=1)
_adapter_env() {
  local CLI=$1
  shift
  local -a PAIRS=()
  local _K _KEYS _kv_b64
  # Base allowlist — each registry key forwarded when set (_adapter_env_forward).
  # Both key lists are read one name per line from a here-doc, never with
  # `for _K in $LIST` or `$(printf '%s' "$LIST")`: bash pathname-expands every
  # word of an unquoted expansion, so from a lease worktree (lease_dispatch cd's
  # into it) a key such as KIMI_* became the matching file names — builder-
  # chosen text that reached the eval in _adapter_env_forward. A here-doc keeps
  # the loop in this shell, where it can append to PAIRS (a pipeline could not).
  while IFS= read -r _K; do
    [ -n "$_K" ] || continue
    _adapter_env_forward "$_K"
  done <<BASEKEYS
$(printf '%s' "$TRIFORGE_ENV_BASE" | tr ' ' '\n')
BASEKEYS
  PAIRS+=("NO_COLOR=1")   # captured output is parsed, never rendered (U5)
  # Worker marker (KTD9): hook handlers exit at once and lead-owned helpers
  # refuse (_lead_only) anywhere in the worker's process tree. Two values:
  # builder (every lease build) and persona: U25's dispatch_persona will set
  # _ADAPTER_WORKER=persona inside its dispatch subshell, the way
  # lease_dispatch hands over _ADAPTER_ENV_KEYS.
  case "${_ADAPTER_WORKER:-builder}" in
    persona) PAIRS+=("TRIFORGE_LEASE_WORKER=persona") ;;
    *)       PAIRS+=("TRIFORGE_LEASE_WORKER=builder") ;;
  esac
  # No-push backstop (CS1): git honors GIT_CONFIG_COUNT/KEY_n/VALUE_n as
  # per-process config, so every git in the builder's process tree sees (a)
  # core.hooksPath -> the shipped pre-push hook that refuses, and (b)
  # url.<scheme>.pushInsteadOf rewrites that turn any push URL into an
  # unresolvable no-push:// address. Builders commit nothing and never push
  # (KTD11); this makes the prompt-level rule mechanical. Reads (status, log,
  # diff, fetch) are untouched.
  PAIRS+=("GIT_CONFIG_COUNT=6"
          "GIT_CONFIG_KEY_0=core.hooksPath" "GIT_CONFIG_VALUE_0=${_TRIFORGE_SCRIPTS_DIR}/lease-git-hooks"
          "GIT_CONFIG_KEY_1=url.no-push://lease-worktree/.pushInsteadOf" "GIT_CONFIG_VALUE_1=https://"
          "GIT_CONFIG_KEY_2=url.no-push://lease-worktree/.pushInsteadOf" "GIT_CONFIG_VALUE_2=ssh://"
          "GIT_CONFIG_KEY_3=url.no-push://lease-worktree/.pushInsteadOf" "GIT_CONFIG_VALUE_3=git@"
          "GIT_CONFIG_KEY_4=url.no-push://lease-worktree/.pushInsteadOf" "GIT_CONFIG_VALUE_4=git://"
          "GIT_CONFIG_KEY_5=url.no-push://lease-worktree/.pushInsteadOf" "GIT_CONFIG_VALUE_5=file://")
  # The CLI's own credential variables — its registry env_keys (_ADAPTER_ENV_KEYS
  # when lease_dispatch pre-read them, see above). An exact name is forwarded
  # when set; a trailing * (the one documented wildcard, kimi's KIMI_*) forwards
  # every EXPORTED variable with that prefix: `compgen` and ${!V} are bash-only,
  # so python3 (already required) enumerates os.environ and emits each matching
  # NAME=VALUE pair base64-encoded, one per line. base64 has no internal
  # newlines, so line-based read is portable across bash and zsh AND preserves
  # values that themselves contain newlines or `=`.
  if [ -n "${_ADAPTER_ENV_KEYS+x}" ]; then
    _KEYS=$_ADAPTER_ENV_KEYS
  else
    _KEYS=$(cli_field "$CLI" env_keys 2>/dev/null) || _KEYS=""
  fi
  while IFS= read -r _K; do
    [ -n "$_K" ] || continue
    case "$_K" in
      *\*)
        while IFS= read -r _kv_b64; do
          [ -n "$_kv_b64" ] && PAIRS+=("$(printf '%s' "$_kv_b64" | base64 -d 2>/dev/null)")
        done <<PREFIXENV
$(TRIFORGE_ENV_PREFIX="${_K%\*}" python3 -c "
import os, base64, sys
prefix = os.environ['TRIFORGE_ENV_PREFIX']
for k, v in os.environ.items():
    if k.startswith(prefix) and k != 'TRIFORGE_ENV_PREFIX':
        sys.stdout.write(base64.b64encode((k + '=' + v).encode()).decode() + '\n')
")
PREFIXENV
        ;;
      *)
        _adapter_env_forward "$_K"
        ;;
    esac
  done <<ENVKEYS
$(printf '%s' "$_KEYS" | tr ' ' '\n')
ENVKEYS
  case "$CLI" in
    claude)
      PAIRS+=("${_ADAPTER_ENV_CLAUDE[@]}")
      ;;
    opencode)
      # D-033 defense-in-depth: the shipped deny set rides as OPENCODE_PERMISSION
      # (caller's own value wins) — the adapter stays off --auto regardless. A
      # value injection, not an allowlist key, so it stays a lane arm here.
      PAIRS+=("OPENCODE_PERMISSION=${OPENCODE_PERMISSION:-$_OPENCODE_PERMISSION_DEFAULT}")
      ;;
  esac
  env -i "${PAIRS[@]}" "$@"
}

# Absolute path of the timeout binary, for lanes that exec it via env -i.
# Fail-closed like _run_with_timeout: no tool -> _RC_NO_TIMEOUT_TOOL.
_timeout_tool() {
  if command -v timeout >/dev/null 2>&1; then
    command -v timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    command -v gtimeout
  else
    echo "invoke-external.sh: ERROR neither \`timeout\` nor \`gtimeout\` is on PATH — refusing to dispatch a lease without timeout enforcement (fail-closed). Fix: on macOS run \`brew install coreutils\`, then retry." >&2
    return "$_RC_NO_TIMEOUT_TOOL"
  fi
}

# _lease_plugin_root — the real path of the Triforge plugin root this library
# was loaded from: ${_TRIFORGE_PLUGIN_ROOT}, which the loader resolved once
# (KTD6: the Claude Code plugin-root variable when it names a Triforge root,
# else the directory above the loader's own scripts/, else the loader refused
# to load — scripts/invoke-external.sh holds the one read of that variable). The only
# source for lease provisioning — never the project's own tree: a user
# project's skills/ or scripts/ is not Triforge's (R42). Empty + rc 1 only when
# the variable is somehow empty or no longer a Triforge root.
_lease_plugin_root() {
  if _triforge_is_plugin_root "${_TRIFORGE_PLUGIN_ROOT:-}"; then
    _lease_realpath "$_TRIFORGE_PLUGIN_ROOT"
    return 0
  fi
  return 1
}

# Worktrees lack .agents/skills/ (gitignored in user projects) — provision a
# copy so portable-skill discovery survives isolation. Same ownership rule as
# session start (KTD12): scripts/lib/skills-sync.py writes empty slots and
# refreshes only directories whose digest matches the stamp, so a user's own
# committed .agents/skills/<name>/ survives provisioning; a symlinked .agents
# or .agents/skills (or one resolving outside the worktree) is left untouched.
_lease_provision_skills() {
  local WT=$1 PROOT
  if ! PROOT=$(_lease_plugin_root); then
    echo "lease: WARNING the loaded plugin root (${_TRIFORGE_PLUGIN_ROOT:-<empty>}) is no longer a Triforge root — worktree gets no .agents/skills/ (reinstall the plugin)" >&2
    return 0
  fi
  if [ ! -f "${_TRIFORGE_SCRIPTS_DIR}/lib/skills-sync.py" ]; then
    echo "lease: WARNING ${_TRIFORGE_SCRIPTS_DIR}/lib/skills-sync.py is missing — worktree gets no .agents/skills/ (reinstall the plugin)" >&2
    return 0
  fi
  python3 "${_TRIFORGE_SCRIPTS_DIR}/lib/skills-sync.py" sync --plugin-root "$PROOT" --project "$WT" --prefix "lease: " >&2 \
    || echo "lease: WARNING skills provisioning failed for ${WT} (the builder may not see the portable skills)" >&2
  return 0
}

# _lease_provision_claude_skills <worktree> [<names,>] — the claude worker's
# copy (KTD16): Claude Code reads skills from .claude/skills, not .agents/skills.
# skills-sync.py add writes the same portable set there, names only: an entry
# already present (a tracked one, like this repo's .claude/skills/watch-cycle/)
# and each name in <names,> (the names git tracks there) stay as they are, and
# nothing is replaced, retired or stamped; the same symlink and realpath guards
# apply (KTD12).
_lease_provision_claude_skills() {
  local WT=$1 SKIP=${2:-} PROOT
  PROOT=$(_lease_plugin_root) || return 0
  [ -f "${_TRIFORGE_SCRIPTS_DIR}/lib/skills-sync.py" ] || return 0
  python3 "${_TRIFORGE_SCRIPTS_DIR}/lib/skills-sync.py" add --plugin-root "$PROOT" --project "$WT" --dest .claude/skills --skip "$SKIP" --prefix "lease: " >&2 \
    || echo "lease: WARNING .claude/skills provisioning failed for ${WT} (the claude builder may not see the portable skills)" >&2
  return 0
}

# _lease_provision <worktree> <builder-cli> — provision a worktree _lease_carve
# just made (it reads _CARVE_ADMIN) and append provisioned=<the paths that
# wrote> to _CARVE_FIELDS, the lease row's `provisioned` field (KTD9): the
# portable skills in .agents/skills, and for a claude builder in .claude/skills
# too. rc 1 when the list can't be read: a row without it would fall back to
# excluding all of .agents/.
_lease_provision() {
  local WT=$1 CLI=${2:-} LIST TRACKED=""
  local -a DIRS=(.agents/skills)
  _lease_provision_skills "$WT"
  case "$CLI" in
    claude)
      TRACKED=$(_lgw "$WT" "$_CARVE_ADMIN" ls-files -z -- .claude/skills 2>/dev/null | python3 -c '
import sys
names = set()
for p in sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\0"):
    parts = p.split("/")
    if len(parts) > 2 and parts[0] == ".claude" and parts[1] == "skills":
        names.add(parts[2])
print(",".join(sorted(names)))
') || TRACKED=""
      _lease_provision_claude_skills "$WT" "$TRACKED"
      DIRS+=(.claude/skills)
      ;;
  esac
  LIST=$(_lease_provisioned "$WT" "$_CARVE_ADMIN" "${DIRS[@]}") || {
    echo "lease: ERROR could not list the paths provisioning wrote into ${WT}, so the snapshot could not exclude exactly those (KTD9)" >&2
    return 1
  }
  _CARVE_FIELDS+=("provisioned=${LIST}")
}

# _lease_provisioned <worktree> <admin> <dir...> — print, space-separated, the
# paths provisioning wrote into a freshly carved worktree, or "none" (KTD9):
# each entry directly inside a provisioning <dir> (for .agents/skills, a
# skill directory or the digest stamp) under which git status sees a new,
# ignored, modified or deleted path. Run right after the carve and the
# provisioning, so every change it sees is provisioning's. The snapshot
# excludes exactly these; any other edit, under .agents/, .claude/ or .codex/
# included, merges and meets the protected-path check. An entry name outside
# [A-Za-z0-9._-] is not recorded (skills-sync.py writes none), so it stays in
# the snapshot where the lead sees it — the list errs toward merging.
_lease_provisioned() {
  local W=$1 A=$2 TMP RC=0
  shift 2
  TMP=$(mktemp "${TMPDIR:-/tmp}/triforge-provisioned.XXXXXX") || return 1
  # Into a file, so git's own exit status is checked (a pipeline would report
  # only python's, and a failed status would read as "nothing provisioned").
  _lgw "$W" "$A" status --porcelain=v1 -z --untracked-files=all --ignored=traditional -- "$@" > "$TMP" 2>/dev/null || RC=1
  if [ "$RC" -eq 0 ]; then
    python3 -c '
import re, sys
dirs = [d.rstrip("/") for d in sys.argv[1:]]
fields = sys.stdin.buffer.read().decode("utf-8", "surrogateescape").split("\0")
paths, i = [], 0
while i < len(fields):
    f = fields[i]
    i += 1
    if len(f) < 4:
        continue
    paths.append(f[3:])
    if f[0] in "RC":        # a rename or copy: the next field is its source
        if i < len(fields):
            paths.append(fields[i])
        i += 1
found = set()
for p in paths:
    for d in dirs:
        if p.startswith(d + "/"):
            entry = p[len(d) + 1:].split("/", 1)[0]
            if entry not in ("", ".", "..") and re.match(r"^[A-Za-z0-9._-]+$", entry):
                found.add(d + "/" + entry)
print(" ".join(sorted(found)) or "none")
' "$@" < "$TMP" || RC=1
  fi
  rm -f "$TMP"
  return "$RC"
}

# ---------------------------------------------------------------------------
# Worktree carve, collect snapshot and snapshot-only merge (KTD3, KTD18, KTD19)
# ---------------------------------------------------------------------------

# _lease_carve <task_id> <worktree> — the lease worktree + lease/<task> branch
# at the lead's current HEAD, through _lead_git (no hook runs, whatever a
# worker planted). Sets _CARVE_BASE (the recorded base SHA), _CARVE_ADMIN (the
# worktree's admin dir, read from the pointer the lead just created) and
# _CARVE_POINTER / _CARVE_ADMIN_DIGEST (the per-lease integrity baseline), and
# _CARVE_FIELDS: the key=value list every (re)carved lease row starts from
# (those four, the branch it was carved on — empty on the default branch, which
# is never an integration branch — the lease root it was carved under, and the
# cleared snapshot, integrity and protected-status fields and the claude
# session record (a fresh worktree starts a fresh session); _lease_provision then appends
# `provisioned`), passed as "${_CARVE_FIELDS[@]}" by lease_create and
# lease_requeue. Set only on success, and then never empty, so the expansion
# is safe under bash 3.2 `set -u` and in zsh.
_lease_carve() {
  local T=$1 WT=$2 D CUR
  _CARVE_BASE=""; _CARVE_ADMIN=""; _CARVE_POINTER=""; _CARVE_ADMIN_DIGEST=""; _CARVE_FIELDS=()
  _CARVE_BASE=$(_lgr rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null) || {
    echo "lease: ERROR the lead's checkout has no HEAD commit — commit something before leasing" >&2; return 1; }
  if ! _lgr worktree add "$WT" -b "lease/${T}" "$_CARVE_BASE" >&2; then
    echo "lease: ERROR git worktree add failed for task ${T}" >&2
    return 1
  fi
  D=$(_lead_lease_digests "$WT") || return 1
  _CARVE_POINTER=$(printf '%s\n' "$D" | cut -f1)
  _CARVE_ADMIN_DIGEST=$(printf '%s\n' "$D" | cut -f2)
  _CARVE_ADMIN=$(printf '%s\n' "$D" | cut -f3)
  if [ -z "$_CARVE_ADMIN" ]; then
    echo "lease: ERROR the new worktree's admin dir is not under ${_LEASE_COMMON}/worktrees — refusing to lease ${T}" >&2
    return 1
  fi
  CUR=$(_lease_current_branch)
  if [ -n "$CUR" ] && [ "$CUR" = "$(_lease_default_branch)" ]; then CUR=""; fi
  _CARVE_FIELDS=(base_sha="$_CARVE_BASE" admin_dir="$_CARVE_ADMIN" pointer_digest="$_CARVE_POINTER" admin_digest="$_CARVE_ADMIN_DIGEST"
                 integration_branch="$CUR" lease_root="$_LEASE_ROOT" snapshot_sha= snapshot_tree= builder_commits= integrity_prev_state=
                 protected= protected_paths=
                 session_id= resumed_session= result_subtype= result_is_error=)
}

# _lease_tree_of_worktree <worktree> <admin> <start-commit> [<provisioned>] —
# print the tree the worktree holds now, built in a throwaway index seeded
# from <start-commit>: every change, except the paths provisioning wrote
# (<provisioned>, the lease row's list from _lease_provisioned), which keep
# their <start-commit> content — provisioned copies never merge (KTD9).
# "none" excludes nothing; an empty list is a lease created before 4.0, which
# recorded none, and keeps the old rule: all of .agents/ excluded. The
# excluded paths are put back with `reset` after `add -A`, not left out with
# an exclude pathspec: `add` exits 1 when an excluded path is gitignored (a
# project that ignores .agents/, this one included), which failed every
# collect there. The worktree's own index and HEAD are not touched.
_lease_tree_of_worktree() {
  local W=$1 A=$2 START=$3 PROV=${4:-} IDXD TREE RC=0 P NKEEP=1
  local -a KEEP=(":(literal).agents")
  case "$PROV" in
    "") ;;
    none) NKEEP=0 ;;
    *)
      KEEP=()
      NKEEP=0
      while IFS= read -r P; do
        [ -n "$P" ] || continue
        KEEP+=(":(literal)${P}")
        NKEEP=$((NKEEP + 1))
      done <<PROVISIONED_EOF
$(printf '%s' "$PROV" | tr ' ' '\n')
PROVISIONED_EOF
      ;;
  esac
  IDXD=$(mktemp -d "${TMPDIR:-/tmp}/triforge-snap.XXXXXX") || return 1
  _LEAD_GIT_INDEX="${IDXD}/index"
  # KEEP is expanded only when NKEEP > 0 (never empty there: bash 3.2, set -u).
  { _lgw "$W" "$A" read-tree "$START" && _lgw "$W" "$A" add -A -- . >/dev/null \
      && { [ "$NKEEP" -eq 0 ] || _lgw "$W" "$A" reset -q "$START" -- "${KEEP[@]}" >/dev/null; } \
      && TREE=$(_lgw "$W" "$A" write-tree); } || RC=1
  _LEAD_GIT_INDEX=""
  rm -rf "$IDXD"
  [ "$RC" -eq 0 ] || return 1
  printf '%s\n' "$TREE"
}

# _lease_protected_scan <default-branch> <git diff revs...> — classify the
# paths a diff changes against the registry's protected lists (KTD8): both
# sides of every rename (--no-renames), NUL-separated (-z) so core.quotePath
# can't wrap a path in quotes that dodge a prefix match, a submodule entry
# listed whatever .gitmodules says (--ignore-submodules=none), and
# framework_protected only in the Triforge checkout
# (_lease_is_framework_checkout, which reads <default-branch> too). Sets
# _LP_HITS ("<list><TAB><path>" lines, empty for none), _LP_COUNT (how many)
# and _LP_ERR (why the scan could not run, empty when it ran): a caller reads a
# non-empty _LP_ERR as protected, so the scan fails closed. Also sets the lease
# row's values: _LP_STATUS (yes, no or unknown) and _LP_PATHS (the first ten
# paths, or the error). lease_promote scans <default>...HEAD; lease_collect and
# lease_merge scan base to snapshot (KTD3, U10).
_lease_protected_scan() {
  local DEF=$1 D FRAMEWORK=0
  shift
  _LP_HITS=""; _LP_COUNT=0; _LP_ERR=""; _LP_STATUS=unknown; _LP_PATHS=""
  if ! D=$(mktemp -d "${TMPDIR:-/tmp}/triforge-protected-scan.XXXXXX"); then
    _LP_ERR="could not create a temp dir for the scan"
    _LP_PATHS=$_LP_ERR
    return 0
  fi
  if ! _lgr diff -z --name-only --no-renames --no-ext-diff --ignore-submodules=none "$@" > "${D}/changed" 2> "${D}/err"; then
    _LP_ERR="git diff $* failed: $(head -c 300 "${D}/err" | tr '\n' ' ')"
  else
    if _lease_is_framework_checkout "$_LEASE_REPO" "$DEF"; then FRAMEWORK=1; fi
    if ! _protected_classify "$FRAMEWORK" < "${D}/changed" > "${D}/hits" 2> "${D}/err"; then
      _LP_ERR="protected-path classifier failed: $(tail -c 300 "${D}/err" | tr '\n' ' ')"
    else
      _LP_HITS=$(cat "${D}/hits")
    fi
  fi
  rm -rf "$D"
  if [ -n "$_LP_ERR" ]; then
    _LP_PATHS=$_LP_ERR
  elif [ -z "$_LP_HITS" ]; then
    _LP_STATUS=no
  else
    _LP_STATUS=yes
    _LP_COUNT=$(printf '%s\n' "$_LP_HITS" | grep -c . || true)
    _LP_PATHS=$(printf '%s\n' "$_LP_HITS" | cut -f2- | head -10 | tr '\n' ' ') || true
    _LP_PATHS=${_LP_PATHS% }
    if [ "$_LP_COUNT" -gt 10 ]; then _LP_PATHS="${_LP_PATHS} (+$((_LP_COUNT - 10)) more)"; fi
  fi
  return 0
}

# _lease_snapshot <task_id> — the lead's collect-time snapshot (KTD3): the
# builder's worktree as ONE lead-made commit on top of the recorded base,
# written to lease/<task> and recorded (snapshot_sha, snapshot_tree) so the
# review, the merge and any later approval bind to exactly this state, with
# the diff's protected status (protected, protected_paths). Each
# fix cycle writes a new snapshot on the same base. Commits the builder made
# itself (against the contract) are kept under the snapshot, recorded in
# builder_commits, and make lease_merge refuse (KTD19).
_lease_snapshot() {
  local T=$1 ROW WT ADMIN BASE BRANCH PREV BUILDER PROV TIP BC="" C TREE PARENT SNAP
  ROW=$(_ledger_get_row "$T" worktree admin_dir base_sha branch snapshot_sha builder_cli provisioned) || ROW=""
  { IFS= read -r WT || true; IFS= read -r ADMIN || true; IFS= read -r BASE || true
    IFS= read -r BRANCH || true; IFS= read -r PREV || true; IFS= read -r BUILDER || true
    IFS= read -r PROV || true; } <<SNAP_ROW_EOF
${ROW}
SNAP_ROW_EOF
  if [ ! -d "$WT" ]; then
    echo "lease_collect: ERROR worktree missing: ${WT}" >&2
    return 1
  fi
  if [ -z "$ADMIN" ]; then
    # A pre-3.3.3 lease: take the admin dir from the pointer once (trust at
    # first use), then bind to it like any other lease.
    ADMIN=$(_lead_lease_digests "$WT" | cut -f3)
    [ -n "$ADMIN" ] || { echo "lease_collect: ERROR can't locate ${T}'s admin dir under ${_LEASE_COMMON}/worktrees" >&2; return 1; }
    _ledger_update "$T" admin_dir="$ADMIN" || return 1
  fi
  TIP=$(_lgr rev-parse --verify --quiet "refs/heads/${BRANCH}^{commit}" 2>/dev/null) || {
    echo "lease_collect: ERROR lease branch ${BRANCH} is missing — escalate; the builder's work is only in ${WT}" >&2; return 1; }
  if [ -z "$BASE" ]; then
    BASE=$(_lgr merge-base HEAD "$TIP" 2>/dev/null) || { echo "lease_collect: ERROR no merge base for ${BRANCH}" >&2; return 1; }
  fi
  for C in $(_lgr rev-list "$TIP" "^${BASE}" 2>/dev/null); do
    [ "$C" = "$PREV" ] || BC="${BC:+${BC} }${C}"
  done
  TREE=$(_lease_tree_of_worktree "$WT" "$ADMIN" "$TIP" "$PROV") || { echo "lease_collect: ERROR could not build the snapshot tree for ${T}" >&2; return 1; }
  PARENT=$BASE
  [ -z "$BC" ] || PARENT=$TIP
  SNAP=$(_lgw "$WT" "$ADMIN" commit-tree "$TREE" -p "$PARENT" -m "lease(${T}): builder output snapshot (${BUILDER:-unknown}), taken by the lead at collect") || {
    echo "lease_collect: ERROR git commit-tree failed for ${T} (is user.name/user.email configured?)" >&2; return 1; }
  _lgr update-ref -m "lease collect snapshot" "refs/heads/${BRANCH}" "$SNAP" "$TIP" || { echo "lease_collect: ERROR could not move ${BRANCH} to the snapshot" >&2; return 1; }
  _lgw "$WT" "$ADMIN" reset -q "$SNAP" >/dev/null 2>&1 || true
  # Protected status over the lease's full diff (KTD3), recorded for
  # lease_status; lease_merge scans again and decides on its own result.
  _lease_protected_scan "$(_lease_default_branch)" "$BASE" "$SNAP"
  _ledger_update "$T" snapshot_sha="$SNAP" snapshot_tree="$TREE" base_sha="$BASE" builder_commits="$BC" \
    protected="$_LP_STATUS" protected_paths="$_LP_PATHS" || return 1
  if [ -n "$BC" ]; then
    echo "lease_collect: WARNING the builder made its own commit(s) on ${BRANCH} (the dispatch contract says commit nothing): ${BC} — lease_merge will refuse them (KTD19)" >&2
  fi
}

# _lease_verify_snapshot <task_id> — lease_merge's KTD19 gate. The lease merges
# only the lead's recorded snapshot: lease/<task> must be exactly base + that
# one commit, the worktree must still hold the recorded tree, and the diff must
# not touch the lead-owned ops/. Prints the refusal (naming the commit, the
# moved ref or the files) and returns 1 on any mismatch.
_lease_verify_snapshot() {
  local T=$1 ROW WT ADMIN BASE BRANCH SNAP STREE PROV TIP PARENT NOW LOG OPS
  ROW=$(_ledger_get_row "$T" worktree admin_dir base_sha branch snapshot_sha snapshot_tree provisioned) || ROW=""
  { IFS= read -r WT || true; IFS= read -r ADMIN || true; IFS= read -r BASE || true
    IFS= read -r BRANCH || true; IFS= read -r SNAP || true; IFS= read -r STREE || true
    IFS= read -r PROV || true; } <<VERIFY_ROW_EOF
${ROW}
VERIFY_ROW_EOF
  TIP=$(_lgr rev-parse --verify --quiet "refs/heads/${BRANCH}^{commit}" 2>/dev/null || true)
  if [ "$TIP" != "$SNAP" ]; then
    echo "lease_merge: REFUSED — ${BRANCH} is at ${TIP:-<missing>}, not the lead's recorded collect snapshot ${SNAP} (the branch moved after collect). Merging it would merge an unreviewed state (KTD19); re-collect through lease_redispatch or reclaim the lease." >&2
    return 1
  fi
  PARENT=$(_lgr rev-parse --verify --quiet "${SNAP}^1" 2>/dev/null || true)
  if [ "$PARENT" != "$BASE" ] || [ -n "$(_lgr rev-parse --verify --quiet "${SNAP}^2" 2>/dev/null || true)" ]; then
    LOG=$(_lgr log --format='%h %s' "${SNAP}^" "^${BASE}" 2>/dev/null | head -5 | _scrub | cut -c1-100 | tr '\n' ';' || true)
    echo "lease_merge: REFUSED — ${BRANCH} carries commits the builder made itself (the contract says commit nothing): ${LOG:-<unreadable>}. Only the lead's snapshot merges (KTD19). To keep the work, move the lease branch back to its base ${BASE:0:12} keeping the files, then re-collect via lease_redispatch; otherwise reclaim the lease." >&2
    return 1
  fi
  if [ ! -d "$WT" ]; then
    echo "lease_merge: ERROR worktree missing: ${WT}" >&2
    return 1
  fi
  NOW=$(_lease_tree_of_worktree "$WT" "$ADMIN" "$SNAP" "$PROV") || { echo "lease_merge: REFUSED — could not read ${T}'s worktree to compare it with the snapshot" >&2; return 1; }
  if [ "$NOW" != "$STREE" ]; then
    echo "lease_merge: REFUSED — ${T}'s worktree changed after collect and no longer matches the recorded snapshot (tree ${STREE:0:12}, now ${NOW:0:12}). Something wrote it after the review target was fixed; re-collect via lease_redispatch (KTD19)." >&2
    return 1
  fi
  # The diff lands in a file first so its own exit status is checked: in a
  # pipeline only the classifier's status would be seen, and a failed diff
  # would read as "nothing under ops/" (fails closed, KTD19).
  local DIFF_TMP
  DIFF_TMP=$(mktemp "${TMPDIR:-/tmp}/triforge-ops-diff.XXXXXX") || { echo "lease_merge: REFUSED — could not create a temp file for the ops/ check (KTD19)" >&2; return 1; }
  if ! _lgr diff -z --name-only --no-renames --no-ext-diff --ignore-submodules=none "$BASE" "$SNAP" > "$DIFF_TMP" 2>/dev/null; then
    rm -f "$DIFF_TMP"
    echo "lease_merge: REFUSED — could not diff ${BASE:0:12}..${SNAP:0:12} for the ops/ check; nothing merges on an unreadable diff (KTD19)" >&2
    return 1
  fi
  OPS=$(python3 -c '
import sys
bad = [p for p in sys.stdin.buffer.read().decode("utf-8", "replace").split("\0") if p and (p.casefold() == "ops" or p.casefold().startswith("ops/"))]
print(" ".join(bad[:10]) + (" ..." if len(bad) > 10 else ""))
' < "$DIFF_TMP") || { rm -f "$DIFF_TMP"; echo "lease_merge: REFUSED — the ops/ classifier failed; nothing merges on an unclassified diff (KTD19)" >&2; return 1; }
  rm -f "$DIFF_TMP"
  if [ -n "$OPS" ]; then
    echo "lease_merge: REFUSED — ${T}'s diff touches the lead-owned ops/ tree (builders never write ops/; the lead does, on the main tree): ${OPS}. Remove those changes from the worktree and re-collect (KTD19)." >&2
    return 1
  fi
}

# lease_create <task_id> <role> — resolve the builder from the roster
# (resolve_role), carve the worktree + lease branch, provision skills (the
# paths that wrote are recorded as `provisioned`, KTD9), write the leased
# row, with lead_via: where the lead ran it (lead-session, tty or test, from
# _lead_only's host check), and lead_cli: the lead's CLI, kept for attribution
# (U10, KTD2; a row from before 4.0 has none and reads as _LEAD_LEGACY_CLI).
# Echoes task_id on success so callers can chain.
lease_create() {
  _lead_only lease_create || return $?
  local TASK_ID=${1:?usage: lease_create <task_id> <role>}
  local ROLE=${2:?usage: lease_create <task_id> <role>}
  if ! _lease_valid_task_id "$TASK_ID"; then
    echo "lease_create: ERROR invalid task id '${TASK_ID}' — want [A-Za-z0-9][A-Za-z0-9._-]* (it becomes a branch and directory name)" >&2
    return 1
  fi
  local RESOLVED CLI MODEL EFFORT WT NOW CUR IB="" ISHA="" ROW LEAD=""
  _lease_ctx || { echo "lease_create: ERROR not inside a git repository" >&2; return 1; }
  # A change a worker made since the lead's last check (a planted hook, git
  # config, a moved ref) is caught before the next worktree is carved (KTD18).
  _lead_integrity_check lease_create || return $?
  # The worktree is carved at the lead's HEAD, so the checkout must still be on
  # the integration branch the lead recorded: a builder shares .git and can
  # switch the lead's checkout to a branch of its own (KTD18).
  CUR=$(_lease_current_branch)
  ROW=$(_ledger_get_row @baseline integration_branch integration_sha 2>/dev/null) || ROW=""
  { IFS= read -r IB || true; IFS= read -r ISHA || true; } <<CREATE_ROW_EOF
${ROW}
CREATE_ROW_EOF
  if [ -n "$IB" ] && [ "$IB" != "$CUR" ]; then
    _lead_branch_switched lease_create "$IB" "$ISHA" "$CUR"
    return "$_RC_LEASE_INTEGRITY"
  fi
  RESOLVED=$(resolve_role "$ROLE") || return $?
  CLI=$(printf '%s\n' "$RESOLVED" | cut -f1)
  MODEL=$(printf '%s\n' "$RESOLVED" | cut -f2)
  EFFORT=$(printf '%s\n' "$RESOLVED" | cut -f3)
  WT="${_LEASE_ROOT}/${TASK_ID}"
  if [ -e "$WT" ]; then
    echo "lease_create: ERROR worktree path already exists: ${WT} (reclaim the previous lease first)" >&2
    return 1
  fi
  if _lead_resolve 2>/dev/null; then LEAD=$_LEAD_CLI; fi
  _lease_carve "$TASK_ID" "$WT" || return 1
  _lease_provision "$WT" "$CLI" || return 1
  NOW=$(date +%s)
  # lead_via from this shell's origin, read here: a cached host-check pass
  # does not set it.
  _lead_origin
  _ledger_update "$TASK_ID" \
    task_id="$TASK_ID" role="$ROLE" \
    builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    state=leased worktree="$WT" branch="lease/${TASK_ID}" \
    pid=0 output_file="" created="$NOW" heartbeat_deadline=0 \
    requeue_count=0 review_cycle=0 pinned_reviewer="" previous_builder="" reviewer="" merge_commit="" reason="" \
    lead_via="${_LEAD_VIA:-}" "${_CARVE_FIELDS[@]}" \
    lead_cli="$LEAD" \
    || return 1
  # First lease in this checkout: the lead's verified state becomes the
  # integrity baseline before any builder runs. With no integration branch
  # recorded (a new sprint, or the first lease after a promotion cleared it),
  # the current branch is recorded at the commit its first lease starts from;
  # a recorded one that differs was refused above. The default branch is never
  # recorded as the integration branch (KTD18): a lease created on it leaves
  # the record empty, and the first lease or merge on the sprint branch fills it.
  if [ -z "$(_ledger_get @baseline config 2>/dev/null || true)" ]; then
    _lead_baseline_record || return 1
  fi
  if [ -n "$CUR" ] && [ -z "$IB" ] && [ "$CUR" != "$(_lease_default_branch)" ]; then
    _ledger_update @baseline integration_branch="$CUR" integration_sha="$_CARVE_BASE" || return 1
  fi
  echo "lease_create: task=${TASK_ID} role=${ROLE} builder=${CLI} model=${MODEL:-host-default} worktree=${WT}" >&2
  echo "$TASK_ID"
}

# _lease_extract_stream <cli> <out> — for the stream-shaped lanes, turn the
# captured JSON event stream in <out> into the assistant's final prose so the
# builder's typed report can be parsed: <out> -> <out>.raw, extractor -> <out>.
# Non-stream lanes and a failed extraction leave <out> untouched (a plain-text
# TRIFORGE_TEST_BUILDER stream is simply not JSON).
_lease_extract_stream() {
  local CLI=$1 OUT=$2 X=""
  case "$CLI" in
    opencode) X=_oc_extract_text ;;
    kimi)     X=_kimi_extract_text ;;
    cursor)   X=_cursor_extract_text ;;
    *) return 0 ;;
  esac
  [ -s "$OUT" ] || return 0
  cp "$OUT" "${OUT}.raw" 2>/dev/null || return 0
  if "$X" "${OUT}.raw" "${OUT}.text"; then
    mv -f "${OUT}.text" "$OUT" 2>/dev/null || true
  else
    rm -f "${OUT}.text" 2>/dev/null || true
    echo "lease_dispatch: WARNING could not extract assistant text from the ${CLI} stream — raw stream left in ${OUT} (report may parse as missing)" >&2
  fi
}

# _lease_claude_envelope <out> [<err>] — the claude lane's JSON envelope
# (KTD16). When <out> holds one (an object whose type is "result"), keep it as
# <out>.raw, put its result text in <out>, where the typed report is parsed,
# and write <out>.envelope: subtype=, is_error=, session_id=, num_turns=, each
# value checked against its shape (a session id must look like a UUID) or left
# empty. rc 1 when <out> is not an envelope (a plain-text
# TRIFORGE_TEST_BUILDER, an auth failure printed as text): <out> is then left
# as it is, with <err> (the run's stderr, when given and not empty) appended,
# so it holds what the CLI said.
_lease_claude_envelope() {
  if [ -s "$1" ] && CE_OUT="$1" python3 -c '
import json, os, re, shutil, sys
out = os.environ["CE_OUT"]
src = open(out, encoding="utf-8", errors="replace").read()
i = src.find("{")
try:
    obj = json.JSONDecoder().raw_decode(src[i:])[0] if i >= 0 else None
except ValueError:
    obj = None
if not isinstance(obj, dict) or obj.get("type") != "result":
    sys.exit(1)
def shaped(v, rx):
    v = "" if v is None else str(v)
    return v if re.fullmatch(rx, v) else ""
meta = ["subtype=" + shaped(obj.get("subtype"), r"[a-z_]{1,40}"),
        "is_error=" + ("true" if obj.get("is_error") is True else "false"),
        "session_id=" + shaped(obj.get("session_id"), r"[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}"),
        "num_turns=" + shaped(obj.get("num_turns"), r"[0-9]{1,6}")]
res = obj.get("result")
res = res if isinstance(res, str) else ""
shutil.copyfile(out, out + ".raw")
with open(out + ".text", "w", encoding="utf-8") as f:
    f.write(res + ("\n" if res and not res.endswith("\n") else ""))
os.replace(out + ".text", out)
with open(out + ".envelope", "w", encoding="utf-8") as f:
    f.write("\n".join(meta) + "\n")
' 2>/dev/null; then
    return 0
  fi
  if [ -n "${2:-}" ] && [ -s "$2" ]; then
    cat "$2" >> "$1" 2>/dev/null || true
  fi
  return 1
}

# lease_dispatch <task_id> <prompt> [timeout-seconds]
#
# Composes the FULL dispatch prompt: injected context header (KTD-3 — the
# lease's roster line plus the explicit confinement contract) + the
# lead-provided task prompt (which carries the task row text and any
# CONTRACTS.md slice — the builder never reads canonical ops/).
#
# The builder runs DETACHED (KTD10, scripts/lib/lease-wait.sh): _LEASE_LAUNCH_PY
# starts it in its own session and process group, and _lease_builder_run runs
# the lane command (_lease_lane_argv) from the worktree under _adapter_env's
# per-CLI allowlist (KTD-14), so the worker marker and the no-push backstop
# reach it as before. Exit code and KTD-9 class land in <out>.rc / <out>.class,
# the builder process's own diagnostics in <out>.log, for the single-writer
# lead to collect — the builder process never touches the ledger. The row
# records state=building, pid, pgid, pid_started, lead_pid, lead_started,
# output_file and heartbeat_deadline (the timeout plus _LEASE_DEADLINE_SLACK_S);
# lease_wait waits on it. A launch record (<out>.launch) left by a dispatch
# interrupted between the launch and that ledger write names a builder that may
# still run in the worktree: it is stopped before the next launch. Variables the
# lanes read from the environment (a CLI's credential keys, OPENCODE_PERMISSION)
# must be exported: the builder process inherits the lead's environment, not
# its shell.
#
# Test seam: TRIFORGE_TEST_BUILDER=<script path> replaces the real adapter
# for lifecycle determinism — the script runs with the worktree as cwd and
# the full prompt as its first argument, still under the recorded CLI's env
# allowlist and timeout so the confinement/heartbeat paths stay honest.
lease_dispatch() {
  _lead_only lease_dispatch || return $?
  local TASK_ID=${1:?usage: lease_dispatch <task_id> <prompt> [timeout]}
  local PROMPT=${2:?usage: lease_dispatch <task_id> <prompt> [timeout]}
  local TIMEOUT=${3:-600}
  local STATE CLI MODEL EFFORT ROLE WT OUT TOBIN NOW DEADLINE PID="" PGID="" PID_START="" LAUNCH="" BASH_BIN=/bin/bash
  local TAB
  TAB=$(printf '\t')
  _lease_ctx || return 1
  _lead_integrity_check lease_dispatch || return $?
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_dispatch: ERROR no lease row for task '${TASK_ID}' — run lease_create first" >&2; return 1; }
  if [ "$STATE" != "leased" ]; then
    echo "lease_dispatch: ERROR task ${TASK_ID} is in state '${STATE}' (want leased)" >&2
    return 1
  fi
  local ROW SESSION="" RESUME=""
  ROW=$(_ledger_get_row "$TASK_ID" builder_cli builder_model builder_effort role worktree session_id) || ROW=""
  { IFS= read -r CLI || true; IFS= read -r MODEL || true; IFS= read -r EFFORT || true
    IFS= read -r ROLE || true; IFS= read -r WT || true; IFS= read -r SESSION || true; } <<DISPATCH_ROW_EOF
${ROW}
DISPATCH_ROW_EOF
  if [ ! -d "$WT" ]; then
    echo "lease_dispatch: ERROR worktree missing: ${WT}" >&2
    return 1
  fi
  OUT="${_LEASE_ROOT}/${TASK_ID}.out"
  TOBIN=$(_timeout_tool) || return $?

  # Dispatch contract (KTD11 / S5+S13+S14) — one block for EVERY lane, claude
  # included: no sub-dispatch, git stays local, and a typed final report whose
  # `Status:` line lease_collect parses (a clean exit without it is "report
  # missing", never review-ready). The lane's builder brief body (opencode /
  # cursor: opencode-agents|cursor-agents/builder.md, frontmatter stripped) is
  # prepended here; Kimi's arrives natively via --agent-file; claude / codex /
  # antigravity carry no separate builder brief (their role instructions are
  # the contract itself). Wording is CLI-neutral on purpose.
  local BRIEF_BODY="" BRIEF_FILE=""
  case "$CLI" in
    opencode|cursor)
      BRIEF_FILE="${_TRIFORGE_PLUGIN_ROOT}/${CLI}-agents/builder.md"
      if [ -f "$BRIEF_FILE" ]; then
        BRIEF_BODY=$(awk '/^---[[:space:]]*$/{skip++; next} skip>=2{print}' "$BRIEF_FILE")
      fi
      ;;
  esac
  local FULL_PROMPT
  FULL_PROMPT="## Lease dispatch: ${TASK_ID}
Roster entry: role=${ROLE} cli=${CLI} model=${MODEL:-<host-default>} effort=${EFFORT}

## Confinement contract
You are working in an isolated worktree at ${WT}. Never modify files outside it. Never read or write the project's canonical ops/ directory — required context is included below. Commit nothing; the lead collects.

## Dispatch contract (applies to every builder)
- Do not spawn sub-agents, delegate, or invoke other coding tools; do the work yourself in this worktree.
- Never run git push, git pull, or git fetch. Do not commit, rebase, or switch branches.
- Do not end your final turn while a command you started in the background is still running: wait for it or stop it first.
- Finish with a final report in exactly this shape (the lead parses the Status line; a run without it is treated as incomplete):
  Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
  Files changed: <list>
  Tests: <one-line summary, or none>
  Concerns: <list, or None>
  Discoveries for later tasks: <list, or None>
${BRIEF_BODY:+
## Builder role brief
${BRIEF_BODY}
}
## Task
${PROMPT}"

  # A launch record here is a dispatch interrupted after the launcher released
  # its builder but before the row reached building (a tool call cut off, a
  # killed lead): that builder may still run in this worktree, so it is stopped
  # first, through the fingerprinted group kill (a pid that now answers as
  # another process is never signalled), and a second one never joins it.
  if _lease_launch_read "$OUT"; then
    if ! _lease_stop_one lease_dispatch "$TASK_ID" "$_LL_PID" "$_LL_PGID" "$_LL_START" "builder an interrupted lease_dispatch started" quiet; then
      echo "lease_dispatch: ERROR a builder from an earlier, interrupted dispatch of ${TASK_ID} may still run in ${WT} (see above) — not launching another; stop it by hand, remove ${OUT}.launch, and dispatch again" >&2
      return 1
    fi
  fi
  rm -f "$OUT" "${OUT}.rc" "${OUT}.class" "${OUT}.log" "${OUT}.launch" "${OUT}.err" "${OUT}.raw" "${OUT}.envelope"

  # Lane-specific composition that must happen LEAD-SIDE, before env -i: the
  # Kimi builder definition's absolute plugin path (D-024), the Cursor binary and
  # the effort-suffixed Cursor model id (D-025). One registry read serves the
  # whole dispatch — cli_field <cli> model env_keys: the lanes that always pin a
  # model (agy — AE2 — and the optional three) fall back from an empty MODEL to
  # the CLI's shipped default, while claude and codex pass a model only when the
  # roster set one and keep MODEL as is; the env_keys reach _adapter_env through
  # _ADAPTER_ENV_KEYS inside the builder process, so it does not read them
  # again. The ledger records the id that was actually dispatched
  # (dispatched_model) beside the roster values (builder_model / builder_effort).
  local KIMI_AGENT_FILE="" CBIN="" DISPATCH_MODEL="$MODEL" REG_ROW="" REG_ENV_KEYS=""
  REG_ROW=$(cli_field "$CLI" model env_keys 2>/dev/null) || REG_ROW=""
  REG_ENV_KEYS=${REG_ROW#*$'\t'}
  case "$CLI" in
    antigravity|opencode|kimi|cursor) [ -n "$DISPATCH_MODEL" ] || DISPATCH_MODEL=${REG_ROW%%$'\t'*} ;;
  esac
  case "$CLI" in
    kimi)
      [ -f "${_TRIFORGE_PLUGIN_ROOT}/kimi-agents/builder.md" ] && KIMI_AGENT_FILE="${_TRIFORGE_PLUGIN_ROOT}/kimi-agents/builder.md"
      ;;
    cursor)
      DISPATCH_MODEL=$(_cursor_model_for_effort "$DISPATCH_MODEL" "$EFFORT")
      if ! CBIN=$(_cursor_bin); then
        echo "lease_dispatch: ERROR no Cursor CLI on PATH (cursor-agent, or an agent whose --version matches YYYY.MM.DD-<hex>) — cannot dispatch ${TASK_ID}" >&2
        return 1
      fi
      ;;
  esac
  # The claude lane resumes the session its last run recorded (KTD16): a fix
  # cycle, or the re-dispatch after a report-missing collect, continues the
  # same conversation in the same worktree; a requeue re-carves and clears it.
  case "$CLI" in
    claude) if _claude_session_ok "$SESSION"; then RESUME=$SESSION; fi ;;
  esac
  _ledger_update "$TASK_ID" dispatched_model="$DISPATCH_MODEL" resumed_session="$RESUME" || return 1

  # Detached launch (KTD10): the builder process is a fresh bash that sources
  # this loader and runs _lease_builder_run with the composition above, in its
  # own session and process group, released only once its pgid and start time
  # are read. TRIFORGE_TEST_BUILDER rides as an argument, so a shell variable
  # that was never exported still reaches it.
  if [ ! -x "$BASH_BIN" ]; then BASH_BIN=$(command -v bash 2>/dev/null || printf 'bash'); fi
  LAUNCH=$(python3 -c "$_LEASE_LAUNCH_PY" "${OUT}.log" "$BASH_BIN" -c "$_LEASE_BUILDER_SH" triforge-lease-builder \
             "${_TRIFORGE_SCRIPTS_DIR}/invoke-external.sh" "$CLI" "$MODEL" "$EFFORT" "$DISPATCH_MODEL" "$KIMI_AGENT_FILE" \
             "$CBIN" "$TOBIN" "$TIMEOUT" "$OUT" "$WT" "$REG_ENV_KEYS" "${TRIFORGE_TEST_BUILDER:-}" "$FULL_PROMPT" \
             "$_LEASE_COMMON" "$RESUME") || LAUNCH=""
  { IFS="$TAB" read -r PID PGID PID_START || true; } <<LAUNCH_EOF
${LAUNCH}
LAUNCH_EOF
  case "${PID}:${PGID}" in
    *[!0-9:]*|:*|*:) echo "lease_dispatch: ERROR could not start the builder for ${TASK_ID} in its own session (see above); the lease stays leased" >&2; return 1 ;;
  esac
  # The lead process this dispatch belongs to: when it is gone at the next
  # reconcile, the lease went through a lead exit (_lease_sweep_one).
  _lease_lead_proc

  NOW=$(date +%s)
  DEADLINE=$((NOW + TIMEOUT + _LEASE_DEADLINE_SLACK_S))
  if ! _ledger_update "$TASK_ID" state=building pid="$PID" pgid="$PGID" pid_started="$PID_START" lead_pid="$_LEAD_PID" lead_started="$_LEAD_STARTED" \
         output_file="$OUT" heartbeat_deadline="$DEADLINE"; then
    _lease_kill_builder "$PID" "$PGID" "$PID_START"   # unrecorded, so never left running
    return 1
  fi
  # Recorded: the launch record has done its job (lease_stop reads the row).
  rm -f "${OUT}.launch"
  echo "lease_dispatch: task=${TASK_ID} builder=${CLI} pid=${PID} pgid=${PGID} (detached) timeout=${TIMEOUT}s output=${OUT}" >&2
}

# lease_redispatch <task_id> <prompt-with-findings> [timeout] — the review ->
# building fix cycle (KTD-10; wave-orchestration "Findings, cycle < 3 -> re-
# dispatch the SAME lease to the SAME builder"). This is the ONLY path from
# state=review back to building: without it a reviewer that requests changes
# strands the lease, because lease_dispatch requires state=leased and
# lease_requeue requires state=requeued. Increments review_cycle and, at the
# 3rd cycle, ESCALATES to the user instead of re-dispatching (state=escalated) —
# the "Maximum 3 review cycles per task" cap. Builder, worktree, and roster
# entry are unchanged; the reviewer's findings ride in <prompt-with-findings>.
lease_redispatch() {
  _lead_only lease_redispatch || return $?
  local TASK_ID=${1:?usage: lease_redispatch <task_id> <prompt-with-findings> [timeout]}
  local PROMPT=${2:?usage: lease_redispatch <task_id> <prompt-with-findings> [timeout]}
  local TIMEOUT=${3:-600}
  local STATE WT CYCLE NEXT
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_redispatch: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if [ "$STATE" != "review" ]; then
    echo "lease_redispatch: ERROR task ${TASK_ID} is in state '${STATE}' (want review — lease_collect sets it; redispatch is the findings path). Approved work goes to lease_merge; orphaned/timed-out work to lease_requeue." >&2
    return 1
  fi
  WT=$(_ledger_get "$TASK_ID" worktree)
  if [ ! -d "$WT" ]; then
    echo "lease_redispatch: ERROR worktree missing: ${WT} (already merged/reclaimed?) — cannot re-dispatch" >&2
    return 1
  fi
  CYCLE=$(_ledger_get "$TASK_ID" review_cycle 2>/dev/null || true)
  case "${CYCLE:-}" in ''|*[!0-9]*) CYCLE=0 ;; esac
  NEXT=$((CYCLE + 1))
  # Cap at 3 cycles: the 3rd round of findings escalates to the user instead of a
  # 4th builder run (KTD-10 / "Maximum 3 review cycles per task").
  if [ "$NEXT" -ge 3 ]; then
    _ledger_update "$TASK_ID" state=escalated review_cycle="$NEXT" || return 1
    echo "lease_redispatch: task ${TASK_ID} reached review cycle ${NEXT} (cap 3) — ESCALATED to the user; no further auto re-dispatch (KTD-10). Resolve manually, then lease_merge or abandon the lease." >&2
    return "$_RC_LEASE_ESCALATED"
  fi
  # review -> leased (transient), then reuse lease_dispatch's launch machinery to
  # re-run the SAME builder in the SAME worktree; lease_dispatch sets state=building.
  _ledger_update "$TASK_ID" state=leased review_cycle="$NEXT" || return 1
  echo "lease_redispatch: task ${TASK_ID} findings re-dispatch — review cycle ${NEXT}/3, same builder, same worktree" >&2
  lease_dispatch "$TASK_ID" "$PROMPT" "$TIMEOUT"
}

# _lease_root_valid <dir> — 0 when <dir> can stand as one of this checkout's
# lease roots: an absolute, canonical path (no traversal, no symlink
# component, not /) named like this shell's root (the <repo>-<hash> basename
# _lease_ctx derives) that is a lease root (_is_lease_root, common.sh: its
# lead/gitconfig starts with _LEAD_GITCONFIG_SIGNATURE). A path read from the
# ledger is checked with it before anything is written or removed under it.
_lease_root_valid() {
  local D=${1:-}
  case "$D" in
    ""|/) return 1 ;;
    /*) ;;
    *) return 1 ;;
  esac
  case "${D}/" in *"/../"*|*"/./"*) return 1 ;; esac
  if [ "${D##*/}" != "${_LEASE_ROOT##*/}" ] || [ "$(_lease_realpath "$D")" != "$D" ]; then
    return 1
  fi
  _is_lease_root "$D"
}

# _lease_recorded_root <task_id> — print the row's recorded lease_root when it
# differs from this shell's lease root and is still one of this checkout's
# lease roots (_lease_root_valid). rc 1 otherwise (no record, the same root,
# or not such a root), and lease_reclaim keeps its own.
_lease_recorded_root() {
  local REC
  REC=$(_ledger_get "$1" lease_root 2>/dev/null) || return 1
  if [ "$REC" = "$_LEASE_ROOT" ] || ! _lease_root_valid "$REC"; then
    return 1
  fi
  printf '%s\n' "$REC"
}

# _lease_at_ledger_root <op> — for the two helpers that write the ledger from
# any shell (lease_approve; roster_write_lead's forced handover), which may run
# under another TMPDIR than the lead (a terminal, the other lead's session,
# Claude Code's sandboxed Bash): move this shell's lease context to the root
# the ledger was last written under, [baseline].lease_root (a ledger from
# before that stamp: the newest row's lease_root), so the write updates the
# lead's own integrity anchors. Written beside a fresh set, it would read to
# the lead as a change made outside its writes, and be restored away and
# escalated (rc 44). The caller declares `local TRIFORGE_LEASE_ROOT` first;
# this sets it. Nothing moves when TRIFORGE_LEASE_ROOT is already set (the
# user chose the root), no root is recorded, or it is this shell's. rc 1 with
# a refusal naming export TRIFORGE_LEASE_ROOT when the recorded root is not
# one of this checkout's lease roots any more (_lease_root_valid), and when
# the ledger holds the lead's writes (a lease row or a [baseline]; one that
# can't be read counts) but the root this lands on holds no anchors for it
# (no ledger digest or copy in its lead state dir): a stamp stripped, or
# rewritten to name this shell's own root, would otherwise have the writer
# adopt the ledger as found beside a fresh set of anchors (KTD18). A pre-stamp
# ledger whose anchors are in this shell's root still passes.
_lease_at_ledger_root() {
  local OP=${1:-lease} REC="" WRITES SHOWN TAB
  if [ -n "${TRIFORGE_LEASE_ROOT:-}" ]; then
    return 0
  fi
  if [ ! -f "$_LEASE_LEDGER" ]; then
    # No ledger to read the root from (Phase 3 round 4, B4): the lease-root
    # record in the checkout's git dir names it, so a deleted ledger is
    # checked where the lead's anchors are, which restores it from the lead's
    # copy; a record that names no valid root is left to
    # _lead_integrity_check, which refuses on it.
    if [ -f "${_LEASE_GITDIR}/triforge-lease-root" ] && [ ! -L "${_LEASE_GITDIR}/triforge-lease-root" ]; then
      REC=$(grep -v '^#' "${_LEASE_GITDIR}/triforge-lease-root" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1 || true)
    fi
    if [ -n "$REC" ] && [ "$REC" != "$_LEASE_ROOT" ] && _lease_root_valid "$REC"; then
      TRIFORGE_LEASE_ROOT=$REC
      _lease_ctx || return 1
      echo "${OP}: NOTE ${_LEASE_LEDGER} is missing and this shell resolves another lease root; checking under ${REC}, the root this checkout's lease-root record names" >&2
    fi
    return 0
  fi
  TAB=$(printf '\t')
  REC=$(LR_LEDGER="$_LEASE_LEDGER" python3 -c '
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stdout.write("\t1")
        sys.exit(0)
try:
    with open(os.environ["LR_LEDGER"], "rb") as f:
        data = tomllib.load(f)
except Exception:
    sys.stdout.write("\t" + ("1" if os.path.getsize(os.environ["LR_LEDGER"]) else "0"))
    sys.exit(0)
rows = data.get("lease")
b = data.get("baseline")
writes = (isinstance(rows, dict) and len(rows) > 0) or (isinstance(b, dict) and len(b) > 0)
root = str(b.get("lease_root", "") or "") if isinstance(b, dict) else ""
if not root:
    best = None
    for r in (rows.values() if isinstance(rows, dict) else []):
        if isinstance(r, dict) and r.get("lease_root"):
            c = r.get("created", 0)
            c = c if isinstance(c, int) else 0
            if best is None or c >= best[0]:
                best = (c, str(r["lease_root"]))
    root = best[1] if best else ""
sys.stdout.write(root.replace("\t", " ") + "\t" + ("1" if writes else "0"))
' 2>/dev/null) || REC=$(printf '\t1')
  WRITES=${REC##*"$TAB"}
  REC=${REC%"$TAB"*}
  if [ -n "$REC" ] && [ "$REC" != "$_LEASE_ROOT" ]; then
    if ! _lease_root_valid "$REC"; then
      SHOWN=$(printf '%s' "$REC" | LC_ALL=C tr -d '\000-\037\177')
      echo "${OP}: REFUSED — the ledger was last written under the lease root ${SHOWN}, this shell resolves ${_LEASE_ROOT} (another TMPDIR or TRIFORGE_LEASE_ROOT), and the recorded root is not one of this checkout's lease roots any more (missing, moved or renamed). Written from here, the ledger would read to the lead as a change made outside its writes (KTD18). Point this shell at the lead's lease root and rerun: export TRIFORGE_LEASE_ROOT=<the lead's lease root>" >&2
      return 1
    fi
    TRIFORGE_LEASE_ROOT=$REC
    _lease_ctx || return 1
    echo "${OP}: NOTE this shell resolves another lease root; writing under ${REC}, where the ledger was last written" >&2
  fi
  if [ "$WRITES" != 0 ] && [ ! -e "${_LEASE_STATE}/ledger.sha256" ] && [ ! -e "${_LEASE_STATE}/ledger.copy" ]; then
    echo "${OP}: REFUSED — ${_LEASE_LEDGER} holds the lead's writes, but the lease root ${_LEASE_ROOT} holds no anchors for it (no ledger digest or copy in ${_LEASE_STATE}), and the ledger names no other root that does (its lease_root stamp is missing or names this shell's own root). Checked from here, the ledger would be adopted as found (KTD18). Point this shell at the lead's lease root and rerun: export TRIFORGE_LEASE_ROOT=<the lead's lease root>. If the lead's state dir is really gone, inspect the ledger, then accept it from the lead's terminal with lease_rebaseline." >&2
    return 1
  fi
}

# Refusal helper for lease_reclaim: loud, escalates the row, deletes NOTHING.
# Returns 0 so callers can '\; return 1' without tripping errexit.
_lease_refuse_prune() {
  local TASK_ID=$1 STORED=$2 MSG=$3
  echo "lease_reclaim: REFUSING prune for ${TASK_ID}: ${MSG} (stored='${STORED}')" >&2
  _ledger_update "$TASK_ID" state=escalated reason="lease identity mismatch" || true
  return 0
}

# lease_reclaim <task_id> — SAFE PRUNE. Destructive cleanup runs only after
# the lease identity survives, in this exact order:
#   1. canonicalize the stored worktree path (python3 os.path.realpath)
#   2. reject traversal ('..'/'.') components and non-canonical paths —
#      stored paths are canonical from birth (_lease_ctx realpaths the lease
#      root every worktree path is built under), so any
#      canonical-vs-stored difference means a symlink or tampering
#   3. REQUIRE the canonical path sits strictly beneath the canonical root
#   4. REQUIRE git worktree list --porcelain knows the path
# The root is this shell's lease root, or the row's recorded lease_root when
# that differs and still holds a lease root's lead/gitconfig: a lease created
# under one lead is reclaimed under the other, whose shell may resolve another
# TMPDIR (_lease_recorded_root). Step 4 still has to pass, so a forged
# lease_root reaches only a worktree git already lists, and the recorded root
# must be named like this shell's (_lease_root_valid). The integrity check runs
# first, so the row it reads is the lead's own write (KTD18).
# ANY mismatch: nothing is deleted, state=escalated with reason "lease
# identity mismatch", nonzero return. A clean pass prunes worktree + branch,
# then transitions per the current state:
#   orphaned + requeue_count 0  -> requeued   (lease_requeue re-leases it)
#   orphaned + requeue_count 1+ -> escalated  (KTD-9: requeue once, loudly)
#   merged / anything else      -> state kept (prune only)
lease_reclaim() {
  _lead_only lease_reclaim || return $?
  local TASK_ID=${1:?usage: lease_reclaim <task_id>}
  local ROOT REC WT_STORED WT_CANON STATE RQ
  _lease_ctx || return 1
  _lead_integrity_check lease_reclaim || return $?
  ROOT=$_LEASE_ROOT
  WT_STORED=$(_ledger_get "$TASK_ID" worktree) || { echo "lease_reclaim: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  STATE=$(_ledger_get "$TASK_ID" state)
  if REC=$(_lease_recorded_root "$TASK_ID"); then
    echo "lease_reclaim: NOTE ${TASK_ID} was created under the lease root $(printf '%s' "$REC" | LC_ALL=C tr -d '\000-\037\177') (this shell resolves ${ROOT}); checking it against the recorded root" >&2
    ROOT=$REC
  fi

  if [ -z "$WT_STORED" ]; then
    _lease_refuse_prune "$TASK_ID" "$WT_STORED" "empty worktree path"; return 1
  fi
  case "$WT_STORED" in
    /*) : ;;
    *) _lease_refuse_prune "$TASK_ID" "$WT_STORED" "relative path"; return 1 ;;
  esac
  case "${WT_STORED}/" in
    *"/../"*|*"/./"*) _lease_refuse_prune "$TASK_ID" "$WT_STORED" "path contains traversal"; return 1 ;;
  esac
  WT_CANON=$(_lease_realpath "$WT_STORED")
  if [ "$WT_CANON" != "${WT_STORED%/}" ]; then
    _lease_refuse_prune "$TASK_ID" "$WT_STORED" "stored path is not canonical (symlink component or traversal; canonical='${WT_CANON}')"; return 1
  fi
  case "$WT_CANON" in
    "${ROOT}"/?*) : ;;
    *) _lease_refuse_prune "$TASK_ID" "$WT_STORED" "path not strictly beneath lease root '${ROOT}'"; return 1 ;;
  esac
  if ! _lgr worktree list --porcelain | grep -Fxq "worktree ${WT_CANON}"; then
    _lease_refuse_prune "$TASK_ID" "$WT_STORED" "path not registered in git worktree list"; return 1
  fi

  if ! _lgr worktree remove --force "$WT_CANON" >&2; then
    echo "lease_reclaim: ERROR git worktree remove failed for ${WT_CANON}" >&2
    _ledger_update "$TASK_ID" state=escalated reason="worktree remove failed" || true
    return 1
  fi
  _lgr branch -D "lease/${TASK_ID}" >/dev/null 2>&1 || true

  case "$STATE" in
    orphaned)
      RQ=$(_ledger_get "$TASK_ID" requeue_count)
      if [ "${RQ:-0}" -eq 0 ] 2>/dev/null; then
        _ledger_update "$TASK_ID" state=requeued || return 1
        echo "lease_reclaim: ${TASK_ID} pruned — requeued (one retry available via lease_requeue, KTD-9)" >&2
      else
        _ledger_update "$TASK_ID" state=escalated reason="second builder failure" || return 1
        echo "lease_reclaim: ${TASK_ID} pruned — ESCALATED: second builder failure (requeue_count=${RQ}). KTD-9 allows exactly one requeue; the lead must diagnose or reassign manually." >&2
      fi
      ;;
    *)
      echo "lease_reclaim: ${TASK_ID} pruned (state stays '${STATE}')" >&2
      ;;
  esac
  return 0
}

# lease_requeue <task_id> — one second chance, on a DIFFERENT builder
# (KTD-9: exactly once). Walks the role's fallback chain past
# previous_builder via resolve_role's RESOLVE_ROLE_EXCLUDE hook, carves a
# fresh worktree, and re-leases. requeue_count >= 1 escalates instead.
lease_requeue() {
  _lead_only lease_requeue || return $?
  local TASK_ID=${1:?usage: lease_requeue <task_id>}
  local STATE RQ PREV ROLE OUT WT RESOLVED CLI MODEL EFFORT
  _lease_ctx || return 1
  _lead_integrity_check lease_requeue || return $?
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_requeue: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  RQ=$(_ledger_get "$TASK_ID" requeue_count)
  OUT=$(_ledger_get "$TASK_ID" output_file)
  if [ "${RQ:-0}" -ge 1 ] 2>/dev/null; then
    _ledger_update "$TASK_ID" state=escalated reason="requeue budget exhausted" || true
    echo "lease_requeue: ${TASK_ID} ESCALATED — requeue_count=${RQ}; KTD-9 allows exactly one requeue and a different builder already failed this task. The lead must diagnose (see ${OUT:-the builder output}) or reassign manually." >&2
    return 1
  fi
  if [ "$STATE" != "requeued" ]; then
    echo "lease_requeue: ERROR task ${TASK_ID} is in state '${STATE}' (want requeued — lease_reclaim sets it after a clean prune)" >&2
    return 1
  fi
  PREV=$(_ledger_get "$TASK_ID" builder_cli)
  ROLE=$(_ledger_get "$TASK_ID" role)
  RESOLVED=$(RESOLVE_ROLE_EXCLUDE="$PREV" resolve_role "$ROLE") || {
    _ledger_update "$TASK_ID" state=escalated reason="no alternative builder" || true
    echo "lease_requeue: ${TASK_ID} ESCALATED — no live builder past previous '${PREV}' in role '${ROLE}' fallback chain." >&2
    return 1
  }
  CLI=$(printf '%s\n' "$RESOLVED" | cut -f1)
  MODEL=$(printf '%s\n' "$RESOLVED" | cut -f2)
  EFFORT=$(printf '%s\n' "$RESOLVED" | cut -f3)
  WT="${_LEASE_ROOT}/${TASK_ID}"
  if [ -e "$WT" ]; then
    echo "lease_requeue: ERROR stale worktree still present at ${WT} — reclaim first" >&2
    return 1
  fi
  _lease_carve "$TASK_ID" "$WT" || return 1
  _lease_provision "$WT" "$CLI" || return 1
  _ledger_update "$TASK_ID" \
    state=leased builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    previous_builder="$PREV" requeue_count=1 pid=0 heartbeat_deadline=0 reason="" \
    worktree="$WT" "${_CARVE_FIELDS[@]}" \
    || return 1
  echo "lease_requeue: ${TASK_ID} re-leased to ${CLI} (previous builder: ${PREV}) — dispatch again with lease_dispatch" >&2
  echo "$TASK_ID"
}

# _lease_parse_status <output-file> — print the builder's typed completion
# signal from its final report (KTD11): the LAST line matching
# `Status: DONE|DONE_WITH_CONCERNS|BLOCKED|NEEDS_CONTEXT` (case-insensitive,
# optional leading list marker / bold). Prints MISSING when no such line exists.
# The token must END the line (a closing `**`, optional trailing punctuation,
# then whitespace/EOL — never a `|`): the dispatch contract's own template line
# `Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT` is echoed back
# into the captured output by CLIs that print the prompt (codex exec does, on
# stderr), and an unanchored match read every such run as DONE.
_lease_parse_status() {
  local F=${1:?usage: _lease_parse_status <output-file>}
  local S=""
  S=$(grep -iE '^[[:space:]]*[-*]*[[:space:]]*\**Status\**:?\**[[:space:]]*\**(DONE_WITH_CONCERNS|DONE|BLOCKED|NEEDS_CONTEXT)\**[.,;)]?([[:space:]]*$|[[:space:]]+[^|[:space:]])' "$F" 2>/dev/null | tail -1 | grep -oiE 'DONE_WITH_CONCERNS|DONE|BLOCKED|NEEDS_CONTEXT' | head -1 | tr '[:lower:]' '[:upper:]' || true)
  printf '%s\n' "${S:-MISSING}"
}

# _lease_copy_discoveries <task_id> <builder> <output-file> — copy the
# builder's "Discoveries for later tasks" block into ops/MEMORY.md (scrubbed,
# lead-side — builders never write ops/). Skips "None"/empty.
# The LAST block wins (the contract template echoed back by a prompt-printing
# CLI carries an earlier placeholder block); the placeholder itself and the
# None spellings are skipped; the copy is bounded (20 lines x 400 chars) and
# labeled as unverified builder claims, never as lead decisions — MEMORY.md is
# read as trusted institutional knowledge by later sessions. It lands as a
# 4-space-indented literal block, never a fence: a builder line of three
# backticks would close a fence and turn the rest into live Markdown.
_lease_copy_discoveries() {
  local TASK_ID=$1 BUILDER=$2 F=$3
  local BLOCK
  BLOCK=$(awk 'BEGIN{p=0; b=""} /^[[:space:]]*[-*]?[[:space:]]*\**Discoveries for later tasks\**:?/{p=1; b=""; line=$0; sub(/^[^:]*:[[:space:]]*/, "", line); if (line != "") b=line "\n"; next} p==1{ if ($0 ~ /^[[:space:]]*$/) {p=0; next} b=b $0 "\n" } END{printf "%s", b}' "$F" 2>/dev/null | head -n 20 | cut -c1-400 | _scrub || true)
  case "$(printf '%s' "$BLOCK" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')" in ''|none|'-none'|'*none'|'none.'|'<list,ornone>'|'<listornone>') return 0 ;; esac
  # Anchored to the lead checkout, not the cwd: lease_collect may run from a
  # subdirectory, and a relative ops/ would land the block in the wrong tree.
  mkdir -p "${_LEASE_REPO}/ops"
  {
    echo ""
    echo "## Builder-reported discoveries — lease ${TASK_ID} (builder: ${BUILDER}, $(date -u +%Y-%m-%d))"
    echo "Unverified builder claims, not lead decisions — promote into Decisions/Gotchas only after checking them:"
    echo ""
    printf '%s\n' "$BLOCK" | sed 's/^/    /'
  } >> "${_LEASE_REPO}/ops/MEMORY.md" 2>/dev/null || true
  echo "lease_collect: copied the builder's discoveries into ops/MEMORY.md (labeled unverified)" >&2
}

# lease_collect <task_id> — lead-side harvest of a finished builder. Exit 0:
# state=review, prints the output-file path (U10 feeds it to the reviewer).
# Nonzero: routed by the KTD-9 class the launcher recorded (<out>.class):
#   deterministic       -> state=failed, fail fast with guidance, NO requeue
#   timeout / retryable -> orphan path (reclaim -> requeue once -> escalate)
# On a CLEAN exit the typed report decides (KTD11):
#   Status: DONE / DONE_WITH_CONCERNS -> state=review (report_status recorded;
#                                        discoveries copied to ops/MEMORY.md)
#   Status: BLOCKED / NEEDS_CONTEXT    -> state=escalated, never review
#   no Status line                     -> "report missing": state stays
#                                        building, rc _RC_DEGRADED (80); the
#                                        lead re-dispatches with the contract
#                                        restated (lease_redispatch needs
#                                        state=review, so use lease_requeue's
#                                        sibling: mark orphaned -> reclaim ->
#                                        requeue) or escalates after one repeat
# The claude lane's envelope (<out>.envelope) is recorded first: result_subtype,
# result_is_error and session_id (the next dispatch resumes it), and a
# max-turns stop (subtype error_max_turns, nonzero exit) is routed as a clean
# exit without a report: report missing (KTD16).
lease_collect() {
  _lead_only lease_collect || return $?
  local TASK_ID=${1:?usage: lease_collect <task_id>}
  local STATE PID="" OUT="" PID_STARTED="" PGID="" ROW RC CLASS
  _lease_ctx || return 1
  # Before anything reads the row or touches the worktree: a builder that
  # planted git config, hooks, a pointer redirect or a ledger edit is caught
  # here, and its snapshot is never taken (KTD18).
  _lead_integrity_check lease_collect || return $?
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_collect: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if [ "$STATE" != "building" ]; then
    echo "lease_collect: ERROR task ${TASK_ID} is in state '${STATE}' (want building)" >&2
    return 1
  fi
  ROW=$(_ledger_get_row "$TASK_ID" pid output_file pid_started pgid) || ROW=""
  { IFS= read -r PID || true; IFS= read -r OUT || true; IFS= read -r PID_STARTED || true; IFS= read -r PGID || true; } <<COLLECT_ROW_EOF
${ROW}
COLLECT_ROW_EOF
  if [ ! -f "${OUT}.rc" ]; then
    if [ "$(_lease_proc_state "$PID" "$PID_STARTED" "$PGID")" = alive ]; then
      echo "lease_collect: task ${TASK_ID} still running (pid ${PID}) — lease_wait ${TASK_ID}, which also enforces the deadline" >&2
      return 1
    fi
    echo "lease_collect: task ${TASK_ID} builder died without an exit record — silent death, taking the orphan path" >&2
    _ledger_update "$TASK_ID" state=orphaned || return 1
    lease_reclaim "$TASK_ID" || true
    return 1
  fi
  RC=$(cat "${OUT}.rc" 2>/dev/null || echo 1)
  CLASS=$(cat "${OUT}.class" 2>/dev/null || true)
  # The claude lane's envelope (KTD16, _lease_claude_envelope): subtype and
  # is_error go to the row, and the session id the next dispatch resumes. A
  # max-turns stop is the lane's turn cap, not a crash: the work so far stays in
  # the worktree, and with no report it routes as report missing.
  if [ -f "${OUT}.envelope" ]; then
    local ESUB="" EERR="" ESID="" L SEEN=""
    # The first line of each key wins.
    while IFS= read -r L || [ -n "$L" ]; do
      case "$L" in
        subtype=*)    case "$SEEN" in *s*) ;; *) ESUB=${L#subtype=}; SEEN="${SEEN}s" ;; esac ;;
        is_error=*)   case "$SEEN" in *e*) ;; *) EERR=${L#is_error=}; SEEN="${SEEN}e" ;; esac ;;
        session_id=*) case "$SEEN" in *i*) ;; *) ESID=${L#session_id=}; SEEN="${SEEN}i" ;; esac ;;
      esac
    done 2>/dev/null < "${OUT}.envelope"
    case "$ESUB" in *[!a-z_]*) ESUB="" ;; esac
    case "$EERR" in true|false) ;; *) EERR="" ;; esac
    _claude_session_ok "$ESID" || ESID=$(_ledger_get "$TASK_ID" session_id 2>/dev/null || true)
    _ledger_update "$TASK_ID" result_subtype="$ESUB" result_is_error="$EERR" session_id="$ESID" || return 1
    if [ "$ESUB" = error_max_turns ] && [ "$RC" != 0 ]; then
      echo "lease_collect: task ${TASK_ID} claude builder stopped at its turn cap (subtype error_max_turns, rc ${RC}) before its final report — routed as report missing" >&2
      RC=0
    fi
  fi
  if [ "$RC" -eq 0 ] 2>/dev/null; then
    local REPORT BUILDER
    REPORT=$(_lease_parse_status "$OUT")
    BUILDER=$(_ledger_get "$TASK_ID" builder_cli 2>/dev/null || true)
    _ledger_update "$TASK_ID" report_status="$REPORT" || return 1
    case "$REPORT" in
      DONE|DONE_WITH_CONCERNS)
        # The builder is finished, then the lead takes its snapshot, which the
        # review, the merge and any approval bind to (KTD3). The detached
        # builder process swept its own process group before it wrote the
        # exit record (KTD10); a leader still finishing its exit is sent TERM
        # here, and only while it still answers with the recorded start time
        # and group: a reused pid is never signalled. A row with no recorded
        # start time (from before 3.3.3) is never signalled here: its pid can
        # only be tested for liveness, and by now it may be anyone's. A row
        # from before KTD10 (no pgid) gets the old sweep of the pid's own tree,
        # under the same start-time test.
        if [ -n "$PID_STARTED" ]; then
          _lease_kill_builder "$PID" "$PGID" "$PID_STARTED" term
        fi
        # Once more, right before the snapshot's `add -A` runs the clean
        # filters: a builder process that left its process group (its own
        # setsid) and is still alive could have planted config in that window.
        _lead_integrity_check lease_collect || return $?
        if ! _lease_snapshot "$TASK_ID"; then
          _ledger_update "$TASK_ID" state=escalated reason="collect snapshot failed (see stderr)" || true
          echo "lease_collect: task ${TASK_ID} ESCALATED — the lead could not take its collect snapshot; the builder's work is still in its worktree" >&2
          return 1
        fi
        _ledger_update "$TASK_ID" state=review || return 1
        # The snapshot's scan (_lease_snapshot), as it recorded it.
        if [ "$_LP_STATUS" != no ]; then
          echo "lease_collect: task ${TASK_ID}'s snapshot touches protected paths (${_LP_PATHS}); lease_merge needs a merge approval for it from the lead (when the lead's CLI did not build it) or the user: lease_approve task:${TASK_ID} <lead CLI|user> (U10)" >&2
        fi
        _lease_copy_discoveries "$TASK_ID" "${BUILDER:-unknown}" "$OUT"
        echo "lease_collect: task ${TASK_ID} builder exited 0 with Status: ${REPORT} — state=review, output below" >&2
        printf '%s\n' "$OUT"
        return 0
        ;;
      BLOCKED|NEEDS_CONTEXT)
        local WHY
        WHY=$(grep -iE '^[[:space:]]*[-*]?[[:space:]]*\**Concerns\**:?' "$OUT" 2>/dev/null | tail -1 | cut -c1-200 | _scrub || true)
        _ledger_update "$TASK_ID" state=escalated reason="builder reported ${REPORT}: ${WHY:-see output}" || return 1
        echo "lease_collect: task ${TASK_ID} builder reported Status: ${REPORT} — ESCALATED, never routed to review (see ${OUT}). Supply the missing context / unblock, then re-lease." >&2
        return 1
        ;;
      *)
        # Report missing (KTD11). A finished builder with a dead pid is never
        # orphaned by lease_heartbeat_check and lease_requeue refuses a building
        # row, so the lease must transition here: the FIRST miss goes back to
        # leased — lease_dispatch (which always prepends the contract) re-runs
        # the SAME builder in the SAME worktree, keeping its uncommitted work —
        # and the SECOND miss escalates (two clean exits without a report mean
        # the builder is not following the contract).
        local MISSES
        MISSES=$(_ledger_get "$TASK_ID" report_missing_count 2>/dev/null || true)
        case "${MISSES:-}" in ''|*[!0-9]*) MISSES=0 ;; esac
        MISSES=$((MISSES + 1))
        if [ "$MISSES" -ge 2 ]; then
          local FIRST_OUT
          FIRST_OUT=$(_ledger_get "$TASK_ID" report_missing_output 2>/dev/null || true)
          _ledger_update "$TASK_ID" state=escalated report_missing_count="$MISSES" reason="report missing twice: clean exits without a Status line (outputs: ${FIRST_OUT:-?} ; ${OUT})" || return 1
          echo "lease_collect: task ${TASK_ID} builder exited 0 without a final 'Status:' report for the SECOND time — ESCALATED, never review (KTD11: rule on reassigning the task to another roster member or stopping the wave; ledger the Ruling). Output: ${OUT}" >&2
          return 1
        fi
        # Keep the first miss's output: the re-dispatch rewrites ${OUT} in place.
        cp "$OUT" "${OUT}.miss1" 2>/dev/null || true
        _ledger_update "$TASK_ID" state=leased report_missing_count="$MISSES" report_missing_output="${OUT}.miss1" reason="report missing: clean exit without a Status line (${OUT}; re-dispatch once, contract restated)" || return 1
        echo "lease_collect: task ${TASK_ID} builder exited 0 but its output has NO final 'Status:' report line — report missing, NOT review-ready (rc ${_RC_DEGRADED}; state back to leased, same builder + worktree kept). Re-dispatch once: lease_dispatch ${TASK_ID} \"<one line: the previous run ended without a report> <original prompt>\" — a second miss escalates. Output: ${OUT}" >&2
        return "$_RC_DEGRADED"
        ;;
    esac
  fi
  if [ -z "$CLASS" ]; then
    _classify_invoke_failure "$RC" "$OUT"
    CLASS="$INVOKE_FAILURE_CLASS"
  fi
  case "$CLASS" in
    deterministic)
      _ledger_update "$TASK_ID" state=failed reason="deterministic failure rc=${RC}" || return 1
      echo "lease_collect: task ${TASK_ID} FAILED deterministically (rc=${RC}) — retry cannot help; fix the cause (see ${OUT}) and escalate. No requeue (KTD-9)." >&2
      return 1
      ;;
    *)
      echo "lease_collect: task ${TASK_ID} builder failed rc=${RC} class=${CLASS} — orphaning for the requeue path (see ${OUT})" >&2
      _ledger_update "$TASK_ID" state=orphaned || return 1
      lease_reclaim "$TASK_ID" || true
      return 1
      ;;
  esac
}

# lease_pin_reviewer <task_id> <reviewer> — record the non-author reviewer for a
# lease (KTD-10). The reviewer pinned here stays this task's reviewer for ALL
# <=3 fix cycles, and — because it lives in the ledger — that pin survives a
# session boundary, so a fresh session cannot silently re-pin a different
# reviewer mid-sprint. Idempotent: re-pinning the SAME reviewer is a no-op
# that keeps the recorded class; pinning a DIFFERENT one is refused. Refuses
# reviewer == builder_cli (AE3). The reviewer is a CLI or `user`
# (_approver_ok), and the pin records its class (U10, KTD2): user; lead when
# the CLI is the current lead (lead_is); worker for any other CLI. It also
# records the row's handover_at at pin time (pin_handover_at), so a forced
# handover after the pin is visible to lease_merge. Call it after
# lease_collect (state=review), before reviewing.
lease_pin_reviewer() {
  _lead_only lease_pin_reviewer || return $?
  local TASK_ID=${1:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local REVIEWER=${2:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local ROW BUILDER PINNED PCLASS HO CLASS
  _lease_ctx || return 1
  _lead_integrity_check lease_pin_reviewer || return $?
  ROW=$(_ledger_get_row "$TASK_ID" builder_cli pinned_reviewer reviewer_class handover_at) || {
    echo "lease_pin_reviewer: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  { IFS= read -r BUILDER || true; IFS= read -r PINNED || true; IFS= read -r PCLASS || true
    IFS= read -r HO || true; } <<PIN_ROW_EOF
${ROW}
PIN_ROW_EOF
  if ! _approver_ok "$REVIEWER"; then
    echo "lease_pin_reviewer: REFUSED — '${REVIEWER}' is not a known reviewer identity (user, or one of: $(_known_clis)). A fabricated label cannot stand in for a real reviewer (AE3)." >&2
    return 1
  fi
  if [ "$REVIEWER" = "$BUILDER" ]; then
    echo "lease_pin_reviewer: REFUSED — reviewer '${REVIEWER}' is the builder of ${TASK_ID}; self-review is never allowed (AE3). Pick a non-author reviewer." >&2
    return 1
  fi
  if [ -n "$PINNED" ] && [ "$PINNED" != "$REVIEWER" ]; then
    echo "lease_pin_reviewer: REFUSED — ${TASK_ID} is already pinned to reviewer '${PINNED}' (KTD-10: the same reviewer stays across all fix cycles). Re-review with '${PINNED}', or escalate to the user if that reviewer is unavailable. A protected change needs a merge approval next to this pin, never a re-pin: lease_approve task:${TASK_ID} <lead CLI|user>." >&2
    return 1
  fi
  if [ -n "$PINNED" ]; then
    echo "lease_pin_reviewer: ${TASK_ID} is already pinned to '${PINNED}' (${PCLASS}); unchanged" >&2
    return 0
  fi
  CLASS=$(_lease_reviewer_class "$REVIEWER")
  _ledger_update "$TASK_ID" pinned_reviewer="$REVIEWER" reviewer_class="$CLASS" \
    pin_handover_at="$HO" || return 1
  echo "lease_pin_reviewer: ${TASK_ID} reviewer pinned to '${REVIEWER}' (${CLASS}; holds across all <=3 cycles)" >&2
}

# _lease_reviewer_class <reviewer> — user, lead (the CLI is the current lead,
# lead_is) or worker (U10, KTD2): the class lease_pin_reviewer records and
# lease_approve gives an approver.
_lease_reviewer_class() {
  if [ "${1:-}" = user ]; then
    echo user
  elif lead_is "${1:-}"; then
    echo lead
  else
    echo worker
  fi
}

# _lease_recorded_class <reviewer> <lead_cli> — the class of a pin recorded
# with no reviewer_class (a row from before 4.0 or before U10): user, lead
# when the reviewer is the row's own lead (its lead_cli; empty reads as
# _LEAD_LEGACY_CLI, the only lead those versions had), else worker. Taken from
# the row, never from the current lead, so it holds across handovers: a stale
# lead pin still needs the user's merge approval after the lead changed
# (KTD2), and a worker pin never turns into a lead one.
_lease_recorded_class() {
  if [ "${1:-}" = user ]; then
    echo user
  elif [ -n "${1:-}" ] && [ "$1" = "${2:-$_LEAD_LEGACY_CLI}" ]; then
    echo lead
  else
    echo worker
  fi
}

# ---------------------------------------------------------------------------
# Approvals (U10 — KTD2, KTD4; R5, R32, R33)
# ---------------------------------------------------------------------------

# lease_approve <scope> <approver> — record an approval in the ledger.
#   task:<id>           a merge approval (lease_merge needs one for a protected
#                       diff or a stale lead-class pin): <approver> is `user`,
#                       or the current lead's CLI when that CLI did not build the
#                       task (a protected task built by the lead's own CLI
#                       routes to the user). Bound to the task's collect
#                       snapshot (approval_snapshot): the next fix cycle's
#                       collect writes a new snapshot and voids it. Needs the
#                       task in review.
#   promotion:<branch>  a promotion approval (lease_promote needs one when its
#                       gate is on): `user` only. Bound to <branch>'s tree, the
#                       protected paths it changes against the default branch
#                       and the default branch's commit, in [baseline]
#                       (promotion_*): a later merge or a default-branch move
#                       voids it, and lease_promote uses it once.
# A worker CLI never approves. Where it runs decides the rest
# (_lead_origin_match): a lead-class approval by <cli> comes from <cli>'s own
# session (via=lead-session, host <cli>), a terminal (via=tty: the user
# relaying it) or the SELF seam simulating <cli> (via=test), and is refused
# from another CLI's session, where a record claiming the lead's review would
# contradict itself (lease_merge does not count such a record either); a
# user-class approval is recorded from any stated origin. Both are refused
# from a shell with none (via=none), since the record could not say where it
# came from, and under both leads' host markers, before a terminal or the seam
# is consulted. Every record carries its origin (_lead_origin): via, the host
# CLI, the lead's CLI and the time. The record is written under the lease root
# the ledger was last written under (_lease_at_ledger_root), so an approval
# from a shell with another TMPDIR lands beside the lead's integrity anchors.
# Exempt from the lead host check
# (R38): run under the other lead's markers it records that origin instead of refusing; the worker marker
# and the lease root still refuse (KTD9, rc 45). It runs no integrity check:
# lease_merge and lease_promote run theirs, and check the record against the
# state they act on. Audit, not prevention: any shell with the helper can
# record a user approval, the lead's agent shell included (via=lead-session).
# rc: 0 recorded; 1 refused (an origin, the approver, the state, or a recorded
# lease root that is gone); 45 a worker or a lease root; 64 usage.
lease_approve() {
  _lead_only lease_approve --any-host || return $?
  local USAGE="lease_approve: usage: lease_approve task:<id>|promotion:<branch> user|<lead CLI>"
  local SCOPE=${1:-} WHO=${2:-} OUT RC=0 LEADNOW CLASS STAMP T B ROW STATE SNAP BUILDER TREE PDIG M=0
  local TRIFORGE_LEASE_ROOT="${TRIFORGE_LEASE_ROOT:-}"   # _lease_at_ledger_root may set it
  if [ -z "$SCOPE" ] || [ -z "$WHO" ] || [ "$#" -gt 2 ]; then
    echo "$USAGE" >&2
    return 64
  fi
  if ! _approver_ok "$WHO"; then
    echo "lease_approve: REFUSED — '${WHO}' is not an approver: user, or a CLI (one of: $(_known_clis)) (KTD2)" >&2
    return 1
  fi
  _lease_ctx || return 1
  _lease_at_ledger_root lease_approve || return 1
  _lead_resolve 2>/dev/null || RC=$?
  if [ "$RC" -ne 0 ]; then
    OUT=$(resolve_lead 2>&1) || true   # for its message; RC is the first call's
    echo "lease_approve: REFUSED — the lead could not be resolved (rc ${RC}), so whose approval this is can't be told; fail closed: $(printf '%s' "$OUT" | tail -1)" >&2
    return 1
  fi
  LEADNOW=$_LEAD_CLI
  CLASS=$(_lease_reviewer_class "$WHO")
  if [ "$CLASS" = worker ]; then
    echo "lease_approve: REFUSED — ${WHO} is a worker CLI here (the lead is ${LEADNOW}); an approval is the lead's or the user's: lease_approve ${SCOPE} user (KTD2)" >&2
    return 1
  fi
  _lead_origin
  _lead_origin_match "$_LEAD_VIA" "$_LEAD_HOST" "$WHO" || M=$?
  case "$M" in
    3)
      echo "lease_approve: REFUSED — $(_lead_ambiguous_note); an approval records where it was given (KTD4)" >&2
      return 1
      ;;
    2)
      echo "lease_approve: REFUSED — via=none: no lead host markers (${_LEAD_HOST_MARKERS}) and no terminal on stdin, so the record could not say where it was given; an approval needs a stated origin. Run it from a lead's tool shell or a terminal (KTD4)" >&2
      return 1
      ;;
    1)
      if [ "$CLASS" = lead ]; then
        echo "lease_approve: REFUSED — a ${WHO} (lead) approval comes from the ${WHO} lead's own session or a terminal; this shell runs with via=${_LEAD_VIA} host=${_LEAD_HOST}. Record the user's approval instead, on the user's say-so: lease_approve ${SCOPE} user (KTD2)" >&2
        return 1
      fi
      ;;
  esac
  STAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  case "$SCOPE" in
    task:*)
      T=${SCOPE#task:}
      if ! _lease_valid_task_id "$T"; then echo "$USAGE" >&2; return 64; fi
      ROW=$(_ledger_get_row "$T" state snapshot_sha builder_cli) || { echo "lease_approve: ERROR no lease row for '${T}'" >&2; return 1; }
      { IFS= read -r STATE || true; IFS= read -r SNAP || true; IFS= read -r BUILDER || true; } <<APPROVE_ROW_EOF
${ROW}
APPROVE_ROW_EOF
      if [ "$STATE" != review ] || [ -z "$SNAP" ]; then
        echo "lease_approve: REFUSED — ${T} is in state '${STATE}'; a merge approval binds to the snapshot lease_collect takes, so approve after it (state review)" >&2
        return 1
      fi
      if [ "$CLASS" = lead ] && [ "$WHO" = "$BUILDER" ]; then
        echo "lease_approve: REFUSED — ${T} was built by the lead's own CLI (${BUILDER}); a protected task built by the lead's own CLI routes to the user: lease_approve task:${T} user (KTD2)" >&2
        return 1
      fi
      _ledger_write "$T" approval_class="$CLASS" approval_by="$WHO" approval_snapshot="$SNAP" approval_via="$_LEAD_VIA" \
        approval_host="$_LEAD_HOST" approval_lead_cli="$LEADNOW" approval_at="$STAMP" >/dev/null || return 1
      echo "lease_approve: task ${T} approved by ${WHO} (${CLASS}) for snapshot ${SNAP:0:12}; recorded via=${_LEAD_VIA} host=${_LEAD_HOST} lead=${LEADNOW} at ${STAMP}. A later fix cycle's collect voids it. Audit, not prevention: the record says where this ran, not who typed it." >&2
      ;;
    promotion:*)
      B=${SCOPE#promotion:}
      if [ "$CLASS" != user ]; then
        echo "lease_approve: REFUSED — a promotion approval is the user's alone (KTD4); ${WHO} is the lead. Ask the user to run: lease_approve promotion:${B} user" >&2
        return 1
      fi
      if [ -z "$B" ] || ! TREE=$(_lgr rev-parse --verify --quiet "refs/heads/${B}^{tree}" 2>/dev/null); then
        echo "lease_approve: ERROR '${B}' is not a local branch (promotion:<integration branch>)" >&2
        return 1
      fi
      _lease_default_ref
      if [ -z "$_LEASE_DEF" ] || [ -z "$_LEASE_DEF_SHA" ]; then
        echo "lease_approve: ERROR no default branch (origin/HEAD, main or master) to bind a promotion approval to" >&2
        return 1
      fi
      if [ "$B" = "$_LEASE_DEF" ]; then
        echo "lease_approve: ERROR ${B} is the default branch; approve the integration branch that lease_promote promotes into it" >&2
        return 1
      fi
      _lease_protected_scan "$_LEASE_DEF" "${_LEASE_DEF}...refs/heads/${B}"
      if [ -n "$_LP_ERR" ]; then
        echo "lease_approve: REFUSED — the protected-path scan could not run, so there is no protected-path set to bind the approval to: ${_LP_ERR}" >&2
        return 1
      fi
      PDIG=$(_lease_protected_digest "$_LP_HITS") || { echo "lease_approve: ERROR could not digest the protected-path set" >&2; return 1; }
      _ledger_write @baseline promotion_scope="promotion:${B}" promotion_class=user promotion_by=user promotion_tree="$TREE" \
        promotion_default="$_LEASE_DEF" promotion_default_sha="$_LEASE_DEF_SHA" promotion_protected="$PDIG" \
        promotion_via="$_LEAD_VIA" promotion_host="$_LEAD_HOST" promotion_lead_cli="$LEADNOW" promotion_at="$STAMP" promotion_voided= >/dev/null || return 1
      # A checkout with no integrity baseline yet (no lease ever ran): record
      # it now, as lease_create would, or the next check reads the lead's
      # ledger copy as a baseline that went missing.
      if [ -z "$(_ledger_get @baseline config 2>/dev/null || true)" ]; then
        _lead_baseline_record _ledger_write >/dev/null || return 1
      fi
      echo "lease_approve: promotion of ${B} into ${_LEASE_DEF} approved by the user: tree ${TREE:0:12}, ${_LEASE_DEF} at ${_LEASE_DEF_SHA:0:12}, ${_LP_COUNT} protected path(s)${_LP_PATHS:+: ${_LP_PATHS}}; recorded via=${_LEAD_VIA} host=${_LEAD_HOST} lead=${LEADNOW} at ${STAMP}. A later merge or a move of ${_LEASE_DEF} voids it. Audit, not prevention: any shell with the helper can record this, the lead's agent shell included (via=lead-session)." >&2
      ;;
    *)
      echo "$USAGE" >&2
      return 64
      ;;
  esac
  return 0
}

# lease_attribution <task_id> — the task's ops/CHANGELOG.md attribution, one
# line from the ledger (U10): builder (model), reviewer (class), the lead's CLI
# at create (lead_cli; a row from before 4.0 reads as _LEAD_LEGACY_CLI), the
# approval that stood behind the merge with its origin (merge_approval, or
# none), and the merge commit. lease_merge prints it; read-only otherwise.
lease_attribution() {
  local T=${1:?usage: lease_attribution <task_id>} ROW BUILDER MODEL REVIEWER PINNED CLASS LC APPROVAL MC
  ROW=$(_ledger_get_row "$T" builder_cli builder_model reviewer pinned_reviewer reviewer_class lead_cli merge_approval merge_commit) || {
    echo "lease_attribution: ERROR no lease row for '${T}'" >&2; return 1; }
  { IFS= read -r BUILDER || true; IFS= read -r MODEL || true; IFS= read -r REVIEWER || true; IFS= read -r PINNED || true
    IFS= read -r CLASS || true; IFS= read -r LC || true; IFS= read -r APPROVAL || true; IFS= read -r MC || true; } <<ATTR_ROW_EOF
${ROW}
ATTR_ROW_EOF
  REVIEWER=${REVIEWER:-$PINNED}
  if [ -z "$CLASS" ] && [ -n "$REVIEWER" ]; then CLASS=$(_lease_recorded_class "$REVIEWER" "$LC"); fi
  printf '%s\n' "- lease ${T}: builder ${BUILDER:-?} (${MODEL:-host default}), reviewer ${REVIEWER:-none} (${CLASS:-none}), lead ${LC:-$_LEAD_LEGACY_CLI}, approval ${APPROVAL:-none}, merge ${MC:0:12}"
}

# _lease_open_rows <ledger> — the open leases (every state but merged and
# failed) of <ledger>, read once for roster_write_lead's lead switch: first
# "<task> (<state>), ..." for display (characters that don't print shown as
# ?), a tab, and how many are building; then each task id as the ledger has
# it, one per line, for _lease_mark_handover. Nothing for no ledger; rc 1 with
# the reason on stdout when it can't be read (the switch then refuses: fail
# closed).
_lease_open_rows() {
  LO_LEDGER="$1" python3 -c '
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("no TOML parser to read the lease ledger")
        sys.exit(1)
p = os.environ["LO_LEDGER"]
if not os.path.isfile(p):
    sys.exit(0)
try:
    with open(p, "rb") as f:
        leases = tomllib.load(f).get("lease", {})
except Exception as exc:
    print(p + " does not parse: " + " ".join(str(exc).split()))
    sys.exit(1)
leases = leases if isinstance(leases, dict) else {}
def clean(x):
    return "".join(ch if ch.isprintable() else "?" for ch in str(x))
open_rows = [(t, r) for t, r in sorted(leases.items()) if isinstance(r, dict) and str(r.get("state", "")) not in ("merged", "failed")]
shown = [(clean(t), clean(r.get("state", ""))) for t, r in open_rows]
print(", ".join(t + " (" + s + ")" for t, s in shown) + "\t" + str(sum(1 for t, s in shown if s == "building")))
for t, r in open_rows:
    print(t)
'
}

# _lease_mark_handover <from-cli> <to-cli> <task ids> — stamp handover_from,
# handover_to and handover_at on each open row named in <task ids> (one per
# line, as _lease_open_rows prints them): roster_write_lead --force calls it
# right before it writes the new [lead] (KTD2), once its own checks passed and
# it moved to the ledger's lease root (_lease_at_ledger_root): it runs from the
# new lead or a terminal, so the write goes through _ledger_write, as
# roster_write_lead skips the host check too. A lead-class pin made before it
# then needs the user's merge approval (_lease_merge_gate compares handover_at
# with the pin's pin_handover_at).
_lease_mark_handover() {
  local FROM=${1:-unknown} TO=${2:-} IDS=${3:-} STAMP T
  _lease_ctx || return 1
  [ -f "$_LEASE_LEDGER" ] || return 0
  STAMP=$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ"))') || return 1
  while IFS= read -r T; do
    [ -n "$T" ] || continue
    _ledger_write "$T" handover_from="$FROM" handover_to="$TO" handover_at="$STAMP" >/dev/null || return 1
  done <<HANDOVER_EOF
${IDS}
HANDOVER_EOF
  return 0
}

# lease_merge <task_id> <reviewer-identity> — single-commit-per-task merge
# (KTD-5) with the AE3 mechanical guard, hardened three ways: the reviewer must
# be (1) a KNOWN identity, a registered CLI or `user` (_approver_ok; a
# fabricated label like "codex-reviewer" is rejected), (2) different from
# builder_cli (self-review never merges), and (3)
# already PINNED via lease_pin_reviewer — the pin is the "a review happened"
# receipt, so a merge with no pin is refused. It squash-merges the lead's collect snapshot
# (KTD3/KTD19 — recorded by lease_collect; "commit nothing; the lead
# collects") into the MAIN tree only after the integrity check, the
# integration-branch check, the snapshot checks (_lease_verify_snapshot:
# branch = base + that one commit, worktree unchanged since collect, no ops/
# path) and the approval gate pass (_lease_merge_gate, U10: a protected diff
# or a stale lead-class pin needs a merge approval for this snapshot, rc 42),
# records reviewer, its class, the approval and merge_commit, voids a
# promotion approval on record, prints the CHANGELOG attribution
# (lease_attribution), then reclaims via the safe-prune
# path. Every git call runs through _lead_git, so no repository hook runs on
# the merge commit. Squash conflicts leave a dirty index: reset --merge, state
# stays review, the lead resolves manually.
lease_merge() {
  _lead_only lease_merge || return $?
  local TASK_ID=${1:?usage: lease_merge <task_id> <reviewer-identity>}
  local REVIEWER=${2:-}
  local STATE BUILDER WT BRANCH SHA PINNED SNAP
  _lease_ctx || return 1
  _lead_integrity_check lease_merge || return $?
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_merge: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if [ "$STATE" != "review" ]; then
    echo "lease_merge: ERROR task ${TASK_ID} is in state '${STATE}' (want review — lease_collect sets it)" >&2
    return 1
  fi
  if [ -z "$REVIEWER" ]; then
    echo "lease_merge: ERROR reviewer identity is required — no merge without a named reviewer (AE3)" >&2
    return 1
  fi
  if ! _approver_ok "$REVIEWER"; then
    echo "lease_merge: REFUSED — '${REVIEWER}' is not a known reviewer identity (user, or one of: $(_known_clis)). A fabricated label like 'codex-reviewer' cannot pass the non-author gate (AE3)." >&2
    return 1
  fi
  BUILDER=$(_ledger_get "$TASK_ID" builder_cli)
  if [ "$REVIEWER" = "$BUILDER" ]; then
    echo "lease_merge: REFUSED — reviewer '${REVIEWER}' is the builder of ${TASK_ID}; self-review never merges (AE3). Pick a non-author reviewer." >&2
    return 1
  fi
  # Pin IS the "a review happened" receipt (KTD-10). A merge with NO pinned
  # reviewer means the pin/review step (lease_pin_reviewer) never ran — refuse,
  # rather than trust a bare argument that no review backs. When a pin exists,
  # the SAME reviewer must approve every cycle: reject a mismatch so a session
  # boundary cannot swap the reviewer.
  PINNED=$(_ledger_get "$TASK_ID" pinned_reviewer 2>/dev/null || true)
  if [ -z "$PINNED" ]; then
    echo "lease_merge: REFUSED — no reviewer is pinned for ${TASK_ID}. Pin the reviewer first: 'lease_pin_reviewer ${TASK_ID} <reviewer>' (that step records that a review happened); merging without a pin is not allowed (AE3/KTD-10)." >&2
    return 1
  fi
  if [ "$PINNED" != "$REVIEWER" ]; then
    echo "lease_merge: REFUSED — ${TASK_ID} is pinned to reviewer '${PINNED}' (KTD-10) but lease_merge was called with '${REVIEWER}'. The same non-author reviewer must approve across all cycles; re-run with '${PINNED}' (or escalate if that reviewer is unavailable)." >&2
    return 1
  fi
  WT=$(_ledger_get "$TASK_ID" worktree)
  BRANCH=$(_ledger_get "$TASK_ID" branch)
  if [ ! -d "$WT" ]; then
    echo "lease_merge: ERROR worktree missing: ${WT}" >&2
    return 1
  fi

  # Integration-branch guard (KTD-5): lease_merge lands a squash commit on the
  # SPRINT INTEGRATION BRANCH, never the repo's default branch. Refuse when the
  # main tree is checked out on the default branch — the lead must cut an
  # integration branch first; promotion to the default branch is lease_promote's
  # gated job. When there is no default-branch concept (detached HEAD, or a
  # single-branch repo with no origin/HEAD and no local main/master), allow it
  # but log so the honest boundary is visible.
  local DEFAULT_BRANCH CURRENT_BRANCH
  DEFAULT_BRANCH=$(_lease_default_branch)
  CURRENT_BRANCH=$(_lease_current_branch)
  if [ -n "$DEFAULT_BRANCH" ] && [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
    echo "lease_merge: REFUSED — the main tree is on the default branch '${DEFAULT_BRANCH}'. lease_merge lands on a sprint integration branch, not the default branch — cut/checkout an integration branch first (e.g. git checkout -b sprint/<name>), then rerun. Promotion to '${DEFAULT_BRANCH}' is lease_promote's gated job (KTD-5)." >&2
    return 1
  fi
  if [ -z "$DEFAULT_BRANCH" ] || [ -z "$CURRENT_BRANCH" ]; then
    # No default-branch concept (detached HEAD, or a single-branch repo with no
    # origin/HEAD and no local main/master). With no default branch there is no
    # integration/promotion separation to enforce, so landing the squash here
    # would silently bypass the KTD-5 gate (lease_promote would never run).
    # Refuse unless the lead explicitly confirms this checkout IS the intended
    # integration branch via TRIFORGE_INTEGRATION_BRANCH.
    if [ -z "${TRIFORGE_INTEGRATION_BRANCH:-}" ]; then
      echo "lease_merge: REFUSED — no default-branch concept (default='${DEFAULT_BRANCH:-<none>}' current='${CURRENT_BRANCH:-<detached>}'), so the integration/promotion separation (KTD-5) cannot be enforced and lease_promote's gate would be bypassed. Set TRIFORGE_INTEGRATION_BRANCH=<name> to confirm this checkout is the integration branch and proceed intentionally." >&2
      return 1
    fi
    echo "lease_merge: NOTE no default-branch concept — proceeding because TRIFORGE_INTEGRATION_BRANCH='${TRIFORGE_INTEGRATION_BRANCH}' explicitly confirms the integration branch (single-branch or detached repo)." >&2
  fi

  # Snapshot-only merge (KTD19): the squash comes from the snapshot the lead
  # recorded at collect, never the branch name, and only after the branch,
  # the worktree and the diff still match it. A lease collected before 3.3.3
  # has no snapshot yet: take it now, under the same checks.
  _lead_integration_check lease_merge || return $?
  SNAP=$(_ledger_get "$TASK_ID" snapshot_sha 2>/dev/null || true)
  if [ -z "$SNAP" ]; then
    echo "lease_merge: NOTE ${TASK_ID} was collected before 3.3.3 — taking the lead's snapshot now" >&2
    _lease_snapshot "$TASK_ID" || return 1
    SNAP=$(_ledger_get "$TASK_ID" snapshot_sha)
  fi
  _lease_verify_snapshot "$TASK_ID" || return 1
  # Who stands behind this merge (U10): the protected check over the lease's
  # full diff, base to the verified snapshot, at every merge, and the merge
  # approval it then needs; a stale lead-class pin needs the user's.
  _lease_merge_gate "$TASK_ID" "$BUILDER" "$PINNED" "$SNAP" "$DEFAULT_BRANCH" || return $?

  # The squash commit must contain exactly this lease's work (KTD-5): a
  # pre-dirtied main index would smuggle unrelated changes into it.
  if ! _lgr diff --cached --quiet --no-ext-diff 2>/dev/null; then
    echo "lease_merge: ERROR main tree index has staged changes — commit or unstage them first; the lease commit must contain only ${TASK_ID}'s work" >&2
    return 1
  fi
  if ! _lgr merge --squash "$SNAP" >&2; then
    _lgr reset --merge >&2 || true
    echo "lease_merge: CONFLICT squash-merging ${TASK_ID}'s snapshot ${SNAP:0:12} into the main tree — index reset, state stays review. The lead resolves manually (rebase the work onto HEAD and re-collect), then reruns lease_merge." >&2
    return 1
  fi
  if _lgr diff --cached --quiet --no-ext-diff 2>/dev/null; then
    echo "lease_merge: ERROR ${TASK_ID}'s snapshot brought no changes (builder produced nothing?) — state stays review" >&2
    return 1
  fi
  if ! _lgr commit -q -m "lease(${TASK_ID}): merged from ${BUILDER}, reviewed by ${REVIEWER}" >&2; then
    _lgr reset --merge >&2 || true
    echo "lease_merge: ERROR commit failed — index reset, state stays review" >&2
    return 1
  fi
  SHA=$(_lgr rev-parse HEAD)
  _ledger_update "$TASK_ID" state=merged reviewer="$REVIEWER" pinned_reviewer="$REVIEWER" merge_commit="$SHA" \
    reviewer_class="$_LMG_CLASS" protected="$_LP_STATUS" protected_paths="$_LP_PATHS" merge_approval="$_LMG_APPROVAL" || return 1
  # The lead's own merge moves the integration branch: that is the new state
  # the next merge or promotion must start from (KTD18). It also voids a
  # promotion approval on record (KTD4): the user approved the tree before it.
  local VOID="" PSCOPE="" PVOIDED="" PROW
  PROW=$(_ledger_get_row @baseline promotion_scope promotion_voided 2>/dev/null) || PROW=""
  { IFS= read -r PSCOPE || true; IFS= read -r PVOIDED || true; } <<MERGE_PROMOTION_EOF
${PROW}
MERGE_PROMOTION_EOF
  if [ -n "$PSCOPE" ] && [ -z "$PVOIDED" ]; then
    VOID="$(date -u +%Y-%m-%dT%H:%M:%SZ) by lease_merge ${TASK_ID} (${SHA:0:12})"
  fi
  _ledger_update @baseline integration_branch="$(_lease_current_branch)" integration_sha="$SHA" ${VOID:+"promotion_voided=${VOID}"} >/dev/null || return 1
  echo "lease_merge: ${TASK_ID} merged as ${SHA} (builder ${BUILDER}, reviewer ${REVIEWER}) — reclaiming worktree" >&2
  if [ -n "$VOID" ]; then
    echo "lease_merge: the promotion approval on record is void now (the tree it bound to changed): ${PSCOPE}" >&2
  fi
  echo "lease_merge: attribution for ops/CHANGELOG.md: $(lease_attribution "$TASK_ID" 2>/dev/null || true)" >&2
  lease_reclaim "$TASK_ID" || true
  return 0
}

# _lease_merge_gate <task_id> <builder> <pinned reviewer> <snapshot>
# <default branch> — the U10 half of lease_merge, run on the verified snapshot
# (KTD2-KTD4), with the default branch lease_merge read. 0 when
# the merge may go ahead; otherwise one refusal and _RC_PROMOTE_BLOCKED (42),
# nothing merged. A merge approval (lease_approve task:<id>) counts only for
# this snapshot (approval_snapshot): each fix cycle's collect writes a new one
# and voids it. A user-class approval always counts; a lead-class one only
# while its CLI is the current lead, did not build the task and recorded it
# from its own session or a terminal (_lead_origin_match, roster.sh).
#   protected    the diff base..snapshot touches a protected path, or the scan
#                could not run (fail closed): needs a lead or user approval
#   stale pin    the pin is lead class, but its CLI is no longer the lead or a
#                forced handover came after the pin (handover_at differs from
#                pin_handover_at): needs the user's approval, never a re-pin
# Sets, for lease_merge's ledger write: _LMG_CLASS (the pin's class; for a pin
# recorded with none, derived from the row's own lead, _lease_recorded_class),
# _LMG_APPROVAL (a valid approval for this
# snapshot, needed or not, "<class>:<by> via=<via> host=<host> lead=<lead>
# at=<UTC>", else none) and the _LP_* values of the scan.
_lease_merge_gate() {
  local T=$1 B=$2 P=$3 SNAP=$4 DEF=${5:-} ROW BASE CLASS PINHO HO HOFROM ACLASS ABY ASNAP AVIA AHOST ALEAD AAT RLEAD
  local WHY="" USER_ONLY=0 NEED=0 VALID=0 RECORD="" BLEAD=0
  ROW=$(_ledger_get_row "$T" base_sha reviewer_class pin_handover_at handover_at handover_from approval_class approval_by approval_snapshot approval_via approval_host approval_lead_cli approval_at lead_cli) || ROW=""
  { IFS= read -r BASE || true; IFS= read -r CLASS || true; IFS= read -r PINHO || true; IFS= read -r HO || true; IFS= read -r HOFROM || true
    IFS= read -r ACLASS || true; IFS= read -r ABY || true; IFS= read -r ASNAP || true; IFS= read -r AVIA || true
    IFS= read -r AHOST || true; IFS= read -r ALEAD || true; IFS= read -r AAT || true; IFS= read -r RLEAD || true; } <<MERGE_GATE_EOF
${ROW}
MERGE_GATE_EOF
  if [ -z "$CLASS" ]; then CLASS=$(_lease_recorded_class "$P" "$RLEAD"); fi
  _LMG_CLASS=$CLASS
  _LMG_APPROVAL=none
  if [ "$CLASS" = lead ]; then
    if [ -n "$HO" ] && [ "$HO" != "$PINHO" ]; then
      USER_ONLY=1
      WHY="the pinned reviewer ${P} was the lead when pinned, and a forced handover from ${HOFROM:-the previous lead} came after the pin (${HO}); that review is now the user's to stand behind"
    elif ! lead_is "$P"; then
      USER_ONLY=1
      WHY="the pinned reviewer ${P} was the lead when pinned and is no longer this checkout's lead; that review is now the user's to stand behind"
    fi
  fi
  _lease_protected_scan "$DEF" "$BASE" "$SNAP"
  if [ -n "$_LP_HITS" ] || [ -n "$_LP_ERR" ]; then NEED=1; fi
  if [ -n "$ABY" ]; then RECORD="${ACLASS}:${ABY}, snapshot ${ASNAP:0:12}, via=${AVIA:-?}"; fi
  if [ -n "$ABY" ] && [ "$ASNAP" = "$SNAP" ]; then
    if [ "$ACLASS" = user ]; then
      VALID=1
    elif [ "$ACLASS" = lead ] && [ "$USER_ONLY" -eq 0 ] && [ "$ABY" != "$B" ] && lead_is "$ABY" && _lead_origin_match "$AVIA" "$AHOST" "$ABY"; then
      VALID=1
    fi
  fi
  # A valid approval is recorded with the merge even where none was needed.
  if [ "$VALID" -eq 1 ]; then
    _LMG_APPROVAL="${ACLASS}:${ABY} via=${AVIA:-?} host=${AHOST:-none} lead=${ALEAD:-?} at=${AAT:-?}"
    return 0
  fi
  if [ "$NEED" -eq 0 ] && [ "$USER_ONLY" -eq 0 ]; then
    return 0
  fi
  echo "lease_merge: REFUSED — ${T} needs a merge approval for its snapshot ${SNAP:0:12} (U10, rc ${_RC_PROMOTE_BLOCKED}); nothing merged, state stays review:" >&2
  if [ -n "$_LP_ERR" ]; then
    echo "  the protected-path scan could not run, so the diff counts as protected (fails closed): ${_LP_ERR}" >&2
  elif [ "$NEED" -eq 1 ]; then
    echo "  it touches protected paths, which need the lead or the user as cross-reviewer, never a worker-only review: ${_LP_PATHS}" >&2
  fi
  if [ -n "$WHY" ]; then echo "  ${WHY}" >&2; fi
  if [ -n "$ABY" ] && [ "$ASNAP" != "$SNAP" ]; then
    echo "  the approval on record (${RECORD}) is for an earlier snapshot: a fix cycle's collect voids it" >&2
  elif [ -n "$ABY" ]; then
    echo "  the approval on record (${RECORD}) does not count here: a lead-class approval needs the current lead's CLI, recorded from its own session or a terminal, one that did not build the task, and no stale lead pin" >&2
  fi
  if lead_is "$B"; then BLEAD=1; fi
  if [ "$USER_ONLY" -eq 1 ] || [ "$BLEAD" -eq 1 ]; then
    if [ "$BLEAD" -eq 1 ]; then echo "  ${T} was built by the lead's own CLI (${B}), so it routes to the user" >&2; fi
    echo "  Record the user's approval: lease_approve task:${T} user — then rerun lease_merge." >&2
  else
    echo "  Review it as the lead and record that: lease_approve task:${T} <the lead's CLI> — or the user's: lease_approve task:${T} user. Then rerun lease_merge." >&2
  fi
  return "$_RC_PROMOTE_BLOCKED"
}

# Distinct return code for "promotion is gated — the lead/user must approve"
# (lease_promote). Outside the invoke_* / timeout / resolve_role code space.
_RC_PROMOTE_BLOCKED=42

# Distinct return code for "review fix cycle hit the 3-cycle cap — escalated to
# the user" (lease_redispatch). Same reserved code space as the gates above.
_RC_LEASE_ESCALATED=43

# Degraded: the operation completed but its result could not be verified —
# lease_collect on a clean exit with NO final `Status:` report line (the lease
# stays `building`, never review-ready), and lease_heartbeat_check when a row
# lacks the pid/output it needs to judge liveness. Deliberately outside the
# resolve_role roster errors (2–6), the invoke_* / timeout codes (1, 124–127),
# and the gate codes (40–45, 96; 44 = _RC_LEASE_INTEGRITY, defined with the
# integrity check; 45 = _RC_LEAD_ONLY, defined in scripts/lib/common.sh).
_RC_DEGRADED=80

# _lease_is_framework_checkout <repo> <default-branch> — 0 when <repo> is the
# Triforge checkout, where framework_protected applies (KTD8). Reads
# .claude-plugin/plugin.json from the working tree, HEAD and the default
# branch: a diff that renames the plugin can't switch the framework list off,
# because the default branch still names agent-triforge. Fail closed: a
# manifest that exists but doesn't parse counts as the Triforge checkout.
_lease_is_framework_checkout() {
  local REPO=$1 DEF=${2:-} REV M
  M="${REPO}/.claude-plugin/plugin.json"
  [ -f "$M" ] && _lease_manifest_is_triforge < "$M" && return 0
  for REV in HEAD ${DEF:+"$DEF"}; do
    _lgr show "${REV}:.claude-plugin/plugin.json" 2>/dev/null | _lease_manifest_is_triforge && return 0
  done
  return 1
}

# _lease_manifest_is_triforge < manifest — 0 when stdin is a plugin manifest
# named agent-triforge OR is non-empty but not valid JSON (fail closed); 1 for
# an empty input or a manifest with another name.
_lease_manifest_is_triforge() {
  python3 -c '
import json, sys
raw = sys.stdin.read()
if not raw.strip():
    sys.exit(1)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)
sys.exit(0 if isinstance(data, dict) and data.get("name") == "agent-triforge" else 1)
'
}

# lease_promote [<default-branch>] — wave-end promotion of the sprint integration
# branch to the repo default branch (KTD-5). This is the ONLY path that writes the
# default branch; lease_merge only ever lands on the integration branch. Run it
# from the main tree checked out ON the integration branch (where lease_merge put
# the wave's squash commits), NOT on the default branch.
#
# Gate, in order:
#   (0) the integrity check (KTD18) and, when a ledger exists, the
#       integration-branch check: a moved default branch, planted git config
#       or hooks, a checkout switched off the recorded integration branch, or
#       an unrecorded commit on the integration branch refuses with rc 44
#       before anything else runs; a successful promotion clears the recorded
#       integration branch (the sprint is done)
#   (a) read [promotion].require_user_approval from ops/roster.toml (default false)
#   (b) compute the integration branch's changed paths vs the default branch:
#       git diff -z --name-only --no-renames --ignore-submodules=none
#       <default>...HEAD — both sides of every rename, NUL-separated so no
#       path is quoted out of a match, and a submodule entry (a nested repo
#       the snapshot recorded as a gitlink) listed even when .gitmodules on
#       the integration branch says `ignore = all`
#   (c) classify them against the registry's protected-path lists (KTD8,
#       scripts/lib/registry.sh): project_protected always, framework_protected
#       only in the Triforge checkout (_lease_is_framework_checkout). Case-
#       folded; instruction files match at any depth. A classifier or diff
#       error counts as a hit — the scan fails closed
#   (d) require_user_approval=true OR any protected path touched OR the scan
#       failed -> the gate is on: it passes only on the user's unvoided
#       promotion approval for exactly this state (_lease_promotion_check,
#       KTD4: recorded by lease_approve promotion:<branch> user, bound to the
#       integration tree, its protected-path set and the default branch's
#       commit; a later merge or a default-branch move voids it), printing
#       where it was recorded. Without one (or after a failed scan, which has
#       no set to bind to) -> BLOCK: say what is missing or void and name the
#       lease_approve call, return _RC_PROMOTE_BLOCKED, do NOT merge
#   (e) else fast-forward (or merge) the integration branch into the default
#       branch and report the promotion; an approval it used is marked used.
# Atomic where it matters: the default branch is never touched unless the gate
# passes — the block path leaves the tree exactly as it found it.
lease_promote() {
  _lead_only lease_promote || return $?
  local DEFAULT_BRANCH CURRENT_BRANCH INTEGRATION_BRANCH
  _lease_ctx || { echo "lease_promote: ERROR not inside a git repository" >&2; return 1; }
  # Promotion writes the default branch: only from a git state the lead
  # verified (KTD18) — a moved default branch, planted config or hooks, a
  # switched checkout, or an unrecorded commit on the integration branch
  # refuses here.
  _lead_integrity_check lease_promote || return $?
  DEFAULT_BRANCH=${1:-$(_lease_default_branch)}
  if [ -z "$DEFAULT_BRANCH" ]; then
    echo "lease_promote: ERROR could not determine the default branch (no origin/HEAD, no local main/master). Pass it explicitly: lease_promote <default-branch>." >&2
    return 1
  fi
  CURRENT_BRANCH=$(_lease_current_branch)
  if [ -z "$CURRENT_BRANCH" ]; then
    echo "lease_promote: ERROR the main tree is in detached HEAD — check out the sprint integration branch first." >&2
    return 1
  fi
  if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
    echo "lease_promote: ERROR the main tree is already on the default branch '${DEFAULT_BRANCH}' — nothing to promote. lease_promote runs from the sprint integration branch." >&2
    return 1
  fi
  INTEGRATION_BRANCH="$CURRENT_BRANCH"
  if [ -f "$_LEASE_LEDGER" ]; then
    _lead_integration_check lease_promote || return $?
  fi
  # A dirty index would ride into the promotion merge — refuse it.
  if ! _lgr diff --cached --quiet --no-ext-diff 2>/dev/null; then
    echo "lease_promote: ERROR the main tree index has staged changes — commit or unstage them before promoting." >&2
    return 1
  fi

  # (a) user-approval knob (default false; absent/unparseable roster -> false).
  local REQUIRE_APPROVAL="false"
  # The roster of the lead checkout, whatever the cwd: a relative path would
  # read no roster from a subdirectory and default the gate to off.
  if [ -f "${_LEASE_REPO}/ops/roster.toml" ]; then
    REQUIRE_APPROVAL=$(ROSTER_FILE="${_LEASE_REPO}/ops/roster.toml" python3 -c "
import os, sys
# Fail CLOSED: an existing roster that cannot be parsed (no TOML library, or a
# malformed file) must NOT silently disable the approval gate — that would let
# an unattended promotion land on the default branch despite a maintainer who
# configured require_user_approval=true. A misconfigured roster requires human
# approval. Only an ABSENT roster uses the documented false default, and that
# case never reaches this block (the enclosing -f test guards it).
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('true'); sys.exit(0)
try:
    with open(os.environ['ROSTER_FILE'], 'rb') as f:
        data = tomllib.load(f)
except Exception:
    print('true'); sys.exit(0)
p = data.get('promotion', {})
v = p.get('require_user_approval', False) if isinstance(p, dict) else False
print('true' if v is True else 'false')
" 2>/dev/null || echo "true")
  fi

  # (b) changed paths of the integration branch vs the default branch, both
  # sides of each rename (--no-renames), NUL-separated (-z) so core.quotePath
  # can't wrap a non-ASCII path in quotes that dodge a prefix match.
  if ! _lgr rev-parse --verify --quiet "${DEFAULT_BRANCH}^{commit}" >/dev/null 2>&1; then
    echo "lease_promote: ERROR '${DEFAULT_BRANCH}' is not a valid branch or commit — pass the default branch explicitly: lease_promote <default-branch>." >&2
    return 1
  fi
  # (c) protected-path scan (KTD8). A hit forces the gate ON regardless of the
  # knob. Fail closed: an unreadable plugin manifest counts as the Triforge
  # checkout, and any diff or classifier error blocks with its message.
  local APPROVED=""
  _lease_protected_scan "$DEFAULT_BRANCH" "${DEFAULT_BRANCH}...HEAD"

  # (d) gated: proceed only on the user's promotion approval for exactly this
  # state (KTD4), else block. A scan that could not run has no protected set
  # to bind an approval to, so it blocks whatever is on record.
  if [ "$REQUIRE_APPROVAL" = "true" ] || [ -n "$_LP_HITS" ] || [ -n "$_LP_ERR" ]; then
    if [ -z "$_LP_ERR" ] && _lease_promotion_check "$INTEGRATION_BRANCH" "$DEFAULT_BRANCH" "$_LP_HITS"; then
      APPROVED=$_LPC_ORIGIN
    else
      echo "lease_promote: BLOCKED — promotion of '${INTEGRATION_BRANCH}' to '${DEFAULT_BRANCH}' needs the user's approval. No merge performed." >&2
      if [ "$REQUIRE_APPROVAL" = "true" ]; then
        echo "  reason: [promotion].require_user_approval = true in ops/roster.toml (KTD-5 user gate)." >&2
      fi
      if [ -n "$_LP_ERR" ]; then
        echo "  reason: the protected-path scan could not run, so the diff is treated as protected (fail-closed, KTD8): ${_LP_ERR}" >&2
      fi
      if [ -n "$_LP_HITS" ]; then
        echo "  reason: the integration diff touches protected paths (controls that govern the pool; lists in scripts/lib/registry.sh — framework_protected applies in the Triforge checkout only). A protected-path diff forces the gate ON regardless of the knob; its tasks merged with a lead or user merge approval, and its promotion needs the user's:" >&2
        printf '%s\n' "$_LP_HITS" | while IFS="$(printf '\t')" read -r _pl _ph; do
          if [ -n "$_ph" ]; then echo "    ${_ph}  (${_pl}_protected)" >&2; fi
        done
      fi
      if [ -z "$_LP_ERR" ]; then
        echo "  approval: ${_LPC_WHY}" >&2
        echo "  Record the user's approval, bound to this tree, its protected paths and ${DEFAULT_BRANCH}'s commit: lease_approve promotion:${INTEGRATION_BRANCH} user — then rerun lease_promote. (Or, for a diff with no protected path, set [promotion].require_user_approval=false and rerun.)" >&2
      else
        echo "  Fix the scan, then record the user's approval: lease_approve promotion:${INTEGRATION_BRANCH} user — and rerun lease_promote." >&2
      fi
      return "$_RC_PROMOTE_BLOCKED"
    fi
  fi

  # (e) promote: fast-forward when possible, else a merge commit.
  if ! _lgr checkout -q "$DEFAULT_BRANCH" >&2; then
    echo "lease_promote: ERROR could not checkout the default branch '${DEFAULT_BRANCH}'." >&2
    return 1
  fi
  if _lgr merge -q --ff-only "$INTEGRATION_BRANCH" >&2; then
    :
  elif _lgr merge -q --no-edit "$INTEGRATION_BRANCH" >&2; then
    :
  else
    _lgr merge --abort 2>/dev/null || true
    _lgr checkout -q "$INTEGRATION_BRANCH" >&2 2>/dev/null || true
    echo "lease_promote: ERROR merging '${INTEGRATION_BRANCH}' into '${DEFAULT_BRANCH}' failed (conflicts) — aborted and returned to '${INTEGRATION_BRANCH}'. Resolve manually." >&2
    return 1
  fi
  local SHA
  SHA=$(_lgr rev-parse HEAD)
  # The lead's own promotion moves the default branch: record it, so the next
  # check compares against this state rather than escalating it (KTD18). The
  # record is the default branch as the check resolves it (_lease_default_ref),
  # not the argument, so an explicit <default-branch> that differs from
  # origin/HEAD or main/master can't leave a baseline the next check disagrees
  # with. That sprint's integration branch is done: clear it, and the next
  # lease_create (or merge) records the new one.
  # A promotion approval is used once: mark it consumed with the record.
  if [ -f "$_LEASE_LEDGER" ]; then
    _lease_default_ref
    _ledger_update @baseline default_branch="$_LEASE_DEF" default_sha="$_LEASE_DEF_SHA" integration_branch="" integration_sha="" \
      ${APPROVED:+"promotion_voided=$(date -u +%Y-%m-%dT%H:%M:%SZ) used by lease_promote (${SHA:0:12})"} >/dev/null || true
  fi
  if [ -n "$APPROVED" ]; then
    echo "lease_promote: PROMOTED '${INTEGRATION_BRANCH}' -> '${DEFAULT_BRANCH}' (HEAD ${SHA}); require_user_approval=${REQUIRE_APPROVAL}, protected-paths=${_LP_COUNT}, on the approval above." >&2
  else
    echo "lease_promote: PROMOTED '${INTEGRATION_BRANCH}' -> '${DEFAULT_BRANCH}' (HEAD ${SHA}); require_user_approval=${REQUIRE_APPROVAL}, protected-paths=none." >&2
  fi
  return 0
}

# _lease_protected_digest <hits> — the sha256 of the sorted, distinct paths in
# <hits> (_lease_protected_scan's "<list><TAB><path>" lines): the
# protected-path set a promotion approval binds to (no path hashes as the
# empty set).
_lease_protected_digest() {
  printf '%s\n' "${1:-}" | python3 -c '
import hashlib, sys
paths = sorted(set(l.split("\t", 1)[-1] for l in sys.stdin.read().splitlines() if l.strip()))
print(hashlib.sha256("\n".join(paths).encode("utf-8", "surrogateescape")).hexdigest())
'
}

# _lease_promotion_check <integration-branch> <default-branch> <protected hits>
# — 0 when [baseline] holds the user's unvoided promotion approval for exactly
# this state (KTD4): scope promotion:<branch>, class user, the integration
# tree (HEAD^{tree}, lease_promote runs from that branch), the default branch
# and its commit, and the protected-path set (_lease_protected_digest of the
# hits). Then _LPC_ORIGIN says where it was recorded and the approval line and
# the disclosure are printed; otherwise _LPC_WHY says what is missing or void.
_lease_promotion_check() {
  local IB=$1 DEF=$2 ROW SCOPE CLASS VOIDED TREE PDEF PDSHA PDIG VIA HOST LEAD AT NOWTREE NOWDSHA
  _LPC_WHY=""; _LPC_ORIGIN=""
  ROW=$(_ledger_get_row @baseline promotion_scope promotion_class promotion_voided promotion_tree promotion_default promotion_default_sha promotion_protected promotion_via promotion_host promotion_lead_cli promotion_at 2>/dev/null) || ROW=""
  { IFS= read -r SCOPE || true; IFS= read -r CLASS || true; IFS= read -r VOIDED || true; IFS= read -r TREE || true
    IFS= read -r PDEF || true; IFS= read -r PDSHA || true; IFS= read -r PDIG || true; IFS= read -r VIA || true
    IFS= read -r HOST || true; IFS= read -r LEAD || true; IFS= read -r AT || true; } <<PROMOTION_ROW_EOF
${ROW}
PROMOTION_ROW_EOF
  NOWTREE=$(_lgr rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null || true)
  NOWDSHA=$(_lgr rev-parse --verify --quiet "${DEF}^{commit}" 2>/dev/null || true)
  if [ -z "$SCOPE" ]; then
    _LPC_WHY="none on record"
  elif [ "$SCOPE" != "promotion:${IB}" ]; then
    _LPC_WHY="the one on record is for ${SCOPE}, not promotion:${IB}"
  elif [ -n "$VOIDED" ]; then
    _LPC_WHY="the one on record (recorded ${AT:-?}, via=${VIA:-?}) is void: ${VOIDED}"
  elif [ "$CLASS" != user ]; then
    _LPC_WHY="the one on record is class '${CLASS}'; a promotion approval is the user's alone"
  elif [ "$PDEF" != "$DEF" ]; then
    _LPC_WHY="the one on record is void: it approved a promotion into ${PDEF}, not ${DEF}"
  elif [ "$PDSHA" != "$NOWDSHA" ]; then
    _LPC_WHY="the one on record is void: the default branch ${DEF} moved ${PDSHA:0:12} -> ${NOWDSHA:0:12} since it was recorded"
  elif [ "$TREE" != "$NOWTREE" ]; then
    _LPC_WHY="the one on record is void: ${IB}'s tree changed since it was recorded (${TREE:0:12} -> ${NOWTREE:0:12})"
  elif [ "$PDIG" != "$(_lease_protected_digest "$3")" ]; then
    _LPC_WHY="the one on record is void: the protected-path set changed since it was recorded"
  else
    _LPC_ORIGIN="via=${VIA:-?} host=${HOST:-none} lead=${LEAD:-?} at=${AT:-?}"
    echo "lease_promote: approved by the user for promotion:${IB} (tree ${TREE:0:12}, ${DEF} at ${PDSHA:0:12}), recorded ${_LPC_ORIGIN}" >&2
    echo "  Audit, not prevention: the record says where lease_approve ran. Any shell with the helper can record a user approval, a lead's agent shell included (that one says via=lead-session); via=tty only says a terminal was attached." >&2
    return 0
  fi
  return 1
}

# lease_status — human table of the ledger for at-status and at-resume
# orientation: task, builder, model, state, the lead's CLI at create (LEAD; a
# row from before 4.0 reads as _LEAD_LEGACY_CLI), the pinned reviewer and its
# class, whether the snapshot touches a protected path (PROT: yes, no, ? when
# the scan failed, - before collect) and the merge approval (APPROVAL:
# <class>:<by>/<via> for the current snapshot, void for an earlier one, needed
# when a protected snapshot in review has none, else -), and age (U10).
# Tolerant: reports a missing or unparseable ledger instead of failing.
lease_status() {
  local LEDGER
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  if [ ! -f "$LEDGER" ]; then
    echo "lease_status: no lease ledger (${LEDGER}) — no leases have been created"
    return 0
  fi
  LEDGER_FILE="$LEDGER" LS_LEGACY_LEAD="$_LEAD_LEGACY_CLI" python3 -c "
import os, sys, time
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.stderr.write('lease_status: ERROR no TOML parser available\n')
        sys.exit(1)
try:
    with open(os.environ['LEDGER_FILE'], 'rb') as f:
        data = tomllib.load(f)
except Exception as exc:
    sys.stderr.write('lease_status: ERROR ledger unparseable: ' + str(exc) + '\n')
    sys.exit(1)
leases = data.get('lease', {})
now = int(time.time())
counts = {}
rows = [('TASK', 'BUILDER', 'MODEL', 'STATE', 'LEAD', 'REVIEWER', 'PROT', 'APPROVAL', 'AGE')]
def g(r, k):
    return str(r.get(k, '') or '')
for t in sorted(leases if isinstance(leases, dict) else {}):
    r = leases[t]
    if not isinstance(r, dict):
        continue
    state = str(r.get('state', '?'))
    counts[state] = counts.get(state, 0) + 1
    try:
        age = max(0, now - int(r.get('updated') or now))
    except (TypeError, ValueError):
        age = 0
    if age >= 3600:
        age_s = str(age // 3600) + 'h' + str((age % 3600) // 60) + 'm'
    elif age >= 60:
        age_s = str(age // 60) + 'm' + str(age % 60) + 's'
    else:
        age_s = str(age) + 's'
    pinned = g(r, 'reviewer') or g(r, 'pinned_reviewer')
    reviewer = (pinned + '/' + (g(r, 'reviewer_class') or '?')) if pinned else '-'
    prot = {'yes': 'yes', 'no': 'no', 'unknown': '?'}.get(g(r, 'protected'), '-')
    if state == 'merged':
        approval = g(r, 'merge_approval').split(' ')[0] or '-'
        approval = '-' if approval == 'none' else approval
    elif g(r, 'approval_by') and g(r, 'approval_snapshot') == g(r, 'snapshot_sha'):
        approval = g(r, 'approval_class') + ':' + g(r, 'approval_by') + '/' + (g(r, 'approval_via') or '?')
    elif g(r, 'approval_by'):
        approval = 'void'
    elif state == 'review' and prot in ('yes', '?'):
        approval = 'needed'
    else:
        approval = '-'
    rows.append((str(t), str(r.get('builder_cli', '?')),
                 str(r.get('builder_model', '') or '-'), state,
                 g(r, 'lead_cli') or os.environ.get('LS_LEGACY_LEAD', ''), reviewer, prot, approval, age_s))
if len(rows) == 1:
    print('lease_status: ledger is empty')
    sys.exit(0)
widths = [max(len(r[i]) for r in rows) for i in range(len(rows[0]))]
for r in rows:
    print('  '.join(r[i].ljust(widths[i]) for i in range(len(r))).rstrip())
print('')
print('states: ' + ', '.join(k + '=' + str(v) for k, v in sorted(counts.items())))
"
}
