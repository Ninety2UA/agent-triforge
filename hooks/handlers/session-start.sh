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

# Bootstrap Gemini agent definitions (.gemini/agents/)
# Only copies files that don't already exist — preserves user customizations
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT}/gemini-agents" ]; then
  mkdir -p .gemini/agents
  for f in "${CLAUDE_PLUGIN_ROOT}/gemini-agents/"*.md; do
    [ -f "$f" ] && [ ! -f ".gemini/agents/$(basename "$f")" ] && cp "$f" ".gemini/agents/$(basename "$f")"
  done
  if [ -f "${CLAUDE_PLUGIN_ROOT}/gemini-agents/policies.toml" ] && [ ! -f ".gemini/policies.toml" ]; then
    cp "${CLAUDE_PLUGIN_ROOT}/gemini-agents/policies.toml" ".gemini/policies.toml"
  fi
  # Bootstrap .gemini/settings.json (disables built-in codebase_investigator; see template for rationale)
  if [ -f "${CLAUDE_PLUGIN_ROOT}/templates/.gemini/settings.json" ] && [ ! -f ".gemini/settings.json" ]; then
    cp "${CLAUDE_PLUGIN_ROOT}/templates/.gemini/settings.json" ".gemini/settings.json"
  fi
fi

# G12 guard: warn if user disabled Gemini agents globally in ~/.gemini/settings.json
GEMINI_AGENTS_DISABLED_WARNING=""
if [ -f "${HOME}/.gemini/settings.json" ]; then
  if python3 -c "
import json, sys
try:
    with open('${HOME}/.gemini/settings.json') as f:
        s = json.load(f)
    exp = s.get('experimental', {})
    sys.exit(0 if exp.get('enableAgents') is False else 1)
" 2>/dev/null; then
    GEMINI_AGENTS_DISABLED_WARNING="WARNING: ~/.gemini/settings.json has experimental.enableAgents=false — Gemini subagents will not load. Remove that flag to enable Agent Triforge's Gemini layer."
  fi
fi

# Warn if neither `timeout` nor `gtimeout` is available — invoke-external.sh
# silently runs without timeout enforcement in that case, which can leave
# orphaned Gemini/Codex processes running for hours.
TIMEOUT_MISSING_WARNING=""
if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_MISSING_WARNING="WARNING: neither \`timeout\` nor \`gtimeout\` found on PATH — Gemini/Codex invocations will run without timeout enforcement. On macOS, install with: brew install coreutils"
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

# Suggest CLAUDE.md template if not present
if [ ! -f "CLAUDE.md" ] && [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md" ]; then
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
  BLOCKED_COUNT=$(grep -c '\[B\]' ops/TASKS.md 2>/dev/null || echo "0")
  PENDING_COUNT=$(grep -c '\[ \]' ops/TASKS.md 2>/dev/null || echo "0")
  IN_PROGRESS_COUNT=$(grep -c '\[-\]' ops/TASKS.md 2>/dev/null || echo "0")
fi

if [ -f "ops/GOALS.md" ]; then
  HAS_GOALS="yes"
fi

if [ -f "ops/AGENTS.md" ]; then
  HAS_AGENTS="yes"
fi

if [ -f "ops/REVIEW_GEMINI.md" ] || [ -f "ops/REVIEW_CODEX.md" ] || [ -f "ops/TEST_RESULTS.md" ]; then
  HAS_REVIEWS="yes"
fi

SOLUTION_COUNT=$(find ops/solutions -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || echo "0")

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
HAS_GEMINI_AGENTS=""
HAS_CODEX_AGENTS=""
GEMINI_AGENT_COUNT=0
CODEX_AGENT_COUNT=0

if [ -d ".gemini/agents" ]; then
  GEMINI_AGENT_COUNT=$(find .gemini/agents -name "*.md" 2>/dev/null | wc -l | tr -d ' ' || echo "0")
  if [ "$GEMINI_AGENT_COUNT" -gt "0" ]; then
    HAS_GEMINI_AGENTS="yes"
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
print(len(data.get('agents', {})))
" 2>/dev/null || grep -c '^\[agents\.' .codex/agents/agents.toml 2>/dev/null || echo "0")
  if [ "$CODEX_AGENT_COUNT" -gt "0" ]; then
    HAS_CODEX_AGENTS="yes"
  fi
fi

if [ "$HAS_GEMINI_AGENTS" = "yes" ] || [ "$HAS_CODEX_AGENTS" = "yes" ]; then
  AGENT_PARTS=""
  [ "$HAS_GEMINI_AGENTS" = "yes" ] && AGENT_PARTS="${GEMINI_AGENT_COUNT} Gemini"
  [ "$HAS_CODEX_AGENTS" = "yes" ] && AGENT_PARTS="${AGENT_PARTS:+${AGENT_PARTS} + }${CODEX_AGENT_COUNT} Codex"
  MSG="$MSG\nExternal agent definitions loaded: ${AGENT_PARTS}."
fi

if [ "$HAS_TASKS" != "yes" ] && [ "$HAS_STATE" != "yes" ]; then
  MSG="$MSG\nNo active sprint. Use /plan <goal> to start or /ship <goal> for full autonomous mode."
fi

# Append Gemini enableAgents warning if set
if [ -n "${GEMINI_AGENTS_DISABLED_WARNING}" ]; then
  MSG="$MSG\n${GEMINI_AGENTS_DISABLED_WARNING}"
fi

# Append timeout-missing warning if set
if [ -n "${TIMEOUT_MISSING_WARNING}" ]; then
  MSG="$MSG\n${TIMEOUT_MISSING_WARNING}"
fi

# Append CLAUDE.md tip if set
MSG="$MSG${CLAUDE_MD_TIP:-}"

printf '%b\n' "Multi-agent framework ready.$MSG"
echo ""
echo "Commands: /ship /plan /build /review /test /debug /quick /deep-research /status /pause /resume /wrap /compound"

exit 0
