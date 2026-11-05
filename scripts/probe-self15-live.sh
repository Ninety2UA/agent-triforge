#!/usr/bin/env bash
# probe-self15-live.sh — the SELF seam, the SELF-15 fixture helpers and the live
# rows SELF-15b and SELF-15c. NOT a standalone script: sourced by
# scripts/probe-self-tests.sh (the full run and --self-only) and by the --only
# block in scripts/probe-capabilities.sh, which never sources the row file, so
# one definition serves both paths (G4, KTD7). Uses the harness's helpers (row,
# _evidence, _lane_run, _skip_reason, _want) and state (WORK, REPO_ROOT,
# SELF_ONLY, CC_LIVE, CDX_LIVE, CDX_MODEL, U29_CDX_FLAGS).
if [ -z "${WORK:-}" ] || [ -z "${REPO_ROOT:-}" ] || ! declare -F row >/dev/null 2>&1; then
  echo "probe-self15-live.sh: must be sourced by the capability probe (harness state missing)" >&2
  return 2 2>/dev/null || exit 2
fi
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# _self_seam_init — the environment every SELF row runs under.
_self_seam_init() {
  # The rows play the lead in throwaway repos under WORK. Run by a lease builder
  # testing a framework change, the worker marker it inherited would make every
  # lead helper they call refuse (KTD9), so it is dropped here; SELF-15 sets it
  # where a case needs it, and _lane_run sets it for the live lease-lane rows.
  unset TRIFORGE_LEASE_WORKER

  # The lead host check (R38, _lead_host_gate in roster.sh) lets a lead-owned
  # helper run under the lead's host markers, from a terminal, or under the SELF
  # seam. The rows strip the host markers, so they see the same host from a
  # Claude Code or a Codex tool shell, a terminal and the CI runner (which has
  # no markers and no TTY), and name the simulated lead through the seam: claude,
  # the lead of a roster without [lead]. TRIFORGE_TEST_BUILDER defaults to a
  # builder that only reports BLOCKED, so a row that forgets its own never
  # dispatches a real CLI; the rows that dispatch set theirs. A row testing
  # another lead or host sets its own (SELF-13, SELF-19's killcodex).
  unset CLAUDECODE CLAUDE_CODE_ENTRYPOINT CODEX_CI CODEX_THREAD_ID
  # The rows take Claude Code's user tier from a throwaway HOME's .claude; a
  # CLAUDE_CONFIG_DIR the runner exported would move it (instructions.sh,
  # _adapter_env, the claude lane's deny rules), so it is dropped here, and the
  # cases that test it set their own.
  unset CLAUDE_CONFIG_DIR
  export TRIFORGE_TEST_LEAD=claude
  mkdir -p "${WORK}/self-seam"
  printf '#!/bin/sh\n# SELF seam default builder: reports and does nothing\necho "Status: BLOCKED (no fake builder named for this row)"\n' > "${WORK}/self-seam/no-builder.sh"
  chmod +x "${WORK}/self-seam/no-builder.sh"
  export TRIFORGE_TEST_BUILDER="${WORK}/self-seam/no-builder.sh"

  # Stub core-trio binaries for the rows that walk the roster (resolve_role
  # needs the builder's binary on PATH) but never run a real CLI — the fake
  # builder (TRIFORGE_TEST_BUILDER) replaces the adapter. Prepended to PATH in
  # those rows only, so the rows pass the same way on a host with no CLI
  # installed (the PR workflow's macOS runner) as on a developer machine.
  _SELF_STUBS="${WORK}/self-stubs"
  mkdir -p "$_SELF_STUBS"
  for _stub in claude codex agy; do
    printf '#!/bin/sh\n# probe stub: answers --version; resolution only, never dispatched\necho "0.0.0-probe-stub"\nexit 0\n' > "${_SELF_STUBS}/${_stub}"
    chmod +x "${_SELF_STUBS}/${_stub}"
  done
  unset _stub
  # The builder behind the seam default, under a name that no row re-exports:
  # the live rows hand it to _s15_lead, which never dispatches it.
  _SELF_NO_BUILDER="${WORK}/self-seam/no-builder.sh"
}

