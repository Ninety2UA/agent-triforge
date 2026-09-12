#!/usr/bin/env bash
# probe-self-tests.sh — the SELF-* rows of the capability probe (framework
# SCRIPT invariants: roster chain rejection, coordinate.sh composition, the
# adapter env allowlist and its no-push backstop, the R35 boundary note, the
# Status-line parser seam, lease-lane skill discovery per CLI, the
# TRIFORGE_TEST_BUILDER lifecycle, session-start idempotence and the skills
# refresh's destructive paths).
#
# NOT a standalone script: sourced by scripts/probe-capabilities.sh after the
# per-CLI sections, inside the same shell, so it uses the harness's helpers
# (row, _evidence, _scrub, _lane_run, _probe_run, _skip_reason, _s6_record,
# _flat_names, _name_listed), its state (WORK, FIX, REPO_ROOT, LIST12_PROMPT,
# SHIPPED_SKILLS, the *_LIVE / KIMI_AUTH / KIMI_QUOTA gates, TIMEOUT_BIN) and
# its `set -euo pipefail`. Split out of the harness (review finding #17 on
# the v3.3.0 branch) so the harness proper stays the per-CLI probe list.
if [ -z "${WORK:-}" ] || [ -z "${REPO_ROOT:-}" ] || ! declare -F row >/dev/null 2>&1; then
  echo "probe-self-tests.sh: must be sourced by scripts/probe-capabilities.sh (harness state missing)" >&2
  return 2 2>/dev/null || exit 2
fi

# --------------------------------------------------------- Self-verification
# Framework SCRIPT invariants — self-tests against the lease/roster machinery
# and the hook handlers. SELF-01..05, SELF-07, SELF-08 are static (no external
# CLI, no network) and always run; SELF-06 reproduces the lease lane per CLI
# and is gated on each CLI's live gate.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# SELF-01 (R21): resolve_role REJECTS a fallback chain that resolves entirely to
# optional members (no core-trio terminus) — the guard between a misconfigured
# roster and a confusing runtime failure. Expect exit 5 + the terminus message.
_S1_DIR="${WORK}/self-r21"
mkdir -p "${_S1_DIR}/ops"
printf '[roles.tester]\ncli = "opencode"\nfallbacks = ["kimi"]\n' > "${_S1_DIR}/ops/roster.toml"
_S1_RC=0
_S1_ERR=$( ( cd "$_S1_DIR" && source "${_SELF_DIR}/invoke-external.sh" && resolve_role tester ) 2>&1 >/dev/null ) || _S1_RC=$?
if [ "$_S1_RC" -eq 5 ] && printf '%s' "$_S1_ERR" | grep -q "does not terminate at a core-trio member"; then
  row "SELF-01" "claude" "resolve_role rejects an all-optional fallback chain (R21)" "PASS" "exit 5 + terminus message: $(printf '%s' "$_S1_ERR" | _scrub | cut -c1-100)" "static"
else
  row "SELF-01" "claude" "resolve_role rejects an all-optional fallback chain (R21)" "FAIL" "expected exit 5 + terminus message; got rc=${_S1_RC} err=$(printf '%s' "$_S1_ERR" | _scrub | cut -c1-100)" "static"
fi
rm -rf "$_S1_DIR"

# SELF-02: coordinate.sh --dry-run is the composition "verification hook" — it
# must emit the leading /goal line AND, when a live lease ledger exists, the
# lease-resume paragraph. Asserting on it here makes that claim true (previously
# no consumer checked --dry-run output).
_S2_DIR="${WORK}/self-dryrun"
mkdir -p "${_S2_DIR}/ops"
( cd "$_S2_DIR" && git init -q 2>/dev/null ) || true
printf '[lease.probe1]\nstate = "leased"\n' > "${_S2_DIR}/ops/leases.toml"
_S2_OUT=$( ( cd "$_S2_DIR" && bash "${_SELF_DIR}/coordinate.sh" "probe goal" --dry-run ) 2>/dev/null || true )
_S2_GOAL=no;   printf '%s' "$_S2_OUT" | grep -q "^/goal "            && _S2_GOAL=yes
_S2_RESUME=no; printf '%s' "$_S2_OUT" | grep -q "A lease ledger exists" && _S2_RESUME=yes
if [ "$_S2_GOAL" = yes ] && [ "$_S2_RESUME" = yes ]; then
  row "SELF-02" "claude" "coordinate.sh --dry-run emits /goal line + lease-resume paragraph" "PASS" "both markers present in the composed prompt" "static"
else
  row "SELF-02" "claude" "coordinate.sh --dry-run emits /goal line + lease-resume paragraph" "FAIL" "missing marker (goal_line=${_S2_GOAL} resume_para=${_S2_RESUME})" "static"
fi
rm -rf "$_S2_DIR"

