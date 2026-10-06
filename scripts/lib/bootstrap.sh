#!/usr/bin/env bash
# scripts/lib/bootstrap.sh — triforge_bootstrap (KTD11, R37): the project bootstrap (ops/ skeleton, digest-stamped .agents/skills refresh, per-CLI template copies, the Antigravity agent pack, the plugin-root pointer) as one helper that the session-start hook, at-setup and the at-build / at-review preambles all call
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/roster.sh and before scripts/lib/lease-wait.sh.
# It calls _lead_only (common.sh) and _cursor_bin (cursor.sh), resolved at call
# time; nothing runs at source time but assignments and function definitions.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/bootstrap.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# triforge_bootstrap (KTD11, R37) — bootstrap is a primitive, the hook a trigger
# ---------------------------------------------------------------------------
#
# Until 4.0 the session-start hook did this work inline, so a project was set
# up only once a Claude Code session had run the plugin's hooks. A Codex lead
# runs plugin hooks only after the user trusts them (CDX-16), so the work lives
# here: hooks/handlers/session-start.sh calls it on every session start, and
# at-setup, at-build and at-review call it from their preambles. Every step is
# copy-if-absent or version/digest-gated, so a call on a bootstrapped project
# writes nothing and prints nothing.
#
# triforge_bootstrap [--prefix <text>]
#   The project is the current directory, as it always was for the hook; the
#   plugin is the loader's resolved root (${_TRIFORGE_PLUGIN_ROOT}). Steps:
#     1. ops/ skeleton (_tb_ops) — only while ops/ does not exist.
#     2. .agents/skills/ (_tb_skills) — the portable skills, through
#        scripts/lib/skills-sync.py and its content-digest stamp (KTD12).
#     3. The Antigravity agent pack (_tb_agy_pack) and
#        .antigravity/settings.json.
#     4. Per-CLI files, copy-if-absent: .codex/ (_tb_codex: the one-time 3.x
#        migrations and the symlink guard), then .opencode/, .kimi-code/ and
#        .cursor/ for the optional CLIs installed here (_tb_optional_clis), and
#        ops/roster.toml.
#     5. The plugin-root pointer (_tb_pointer).
#   stdout: nothing. stderr: one notice per line, each starting with <text>
#   (default "triforge_bootstrap: "; the hook passes "session-start: " and
#   splices the lines into its orientation). A notice names a step that acted,
#   or a state left alone on purpose, repeated until it changes.
#   rc 0  every step ran
#      45 refused: the worker marker or a lease root (one stderr line from
#         _lead_only, nothing written)
#      64 usage
#      80 degraded: a step could not finish — a write failed, the skills
#         refresh failed or timed out, the agy pack install failed, or the
#         pointer could not be written or sits where the locator refuses it.
#         The notices say which; the next call retries.
# Host: `_lead_only triforge_bootstrap --any-host` — the worker marker and the
# lease root refuse; the lead host check (R38) does not run. The hook (a Claude
# Code session, whichever CLI the roster names as lead), a Codex lead's tool
# shell and a person at a terminal all call it, and every write is
# project-local and copy-if-absent, so no lead-owned state is at stake.
# Bash 3.2 and zsh: no arrays, no globs (zsh aborts the caller on a pattern
# that matches nothing), no unquoted word splitting, printf for any text that
# is not this file's own.
triforge_bootstrap() {
  local _TB_PREFIX="triforge_bootstrap: " _TB_DEGRADED=0 _TB_ROOT="" _TB_TIMEOUT=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --prefix)
        if [ "$#" -lt 2 ]; then
          echo "triforge_bootstrap: usage: triforge_bootstrap [--prefix <text>]" >&2
          return 64
        fi
        _TB_PREFIX=$2
        shift 2
        ;;
      *)
        printf 'triforge_bootstrap: usage: triforge_bootstrap [--prefix <text>] (unknown argument %s)\n' "$1" >&2
        return 64
        ;;
    esac
  done
  _lead_only triforge_bootstrap --any-host || return $?
  _TB_ROOT=$_TRIFORGE_PLUGIN_ROOT
  if command -v timeout >/dev/null 2>&1; then
    _TB_TIMEOUT=timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    _TB_TIMEOUT=gtimeout
  fi
  _tb_ops
  _tb_skills
  _tb_agy_pack
  # Antigravity workspace settings (permission deny rules). Project-tier
  # settings are NOT read headless (D-032: agy enforces only the user tier,
  # ~/.gemini/antigravity-cli/settings.json, which Triforge never writes); the
  # file documents the deny intent in agy's action syntax and covers
  # interactive `agy` use. Triforge ships no agy hook (AGY-08 is an open watch).
  _bootstrap_copy "${_TB_ROOT}/templates/.antigravity/settings.json" ".antigravity/settings.json"
  _tb_codex
  _tb_optional_clis
  # ops/roster.toml — its own copy-if-absent step, outside the ops/ skeleton,
  # so an upgraded project that already has ops/ still receives it; a user's
  # roster is never overwritten. The watch registry is not bootstrapped:
  # /cli-watch and /repo-watch are maintainer tooling in the Triforge checkout.
  _bootstrap_copy "${_TB_ROOT}/templates/ops/roster.toml" "ops/roster.toml"
  _tb_pointer
  if [ "$_TB_DEGRADED" -ne 0 ]; then
    return 80
  fi
  return 0
}