# _s15_init — a fresh SELF-15 directory: the case HOME and the 3.x hook file.
# The 3.x templates/.codex/hooks.json, verbatim: it appended to ops/CHANGELOG.md
# and wrote .claude/codex-changelog.* from every Codex session (codexhook, SELF-15c).
_s15_init() {
  _S15="${WORK}/self15"
  rm -rf "$_S15"
  mkdir -p "$_S15/home"
  cat > "$_S15/codex-hooks-3x.json" <<'S15_CDX3_EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "sh -c '[ -f .claude/codex-changelog.$PPID ] || { mkdir -p .claude ops; printf \"%s | codex | tool activity in session\\n\" \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" >> ops/CHANGELOG.md && touch .claude/codex-changelog.$PPID; }'"
          }
        ]
      }
    ]
  }
}
S15_CDX3_EOF
}

# _s15_repo <dir> <ignore-agents:yes|no> — main + checked-out sprint/s15, tracking
# .agents/skills/my-skill/SKILL.md and .claude/commands/my-command.md
_s15_repo() {
  ( mkdir -p "$1" && cd "$1" && export HOME="$_S15/home" GIT_CONFIG_NOSYSTEM=1 && git init -q -b main \
      && git config user.email "probe@triforge.local" && git config user.name "triforge-probe" \
      && mkdir -p ops .agents/skills/my-skill .claude/commands \
      && printf '[roles.builder]\ncli = "claude"\n' > ops/roster.toml \
      && printf 'my skill\n' > .agents/skills/my-skill/SKILL.md && printf 'my command\n' > .claude/commands/my-command.md \
      && { [ "$2" = no ] || printf '/.agents/\n' > .gitignore; } && echo r > README.md \
      && git add -A && git add -f .agents/skills/my-skill/SKILL.md && git commit -qm init \
      && git checkout -q -b sprint/s15 ) >/dev/null 2>&1
}
# _s15_lead <repo> <fake builder> <script> — lead-side steps from <repo> with the
# library sourced, the case's HOME and lease root exported (as _s18_lead does)
_s15_lead() {
  ( cd "$1" && export HOME="$_S15/home" TRIFORGE_LEASE_ROOT="$1.leases" PATH="${_SELF_STUBS}:$PATH" TRIFORGE_TEST_BUILDER="$2" GIT_CONFIG_NOSYSTEM=1 \
      && source "${_SELF_DIR}/invoke-external.sh" 2>/dev/null && {
    _s15_go() { # _s15_go <task> — dispatch an existing lease and wait for its exit record
      local N=0 OUT
      lease_dispatch "$1" "probe task" 60 >/dev/null 2>&1 || { echo "dispatch-failed"; return 1; }
      OUT=$(_ledger_get "$1" output_file 2>/dev/null)
      while [ ! -f "${OUT}.rc" ] && [ "$N" -lt 300 ]; do sleep 0.1; N=$((N + 1)); done
    }
    _s15_snapnames() { # _s15_snapnames <task> — the paths the lead's snapshot of <task> would carry now
      local ROW W A B P T
      ROW=$(_ledger_get_row "$1" worktree admin_dir base_sha provisioned) || return 1
      { IFS= read -r W || true; IFS= read -r A || true; IFS= read -r B || true; IFS= read -r P || true; } <<S15_ROW_EOF
${ROW}
S15_ROW_EOF
      T=$(_lease_tree_of_worktree "$W" "$A" "$B" "$P") || return 1
      git diff --name-only "$B" "$T" | tr '\n' ' '
    }
    eval "$3"
  } ) 2>&1 || true   # the caller reads the output; a case that stops early shows as missing lines
}

# SELF-15b / SELF-15c: the live halves (see the SELF-15 comment in
# scripts/probe-self-tests.sh). `--only SELF-15b,SELF-15c` runs them alone.
_S15_LCAP="live worker leaves no bootstrap residue in its worktree or squash (KTD9)"
_S15_LPROMPT="Create a file named feature.txt in the current directory containing the single word ok. Then reply with exactly one line: Status: DONE"
_s15_residue() { # _s15_residue <worktree> — new or changed bootstrap paths there (ops/, .codex/, .claude/*.local.md, .claude/codex-changelog.*)
  git -C "$1" status --porcelain --untracked-files=all --ignored 2>/dev/null | cut -c4- \
    | grep -E '^(ops/|\.codex/|\.claude/[^/]*\.local\.md$|\.claude/codex-changelog\.)' | tr '\n' ' ' || true
}
# _s15_lease <repo> <task> — carve the lease a live worker runs in, its output
# in <repo>.<task>.lease.txt. The named builder is what opens the SELF seam: an
# empty one closes it, and with no terminal on stdin lease_create then refuses
# (_lead_origin in scripts/lib/roster.sh), so no worktree appears.
_s15_lease() {
  _s15_lead "$1" "$_SELF_NO_BUILDER" "lease_create $2 builder" > "$1.$2.lease.txt"
}
_s15_wt_state() { # _s15_wt_state <worktree> — present or missing
  if [ -e "$1/.git" ]; then echo present; else echo missing; fi
}
# _s15_why <repo> <task> <worktree state> <worker rc> <worker output> — why a
# worker's run shows nothing: the lease log, the worktree before the worker ran,
# and the worker's exit and output. A worker that never started has no output file.
_s15_why() {
  local LOG="no lease log" OUT="no output file, the worker never started"
  if [ -f "$1.$2.lease.txt" ]; then LOG=$(_evidence "$1.$2.lease.txt"); fi
  if [ -f "$5" ]; then OUT=$(_evidence "$5"); OUT=${OUT:-empty}; fi
  printf 'lease_create(%s): %s; worktree before the worker: %s; worker rc=%s, output: %s' "$2" "${LOG:-empty}" "$3" "$4" "$OUT"
}