# SELF-03 (R35): the env-allowlist isolation IS enforced — _adapter_env scopes
# env vars per adapter, so a planted cross-adapter credential is stripped.
# Assert codex never sees opencode's OPENROUTER_API_KEY / kimi's KIMI_* /
# cursor's CURSOR_API_KEY, and (positive control) opencode DOES see its own.
# Deterministic, no real CLI: `_adapter_env <cli> env` prints the scoped env.
# Runs in a subshell that sources the lib so the probe's own env stays clean.
_S3_FAIL=$( source "${_SELF_DIR}/invoke-external.sh" 2>/dev/null; F=""
  OPENROUTER_API_KEY=planted _adapter_env codex    env 2>/dev/null | grep -q '^OPENROUTER_API_KEY=' && F="${F} codex-saw-OPENROUTER"
  KIMI_TOKEN=planted         _adapter_env codex    env 2>/dev/null | grep -q '^KIMI_TOKEN='         && F="${F} codex-saw-KIMI"
  CURSOR_API_KEY=planted     _adapter_env codex    env 2>/dev/null | grep -q '^CURSOR_API_KEY='     && F="${F} codex-saw-CURSOR"
  OPENROUTER_API_KEY=planted _adapter_env opencode env 2>/dev/null | grep -q '^OPENROUTER_API_KEY=' || F="${F} opencode-missing-OPENROUTER(positive-control)"
  printf '%s' "$F" )
if [ -z "$_S3_FAIL" ]; then
  row "SELF-03" "claude" "_adapter_env strips cross-adapter credentials (R35/KTD-14)" "PASS" "codex env carries no OPENROUTER/KIMI/CURSOR key; opencode carries its own (positive control held)" "static"
else
  row "SELF-03" "claude" "_adapter_env strips cross-adapter credentials (R35/KTD-14)" "FAIL" "env-allowlist leak:${_S3_FAIL}" "static"
fi

# SELF-04 (R35, honest boundary): the OTHER two R35 escape classes are NOT
# confined by design — do not fake them as passing. HOME is forwarded to every
# adapter (the core trio authenticate via HOME-based stores), so a builder CAN
# read credential files under $HOME; and there is no network filter, so egress
# is not blocked. Recorded as INFO so the record matches the corrected KTD-14/R35
# claim in .claude/CLAUDE.md instead of overclaiming confinement the code does
# not provide. The enforced boundary is worktree writes + env-var allowlist +
# prompt confinement (SELF-03 covers the env-var half).
_S4_HOME=$( source "${_SELF_DIR}/invoke-external.sh" 2>/dev/null; _adapter_env codex env 2>/dev/null | grep -q '^HOME=' && echo yes || echo no )
row "SELF-04" "claude" "R35 boundary: credential-store read + network egress are NOT confined (HOME forwarded, no net filter)" "INFO" "HOME reaches builder=${_S4_HOME}; enforced boundary is worktree writes + env-var allowlist + prompt, NOT home-credential read-isolation or egress filtering (see .claude/CLAUDE.md KTD-14)" "static"

# SELF-05 (KTD11): the contract-parsing seam — _lease_parse_status <file>
# reads the builder's final-report `Status:` line and prints DONE |
# DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT, or MISSING when the report
# carries no such line — the token lease_collect keys "report missing" on (a
# clean exit with no report is never review-ready). The three plan fixtures
# (Status: DONE / no line / Status: BLOCKED) plus the other two tokens.
_S5_HAS=$( source "${_SELF_DIR}/invoke-external.sh" 2>/dev/null; declare -F _lease_parse_status >/dev/null 2>&1 && echo yes || echo no )
if [ "$_S5_HAS" = yes ]; then
  _S5_DIR="${WORK}/self05"
  mkdir -p "$_S5_DIR"
  printf 'did the work\n\nStatus: DONE\nCommits: none\n' > "$_S5_DIR/done.txt"
  printf 'did the work but wrote no report line\n' > "$_S5_DIR/none.txt"
  printf 'could not proceed\n\nStatus: BLOCKED\nReason: probe\n' > "$_S5_DIR/blocked.txt"
  printf 'did the work\n\nStatus: DONE_WITH_CONCERNS\nConcerns: one\n' > "$_S5_DIR/concerns.txt"
  printf 'need input\n\nStatus: NEEDS_CONTEXT\nQuestion: probe\n' > "$_S5_DIR/needs.txt"
  # Decoys: CLIs that echo the prompt (codex exec, on stderr) put the contract
  # template `Status: DONE | DONE_WITH_CONCERNS | ...` into the captured file;
  # it must never parse as DONE, and a real BLOCKED must survive a later echo.
  printf 'echo of the prompt:\n  Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT\n  Discoveries for later tasks: <list, or None>\nno report written\n' > "$_S5_DIR/decoy.txt"
  printf 'Status: BLOCKED\nFiles changed: none\n\n  Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT\n' > "$_S5_DIR/blocked-then-decoy.txt"
  _S5_OUT=$( source "${_SELF_DIR}/invoke-external.sh" 2>/dev/null
    for f in done none blocked concerns needs decoy blocked-then-decoy; do
      printf '%s=' "$f"; _lease_parse_status "$_S5_DIR/$f.txt" 2>/dev/null | tr -d '[:space:]'; printf '\n'
    done )
  _S5_FAIL=""
  printf '%s\n' "$_S5_OUT" | grep -q '^done=DONE$'                     || _S5_FAIL="$_S5_FAIL done"
  printf '%s\n' "$_S5_OUT" | grep -q '^none=MISSING$'                  || _S5_FAIL="$_S5_FAIL none"
  printf '%s\n' "$_S5_OUT" | grep -q '^blocked=BLOCKED$'               || _S5_FAIL="$_S5_FAIL blocked"
  printf '%s\n' "$_S5_OUT" | grep -q '^concerns=DONE_WITH_CONCERNS$'   || _S5_FAIL="$_S5_FAIL concerns"
  printf '%s\n' "$_S5_OUT" | grep -q '^needs=NEEDS_CONTEXT$'           || _S5_FAIL="$_S5_FAIL needs"
  printf '%s\n' "$_S5_OUT" | grep -q '^decoy=MISSING$'                 || _S5_FAIL="$_S5_FAIL decoy-template-read-as-status"
  printf '%s\n' "$_S5_OUT" | grep -q '^blocked-then-decoy=BLOCKED$'    || _S5_FAIL="$_S5_FAIL blocked-lost-to-decoy"
  if [ -z "$_S5_FAIL" ]; then
    row "SELF-05" "claude" "_lease_parse_status reads the Status: contract line (KTD11 seam)" "PASS" "Status: DONE -> DONE; no Status line -> MISSING; Status: BLOCKED -> BLOCKED (DONE_WITH_CONCERNS / NEEDS_CONTEXT also parsed); the echoed contract template -> MISSING, and a real BLOCKED survives a later echo" "static"
  else
    row "SELF-05" "claude" "_lease_parse_status reads the Status: contract line (KTD11 seam)" "FAIL" "mismatch:${_S5_FAIL}; parser output: $(printf '%s' "$_S5_OUT" | tr '\n' ' ' | cut -c1-120)" "static"
  fi
  rm -rf "$_S5_DIR"