# _tb_note <text> — one notice on stderr: the caller's prefix, then the text
# with control characters dropped, so a file name or a version string read
# from disk can never split it into a second line.
_tb_note() {
  printf '%s%s\n' "${_TB_PREFIX:-triforge_bootstrap: }" "$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')" >&2
}

# _tb_run <seconds> <command...> — the command under the timeout binary when
# there is one, else as it is (a step that must not run unbounded checks
# _TB_TIMEOUT itself, as the agy pack step does).
_tb_run() {
  local SECS=$1
  shift
  if [ -n "${_TB_TIMEOUT:-}" ]; then
    "$_TB_TIMEOUT" "${SECS}s" "$@"
  else
    "$@"
  fi
}

# _tb_files <dir> <suffix> — the regular files directly in <dir> whose names
# end in <suffix> ("" for any), dot files left out, sorted, one per line: what
# the glob <dir>/*<suffix> named, without a glob.
_tb_files() {
  [ -d "$1" ] || return 0
  find "$1" -mindepth 1 -maxdepth 1 -type f -name "*$2" ! -name '.*' 2>/dev/null | LC_ALL=C sort
}

# _bootstrap_copy <src> <dest> — provision a template file into the project,
# copy-if-absent so user customizations survive. Creates the parent dir. Never
# aborts the caller on a filesystem error (read-only dir, a path component
# that is a regular file): the step warns, marks the run degraded and is
# skipped, so every other bootstrap step still runs.
_bootstrap_copy() {
  local src="$1" dest="$2"
  [ -f "$src" ] || return 0
  [ -e "$dest" ] && return 0        # preserve an existing user file/dir
  [ -L "$dest" ] && return 0        # and a dangling symlink, which cp would follow out of the project
  if ! mkdir -p "$(dirname "$dest")" 2>/dev/null; then
    _tb_note "WARNING could not create $(dirname "$dest") — skipping bootstrap of ${dest} (session continues)"
    _TB_DEGRADED=1
    return 0
  fi
  if ! cp "$src" "$dest" 2>/dev/null; then
    _tb_note "WARNING could not copy ${dest} — skipping (session continues)"
    _TB_DEGRADED=1
  fi
  return 0
}

# _tb_ops — step 1: ops/solutions, ops/decisions, ops/archive and the skeleton
# MEMORY.md, CHANGELOG.md, AGENTS.md and GOALS.md from templates/ops/, only
# while ops/ does not exist: an existing ops/ is the project's.
_tb_ops() {
  local F
  [ ! -d ops ] || return 0
  if ! mkdir -p ops/solutions ops/decisions ops/archive 2>/dev/null; then
    _tb_note "WARNING could not create ops/ — the ops skeleton was not bootstrapped (the next run retries)."
    _TB_DEGRADED=1
    return 0
  fi
  for F in MEMORY.md CHANGELOG.md AGENTS.md GOALS.md; do
    _bootstrap_copy "${_TB_ROOT}/templates/ops/${F}" "ops/${F}"
  done
  return 0
}

