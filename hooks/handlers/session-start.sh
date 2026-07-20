#!/usr/bin/env bash
# Session Start — SessionStart hook
# Scans for existing state, pending tasks, and available context.
# Provides orientation when starting a new session.
#
# Hook event: SessionStart
# Configuration: registered in hooks/hooks.json (plugin)

set -euo pipefail

# Ensure .claude/ directory exists for project-local state files
mkdir -p .claude

# Clean stale state files from previous sessions
rm -f .claude/context-monitor.local.md

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

# Bootstrap the Antigravity agent pack (agy plugin install)
# antigravity-agents/ is a valid agy plugin; installing it registers the four
# external agents. Failure-tolerant: native listing doesn't surface plugin
# agents headless yet (agy 1.1.3), so invoke_antigravity falls back to
# injection mode from the plugin templates either way.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && command -v agy >/dev/null 2>&1; then
  if ! agy plugin list 2>/dev/null | grep -q "agent-triforge"; then
    agy plugin install "${CLAUDE_PLUGIN_ROOT}/antigravity-agents" >/dev/null 2>&1 \
      || { echo "session-start: agy plugin install failed — invoke_antigravity will use injection mode from plugin templates." >&2; true; }
  fi
fi

# Deploy Antigravity workspace settings (permission deny rules), copy-if-absent.
# Probe 2026-07-17 (agy 1.1.3): NO project-tier settings.json lifted the
# headless permission auto-deny — .gemini/, .agents/, and .antigravity/
# settings.json were each tried with permissions.allow rules (blanket
# "command", full-command and prefix targets, both command()/
# run_shell_command() spellings) and every run still auto-denied; the
# settings.json the denial message refers to is the user tier
# (~/.gemini/antigravity-cli/settings.json), which we never touch. We ship
# the file anyway: it documents deny intent, covers interactive `agy` use
# and future tiers, and the captured-output fallback in /review and
# /deep-research carries the headless pipeline meanwhile.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/.antigravity/settings.json" ] && [ ! -f ".antigravity/settings.json" ]; then
  mkdir -p .antigravity
  cp "${CLAUDE_PLUGIN_ROOT}/templates/.antigravity/settings.json" ".antigravity/settings.json"
fi

# .agents/skills/ — the Antigravity workspace-skills tier AND the cross-CLI
# agentskills.io interop path. We copy (not symlink) so loaders that refuse
# to follow symlinks across mount boundaries still see the skills.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/skills" ] && [ ! -e ".agents/skills" ]; then
  mkdir -p .agents
  cp -R "${CLAUDE_PLUGIN_ROOT}/skills" .agents/skills 2>/dev/null || true
fi

# Warn if neither `timeout` nor `gtimeout` is available — timeout enforcement
# is FAIL-CLOSED in invoke-external.sh, so without one of them every external
# invocation (Antigravity/Codex) refuses to run at all.
TIMEOUT_MISSING_WARNING=""
if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_MISSING_WARNING="WARNING: neither \`timeout\` nor \`gtimeout\` found on PATH — invoke-external.sh is fail-closed and will refuse to run Antigravity/Codex invocations. On macOS, install with: brew install coreutils"
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
# customizations survive: agents.toml = agent defs; AGENTS.md = custom
# instructions; config.toml disables Codex's auto-memory pipeline (conflict with
# ops/MEMORY.md); hooks.json enforces CHANGELOG attribution under `codex exec`
# (probe CDX-04 PASS on 0.144.4; invoke-external.sh passes
# --dangerously-bypass-hook-trust when this file is present). See
# templates/.codex/README.md and ops/decisions/2026-07-18-codex-hooks-under-exec.md.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml"     ".codex/agents/agents.toml"
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
# permission map (edit/bash deny), NOT opencode.json denies (OC-06: denies do
# not survive --auto — see templates/.opencode/README.md).
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
# customizations survive. Guarded on `command -v kimi`. Kimi has NO native agent
# CLI surface (probe KIMI-03), so there is NO agents/ dir to provision: roles
# ride as (1) prompt-prefix injection from the plugin's kimi-agents/ briefs and
# (2) the builder/reviewer role sections in .kimi-code/AGENTS.md that Kimi merges
# into its system prompt. config.toml disables telemetry (R25) + ships a bash
# denylist; the real headless confinement is the lease worktree + _adapter_env
# KIMI_* allowlist (see templates/.kimi-code/README.md).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && command -v kimi >/dev/null 2>&1; then
  for f in AGENTS.md config.toml; do
    _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/.kimi-code/${f}" ".kimi-code/${f}"
  done
