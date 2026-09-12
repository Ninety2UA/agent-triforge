#!/usr/bin/env bash
# Session Start — SessionStart hook
# Scans for existing state, pending tasks, and available context; bootstraps
# the project's ops/ + per-CLI files; migrates an upgraded project to the
# current plugin layout (skills refresh, Antigravity pack reinstall, Codex file
# move) with one notice per step. Provides orientation for the new session.
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
#   Audited 2026-09-11: every stdout line is prose ("Multi-agent framework
#   ready.", "session-start: …", "Roster …", "Tip: …", "Commands: …"); every
#   external-CLI capture (agy plugin list / agy agents) is consumed here and
#   never echoed.
# Bash 3.2 compatible (macOS /bin/bash): no associative arrays, no mapfile, no
#   "${arr[@]}" expansion of a possibly-empty array under set -u.

set -euo pipefail

_ss_on_exit() {
  local RC=$?
  [ "$RC" -eq 0 ] && return 0
  echo "session-start: WARNING hook crashed (rc=${RC}) — session continues; bootstrap steps after the crash did not run (ON_CRASH: ALLOW)" >&2
  echo "Multi-agent framework ready (session-start hook degraded — see stderr)."
  exit 0
}
trap _ss_on_exit EXIT

# Ensure .claude/ directory exists for project-local state files
mkdir -p .claude

# Clean stale state files from previous sessions
rm -f .claude/context-monitor.local.md

