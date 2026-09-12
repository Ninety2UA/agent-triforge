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
# Confinement (KTD-3, KTD-14, R35): builders never read or write the
# canonical ops/ tree — required context is injected into the dispatch
# prompt; the builder runs with cwd = its worktree under a per-adapter env
# allowlist (_adapter_env) so no cross-provider credential leaks; shared-file
# mutations happen lead-side at collect/merge time on the main tree.

# Repo root of the MAIN checkout (lease functions are lead-side and run from
# the main tree, never from inside a worktree).
_lease_repo_root() {
  git rev-parse --show-toplevel 2>/dev/null
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
  local REPO=$1 REF="" B
  REF=$(git -C "$REPO" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null) || REF=""
  if [ -n "$REF" ]; then
    printf '%s\n' "${REF#refs/remotes/origin/}"
    return 0
  fi
  for B in main master; do
    if git -C "$REPO" show-ref --verify --quiet "refs/heads/${B}" 2>/dev/null; then
      printf '%s\n' "$B"
      return 0
    fi
  done
  return 0
}

# Current checked-out branch of the main tree, or empty on detached HEAD.
_lease_current_branch() {
  git -C "$1" symbolic-ref --quiet --short HEAD 2>/dev/null || true
}

# Lease root: TRIFORGE_LEASE_ROOT override, else
# ${TMPDIR:-/tmp}/triforge-leases/<repo-basename>-<git-hash-of-repo-root-path>
# (the hash is of the canonical root path STRING, so two checkouts of one
# repo get distinct roots). Created, then canonicalized before printing —
# every stored worktree path is canonical from birth, which is what lets
# lease_reclaim compare stored vs canonical byte-for-byte.
_lease_root() {
  local ROOT REPO
  REPO=$(_lease_repo_root) || { echo "lease: ERROR not inside a git repository — worktree leases require one (outside git the builder pool degrades to lead-only in-place execution)." >&2; return 1; }
  REPO=$(_lease_realpath "$REPO")
  if [ -n "${TRIFORGE_LEASE_ROOT:-}" ]; then
    ROOT="$TRIFORGE_LEASE_ROOT"
  else
    local BASE HASH
    BASE=$(basename "$REPO")
    HASH=$(printf '%s' "$REPO" | git hash-object --stdin | cut -c1-12)
    ROOT="${TMPDIR:-/tmp}"
    ROOT="${ROOT%/}/triforge-leases/${BASE}-${HASH}"
  fi
  mkdir -p "$ROOT" || return 1
  _lease_realpath "$ROOT"
}