_s15_live_claude() {
  local ST STC RC=0 RCC=0 W WC RES RESC SQ
  if ! command -v claude >/dev/null 2>&1; then
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "UNAVAILABLE" "claude not on PATH" "live"
    return 0
  fi
  if [ "$CC_LIVE" != 1 ]; then
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "$(_skip_reason)" "gated on CC-02" "live"
    return 0
  fi
  _s15_repo "$_S15/lcc" no
  _s15_lease "$_S15/lcc" m
  _s15_lease "$_S15/lcc" c
  W="$_S15/lcc.leases/m"; WC="$_S15/lcc.leases/c"
  ST=$(_s15_wt_state "$W"); STC=$(_s15_wt_state "$WC")
  ( cd "$W" && PATH="$_S15/live-stubs:$PATH" _lane_run 300 claude -p --plugin-dir "$REPO_ROOT" --model sonnet --permission-mode acceptEdits --output-format text "$_S15_LPROMPT" > "$_S15/lcc-m.txt" 2>&1 ) || RC=$?
  ( cd "$WC" && PATH="$_S15/live-stubs:$PATH" _lane_run 300 env -u TRIFORGE_LEASE_WORKER claude -p --plugin-dir "$REPO_ROOT" --model sonnet --permission-mode acceptEdits --output-format text "$_S15_LPROMPT" > "$_S15/lcc-c.txt" 2>&1 ) || RCC=$?
  RES=$(_s15_residue "$W"); RESC=$(_s15_residue "$WC")
  SQ=$(_s15_lead "$_S15/lcc" "$_SELF_NO_BUILDER" '_s15_snapnames m')
  if [ "$ST" != present ]; then
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "FAIL" "no lease worktree, so no worker ran: $(_s15_why "$_S15/lcc" m "$ST" "$RC" "$_S15/lcc-m.txt")" "live"
  elif [ ! -f "$W/feature.txt" ]; then
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "FAIL" "the worker wrote no feature.txt, so no tool hook ran: $(_s15_why "$_S15/lcc" m "$ST" "$RC" "$_S15/lcc-m.txt")" "live"
  elif [ -z "$RESC" ]; then
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "FAIL" "control without the marker left no residue either — the plugin hooks did not load under --plugin-dir in env -i, so the marker run proves nothing; $(_s15_why "$_S15/lcc" c "$STC" "$RCC" "$_S15/lcc-c.txt")" "live"
  elif [ -n "$RES" ] || [ "${SQ% }" != "feature.txt" ]; then
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "FAIL" "marker run left residue: ${RES:-none}; squash: ${SQ:-<empty>}; control residue: ${RESC}" "live"
  else
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "PASS" "claude -p --plugin-dir <this checkout> --model sonnet under _lane_run (marker builder) in a lease worktree: feature.txt written, no ops/.codex/.claude/*.local.md, squash = feature.txt; control without the marker left: ${RESC% }" "live"
  fi
}

