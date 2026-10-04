#!/usr/bin/env bash
# scripts/lib/lease.sh — the lease lifecycle (KTD-4): ledger, per-adapter env allowlist (+ no-push backstop, worker marker), lease_create/dispatch/collect/merge/promote, detached builders + lease_wait + the lead-exit reconcile (KTD10), the typed-report parser (KTD11)
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh. Every function keeps the name and
# contract it had when this code lived in invoke-external.sh; the split (review
# finding #15 on the v3.3.0 branch) is by lane, not by behavior.
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
# birth, which is what lets lease_reclaim compare stored vs canonical.
_lease_ctx() {
  local KEY="${PWD}|${TRIFORGE_LEASE_ROOT:-}|${TMPDIR:-}"
  if [ "${_LEASE_CTX_KEY:-}" = "$KEY" ] && [ -n "${_LEAD_CFG:-}" ] && [ -f "${_LEAD_CFG}" ]; then
    return 0
  fi
  local OUT
  OUT=$(LC_ROOT="${TRIFORGE_LEASE_ROOT:-}" LC_TMP="${TMPDIR:-/tmp}" python3 -c '
import hashlib, os, sys
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
if not root:
    b = repo.encode("utf-8", "surrogateescape")
    h = hashlib.sha1(b"blob " + str(len(b)).encode() + b"\0" + b).hexdigest()[:12]
    root = os.path.join(os.environ.get("LC_TMP") or "/tmp", "triforge-leases", os.path.basename(repo) + "-" + h)
os.makedirs(os.path.join(root, "lead"), exist_ok=True)
for p in (repo, os.path.realpath(gitdir), os.path.realpath(common), os.path.realpath(root)):
    print(p)
' 2>/dev/null) || { echo "lease: ERROR not inside a git repository — worktree leases require one (outside git the builder pool degrades to lead-only in-place execution)." >&2; return 1; }
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
# _lease_root_above recognizes a lease root (KTD9): keep it.
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
# lease_* entry points' own refusal.
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
  LEDGER_FILE="$LEDGER" LEDGER_TASK="$TASK_ID" LEDGER_STATE="$_LEASE_STATE" python3 -c "
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
# fails closed; any alert, update or missing anchor still writes.
if (task == '@baseline' and len(sys.argv) == 1 and not alert and recorded and isinstance(data.get('baseline'), dict)
        and os.path.isfile(copy_file) and _sha(copy_file) == recorded):
    sys.exit(0)
leases = data.get('lease', {})
leases = leases if isinstance(leases, dict) else {}
baseline = data.get('baseline', {})
baseline = dict(baseline) if isinstance(baseline, dict) else {}
if alert:
    baseline['ledger_alert'] = alert
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
import hashlib, os, shutil, stat, sys, time
try:
    import tomllib
except ImportError:
    import tomli as tomllib

def _sha(b):
    return hashlib.sha256(b).hexdigest()

def file_digest(p):
    try:
        if os.path.islink(p):
            return "link:" + os.readlink(p)
        if os.path.isdir(p):
            return "dir:" + tree_digest(p)
        with open(p, "rb") as f:
            return _sha(f.read())
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
                    with open(full, "rb") as f:
                        entries.append((rel, "F%o" % (st.st_mode & 0o111), _sha(f.read())))
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
        with open(p, "rb") as f:
            return _sha(f.read())
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
           "lead_gitconfig": file_digest(os.path.join(state, "gitconfig"))}
    if repo:
        cur["checkout"] = checkout_digest(repo)
    return cur

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
        line = open(os.path.join(wt, ".git"), encoding="utf-8").read().strip()
    except OSError:
        return ""
    if not line.startswith("gitdir:"):
        return ""
    admin = os.path.realpath(os.path.join(wt, line[len("gitdir:"):].strip()))
    return admin if os.path.dirname(admin) == os.path.realpath(os.path.join(common, "worktrees")) else ""

if mode == "record":
    save_copies()
    for k, v in sorted(repo_surfaces(common, state, repo, gitdir).items()):
        print(k + "=" + v)
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
# after escalating it, so a rebaseline can't accept a ledger change.
_lead_baseline_record() {
  local L
  local -a ARGS=()
  _lease_ctx || return 1
  _lease_default_ref
  while IFS= read -r L; do
    if [ -n "$L" ]; then ARGS+=("$L"); fi
  done <<BASELINE_EOF
$(LI_MODE=record LI_COMMON="$_LEASE_COMMON" LI_GITDIR="$_LEASE_GITDIR" LI_STATE="$_LEASE_STATE" LI_REPO="$_LEASE_REPO" python3 -c "$_LEAD_INTEGRITY_PY")
BASELINE_EOF
  # config, config_worktree, hooks, info, global_gitconfig, lead_gitconfig, checkout.
  if [ "${#ARGS[@]}" -lt 7 ]; then
    echo "lease: ERROR could not record the integrity baseline (KTD18)" >&2
    return 1
  fi
  _ledger_update @baseline "${ARGS[@]}" default_branch="$_LEASE_DEF" default_sha="$_LEASE_DEF_SHA" \
    recorded_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

# _lead_lease_digests <worktree> [admin-dir] — "<pointer-digest>\t<admin-digest>\t<admin-dir>"
# for a lease worktree (the admin dir is derived from the pointer when not given
# — only right after the lead itself created the worktree).
_lead_lease_digests() {
  _lease_ctx || return 1
  LI_MODE=lease LI_COMMON="$_LEASE_COMMON" LI_WT="$1" LI_ADMIN="${2:-}" python3 -c "$_LEAD_INTEGRITY_PY"
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
      echo "${OP}: INTEGRITY — ${LEDGER} and its digest are gone, but the lead state dir ${_LEASE_STATE} holds copies saved for earlier leases: the ledger was deleted outside the lead's writes (KTD18; detection, not prevention). Nothing was merged or promoted. Inspect; to recover, copy ${_LEASE_STATE}/ledger.copy back to ${LEDGER} and run lease_rebaseline — or, if you removed the ledger on purpose, remove ${_LEASE_STATE} too." >&2
      return "$_RC_LEASE_INTEGRITY"
    fi
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
  if [ "$LU_RC" -ne 0 ]; then
    echo "${OP}: INTEGRITY CHECK COULD NOT RUN — the ledger could not be verified under its lock; treated as a change (fail closed, KTD18): $(printf '%s' "$LU_ERR" | tail -3 | tr '\n' ' ' | cut -c1-300)" >&2
    return "$_RC_LEASE_INTEGRITY"
  fi
  _lease_default_ref
  OUT=$(LI_MODE=check LI_RESTORE=1 LI_COMMON="$_LEASE_COMMON" LI_GITDIR="$_LEASE_GITDIR" LI_STATE="$_LEASE_STATE" LI_REPO="$_LEASE_REPO" LI_LEDGER="$LEDGER" \
        LI_DEF="$_LEASE_DEF" LI_DEF_SHA="$_LEASE_DEF_SHA" python3 -c "$_LEAD_INTEGRITY_PY" 2>&1) || RC=$?
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
# gets the base allowlist alone. env -i execs external commands only; shell
# functions cannot cross it, which is why lease_dispatch composes direct CLI
# commands instead of calling the invoke_* helpers (see there). Mirrored by
# _lane_run in scripts/probe-capabilities.sh, which reads the same base list.
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

# _lease_provision <worktree> — provision a worktree _lease_carve just made
# (it reads _CARVE_ADMIN) and append provisioned=<the paths that wrote> to
# _CARVE_FIELDS, the lease row's `provisioned` field (KTD9). rc 1 when the
# list can't be read: a row without it would fall back to excluding all of
# .agents/.
_lease_provision() {
  local WT=$1 LIST
  _lease_provision_skills "$WT"
  LIST=$(_lease_provisioned "$WT" "$_CARVE_ADMIN" .agents/skills) || {
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
# cleared snapshot/integrity fields; _lease_provision then appends
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
                 integration_branch="$CUR" lease_root="$_LEASE_ROOT" snapshot_sha= snapshot_tree= builder_commits= integrity_prev_state=)
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

# _lease_snapshot <task_id> — the lead's collect-time snapshot (KTD3): the
# builder's worktree as ONE lead-made commit on top of the recorded base,
# written to lease/<task> and recorded (snapshot_sha, snapshot_tree) so the
# review, the merge and any later approval bind to exactly this state. Each
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
  _ledger_update "$T" snapshot_sha="$SNAP" snapshot_tree="$TREE" base_sha="$BASE" builder_commits="$BC" || return 1
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
# row. Echoes task_id on success so callers can chain.
lease_create() {
  _lead_only lease_create || return $?
  local TASK_ID=${1:?usage: lease_create <task_id> <role>}
  local ROLE=${2:?usage: lease_create <task_id> <role>}
  if ! _lease_valid_task_id "$TASK_ID"; then
    echo "lease_create: ERROR invalid task id '${TASK_ID}' — want [A-Za-z0-9][A-Za-z0-9._-]* (it becomes a branch and directory name)" >&2
    return 1
  fi
  local RESOLVED CLI MODEL EFFORT WT NOW CUR IB="" ISHA="" ROW
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
  _lease_carve "$TASK_ID" "$WT" || return 1
  _lease_provision "$WT" || return 1
  NOW=$(date +%s)
  _ledger_update "$TASK_ID" \
    task_id="$TASK_ID" role="$ROLE" \
    builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    state=leased worktree="$WT" branch="lease/${TASK_ID}" \
    pid=0 output_file="" created="$NOW" heartbeat_deadline=0 \
    requeue_count=0 review_cycle=0 pinned_reviewer="" previous_builder="" reviewer="" merge_commit="" reason="" \
    "${_CARVE_FIELDS[@]}" \
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
# pid_started (the leader's ps start time, whitespace-collapsed), so a pid the
# OS later gave to another process is never taken for the builder and never
# signalled; and lead_pid / lead_started, the lead process that dispatched it
# (_lease_lead_proc). The lead waits with lease_wait, the one waiting
# primitive; lease_heartbeat_check is the resume sweep. Both reconcile each
# building lease through _lease_sweep_one: a live builder keeps building; a
# finished one is collected; a dead one without an exit record takes the
# orphan path. When the recorded lead process is gone (it exited, was killed,
# or a forced handover says so), a live builder is adopted by the current lead
# and a finished one is collected normally, both with reason=lead-exit and
# lead_exit_at, and requeue_count untouched (R38).

# lease_wait's rc when its budget ran out with a watched lease still building
# (EX_TEMPFAIL: call it again).
_RC_WAIT_BUILDING=75

# The field separator of _LEASE_WAIT_PY's lines (ASCII unit separator).
_LEASE_US=$'\037'

# _LEASE_LAUNCH_PY <log> <argv...> — start argv in a new session with stdin
# /dev/null and stdout/stderr appended to <log>, and print
# "<pid>\t<pgid>\t<start time>". The child holds at a pipe (fd _TRIFORGE_GO_FD,
# read by _LEASE_BUILDER_SH) until its pgid and start time are read, so the
# recorded fingerprint is the live process's own even for a builder that
# finishes at once; when the launcher fails or dies first, the pipe closes
# unreleased and the child exits without running anything. The probe's
# survival rows (CC-09, CC-10, CDX-12, CDX-13) read it through the loader and
# start their test builder with it, so they test this launcher.
_LEASE_LAUNCH_PY='
import os, subprocess, sys
log, argv = sys.argv[1], sys.argv[2:]
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
try:
    info = subprocess.run(["ps", "-o", "pgid=,lstart=", "-p", str(p.pid)], capture_output=True, text=True).stdout.split()
except OSError:
    info = []
if len(info) < 2 or info[0] != str(p.pid):
    os.close(w)
    sys.stderr.write("lease_dispatch: the builder process " + str(p.pid) + " is not a session leader with a readable start time (ps: " + " ".join(info) + "); it was not released\n")
    sys.exit(1)
os.write(w, b"go\n")
os.close(w)
print(str(p.pid) + "\t" + info[0] + "\t" + " ".join(info[1:]))
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
# pid runs (not a zombie) with the recorded start time (whitespace-collapsed,
# as ps -o lstart= prints it) and, when one is given, the recorded process
# group; "reused" when the pid runs as a different process; "gone" otherwise.
# An empty recorded start (a row from before 3.3.3) is the plain liveness test;
# the 3.3.3 marker "exited-before-record" never matches. One awk reads ps and
# collapses the recorded start too (through ENVIRON), printed as the last
# field: the only one that can be empty, so the tab split keeps the others.
_lease_proc_state() {
  local P=${1:-} S=${2:-} G=${3:-} INFO="" ST="" NG="" NS="" TAB
  TAB=$(printf '\t')
  case "$P" in ''|0|*[!0-9]*) printf 'gone\n'; return 0 ;; esac
  INFO=$(ps -o stat=,pgid=,lstart= -p "$P" 2>/dev/null | PS_START="$S" awk 'NF >= 3 {
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
# its start time (0 and "" when the start time can't be read): the process
# whose exit the lead-exit reconcile detects. TRIFORGE_LEAD_PID when set (a
# test, or a harness that knows its lead), else the parent of the current
# process group's leader, else this shell ($$, passed in: inside the $(...)
# below, python3's own parent is a subshell that is gone once it returns). A
# lead's shell tool starts each call as a group leader whose parent is the lead
# CLI (Claude Code on the reference host; U14 verifies the Codex lead); a
# by-hand terminal session resolves to the terminal's shell. Call it directly,
# never in $(...), so the two globals land in the caller's shell.
_lease_lead_proc() {
  local OUT TAB
  TAB=$(printf '\t')
  _LEAD_PID=0
  _LEAD_STARTED=""
  OUT=$(LP_SHELL=$$ python3 -c '
import os, subprocess, sys
def ps(field, pid):
    try:
        return subprocess.run(["ps", "-o", field + "=", "-p", str(pid)], capture_output=True, text=True).stdout.split()
    except OSError:
        return []
pid = os.environ.get("TRIFORGE_LEAD_PID", "")
if not pid.isdigit() or int(pid) <= 0:
    up = ps("ppid", os.getpgid(0))
    pid = up[0] if up and up[0].isdigit() else os.environ.get("LP_SHELL", "")
start = " ".join(ps("lstart", pid)) if pid.isdigit() else ""
if not start:
    sys.exit(1)
print(pid + "\t" + start)
' 2>/dev/null) || OUT=""
  { IFS="$TAB" read -r _LEAD_PID _LEAD_STARTED || true; } <<LEAD_PROC_EOF
${OUT}
LEAD_PROC_EOF
  case "$_LEAD_PID" in ''|*[!0-9]*) _LEAD_PID=0; _LEAD_STARTED="" ;; esac
}

# _lease_kill_builder <pid> <pgid> <recorded start> [term] — TERM a builder's
# process group, then KILL it a second later ("term": TERM only), and only
# while its leader still answers as the recorded process (_lease_proc_state
# alive): a reused pid is never signalled. The KILL goes out unless the pid
# answers as another process by then (the members left keep the group id
# reserved). A row from before KTD10 (no pgid: an undetached subshell) keeps
# the old rule, the pid's own process tree.
_lease_kill_builder() {
  local P=$1 G=${2:-} S=${3:-} MODE=${4:-}
  case "$G" in ''|0|*[!0-9]*) G="" ;; esac
  if [ "$(_lease_proc_state "$P" "$S" "$G")" != alive ]; then return 0; fi
  if [ -z "$G" ]; then
    _kill_tree "$P" TERM
    if [ "$MODE" != term ]; then sleep 1; _kill_tree "$P" KILL; fi
    return 0
  fi
  kill -TERM -- "-${G}" 2>/dev/null || true
  if [ "$MODE" = term ]; then return 0; fi
  sleep 1
  if [ "$(_lease_proc_state "$P" "$S" "$G")" = reused ]; then return 0; fi
  kill -KILL -- "-${G}" 2>/dev/null || true
  return 0
}

# _lease_codex_lane_flags — set _LEASE_CODEX_FLAGS to the codex lane's argv
# after `codex` (model and effort follow): exec in the workspace-write sandbox
# with approval never, plus two sandbox_workspace_write excludes that drop
# codex's default temp-dir write allowance: lease worktrees live under TMPDIR,
# so without them a builder could cross into sibling worktrees or the lease
# root (R35: writes restricted to the lease worktree). The probe's CDX-16 and
# CDX-17 rows and SELF-15c read this list through the loader, so they run the
# exact lane flags.
_lease_codex_lane_flags() {
  _LEASE_CODEX_FLAGS=(exec -s workspace-write -c 'approval_policy="never"'
                      -c 'sandbox_workspace_write.exclude_tmpdir_env_var=true'
                      -c 'sandbox_workspace_write.exclude_slash_tmp=true')
}

# _lease_builder_run <cli> <model> <effort> <dispatch-model> <kimi-agent-file>
#   <cursor-bin> <timeout-bin> <timeout-s> <out> <worktree> <env-keys>
#   <test-builder> <prompt>
# The detached builder's body: from the worktree, the lane command for <cli>
# under _adapter_env (or the TRIFORGE_TEST_BUILDER script <test-builder>),
# output in <out>; then the sweep of its own process group
# (_LEASE_OWN_GROUP_PY) and the exit record: <out>.class, then <out>.rc, the
# file the lead waits for. It runs only in the process _LEASE_LAUNCH_PY
# started, never in the lead's shell, and never writes the ledger (KTD-4).
# The invoke_* helpers are shell functions and can't cross env -i, so each
# lane composes the adapter's command core directly: codex = exec +
# workspace-write + approval never + stdin guard (_lease_codex_lane_flags;
# codex's own sandbox then scopes writes to the worktree cwd); antigravity =
# model pin + --add-dir + --print-timeout; claude = -p --permission-mode
# acceptEdits (cwd IS the worktree, no --add-dir needed); opencode, kimi and
# cursor as their arms below say.
_lease_builder_run() {
  local CLI=$1 MODEL=$2 EFFORT=$3 DISPATCH_MODEL=$4 KIMI_AGENT_FILE=$5 CBIN=$6 TOBIN=$7 TIMEOUT=$8 OUT=$9
  local WT=${10} TEST_BUILDER=${12} FULL_PROMPT=${13} RC=0 CLASS_SET=0 AGY_PRC=0
  local -a TO CMD
  _ADAPTER_ENV_KEYS=${11}   # the registry read lease_dispatch did; _adapter_env reads none
  cd "$WT" || return 97
  # --foreground keeps the builder's whole tree in this process group (GNU
  # timeout otherwise moves into a group of its own), so the lead's kill of the
  # group and the sweep below reach every process it started; the children
  # timeout itself leaves running at expiry are the sweep's.
  TO=("$TOBIN" --foreground "${TIMEOUT}s")
  if [ -n "$TEST_BUILDER" ]; then
    # Test seam (see lease_dispatch): deterministic fake builder.
    _adapter_env "$CLI" "${TO[@]}" "$TEST_BUILDER" "$FULL_PROMPT" > "$OUT" 2>&1 || RC=$?
  else
    case "$CLI" in
      claude)
        CMD=(claude -p --permission-mode acceptEdits)
        if [ -n "$MODEL" ]; then CMD+=(--model "$MODEL"); fi
        _adapter_env claude "${TO[@]}" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        ;;
      codex)
        # Mirrors invoke_codex's retry-safe core (sandbox, approval, model
        # pin, stdin guard) — see the env -i note in the function comment.
        _lease_codex_lane_flags
        CMD=(codex "${_LEASE_CODEX_FLAGS[@]}")
        if [ -n "$MODEL" ]; then CMD+=(-m "$MODEL"); fi
        if [ -n "$EFFORT" ]; then CMD+=(-c "model_reasoning_effort=\"${EFFORT}\""); fi
        _adapter_env codex "${TO[@]}" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        ;;
      antigravity)
        # JSON envelope (KTD2, D-032): exit 0 is not a completion signal on
        # agy >= 1.1.20 — parse status/response/denied_actions instead. The
        # prose lands in $OUT (what lease_collect prints), the streams in
        # $OUT.raw / $OUT.err, the verdict in $OUT.status / $OUT.denied.
        _adapter_env antigravity "${TO[@]}" agy --model "$DISPATCH_MODEL" --add-dir "$WT" --print-timeout "${TIMEOUT}s" --output-format json -p "$FULL_PROMPT" < /dev/null > "${OUT}.raw" 2> "${OUT}.err" || RC=$?
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
        # R35-confined optional-tier builder (U11): raw `opencode run` with
        # cwd = the worktree, under _adapter_env opencode — which allowlists
        # ONLY OPENROUTER_API_KEY (KTD-14), so no cross-provider credential
        # leak. No --auto (OC-06: denies do not survive it) and no
        # invoke_opencode (a shell function cannot cross env -i); the
        # confinement contract rides in FULL_PROMPT like every other lane.
        # Shipped default (DISPATCH_MODEL, from the registry when the roster
        # carries no pin) is the OpenRouter GLM, so a live build AUTH-FAILs
        # until the provider is connected — that failure is deterministic and
        # the lead sees it via <out>.class (no requeue). Effort -> --variant
        # (OC-05 best-effort), guarded on a non-empty effort exactly like the
        # codex case guards model_reasoning_effort. The lease path has no
        # retry, so a provider that rejects the variant surfaces as a
        # KTD-9-classified failure the lead requeues — same as any other lane.
        # OpenCode V2 guard (D-049): V2 ignores OPENCODE_PERMISSION and runs
        # a shared background service outside env -i, so a V2 binary (or one
        # whose version can't be read — fail-closed) never dispatches —
        # deterministic refusal naming the V1 pin, recorded in <out>.class
        # like the agy denied-actions arm (no requeue).
        if ! _opencode_v2_check opencode; then
          _opencode_v2_refusal lease_dispatch > "$OUT"
          RC=1; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1
        else
          CMD=(opencode run --format json -m "$DISPATCH_MODEL")
          if [ -n "$EFFORT" ]; then CMD+=(--variant "$EFFORT"); fi
          _adapter_env opencode "${TO[@]}" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        fi
        ;;
      kimi)
        # R35-confined optional-tier builder (U12): raw `kimi -p` with cwd =
        # the worktree, under _adapter_env kimi — which allowlists ONLY KIMI_*
        # (KTD-14), so no cross-provider credential leak. Telemetry off (R25)
        # via the inner `env`. Kimi has no per-tool sandbox flag and -p uses
        # the auto policy, so confinement is the worktree + env allowlist; the
        # role brief rides in FULL_PROMPT (injection — KIMI-03 has no --agent,
        # so no invoke_kimi either: a shell function cannot cross env -i).
        # Shipped default (DISPATCH_MODEL, from the registry when the roster
        # carries no pin) is kimi-code/k3 (the OAuth-managed alias, D-024), so
        # a live build AUTH-FAILs until kimi is signed in — that failure is
        # deterministic and the lead sees it via <out>.class (no requeue). The
        # builder definition rides as --agent-file with the ABSOLUTE plugin
        # path composed by the lead shell (KIMI_AGENT_FILE) so it survives
        # env -i; no --skills-dir (it would replace Kimi's native
        # .agents/skills discovery — KIMI-04). -p LAST (commander.js consumes
        # the next token as -p's value; see the invoke_kimi note) — prompt
        # right after -p.
        CMD=(kimi --output-format stream-json -m "$DISPATCH_MODEL")
        if [ -n "$KIMI_AGENT_FILE" ]; then CMD+=(--agent-file "$KIMI_AGENT_FILE"); fi
        _adapter_env kimi "${TO[@]}" env KIMI_DISABLE_TELEMETRY=1 "${CMD[@]}" -p "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        ;;
      cursor)
        # R35-confined optional-tier builder (U13): raw `cursor-agent -p` with
        # cwd = the worktree, under _adapter_env cursor — which allowlists ONLY
        # CURSOR_API_KEY (KTD-14), so no cross-provider credential leak.
        # --trust bypasses the workspace-trust prompt (mandatory headless,
        # CUR-04); --force applies edits without confirmation (builder role,
        # inside the worktree). Model pinned to the suffixed id composed by
        # _cursor_model_for_effort from the roster model + effort (D-025;
        # default cursor-grok-4.6-xhigh), NEVER Auto (ledger attribution needs
        # a named model). Binary resolved lead-side by _cursor_bin (CBIN —
        # cursor-agent first, verified `agent` fallback) and exec'd by
        # absolute path inside env -i. Confinement is the worktree + env
        # allowlist, NOT --sandbox (CUR-07: --sandbox enabled did not confine
        # — an absolute-path write escaped). -p is a BOOLEAN flag (unlike
        # kimi's -p); the prompt is the TRAILING POSITIONAL (verified live
        # 2026-07-18), so it comes LAST. No invoke_cursor (a shell function
        # cannot cross env -i; the role brief rides in FULL_PROMPT via
        # injection — cursor has no headless --agent selector). A live build
        # AUTH-FAILs until cursor-agent is logged in — that failure is
        # deterministic and the lead sees it via <out>.class.
        CMD=("$CBIN" -p --output-format stream-json --model "$DISPATCH_MODEL" --trust --force)
        _adapter_env cursor "${TO[@]}" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
        ;;
      *)
        echo "lease_dispatch: ERROR builder CLI '${CLI}' has no dispatch arm here — not integrated. Registered CLIs: $(_known_clis '<registry unreadable>')." > "$OUT"
        RC=95
        ;;
    esac
  fi
  python3 -c "$_LEASE_OWN_GROUP_PY" 2>/dev/null || true
  # Only a nonzero exit has a failure class (matches invoke_antigravity /
  # invoke_codex): a clean run is class=none, so lease_collect never reads a
  # spurious 'retryable' off a builder that actually succeeded.
  if [ "$RC" -eq 0 ]; then
    INVOKE_FAILURE_CLASS="none"
    # The opencode / kimi / cursor lanes answer as a JSON event stream; the
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