else
  row "SELF-05" "claude" "_lease_parse_status reads the Status: contract line (KTD11 seam)" "FAIL" "_lease_parse_status is not defined by scripts/invoke-external.sh — lease_collect cannot read the typed report (KTD11)" "static"
fi

# SELF-06 (KTD7 / R9): lease-lane skill discovery per CLI. A lease worktree
# gets a fresh .agents/skills/ copy (_lease_provision_skills) and the builder
# runs under the env -i allowlist (KTD-14). Reproduce exactly that: a linked
# worktree of the fixture under TMPDIR, the shipped skills provisioned, each
# CLI asked in its own invocation form under env -i HOME PATH TMPDIR — one
# row per CLI, gated on that CLI's live gate (kimi: PENDING-AUTH while
# KIMI-05 is AUTH-FAIL). PASS when the probe skill tf-agents-skill (inherited
# from the fixture commit, exactly like a user-added skill) is listed; the
# shipped-name coverage rides in the evidence. The claude lane is the honest
# exception: .agents/skills/ is not a Claude path, so its row reports what
# the plugin path delivers into a lease worktree.
_s6_record() { # _s6_record <id> <cli> <capability> <file> <note>
  local ID=$1 CLI=$2 CAP=$3 F=$4 NOTE=$5 MISS N_PRESENT
  MISS=$(_names_missing "$F")
  # shellcheck disable=SC2086
  N_PRESENT=$((SHIPPED_COUNT - $(_count_words $MISS)))
  if _name_listed "$F" tf-agents-skill; then
    row "$ID" "$CLI" "$CAP" "PASS" "tf-agents-skill listed from the lease worktree; shipped names present ${N_PRESENT}/${SHIPPED_COUNT}${MISS:+ (missing: ${MISS})} (${NOTE})" "live"
  else
    row "$ID" "$CLI" "$CAP" "FAIL" "tf-agents-skill NOT listed; shipped names present ${N_PRESENT}/${SHIPPED_COUNT}${MISS:+ (missing: ${MISS})} (${NOTE}); $(_evidence "$F")" "live"
  fi
}
_S6_WT="$WORK/self06-wt"
_S6_OK=0
if git -C "$FIX" worktree add -q "$_S6_WT" -b probe/self-06 >/dev/null 2>&1; then
  mkdir -p "$_S6_WT/.agents/skills"
  for s in $SHIPPED_SKILLS; do
    mkdir -p "$_S6_WT/.agents/skills/$s"
    cp -R "$REPO_ROOT/skills/$s/." "$_S6_WT/.agents/skills/$s/"
  done
  _S6_OK=1