# _tb_skills — step 2: the .agents/skills/ refresh (KTD12, R31), the agy
# workspace-skills tier and the cross-CLI agentskills.io path (Codex, OpenCode,
# Cursor and Kimi read it). Copies, never symlinks, so loaders that refuse to
# follow symlinks across mount boundaries still see the skills.
#
# The work is scripts/lib/skills-sync.py's, which _lease_provision_skills also
# runs for each lease worktree, so both follow one ownership rule: Triforge
# replaces or retires a directory only when its content digest matches the
# digest recorded in the stamp .agents/skills/.triforge-plugin-version for
# that name (a 3.3.0–3.3.2 stamp without digests is migrated against
# scripts/lib/skill-digests.txt, the digests of every released copy). Anything
# else is user-owned: kept, with one notice naming it. With no stamp, only
# empty slots are written. The stamp is safe to commit in a user project (this
# repo ignores /.agents/); an unchanged plugin version is a no-op with no
# notice, and the stamp is written last, so an interrupted refresh re-runs on
# the next call. A symlinked .agents or .agents/skills, or one that resolves
# outside the project, is left untouched with one notice. Its WARNING lines,
# a nonzero exit and the 60 s timeout mark the run degraded.
_tb_skills() {
  local SYNC="${_TB_ROOT}/scripts/lib/skills-sync.py" OUT="" RC=0 LINE=""
  [ -d "${_TB_ROOT}/skills" ] || return 0
  if [ ! -f "$SYNC" ]; then
    _tb_note "WARNING ${SYNC} is missing — .agents/skills not refreshed (reinstall the plugin)."
    _TB_DEGRADED=1
    return 0
  fi
  # A crash or a timeout must not abort the caller, but it must not be silent
  # either: the exit status is kept and reported.
  OUT=$(_tb_run 60 python3 "$SYNC" sync --plugin-root "$_TB_ROOT" --project . --prefix "" 2>/dev/null) || RC=$?
  while IFS= read -r LINE; do
    [ -n "$LINE" ] || continue
    _tb_note "$LINE"
    case "$LINE" in
      WARNING*) _TB_DEGRADED=1 ;;
    esac
  done <<TB_SYNC_EOF
${OUT}
TB_SYNC_EOF
  if [ "$RC" -ne 0 ]; then
    _tb_note "WARNING .agents/skills refresh failed (skills-sync.py exit ${RC}; 124 means the 60 s timeout) — skills may be stale; the refresh re-runs next session."
    _TB_DEGRADED=1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Antigravity agent pack — install-over on version change (KTD8, R8).
# antigravity-agents/ is a valid agy plugin; installing it registers the four
# external agents (codebase-analyst, architecture-reviewer, targeted-researcher,
# documentation-writer). `agy plugin list` carries no version field, so the
# installed version is read from the managed copy agy writes at
# $HOME/.gemini/config/plugins/agent-triforge/plugin.json and compared with the
# shipped antigravity-agents/plugin.json; on a mismatch, or when the pack is not
# installed, `agy plugin install <plugin-root>/antigravity-agents` runs — agy
# ≥ 1.1.28 replaces the managed directory exactly on reinstall. Acceptance is
# `importedAt` advancing in $HOME/.gemini/config/import_manifest.json (the
# imports[] entry named agent-triforge) and `agy agents` listing all four names
# (AGY-12); when the listing stays short the step tries `agy plugin uninstall
# agent-triforge` and installs once more. When the managed plugin.json is
# unreadable, the version last installed here is read from the runtime stamp
# .claude/agy-pack-version.local.md instead. Every agy call is wrapped in the
# timeout binary (30 s) and failure-tolerant; invoke_antigravity keeps its
# injection fallback (TRIFORGE_AGY_MODE, KTD10) whatever the outcome. Skipped
# entirely without a timeout binary (fail-closed: a hung agy must not stall the
# caller; the hook's orientation names the missing tool).
_TB_AGY_STAMP=".claude/agy-pack-version.local.md"

# _tb_json_version <file> — top-level "version" string of a JSON file, or ""
# when the file is missing/unreadable. The path travels as an environment
# variable, never interpolated into the python source.
_tb_json_version() {
  [ -f "$1" ] || return 0
  _tb_run 30 env TB_JSON_FILE="$1" python3 -c '
import json, os
try:
    with open(os.environ["TB_JSON_FILE"], "r", encoding="utf-8") as f:
        print(str(json.load(f).get("version", "")).strip())
except Exception:
    pass
' 2>/dev/null || true
}

# _tb_agy_imported_at — importedAt of the agent-triforge entry in agy's import
# manifest, or "" when absent/unreadable.
_tb_agy_imported_at() {
  local MANIFEST="${HOME:-}/.gemini/config/import_manifest.json"
  [ -f "$MANIFEST" ] || return 0
  env TB_MANIFEST="$MANIFEST" python3 -c '
import json, os
try:
    with open(os.environ["TB_MANIFEST"], "r", encoding="utf-8") as f:
        data = json.load(f)
    imports = data.get("imports", []) if isinstance(data, dict) else data
    for entry in imports:
        if isinstance(entry, dict) and entry.get("name") == "agent-triforge":
            print(str(entry.get("importedAt", "")).strip())
            break
except Exception:
    pass
' 2>/dev/null || true
}

# _tb_agy_agents_missing — shipped agent names absent from `agy agents` (30 s).
_tb_agy_agents_missing() {
  local LISTING="" NAME="" MISSING=""
  LISTING=$("$_TB_TIMEOUT" 30s agy agents 2>/dev/null || true)
  for NAME in codebase-analyst architecture-reviewer targeted-researcher documentation-writer; do
    printf '%s\n' "$LISTING" | grep -q -- "$NAME" || MISSING="${MISSING:+${MISSING} }${NAME}"
  done
  printf '%s' "$MISSING"
}