# lease_dispatch <task_id> <prompt> [timeout-seconds]
#
# Composes the FULL dispatch prompt: injected context header (KTD-3 — the
# lease's roster line plus the explicit confinement contract) + the
# lead-provided task prompt (which carries the task row text and any
# CONTRACTS.md slice — the builder never reads canonical ops/).
#
# The builder runs DETACHED (KTD10): _LEASE_LAUNCH_PY starts it in its own
# session and process group, and _lease_builder_run runs the lane command from
# the worktree under _adapter_env's per-CLI allowlist (KTD-14), so the worker
# marker and the no-push backstop reach it as before (its header sums up the
# lane commands). Exit code and KTD-9 class land in <out>.rc / <out>.class,
# the builder process's own diagnostics in <out>.log, for the single-writer
# lead to collect — the builder process never touches the ledger. The row records
# state=building, pid, pgid, pid_started, lead_pid, lead_started, output_file
# and heartbeat_deadline; lease_wait waits on it. Variables the lanes read from
# the environment (a CLI's credential keys, OPENCODE_PERMISSION) must be
# exported: the builder process inherits the lead's environment, not its shell.
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
  local ROW
  ROW=$(_ledger_get_row "$TASK_ID" builder_cli builder_model builder_effort role worktree) || ROW=""
  { IFS= read -r CLI || true; IFS= read -r MODEL || true; IFS= read -r EFFORT || true
    IFS= read -r ROLE || true; IFS= read -r WT || true; } <<DISPATCH_ROW_EOF
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

  rm -f "$OUT" "${OUT}.rc" "${OUT}.class" "${OUT}.log"

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
  _ledger_update "$TASK_ID" dispatched_model="$DISPATCH_MODEL" || return 1

  # Detached launch (KTD10): the builder process is a fresh bash that sources
  # this loader and runs _lease_builder_run with the composition above, in its
  # own session and process group, released only once its pgid and start time
  # are read. TRIFORGE_TEST_BUILDER rides as an argument, so a shell variable
  # that was never exported still reaches it.
  if [ ! -x "$BASH_BIN" ]; then BASH_BIN=$(command -v bash 2>/dev/null || printf 'bash'); fi
  LAUNCH=$(python3 -c "$_LEASE_LAUNCH_PY" "${OUT}.log" "$BASH_BIN" -c "$_LEASE_BUILDER_SH" triforge-lease-builder \
             "${_TRIFORGE_SCRIPTS_DIR}/invoke-external.sh" "$CLI" "$MODEL" "$EFFORT" "$DISPATCH_MODEL" "$KIMI_AGENT_FILE" \
             "$CBIN" "$TOBIN" "$TIMEOUT" "$OUT" "$WT" "$REG_ENV_KEYS" "${TRIFORGE_TEST_BUILDER:-}" "$FULL_PROMPT") || LAUNCH=""
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
  DEADLINE=$((NOW + TIMEOUT))
  if ! _ledger_update "$TASK_ID" state=building pid="$PID" pgid="$PGID" pid_started="$PID_START" lead_pid="$_LEAD_PID" lead_started="$_LEAD_STARTED" \
         output_file="$OUT" heartbeat_deadline="$DEADLINE"; then
    _lease_kill_builder "$PID" "$PGID" "$PID_START" term   # unrecorded, so never left running
    return 1
  fi
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