fi
_S6_CAP="Lease-lane discovery under env -i from a TMPDIR worktree"
if [ "$_S6_OK" = 1 ]; then
  # agy — /skills answers headless without a model call (the AGY-14 form)
  if ! command -v agy >/dev/null 2>&1; then
    row "SELF-06a" "agy" "$_S6_CAP: agy /skills" "UNAVAILABLE" "agy not on PATH" "live"
  elif [ "$AGY_LIVE" != 1 ]; then
    row "SELF-06a" "agy" "$_S6_CAP: agy /skills" "$(_skip_reason)" "gated on AGY-04" "live"
  else
    O="$WORK/self06-agy.txt"; T="$WORK/self06-agy-text.txt"
    (cd "$_S6_WT" && _lane_run 60 agy --add-dir "$_S6_WT" -p "/skills" > "$O" 2>&1) || true
    _agy_text "$O" "$T"
    _s6_record "SELF-06a" "agy" "$_S6_CAP: agy /skills" "$T" "agy --add-dir <wt> -p /skills"
  fi
  # codex — exec, read-only, low effort
  if ! command -v codex >/dev/null 2>&1; then
    row "SELF-06b" "codex" "$_S6_CAP: codex exec skill listing" "UNAVAILABLE" "codex not on PATH" "live"
  elif [ "$CDX_LIVE" != 1 ]; then
    row "SELF-06b" "codex" "$_S6_CAP: codex exec skill listing" "$(_skip_reason)" "gated on CDX-03" "live"
  else
    O="$WORK/self06-cdx.txt"; LAST="$WORK/self06-cdx-last.txt"
    (cd "$_S6_WT" && _lane_run 240 codex exec --skip-git-repo-check -s read-only -c 'approval_policy="never"' -m "$CDX_MODEL" -c 'model_reasoning_effort="low"' -o "$LAST" "$LIST12_PROMPT" < /dev/null > "$O" 2>&1) || true
    if [ -s "$LAST" ]; then
      _s6_record "SELF-06b" "codex" "$_S6_CAP: codex exec skill listing" "$LAST" "codex exec -s read-only -m $CDX_MODEL"
    else
      _s6_record "SELF-06b" "codex" "$_S6_CAP: codex exec skill listing" "$O" "codex exec -s read-only -m $CDX_MODEL; no last-message file"
    fi
  fi
  # opencode — run --format json on the GLM pick
  if ! command -v opencode >/dev/null 2>&1; then
    row "SELF-06c" "opencode" "$_S6_CAP: opencode run skill listing" "UNAVAILABLE" "opencode not on PATH" "live"
  elif [ "$OC_LIVE" != 1 ]; then
    row "SELF-06c" "opencode" "$_S6_CAP: opencode run skill listing" "$(_skip_reason)" "gated on OC-03" "live"
  else
    O="$WORK/self06-oc.txt"
    (cd "$_S6_WT" && _lane_run 240 opencode run --format json -m "$OC_GLM" "$LIST12_PROMPT" > "$O" 2>&1) || true
    _s6_record "SELF-06c" "opencode" "$_S6_CAP: opencode run skill listing" "$O" "opencode run --format json -m $OC_GLM"
  fi
  # cursor — -p --trust on the Grok pick
  if [ -z "$CUR_BIN" ]; then
    row "SELF-06d" "cursor" "$_S6_CAP: cursor -p skill listing" "UNAVAILABLE" "no Cursor binary on PATH" "live"
  elif [ "$CUR_LIVE" != 1 ]; then
    row "SELF-06d" "cursor" "$_S6_CAP: cursor -p skill listing" "$(_skip_reason)" "gated on CUR-04" "live"
  else
    O="$WORK/self06-cur.txt"
    (cd "$_S6_WT" && _lane_run 240 "$CUR_BIN" -p --trust --output-format text --model "$CUR_GROK" "$LIST12_PROMPT" > "$O" 2>&1) || true
    _s6_record "SELF-06d" "cursor" "$_S6_CAP: cursor -p skill listing" "$O" "$(basename "$CUR_BIN") -p --trust --model $CUR_GROK"
  fi
  # kimi — -p (PENDING-AUTH while KIMI-05 is AUTH-FAIL)
  if ! command -v kimi >/dev/null 2>&1; then
    row "SELF-06e" "kimi" "$_S6_CAP: kimi -p skill listing" "UNAVAILABLE" "kimi not on PATH" "live"
  elif [ "$KIMI_LIVE" != 1 ] && [ "$KIMI_QUOTA" = 1 ]; then
    row "SELF-06e" "kimi" "$_S6_CAP: kimi -p skill listing" "SKIPPED-GATED" "KIMI-05 is QUOTA-FAIL (usage quota exhausted this cycle) — re-run after the refresh" "live"
  elif [ "$KIMI_LIVE" != 1 ] && [ "$KIMI_AUTH" = 1 ]; then
    row "SELF-06e" "kimi" "$_S6_CAP: kimi -p skill listing" "PENDING-AUTH" "KIMI-05 is AUTH-FAIL — after \`kimi login\` run from a worktree carrying .agents/skills/: env -i HOME=\$HOME PATH=\$PATH TMPDIR=\$TMPDIR kimi -p \"<list the shipped skill names>\"" "live"
  elif [ "$KIMI_LIVE" != 1 ]; then
    row "SELF-06e" "kimi" "$_S6_CAP: kimi -p skill listing" "$(_skip_reason)" "gated on KIMI-05" "live"
  else
    O="$WORK/self06-kimi.txt"
    (cd "$_S6_WT" && _lane_run 240 env KIMI_DISABLE_TELEMETRY=1 kimi --output-format text -p "$LIST12_PROMPT" > "$O" 2>&1) || true
    _s6_record "SELF-06e" "kimi" "$_S6_CAP: kimi -p skill listing" "$O" "kimi --output-format text -p"
  fi
  # claude — the plugin path, not .agents/skills (CC-07b)
  if ! command -v claude >/dev/null 2>&1; then
    row "SELF-06f" "claude" "$_S6_CAP: claude -p skill listing (plugin path)" "UNAVAILABLE" "claude not on PATH" "live"
  elif [ "$CC_LIVE" != 1 ]; then
    row "SELF-06f" "claude" "$_S6_CAP: claude -p skill listing (plugin path)" "$(_skip_reason)" "gated on CC-02" "live"
  else
    O="$WORK/self06-cc.txt"
    (cd "$_S6_WT" && _lane_run 240 claude -p --model sonnet --output-format text "$LIST12_PROMPT" > "$O" 2>&1) || true
    _s6_record "SELF-06f" "claude" "$_S6_CAP: claude -p skill listing (plugin path)" "$O" "claude -p --model sonnet; .agents/skills is not a Claude path — names come from the installed plugin"
  fi
  git -C "$FIX" worktree remove --force "$_S6_WT" >/dev/null 2>&1 || rm -rf "$_S6_WT"
  git -C "$FIX" branch -D probe/self-06 >/dev/null 2>&1 || true