fi

# Bootstrap Cursor CLI project files, copy-if-absent so user customizations
# survive. Guarded on `command -v cursor-agent`. Cursor has NO headless --agent
# selector (re-probed 2026-07-18), so roles ride as prompt-prefix injection from
# the plugin's cursor-agents/ briefs (invoke_cursor + the lease_dispatch cursor
# case both inject); the .cursor/agents/ copies are delegation targets +
# documentation, and .cursor/README.md records the --trust-required / grok-4.5-
# pinned-never-Auto / CUR-06 headless-hooks-dead / CUR-07 --sandbox-doesn't-confine
# facts. No afterFileEdit attribution hook is shipped (CUR-06 FAIL); builder
# attribution is lead-side from the lease ledger (U9). Version capture (R26) is
# handled by the optional-CLI detection block below (cursor-agent --version ->
# .claude/roster-detected.local.md), since Cursor has no published semver.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && command -v cursor-agent >/dev/null 2>&1; then
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

# Bootstrap ops/roster.toml + ops/watch-registry.toml — per-file existence
# guards, deliberately OUTSIDE the ops-dir bootstrap above so upgraded v2.x
# projects (which already have ops/) still receive them. A user's existing
# roster is never overwritten. The watch-registry template lands in a later
# unit — the loop tolerates its absence today.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  for f in roster.toml watch-registry.toml; do
    _bootstrap_copy "${CLAUDE_PLUGIN_ROOT}/templates/ops/${f}" "ops/${f}"
  done
fi

# Optional-CLI detection (roster tier): presence + version for opencode /
# kimi / cursor-agent, written to .claude/roster-detected.local.md (runtime
# state, regenerated each session start; .claude/*.local.md is gitignored).
# Line format: cli|version|detected-date, plus one interactive=yes|no signal
# line the enrollment unit keys off. [ -t 0 ] at hook time is best-effort —
# hooks often run with stdin piped — documented as such; the enrollment
# branch treats "no" as headless and enrolls shipped defaults silently.
ROSTER_DETECTED=".claude/roster-detected.local.md"
OPTIONAL_DETECTED_COUNT=0
DETECTED_OPTIONAL=()
TIMEOUT_BIN=""
command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN="timeout"
[ -z "$TIMEOUT_BIN" ] && command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN="gtimeout"
if [ -t 0 ]; then INTERACTIVE_SIGNAL="yes"; else INTERACTIVE_SIGNAL="no"; fi
{
  echo "<!-- runtime state: optional roster CLI detection, regenerated each session start -->"
  echo "interactive=${INTERACTIVE_SIGNAL}"
} > "$ROSTER_DETECTED"
for PAIR in "opencode:opencode" "kimi:kimi" "cursor:cursor-agent"; do
  CLI_NAME=${PAIR%%:*}
  CLI_BIN=${PAIR##*:}
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
    echo "${CLI_NAME}|${CLI_VERSION}|$(date +%Y-%m-%d)" >> "$ROSTER_DETECTED"
    OPTIONAL_DETECTED_COUNT=$((OPTIONAL_DETECTED_COUNT + 1))
    DETECTED_OPTIONAL+=("$CLI_NAME")
  fi
done

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
  # `grep -c` already prints 0 when there are no matches (exiting 1).
  # Use `|| true` to avoid set -e termination without duplicating the 0 via `echo "0"`.
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

# Count the local plugin templates — `agy agents` stays empty headless on
# agy 1.1.3, so the injection templates are the operative definitions.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents" ]; then
  ANTIGRAVITY_AGENT_COUNT=$(find "${CLAUDE_PLUGIN_ROOT}/antigravity-agents/agents" -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || true)
  if [ "$ANTIGRAVITY_AGENT_COUNT" -gt "0" ]; then
    HAS_ANTIGRAVITY_AGENTS="yes"
  fi
fi

if [ -f ".codex/agents/agents.toml" ]; then
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
with open('.codex/agents/agents.toml','rb') as f:
    data = tomllib.load(f)
# Filter to dict values only — [agents] also holds scalar runtime caps
# (max_depth, max_threads, job_max_runtime_seconds) alongside the agent subtables.
print(sum(1 for v in data.get('agents', {}).values() if isinstance(v, dict)))
" 2>/dev/null || grep -c '^\[agents\.' .codex/agents/agents.toml 2>/dev/null || true)
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
echo "Commands: /setup /ship /plan /build /review /test /debug /quick /deep-research /analyze /coordinate /resolve-pr /status /pause /resume /wrap /compound /cli-watch /repo-watch"

exit 0
