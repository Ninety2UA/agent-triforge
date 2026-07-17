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

# Bootstrap Codex agent definitions (.codex/agents/)
# Only copies if not already present — preserves user customizations
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml" ]; then
  mkdir -p .codex/agents
  [ ! -f ".codex/agents/agents.toml" ] && cp "${CLAUDE_PLUGIN_ROOT}/codex-agents/agents.toml" ".codex/agents/agents.toml"
fi

# Copy Codex AGENTS.md for custom instructions
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/codex-agents/AGENTS.md" ]; then
  mkdir -p .codex
  [ ! -f ".codex/AGENTS.md" ] && cp "${CLAUDE_PLUGIN_ROOT}/codex-agents/AGENTS.md" ".codex/AGENTS.md"
fi

# Bootstrap .codex/config.toml (disables Codex's auto-memory pipeline to avoid
# conflict with Triforge's ops/MEMORY.md — see template for rationale).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/.codex/config.toml" ]; then
  mkdir -p .codex
  [ ! -f ".codex/config.toml" ] && cp "${CLAUDE_PLUGIN_ROOT}/templates/.codex/config.toml" ".codex/config.toml"
fi

# Bootstrap .codex/hooks.json (CHANGELOG attribution enforced under
# `codex exec` — probe CDX-04 PASS on 0.144.4; invoke-external.sh passes
# --dangerously-bypass-hook-trust when this file is present. See
# templates/.codex/README.md and ops/decisions/2026-07-18-codex-hooks-under-exec.md).
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/.codex/hooks.json" ]; then
  mkdir -p .codex
  [ ! -f ".codex/hooks.json" ] && cp "${CLAUDE_PLUGIN_ROOT}/templates/.codex/hooks.json" ".codex/hooks.json"
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
  BLOCKED_COUNT=$(grep -c '\[B\]' ops/TASKS.md 2>/dev/null || true)
  PENDING_COUNT=$(grep -c '\[ \]' ops/TASKS.md 2>/dev/null || true)
  IN_PROGRESS_COUNT=$(grep -c '\[-\]' ops/TASKS.md 2>/dev/null || true)
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
echo "Commands: /ship /plan /build /review /test /debug /quick /deep-research /analyze /coordinate /resolve-pr /status /pause /resume /wrap /compound"

exit 0