else
  for r in "SELF-06a:agy" "SELF-06b:codex" "SELF-06c:opencode" "SELF-06d:cursor" "SELF-06e:kimi" "SELF-06f:claude"; do
    row "${r%%:*}" "${r#*:}" "$_S6_CAP: ${r#*:}" "FAIL" "git worktree add failed in the fixture — no lease-shaped worktree to probe" "live"
  done
fi

# SELF-07 (KTD11): the TRIFORGE_TEST_BUILDER lifecycle through lease_create /
# lease_dispatch / lease_collect in a throwaway repo with its own lease root.
# Four fake builders: a report ending "Status: DONE" must land state=review
# (rc 0); a clean exit with NO Status line is "report missing" — lease_collect
# returns 80 and moves the lease back to leased (same builder + worktree, one
# re-dispatch allowed), never review-ready, and a SECOND miss escalates;
# a builder that only echoes the contract template (as codex exec echoes the
# prompt) is report-missing too; "Status: BLOCKED" must land state=escalated. The throwaway repo carries ops/roster.toml with
# builder = claude so the lease is assigned the way a default roster would
# assign it (the fake builder replaces the adapter, not the resolution).
# FAIL outright when the parser is absent: without it lease_collect routes
# every rc 0 to review and the assertions would measure the wrong thing.
if [ "$_S5_HAS" = yes ]; then
  _S7="${WORK}/self07"
  mkdir -p "$_S7/repo/ops"
  printf '[roles.builder]\ncli = "claude"\n' > "$_S7/repo/ops/roster.toml"
  ( cd "$_S7/repo" && git init -q && git config user.email "probe@triforge.local" && git config user.name "triforge-probe" && echo "lease probe" > README.md && git add README.md ops/roster.toml && git commit -qm init ) >/dev/null 2>&1
  printf '#!/bin/sh\necho "work done"\necho "Status: DONE"\n' > "$_S7/fb-done.sh"
  printf '#!/bin/sh\necho "work done, no report line"\n' > "$_S7/fb-none.sh"
  printf '#!/bin/sh\necho "Status: BLOCKED"\necho "reason: probe"\n' > "$_S7/fb-blocked.sh"
  printf '#!/bin/sh\necho "echo of the prompt:"\necho "  Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT"\necho "  Discoveries for later tasks: <list, or None>"\necho "no report written"\n' > "$_S7/fb-echo.sh"
  # A stream-shaped builder (the kimi lane's stream-json): the report lives
  # inside a JSON string, so the lease lane must extract prose before parsing.
  cat > "$_S7/fb-stream.sh" <<'EOF'