# _lease_sweep_one <op> <task> <lead-exit 0|1> <mode> [<row>] — one building
# lease's reconcile, shared by lease_wait and lease_heartbeat_check (KTD10).
# Builder alive = its pid answers as the recorded process (_lease_proc_state:
# pid, pgid and start time). Then:
#   alive, before heartbeat_deadline  keeps building; when the lead that
#                                     dispatched it is gone, the current lead
#                                     adopts it (lead_pid / lead_started),
#                                     reason=lead-exit + lead_exit_at
#   alive past heartbeat_deadline     hung: its process group is killed, then
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
# <mode>: sweep (lease_heartbeat_check: prints the still-building notes);
# poll (lease_wait: quiet, and runs the integrity check before acting on the
# row — adopt, kill, orphan — then sweeps it again as polled); polled (quiet,
# no check: that second sweep, from the verified ledger, KTD18). lease_collect
# runs its own check. <row> is the task's line from _lease_states_read (task,
# state, then the fields below); without one (polled) the row is read here.
# The exit record is tested after the liveness test, never taken from <row>: a
# builder that exits in between has written it by then, and a stale "absent"
# would orphan a finished builder. Sets _LS_RESULT: building | collected |
# orphaned | unverified | left (no longer building). Returns 0, or the rc of
# an integrity check / ledger write that failed.
_lease_sweep_one() {
  local OP=$1 TASK=$2 LEAD_EXIT=${3:-0} MODE=${4:-sweep} ROW=${5:-}
  local T="" ST="" PID="" PGID="" STARTED="" OUT="" DEADLINE="" LPID="" LSTARTED="" B ACTION LEAD_GONE=0
  local NOW AGE=999999 GRACE RC=0 STAMP
  _LS_RESULT=""
  GRACE=${TRIFORGE_HEARTBEAT_GRACE:-60}
  case "$GRACE" in ''|*[!0-9]*) GRACE=60 ;; esac
  if [ -n "$ROW" ]; then
    { IFS="$_LEASE_US" read -r T ST PID PGID STARTED OUT DEADLINE LPID LSTARTED || true; } <<SWEEP_LINE_EOF