# Timeout binary (GNU coreutils `timeout`, or `gtimeout` on macOS). Every
# external-CLI call in this hook runs under it; when neither exists the agy and
# `agent` probes below are SKIPPED (fail-closed, mirroring invoke-external.sh —
# a hung CLI must not stall session start) and the warning is appended to the
# orientation message.
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
[ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="gtimeout"
TIMEOUT_MISSING_WARNING=""
if [ -z "$TIMEOUT_BIN" ]; then
  TIMEOUT_MISSING_WARNING="WARNING: neither \`timeout\` nor \`gtimeout\` found on PATH — invoke-external.sh is fail-closed and will refuse to run Antigravity/Codex invocations (this hook also skipped its agy and cursor probes). On macOS, install with: brew install coreutils"
fi

# _ss_json_version <file> — top-level "version" string of a JSON file, or ""
# when the file is missing/unreadable. Input travels as a prefixed env var,
# never interpolated into the python source.
_ss_json_version() {
  [ -f "$1" ] || return 0
  local -a CMD=(python3 -c '
import json, os
try:
    with open(os.environ["SS_JSON_FILE"], "r", encoding="utf-8") as f:
        print(str(json.load(f).get("version", "")).strip())
except Exception:
    pass
')
  if [ -n "$TIMEOUT_BIN" ]; then
    CMD=("$TIMEOUT_BIN" 30s "${CMD[@]}")
  fi
  SS_JSON_FILE="$1" "${CMD[@]}" 2>/dev/null || true
}

PLUGIN_VERSION=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_VERSION=$(_ss_json_version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")
fi

# Bootstrap ops/ directory if it doesn't exist
if [ ! -d "ops" ]; then
  mkdir -p ops/solutions ops/decisions ops/archive
  # Copy skeleton files from plugin templates if available
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    for f in MEMORY.md CHANGELOG.md AGENTS.md GOALS.md; do
      if [ -f "${CLAUDE_PLUGIN_ROOT}/templates/ops/${f}" ] && [ ! -f "ops/${f}" ]; then
        cp "${CLAUDE_PLUGIN_ROOT}/templates/ops/${f}" "ops/${f}"
      fi
    done
  fi
fi

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
# (AGY-12); when the listing stays short the hook tries `agy plugin uninstall
# agent-triforge` and installs once more. When the managed plugin.json is
# unreadable, the version this hook last installed is read from the runtime
# stamp .claude/agy-pack-version.local.md instead. Every agy call is wrapped in
# the timeout binary (30 s) and failure-tolerant — nothing here aborts the hook;
# invoke_antigravity keeps its injection fallback (TRIFORGE_AGY_MODE, KTD10)
# whatever the outcome. Skipped entirely without a timeout binary (fail-closed).
AGY_PACK_NOTICE=""
AGY_PACK_AGENTS="codebase-analyst architecture-reviewer targeted-researcher documentation-writer"
AGY_PACK_STAMP=".claude/agy-pack-version.local.md"

# _ss_agy_imported_at — importedAt of the agent-triforge entry in agy's import
# manifest, or "" when absent/unreadable.
_ss_agy_imported_at() {
  local MANIFEST="${HOME:-}/.gemini/config/import_manifest.json"
  [ -f "$MANIFEST" ] || return 0
  SS_MANIFEST="$MANIFEST" python3 -c '
import json, os
try:
    with open(os.environ["SS_MANIFEST"], "r", encoding="utf-8") as f:
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

# _ss_agy_agents_missing — shipped agent names absent from `agy agents` (30 s).
_ss_agy_agents_missing() {
  local LISTING NAME MISSING=""
  LISTING=$("$TIMEOUT_BIN" 30s agy agents 2>/dev/null || true)
  for NAME in $AGY_PACK_AGENTS; do
    printf '%s\n' "$LISTING" | grep -q -- "$NAME" || MISSING="${MISSING:+${MISSING} }${NAME}"
  done
  printf '%s' "$MISSING"
}

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -n "$TIMEOUT_BIN" ] && command -v agy >/dev/null 2>&1; then
  SHIPPED_PACK_VERSION=$(_ss_json_version "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/plugin.json")
  INSTALLED_PACK_VERSION=$(_ss_json_version "${HOME:-}/.gemini/config/plugins/agent-triforge/plugin.json")
  if [ -z "$INSTALLED_PACK_VERSION" ]; then
    # Managed copy unreadable or absent: if the pack is installed at all, fall
    # back to the version this hook last installed (stamp); else "not installed".
    if "$TIMEOUT_BIN" 30s agy plugin list 2>/dev/null | grep -q "agent-triforge"; then
      if [ -f "$AGY_PACK_STAMP" ]; then
        INSTALLED_PACK_VERSION=$(sed -n 's/^version=//p' "$AGY_PACK_STAMP" 2>/dev/null | head -1 || true)
      fi
    fi
  fi
  if [ -n "$SHIPPED_PACK_VERSION" ] && [ "$INSTALLED_PACK_VERSION" != "$SHIPPED_PACK_VERSION" ]; then
    IMPORTED_BEFORE=$(_ss_agy_imported_at)
    AGY_INSTALL_RC=0
    "$TIMEOUT_BIN" 30s agy plugin install "${CLAUDE_PLUGIN_ROOT}/antigravity-agents" >/dev/null 2>&1 || AGY_INSTALL_RC=$?
    AGY_MISSING=$(_ss_agy_agents_missing)
    if [ "$AGY_INSTALL_RC" -ne 0 ] || [ -n "$AGY_MISSING" ]; then
      # Install-over did not yield a complete listing: uninstall + install once.
      "$TIMEOUT_BIN" 30s agy plugin uninstall agent-triforge >/dev/null 2>&1 || true
      AGY_INSTALL_RC=0
      "$TIMEOUT_BIN" 30s agy plugin install "${CLAUDE_PLUGIN_ROOT}/antigravity-agents" >/dev/null 2>&1 || AGY_INSTALL_RC=$?
      AGY_MISSING=$(_ss_agy_agents_missing)
    fi
    IMPORTED_AFTER=$(_ss_agy_imported_at)
    if [ "$AGY_INSTALL_RC" -eq 0 ]; then
      {
        echo "<!-- runtime state: Antigravity agent pack version last installed by session-start (regenerated on each reinstall) -->"
        echo "version=${SHIPPED_PACK_VERSION}"
        echo "installed=$(date +%Y-%m-%d)"
        echo "importedAt=${IMPORTED_AFTER:-unknown}"
      } > "${AGY_PACK_STAMP}.tmp.$$" 2>/dev/null && mv -f "${AGY_PACK_STAMP}.tmp.$$" "$AGY_PACK_STAMP" 2>/dev/null || rm -f "${AGY_PACK_STAMP}.tmp.$$" 2>/dev/null || true
      if [ -z "$AGY_MISSING" ]; then
        AGY_PACK_NOTICE="session-start: Antigravity agent pack installed ${INSTALLED_PACK_VERSION:-none} -> ${SHIPPED_PACK_VERSION} (importedAt ${IMPORTED_BEFORE:-none} -> ${IMPORTED_AFTER:-unknown}; agy agents lists all four Triforge agents)."
      else
        AGY_PACK_NOTICE="session-start: Antigravity agent pack installed ${INSTALLED_PACK_VERSION:-none} -> ${SHIPPED_PACK_VERSION} (importedAt ${IMPORTED_BEFORE:-none} -> ${IMPORTED_AFTER:-unknown}), but agy agents does not list: ${AGY_MISSING} — invoke_antigravity stays in injection mode (TRIFORGE_AGY_MODE)."
      fi
    else
      AGY_PACK_NOTICE="session-start: agy plugin install failed (rc=${AGY_INSTALL_RC}) — invoke_antigravity will use injection mode from the plugin templates."
    fi
  fi
fi

# Deploy Antigravity workspace settings (permission deny rules), copy-if-absent.
# Project-tier settings are still NOT read headless: the July probe (no
# project-tier settings.json lifted the `agy -p` auto-deny) stands, and D-032
# records that settings.json enforcement is user-tier only
# (~/.gemini/antigravity-cli/settings.json — never touched here; /setup
# documents the `read_url(*)` allow rule there). The shipped file documents the
# deny intent in agy's action syntax (`command(rm -rf)`, `command(git push)`,
# `command(sudo)`) and covers interactive `agy` use. Hooks (AGY-08): the
# documented `.agents/hooks.json` named-hook shape (PreInvocation, PostInvocation,
# PreToolUse, PostToolUse, Stop) fired headless on agy 1.2.0 (lead re-probe
# 2026-09-11) but NOT on agy 1.2.1 the same evening (harness FAIL with the hooks
# loaded) — an open watch, not an enforcement path; Triforge ships no agy hook.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/.antigravity/settings.json" ] && [ ! -f ".antigravity/settings.json" ]; then
  mkdir -p .antigravity
  cp "${CLAUDE_PLUGIN_ROOT}/templates/.antigravity/settings.json" ".antigravity/settings.json"
fi

# ---------------------------------------------------------------------------
# .agents/skills/ refresh (KTD7, R9) — the agy workspace-skills tier AND the
# cross-CLI agentskills.io path (Codex, OpenCode, Cursor and Kimi all read it).
# Copies, never symlinks, so loaders that refuse to follow symlinks across
# mount boundaries still see the skills.
#
# Ownership rule: shipped-name directories under .agents/skills/ are Triforge-
# OWNED and replaced whenever the plugin version changes; user customizations
# belong in a differently named directory, which this block never touches.
# The stamp .agents/skills/.triforge-plugin-version (line 1 `version=<plugin
# version>`, line 2 `skills=<comma-separated shipped names>`) drives the
# refresh: absent (a legacy v3.2.0-and-earlier copy) or different → refresh;
# equal → no copies and no notice (idempotent). The stamp is safe to commit in
# a user project (nothing gitignores it there; this repo ignores /.agents/) and
# a second session start on the same version is a no-op. It is written LAST,
# only after every copy succeeded, so an interrupted refresh re-runs on the
# next session start.
#
# Safety: `.agents/skills` itself being a symlink → skipped with one notice.
# Every name is validated against ^[a-z0-9][a-z0-9-]*$ and every existing
# destination must be a non-symlink directory DIRECTLY inside .agents/skills
# (python3 os.path.realpath containment) before it is replaced or retired;
# anything else is skipped with one notice. A shipped directory is replaced
# (rm -rf of the validated non-symlink dir, then `cp -R src/. dest/` — never
# `cp -R src dest`, which nests) rather than copied over in place, so a symlink
# planted inside it is never followed by cp. Retirement touches only names
# recorded in the PREVIOUS stamp that no longer ship — foreign (user-added)
# directories are never removed. _lease_provision_skills keeps its own fresh
# per-worktree copy (current by construction) and is unaffected.
SKILLS_NOTICES=""

_ss_skill_name_ok() {
  printf '%s' "$1" | LC_ALL=C grep -Eq '^[a-z0-9][a-z0-9-]*$'
}

# _ss_skill_dir_ok <path> — 0 when <path> is a non-symlink directory whose
# resolved location is directly inside the resolved .agents/skills.
_ss_skill_dir_ok() {
  [ -L "$1" ] && return 1
  [ -d "$1" ] || return 1
  SS_SKILL_PATH="$1" SS_SKILLS_ROOT=".agents/skills" python3 -c '
import os, sys
root = os.path.realpath(os.environ["SS_SKILLS_ROOT"])
raw = os.environ["SS_SKILL_PATH"]
path = os.path.realpath(raw)
ok = (os.path.dirname(path) == root) and os.path.isdir(path) and not os.path.islink(raw)
sys.exit(0 if ok else 1)
' 2>/dev/null
}

_ss_refresh_skills() {
  local VERSION="$1"
  local SRC_ROOT="${CLAUDE_PLUGIN_ROOT}/skills" DEST_ROOT=".agents/skills"
  local STAMP="${DEST_ROOT}/.triforge-plugin-version"
  local STAMPED_VERSION="" PREV_SKILLS="" SHIPPED="" SKIPPED="" RETIRED=""
  local NAME SRC DEST OLD FAILED=0 I=0
  local -a OLD_NAMES=()
  [ -d "$SRC_ROOT" ] || return 0
  if [ -L "$DEST_ROOT" ] || [ -L ".agents" ]; then
    SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: .agents or .agents/skills is a symlink — left untouched (Triforge refreshes only a real directory inside the project; remove the link to let session start manage it)."
    return 0
  fi
  # The resolved destination must be THIS checkout's own .agents/skills. A
  # symlinked ancestor (a repo can ship one) would otherwise let the refresh
  # rm -rf and write shipped-name directories outside the project (CWE-59):
  # _ss_skill_dir_ok anchors on realpath(.agents/skills), which already follows
  # such a link, so the containment has to be checked against the checkout here.
  if ! SS_DEST="$DEST_ROOT" python3 -c 'import os, sys; d = os.environ["SS_DEST"]; sys.exit(0 if os.path.realpath(d) == os.path.join(os.path.realpath("."), ".agents", "skills") else 1)' 2>/dev/null; then
    SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: .agents/skills resolves outside the project (symlinked ancestor) — left untouched."
    return 0
  fi
  if [ -f "$STAMP" ]; then
    STAMPED_VERSION=$(sed -n 's/^version=//p' "$STAMP" 2>/dev/null | head -1 || true)
    PREV_SKILLS=$(sed -n 's/^skills=//p' "$STAMP" 2>/dev/null | head -1 || true)
  fi
  if [ -d "$DEST_ROOT" ] && [ -n "$VERSION" ] && [ "$STAMPED_VERSION" = "$VERSION" ]; then
    return 0    # current: no copies, no notice
  fi
  if [ -d "$DEST_ROOT" ] && [ -z "$VERSION" ]; then
    return 0    # plugin version unreadable: keep what is deployed rather than refresh blind
  fi
  if ! mkdir -p "$DEST_ROOT" 2>/dev/null; then
    SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: WARNING could not create .agents/skills — skills not refreshed (session continues)."
    return 0
  fi
  # 1. Replace every shipped skill directory by name.
  for SRC in "$SRC_ROOT"/*/; do
    [ -d "$SRC" ] || continue
    SRC="${SRC%/}"
    NAME=$(basename "$SRC")
    if ! _ss_skill_name_ok "$NAME"; then
      SKIPPED="${SKIPPED} ${NAME}(invalid-name)"; continue
    fi
    SHIPPED="${SHIPPED:+${SHIPPED},}${NAME}"
    DEST="${DEST_ROOT}/${NAME}"
    if [ -e "$DEST" ] || [ -L "$DEST" ]; then
      if ! _ss_skill_dir_ok "$DEST"; then
        SKIPPED="${SKIPPED} ${NAME}(not-a-plain-directory)"; continue
      fi
      if ! rm -rf "$DEST" 2>/dev/null; then
        FAILED=1; SKIPPED="${SKIPPED} ${NAME}(replace-failed)"; continue
      fi
    fi
    if ! mkdir -p "$DEST" 2>/dev/null || ! cp -R "${SRC}/." "${DEST}/" 2>/dev/null; then
      FAILED=1; SKIPPED="${SKIPPED} ${NAME}(copy-failed)"; continue
    fi
  done
  # 2. Retire names from the PREVIOUS stamp that no longer ship (never a
  #    foreign directory: only stamp-listed names are candidates).
  if [ -n "$PREV_SKILLS" ]; then
    IFS=',' read -r -a OLD_NAMES <<< "$PREV_SKILLS" || true
    I=0
    while [ "$I" -lt "${#OLD_NAMES[@]}" ]; do
      OLD=$(printf '%s' "${OLD_NAMES[$I]}" | tr -d '[:space:]')
      I=$((I + 1))
      [ -n "$OLD" ] || continue
      case ",${SHIPPED}," in *",${OLD},"*) continue ;; esac   # still ships — replaced above
      if ! _ss_skill_name_ok "$OLD"; then
        SKIPPED="${SKIPPED} ${OLD}(invalid-name)"; continue
      fi
      DEST="${DEST_ROOT}/${OLD}"
      [ -e "$DEST" ] || [ -L "$DEST" ] || continue      # already gone
      if ! _ss_skill_dir_ok "$DEST"; then
        SKIPPED="${SKIPPED} ${OLD}(not-a-plain-directory)"; continue
      fi
      if rm -rf "$DEST" 2>/dev/null; then
        RETIRED="${RETIRED:+${RETIRED} }${OLD}"
      else
        SKIPPED="${SKIPPED} ${OLD}(remove-failed)"
      fi
    done
  fi
  # 3. Stamp LAST — only when every copy succeeded (skips are refusals, not
  #    failures: the skipped entry is reported and left alone for good).
  if [ "$FAILED" -eq 0 ]; then
    if { printf 'version=%s\n' "$VERSION"; printf 'skills=%s\n' "$SHIPPED"; } > "${STAMP}.tmp.$$" 2>/dev/null && mv "${STAMP}.tmp.$$" "$STAMP" 2>/dev/null; then
      SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: .agents/skills refreshed to ${VERSION} (shipped-name directories are Triforge-owned and overwritten on version change; keep customizations in a differently named directory)${RETIRED:+; retired no-longer-shipped: ${RETIRED}}."
    else
      rm -f "${STAMP}.tmp.$$" 2>/dev/null || true
      SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: WARNING .agents/skills refreshed but the version stamp could not be written — the refresh re-runs next session."
    fi
  else
    SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: WARNING .agents/skills refresh incomplete (stamp not written; re-runs next session)."
  fi
  if [ -n "$SKIPPED" ]; then
    SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: .agents/skills entries left untouched (symlink, not a plain directory directly inside .agents/skills, or invalid name):${SKIPPED}."
  fi
  return 0
}

if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  _ss_refresh_skills "$PLUGIN_VERSION"
fi

# _bootstrap_copy <src> <dest> — provision a template file into the project,
# copy-if-absent so user customizations survive. Creates the parent dir. NEVER
# aborts the hook on a filesystem error (read-only dir, a path component that is
# a regular file): the step warns and is skipped so session start still
# completes and every other bootstrap step still runs (this handler is under
# `set -euo pipefail`, where a bare `mkdir`/`cp` failure would abort everything).
_bootstrap_copy() {
  local src="$1" dest="$2"
  [ -f "$src" ] || return 0
  [ -e "$dest" ] && return 0        # preserve an existing user file/dir
  if ! mkdir -p "$(dirname "$dest")" 2>/dev/null; then
    echo "session-start: WARNING could not create $(dirname "$dest") — skipping bootstrap of ${dest} (session continues)" >&2
    return 0
  fi
  cp "$src" "$dest" 2>/dev/null || echo "session-start: WARNING could not copy ${dest} — skipping (session continues)" >&2
  return 0
}

# Bootstrap Codex project files (.codex/*), copy-if-absent so user
# customizations survive: triforge-agents.toml = Triforge's agent declarations
# (KTD5 — deployed OUTSIDE .codex/agents/, which Codex ≥ 0.147 sweeps as
# per-agent role files and warns "Ignoring malformed agent role definition" on);
# AGENTS.md = custom instructions; config.toml disables Codex's auto-memory
# pipeline (conflict with ops/MEMORY.md); hooks.json enforces CHANGELOG
# attribution under `codex exec` (probe CDX-04 PASS on 0.154.0 with
# --dangerously-bypass-hook-trust, which invoke-external.sh passes when this
# file is present). See templates/.codex/README.md and
# ops/decisions/2026-07-18-codex-hooks-under-exec.md.
CODEX_MOVE_NOTICE=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  # One-time migration (KTD5): v3.2.0 deployed .codex/agents/agents.toml. Move it
  # to the new name once — a user-modified file is moved, never deleted or
  # overwritten — and drop the now-empty .codex/agents/ only when it IS empty
  # (rmdir, never rm -rf). If both files exist the user resolves it by hand.
  if [ -f ".codex/agents/agents.toml" ]; then
    if [ ! -e ".codex/triforge-agents.toml" ]; then
      if mv ".codex/agents/agents.toml" ".codex/triforge-agents.toml" 2>/dev/null; then
        rmdir ".codex/agents" 2>/dev/null || true
        CODEX_MOVE_NOTICE="session-start: moved .codex/agents/agents.toml to .codex/triforge-agents.toml (Codex sweeps .codex/agents/*.toml as per-agent role files and warned on it; the file content is unchanged)."
      else
        CODEX_MOVE_NOTICE="session-start: WARNING could not move .codex/agents/agents.toml to .codex/triforge-agents.toml — move it by hand (Codex warns on the old location)."
      fi
    else
      CODEX_MOVE_NOTICE="session-start: both .codex/agents/agents.toml and .codex/triforge-agents.toml exist — merge and remove the old file by hand (Codex warns on .codex/agents/*.toml)."
    fi
  fi
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml"     ".codex/triforge-agents.toml"
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/codex-agents/AGENTS.md"       ".codex/AGENTS.md"
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/.codex/config.toml" ".codex/config.toml"
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/.codex/hooks.json"  ".codex/hooks.json"
fi

# Bootstrap OpenCode agent definitions (.opencode/agents/) + project config
# (.opencode/opencode.json), copy-if-absent so user customizations survive.
# Guarded on `command -v opencode` — the optional-CLI detection below records
# presence/version; this only provisions the agent-def/config surface when the
# binary is actually installed. invoke_opencode routes builder/reviewer via
# `--agent <name>` from .opencode/agents/ (project tier) with the plugin's
# opencode-agents/ as fallback. Reviewer read-only safety is the agent-def
# permission map (edit/bash deny) plus the OPENCODE_PERMISSION deny rules
# injected at dispatch (R7); the adapter stays off --auto (OC-06 — see
# templates/.opencode/README.md).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && command -v opencode >/dev/null 2>&1; then
  if [ -d "${CLAUDE_PLUGIN_ROOT}/opencode-agents" ]; then
    for f in "${CLAUDE_PLUGIN_ROOT}/opencode-agents"/*.md; do
      [ -f "$f" ] || continue
      _bootstrap_copy "$f" ".opencode/agents/$(basename "$f")"
    done
  fi
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/.opencode/opencode.json" ".opencode/opencode.json"
fi

# Bootstrap Kimi Code project files (.kimi-code/), copy-if-absent so user
# customizations survive. Guarded on `command -v kimi`. Kimi 0.42.0 reversed
# KIMI-03 (D-024): `--agent <name>` / `--agent-file <path>` work in `-p`, so
# roles ride as native agent definitions loaded with --agent-file from the
# plugin's kimi-agents/ (R6; agent definitions are never deployed into
# .agents/agents/ — KTD13). `--skills-dir` is no longer passed: .agents/skills/
# is native and the flag REPLACES auto-discovery. The project
# .kimi-code/config.toml is NOT read by the CLI (only ~/.kimi-code/config.toml
# is) — the two files provisioned here are documentation of the intended
# posture; the real headless confinement is the lease worktree + _adapter_env
# KIMI_* allowlist + KIMI_DISABLE_TELEMETRY (see templates/.kimi-code/README.md).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && command -v kimi >/dev/null 2>&1; then
  for f in AGENTS.md config.toml; do
    _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/.kimi-code/${f}" ".kimi-code/${f}"
  done
fi

# _ss_resolve_cursor_bin — bash re-implementation of the helper's _cursor_bin
# (KTD3, D-025; the hook cannot source invoke-external.sh cheaply): prefer
# `cursor-agent` (the legacy symlink the 2026.09.10 install script still
# ships) and otherwise walk every `agent` on PATH (`which -a agent`), keeping
# the first whose --version (10 s cap) matches Cursor's `YYYY.MM.DD-<hex>`
# format — an unrelated ~/.grok/bin/agent shadows Cursor's `agent` on the
# probe host, so a bare command -v is not enough. Prints the resolved path or
# nothing; without a timeout binary the `agent` walk is skipped (fail-closed).
_ss_resolve_cursor_bin() {
  local BIN VER
  if command -v cursor-agent >/dev/null 2>&1; then
    command -v cursor-agent
    return 0
  fi
  [ -n "$TIMEOUT_BIN" ] || return 0
  while IFS= read -r BIN; do
    [ -n "$BIN" ] && [ -x "$BIN" ] || continue
    VER=$("$TIMEOUT_BIN" 10s "$BIN" --version 2>/dev/null | head -1 || true)
    if printf '%s' "$VER" | LC_ALL=C grep -Eq '^[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[0-9a-f]+'; then
      printf '%s\n' "$BIN"
      return 0
    fi
  done < <(which -a agent 2>/dev/null || true)
  return 0
}
CURSOR_BIN=$(_ss_resolve_cursor_bin)

# Bootstrap Cursor CLI project files, copy-if-absent so user customizations
# survive. Guarded on the resolver above (binary `agent` primary, `cursor-agent`
# legacy per the 2026.09.10 install script). Cursor still has NO headless
# --agent selector, so roles ride as prompt-prefix injection from the plugin's
# cursor-agents/ briefs (invoke_cursor + the lease_dispatch cursor case both
# inject); the .cursor/agents/ copies are delegation targets + documentation,
# and .cursor/README.md records the --trust-required / grok-4.6-pinned-never-
# Auto / CUR-06 headless-hooks-dead / CUR-07 --sandbox-doesn't-confine /
# CUR-08 --mode-plan-is-read-only facts. Shipped default cursor-grok-4.6-xhigh:
# effort is a model-id SUFFIX (-low|-medium|-high|-xhigh) composed at dispatch
# from the roster effort (KTD3), never the bracket form (CUR-10 rejected it).
# No afterFileEdit attribution hook is shipped (CUR-06 FAIL); builder
# attribution is lead-side from the lease ledger. Version capture is handled by
# the optional-CLI detection block below (--version -> .claude/
# roster-detected.local.md, plus the resolved cursor_bin), since Cursor has no
# published semver.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -n "$CURSOR_BIN" ]; then
  if [ -d "${CLAUDE_PLUGIN_ROOT}/cursor-agents" ]; then
    for f in "${CLAUDE_PLUGIN_ROOT}/cursor-agents"/*.md; do
      [ -f "$f" ] || continue
      case "$(basename "$f")" in README.md) continue ;; esac
      _bootstrap_copy "$f" ".cursor/agents/$(basename "$f")"
    done
  fi
  if [ -d "${CLAUDE_PLUGIN_ROOT}/templates/.cursor" ]; then
    for f in "${CLAUDE_PLUGIN_ROOT}/templates/.cursor"/*; do
      [ -f "$f" ] || continue
      _bootstrap_copy "$f" ".cursor/$(basename "$f")"
    done
  fi
fi

# Bootstrap ops/roster.toml — existence-guarded, deliberately OUTSIDE the
# ops-dir bootstrap above so upgraded v2.x projects (which already have ops/)
# still receive it. A user's existing roster is never overwritten. The watch
# registry is NOT bootstrapped: /cli-watch + /repo-watch are repo-local
# maintainer tooling in the agent-triforge checkout, not plugin features.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/ops/roster.toml" "ops/roster.toml"
fi

# Optional-CLI detection (roster tier): presence + version for opencode /
# kimi / cursor, written to .claude/roster-detected.local.md (runtime state,
# regenerated each session start; .claude/*.local.md is gitignored).
# Line format: cli|version|detected-date, plus one interactive=yes|no signal
# line the enrollment unit keys off, plus `cursor_bin=<resolved path>` when the
# resolver above found a Cursor binary (the helper's _cursor_bin may reuse it).
# [ -t 0 ] at hook time is best-effort — hooks often run with stdin piped —
# documented as such; the enrollment branch treats "no" as headless and enrolls
# shipped defaults silently.
ROSTER_DETECTED=".claude/roster-detected.local.md"
OPTIONAL_DETECTED_COUNT=0
DETECTED_OPTIONAL=()
if [ -t 0 ]; then INTERACTIVE_SIGNAL="yes"; else INTERACTIVE_SIGNAL="no"; fi
# Written to a temp file and moved into place (like the two stamps): a bare
# redirect would follow a repo-shipped symlink at .claude/roster-detected.local.md.
ROSTER_DETECTED_TMP="${ROSTER_DETECTED}.tmp.$$"
{
  echo "<!-- runtime state: optional roster CLI detection, regenerated each session start -->"
  echo "interactive=${INTERACTIVE_SIGNAL}"
} > "$ROSTER_DETECTED_TMP"
for PAIR in "opencode:opencode" "kimi:kimi" "cursor:${CURSOR_BIN}"; do
  CLI_NAME=${PAIR%%:*}
  CLI_BIN=${PAIR#*:}
  [ -n "$CLI_BIN" ] || continue      # cursor: resolver found nothing
  if command -v "$CLI_BIN" >/dev/null 2>&1; then
    # Version capture is best-effort: --version first, -V fallback, 10s cap
    # each; a CLI that answers neither is still recorded as present.
    CLI_VERSION=""
    if [ -n "$TIMEOUT_BIN" ]; then
      CLI_VERSION=$("$TIMEOUT_BIN" 10s "$CLI_BIN" --version 2>/dev/null | head -1 || true)
      [ -z "$CLI_VERSION" ] && CLI_VERSION=$("$TIMEOUT_BIN" 10s "$CLI_BIN" -V 2>/dev/null | head -1 || true)
    else
      CLI_VERSION=$("$CLI_BIN" --version 2>/dev/null | head -1 || true)
      [ -z "$CLI_VERSION" ] && CLI_VERSION=$("$CLI_BIN" -V 2>/dev/null | head -1 || true)
    fi
    [ -z "$CLI_VERSION" ] && CLI_VERSION="unknown"
    echo "${CLI_NAME}|${CLI_VERSION}|$(date +%Y-%m-%d)" >> "$ROSTER_DETECTED_TMP"
    [ "$CLI_NAME" = "cursor" ] && echo "cursor_bin=${CLI_BIN}" >> "$ROSTER_DETECTED_TMP"
    OPTIONAL_DETECTED_COUNT=$((OPTIONAL_DETECTED_COUNT + 1))
    DETECTED_OPTIONAL+=("$CLI_NAME")
  fi
done
mv -f "$ROSTER_DETECTED_TMP" "$ROSTER_DETECTED" 2>/dev/null || rm -f "$ROSTER_DETECTED_TMP" 2>/dev/null || true

# First-detection enrollment trigger (R37). For each optional CLI detected THIS
# session with no [members.<cli>] entry yet:
#   headless (interactive=no) -> silently enroll its shipped default now (a hook
#     cannot prompt); the lease layer records the resolved model at dispatch.
#   interactive (=yes)        -> emit an orientation line pointing at /setup.
# All writes go through the single-writer roster writer (roster_write_member) in
# invoke-external.sh — never a hand-rolled write here. Fast: headless enrollment
# does no live auth probe; each helper call is tomllib-only.
ENROLLMENT_NOTICES=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh" ] && [ "${#DETECTED_OPTIONAL[@]}" -gt 0 ]; then
  # shellcheck source=/dev/null
  source "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh"
  for CLI_NAME in "${DETECTED_OPTIONAL[@]}"; do
    ENROLL_HAS_RC=0
    roster_has_member "$CLI_NAME" || ENROLL_HAS_RC=$?
    [ "$ENROLL_HAS_RC" -eq 0 ] && continue   # already enrolled or declined — never re-ask (AE6)
    [ "$ENROLL_HAS_RC" -eq 2 ] && continue   # roster unparseable — leave it to resolve_role to surface loudly
    if [ "$INTERACTIVE_SIGNAL" = "no" ]; then
      roster_enroll_member "$CLI_NAME" headless >/dev/null 2>&1 || true
    else
      ENROLL_DEF=$(roster_member_default "$CLI_NAME" 2>/dev/null || true)
      ENROLLMENT_NOTICES="${ENROLLMENT_NOTICES}\nNew optional CLI detected: ${CLI_NAME} (unenrolled). Run /setup to enroll, or it enrolls with its shipped default (${ENROLL_DEF}) on first headless use."
    fi
  done
fi

# Enrolled count = [members.*] entries in ops/roster.toml when present
# (tolerant: a malformed roster must not break session start — it reports 0
# here and resolve_role raises the loud parse error at first use).
ENROLLED_COUNT=0
if [ -f "ops/roster.toml" ]; then
  ENROLLED_COUNT=$(python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print(0); sys.exit(0)
try:
    with open('ops/roster.toml', 'rb') as f:
        data = tomllib.load(f)
    members = data.get('members', {})
    print(sum(1 for v in members.values() if isinstance(v, dict)) if isinstance(members, dict) else 0)
except Exception:
    print(0)
" 2>/dev/null || echo 0)
fi

# Roster pin drift (informational): persisted [members.*].model / [roles.*].model
# values that differ from the shipped defaults. An upgraded project keeps
# whatever its roster carries — a pin is never rewritten here — so one line per
# differing pin points at /setup. The SHIPPED map mirrors CLI_DEFAULT_MODEL in
# resolve_role (scripts/invoke-external.sh) and templates/ops/roster.toml; keep
# the three in sync (validate-versions.sh check 3 diffs the SHIPPED / ROLE_CLI
# literals below against CLI_DEFAULT_MODEL / DEFAULTS). An effort
# variant of the default is NOT drift: the agy `(Low|Medium|High)` suffix and
# the Cursor `-low|-medium|-high|-xhigh` suffix are effort controls (KTD3, KTD6),
# so both sides are compared with that suffix stripped. Tolerant: a malformed
# roster prints nothing (resolve_role raises the loud error later).
ROSTER_DRIFT_NOTICES=""
if [ -f "ops/roster.toml" ]; then
  ROSTER_DRIFT_NOTICES=$(python3 -c '
import re, sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
SHIPPED = {
    "antigravity": "Gemini 3.8 Flash (High)",
    "codex": "gpt-6-astra",
    "opencode": "openrouter/z-ai/glm-5.3",
    "kimi": "kimi-code/k3",
    "cursor": "cursor-grok-4.6-xhigh",
}
ROLE_CLI = {"builder": "claude", "reviewer": "codex", "tester": "codex",
            "analyst": "antigravity", "documenter": "antigravity"}
def norm(cli, model):
    if cli == "antigravity":
        return re.sub(r"\s*\((Low|Medium|High)\)\s*$", "", model)
    if cli == "cursor":
        return re.sub(r"-(low|medium|high|xhigh)$", "", model)
    return model
try:
    with open("ops/roster.toml", "rb") as f:
        data = tomllib.load(f)
    lines = []
    members = data.get("members", {})
    if isinstance(members, dict):
        for name in sorted(members):
            entry = members[name]
            if not isinstance(entry, dict) or name not in SHIPPED:
                continue
            model = str(entry.get("model", "") or "")
            if model and norm(name, model) != norm(name, SHIPPED[name]):
                lines.append("Roster pin differs from the shipped default: members.%s.model=%s (shipped: %s) — run /setup to re-enroll, or edit ops/roster.toml" % (name, model, SHIPPED[name]))
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
                lines.append("Roster pin differs from the shipped default: roles.%s.model=%s (shipped: %s) — run /setup roles to re-default" % (name, model, shipped))
    for line in lines:
        print(line)
except Exception:
    pass
' 2>/dev/null || true)
fi

# Suggest CLAUDE.md template if not present (either supported location)
if [ ! -f "CLAUDE.md" ] && [ ! -f ".claude/CLAUDE.md" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md" ]; then
  CLAUDE_MD_TIP="\nTip: No CLAUDE.md found. Copy the template: cp \"${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md\" ./CLAUDE.md"
fi

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

if [ "$HAS_STATE" = "yes" ]; then
  MSG="$MSG\nPrevious session state found (ops/STATE.md). Use /resume to continue."
fi

if [ "$HAS_TASKS" = "yes" ]; then
  MSG="$MSG\nActive sprint found (ops/TASKS.md): $PENDING_COUNT pending, $IN_PROGRESS_COUNT in progress, $BLOCKED_COUNT blocked."
fi

if [ "$HAS_GOALS" = "yes" ]; then
  MSG="$MSG\nProject goals found (ops/GOALS.md)."
fi

if [ "$HAS_AGENTS" = "yes" ]; then
  MSG="$MSG\nAgent protocol found (ops/AGENTS.md)."
fi

if [ "$HAS_REVIEWS" = "yes" ]; then
  MSG="$MSG\nUnprocessed review files found. Consider running /review to process them."
fi

if [ "$SOLUTION_COUNT" -gt "0" ]; then
  MSG="$MSG\nInstitutional knowledge: $SOLUTION_COUNT documented solutions in ops/solutions/."
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
  CODEX_AGENT_COUNT=$(python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        sys.exit(0)
with open('.codex/triforge-agents.toml','rb') as f:
    data = tomllib.load(f)
# Filter to dict values only — [agents] also holds scalar Triforge-internal
# declarations (max_depth, max_threads, default_subagent_*) alongside the
# agent subtables.
print(sum(1 for v in data.get('agents', {}).values() if isinstance(v, dict)))
" 2>/dev/null || grep -c '^\[agents\.' .codex/triforge-agents.toml 2>/dev/null || true)
  if [ "$CODEX_AGENT_COUNT" -gt "0" ]; then
    HAS_CODEX_AGENTS="yes"
  fi
fi

if [ "$HAS_ANTIGRAVITY_AGENTS" = "yes" ] || [ "$HAS_CODEX_AGENTS" = "yes" ]; then
  AGENT_PARTS=""
  [ "$HAS_ANTIGRAVITY_AGENTS" = "yes" ] && AGENT_PARTS="${ANTIGRAVITY_AGENT_COUNT} Antigravity"
  [ "$HAS_CODEX_AGENTS" = "yes" ] && AGENT_PARTS="${AGENT_PARTS:+${AGENT_PARTS} + }${CODEX_AGENT_COUNT} Codex"
  MSG="$MSG\nExternal agent definitions loaded: ${AGENT_PARTS}."
fi

# Roster orientation (KTD-2): optional members detected this session, and how
# many carry [members.*] enrollment entries in ops/roster.toml.
MSG="$MSG\nRoster: core trio + ${OPTIONAL_DETECTED_COUNT} optional member(s) detected (${ENROLLED_COUNT} enrolled)."
MSG="$MSG${ENROLLMENT_NOTICES:-}"
if [ -n "$ROSTER_DRIFT_NOTICES" ]; then
  MSG="$MSG\n${ROSTER_DRIFT_NOTICES}"
fi

# Migration notices (one per step that acted this session; silent otherwise).
MSG="$MSG${SKILLS_NOTICES:-}"
if [ -n "$AGY_PACK_NOTICE" ]; then
  MSG="$MSG\n${AGY_PACK_NOTICE}"
fi
if [ -n "$CODEX_MOVE_NOTICE" ]; then
  MSG="$MSG\n${CODEX_MOVE_NOTICE}"
fi

# Lease-ledger resume orientation (KTD-4/U9): report active leases left by a
# previous session. Deliberately NO auto-prune here — a session-start hook
# must never delete worktrees; /resume or the wave protocol runs
# lease_heartbeat_check, whose safe-prune path does the reclamation.
ACTIVE_LEASES=0
if [ -f "ops/leases.toml" ]; then
  ACTIVE_LEASES=$(python3 -c "
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
    with open('ops/leases.toml', 'rb') as f:
        data = tomllib.load(f)
    leases = data.get('lease', {})
    active = ('building', 'leased', 'orphaned')
    print(sum(1 for v in (leases.values() if isinstance(leases, dict) else [])
              if isinstance(v, dict) and v.get('state') in active))
except Exception:
    print(0)
" 2>/dev/null || echo 0)
fi
if [ "${ACTIVE_LEASES:-0}" -gt 0 ] 2>/dev/null; then
  MSG="$MSG\nLease ledger: ${ACTIVE_LEASES} active lease(s) from a previous session — run lease_heartbeat_check (or /resume) to reclaim orphans."
fi

if [ "$HAS_TASKS" != "yes" ] && [ "$HAS_STATE" != "yes" ]; then
  MSG="$MSG\nNo active sprint. Use /plan <goal> to start or /ship <goal> for full autonomous mode."
fi

# Append timeout-missing warning if set
if [ -n "${TIMEOUT_MISSING_WARNING}" ]; then
  MSG="$MSG\n${TIMEOUT_MISSING_WARNING}"
fi

# Append CLAUDE.md tip if set
MSG="$MSG${CLAUDE_MD_TIP:-}"

printf '%b\n' "Multi-agent framework ready.$MSG"
echo ""
echo "Commands: /setup /ship /plan /build /review /test /debug /quick /deep-research /analyze /coordinate /resolve-pr /status /pause /resume /wrap /compound"

exit 0