# _tb_agy_pack — step 3 (see the block comment above).
_tb_agy_pack() {
  local SHIPPED="" INSTALLED="" LISTED="" BEFORE="" AFTER="" RC=0 MISSING="" TMP=""
  [ -n "$_TB_TIMEOUT" ] || return 0
  command -v agy >/dev/null 2>&1 || return 0
  SHIPPED=$(_tb_json_version "${_TB_ROOT}/antigravity-agents/plugin.json")
  INSTALLED=$(_tb_json_version "${HOME:-}/.gemini/config/plugins/agent-triforge/plugin.json")
  if [ -z "$INSTALLED" ]; then
    # Managed copy unreadable or absent: if the pack is installed at all, fall
    # back to the version last installed here (stamp); else "not installed".
    LISTED=$("$_TB_TIMEOUT" 30s agy plugin list 2>/dev/null || true)
    if printf '%s\n' "$LISTED" | grep -q "agent-triforge" && [ -f "$_TB_AGY_STAMP" ]; then
      INSTALLED=$(sed -n 's/^version=//p' "$_TB_AGY_STAMP" 2>/dev/null | head -1 || true)
    fi
  fi
  if [ -z "$SHIPPED" ] || [ "$INSTALLED" = "$SHIPPED" ]; then
    return 0
  fi
  BEFORE=$(_tb_agy_imported_at)
  "$_TB_TIMEOUT" 30s agy plugin install "${_TB_ROOT}/antigravity-agents" >/dev/null 2>&1 || RC=$?
  MISSING=$(_tb_agy_agents_missing)
  if [ "$RC" -ne 0 ] || [ -n "$MISSING" ]; then
    # Install-over did not yield a complete listing: uninstall + install once.
    "$_TB_TIMEOUT" 30s agy plugin uninstall agent-triforge >/dev/null 2>&1 || true
    RC=0
    "$_TB_TIMEOUT" 30s agy plugin install "${_TB_ROOT}/antigravity-agents" >/dev/null 2>&1 || RC=$?
    MISSING=$(_tb_agy_agents_missing)
  fi
  AFTER=$(_tb_agy_imported_at)
  if [ "$RC" -ne 0 ]; then
    _tb_note "agy plugin install failed (rc=${RC}) — invoke_antigravity will use injection mode from the plugin templates."
    _TB_DEGRADED=1
    return 0
  fi
  # Temp file + rename: a bare redirect would follow a symlink planted at the
  # stamp path. A failed write leaves the old stamp; the next call reinstalls.
  TMP="${_TB_AGY_STAMP}.tmp.$$"
  if mkdir -p .claude 2>/dev/null && {
       printf '%s\n' "<!-- runtime state: Antigravity agent pack version last installed by triforge_bootstrap (regenerated on each reinstall) -->"
       printf 'version=%s\n' "$SHIPPED"
       printf 'installed=%s\n' "$(date +%Y-%m-%d)"
       printf 'importedAt=%s\n' "${AFTER:-unknown}"
     } > "$TMP" 2>/dev/null; then
    mv -f "$TMP" "$_TB_AGY_STAMP" 2>/dev/null || rm -f "$TMP" 2>/dev/null || true
  else
    rm -f "$TMP" 2>/dev/null || true
  fi
  if [ -z "$MISSING" ]; then
    _tb_note "Antigravity agent pack installed ${INSTALLED:-none} -> ${SHIPPED} (importedAt ${BEFORE:-none} -> ${AFTER:-unknown}; agy agents lists all four Triforge agents)."
  else
    _tb_note "Antigravity agent pack installed ${INSTALLED:-none} -> ${SHIPPED} (importedAt ${BEFORE:-none} -> ${AFTER:-unknown}), but agy agents does not list: ${MISSING} — invoke_antigravity stays in injection mode (TRIFORGE_AGY_MODE)."
  fi
  return 0
}

# _tb_is_3x_codex_hooks <file> — 0 when the file is byte-equal to the one 3.x
# templates/.codex/hooks.json (sha256 below): Triforge's own copy of the
# attribution hook that appended to ops/CHANGELOG.md and wrote
# .claude/codex-changelog.* from every Codex session, inside lease worktrees
# too. The grep is a cheap gate in front of the hash, which decides.
_TB_3X_CODEX_HOOKS_SHA256="9aece38547f04f98c9cd158538cb31e654c1fa3767de414afbab1bd50b8f140c"
_tb_is_3x_codex_hooks() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  grep -qF 'codex-changelog' "$1" 2>/dev/null || return 1
  [ "$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1" 2>/dev/null || true)" = "$_TB_3X_CODEX_HOOKS_SHA256" ]
}