${ROW}
SWEEP_LINE_EOF
  else
    ROW=$(_ledger_get_row "$TASK" state pid pgid pid_started output_file heartbeat_deadline lead_pid lead_started) || ROW=""
    { IFS= read -r ST || true; IFS= read -r PID || true; IFS= read -r PGID || true; IFS= read -r STARTED || true
      IFS= read -r OUT || true; IFS= read -r DEADLINE || true; IFS= read -r LPID || true; IFS= read -r LSTARTED || true; } <<SWEEP_ROW_EOF
${ROW}
SWEEP_ROW_EOF
  fi
  if [ -n "$ROW" ] && [ "$ST" != building ]; then
    _LS_RESULT=left
    return 0
  fi
  if [ -z "$PID" ] || [ -z "$OUT" ]; then
    # Could not verify: a building row with no pid/output to judge liveness
    # by (ledger written by an older version, or a crash between dispatch
    # and its ledger update). Report it, leave it alone — never guess.
    echo "${OP}: ${TASK} building but pid/output_file missing from the ledger — cannot verify liveness (degraded); inspect and reclaim by hand" >&2
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
      _LS_RESULT=collected
      return 0
      ;;
    expire)
      # Hung past its window: still breathing but the lease is expired — kill
      # its process group, then orphan (the launcher's own timeout should have
      # fired; this is the belt to that suspender).
      echo "${OP}: ${TASK} EXPIRED — pid ${PID} alive past heartbeat_deadline; killing the builder's process group and orphaning" >&2
      _lease_kill_builder "$PID" "$PGID" "$STARTED"
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
# TRIFORGE_LEASE_ROOT changed since lease_create), naming the export that
# reaches it again. The recorded root is a hint, never a source: the lease root
# holds the lead's integrity anchors, so it is not taken from the ledger.
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
        sys.stderr.write(os.environ["LR_OP"] + ": NOTE lease " + str(t) + " was created under the lease root " + root
                         + ", but this shell resolves " + os.environ["LR_ROOT"] + " (TMPDIR or TRIFORGE_LEASE_ROOT changed): export TRIFORGE_LEASE_ROOT=" + root + " to reach it\n")