_lease_ledger_path() {
  local REPO
  REPO=$(_lease_repo_root) || return 1
  printf '%s\n' "${REPO}/ops/leases.toml"
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
_ledger_update() {
  local TASK_ID=$1
  shift
  local LEDGER LOCK RC=0 TRIES=0
  LEDGER=$(_lease_ledger_path) || return 1
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
  LEDGER_FILE="$LEDGER" LEDGER_TASK="$TASK_ID" python3 -c "
import json, os, sys, time
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
data = {}
if os.path.isfile(path):
    with open(path, 'rb') as f:
        data = tomllib.load(f)
leases = data.get('lease', {})
leases = leases if isinstance(leases, dict) else {}
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
leases[task] = row

# Flat serializer: only ints, bools, and strings ever land in a row.
# json.dumps escaping is valid TOML for basic strings and quoted keys.
lines = ['# ops/leases.toml — lead-owned lease ledger (KTD-4). Runtime state,',
         '# gitignored. Single writer: the lead, via _ledger_update in',
         '# scripts/invoke-external.sh. Builders never write this file.',
         '']
for t in sorted(leases):
    r = leases[t]
    if not isinstance(r, dict):
        continue
    lines.append('[lease.' + json.dumps(str(t)) + ']')
    for k in sorted(r):
        v = r[k]
        if isinstance(v, bool):
            lines.append(k + ' = ' + ('true' if v else 'false'))
        elif isinstance(v, int):
            lines.append(k + ' = ' + str(v))
        else:
            lines.append(k + ' = ' + json.dumps(str(v)))
    lines.append('')

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
" "$@"
  RC=$?
  rm -rf "$LOCK" 2>/dev/null || true   # lock dir now carries a pid file — rm -rf, not rmdir
  return $RC
}

# _ledger_get <task_id> <key> — print the value ('' when the key is unset);
# nonzero when the ledger or the lease row is missing entirely.
_ledger_get() {
  local LEDGER
  LEDGER=$(_lease_ledger_path) || return 1
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
row = data.get('lease', {}).get(os.environ['LEDGER_TASK'])
if not isinstance(row, dict):
    sys.exit(1)
print(row.get(os.environ['LEDGER_KEY'], ''))
"
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

# Worktrees lack .agents/skills/ (gitignored in user projects) — provision a
# copy so portable-skill discovery survives isolation (mirrors the
# session-start.sh bootstrap; KTD-3 groundwork).
_lease_provision_skills() {
  local WT=$1
  local SRC=""
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/skills" ]; then
    SRC="${CLAUDE_PLUGIN_ROOT}/skills"
  elif [ -d "$(_lease_repo_root)/skills" ]; then
    SRC="$(_lease_repo_root)/skills"
  fi
  if [ -z "$SRC" ]; then
    echo "lease: WARNING no skills source found (CLAUDE_PLUGIN_ROOT/skills or repo skills/) — worktree gets no .agents/skills/" >&2
    return 0
  fi
  # `cp -R src/. dest/` — never `cp -R src dest`, which NESTS when the worktree
  # already carries a committed .agents/skills/ (the stamp is safe to commit in
  # user projects, so that layout is expected). Shipped-name directories are
  # Triforge-owned and replaced, matching session-start's refresh (KTD7).
  local NAME
  mkdir -p "${WT}/.agents/skills"
  for NAME in "$SRC"/*/; do
    [ -d "$NAME" ] || continue
    NAME=$(basename "$NAME")
    rm -rf "${WT}/.agents/skills/${NAME}" 2>/dev/null || true
    mkdir -p "${WT}/.agents/skills/${NAME}" 2>/dev/null && cp -R "${SRC}/${NAME}/." "${WT}/.agents/skills/${NAME}/" 2>/dev/null || true
  done
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
  local REPO ROOT RESOLVED CLI MODEL EFFORT WT NOW
  REPO=$(_lease_repo_root) || { echo "lease_create: ERROR not inside a git repository" >&2; return 1; }
  ROOT=$(_lease_root) || return 1
  RESOLVED=$(resolve_role "$ROLE") || return $?
  CLI=$(printf '%s\n' "$RESOLVED" | cut -f1)
  MODEL=$(printf '%s\n' "$RESOLVED" | cut -f2)
  EFFORT=$(printf '%s\n' "$RESOLVED" | cut -f3)
  WT="${ROOT}/${TASK_ID}"
  if [ -e "$WT" ]; then
    echo "lease_create: ERROR worktree path already exists: ${WT} (reclaim the previous lease first)" >&2
    return 1
  fi
  if ! git -C "$REPO" worktree add "$WT" -b "lease/${TASK_ID}" >&2; then
    echo "lease_create: ERROR git worktree add failed for task ${TASK_ID}" >&2
    return 1
  fi
  _lease_provision_skills "$WT"
  NOW=$(date +%s)
  _ledger_update "$TASK_ID" \
    task_id="$TASK_ID" role="$ROLE" \
    builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    state=leased worktree="$WT" branch="lease/${TASK_ID}" \
    pid=0 output_file="" created="$NOW" heartbeat_deadline=0 \
    requeue_count=0 review_cycle=0 pinned_reviewer="" previous_builder="" reviewer="" merge_commit="" reason="" \
    || return 1
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
  STATE=$(_ledger_get "$TASK_ID" state) || { echo "lease_dispatch: ERROR no lease row for task '${TASK_ID}' — run lease_create first" >&2; return 1; }
  if [ "$STATE" != "leased" ]; then
    echo "lease_dispatch: ERROR task ${TASK_ID} is in state '${STATE}' (want leased)" >&2
    return 1
  fi
  CLI=$(_ledger_get "$TASK_ID" builder_cli)
  MODEL=$(_ledger_get "$TASK_ID" builder_model)
  EFFORT=$(_ledger_get "$TASK_ID" builder_effort)
  ROLE=$(_ledger_get "$TASK_ID" role)
  WT=$(_ledger_get "$TASK_ID" worktree)
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
          local -a CMD=(opencode run --format json -m "${MODEL:-openrouter/z-ai/glm-5.3}")
          [ -n "$EFFORT" ] && CMD+=(--variant "$EFFORT")
          _adapter_env opencode "$TOBIN" "${TIMEOUT}s" "${CMD[@]}" "$FULL_PROMPT" < /dev/null > "$OUT" 2>&1 || RC=$?
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

# lease_heartbeat_check [task_id] — sweep building leases (or just one).
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
  local REPO ROOT WT_STORED WT_CANON STATE RQ
  REPO=$(_lease_repo_root) || return 1
  ROOT=$(_lease_root) || return 1
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
  if ! git -C "$REPO" worktree list --porcelain | grep -Fxq "worktree ${WT_CANON}"; then
    _lease_refuse_prune "$TASK_ID" "$WT_STORED" "path not registered in git worktree list"; return 1
  fi

  if ! git -C "$REPO" worktree remove --force "$WT_CANON" >&2; then
    echo "lease_reclaim: ERROR git worktree remove failed for ${WT_CANON}" >&2
    _ledger_update "$TASK_ID" state=escalated reason="worktree remove failed" || true
    return 1
  fi
  git -C "$REPO" branch -D "lease/${TASK_ID}" >/dev/null 2>&1 || true

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
  local STATE RQ PREV ROLE OUT REPO ROOT WT RESOLVED CLI MODEL EFFORT
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
  REPO=$(_lease_repo_root) || return 1
  ROOT=$(_lease_root) || return 1
  RESOLVED=$(RESOLVE_ROLE_EXCLUDE="$PREV" resolve_role "$ROLE") || {
    _ledger_update "$TASK_ID" state=escalated reason="no alternative builder" || true
    echo "lease_requeue: ${TASK_ID} ESCALATED — no live builder past previous '${PREV}' in role '${ROLE}' fallback chain." >&2
    return 1
  }
  CLI=$(printf '%s\n' "$RESOLVED" | cut -f1)
  MODEL=$(printf '%s\n' "$RESOLVED" | cut -f2)
  EFFORT=$(printf '%s\n' "$RESOLVED" | cut -f3)
  WT="${ROOT}/${TASK_ID}"
  if [ -e "$WT" ]; then
    echo "lease_requeue: ERROR stale worktree still present at ${WT} — reclaim first" >&2
    return 1
  fi
  if ! git -C "$REPO" worktree add "$WT" -b "lease/${TASK_ID}" >&2; then
    echo "lease_requeue: ERROR git worktree add failed for task ${TASK_ID}" >&2
    return 1
  fi
  _lease_provision_skills "$WT"
  _ledger_update "$TASK_ID" \
    state=leased builder_cli="$CLI" builder_model="$MODEL" builder_effort="$EFFORT" \
    previous_builder="$PREV" requeue_count=1 pid=0 heartbeat_deadline=0 reason="" \
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
# protocol on these checks). The lead snapshots the
# builder's uncommitted worktree changes onto the lease branch ("commit
# nothing; the lead collects"), squash-merges into the MAIN tree, records
# reviewer + merge_commit, then reclaims via the safe-prune path. Squash
# conflicts leave a dirty index: reset --merge, state stays review, the lead
# resolves manually.
lease_merge() {
  local TASK_ID=${1:?usage: lease_merge <task_id> <reviewer-identity>}
  local REVIEWER=${2:-}
  local STATE BUILDER WT BRANCH REPO SHA PINNED
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
  REPO=$(_lease_repo_root) || return 1
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

  # Lead-side collect commit: the builder committed nothing (contract), so
  # snapshot its work onto the lease branch. .agents/ (provisioned skills)
  # is excluded even where a project forgot to gitignore it.
  git -C "$WT" add -A -- . ":(exclude).agents" >&2 || return 1
  if ! git -C "$WT" diff --cached --quiet 2>/dev/null; then
    git -C "$WT" commit -m "lease(${TASK_ID}): builder output snapshot (${BUILDER})" >&2 || return 1
  fi

  # The squash commit must contain exactly this lease's work (KTD-5): a
  # pre-dirtied main index would smuggle unrelated changes into it.
  if ! git -C "$REPO" diff --cached --quiet 2>/dev/null; then
    echo "lease_merge: ERROR main tree index has staged changes — commit or unstage them first; the lease commit must contain only ${TASK_ID}'s work" >&2
    return 1
  fi
  if ! git -C "$REPO" merge --squash "$BRANCH" >&2; then
    git -C "$REPO" reset --merge >&2 || true
    echo "lease_merge: CONFLICT squash-merging ${BRANCH} into the main tree — index reset, state stays review. The lead resolves manually (rebase the lease branch onto HEAD, or cherry-pick), then reruns lease_merge." >&2
    return 1
  fi
  if git -C "$REPO" diff --cached --quiet 2>/dev/null; then
    echo "lease_merge: ERROR ${BRANCH} brought no changes (builder produced nothing?) — state stays review" >&2
    return 1
  fi
  if ! git -C "$REPO" commit -m "lease(${TASK_ID}): merged from ${BUILDER}, reviewed by ${REVIEWER}" >&2; then
    git -C "$REPO" reset --merge >&2 || true
    echo "lease_merge: ERROR commit failed — index reset, state stays review" >&2
    return 1
  fi
  SHA=$(git -C "$REPO" rev-parse HEAD)
  _ledger_update "$TASK_ID" state=merged reviewer="$REVIEWER" pinned_reviewer="$REVIEWER" merge_commit="$SHA" || return 1
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
# and the gate codes above (40–43, 96).
_RC_DEGRADED=80

# lease_promote [<default-branch>] — wave-end promotion of the sprint integration
# branch to the repo default branch (KTD-5). This is the ONLY path that writes the
# default branch; lease_merge only ever lands on the integration branch. Run it
# from the main tree checked out ON the integration branch (where lease_merge put
# the wave's squash commits), NOT on the default branch.
#
# Gate, in order:
#   (a) read [promotion].require_user_approval from ops/roster.toml (default false)
#   (b) compute the integration branch's changed paths vs the default branch:
#       git diff --name-only <default>...HEAD
#   (c) scan them against PROTECTED_PATHS — the controls that govern the pool:
#       permission configs, deny/policy rules, ops/roster.toml (incl [promotion]),
#       and the shipped agent configs
#   (d) require_user_approval=true OR any protected path touched -> BLOCK: print
#       that promotion needs lead/user approval (a protected-path diff forces the
#       gate on and requires the lead or user as reviewer, never external-CLI-only),
#       return _RC_PROMOTE_BLOCKED, do NOT merge
#   (e) else fast-forward (or merge) the integration branch into the default
#       branch and report the promotion.
# Atomic where it matters: the default branch is never touched unless the gate
# passes — the block path leaves the tree exactly as it found it.
lease_promote() {
  local REPO DEFAULT_BRANCH CURRENT_BRANCH INTEGRATION_BRANCH
  REPO=$(_lease_repo_root) || { echo "lease_promote: ERROR not inside a git repository" >&2; return 1; }
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
  # A dirty index would ride into the promotion merge — refuse it.
  if ! git -C "$REPO" diff --cached --quiet 2>/dev/null; then
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

  # (b) changed paths of the integration branch vs the default branch.
  local CHANGED
  CHANGED=$(git -C "$REPO" diff --name-only "${DEFAULT_BRANCH}...HEAD" 2>/dev/null) || {
    echo "lease_promote: ERROR could not diff '${DEFAULT_BRANCH}...HEAD' — is '${DEFAULT_BRANCH}' a valid branch reachable from HEAD?" >&2
    return 1
  }

  # (c) protected-path scan. A single match forces the gate ON regardless of the
  # knob. Prefixes cover every shipped agent config, each CLI's permission/deny
  # config (shipped templates/.*/ AND the project-level live .*/ dirs), and
  # ops/roster.toml (incl
  # its [promotion] block), and the shipped agent configs (agents/, and every
  # <cli>-agents/ dir). No literal backticks in the heredoc.
  local PROTECTED_HIT=""
  PROTECTED_HIT=$(CHANGED="$CHANGED" python3 -c "
import os
protected_prefixes = (
    'agents/',
    'antigravity-agents/',
    'codex-agents/',
    'opencode-agents/',
    'kimi-agents/',
    'cursor-agents/',
    # Orchestration + lifecycle control plane — the framework's own files that
    # IMPLEMENT the lease/confinement/promotion/review machinery and lifecycle
    # hooks. Protected by SPECIFIC path (not whole top-level dirs) so a wave in a
    # USER project whose own app code lives under scripts/ or commands/ is not
    # force-gated on every touch; these are the plugin's control-plane files
    # (when dogfooding this repo) plus the permission configs sensitive in ANY
    # project. A wave must never promote a change to its own enforcement code or
    # permission config on an external-CLI-only review.
    'scripts/invoke-external.sh',
    'scripts/coordinate.sh',
    'scripts/probe-capabilities.sh',
    'hooks/hooks.json',
    'hooks/handlers/',
    '.claude/settings.json',
    '.claude/settings.local.json',
    '.claude-plugin/',
    # Shipped per-CLI templates (member-governing configs, permission/deny
    # rules) — every optional member's dir, symmetric with the core trio's.
    'templates/.antigravity/',
    'templates/.opencode/',
    'templates/.codex/',
    'templates/.kimi-code/',
    'templates/.cursor/',
    'templates/ops/roster.toml',
    # Project-level live CLI configs — a wave must not silently rewrite the
    # permission/governance config any adapter reads.
    '.codex/',
    '.opencode/',
    '.kimi-code/',
    '.cursor/',
    '.antigravity/',
    'ops/roster.toml',
)
for line in os.environ.get('CHANGED', '').splitlines():
    p = line.strip()
    if p and p.startswith(protected_prefixes):
        print(p)
" 2>/dev/null || true)

  # (d) block when gated.
  if [ "$REQUIRE_APPROVAL" = "true" ] || [ -n "$PROTECTED_HIT" ]; then
    echo "lease_promote: BLOCKED — promotion of '${INTEGRATION_BRANCH}' to '${DEFAULT_BRANCH}' needs lead/user approval. No merge performed." >&2
    if [ "$REQUIRE_APPROVAL" = "true" ]; then
      echo "  reason: [promotion].require_user_approval = true in ops/roster.toml (KTD-5 user gate)." >&2
    fi
    if [ -n "$PROTECTED_HIT" ]; then
      echo "  reason: the integration diff touches protected paths (controls that govern the pool). A protected-path diff forces the gate ON regardless of the knob and requires the LEAD or USER as reviewer — never an external-CLI-only review:" >&2
      printf '%s\n' "$PROTECTED_HIT" | while IFS= read -r _ph; do
        [ -n "$_ph" ] && echo "    ${_ph}" >&2
      done
    fi
    echo "  Once the lead/user approves, promote by hand (git checkout ${DEFAULT_BRANCH} && git merge ${INTEGRATION_BRANCH}) or set [promotion].require_user_approval=false for a purely non-protected diff and rerun." >&2
    return "$_RC_PROMOTE_BLOCKED"
  fi

  # (e) promote: fast-forward when possible, else a merge commit.
  if ! git -C "$REPO" checkout "$DEFAULT_BRANCH" >&2; then
    echo "lease_promote: ERROR could not checkout the default branch '${DEFAULT_BRANCH}'." >&2
    return 1
  fi
  if git -C "$REPO" merge --ff-only "$INTEGRATION_BRANCH" >&2; then
    :
  elif git -C "$REPO" merge --no-edit "$INTEGRATION_BRANCH" >&2; then
    :
  else
    git -C "$REPO" merge --abort 2>/dev/null || true
    git -C "$REPO" checkout "$INTEGRATION_BRANCH" >&2 2>/dev/null || true
    echo "lease_promote: ERROR merging '${INTEGRATION_BRANCH}' into '${DEFAULT_BRANCH}' failed (conflicts) — aborted and returned to '${INTEGRATION_BRANCH}'. Resolve manually." >&2
    return 1
  fi
  local SHA
  SHA=$(git -C "$REPO" rev-parse HEAD)
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