_s15_live_codex() {
  local ST STC RC=0 RCC=0 W WC RES RESC SQ
  if ! command -v codex >/dev/null 2>&1; then
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "UNAVAILABLE" "codex not on PATH" "live"
    return 0
  fi
  if [ "$CDX_LIVE" != 1 ]; then
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "$(_skip_reason)" "gated on CDX-03" "live"
    return 0
  fi
  if [ "${#U29_CDX_FLAGS[@]}" -eq 0 ]; then
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "FAIL" "could not read the codex lane flags (_lease_lane_argv codex) through scripts/invoke-external.sh" "live"
    return 0
  fi
  _s15_repo "$_S15/lcx" no
  _s15_repo "$_S15/lcx3" no
  ( cd "$_S15/lcx" && mkdir -p .codex && cp "$REPO_ROOT/templates/.codex/hooks.json" .codex/hooks.json && git add .codex && git commit -qm "codex hook (4.0 template)" ) >/dev/null 2>&1
  mkdir -p "$_S15/lcx3/.codex" && cp "$_S15/codex-hooks-3x.json" "$_S15/lcx3/.codex/hooks.json"
  ( cd "$_S15/lcx3" && git add .codex && git commit -qm "codex hook (3.x template)" ) >/dev/null 2>&1
  _s15_lease "$_S15/lcx" m
  _s15_lease "$_S15/lcx3" c
  W="$_S15/lcx.leases/m"; WC="$_S15/lcx3.leases/c"
  ST=$(_s15_wt_state "$W"); STC=$(_s15_wt_state "$WC")
  ( cd "$W" && _lane_run 300 codex "${U29_CDX_FLAGS[@]}" --skip-git-repo-check \
      --dangerously-bypass-hook-trust -m "$CDX_MODEL" -c 'model_reasoning_effort="low"' "$_S15_LPROMPT" < /dev/null > "${W}.txt" 2>&1 ) || RC=$?
  ( cd "$WC" && _lane_run 300 codex "${U29_CDX_FLAGS[@]}" --skip-git-repo-check \
      --dangerously-bypass-hook-trust -m "$CDX_MODEL" -c 'model_reasoning_effort="low"' "$_S15_LPROMPT" < /dev/null > "${WC}.txt" 2>&1 ) || RCC=$?
  RES=$(_s15_residue "$W"); RESC=$(_s15_residue "$WC")
  SQ=$(_s15_lead "$_S15/lcx" "$_SELF_NO_BUILDER" '_s15_snapnames m')
  if [ "$ST" != present ]; then
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "FAIL" "no lease worktree, so no worker ran: $(_s15_why "$_S15/lcx" m "$ST" "$RC" "${W}.txt")" "live"
  elif [ ! -f "$W/feature.txt" ]; then
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "FAIL" "the worker wrote no feature.txt, so no tool hook ran: $(_s15_why "$_S15/lcx" m "$ST" "$RC" "${W}.txt")" "live"
  elif [ -z "$RESC" ]; then
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "FAIL" "control (3.x hook) left no residue either — project hooks did not fire with --dangerously-bypass-hook-trust in env -i, so the 4.0 run proves nothing; $(_s15_why "$_S15/lcx3" c "$STC" "$RCC" "${WC}.txt")" "live"
  elif [ -n "$RES" ] || [ "${SQ% }" != "feature.txt" ]; then
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "FAIL" "4.0 hook run left residue: ${RES:-none}; squash: ${SQ:-<empty>}; control residue: ${RESC}" "live"
  else
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "PASS" "codex exec --disable plugins -s workspace-write --dangerously-bypass-hook-trust -m $CDX_MODEL under _lane_run (marker builder) in a lease worktree with the shipped .codex/hooks.json: feature.txt written, no ops/.codex-changelog residue, squash = feature.txt; control with the 3.x hook left: ${RESC% }" "live"
  fi
}

# _s15_live_rows — both rows, or the one --only names; SKIPPED under --self-only.
_s15_live_rows() {
  if [ "$SELF_ONLY" = 1 ]; then
    row "SELF-15b" "claude" "$_S15_LCAP: claude -p" "SKIPPED" "--self-only: live rows are not part of the SELF gate (run the full probe)" "live"
    row "SELF-15c" "codex" "$_S15_LCAP: codex exec" "SKIPPED" "--self-only: live rows are not part of the SELF gate (run the full probe)" "live"
    return 0
  fi
  # stub agy only, so the control run's session start never installs the real agy pack
  mkdir -p "$_S15/live-stubs"
  printf '#!/bin/sh\n# probe stub (SELF-15b): answers the session-start hook without touching the real agy install\necho "0.0.0-probe-stub"\nexit 0\n' > "$_S15/live-stubs/agy"
  chmod +x "$_S15/live-stubs/agy"
  if _want SELF-15b; then _s15_live_claude; fi
  if _want SELF-15c; then _s15_live_codex; fi
}