' || true
}

# lease_heartbeat_check [--lead-exit] [task_id] — the resume sweep: every
# building lease (or just one) through _lease_sweep_one, after the integrity
# check (KTD18: a change is escalated and returns 44). A live builder keeps
# building; a finished one is collected (lease_collect's stdout goes to stderr
# here); a dead one with no exit record is orphaned and reclaimed (KTD-9); a
# lease whose dispatching lead is gone is adopted or collected with
# reason=lead-exit and its requeue budget untouched. --lead-exit treats every
# swept lease's lead as gone: the forced handover (U9) calls it. rc 0;
# _RC_DEGRADED when a row could not be verified; a collect's 44 passes through.
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
  _lease_root_notice lease_heartbeat_check
  _lead_integrity_check lease_heartbeat_check || return $?
  # Every building lease's row, one line each, in one ledger read; a ledger
  # that does not parse shows on stderr and sweeps nothing.
  ROWS=$(_lease_states_read "") || ROWS=""
  # $ROWS is NEWLINE-separated. Iterate with read, NOT `for ROW in $ROWS`:
  # under zsh (the caller's shell on macOS) an unquoted $ROWS is not
  # word-split, so `for` would run once on the whole blob and corrupt the
  # sweep for 2+ concurrent leases — the parallel-wave case. The heredoc (not
  # a `printf | while` pipe) keeps the loop in THIS shell so the counters
  # persist; each sweep reads /dev/null, never the row list.
  while IFS= read -r ROW; do
    TASK=${ROW%%"$_LEASE_US"*}
    case "$TASK" in ""|@now) continue ;; esac
    if [ -n "$ONLY" ] && [ "$TASK" != "$ONLY" ]; then continue; fi
    SWEPT=$((SWEPT + 1))
    RC=0
    _lease_sweep_one lease_heartbeat_check "$TASK" "$LEAD_EXIT" sweep "$ROW" < /dev/null || RC=$?
    if [ "$RC" -ne 0 ]; then return "$RC"; fi
    case "$_LS_RESULT" in
      collected)  COLLECTED=$((COLLECTED + 1)) ;;
      orphaned)   ORPHANED=$((ORPHANED + 1)) ;;
      unverified) UNVERIFIED=$((UNVERIFIED + 1)) ;;
    esac
  done <<HEARTBEAT_ROWS