# _tb_dir_in_project <dir> — 0 when <dir> (a direct child of the project root,
# the cwd) is absent, or a real directory, not a symlink, whose physical path
# is inside the project. A .codex linked elsewhere (to ~/.codex, say) holds
# another tier's files, which Triforge never writes.
_tb_dir_in_project() {
  local ROOT="" D=""
  if [ -L "$1" ]; then return 1; fi
  if [ ! -e "$1" ]; then return 0; fi
  ROOT=$(pwd -P 2>/dev/null) || return 1
  D=$(cd "$1" 2>/dev/null && pwd -P 2>/dev/null) || return 1
  case "$D" in "${ROOT}/"*) return 0 ;; esac
  return 1
}

# _tb_codex — step 4a: the Codex project files (.codex/*), copy-if-absent so
# user customizations survive: triforge-agents.toml = Triforge's agent
# declarations (KTD5 — deployed OUTSIDE .codex/agents/, which Codex ≥ 0.147
# sweeps as per-agent role files and warns "Ignoring malformed agent role
# definition" on); config.toml disables Codex's auto-memory pipeline (conflict
# with ops/MEMORY.md); hooks.json ships with no hooks since 4.0 (KTD9: the 3.x
# CHANGELOG attribution hook wrote ops/ from every Codex session, lease workers
# included; attribution now comes from the ledger). See
# templates/.codex/README.md and ops/decisions/2026-07-18-codex-hooks-under-exec.md.
_tb_codex() {
  if ! _tb_dir_in_project ".codex"; then
    # A .codex that is a symlink or resolves outside the project: nothing below
    # writes through it (the move, the bootstrap copies, the 3.x replacement).
    # Reading the hooks file to name the manual step is fine.
    if _tb_is_3x_codex_hooks ".codex/hooks.json"; then
      _tb_note "WARNING .codex/hooks.json is the unchanged 3.x copy, which writes ops/CHANGELOG.md from every Codex session, but .codex is a symlink or resolves outside this project, so it was NOT replaced (Triforge never writes outside the project) — if that file is yours to change, copy templates/.codex/hooks.json over it by hand."
    else
      _tb_note ".codex is a symlink or resolves outside this project, so Triforge's Codex files were not bootstrapped there (it never writes outside the project) — copy codex-agents/agents.toml to .codex/triforge-agents.toml and templates/.codex/config.toml by hand if you want them."
    fi
    return 0
  fi
  # One-time migration (KTD5): v3.2.0 deployed .codex/agents/agents.toml. Move it
  # to the new name once — a user-modified file is moved, never deleted or
  # overwritten — and drop the now-empty .codex/agents/ only when it IS empty
  # (rmdir, never rm -rf). If both files exist the user resolves it by hand.
  if [ -f ".codex/agents/agents.toml" ]; then
    if [ ! -e ".codex/triforge-agents.toml" ]; then
      if mv ".codex/agents/agents.toml" ".codex/triforge-agents.toml" 2>/dev/null; then
        rmdir ".codex/agents" 2>/dev/null || true
        _tb_note "moved .codex/agents/agents.toml to .codex/triforge-agents.toml (Codex sweeps .codex/agents/*.toml as per-agent role files and warned on it; the file content is unchanged)."
      else
        _tb_note "WARNING could not move .codex/agents/agents.toml to .codex/triforge-agents.toml — move it by hand (Codex warns on the old location)."
        _TB_DEGRADED=1
      fi
    else
      _tb_note "both .codex/agents/agents.toml and .codex/triforge-agents.toml exist — merge and remove the old file by hand (Codex warns on .codex/agents/*.toml)."
    fi
  fi
  _bootstrap_copy "${_TB_ROOT}/codex-agents/agents.toml"     ".codex/triforge-agents.toml"
  _bootstrap_copy "${_TB_ROOT}/templates/.codex/config.toml" ".codex/config.toml"
  # One-time migration (KTD9): a .codex/hooks.json still byte-equal to the 3.x
  # template (_tb_is_3x_codex_hooks) is replaced once by the 4.0 template. An
  # edited copy is the user's and is left alone.
  if [ -f "${_TB_ROOT}/templates/.codex/hooks.json" ] && _tb_is_3x_codex_hooks ".codex/hooks.json"; then
    if cp "${_TB_ROOT}/templates/.codex/hooks.json" ".codex/hooks.json" 2>/dev/null; then
      _tb_note "replaced .codex/hooks.json — the unchanged 3.x copy appended a line to ops/CHANGELOG.md from every Codex session, lease workers included; attribution now comes from the lease ledger."
    else
      _tb_note "WARNING could not replace the 3.x .codex/hooks.json, which writes ops/CHANGELOG.md from every Codex session — copy templates/.codex/hooks.json over it by hand."
      _TB_DEGRADED=1
    fi
  fi
  _bootstrap_copy "${_TB_ROOT}/templates/.codex/hooks.json"  ".codex/hooks.json"
  return 0
}