#!/bin/sh
printf '%s\n' '{"role":"assistant","id":"m1","content":"working..."}'
printf '%s\n' '{"role":"assistant","id":"m2","content":"Done.\n\nStatus: DONE\nFiles changed: a.txt\nTests: none\nConcerns: None\nDiscoveries for later tasks: None\n"}'
EOF
  chmod +x "$_S7"/fb-*.sh
  _S7_RES=$( cd "$_S7/repo" && export TRIFORGE_LEASE_ROOT="$_S7/leases" && source "${_SELF_DIR}/invoke-external.sh" 2>/dev/null && {
    _s7_case() { # _s7_case <task> <fake-builder>
      local T=$1 S=$2 OUT RC=0 ST N=0
      export TRIFORGE_TEST_BUILDER="$S"
      lease_create "$T" builder >/dev/null 2>&1 || { printf '%s:create-failed\n' "$T"; return 0; }
      lease_dispatch "$T" "probe task: report only" 60 >/dev/null 2>&1 || { printf '%s:dispatch-failed\n' "$T"; return 0; }
      OUT=$(_ledger_get "$T" output_file 2>/dev/null)
      while [ ! -f "${OUT}.rc" ] && [ "$N" -lt 300 ]; do sleep 0.1; N=$((N + 1)); done
      lease_collect "$T" >/dev/null 2>&1 || RC=$?
      ST=$(_ledger_get "$T" state 2>/dev/null)
      printf '%s:rc=%s:state=%s\n' "$T" "$RC" "$ST"
    }
    _s7_case s7done "$_S7/fb-done.sh"
    _s7_case s7none "$_S7/fb-none.sh"
    _s7_case s7blocked "$_S7/fb-blocked.sh"
    _s7_case s7echo "$_S7/fb-echo.sh"
    # stream lane: re-lease the task as kimi (the seam replaces the CLI, not
    # the lane), so _lease_extract_stream runs on the captured JSON stream.
    printf '[roles.builder]\ncli = "kimi"\nfallbacks = ["claude"]\n[members.kimi]\nenabled = true\n' > ops/roster.toml
    if command -v kimi >/dev/null 2>&1; then
      _s7_case s7stream "$_S7/fb-stream.sh"
    else
      printf 's7stream:skipped-no-kimi-binary\n'
    fi
    # report-missing recovery: the s7none lease is back in leased — one
    # re-dispatch of the same builder in the same worktree, then a second
    # clean miss must escalate (never review).
    _s7_again() { # _s7_again <task> <fake-builder> <label>
      local T=$1 S=$2 L=$3 OUT RC=0 N=0
      export TRIFORGE_TEST_BUILDER="$S"
      lease_dispatch "$T" "probe task: previous run ended without a report" 60 >/dev/null 2>&1 || { printf '%s:dispatch-failed:state=%s\n' "$L" "$(_ledger_get "$T" state 2>/dev/null)"; return 0; }
      OUT=$(_ledger_get "$T" output_file 2>/dev/null)
      while [ ! -f "${OUT}.rc" ] && [ "$N" -lt 300 ]; do sleep 0.1; N=$((N + 1)); done
      lease_collect "$T" >/dev/null 2>&1 || RC=$?
      printf '%s:rc=%s:state=%s:misses=%s\n' "$L" "$RC" "$(_ledger_get "$T" state 2>/dev/null)" "$(_ledger_get "$T" report_missing_count 2>/dev/null)"
    }
    _s7_again s7none "$_S7/fb-none.sh" s7none2
  } 2>/dev/null )
  _S7_FAIL=""
  printf '%s\n' "$_S7_RES" | grep -q '^s7done:rc=0:state=review$'                 || _S7_FAIL="$_S7_FAIL done"
  printf '%s\n' "$_S7_RES" | grep -q '^s7none:rc=80:state=leased$'                || _S7_FAIL="$_S7_FAIL report-missing"
  printf '%s\n' "$_S7_RES" | grep -qE '^s7blocked:rc=[0-9]+:state=escalated$'     || _S7_FAIL="$_S7_FAIL blocked"
  printf '%s\n' "$_S7_RES" | grep -q '^s7echo:rc=80:state=leased$'                || _S7_FAIL="$_S7_FAIL echoed-template-read-as-report"
  printf '%s\n' "$_S7_RES" | grep -qE '^s7none2:rc=[0-9]+:state=escalated:misses=2$' || _S7_FAIL="$_S7_FAIL second-miss-not-escalated"
  printf '%s\n' "$_S7_RES" | grep -qE '^s7stream:(rc=0:state=review|skipped-no-kimi-binary)$' || _S7_FAIL="$_S7_FAIL stream-lane-report-not-extracted"
  if [ -z "$_S7_FAIL" ]; then
    row "SELF-07" "claude" "TRIFORGE_TEST_BUILDER lifecycle: DONE -> review; no Status line -> leased + rc 80 (re-dispatch once), echoed template -> report-missing, second miss -> escalated; BLOCKED -> escalated (KTD11)" "PASS" "$(printf '%s' "$_S7_RES" | tr '\n' ' ')" "static"
  else
    row "SELF-07" "claude" "TRIFORGE_TEST_BUILDER lifecycle: DONE -> review; no Status line -> leased + rc 80 (re-dispatch once), echoed template -> report-missing, second miss -> escalated; BLOCKED -> escalated (KTD11)" "FAIL" "mismatch:${_S7_FAIL}; got: $(printf '%s' "$_S7_RES" | tr '\n' ' ' | cut -c1-160)" "static"
  fi
  rm -rf "$_S7"
else
  row "SELF-07" "claude" "TRIFORGE_TEST_BUILDER lifecycle: DONE -> review; no Status line -> leased + rc 80 (re-dispatch once), echoed template -> report-missing, second miss -> escalated; BLOCKED -> escalated (KTD11)" "FAIL" "_lease_parse_status is not defined by scripts/invoke-external.sh, so lease_collect cannot route on the typed report; run once it exists: TRIFORGE_LEASE_ROOT=<tmp> TRIFORGE_TEST_BUILDER=<fake-builder.sh> lease_create t builder && lease_dispatch t \"probe\" 60 && lease_collect t — expect review / rc 80 + leased / escalated for DONE / no line / BLOCKED" "static"
fi

