#!/usr/bin/env bash
# scripts/lib/lease.sh — the lease lifecycle (KTD-4): ledger, per-adapter env allowlist (+ no-push backstop), lease_create/dispatch/collect/merge/promote, the typed-report parser (KTD11)
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
# .git/info and the ledger from the lead's copies, escalates, and merges only
# the lead's own recorded snapshot of each lease (KTD19). Other git callers —
# the harness's own git, ad-hoc git the lead model runs, other builders — are
# covered only by that detection. All of it is detection, not prevention.

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
# The only git this file runs outside _lead_git: `git config --<scope>` reads
# that one scope (include.* is off for a named scope) and executes nothing.
# Captured before any builder runs, so a later worker edit to ~/.gitconfig never
# reaches the lead's git (and the integrity check reports it).
_lead_gitconfig_capture() {
  local DEST=$1 TMP="${1}.tmp.$$" SCOPE K V LIST
  mkdir -p "$(dirname "$DEST")" || return 1
  printf '# Triforge trusted git config (KTD18) — captured from your system/global git config on\n# first use. The lead-side git calls in scripts/lib/lease.sh read ONLY this file as global\n# config. Delete it to re-capture.\n' > "$TMP" || return 1
  for SCOPE in --system --global; do
    LIST=$(env -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_DIR -u GIT_WORK_TREE \
             git config "$SCOPE" --null --get-regexp '^(user\.(name|email)|core\.(excludesfile|autocrlf|eol)|init\.defaultbranch|safe\.directory|filter\.lfs\..*)$' 2>/dev/null \
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
# .git/info) is digest-checked before these calls run. Inherited GIT_* that
# would redirect the call are unset; _LEAD_GIT_INDEX, when set, becomes
# GIT_INDEX_FILE (the temporary index a snapshot is built in).
_lead_git() {
  if [ -z "${_LEAD_CFG:-}" ] || [ ! -f "${_LEAD_CFG}" ]; then
    _lease_ctx || return 1
  fi
  local -a E=(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY
              -u GIT_ALTERNATE_OBJECT_DIRECTORIES -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_EXTERNAL_DIFF
              GIT_CONFIG_NOSYSTEM=1 "GIT_CONFIG_GLOBAL=${_LEAD_CFG}" GIT_TERMINAL_PROMPT=0 GIT_PAGER=cat GIT_EDITOR=true GIT_OPTIONAL_LOCKS=0)
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

# Repo root of the lead's checkout (lease functions are lead-side and run from
# the main tree, never from inside a worktree).
_lease_repo_root() {
  _lease_ctx || return 1
  printf '%s\n' "$_LEASE_REPO"
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
# on every call. Int keys: pid, created, updated, heartbeat_deadline,
# requeue_count, review_cycle.
#
# The reserved id @baseline (never a valid task id) writes the [baseline]
# table instead of a lease row: the lead's last verified git state (KTD18) —
# digests of .git/config, .git/hooks, .git/info and the global git config, the
# default branch and its SHA, the integration branch and its SHA.
#
# Integrity (KTD18): after every write the ledger's digest and a copy of it are
# kept in the lead state dir (<lease root>/lead/ledger.sha256, ledger.copy).
# Before a write, a ledger that no longer matches the lead's last write was
# changed by someone else: the write starts from the lead's copy instead
# (restoring it) and sets [baseline].ledger_alert, which the next
# _lead_integrity_check escalates.
_ledger_update() {
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
        with open(p, 'rb') as f:
            return hashlib.sha256(f.read()).hexdigest()
    except OSError:
        return 'absent'
recorded = ''
if os.path.isfile(digest_file):
    recorded = open(digest_file).read().strip()
source, alert = path, ''
if recorded and _sha(path) != recorded:
    stamp = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    if os.path.isfile(copy_file) and _sha(copy_file) == recorded:
        source = copy_file
        alert = stamp + ' ops/leases.toml changed outside the lead writes (restored from the lead copy before a write)'
    else:
        alert = stamp + ' ops/leases.toml changed outside the lead writes (no intact lead copy to restore from)'
data = {}
if os.path.isfile(source):
    with open(source, 'rb') as f:
        data = tomllib.load(f)
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
INT_KEYS = ('pid', 'created', 'updated', 'heartbeat_deadline', 'requeue_count', 'review_cycle', 'report_missing_count')
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
row = data.get('lease', {}).get(os.environ['LEDGER_TASK'])
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
#                             and the global git config files; the default
#                             branch and its SHA; the integration branch and
#                             its SHA (updated after each of the lead's merges)
#   each lease row            its worktree's .git pointer file and admin dir
#                             (.git/worktrees/<name>: HEAD, gitdir, commondir,
#                             config.worktree), base_sha, and the collect
#                             snapshot (snapshot_sha, snapshot_tree)
#   <lease root>/lead/        copies of .git/config, .git/hooks, .git/info and
#                             the ledger (with its digest), for restoring
# _lead_integrity_check runs at lease_create, lease_dispatch, lease_pin_reviewer,
# lease_collect, lease_merge, lease_promote, lease_requeue and
# lease_heartbeat_check. A change the lead did not make restores what can be
# restored (.git/config, .git/hooks, .git/info, the ledger), escalates, names
# the changed surface, and returns _RC_LEASE_INTEGRITY (44). A repo-wide change
# escalates every building/review lease (any of their builders could have made
# it); a per-lease change escalates that lease. lease_rebaseline accepts a
# change the lead or user made (and resumes the leases it escalated).
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

def tree_digest(p):
    if os.path.islink(p):
        return "link:" + os.readlink(p)
    if not os.path.isdir(p):
        return file_digest(p) if os.path.lexists(p) else "absent"
    entries = []
    for root, dirs, files in os.walk(p):
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

def repo_surfaces(common):
    return {"config": file_digest(os.path.join(common, "config")),
            "hooks": tree_digest(os.path.join(common, "hooks")),
            "info": tree_digest(os.path.join(common, "info")),
            "global_gitconfig": global_digest()}

NAMES = {"config": ".git/config", "hooks": ".git/hooks/", "info": ".git/info/",
         "global_gitconfig": "the global git config (~/.gitconfig, ~/.config/git/config)"}
RESTORABLE = ("config", "hooks", "info")

def _remove(p):
    if os.path.islink(p) or os.path.isfile(p):
        os.unlink(p)
    elif os.path.isdir(p):
        shutil.rmtree(p)

def save_copies(common, state):
    for name in RESTORABLE:
        src, dst = os.path.join(common, name), os.path.join(state, name + ".copy")
        _remove(dst)
        if os.path.islink(src):
            continue
        if os.path.isdir(src):
            shutil.copytree(src, dst, symlinks=True)
        elif os.path.isfile(src):
            shutil.copyfile(src, dst)

def restore(common, state, name, baseline_digest):
    src, dst = os.path.join(state, name + ".copy"), os.path.join(common, name)
    if not os.path.lexists(src) and baseline_digest != "absent":
        return "no lead copy to restore from"
    if os.path.isfile(src) and not os.path.islink(src):
        shutil.copyfile(src, dst + ".triforge-restore")
        if os.path.isdir(dst) and not os.path.islink(dst):
            shutil.rmtree(dst)
        os.replace(dst + ".triforge-restore", dst)
    else:
        _remove(dst)
        if os.path.isdir(src):
            shutil.copytree(src, dst, symlinks=True)
    return "restored from the lead copy"

def admin_from_pointer(wt, common):
    try:
        line = open(os.path.join(wt, ".git"), encoding="utf-8").read().strip()
    except OSError:
        return ""
    if not line.startswith("gitdir:"):
        return ""
    admin = os.path.realpath(os.path.join(wt, line[len("gitdir:"):].strip()))
    return admin if os.path.dirname(admin) == os.path.realpath(os.path.join(common, "worktrees")) else ""

mode = os.environ["LI_MODE"]
common = os.environ.get("LI_COMMON", "")
state = os.environ.get("LI_STATE", "")

if mode == "record":
    save_copies(common, state)
    for k, v in sorted(repo_surfaces(common).items()):
        print(k + "=" + v)
    sys.exit(0)

if mode == "lease":
    wt, admin = os.environ["LI_WT"], os.environ.get("LI_ADMIN", "")
    admin = admin or admin_from_pointer(wt, common)
    print(file_digest(os.path.join(wt, ".git")) + "\t" + admin_digest(admin) + "\t" + admin)
    sys.exit(0)

# mode == "check": compare, restore (LI_RESTORE=1), report one line per finding.
restoring = os.environ.get("LI_RESTORE") == "1"
force_record = os.environ.get("LI_FORCE_RECORD") == "1"
ledger = os.environ["LI_LEDGER"]
out = []
dig_file, copy_file = os.path.join(state, "ledger.sha256"), os.path.join(state, "ledger.copy")
recorded = open(dig_file).read().strip() if os.path.isfile(dig_file) else ""
if recorded and file_digest(ledger) != recorded:
    note = "no intact lead copy to restore from"
    if restoring and os.path.isfile(copy_file) and file_digest(copy_file) == recorded:
        shutil.copyfile(copy_file, ledger + ".triforge-restore")
        os.replace(ledger + ".triforge-restore", ledger)
        note = "restored from the lead copy"
    out.append(("REPO", "ledger", "ops/leases.toml changed outside the lead writes (" + note + ")"))
data = {}
if os.path.isfile(ledger):
    with open(ledger, "rb") as f:
        data = tomllib.load(f)
base = data.get("baseline")
leases = data.get("lease", {})
leases = leases if isinstance(leases, dict) else {}
if not isinstance(base, dict) or not base.get("config"):
    out.append(("NOBASELINE", "", ""))
    base = None
else:
    if base.get("ledger_alert"):
        out.append(("REPO", "ledger_alert", str(base["ledger_alert"])))
    cur = repo_surfaces(common)
    for k in sorted(cur):
        if str(base.get(k, "")) and cur[k] != str(base.get(k)):
            how = restore(common, state, k, str(base.get(k))) if (restoring and k in RESTORABLE) else ("not restored: a user file" if k == "global_gitconfig" else "not restored")
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
# on a state they just verified or explicitly accept (lease_rebaseline).
_lead_baseline_record() {
  local L
  local -a ARGS=()
  _lease_ctx || return 1
  _lease_default_ref
  while IFS= read -r L; do
    if [ -n "$L" ]; then ARGS+=("$L"); fi
  done <<BASELINE_EOF
$(LI_MODE=record LI_COMMON="$_LEASE_COMMON" LI_STATE="$_LEASE_STATE" python3 -c "$_LEAD_INTEGRITY_PY")
BASELINE_EOF
  if [ "${#ARGS[@]}" -lt 4 ]; then
    echo "lease: ERROR could not record the integrity baseline (KTD18)" >&2
    return 1
  fi
  _ledger_update @baseline "${ARGS[@]}" default_branch="$_LEASE_DEF" default_sha="$_LEASE_DEF_SHA" ledger_alert="" \
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
  local OP=${1:-lease} LEDGER OUT RC=0 KIND A B C D TAB NL
  local REPO_DESC="" OPEN="" LEASE_HITS="" ALERT=0 NOBASE=0 T S ESCALATED=""
  TAB=$(printf '\t'); NL='
'
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  if [ ! -f "$LEDGER" ] && [ ! -f "${_LEASE_STATE}/ledger.sha256" ]; then
    return 0    # no lease was ever created here: nothing to compare against
  fi
  _lease_default_ref
  OUT=$(LI_MODE=check LI_RESTORE=1 LI_COMMON="$_LEASE_COMMON" LI_STATE="$_LEASE_STATE" LI_LEDGER="$LEDGER" \
        LI_DEF="$_LEASE_DEF" LI_DEF_SHA="$_LEASE_DEF_SHA" python3 -c "$_LEAD_INTEGRITY_PY" 2>&1) || RC=$?
  if [ "$RC" -ne 0 ]; then
    echo "${OP}: INTEGRITY CHECK COULD NOT RUN — treated as a change (fail closed, KTD18): $(printf '%s' "$OUT" | tail -3 | tr '\n' ' ' | cut -c1-300)" >&2
    return "$_RC_LEASE_INTEGRITY"
  fi
  while IFS="$TAB" read -r KIND A B C D; do
    case "$KIND" in
      NOBASELINE) NOBASE=1 ;;
      REPO) REPO_DESC="${REPO_DESC}${REPO_DESC:+${NL}}    ${B}"; if [ "$A" = "ledger_alert" ]; then ALERT=1; fi ;;
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
  return "$_RC_LEASE_INTEGRITY"
}

# _lead_integration_check <op> — lease_merge and lease_promote build on the
# integration branch only from a state the lead verified: its tip must equal
# the SHA recorded after the lead's last merge (a builder can move the branch,
# since it shares .git). A new integration branch is recorded as found.
_lead_integration_check() {
  local OP=$1 IB ISHA CUR HEAD_SHA LOG
  CUR=$(_lease_current_branch)
  [ -n "$CUR" ] || return 0
  HEAD_SHA=$(_lgr rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null || true)
  IB=$(_ledger_get @baseline integration_branch 2>/dev/null || true)
  ISHA=$(_ledger_get @baseline integration_sha 2>/dev/null || true)
  if [ "$IB" != "$CUR" ] || [ -z "$ISHA" ]; then
    _ledger_update @baseline integration_branch="$CUR" integration_sha="$HEAD_SHA" >/dev/null || return 1
    return 0
  fi
  [ "$ISHA" = "$HEAD_SHA" ] && return 0
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
# acceptance, never a worker's.
lease_rebaseline() {
  local LEDGER OUT KIND A B C D TAB T PREV CUR HEAD_SHA
  TAB=$(printf '\t')
  _lease_ctx || return 1
  LEDGER=$_LEASE_LEDGER
  if [ ! -f "$LEDGER" ]; then
    echo "lease_rebaseline: no lease ledger (${LEDGER}) — nothing to rebaseline" >&2
    return 0
  fi
  _lease_default_ref
  OUT=$(LI_MODE=check LI_RESTORE=0 LI_FORCE_RECORD=1 LI_COMMON="$_LEASE_COMMON" LI_STATE="$_LEASE_STATE" LI_LEDGER="$LEDGER" \
        LI_DEF="$_LEASE_DEF" LI_DEF_SHA="$_LEASE_DEF_SHA" python3 -c "$_LEAD_INTEGRITY_PY") || { echo "lease_rebaseline: ERROR the integrity check could not run" >&2; return 1; }
  while IFS="$TAB" read -r KIND A B C D; do
    case "$KIND" in
      REPO) echo "lease_rebaseline: accepting — ${B}" >&2 ;;
      RECORD) _ledger_update "$A" pointer_digest="$B" admin_digest="$C" admin_dir="$D" >/dev/null || return 1 ;;
    esac
  done <<REBASE_EOF
${OUT}
REBASE_EOF
  _lead_baseline_record || return 1
  CUR=$(_lease_current_branch)
  if [ -n "$CUR" ]; then
    HEAD_SHA=$(_lgr rev-parse --verify --quiet 'HEAD^{commit}' 2>/dev/null || true)
    _ledger_update @baseline integration_branch="$CUR" integration_sha="$HEAD_SHA" >/dev/null || return 1
  fi
  for T in "$@"; do
    PREV=$(_ledger_get "$T" integrity_prev_state 2>/dev/null || true)
    if [ -n "$PREV" ] && [ "$(_ledger_get "$T" state 2>/dev/null || true)" = "escalated" ]; then
      _ledger_update "$T" state="$PREV" integrity_prev_state="" reason="" >/dev/null || return 1
      echo "lease_rebaseline: ${T} back to '${PREV}'" >&2
    else
      echo "lease_rebaseline: ${T} was not escalated by an integrity check — state unchanged" >&2
    fi
  done
  echo "lease_rebaseline: baseline recorded (default ${_LEASE_DEF:-<none>} ${_LEASE_DEF_SHA:0:12}, integration ${CUR:-<detached>} ${HEAD_SHA:0:12})" >&2
}

# _adapter_env <cli> <cmd...> — run an external command under the per-adapter
# environment allowlist (KTD-14): base allowlist HOME PATH TMPDIR TERM LANG
# COLORTERM USER (+ the GIT_CONFIG_* no-push backstop, CS1) plus ONLY the
# invoked CLI's own credential variables (opencode:
# OPENROUTER_API_KEY; kimi: KIMI_*; cursor: CURSOR_API_KEY). claude, codex,
# and antigravity authenticate via HOME-based stores and get nothing extra —
# no cross-provider leakage. env -i execs external commands only; shell
# functions cannot cross it, which is why lease_dispatch composes direct CLI
# commands instead of calling the invoke_* helpers (see there).
_adapter_env() {
  local CLI=$1
  shift
  local -a PAIRS=()
  # Base allowlist — enumerated explicitly rather than via ${!V} indirect
  # expansion. This file is `source`d under the CALLER's shell (the commands
  # do a plain `source`, which ignores the bash shebang), and on macOS that is
  # zsh, where ${!V} raises "bad substitution" and would kill every lease
  # dispatch. Explicit ${HOME+x} tests and array append work under both bash
  # and zsh (verified).
  [ -n "${HOME+x}" ]      && PAIRS+=("HOME=${HOME}")
  [ -n "${PATH+x}" ]      && PAIRS+=("PATH=${PATH}")
  [ -n "${TMPDIR+x}" ]    && PAIRS+=("TMPDIR=${TMPDIR}")
  [ -n "${TERM+x}" ]      && PAIRS+=("TERM=${TERM}")
  [ -n "${LANG+x}" ]      && PAIRS+=("LANG=${LANG}")
  [ -n "${COLORTERM+x}" ] && PAIRS+=("COLORTERM=${COLORTERM}")
  # USER is identity, not a secret: Claude Code resolves its keychain credential
  # account from it, so without it `claude -p` under env -i answers "Not logged
  # in" on every macOS host (live bisect 2026-09-11: +USER -> READY; LOGNAME
  # alone does not help). Mirrored by _lane_run in scripts/probe-capabilities.sh.
  [ -n "${USER+x}" ]      && PAIRS+=("USER=${USER}")
  PAIRS+=("NO_COLOR=1")   # captured output is parsed, never rendered (U5)
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
  case "$CLI" in
    opencode)
      [ -n "${OPENROUTER_API_KEY+x}" ] && PAIRS+=("OPENROUTER_API_KEY=${OPENROUTER_API_KEY}")
      # D-033 defense-in-depth: the shipped deny set rides as OPENCODE_PERMISSION
      # (caller's own value wins) — the adapter stays off --auto regardless.
      PAIRS+=("OPENCODE_PERMISSION=${OPENCODE_PERMISSION:-$_OPENCODE_PERMISSION_DEFAULT}")
      ;;
    kimi)
      # Forward every EXPORTED KIMI_* var. `compgen` and ${!V} are bash-only,
      # so python3 (already required) enumerates os.environ and emits each
      # matching NAME=VALUE pair base64-encoded, one per line. base64 has no
      # internal newlines, so line-based read is portable across bash and zsh
      # AND preserves values that themselves contain newlines or `=`.
      local _kv_b64
      while IFS= read -r _kv_b64; do
        [ -n "$_kv_b64" ] && PAIRS+=("$(printf '%s' "$_kv_b64" | base64 -d 2>/dev/null)")
      done <<KIMIENV
$(python3 -c "
import os, base64, sys
for k, v in os.environ.items():
    if k.startswith('KIMI_'):
        sys.stdout.write(base64.b64encode((k + '=' + v).encode()).decode() + '\n')
")
KIMIENV
      ;;
    cursor)
      [ -n "${CURSOR_API_KEY+x}" ] && PAIRS+=("CURSOR_API_KEY=${CURSOR_API_KEY}")
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

# _lease_plugin_root — the Triforge plugin root this library belongs to:
# CLAUDE_PLUGIN_ROOT when set, else the directory above the loaded scripts/
# when it IS a Triforge root (.claude-plugin/plugin.json named agent-triforge
# plus scripts/invoke-external.sh). Never the project's own tree: a user
# project's skills/ or scripts/ is not Triforge's (R42). Empty + rc 1 when no
# root qualifies.
_lease_plugin_root() {
  local C
  for C in "${CLAUDE_PLUGIN_ROOT:-}" "${_TRIFORGE_SCRIPTS_DIR:-}/.."; do
    [ -n "$C" ] && [ -f "${C}/scripts/invoke-external.sh" ] || continue
    if PR_MANIFEST="${C}/.claude-plugin/plugin.json" python3 -c '
import json, os, sys
try:
    with open(os.environ["PR_MANIFEST"], encoding="utf-8") as f:
        sys.exit(0 if json.load(f).get("name") == "agent-triforge" else 1)
except Exception:
    sys.exit(1)
' 2>/dev/null; then
      _lease_realpath "$C"
      return 0
    fi
  done
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
    echo "lease: WARNING no Triforge plugin root found (CLAUDE_PLUGIN_ROOT, or the directory above the loaded scripts/) — worktree gets no .agents/skills/" >&2
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

# ---------------------------------------------------------------------------
# Worktree carve, collect snapshot and snapshot-only merge (KTD3, KTD18, KTD19)
# ---------------------------------------------------------------------------

# _lease_carve <task_id> <worktree> — the lease worktree + lease/<task> branch
# at the lead's current HEAD, through _lead_git (no hook runs, whatever a
# worker planted). Sets _CARVE_BASE (the recorded base SHA), _CARVE_ADMIN (the
# worktree's admin dir, read from the pointer the lead just created) and
# _CARVE_POINTER / _CARVE_ADMIN_DIGEST (the per-lease integrity baseline).
_lease_carve() {
  local T=$1 WT=$2 D
  _CARVE_BASE=""; _CARVE_ADMIN=""; _CARVE_POINTER=""; _CARVE_ADMIN_DIGEST=""
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
}

# _lease_tree_of_worktree <worktree> <admin> <start-commit> — print the tree
# the worktree holds now, built in a throwaway index seeded from <start-commit>
# (the snapshot's own rule: every change, .agents/ excluded — provisioned
# skills never merge). The worktree's own index and HEAD are not touched.
_lease_tree_of_worktree() {
  local W=$1 A=$2 START=$3 IDXD TREE RC=0
  IDXD=$(mktemp -d "${TMPDIR:-/tmp}/triforge-snap.XXXXXX") || return 1
  _LEAD_GIT_INDEX="${IDXD}/index"
  { _lgw "$W" "$A" read-tree "$START" && _lgw "$W" "$A" add -A -- . ':(exclude).agents' >/dev/null && TREE=$(_lgw "$W" "$A" write-tree); } || RC=1
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
  local T=$1 ROW WT ADMIN BASE BRANCH PREV BUILDER TIP BC="" C TREE PARENT SNAP
  ROW=$(_ledger_get_row "$T" worktree admin_dir base_sha branch snapshot_sha builder_cli) || ROW=""
  { IFS= read -r WT || true; IFS= read -r ADMIN || true; IFS= read -r BASE || true
    IFS= read -r BRANCH || true; IFS= read -r PREV || true; IFS= read -r BUILDER || true; } <<SNAP_ROW_EOF
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
  TREE=$(_lease_tree_of_worktree "$WT" "$ADMIN" "$TIP") || { echo "lease_collect: ERROR could not build the snapshot tree for ${T}" >&2; return 1; }
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
  local T=$1 ROW WT ADMIN BASE BRANCH SNAP STREE TIP PARENT NOW LOG OPS
  ROW=$(_ledger_get_row "$T" worktree admin_dir base_sha branch snapshot_sha snapshot_tree) || ROW=""
  { IFS= read -r WT || true; IFS= read -r ADMIN || true; IFS= read -r BASE || true
    IFS= read -r BRANCH || true; IFS= read -r SNAP || true; IFS= read -r STREE || true; } <<VERIFY_ROW_EOF
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
  NOW=$(_lease_tree_of_worktree "$WT" "$ADMIN" "$SNAP") || { echo "lease_merge: REFUSED — could not read ${T}'s worktree to compare it with the snapshot" >&2; return 1; }
  if [ "$NOW" != "$STREE" ]; then
    echo "lease_merge: REFUSED — ${T}'s worktree changed after collect and no longer matches the recorded snapshot (tree ${STREE:0:12}, now ${NOW:0:12}). Something wrote it after the review target was fixed; re-collect via lease_redispatch (KTD19)." >&2
    return 1
  fi
  OPS=$(_lgr diff -z --name-only --no-renames --no-ext-diff "$BASE" "$SNAP" 2>/dev/null | python3 -c '
import sys
bad = [p for p in sys.stdin.buffer.read().decode("utf-8", "replace").split("\0") if p and (p.casefold() == "ops" or p.casefold().startswith("ops/"))]
print(" ".join(bad[:10]) + (" ..." if len(bad) > 10 else ""))
') || OPS="<diff failed>"
  if [ -n "$OPS" ]; then
    echo "lease_merge: REFUSED — ${T}'s diff touches the lead-owned ops/ tree (builders never write ops/; the lead does, on the main tree): ${OPS}. Remove those changes from the worktree and re-collect (KTD19)." >&2
    return 1
  fi
}

# lease_create <task_id> <role> — resolve the builder from the roster
# (resolve_role), carve the worktree + lease branch, provision skills, write
# the leased row. Echoes task_id on success so callers can chain.
lease_create() {
  local TASK_ID=${1:?usage: lease_create <task_id> <role>}
  local ROLE=${2:?usage: lease_create <task_id> <role>}
  if ! _lease_valid_task_id "$TASK_ID"; then
    echo "lease_create: ERROR invalid task id '${TASK_ID}' — want [A-Za-z0-9][A-Za-z0-9._-]* (it becomes a branch and directory name)" >&2
    return 1
  fi
  local RESOLVED CLI MODEL EFFORT WT NOW CUR IB
  _lease_ctx || { echo "lease_create: ERROR not inside a git repository" >&2; return 1; }
  # A change a worker made since the lead's last check (a planted hook, git
  # config, a moved ref) is caught before the next worktree is carved (KTD18).
  _lead_integrity_check lease_create || return $?
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
  _lease_provision_skills "$WT"
  NOW=$(date +%s)
  CUR=$(_lease_current_branch)
  _ledger_update "$TASK_ID" \
    task_id="$TASK_ID" role="$ROLE" \
    builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    state=leased worktree="$WT" branch="lease/${TASK_ID}" \
    pid=0 output_file="" created="$NOW" heartbeat_deadline=0 \
    requeue_count=0 review_cycle=0 pinned_reviewer="" previous_builder="" reviewer="" merge_commit="" reason="" \
    base_sha="$_CARVE_BASE" admin_dir="$_CARVE_ADMIN" pointer_digest="$_CARVE_POINTER" admin_digest="$_CARVE_ADMIN_DIGEST" \
    integration_branch="$CUR" snapshot_sha="" snapshot_tree="" builder_commits="" integrity_prev_state="" \
    || return 1
  # First lease in this checkout: the lead's verified state becomes the
  # integrity baseline before any builder runs; a new integration branch is
  # recorded at the commit its first lease starts from.
  if [ -z "$(_ledger_get @baseline config 2>/dev/null || true)" ]; then
    _lead_baseline_record || return 1
  fi
  IB=$(_ledger_get @baseline integration_branch 2>/dev/null || true)
  if [ -n "$CUR" ] && [ "$IB" != "$CUR" ]; then
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

# lease_dispatch <task_id> <prompt> [timeout-seconds]
#
# Composes the FULL dispatch prompt: injected context header (KTD-3 — the
# lease's roster line plus the explicit confinement contract) + the
# lead-provided task prompt (which carries the task row text and any
# CONTRACTS.md slice — the builder never reads canonical ops/).
#
# The builder launches in the BACKGROUND with cwd = the worktree (subshell
# cd), under _adapter_env's per-CLI allowlist (KTD-14). The invoke_* helpers
# are shell functions and cannot cross env -i, so each lane composes the
# adapter's command core directly: codex = exec + workspace-write + approval
# never + stdin guard (codex's own sandbox then scopes writes to the
# worktree cwd); antigravity = model pin + --add-dir + --print-timeout;
# claude = -p --permission-mode acceptEdits (cwd IS the worktree, no
# --add-dir needed). Exit code and KTD-9 class land in <out>.rc /
# <out>.class for the single-writer lead to collect — the builder process
# never touches the ledger.
#
# Test seam: TRIFORGE_TEST_BUILDER=<script path> replaces the real adapter
# for lifecycle determinism — the script runs with the worktree as cwd and
# the full prompt as its first argument, still under the recorded CLI's env
# allowlist and timeout so the confinement/heartbeat paths stay honest.
lease_dispatch() {
  local TASK_ID=${1:?usage: lease_dispatch <task_id> <prompt> [timeout]}
  local PROMPT=${2:?usage: lease_dispatch <task_id> <prompt> [timeout]}
  local TIMEOUT=${3:-600}
  local STATE CLI MODEL EFFORT ROLE WT ROOT OUT TOBIN NOW DEADLINE PID
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
  ROOT=$(_lease_root) || return 1
  OUT="${ROOT}/${TASK_ID}.out"
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
      BRIEF_FILE="${CLAUDE_PLUGIN_ROOT:-}/${CLI}-agents/builder.md"
      if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "$BRIEF_FILE" ]; then
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

  rm -f "$OUT" "${OUT}.rc" "${OUT}.class"

  # Lane-specific composition that must happen LEAD-SIDE, before env -i: the
  # Kimi builder definition's absolute plugin path (D-024), the Cursor binary and
  # the effort-suffixed Cursor model id (D-025). The ledger records the id that
  # was actually dispatched (dispatched_model) beside the roster values
  # (builder_model / builder_effort).
  local KIMI_AGENT_FILE="" CBIN="" DISPATCH_MODEL="$MODEL"
  case "$CLI" in
    kimi)
      [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/kimi-agents/builder.md" ] && KIMI_AGENT_FILE="${CLAUDE_PLUGIN_ROOT}/kimi-agents/builder.md"
      DISPATCH_MODEL="${MODEL:-kimi-code/k3}"
      ;;
    cursor)
      DISPATCH_MODEL=$(_cursor_model_for_effort "${MODEL:-cursor-grok-4.6-xhigh}" "$EFFORT")
      if ! CBIN=$(_cursor_bin); then
        echo "lease_dispatch: ERROR no Cursor CLI on PATH (cursor-agent, or an agent whose --version matches YYYY.MM.DD-<hex>) — cannot dispatch ${TASK_ID}" >&2
        return 1
      fi
      ;;
    antigravity) DISPATCH_MODEL="${MODEL:-Gemini 3.8 Flash (High)}" ;;
    opencode)    DISPATCH_MODEL="${MODEL:-openrouter/z-ai/glm-5.3}" ;;
  esac
  _ledger_update "$TASK_ID" dispatched_model="$DISPATCH_MODEL" || return 1

  (
    cd "$WT" || exit 97
    RC=0
    CLASS_SET=0
    if [ -n "${TRIFORGE_TEST_BUILDER:-}" ]; then
      # Test seam (see function comment): deterministic fake builder.
      _adapter_env "$CLI" "$TOBIN" "${TIMEOUT}s" "$TRIFORGE_TEST_BUILDER" "$FULL_PROMPT" > "$OUT" 2>&1 || RC=$?
    else
      case "$CLI" in
        claude)
          local -a CMD=(claude -p --permission-mode acceptEdits)
          [ -n "$MODEL" ] && CMD+=(--model "$MODEL")
          _adapter_env claude "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        codex)
          # Mirrors invoke_codex's retry-safe core (sandbox, approval, model
          # pin, stdin guard) — see the env -i note in the function comment.
          # The two sandbox_workspace_write excludes drop codex's default
          # temp-dir write allowance: lease worktrees live under TMPDIR, so
          # without them a builder could cross into sibling worktrees or the
          # lease root (R35: writes restricted to the lease worktree).
          local -a CMD=(codex exec -s workspace-write -c 'approval_policy="never"'
                        -c 'sandbox_workspace_write.exclude_tmpdir_env_var=true'
                        -c 'sandbox_workspace_write.exclude_slash_tmp=true')
          [ -n "$MODEL" ] && CMD+=(-m "$MODEL")
          [ -n "$EFFORT" ] && CMD+=(-c "model_reasoning_effort=\"${EFFORT}\"")
          _adapter_env codex "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        antigravity)
          # JSON envelope (KTD2, D-032): exit 0 is not a completion signal on
          # agy >= 1.1.20 — parse status/response/denied_actions instead. The
          # prose lands in $OUT (what lease_collect prints), the streams in
          # $OUT.raw / $OUT.err, the verdict in $OUT.status / $OUT.denied.
          _adapter_env antigravity "$TOBIN" "${TIMEOUT}s" agy --model "${MODEL:-Gemini 3.8 Flash (High)}" --add-dir "$WT" --print-timeout "${TIMEOUT}s" --output-format json -p "$FULL_PROMPT" < /dev/null > "${OUT}.raw" 2> "${OUT}.err" || RC=$?
          if [ "$RC" -eq 0 ]; then
            AGY_PRC=0
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
          # cwd = the worktree (the enclosing subshell cd'd there), under
          # _adapter_env opencode — which allowlists ONLY OPENROUTER_API_KEY
          # (KTD-14), so no cross-provider credential leak. No --auto (OC-06:
          # denies do not survive it) and no invoke_opencode (a shell function
          # cannot cross env -i); the confinement contract rides in FULL_PROMPT
          # like every other lane. Shipped default is the OpenRouter GLM, so a
          # live build AUTH-FAILs until the provider is connected — that failure
          # is deterministic and the lead sees it via <out>.class (no requeue).
          # Effort -> --variant (OC-05 best-effort), guarded on a non-empty effort
          # exactly like the codex case guards model_reasoning_effort. The lease
          # path has no retry, so a provider that rejects the variant surfaces as a
          # KTD-9-classified failure the lead requeues — same as any other lane.
          # OpenCode V2 guard (D-049): V2 ignores OPENCODE_PERMISSION and runs
          # a shared background service outside env -i, so a V2 binary (or one
          # whose version can't be read — fail-closed) never dispatches — deterministic refusal naming the V1 pin, recorded in
          # <out>.class like the agy denied-actions arm (no requeue).
          if ! _opencode_v2_check opencode; then
            _opencode_v2_refusal lease_dispatch > "$OUT"
            RC=1; INVOKE_FAILURE_CLASS="deterministic"; CLASS_SET=1
          else
            local -a CMD=(opencode run --format json -m "${MODEL:-openrouter/z-ai/glm-5.3}")
            [ -n "$EFFORT" ] && CMD+=(--variant "$EFFORT")
            _adapter_env opencode "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          fi
          ;;
        kimi)
          # R35-confined optional-tier builder (U12): raw `kimi -p` with cwd =
          # the worktree (the enclosing subshell cd'd there), under _adapter_env
          # kimi — which allowlists ONLY KIMI_* (KTD-14), so no cross-provider
          # credential leak. Telemetry off (R25) via the inner `env`. --skills-dir
          # .agents/skills when present (KIMI-04). Kimi has no per-tool sandbox
          # flag and -p uses the auto policy, so confinement is the worktree + env
          # allowlist; the role brief rides in FULL_PROMPT (injection — KIMI-03
          # has no --agent, so no invoke_kimi either: a shell function cannot
          # cross env -i). Shipped default is kimi-code/k3 (the OAuth-managed
          # alias, D-024), so a live build AUTH-FAILs until kimi is signed in —
          # that failure is deterministic and the lead sees it via <out>.class
          # (no requeue). The builder definition rides as --agent-file with the
          # ABSOLUTE plugin path composed by the lead shell (KIMI_AGENT_FILE,
          # below) so it survives env -i; no --skills-dir (it would replace
          # Kimi's native .agents/skills discovery — KIMI-04).
          # -p LAST (commander.js consumes the next token as -p's value; see the
          # invoke_kimi note) — prompt right after -p.
          local -a CMD=(kimi --output-format stream-json -m "${MODEL:-kimi-code/k3}")
          [ -n "$KIMI_AGENT_FILE" ] && CMD+=(--agent-file "$KIMI_AGENT_FILE")
          _adapter_env kimi "$TOBIN" "${TIMEOUT}s" env KIMI_DISABLE_TELEMETRY=1 "${CMD[@]}" -p "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        cursor)
          # R35-confined optional-tier builder (U13): raw `cursor-agent -p` with
          # cwd = the worktree (the enclosing subshell cd'd there), under
          # _adapter_env cursor — which allowlists ONLY CURSOR_API_KEY (KTD-14),
          # so no cross-provider credential leak. --trust bypasses the
          # workspace-trust prompt (mandatory headless, CUR-04); --force applies
          # edits without confirmation (builder role, inside the worktree). Model
          # pinned to the suffixed id composed by _cursor_model_for_effort from
          # the roster model + effort (D-025; default cursor-grok-4.6-xhigh),
          # NEVER Auto (ledger attribution needs a named model). Binary resolved
          # lead-side by _cursor_bin (CBIN — cursor-agent first, verified `agent`
          # fallback) and exec'd by absolute path inside env -i. Confinement is
          # the worktree + env allowlist, NOT --sandbox (CUR-07: --sandbox
          # enabled did not confine — an absolute-path write escaped). -p is a
          # BOOLEAN flag (unlike kimi's -p); the prompt is the TRAILING
          # POSITIONAL (verified live 2026-07-18), so it comes LAST. No
          # invoke_cursor (a shell function cannot cross env -i; the role brief
          # rides in FULL_PROMPT via injection — cursor has no headless --agent
          # selector). A live build AUTH-FAILs until cursor-agent is logged in —
          # that failure is deterministic and the lead sees it via <out>.class.
          local -a CMD=("$CBIN" -p --output-format stream-json --model "$DISPATCH_MODEL" --trust --force)
          _adapter_env cursor "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
          ;;
        *)
          echo "lease_dispatch: ERROR unknown builder CLI '${CLI}' — not integrated. Known builder lanes: claude, codex, antigravity, opencode, kimi, cursor." > "$OUT"
          RC=95
          ;;
      esac
    fi
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
    elif [ "${CLASS_SET:-0}" -ne 1 ]; then
      _classify_invoke_failure "$RC" "$OUT"
    fi
    printf '%s\n' "$RC" > "${OUT}.rc"
    printf '%s\n' "${INVOKE_FAILURE_CLASS:-none}" > "${OUT}.class"
    exit "$RC"
  ) &
  PID=$!

  NOW=$(date +%s)
  DEADLINE=$((NOW + TIMEOUT))
  _ledger_update "$TASK_ID" state=building pid="$PID" output_file="$OUT" heartbeat_deadline="$DEADLINE" || return 1
  echo "lease_dispatch: task=${TASK_ID} builder=${CLI} pid=${PID} timeout=${TIMEOUT}s output=${OUT}" >&2
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