# _tb_optional_clis — step 4b: the optional members' project files, each
# guarded on its binary, copy-if-absent.
#   OpenCode (`command -v opencode`): .opencode/agents/*.md + .opencode/opencode.json.
#     invoke_opencode routes builder/reviewer via `--agent <name>` from
#     .opencode/agents/ (project tier) with the plugin's opencode-agents/ as
#     fallback. Reviewer read-only safety is the agent-def permission map
#     (edit/bash deny) plus the OPENCODE_PERMISSION deny rules injected at
#     dispatch (R7); the adapter stays off --auto (OC-06 — see
#     templates/.opencode/README.md).
#   Kimi (`command -v kimi`): .kimi-code/AGENTS.md + config.toml. Kimi 0.42.0
#     reversed KIMI-03 (D-024): `--agent-file <path>` works in `-p`, so roles
#     ride as native agent definitions loaded from the plugin's kimi-agents/
#     (R6; agent definitions are never deployed into .agents/agents/ — KTD13).
#     The project .kimi-code/config.toml is NOT read by the CLI (only
#     ~/.kimi-code/config.toml is): the two files document the intended
#     posture; the real headless confinement is the lease worktree +
#     _adapter_env KIMI_* allowlist + KIMI_DISABLE_TELEMETRY (see
#     templates/.kimi-code/README.md).
#   Cursor (_cursor_bin, the helper's own resolver — KTD3, D-025: `cursor-agent`
#     first, else the first `agent` on PATH whose --version matches Cursor's
#     `YYYY.MM.DD-<hex>` format under a 15 s cap, fail-closed without a timeout
#     tool): .cursor/agents/*.md (README.md left out) + templates/.cursor/*.
#     Cursor has NO headless --agent selector, so roles ride as prompt-prefix
#     injection from the plugin's cursor-agents/ briefs; the .cursor/agents/
#     copies are delegation targets + documentation, and .cursor/README.md
#     records the --trust-required / grok-4.6-pinned-never-Auto / CUR-06
#     headless-hooks-dead / CUR-07 --sandbox-doesn't-confine / CUR-08
#     --mode-plan-is-read-only facts. No afterFileEdit attribution hook is
#     shipped (CUR-06 FAIL); builder attribution is lead-side from the lease
#     ledger. _cursor_bin runs in this shell, so a hit stays exported
#     (TRIFORGE_CURSOR_BIN) for the caller: the hook's detection loop then
#     looks the binary up instead of probing again.
_tb_optional_clis() {
  local F=""
  if command -v opencode >/dev/null 2>&1; then
    while IFS= read -r F; do
      [ -n "$F" ] || continue
      _bootstrap_copy "$F" ".opencode/agents/${F##*/}"
    done <<TB_OC_EOF
$(_tb_files "${_TB_ROOT}/opencode-agents" .md)
TB_OC_EOF
    _bootstrap_copy "${_TB_ROOT}/templates/.opencode/opencode.json" ".opencode/opencode.json"
  fi
  if command -v kimi >/dev/null 2>&1; then
    for F in AGENTS.md config.toml; do
      _bootstrap_copy "${_TB_ROOT}/templates/.kimi-code/${F}" ".kimi-code/${F}"
    done
  fi
  if _cursor_bin >/dev/null 2>&1; then
    while IFS= read -r F; do
      [ -n "$F" ] || continue
      case "${F##*/}" in README.md) continue ;; esac
      _bootstrap_copy "$F" ".cursor/agents/${F##*/}"
    done <<TB_CURSOR_EOF
$(_tb_files "${_TB_ROOT}/cursor-agents" .md)
TB_CURSOR_EOF
    while IFS= read -r F; do
      [ -n "$F" ] || continue
      _bootstrap_copy "$F" ".cursor/${F##*/}"
    done <<TB_CURSOR_TPL_EOF
$(_tb_files "${_TB_ROOT}/templates/.cursor" "")
TB_CURSOR_TPL_EOF
  fi
  return 0
}