$ROWS
HEARTBEAT_ROWS
  echo "lease_heartbeat_check: swept ${SWEPT} building lease(s), collected ${COLLECTED}, orphaned ${ORPHANED}, unverifiable ${UNVERIFIED}" >&2
  if [ "$UNVERIFIED" -gt 0 ]; then return "$_RC_DEGRADED"; fi
  return 0
}

# _lease_lead_host — the CLI leading this session, for its registry
# lead.wait_budget_s, from the host markers U29 recorded: CODEX_THREAD_ID or
# CODEX_CI in a Codex lead's tool shell (CDX-15), else claude (CLAUDECODE=1
# under Claude Code, CC-11, and the default with no markers). U9's lead
# resolution replaces it.
_lease_lead_host() {
  if [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_CI:-}" ]; then
    printf 'codex\n'
  else
    printf 'claude\n'
  fi
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

# _LEASE_WAIT_PY — the ledger read of lease_wait and lease_heartbeat_check: one
# line per task in LW_NAMES (space-separated), or per building lease when
# LW_NAMES is empty — task, state (whitespace-collapsed; "@missing" for a task
# with no row), then the row fields _lease_sweep_one needs: pid, pgid,
# pid_started, output_file, heartbeat_deadline, lead_pid, lead_started; then
# "@now" and the epoch ms. Fields are separated by _LEASE_US (\037), which,
# unlike a tab, keeps an empty field in place under `read`. A row whose fields
# hold a line break or that separator keeps only its state (the sweep then
# finds no pid and reports it unverifiable, as a row _ledger_get_row can't
# read), and a ledger key holding one is not listed as building.
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
# lead from _lease_lead_host until U9 lands; TRIFORGE_LEAD_WAIT_BUDGET_S may
# only lower it): the default and the cap are that value minus a quarter of
# it, at most 15 s, so the call returns inside the lead's shell-tool limit.
# The budget counts from the call's start, and the polling stops a second
# before it, so the closing integrity check fits inside it too. Under a
# Claude lead, pass the Bash tool timeout explicitly: wait_budget_s x 1000 ms.
# stdout: "<task> <state>" for each watched lease that left building, then
# "still building: <task>..." when any still is, or "no lease building".
# rc 0: a lease left building, or none was building; _RC_WAIT_BUILDING (75):
# the budget ran out, everything watched still building; 44: the integrity
# check found a change (restored and escalated, as in every lease helper);
# 1: ledger error (missing, unparseable) or an unknown task; 64: usage;
# 45: run by a worker or from inside the lease root. Loop it in bounded slices
# until it prints no "still building:" line.
lease_wait() {
  _lead_only lease_wait || return $?
  local BUDGET="" NAMES="" ERR WAIT_CLI CAP HEADROOM EFF READ WATCH ROW START_MS STOP_MS CHECK_MS REM RC=0
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
      _lead_integrity_check lease_wait || return $?
      ERR=$(_lease_ledger_check) || { echo "lease_wait: LEDGER ERROR — ${ERR}" >&2; return 1; }
    else
      echo "lease_wait: LEDGER ERROR — ${ERR}; nothing to wait on" >&2
      return 1
    fi
  fi
  _lease_root_notice lease_wait
  _lead_integrity_check lease_wait || return $?
  WAIT_CLI=$(_lease_lead_host)
  CAP=$(cli_field "$WAIT_CLI" lead.wait_budget_s 2>/dev/null) || CAP=""
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
    echo "lease_wait: budget capped at ${EFF}s (${WAIT_CLI} lead: wait_budget_s ${CAP}s, the wait returns ${HEADROOM}s inside it)" >&2
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
  # room the closing integrity check needs.
  STOP_MS=$((START_MS + BUDGET * 1000 - 500))
  if [ "$BUDGET" -ge 2 ]; then STOP_MS=$((STOP_MS - 500)); fi
  CHECK_MS=$((START_MS + 15000))
  while :; do
    # One pass over the leases still building, from the rows of the last read.
    _LS_LEAD_KEY=""
    while IFS= read -r ROW; do
      if [ -z "$ROW" ]; then continue; fi
      _lease_sweep_one lease_wait "${ROW%%"$_LEASE_US"*}" 0 poll "$ROW" < /dev/null || RC=$?
      if [ "$RC" -ne 0 ]; then break; fi
    done <<LEASE_WAIT_EOF
${_LW_ROWS}
LEASE_WAIT_EOF
    if [ "$RC" -ne 0 ]; then break; fi
    READ=$(_lease_states_read "$WATCH" 2>/dev/null) || READ=""
    if [ -z "$READ" ]; then
      # The ledger stopped parsing mid-wait: the integrity check restores it
      # from the lead's copy (and escalates), or there is nothing left to trust.
      _lead_integrity_check lease_wait || return $?
      echo "lease_wait: LEDGER ERROR — ${_LEASE_LEDGER} could not be read" >&2
      return 1
    fi
    _lease_wait_parse "$READ"
    if [ -n "$_LW_LEFT" ] || [ -z "$_LW_STILL" ] || [ "$_LW_NOW" -ge "$STOP_MS" ]; then break; fi
    if [ "$_LW_NOW" -ge "$CHECK_MS" ]; then
      _lead_integrity_check lease_wait || { RC=$?; break; }
      CHECK_MS=$((_LW_NOW + 15000))
    fi
    REM=$((STOP_MS - _LW_NOW))
    if [ "$REM" -ge 1000 ]; then sleep 1; else sleep "$(printf '0.%03d' "$REM")"; fi
  done
  # Every return runs the integrity check (KTD10): a builder that changed git
  # state or the ledger while the lead waited is restored and escalated here,
  # and the states printed below are read from the verified ledger.
  if [ "$RC" -eq 0 ]; then _lead_integrity_check lease_wait || RC=$?; fi
  READ=$(_lease_states_read "$WATCH" 2>/dev/null) || READ=""
  _lease_wait_parse "$READ"
  _lease_wait_print
  if [ "$RC" -ne 0 ]; then return "$RC"; fi
  if [ -n "$_LW_LEFT" ] || [ -z "$_LW_STILL" ]; then return 0; fi
  echo "lease_wait: the ${BUDGET}s budget ran out; still building: ${_LW_STILL} — call lease_wait again" >&2
  return "$_RC_WAIT_BUILDING"
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
# ANY mismatch: nothing is deleted, state=escalated with reason "lease
# identity mismatch", nonzero return. A clean pass prunes worktree + branch,
# then transitions per the current state:
#   orphaned + requeue_count 0  -> requeued   (lease_requeue re-leases it)
#   orphaned + requeue_count 1+ -> escalated  (KTD-9: requeue once, loudly)
#   merged / anything else      -> state kept (prune only)
lease_reclaim() {
  _lead_only lease_reclaim || return $?
  local TASK_ID=${1:?usage: lease_reclaim <task_id>}
  local ROOT WT_STORED WT_CANON STATE RQ
  _lease_ctx || return 1
  ROOT=$_LEASE_ROOT
  WT_STORED=$(_ledger_get "$TASK_ID" worktree) || { echo "lease_reclaim: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  STATE=$(_ledger_get "$TASK_ID" state)

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
  _lease_provision "$WT" || return 1
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
# reviewer mid-sprint. Idempotent: re-pinning the SAME reviewer is a no-op;
# pinning a DIFFERENT one is refused. Refuses reviewer == builder_cli (AE3).
# Call it after lease_collect (state=review), before reviewing.
lease_pin_reviewer() {
  _lead_only lease_pin_reviewer || return $?
  local TASK_ID=${1:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local REVIEWER=${2:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local BUILDER PINNED
  _lease_ctx || return 1
  _lead_integrity_check lease_pin_reviewer || return $?
  _ledger_get "$TASK_ID" state >/dev/null || { echo "lease_pin_reviewer: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if ! _is_known_cli "$REVIEWER"; then
    echo "lease_pin_reviewer: REFUSED — '${REVIEWER}' is not a known reviewer identity (one of: $(_known_clis)). A fabricated label cannot stand in for a real reviewer (AE3)." >&2
    return 1
  fi
  BUILDER=$(_ledger_get "$TASK_ID" builder_cli)
  if [ "$REVIEWER" = "$BUILDER" ]; then
    echo "lease_pin_reviewer: REFUSED — reviewer '${REVIEWER}' is the builder of ${TASK_ID}; self-review is never allowed (AE3). Pick a non-author reviewer." >&2
    return 1
  fi
  PINNED=$(_ledger_get "$TASK_ID" pinned_reviewer 2>/dev/null || true)
  if [ -n "$PINNED" ] && [ "$PINNED" != "$REVIEWER" ]; then
    echo "lease_pin_reviewer: REFUSED — ${TASK_ID} is already pinned to reviewer '${PINNED}' (KTD-10: the same reviewer stays across all fix cycles). Re-review with '${PINNED}', or escalate to the user if that reviewer is unavailable." >&2
    return 1
  fi
  _ledger_update "$TASK_ID" pinned_reviewer="$REVIEWER" || return 1
  echo "lease_pin_reviewer: ${TASK_ID} reviewer pinned to '${REVIEWER}' (holds across all <=3 cycles)" >&2
}

# lease_merge <task_id> <reviewer-identity> — single-commit-per-task merge
# (KTD-5) with the AE3 mechanical guard, hardened three ways: the reviewer must
# be (1) a KNOWN adapter identity (a fabricated label like "codex-reviewer" is
# rejected), (2) different from builder_cli (self-review never merges), and (3)
# already PINNED via lease_pin_reviewer — the pin is the "a review happened"
# receipt, so a merge with no pin is refused (U10 layers the full cross-review
# protocol on these checks). It squash-merges the lead's collect snapshot
# (KTD3/KTD19 — recorded by lease_collect; "commit nothing; the lead
# collects") into the MAIN tree only after the integrity check, the
# integration-branch check and the snapshot checks pass (_lease_verify_snapshot:
# branch = base + that one commit, worktree unchanged since collect, no ops/
# path), records reviewer + merge_commit, then reclaims via the safe-prune
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
  if ! _is_known_cli "$REVIEWER"; then
    echo "lease_merge: REFUSED — '${REVIEWER}' is not a known reviewer identity (one of: $(_known_clis)). A fabricated label like 'codex-reviewer' cannot pass the non-author gate (AE3)." >&2
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
  _ledger_update "$TASK_ID" state=merged reviewer="$REVIEWER" pinned_reviewer="$REVIEWER" merge_commit="$SHA" || return 1
  # The lead's own merge moves the integration branch: that is the new state
  # the next merge or promotion must start from (KTD18).
  _ledger_update @baseline integration_branch="$(_lease_current_branch)" integration_sha="$SHA" >/dev/null || return 1
  echo "lease_merge: ${TASK_ID} merged as ${SHA} (builder ${BUILDER}, reviewer ${REVIEWER}) — reclaiming worktree" >&2
  lease_reclaim "$TASK_ID" || true
  return 0
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
#       failed -> BLOCK: print that promotion needs lead/user approval (a
#       protected-path diff forces the gate on and requires the lead or user as
#       reviewer, never external-CLI-only), return _RC_PROMOTE_BLOCKED, do NOT
#       merge
#   (e) else fast-forward (or merge) the integration branch into the default
#       branch and report the promotion.
# Atomic where it matters: the default branch is never touched unless the gate
# passes — the block path leaves the tree exactly as it found it.
lease_promote() {
  _lead_only lease_promote || return $?
  local REPO DEFAULT_BRANCH CURRENT_BRANCH INTEGRATION_BRANCH
  _lease_ctx || { echo "lease_promote: ERROR not inside a git repository" >&2; return 1; }
  REPO=$_LEASE_REPO
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
  local SCAN_DIR SCAN_ERR="" PROTECTED_HIT="" FRAMEWORK=0
  SCAN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/triforge-promote-scan.XXXXXX") || return 1
  if ! _lgr diff -z --name-only --no-renames --no-ext-diff --ignore-submodules=none "${DEFAULT_BRANCH}...HEAD" > "${SCAN_DIR}/changed" 2> "${SCAN_DIR}/err"; then
    SCAN_ERR="git diff ${DEFAULT_BRANCH}...HEAD failed: $(head -c 300 "${SCAN_DIR}/err" | tr '\n' ' ')"
  fi

  # (c) protected-path scan (KTD8). A hit forces the gate ON regardless of the
  # knob. Fail closed: an unreadable plugin manifest counts as the Triforge
  # checkout, and any classifier error blocks with its message.
  if [ -z "$SCAN_ERR" ]; then
    _lease_is_framework_checkout "$REPO" "$DEFAULT_BRANCH" && FRAMEWORK=1
    if ! _protected_classify "$FRAMEWORK" < "${SCAN_DIR}/changed" > "${SCAN_DIR}/hits" 2> "${SCAN_DIR}/err"; then
      SCAN_ERR="protected-path classifier failed: $(tail -c 300 "${SCAN_DIR}/err" | tr '\n' ' ')"
    else
      PROTECTED_HIT=$(cat "${SCAN_DIR}/hits")
    fi
  fi
  rm -rf "$SCAN_DIR"

  # (d) block when gated.
  if [ "$REQUIRE_APPROVAL" = "true" ] || [ -n "$PROTECTED_HIT" ] || [ -n "$SCAN_ERR" ]; then
    echo "lease_promote: BLOCKED — promotion of '${INTEGRATION_BRANCH}' to '${DEFAULT_BRANCH}' needs lead/user approval. No merge performed." >&2
    if [ "$REQUIRE_APPROVAL" = "true" ]; then
      echo "  reason: [promotion].require_user_approval = true in ops/roster.toml (KTD-5 user gate)." >&2
    fi
    if [ -n "$SCAN_ERR" ]; then
      echo "  reason: the protected-path scan could not run, so the diff is treated as protected (fail-closed, KTD8): ${SCAN_ERR}" >&2
    fi
    if [ -n "$PROTECTED_HIT" ]; then
      echo "  reason: the integration diff touches protected paths (controls that govern the pool; lists in scripts/lib/registry.sh — framework_protected applies in the Triforge checkout only). A protected-path diff forces the gate ON regardless of the knob and requires the LEAD or USER as reviewer — never an external-CLI-only review:" >&2
      printf '%s\n' "$PROTECTED_HIT" | while IFS="$(printf '\t')" read -r _pl _ph; do
        if [ -n "$_ph" ]; then echo "    ${_ph}  (${_pl}_protected)" >&2; fi
      done
    fi
    echo "  Once the lead/user approves, promote by hand (git checkout ${DEFAULT_BRANCH} && git merge ${INTEGRATION_BRANCH}), then run lease_rebaseline so the integrity baseline records the new ${DEFAULT_BRANCH} (a hand promotion moves it off [baseline].default_sha, and the next lease_* call would refuse with rc 44) — or set [promotion].require_user_approval=false for a purely non-protected diff and rerun." >&2
    return "$_RC_PROMOTE_BLOCKED"
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
  if [ -f "$_LEASE_LEDGER" ]; then
    _lease_default_ref
    _ledger_update @baseline default_branch="$_LEASE_DEF" default_sha="$_LEASE_DEF_SHA" integration_branch="" integration_sha="" >/dev/null || true
  fi
  echo "lease_promote: PROMOTED '${INTEGRATION_BRANCH}' -> '${DEFAULT_BRANCH}' (HEAD ${SHA}); require_user_approval=${REQUIRE_APPROVAL}, protected-paths=none." >&2
  return 0
}

# lease_status — human table of the ledger (task, builder, state, age) for
# at-status and at-resume orientation. Tolerant: reports a missing or unparseable
# ledger instead of failing.
lease_status() {
  local LEDGER
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  if [ ! -f "$LEDGER" ]; then
    echo "lease_status: no lease ledger (${LEDGER}) — no leases have been created"
    return 0
  fi
  LEDGER_FILE="$LEDGER" python3 -c "
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
rows = [('TASK', 'BUILDER', 'MODEL', 'STATE', 'AGE')]
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
    rows.append((str(t), str(r.get('builder_cli', '?')),
                 str(r.get('builder_model', '') or '-'), state, age_s))
if len(rows) == 1:
    print('lease_status: ledger is empty')
    sys.exit(0)
widths = [max(len(r[i]) for r in rows) for i in range(5)]
for r in rows:
    print('  '.join(r[i].ljust(widths[i]) for i in range(5)).rstrip())
print('')
print('states: ' + ', '.join(k + '=' + str(v) for k, v in sorted(counts.items())))
"
}