# SELF-08 (KTD7 / KTD8): session-start idempotence. hooks/handlers/session-
# start.sh runs twice in a throwaway project with CLAUDE_PLUGIN_ROOT pointing
# at this checkout, a throwaway HOME (no user-tier state is read or written —
# R18) and a stub `agy` first on PATH (answers `plugin list` / `agents` /
# --version so no real agy install is touched). The second run must exit 0 and
# print ZERO lines starting with "session-start:" — every one-time action
# (skills refresh + stamp, Codex file move, pack install + stamp) announces
# itself with that prefix, so a repeat announcement is a non-idempotent step.
_S8="${WORK}/self08"
mkdir -p "$_S8/proj" "$_S8/bin" "$_S8/home"
cat > "$_S8/bin/agy" <<'EOF'
#!/bin/sh
# probe stub (SELF-08): answers the session-start hook without touching the real agy install
case "${1:-}" in
  --version) echo "0.0.0-probe-stub" ;;
  plugin) case "${2:-}" in list) echo "agent-triforge" ;; *) : ;; esac ;;
  agents) printf '%s\n' codebase-analyst architecture-reviewer targeted-researcher documentation-writer ;;
  *) : ;;
esac
exit 0
EOF
chmod +x "$_S8/bin/agy"
( cd "$_S8/proj" && git init -q 2>/dev/null ) || true
_S8_OUT1=$( cd "$_S8/proj" && HOME="$_S8/home" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" PATH="$_S8/bin:$PATH" bash "$REPO_ROOT/hooks/handlers/session-start.sh" 2>&1 ); _S8_RC1=$?
_S8_OUT2=$( cd "$_S8/proj" && HOME="$_S8/home" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" PATH="$_S8/bin:$PATH" bash "$REPO_ROOT/hooks/handlers/session-start.sh" 2>&1 ); _S8_RC2=$?
_S8_N1=$(printf '%s\n' "$_S8_OUT1" | grep -c '^session-start:' || true)
_S8_N2=$(printf '%s\n' "$_S8_OUT2" | grep -c '^session-start:' || true)
if [ "$_S8_RC2" -eq 0 ] && [ "$_S8_N2" -eq 0 ]; then
  row "SELF-08" "claude" "session-start.sh is idempotent (second run prints zero session-start: lines)" "PASS" "run1 rc=${_S8_RC1} session-start: lines=${_S8_N1}; run2 rc=${_S8_RC2} lines=0 (throwaway project + HOME, stub agy on PATH, CLAUDE_PLUGIN_ROOT=this checkout)" "static"
else
  row "SELF-08" "claude" "session-start.sh is idempotent (second run prints zero session-start: lines)" "FAIL" "run1 rc=${_S8_RC1} session-start: lines=${_S8_N1}; run2 rc=${_S8_RC2} lines=${_S8_N2}: $(printf '%s\n' "$_S8_OUT2" | grep '^session-start:' | head -3 | tr '\n' ' ' | _scrub | cut -c1-160)" "static"
fi
rm -rf "$_S8/proj" "$_S8/home"   # keep $_S8/bin (the stub agy) for SELF-08b; removed there

# SELF-08b (KTD7 / CWE-59): the two destructive paths of the skills refresh.
# (a) Retirement: an OLDER stamp naming a skill that no longer ships, with that
#     directory present, must be removed on the version bump — while every
#     shipped directory and a foreign (unstamped) user directory survive.
# (b) Symlinked ancestor: with .agents -> a directory OUTSIDE the project the
#     refresh must leave the target untouched (no rm -rf, no copies, no stamp).
_S8B="${WORK}/self08b"
mkdir -p "$_S8B/proj/.agents/skills/old-fake-skill" "$_S8B/proj/.agents/skills/my-own-skill" "$_S8B/link/target/skills/codebase-mapping" "$_S8B/link/proj" "$_S8B/home"
printf 'version=0.0.1-probe\nskills=old-fake-skill,codebase-mapping\n' > "$_S8B/proj/.agents/skills/.triforge-plugin-version"
echo "user skill" > "$_S8B/proj/.agents/skills/my-own-skill/SKILL.md"
echo "old" > "$_S8B/proj/.agents/skills/old-fake-skill/SKILL.md"
echo "marker" > "$_S8B/link/target/skills/codebase-mapping/USER-MARKER.txt"
ln -s "$_S8B/link/target" "$_S8B/link/proj/.agents"
( cd "$_S8B/proj" && git init -q 2>/dev/null; cd "$_S8B/link/proj" && git init -q 2>/dev/null ) || true
_S8B_OUT=$( cd "$_S8B/proj" && HOME="$_S8B/home" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" PATH="$_S8/bin:$PATH" bash "$REPO_ROOT/hooks/handlers/session-start.sh" 2>&1 ); _S8B_RC=$?
_S8B_FAIL=""
[ ! -e "$_S8B/proj/.agents/skills/old-fake-skill" ]                 || _S8B_FAIL="$_S8B_FAIL retired-dir-still-present"
[ -f "$_S8B/proj/.agents/skills/my-own-skill/SKILL.md" ]            || _S8B_FAIL="$_S8B_FAIL user-dir-removed"
[ "$(ls -d "$_S8B"/proj/.agents/skills/*/ 2>/dev/null | wc -l | tr -d ' ')" -eq "$(( $(printf '%s\n' $SHIPPED_SKILLS | grep -c .) + 1 ))" ] || _S8B_FAIL="$_S8B_FAIL shipped-count($(ls -d "$_S8B"/proj/.agents/skills/*/ 2>/dev/null | wc -l | tr -d ' ')-incl-user)"
printf '%s\n' "$_S8B_OUT" | grep -q 'retired' || _S8B_FAIL="$_S8B_FAIL no-retired-notice"
[ "$_S8B_RC" -eq 0 ] || _S8B_FAIL="$_S8B_FAIL rc=${_S8B_RC}"
_S8B_OUT2=$( cd "$_S8B/link/proj" && HOME="$_S8B/home" CLAUDE_PLUGIN_ROOT="$REPO_ROOT" PATH="$_S8/bin:$PATH" bash "$REPO_ROOT/hooks/handlers/session-start.sh" 2>&1 ); _S8B_RC2=$?
[ -f "$_S8B/link/target/skills/codebase-mapping/USER-MARKER.txt" ]  || _S8B_FAIL="$_S8B_FAIL symlink-target-marker-deleted"
[ ! -e "$_S8B/link/target/skills/.triforge-plugin-version" ]        || _S8B_FAIL="$_S8B_FAIL symlink-target-stamped"
[ "$(ls -d "$_S8B"/link/target/skills/*/ 2>/dev/null | wc -l | tr -d ' ')" -eq 1 ] || _S8B_FAIL="$_S8B_FAIL symlink-target-written($(ls -d "$_S8B"/link/target/skills/*/ 2>/dev/null | wc -l | tr -d ' ')-dirs)"
printf '%s\n' "$_S8B_OUT2" | grep -qi 'symlink' || _S8B_FAIL="$_S8B_FAIL no-symlink-notice"
[ "$_S8B_RC2" -eq 0 ] || _S8B_FAIL="$_S8B_FAIL link-rc=${_S8B_RC2}"
if [ -z "$_S8B_FAIL" ]; then
  row "SELF-08b" "claude" "skills refresh: retires a stamp-listed skill that no longer ships, keeps user dirs; a symlinked .agents ancestor is left untouched (KTD7, CWE-59)" "PASS" "old-fake-skill removed + notice; my-own-skill kept; shipped set present; symlinked target: marker kept, no stamp, no copies" "static"
else
  row "SELF-08b" "claude" "skills refresh: retires a stamp-listed skill that no longer ships, keeps user dirs; a symlinked .agents ancestor is left untouched (KTD7, CWE-59)" "FAIL" "mismatch:${_S8B_FAIL}; run1: $(printf '%s\n' "$_S8B_OUT" | grep '^session-start:' | head -2 | tr '\n' ' ' | _scrub | cut -c1-120)" "static"
fi
rm -rf "$_S8B" "$_S8"

# SELF-09 (CS1 / KTD11): the no-push backstop is mechanical. Under the lease
# env allowlist (_adapter_env) every git in the builder's process tree sees
# core.hooksPath -> scripts/lease-git-hooks (pre-push refuses) and
# url.*.pushInsteadOf -> no-push://, so a push fails whichever remote it names
# while reads keep working. Throwaway repo with a bare remote; the remote must
# not receive the commit.
_S9="${WORK}/self09"
mkdir -p "$_S9/repo"; git init -q --bare "$_S9/remote.git" 2>/dev/null
( cd "$_S9/repo" && git init -q && git config user.email "probe@triforge.local" && git config user.name "triforge-probe" && echo x > README.md && git add README.md && git commit -qm init && git remote add origin "$_S9/remote.git" && git push -q -u origin HEAD 2>/dev/null && echo y > y.txt && git add y.txt && git commit -qm second ) >/dev/null 2>&1
_S9_OUT=$( source "${_SELF_DIR}/invoke-external.sh" 2>/dev/null
  P1=0; _adapter_env claude git -C "$_S9/repo" push origin HEAD >/dev/null 2>"$_S9/push1.err" || P1=$?
  P2=0; _adapter_env claude git -C "$_S9/repo" push "$_S9/remote.git" HEAD >/dev/null 2>"$_S9/push2.err" || P2=$?
  S=0;  _adapter_env claude git -C "$_S9/repo" status --short >/dev/null 2>&1 || S=$?
  printf 'push-name=%s push-path=%s status=%s hook=%s\n' "$P1" "$P2" "$S" "$(grep -c 'git push is blocked' "$_S9/push1.err" "$_S9/push2.err" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')" )
_S9_REMOTE=$(git --git-dir="$_S9/remote.git" rev-list --count HEAD 2>/dev/null || echo "?")
if printf '%s' "$_S9_OUT" | grep -qE '^push-name=[1-9][0-9]* push-path=[1-9][0-9]* status=0 hook=[1-9]' && [ "$_S9_REMOTE" = "1" ]; then
  row "SELF-09" "claude" "lease env blocks git push mechanically (pre-push hook + no-push:// URL rewrite), reads untouched (CS1/KTD11)" "PASS" "$_S9_OUT; bare remote still at 1 commit" "static"
else
  row "SELF-09" "claude" "lease env blocks git push mechanically (pre-push hook + no-push:// URL rewrite), reads untouched (CS1/KTD11)" "FAIL" "$_S9_OUT; remote commits=$_S9_REMOTE (expected 1)" "static"
fi
rm -rf "$_S9"

