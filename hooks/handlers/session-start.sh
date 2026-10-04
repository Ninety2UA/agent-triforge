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
#   Audited 2026-10-01: every stdout line is prose ("Multi-agent framework
#   ready.", "session-start: …", "Roster …", "WARNING: …", "Tip: …",
#   "Lead workflows: …");
#   every external-CLI capture (agy plugin list / agy agents / claude
#   --version) is consumed here and never echoed — the floor warning prints
#   only the X.Y.Z digits parsed out of it.
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

# _ss_run — the rest of this hook, from the ops/ bootstrap to the orientation
# message, as one function: it runs inside the subshell that sources the helper
# (the block at the end of this file) or, when the helper does not load, in the
# hook's own shell with SS_HELPER empty. The body is the hook's linear flow and
# stays at column 0.
_ss_run() {

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
# (~/.gemini/antigravity-cli/settings.json — never touched here; at-setup
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
# .agents/skills/ refresh (KTD12, R31) — the agy workspace-skills tier AND the
# cross-CLI agentskills.io path (Codex, OpenCode, Cursor and Kimi all read it).
# Copies, never symlinks, so loaders that refuse to follow symlinks across
# mount boundaries still see the skills.
#
# The work is done by scripts/lib/skills-sync.py, which _lease_provision_skills
# also runs for each lease worktree, so both follow one ownership rule:
# Triforge replaces or retires a directory only when its content digest
# matches the digest recorded in the stamp .agents/skills/.triforge-plugin-
# version for that name (a 3.3.0–3.3.2 stamp without digests is migrated
# against scripts/lib/skill-digests.txt, the digests of every released copy).
# Anything else is user-owned: kept, with one notice naming it. With no stamp,
# only empty slots are written. The stamp is safe to commit in a user project
# (this repo ignores /.agents/); an unchanged plugin version is a no-op with no
# notice, and the stamp is written last, so an interrupted refresh re-runs on
# the next session start. A symlinked .agents or .agents/skills, or one that
# resolves outside the project, is left untouched with one notice.
SKILLS_NOTICES=""
SS_SKILLS_SYNC="${CLAUDE_PLUGIN_ROOT:-}/scripts/lib/skills-sync.py"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/skills" ]; then
  if [ -f "$SS_SKILLS_SYNC" ]; then
    # A crash or a timeout must not abort the hook (set -e), but it must not be
    # silent either: the exit status is kept and reported as a notice below.
    SS_SYNC_OUT=""
    SS_SYNC_RC=0
    if [ -n "$TIMEOUT_BIN" ]; then
      SS_SYNC_OUT=$("$TIMEOUT_BIN" 60s python3 "$SS_SKILLS_SYNC" sync --plugin-root "$CLAUDE_PLUGIN_ROOT" --project . --prefix "session-start: " 2>/dev/null) || SS_SYNC_RC=$?
    else
      SS_SYNC_OUT=$(python3 "$SS_SKILLS_SYNC" sync --plugin-root "$CLAUDE_PLUGIN_ROOT" --project . --prefix "session-start: " 2>/dev/null) || SS_SYNC_RC=$?
    fi
    while IFS= read -r SS_LINE; do
      if [ -n "$SS_LINE" ]; then SKILLS_NOTICES="${SKILLS_NOTICES}\n${SS_LINE}"; fi
    done <<SS_SYNC_EOF
${SS_SYNC_OUT}
SS_SYNC_EOF
    if [ "$SS_SYNC_RC" -ne 0 ]; then
      SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: WARNING .agents/skills refresh failed (skills-sync.py exit ${SS_SYNC_RC}; 124 means the 60 s timeout) — skills may be stale; the refresh re-runs next session."
    fi
  else
    SKILLS_NOTICES="${SKILLS_NOTICES}\nsession-start: WARNING ${SS_SKILLS_SYNC} is missing — .agents/skills not refreshed (reinstall the plugin)."
  fi
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

# _ss_is_3x_codex_hooks <file> — 0 when the file is byte-equal to the one 3.x
# templates/.codex/hooks.json (sha256 below): Triforge's own copy of the
# attribution hook that appended to ops/CHANGELOG.md and wrote
# .claude/codex-changelog.* from every Codex session, inside lease worktrees
# too. The grep is a cheap gate in front of the hash, which decides.
SS_3X_CODEX_HOOKS_SHA256="9aece38547f04f98c9cd158538cb31e654c1fa3767de414afbab1bd50b8f140c"
_ss_is_3x_codex_hooks() {
  [ -f "$1" ] && [ ! -L "$1" ] || return 1
  grep -qF 'codex-changelog' "$1" 2>/dev/null || return 1
  [ "$(python3 -c 'import hashlib, sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$1" 2>/dev/null || true)" = "$SS_3X_CODEX_HOOKS_SHA256" ]
}

# Bootstrap Codex project files (.codex/*), copy-if-absent so user
# customizations survive: triforge-agents.toml = Triforge's agent declarations
# (KTD5 — deployed OUTSIDE .codex/agents/, which Codex ≥ 0.147 sweeps as
# per-agent role files and warns "Ignoring malformed agent role definition" on);
# config.toml disables Codex's auto-memory
# pipeline (conflict with ops/MEMORY.md); hooks.json ships with no hooks since
# 4.0 (KTD9: the 3.x CHANGELOG attribution hook wrote ops/ from every Codex
# session, lease workers included; attribution now comes from the ledger). See
# templates/.codex/README.md and ops/decisions/2026-07-18-codex-hooks-under-exec.md.
CODEX_MOVE_NOTICE=""
CODEX_HOOK_NOTICE=""
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
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/.codex/config.toml" ".codex/config.toml"
  # One-time migration (KTD9): a .codex/hooks.json still byte-equal to the 3.x
  # template (_ss_is_3x_codex_hooks) is replaced once by the 4.0 template. An
  # edited copy is the user's and is left alone.
  if [ -f "${CLAUDE_PLUGIN_ROOT}/templates/.codex/hooks.json" ] && _ss_is_3x_codex_hooks ".codex/hooks.json"; then
    if cp "${CLAUDE_PLUGIN_ROOT}/templates/.codex/hooks.json" ".codex/hooks.json" 2>/dev/null; then
      CODEX_HOOK_NOTICE="session-start: replaced .codex/hooks.json — the unchanged 3.x copy appended a line to ops/CHANGELOG.md from every Codex session, lease workers included; attribution now comes from the lease ledger."
    else
      CODEX_HOOK_NOTICE="session-start: WARNING could not replace the 3.x .codex/hooks.json, which writes ops/CHANGELOG.md from every Codex session — copy templates/.codex/hooks.json over it by hand."
    fi
  fi
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

# The Cursor binary comes from the helper's own resolver, _cursor_bin (KTD3,
# D-025 — `cursor-agent` first, else the first `agent` on PATH whose --version
# matches Cursor's `YYYY.MM.DD-<hex>` format under a 15 s cap, fail-closed
# without a timeout tool): the registry names it as cursor's resolver, so this
# hook carries no re-implementation. Empty when the helper did not load or
# nothing resolved.
CURSOR_BIN=""
if [ -n "$SS_HELPER" ]; then
  # Run in this shell, not a $(...): the TRIFORGE_CURSOR_BIN export a hit leaves
  # behind makes the detection loop's resolver call below a lookup, not a probe.
  if _cursor_bin >/dev/null 2>&1; then CURSOR_BIN="$TRIFORGE_CURSOR_BIN"; fi
fi

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

# Optional-CLI detection (roster tier): presence + version for every optional
# member of the CLI registry (cli_table optional — opencode / kimi / cursor
# today), written to .claude/roster-detected.local.md (runtime state,
# regenerated each session start; .claude/*.local.md is gitignored).
# Line format: cli|version|detected-date, plus one interactive=yes|no signal
# line the enrollment unit keys off, plus `<cli>_bin=<resolved path>` for a
# member whose registry entry names a resolver (cursor: `cursor_bin=` from
# _cursor_bin, since the binary that answered may be an `agent`, not the name).
# [ -t 0 ] at hook time is best-effort — hooks often run with stdin piped —
# documented as such; the enrollment branch treats "no" as headless and enrolls
# shipped defaults silently. With no helper loaded nothing is detected, and
# SS_HELPER_NOTICE says so — whether the loader failed or CLAUDE_PLUGIN_ROOT
# named no loader at all (unset, or a root without scripts/invoke-external.sh).
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
SS_OPTIONAL_ROWS=""
if [ -n "$SS_HELPER" ]; then
  SS_OPTIONAL_ROWS=$(cli_table optional binary resolver 2>/dev/null || true)
fi
# One registry read for the tier (cli_table: name, binary, resolver per line);
# each member's binary is then resolved from its own row (_registry_binary, no
# further read) and probed with command -v before anything else runs. The rows
# arrive on fd 3 so the version probes keep the hook's stdin.
while IFS=$'\t' read -r -u 3 CLI_NAME CLI_BIN CLI_RESOLVER; do
  [ -n "$CLI_NAME" ] || continue
  CLI_BIN=$(_registry_binary "$CLI_NAME" "$CLI_BIN" "$CLI_RESOLVER" 2>/dev/null || true)
  [ -n "$CLI_BIN" ] || continue
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
    if [ -n "$CLI_RESOLVER" ]; then
      echo "${CLI_NAME}_bin=${CLI_BIN}" >> "$ROSTER_DETECTED_TMP"
    fi
    OPTIONAL_DETECTED_COUNT=$((OPTIONAL_DETECTED_COUNT + 1))
    DETECTED_OPTIONAL+=("$CLI_NAME")
  fi
done 3<<SS_OPTIONAL_EOF
${SS_OPTIONAL_ROWS}
SS_OPTIONAL_EOF
mv -f "$ROSTER_DETECTED_TMP" "$ROSTER_DETECTED" 2>/dev/null || rm -f "$ROSTER_DETECTED_TMP" 2>/dev/null || true

# First-detection enrollment trigger (R37). For each optional CLI detected THIS
# session with no [members.<cli>] entry yet:
#   headless (interactive=no) -> silently enroll its shipped default now (a hook
#     cannot prompt); the lease layer records the resolved model at dispatch.
#   interactive (=yes)        -> emit an orientation line pointing at /at-setup.
# All writes go through the single-writer roster writer (roster_write_member) in
# the helper sourced above — never a hand-rolled write here. Fast: headless
# enrollment does no live auth probe; each helper call is tomllib-only.
ENROLLMENT_NOTICES=""
if [ -n "$SS_HELPER" ] && [ "${#DETECTED_OPTIONAL[@]}" -gt 0 ]; then
  for CLI_NAME in "${DETECTED_OPTIONAL[@]}"; do
    ENROLL_HAS_RC=0
    roster_has_member "$CLI_NAME" || ENROLL_HAS_RC=$?
    [ "$ENROLL_HAS_RC" -eq 0 ] && continue   # already enrolled or declined — never re-ask (AE6)
    [ "$ENROLL_HAS_RC" -eq 2 ] && continue   # roster unparseable — leave it to resolve_role to surface loudly
    if [ "$INTERACTIVE_SIGNAL" = "no" ]; then
      roster_enroll_member "$CLI_NAME" headless >/dev/null 2>&1 || true
    else
      ENROLL_DEF=$(roster_member_default "$CLI_NAME" 2>/dev/null || true)
      ENROLLMENT_NOTICES="${ENROLLMENT_NOTICES}\nNew optional CLI detected: ${CLI_NAME} (unenrolled). Run /at-setup to enroll, or it enrolls with its shipped default (${ENROLL_DEF}) on first headless use."
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
  ROSTER_DRIFT_NOTICES=$(TRIFORGE_CLIS_PY="${_TRIFORGE_CLIS_PY:-}" TRIFORGE_ROLE_DEFAULTS_PY="${_ROLE_DEFAULTS_PY:-}" python3 -c '
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
                lines.append("Roster pin differs from the shipped default: members.%s.model=%s (shipped: %s) — run /at-setup to re-enroll, or edit ops/roster.toml" % (name, model, SHIPPED[name]))
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
                lines.append("Roster pin differs from the shipped default: roles.%s.model=%s (shipped: %s) — run /at-setup roles to re-default" % (name, model, shipped))
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
# CLAUDE.md that imports it (`@AGENTS.md`) loads it on every build. Three
# states leave a Claude lead without it, and each gets one line:
#   floor   `claude --version` below 2.1.277
#   stale   ./CLAUDE.md or ./.claude/CLAUDE.md is a 3.x copy of the retired
#           templates/CLAUDE.md that does not import AGENTS.md
#   above   a CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md in a directory
#           above the project, with no import of the project's AGENTS.md
#           anywhere in the chain
# These describe a standing state, not a one-time action: they print on every
# session start until the state is fixed, and so — like the roster-pin and
# timeout lines — carry no "session-start:" prefix (that prefix marks a step
# that acted once; SELF-08 counts it for idempotence). Nothing here edits a
# file: each line names the edit and leaves it to the user.
CLAUDE_FLOOR="2.1.277"
INSTRUCTION_NOTICES=""
# The instruction files Claude Code reads in a directory, and this project's
# physical path (/tmp and /var are symlinks on macOS).
SS_INSTRUCTION_FILES="CLAUDE.md .claude/CLAUDE.md CLAUDE.local.md"
SS_PROJECT=$(pwd -P 2>/dev/null || true)

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

# _ss_bounded <seconds> <command…> — the command's stdout, the command given
# up on after <seconds>: under the timeout binary when there is one, and on a
# host without one (stock macOS) under a watchdog — the command runs in the
# background, a second background subshell kills it when the time is up, and
# the watchdog is killed as soon as the command returns. The answer travels
# through a temp file and the watchdog's stdio is /dev/null, so nothing a
# killed command leaves running holds the caller's command substitution open;
# each `wait` swallows bash's "Terminated" line.
_ss_bounded() {
  local SECS="$1" OUT CMD_PID DOG_PID
  shift
  if [ -n "$TIMEOUT_BIN" ]; then
    "$TIMEOUT_BIN" "${SECS}s" "$@" 2>/dev/null || true
    return 0
  fi
  OUT=$(mktemp "${TMPDIR:-/tmp}/triforge-session-start.XXXXXX" 2>/dev/null) || return 0
  "$@" </dev/null >"$OUT" 2>/dev/null &
  CMD_PID=$!
  ( sleep "$SECS"; kill "$CMD_PID" ) </dev/null >/dev/null 2>&1 &
  DOG_PID=$!
  wait "$CMD_PID" 2>/dev/null || true
  kill "$DOG_PID" 2>/dev/null || true
  wait "$DOG_PID" 2>/dev/null || true
  cat "$OUT" 2>/dev/null || true
  rm -f "$OUT"
}

# Floor. The answer is read with a 10 s bound, timeout binary or not — a hung
# `claude` must not stall session start. A missing `claude`, one that does not
# answer in time, or an answer with no X.Y.Z in it warns about nothing.
if command -v claude >/dev/null 2>&1; then
  SS_CLAUDE_XYZ=$(_ss_xyz "$(_ss_bounded 10 claude --version | head -1 || true)")
  if [ -n "$SS_CLAUDE_XYZ" ] && [ "$(_ss_xyz_key "$SS_CLAUDE_XYZ")" -lt "$(_ss_xyz_key "$CLAUDE_FLOOR")" ]; then
    INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}\nWARNING: Claude Code ${SS_CLAUDE_XYZ} is below Triforge's floor ${CLAUDE_FLOOR}, the first build that reads AGENTS.md — Triforge's only instruction file, which older builds do not read. Update Claude Code (\`claude update\`)."
  fi
fi

# _ss_imports_agents <file> — 0 when the file imports THIS project's AGENTS.md.
# An import is an `@AGENTS.md` / `@<path>/AGENTS.md` token at a line start or
# after whitespace (a backticked mention is prose, not an import), and its path
# is relative to the directory of the file that holds it (`~/` is the home
# directory; an absolute path stands). So a bare `@AGENTS.md` in a parent's
# CLAUDE.md, or in this project's .claude/CLAUDE.md, names some other
# AGENTS.md and does not count: a token counts when its directory, resolved
# physically, is the project's. A directory that does not exist counts for
# nothing, and neither does a token that goes on after the name
# (@AGENTS.md.bak, @AGENTS.md_old): only trailing punctuation or a #fragment may
# follow it.
SS_IMPORT_RE='^@(([^[:space:]]*/)?)AGENTS\.md([.,;:!?)]*|#[^[:space:]]*)$'
_ss_imports_agents() {
  local BASE WORDS WORD DIR
  [ -f "$1" ] || return 1
  [ -n "$SS_PROJECT" ] || return 1
  case "$1" in
    /*)  BASE="${1%/*}" ;;
    */*) BASE="./${1%/*}" ;;
    *)   BASE="." ;;
  esac
  WORDS=$(LC_ALL=C tr -s '[:space:]' '\n' 2>/dev/null < "$1" | LC_ALL=C grep -aE "$SS_IMPORT_RE" 2>/dev/null || true)
  [ -n "$WORDS" ] || return 1
  while IFS= read -r WORD; do
    [[ "$WORD" =~ $SS_IMPORT_RE ]] || continue
    DIR="${BASH_REMATCH[1]}"
    case "$DIR" in
      "~/"*)
        case "${HOME:-}" in
          /*) DIR="${HOME%/}/${DIR#??}" ;;
          *)  continue ;;
        esac
        ;;
      /*) ;;
      *)  DIR="${BASE}/${DIR}" ;;
    esac
    DIR=$(cd "$DIR" 2>/dev/null && pwd -P 2>/dev/null) || continue
    if [ "$DIR" = "$SS_PROJECT" ]; then return 0; fi
  done <<SS_IMPORTS_EOF
$WORDS
SS_IMPORTS_EOF
  return 1
}

# _ss_is_3x_template <file> — 0 when the file is a copy, customized or not, of
# the 3.x templates/CLAUDE.md. Fingerprint, taken from the template at every
# v3.* tag (v3.0.0 … v3.3.3, five distinct versions): its signature line plus
# at least 3 of the 8 Triforge-specific section headings all of them carry, at
# any heading level. A copy with sections removed, added or reworded still
# matches; a CLAUDE.md that only shares section names, or only quotes the
# signature, does not.
_ss_is_3x_template() {
  local HITS
  [ -f "$1" ] || return 1
  LC_ALL=C grep -qF 'It works with the **Agent Triforge** plugin' "$1" 2>/dev/null || return 1
  HITS=$(LC_ALL=C grep -Ec '^#{1,6}[[:space:]]+(Multi-agent system|Four coordination modes|Shared file protocol|Execution phases|Assignment heuristic|Portable skills|Specialized agents|Agent invocation patterns)' "$1" 2>/dev/null || true)
  [ "${HITS:-0}" -ge 3 ]
}

# _ss_import_line <name> <prefix> — set SS_IMPORT to the line that imports this
# project's AGENTS.md from the instruction file <name> (CLAUDE.md,
# CLAUDE.local.md or .claude/CLAUDE.md), <prefix> being the path from that
# file's directory down to the project ("" in the project itself). An import
# path is relative to the file that holds it, so a .claude/ file goes up one.
_ss_import_line() {
  case "$1" in
    .claude/*) SS_IMPORT="@../${2}AGENTS.md" ;;
    *)         SS_IMPORT="@${2}AGENTS.md" ;;
  esac
}

# Stale template. Only the two locations the 3.x template was copied to are
# fingerprinted (it was never a CLAUDE.local.md).
SS_CHAIN_IMPORTS=""
for SS_FILE in $SS_INSTRUCTION_FILES; do
  if _ss_imports_agents "$SS_FILE"; then SS_CHAIN_IMPORTS="yes"; fi
done
for SS_FILE in CLAUDE.md .claude/CLAUDE.md; do
  if _ss_is_3x_template "$SS_FILE" && ! _ss_imports_agents "$SS_FILE"; then
    _ss_import_line "$SS_FILE" ""
    INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}\nWARNING: ${SS_FILE} is a Triforge 3.x project template (a copy of the retired templates/CLAUDE.md). Triforge 4 ships AGENTS.md only, and Claude Code does not read AGENTS.md while this file exists without importing it. Add the line ${SS_IMPORT} to it, or replace its Triforge content with the pointer block in the plugin's templates/AGENTS.md — session start never edits this file."
  fi
done

# Above the project: every parent up to /. $HOME/.claude/CLAUDE.md is the
# user-tier file and is skipped (both paths compared physically). One import
# of the project's AGENTS.md anywhere in the chain, the project's own files
# included, loads it, so it silences every line here.
SS_ABOVE_NOTICES=""

# _ss_prose <path> — the path as it may appear in MSG: control characters
# dropped and backslashes doubled (MSG is expanded by printf %b, and no stdout
# line may start with `{` — a newline in a directory name must not make one).
_ss_prose() {
  local TEXT
  TEXT=$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')
  printf '%s' "${TEXT//\\/\\\\}"
}

SS_HOME_REAL=""
if [ -n "${HOME:-}" ] && [ -d "${HOME}" ]; then
  SS_HOME_REAL=$(cd "$HOME" 2>/dev/null && pwd -P || true)
fi
case "$SS_PROJECT" in
  /*)
    SS_DIR="$SS_PROJECT"
    while [ -n "$SS_DIR" ] && [ "$SS_DIR" != "/" ]; do
      SS_DIR="${SS_DIR%/*}"
      if [ -z "$SS_DIR" ]; then SS_DIR="/"; fi
      SS_REL="${SS_PROJECT#"${SS_DIR%/}"/}"
      for SS_NAME in $SS_INSTRUCTION_FILES; do
        SS_FILE="${SS_DIR%/}/${SS_NAME}"
        [ -f "$SS_FILE" ] || continue
        if [ -n "$SS_HOME_REAL" ] && [ "$SS_FILE" = "${SS_HOME_REAL%/}/.claude/CLAUDE.md" ]; then continue; fi
        if _ss_imports_agents "$SS_FILE"; then SS_CHAIN_IMPORTS="yes"; fi
        _ss_import_line "$SS_NAME" "${SS_REL}/"
        SS_ABOVE_NOTICES="${SS_ABOVE_NOTICES}\nWARNING: AGENTS.md is not loaded under a Claude lead: $(_ss_prose "$SS_FILE") sits above this project, and Claude Code reads AGENTS.md only while no CLAUDE.md, .claude/CLAUDE.md or CLAUDE.local.md exists in the working directory or above it. Add the line $(_ss_prose "$SS_IMPORT") to that file (an import path is relative to the file that holds it), or remove the file."
      done
    done
    ;;
esac
if [ -z "$SS_CHAIN_IMPORTS" ]; then
  INSTRUCTION_NOTICES="${INSTRUCTION_NOTICES}${SS_ABOVE_NOTICES}"
fi

# Pointer-block tip: a project with no root AGENTS.md carries nothing that
# tells an agent Triforge runs here. A standing tip, printed until the file
# exists; session start does not create it.
AGENTS_MD_TIP=""
if [ ! -e "AGENTS.md" ] && [ ! -L "AGENTS.md" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/AGENTS.md" ]; then
  AGENTS_MD_TIP="\nTip: No AGENTS.md in this project. Triforge's pointer block (the short section that tells every agent this project runs the framework) ships as the plugin's templates/AGENTS.md. Copy it: cp \"$(_ss_prose "$CLAUDE_PLUGIN_ROOT")/templates/AGENTS.md\" ./AGENTS.md"
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
  MSG="$MSG\nPrevious session state found (ops/STATE.md). Use /at-resume to continue."
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
  MSG="$MSG\nUnprocessed review files found. Consider running /at-review to process them."
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
  MSG="$MSG\nExternal agent definitions loaded: ${AGENT_PARTS}."
fi

# Roster orientation (KTD-2): optional members detected this session, and how
# many carry [members.*] enrollment entries in ops/roster.toml.
MSG="$MSG\nRoster: core trio + ${OPTIONAL_DETECTED_COUNT} optional member(s) detected (${ENROLLED_COUNT} enrolled)."
MSG="$MSG${ENROLLMENT_NOTICES:-}"
if [ -n "$ROSTER_DRIFT_NOTICES" ]; then
  MSG="$MSG\n${ROSTER_DRIFT_NOTICES}"
fi
if [ -n "$SS_HELPER_NOTICE" ]; then
  MSG="$MSG\n${SS_HELPER_NOTICE}"
fi

# Migration notices (one per step that acted this session; silent otherwise).
MSG="$MSG${SKILLS_NOTICES:-}"
if [ -n "$AGY_PACK_NOTICE" ]; then
  MSG="$MSG\n${AGY_PACK_NOTICE}"
fi
if [ -n "$CODEX_MOVE_NOTICE" ]; then
  MSG="$MSG\n${CODEX_MOVE_NOTICE}"
fi
if [ -n "$CODEX_HOOK_NOTICE" ]; then
  MSG="$MSG\n${CODEX_HOOK_NOTICE}"
fi

# Upgrade notices (R40): standing states, repeated every session until fixed.
MSG="$MSG${INSTRUCTION_NOTICES:-}"

# Lease-ledger resume orientation (KTD-4/U9): report active leases left by a
# previous session. Deliberately NO auto-prune here — a session-start hook
# must never delete worktrees; at-resume or the wave protocol runs
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
  MSG="$MSG\nLease ledger: ${ACTIVE_LEASES} active lease(s) from a previous session — run lease_heartbeat_check (or /at-resume) to reclaim orphans."
fi

if [ "$HAS_TASKS" != "yes" ] && [ "$HAS_STATE" != "yes" ]; then
  MSG="$MSG\nNo active sprint. Use /at-plan <goal> to start or /at-ship <goal> for full autonomous mode."
fi

# Append timeout-missing warning if set
if [ -n "${TIMEOUT_MISSING_WARNING}" ]; then
  MSG="$MSG\n${TIMEOUT_MISSING_WARNING}"
fi

# Append the pointer-block tip if set
MSG="$MSG${AGENTS_MD_TIP:-}"

printf '%b\n' "Multi-agent framework ready.$MSG"
echo ""
echo 'Lead workflows (/at-<name> here, $at-<name> in a Codex prompt): at-setup at-ship at-plan at-build at-review at-test at-debug at-quick at-deep-research at-analyze at-coordinate at-resolve-pr at-status at-pause at-resume at-wrap at-compound'

exit 0
}

# The helper (scripts/invoke-external.sh) — sourced ONCE, in the subshell that
# then runs _ss_run, so the hook reads the CLI registry (scripts/lib/registry.sh,
# KTD7) for the optional members, their binaries and shipped models, and the
# roster helpers for enrollment, instead of carrying copies. Degraded, never
# fatal: a loader that `exit`s rather than `return`s, or trips set -u, ends only
# that subshell. Its stdout and stderr land in one file in a private temp dir
# (the source's stdout is never the hook's: a loader that prints a JSON-shaped
# line before failing must not start a stdout line with `{`) beside the `loaded`
# marker the subshell writes once the source succeeded (plain files, no extra
# fd: a descriptor would be inherited by every child, and a probe the watchdog
# in _ss_bounded leaves behind must not hold the hook's stdout). No marker: the
# helper did not load, so _ss_run runs below in this shell with SS_HELPER empty
# — optional-CLI detection, enrollment and the roster pin check are skipped and
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
  SS_HELPER_TMP=$(mktemp -d "${TMPDIR:-/tmp}/triforge-session-start.XXXXXX" 2>/dev/null || mktemp -d ".claude/triforge-session-start.XXXXXX" 2>&1) || SS_HELPER_RC=$?
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
  else
    SS_HELPER_ERR=$(printf '%s' "$SS_HELPER_TMP" | head -1 | cut -c1-160)
  fi
  SS_HELPER_NOTICE="WARNING: the Triforge helper did not load (${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh exited ${SS_HELPER_RC}: ${SS_HELPER_ERR}) — optional-CLI detection, enrollment and the roster pin check were skipped this session. Reinstall the plugin: claude plugin install agent-triforge@agent-triforge"
else
  # No loader to source: the plugin host did not export CLAUDE_PLUGIN_ROOT, or
  # it names a tree without scripts/invoke-external.sh. Same standing WARNING,
  # same degraded run (the orientation then reports 0 optional members).
  if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    SS_ROOT_STATE="set to '${CLAUDE_PLUGIN_ROOT}' but has no scripts/invoke-external.sh"
  else
    SS_ROOT_STATE="unset"
  fi
  SS_HELPER_NOTICE="WARNING: the Triforge helper did not load (CLAUDE_PLUGIN_ROOT is ${SS_ROOT_STATE}) — optional-CLI detection, enrollment and the roster pin check were skipped this session. Run this hook through the installed plugin: claude plugin install agent-triforge@agent-triforge"
fi
_ss_run