# lease_heartbeat_check [task_id] — sweep building leases (or just one). The
# integrity check runs first (KTD18): a change is escalated and returns 44.
# Builder alive = the recorded pid answers kill -0 OR the output file was
# modified within the grace window (TRIFORGE_HEARTBEAT_GRACE, default 60s —
# covers a dead wrapper whose work just flushed). A dead pid that left
# <out>.rc is NOT an orphan — the builder finished; run lease_collect. Dead
# and stale, or alive past heartbeat_deadline (hung), goes state=orphaned
# and straight into lease_reclaim's safe prune (KTD-9 timeout class).
lease_heartbeat_check() {
  local ONLY=${1:-}
  local LEDGER GRACE NOW TASKS TASK
  LEDGER=$(_lease_ledger_path) || return 1
  if [ ! -f "$LEDGER" ]; then
    echo "lease_heartbeat_check: no lease ledger at ${LEDGER} — nothing to sweep" >&2
    return 0
  fi
  _lead_integrity_check lease_heartbeat_check || return $?
  GRACE=${TRIFORGE_HEARTBEAT_GRACE:-60}
  NOW=$(date +%s)
  TASKS=$(LEDGER_FILE="$LEDGER" python3 -c "
import os, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
with open(os.environ['LEDGER_FILE'], 'rb') as f:
    data = tomllib.load(f)
for t, r in sorted(data.get('lease', {}).items()):
    if isinstance(r, dict) and r.get('state') == 'building':
        print(t)
")
  local SWEPT=0 ORPHANED=0 UNVERIFIED=0
  # $TASKS is NEWLINE-separated. Iterate with read, NOT `for TASK in $TASKS`:
  # under zsh (the caller's shell on macOS) an unquoted $TASKS is not
  # word-split, so `for` would run once on the whole "taskA\ntaskB" blob and
  # corrupt the sweep for 2+ concurrent leases — the parallel-wave case. The
  # heredoc (not a `printf | while` pipe) keeps the loop in THIS shell so the
  # SWEPT/ORPHANED counters persist.
  while IFS= read -r TASK; do
    [ -z "$TASK" ] && continue
    if [ -n "$ONLY" ] && [ "$TASK" != "$ONLY" ]; then
      continue
    fi
    SWEPT=$((SWEPT + 1))
    local PID OUT DEADLINE ALIVE FRESH AGE
    PID=$(_ledger_get "$TASK" pid)
    OUT=$(_ledger_get "$TASK" output_file)
    if [ -z "$PID" ] || [ -z "$OUT" ]; then
      # Could not verify: a building row with no pid/output to judge liveness
      # by (ledger written by an older version, or a crash between dispatch
      # and its ledger update). Report it, leave it alone — never guess.
      echo "lease_heartbeat_check: ${TASK} building but pid/output_file missing from the ledger — cannot verify liveness (degraded); inspect and reclaim by hand" >&2
      UNVERIFIED=$((UNVERIFIED + 1))
      continue
    fi
    DEADLINE=$(_ledger_get "$TASK" heartbeat_deadline)
    ALIVE=0
    [ -n "$PID" ] && [ "$PID" -gt 0 ] 2>/dev/null && kill -0 "$PID" 2>/dev/null && ALIVE=1
    if [ "$ALIVE" -eq 1 ]; then
      if [ "$NOW" -le "${DEADLINE:-0}" ]; then
        echo "lease_heartbeat_check: ${TASK} building (pid ${PID} alive, deadline in $((DEADLINE - NOW))s)" >&2
        continue
      fi
      # Hung past its window: still breathing but the lease is expired —
      # kill, then orphan (the launcher's own timeout should have fired;
      # this is the belt to that suspender).
      echo "lease_heartbeat_check: ${TASK} EXPIRED — pid ${PID} alive past heartbeat_deadline; killing the builder process tree and orphaning" >&2
      _kill_tree "$PID" TERM
      sleep 1
      _kill_tree "$PID" KILL
    else
      if [ -n "$OUT" ] && [ -f "${OUT}.rc" ]; then
        echo "lease_heartbeat_check: ${TASK} builder exited (rc=$(cat "${OUT}.rc" 2>/dev/null || true)) — run: lease_collect ${TASK}" >&2
        continue
      fi
      FRESH=0
      AGE=999999
      if [ -n "$OUT" ] && [ -f "$OUT" ]; then
        AGE=$(OUT_FILE="$OUT" python3 -c "
import os, time
print(int(time.time() - os.path.getmtime(os.environ['OUT_FILE'])))
" 2>/dev/null || echo 999999)
        [ "$AGE" -lt "$GRACE" ] 2>/dev/null && FRESH=1
      fi
      if [ "$FRESH" -eq 1 ]; then
        echo "lease_heartbeat_check: ${TASK} pid ${PID} gone but output active ${AGE}s ago (grace ${GRACE}s) — leaving as building" >&2
        continue
      fi
      echo "lease_heartbeat_check: ${TASK} ORPHANED — pid ${PID} dead, no exit record, output stale; reclaiming" >&2
    fi
    ORPHANED=$((ORPHANED + 1))
    _ledger_update "$TASK" state=orphaned || return 1
    lease_reclaim "$TASK" || true
  done <<HEARTBEAT_TASKS
$TASKS
HEARTBEAT_TASKS
  echo "lease_heartbeat_check: swept ${SWEPT} building lease(s), orphaned ${ORPHANED}, unverifiable ${UNVERIFIED}" >&2
  [ "$UNVERIFIED" -gt 0 ] && return "$_RC_DEGRADED"
  return 0
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
#      stored paths are canonical from birth (_lease_root realpaths), so any
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
  _lease_provision_skills "$WT"
  _ledger_update "$TASK_ID" \
    state=leased builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    previous_builder="$PREV" requeue_count=1 pid=0 heartbeat_deadline=0 reason="" \
    worktree="$WT" base_sha="$_CARVE_BASE" admin_dir="$_CARVE_ADMIN" pointer_digest="$_CARVE_POINTER" admin_digest="$_CARVE_ADMIN_DIGEST" \
    integration_branch="$(_lease_current_branch)" snapshot_sha="" snapshot_tree="" builder_commits="" integrity_prev_state="" \
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
  mkdir -p ops
  {
    echo ""
    echo "## Builder-reported discoveries — lease ${TASK_ID} (builder: ${BUILDER}, $(date -u +%Y-%m-%d))"
    echo "Unverified builder claims, not lead decisions — promote into Decisions/Gotchas only after checking them:"
    echo ""
    printf '%s\n' "$BLOCK" | sed 's/^/    /'
  } >> ops/MEMORY.md 2>/dev/null || true
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
  local TASK_ID=${1:?usage: lease_collect <task_id>}
  local STATE PID OUT RC CLASS
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
  PID=$(_ledger_get "$TASK_ID" pid)
  OUT=$(_ledger_get "$TASK_ID" output_file)
  if [ ! -f "${OUT}.rc" ]; then
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
      echo "lease_collect: task ${TASK_ID} still running (pid ${PID}) — wait, or lease_heartbeat_check to enforce the deadline" >&2
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
        # The builder is finished: stop anything it left running (until U13
        # detaches builders into their own process group, that is the recorded
        # pid and its children), then take the lead's snapshot, which the
        # review, the merge and any approval bind to (KTD3).
        if [ -n "$PID" ] && [ "$PID" -gt 0 ] 2>/dev/null && kill -0 "$PID" 2>/dev/null; then
          _kill_tree "$PID" TERM
        fi
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
  local TASK_ID=${1:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local REVIEWER=${2:?usage: lease_pin_reviewer <task_id> <reviewer>}
  local BUILDER PINNED
  _lease_ctx || return 1
  _lead_integrity_check lease_pin_reviewer || return $?
  _ledger_get "$TASK_ID" state >/dev/null || { echo "lease_pin_reviewer: ERROR no lease row for '${TASK_ID}'" >&2; return 1; }
  if ! _is_known_cli "$REVIEWER"; then
    echo "lease_pin_reviewer: REFUSED — '${REVIEWER}' is not a known reviewer identity (one of: ${_KNOWN_CLIS}). A fabricated label cannot stand in for a real reviewer (AE3)." >&2
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
  local TASK_ID=${1:?usage: lease_merge <task_id> <reviewer-identity>}
  local REVIEWER=${2:-}
  local STATE BUILDER WT BRANCH REPO SHA PINNED SNAP
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
    echo "lease_merge: REFUSED — '${REVIEWER}' is not a known reviewer identity (one of: ${_KNOWN_CLIS}). A fabricated label like 'codex-reviewer' cannot pass the non-author gate (AE3)." >&2
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
  REPO=$_LEASE_REPO
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
  DEFAULT_BRANCH=$(_lease_default_branch "$REPO")
  CURRENT_BRANCH=$(_lease_current_branch "$REPO")
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
# and the gate codes (40–44, 96; 44 = _RC_LEASE_INTEGRITY, defined with the
# integrity check).
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
#       or hooks, or an unrecorded commit on the integration branch refuses
#       with rc 44 before anything else runs
#   (a) read [promotion].require_user_approval from ops/roster.toml (default false)
#   (b) compute the integration branch's changed paths vs the default branch:
#       git diff -z --name-only --no-renames <default>...HEAD — both sides of
#       every rename, NUL-separated so no path is quoted out of a match
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
  local REPO DEFAULT_BRANCH CURRENT_BRANCH INTEGRATION_BRANCH
  _lease_ctx || { echo "lease_promote: ERROR not inside a git repository" >&2; return 1; }
  REPO=$_LEASE_REPO
  # Promotion writes the default branch: only from a git state the lead
  # verified (KTD18) — a moved default branch, planted config or hooks, or an
  # unrecorded commit on the integration branch refuses here.
  _lead_integrity_check lease_promote || return $?
  DEFAULT_BRANCH=${1:-$(_lease_default_branch "$REPO")}
  if [ -z "$DEFAULT_BRANCH" ]; then
    echo "lease_promote: ERROR could not determine the default branch (no origin/HEAD, no local main/master). Pass it explicitly: lease_promote <default-branch>." >&2
    return 1
  fi
  CURRENT_BRANCH=$(_lease_current_branch "$REPO")
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
  if [ -f "ops/roster.toml" ]; then
    REQUIRE_APPROVAL=$(ROSTER_FILE="ops/roster.toml" python3 -c "
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
  if ! _lgr diff -z --name-only --no-renames --no-ext-diff "${DEFAULT_BRANCH}...HEAD" > "${SCAN_DIR}/changed" 2> "${SCAN_DIR}/err"; then
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
    echo "  Once the lead/user approves, promote by hand (git checkout ${DEFAULT_BRANCH} && git merge ${INTEGRATION_BRANCH}) or set [promotion].require_user_approval=false for a purely non-protected diff and rerun." >&2
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
  # check compares against this state rather than escalating it (KTD18).
  if [ -f "$_LEASE_LEDGER" ]; then
    _ledger_update @baseline default_branch="$DEFAULT_BRANCH" default_sha="$SHA" >/dev/null || true
  fi
  echo "lease_promote: PROMOTED '${INTEGRATION_BRANCH}' -> '${DEFAULT_BRANCH}' (HEAD ${SHA}); require_user_approval=${REQUIRE_APPROVAL}, protected-paths=none." >&2
  return 0
}

# lease_status — human table of the ledger (task, builder, state, age) for
# /status and resume orientation. Tolerant: reports a missing or unparseable
# ledger instead of failing.
lease_status() {
  local LEDGER
  LEDGER=$(_lease_ledger_path) || return 1
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