# ---------------------------------------------------------------------------
# The plugin-root pointer (KTD6, R16) — step 5
# ---------------------------------------------------------------------------
#
# The at- skills' locator (scripts/skill-locator/locate-triforge.sh) reads
# <top>/.agents/triforge-plugin-root.local when the lead exports no plugin
# root and its own copy does not sit in the plugin tree; <top> is the git
# toplevel of the working directory, else the directory itself. This is its
# only writer. The file holds the plugin root's physical path, is rewritten
# only when it is absent or names another path, and is written only where the
# locator would accept it:
#   - <top>/.agents is a real directory (not a symlink, not resolving
#     elsewhere) and the pointer path is absent or a regular file;
#   - git does not track it under any letter case, and git can say so;
#   - the root resolves outside <top> and outside the main checkout of a
#     linked worktree. When the root IS <top> or the main checkout (the
#     Triforge checkout as its own project) nothing is written: the locator
#     finds that root from its own location. A root strictly inside the
#     project gets one notice, since the locator refuses a pointer there;
#   - git ignores it. An existing rule counts (a project that ignores
#     /.agents/, a global excludes file); otherwise .agents/.gitignore gets
#     one — created holding `*.local`, the documented rule, or, when the user
#     already has that file, with /triforge-plugin-root.local appended, so a
#     rule of the user's is never widened — and git check-ignore confirms it
#     before the pointer is written. The project's root .gitignore and its
#     instruction files are never edited. Outside git, .agents/.gitignore is
#     created when absent, so the file stays ignored once the project is.
# Git runs read-only through _tb_git: inherited GIT_* that would redirect it
# unset, hooks and fsmonitor off (the KTD18 per-invocation overrides that need
# no lease context).
_TB_POINTER=".agents/triforge-plugin-root.local"

_tb_git() {
  env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
      GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 \
      git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
}

# _tb_phys <dir> — physical path of an existing directory, spelled as on disk
# (the external pwd, as the locator's phys does, so the two compare equal on a
# case-insensitive filesystem).
_tb_phys() {
  (cd "$1" 2>/dev/null && env pwd -P)
}

# _tb_pointer_refused <reason> — the pointer cannot be written: one notice,
# the run degraded.
_tb_pointer_refused() {
  _tb_note "WARNING no plugin-root pointer written: $1 — the at- skills then find the plugin only from their own install or a plugin root the lead exports (fix it, then run at-setup again)."
  _TB_DEGRADED=1
}

# _tb_ignore_rule <.agents dir> — add the ignore rule to <dir>/.gitignore and
# print what was done (the pointer notice carries it); rc 1 after a notice
# when that file is not a regular file or cannot be written. Called in a
# $(...), so the caller marks the run degraded on rc 1.
_tb_ignore_rule() {
  local GI="$1/.gitignore"
  if [ -L "$GI" ] || { [ -e "$GI" ] && [ ! -f "$GI" ]; }; then
    _tb_pointer_refused ".agents/.gitignore is not a regular file, so git could not be made to ignore the pointer"
    return 1
  fi
  if [ -f "$GI" ]; then
    if { if [ -s "$GI" ] && [ -n "$(tail -c 1 "$GI" 2>/dev/null)" ]; then printf '\n'; fi
         printf '/triforge-plugin-root.local\n'; } >> "$GI" 2>/dev/null; then
      printf '%s' "appended /triforge-plugin-root.local to .agents/.gitignore"
      return 0
    fi
  elif mkdir -p "$1" 2>/dev/null && printf '*.local\n' > "$GI" 2>/dev/null; then
    printf '%s' "created .agents/.gitignore (*.local)"
    return 0
  fi
  _tb_pointer_refused "could not write .agents/.gitignore"
  return 1
}

_tb_pointer() {
  local ROOT="" TOP="" MAIN="" COMMON="" GIT="" PDIR="" PFILE="" CUR="" RC=0 IGNORE="" TMP=""
  ROOT=$(_tb_phys "$_TB_ROOT") || ROOT=""
  if [ -z "$ROOT" ]; then
    _tb_pointer_refused "the plugin root ${_TB_ROOT} did not resolve to a directory"
    return 0
  fi
  if command -v git >/dev/null 2>&1 && [ "$(_tb_git rev-parse --is-inside-work-tree 2>/dev/null || true)" = "true" ]; then
    GIT=yes
    TOP=$(_tb_git rev-parse --show-toplevel 2>/dev/null) || TOP=""
  fi
  [ -n "$TOP" ] || TOP=$(pwd -P 2>/dev/null) || TOP=""
  TOP=$(_tb_phys "$TOP") || TOP=""
  if [ -z "$TOP" ]; then
    _tb_pointer_refused "the project directory did not resolve"
    return 0
  fi
  if [ -n "$GIT" ]; then
    COMMON=$(_tb_git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || COMMON=""
    if [ -n "$COMMON" ] && [ "${COMMON##*/}" = ".git" ]; then
      MAIN=$(_tb_phys "${COMMON%/*}") || MAIN=""
      if [ "$MAIN" = "$TOP" ]; then MAIN=""; fi
    fi
  fi
  if [ "$ROOT" = "$TOP" ] || { [ -n "$MAIN" ] && [ "$ROOT" = "$MAIN" ]; }; then
    return 0
  fi
  case "$ROOT/" in
    "$TOP"/*)
      _tb_note "no plugin-root pointer written: the plugin root ${ROOT} lies inside this project, where the locator refuses one — a lead that exports no plugin root reaches the at- skills only from a plugin install outside the project."
      return 0
      ;;
  esac
  if [ -n "$MAIN" ]; then
    case "$ROOT/" in
      "$MAIN"/*)
        _tb_note "no plugin-root pointer written: the plugin root ${ROOT} lies inside this project's main checkout, where the locator refuses one — a lead that exports no plugin root reaches the at- skills only from a plugin install outside the project."
        return 0
        ;;
    esac
  fi
  PDIR="${TOP}/.agents"
  PFILE="${TOP}/${_TB_POINTER}"
  if [ -L "$PDIR" ]; then
    _tb_pointer_refused ".agents is a symlink (the locator reads a pointer only from a real .agents directory of the project)"
    return 0
  fi
  if [ -e "$PDIR" ] && [ ! -d "$PDIR" ]; then
    _tb_pointer_refused ".agents exists and is not a directory"
    return 0
  fi
  if [ -d "$PDIR" ] && [ "$(_tb_phys "$PDIR" || true)" != "$PDIR" ]; then
    _tb_pointer_refused ".agents resolves outside the project (a symlinked ancestor)"
    return 0
  fi
  if [ -L "$PFILE" ] || { [ -e "$PFILE" ] && [ ! -f "$PFILE" ]; }; then
    _tb_pointer_refused "${_TB_POINTER} exists and is not a regular file"
    return 0
  fi
  if [ -n "$GIT" ]; then
    # tracked under any letter case (a case-insensitive filesystem serves the
    # pointer under a name git tracks differently); a git error is a refusal
    _tb_git -C "$TOP" ls-files --error-unmatch -- ":(icase)${_TB_POINTER}" >/dev/null 2>&1 || RC=$?
    if [ "$RC" -eq 0 ]; then
      _tb_pointer_refused "git tracks ${_TB_POINTER} (it must stay untracked: git rm --cached it)"
      return 0
    fi
    if [ "$RC" -ne 1 ]; then
      _tb_pointer_refused "git could not say whether ${_TB_POINTER} is tracked (git ls-files rc ${RC})"
      return 0
    fi
  fi
  if [ -f "$PFILE" ]; then
    CUR=$(grep -v '^[[:space:]]*#' "$PFILE" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//') || CUR=""
  fi
  if [ -n "$GIT" ]; then
    RC=0
    _tb_git -C "$TOP" check-ignore -q -- "$_TB_POINTER" >/dev/null 2>&1 || RC=$?
    if [ "$RC" -eq 1 ]; then
      IGNORE=$(_tb_ignore_rule "$PDIR") || { _TB_DEGRADED=1; return 0; }   # a $(...) subshell: its own flag is lost
      RC=0
      _tb_git -C "$TOP" check-ignore -q -- "$_TB_POINTER" >/dev/null 2>&1 || RC=$?
      if [ "$RC" -eq 1 ]; then
        _tb_pointer_refused "git still does not ignore ${_TB_POINTER} after Triforge ${IGNORE} (a later rule re-includes it)"
        return 0
      fi
    fi
    if [ "$RC" -ne 0 ]; then
      _tb_pointer_refused "git could not say whether ${_TB_POINTER} is ignored (git check-ignore rc ${RC})"
      return 0
    fi
  elif [ ! -e "${PDIR}/.gitignore" ] && [ ! -L "${PDIR}/.gitignore" ]; then
    IGNORE=$(_tb_ignore_rule "$PDIR") || { _TB_DEGRADED=1; return 0; }
  fi
  if [ "$CUR" = "$ROOT" ]; then
    if [ -n "$IGNORE" ]; then
      _tb_note "${IGNORE}, so git ignores the plugin-root pointer ${_TB_POINTER}."
    fi
    return 0
  fi
  TMP="${PFILE}.tmp.$$"
  if mkdir -p "$PDIR" 2>/dev/null && {
       printf '%s\n' "# Agent Triforge plugin root for this checkout, written by triforge_bootstrap (per user, untracked; rewritten when the plugin moves)."
       printf '%s\n' "$ROOT"
     } > "$TMP" 2>/dev/null && mv -f "$TMP" "$PFILE" 2>/dev/null; then
    _tb_note "wrote the plugin-root pointer ${_TB_POINTER} (${ROOT})${IGNORE:+; ${IGNORE}} — the at- skills read it when no plugin root is exported."
  else
    rm -f "$TMP" 2>/dev/null || true
    _tb_pointer_refused "could not write ${_TB_POINTER}"
  fi
  return 0
}
