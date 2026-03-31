# Changelog

## [2026-03-31] — Comprehensive framework audit, fix pass, and Blueprint alignment

### Claude Code (ship-loop rewrite)
- Rewrote `ship-loop.sh` to match Blueprint's visual output and architecture
- JSON output format: `{decision, reason, systemMessage}` (was plain text echo)
- Session isolation via `session_id` matching from stdin JSON
- Transcript-based promise detection via `transcript_path` JSONL parsing (was basic stdin grep)
- Richer state file: `active`, `session_id`, `completion_promise` fields (was just iteration/max)
- Atomic state updates via temp file + mv (was `sed -i.bak`)
- Integer validation, `set -euo pipefail`, awk frontmatter parsing, perl promise extraction
- Updated `ship.md` and `coordinate.md` state file templates to match

## [2026-03-31] — Comprehensive framework audit and fix pass

### Claude Code
- **Critical fix:** `.claude/settings.json` hooks used flat format (`{ "command": "...", "timeout": ... }`) which Claude Code rejects — migrated to correct `{ "matcher": "...", "hooks": [{ "type": "command", "command": "..." }] }` format
- **Critical fix:** `ship-loop.sh` read `$CLAUDE_STOP_ASSISTANT_MESSAGE` env var (doesn't exist) — now parses stdin JSON for `last_assistant_message`. Completion detection was completely broken.
- **Critical fix:** `context-monitor.sh` read `$CLAUDE_TOOL_NAME` env var (doesn't exist) — now parses stdin JSON for `tool_name`. Analysis paralysis detection was completely broken.
- **Critical fix:** `README.md` Getting Started section shipped broken flat-format hook config — updated to correct matcher/hooks array format
- **Critical fix:** `coordinate.md` ran full Phase 0-6 sprint without ship-loop activation — added state file creation, `<promise>DONE</promise>`, and cleanup
- **High fix:** `session-start.sh` now cleans stale `context-monitor.local.md` on session start (was documented in MEMORY.md but never implemented)
- **High fix:** `build.md` hardcoded `src/auth/` paths in agent team code block — replaced with `<scope>` placeholders
- **High fix:** `deep-research.md` Gemini invocation now injects `codebase-mapping` skill (was the only Gemini call without it)
- **High fix:** `review.md` added `wait $GEMINI_PID $CODEX_PID` — synthesis could read incomplete review files
- **High fix:** `test.md` codex exec now uses `> /tmp/codex_test.txt 2>&1 &` pattern with PID capture and wait
- **High fix:** `security-sentinel.md` removed unnecessary Bash tool (static analysis reviewer, least-privilege)
- **High fix:** `team-lead.md` added structured output format (was the only agent without one)
- **High fix:** `wave-orchestration` SKILL.md team mode section flagged as Claude-specific with experimental note
- **Medium fix:** Fixed missing `ops/` prefixes in `ship.md`, `plan.md`, `quick.md`, `coordinate.md`
- **Medium fix:** `review.md --full` now includes `architecture-strategist` agent (was designed for Phase 3 but never included)
- **Medium fix:** `plan-checker.md` now accepts "Claude subagent" as valid assignment category (was causing false NEEDS_REVISION)
- **Medium fix:** `git-history-analyzer.md` replaced interactive `git bisect` with non-interactive `git log -S` alternative
- **Medium fix:** `deployment-verifier.md` added explicit "never execute rollbacks" safety rule
- **Medium fix:** `session-start.sh` replaced `echo -e` with POSIX-portable `printf '%b\n'`
- Updated ops/solutions/2026-03-26-settings-json-required-for-hooks.md with correct format documentation
- 5 parallel audit agents found 4 CRITICAL, 10 HIGH, ~20 MEDIUM issues across all framework components

## [2026-03-26] — Diagram redesign, full audit, and framework hardening

### Claude Code
- Redesigned ALL diagrams to match Blueprint's dark-badge + white-pill visual grammar
  - hero-banner: navy+gold matching Blueprint exactly (#1a1a2e→#16213e→#0f3460, #D4A574)
  - 5 existing diagrams rebuilt: sprint-lifecycle (pipeline view), review-swarm, knowledge-loop, quality-gates
  - 6 new diagrams created: research-swarm, wave-orchestration, planning-flow, testing-flow, debug-flow, context-recovery
- Added README sections: Planning Pipeline, Deep Research, Wave Orchestration, Review Swarm, Test Pipeline, Debugging, Context Recovery
- **Critical fix:** replaced grep -oP (Perl regex) with POSIX sed in ship-loop.sh and context-monitor.sh — was silently failing on macOS
- **Critical fix:** created .claude/settings.json to register all 3 hooks (were never firing)
- **Critical fix:** updated CLAUDE.md from 14→18 agents, 11→12 skills, added scope-cutting, fixed GEMINI.md/CODEX.md references
- Fixed ship.md: added (append) directive for MEMORY.md/CONTRACTS.md
- Fixed wrap.md: added <promise>DONE</promise> completion marker
- Fixed context-monitor.sh: expanded tool classification, unknown tools now reset read counter
- Added "Do NOT flag" suppressions to test-gap-analyzer
- Added Output sections to 9 skills that lacked them
- Made wave-orchestration fully model-agnostic (removed subagent/worktree references)
- Added Flags sections to /build and /ship commands
- Fixed session-start.sh: removed unused variables, wired up HAS_GOALS
- Fixed README structure tree: removed nonexistent GEMINI.md/CODEX.md, corrected agent count
- 3 full audit passes (5 parallel agents each) until zero defects

## [2026-03-24] — README overhaul and SVG diagram redesign

### Claude Code
- Redesigned hero banner SVG: left-aligned layout with terminal mockup, matching Blueprint's design language
- Redesigned all 4 diagram SVGs (sprint-lifecycle, knowledge-loop, quality-gates, review-swarm):
  - Switched from dark navy backgrounds to white/light backgrounds with Blueprint's pastel palette
  - Colors: #C9E4CA green, #B8D4E3 blue, #FFE4B5 yellow, #D4A574 tan, #FFB3B3 pink, #D4B8E3 purple
  - Reduced stroke-width from 2px to 1px, softened stroke colors to blend with fills
  - Review swarm: widened from 1000px to 1350px viewBox to eliminate box overlap
- Comprehensive README.md rewrite:
  - Restructured to match Blueprint's layout: nav bar, project structure early, expanded sections, FAQ
  - Added 100+ hyperlinks to agents, skills, commands, and files
  - Fixed broken links (GEMINI.md, CODEX.md don't exist → external GitHub URLs)
  - Reordered sprint lifecycle table columns to prevent narrow-column squeeze
  - Added typical session flow, assignment heuristic, key constraints sections
  - Added collapsible FAQ with 8 common questions

## [2026-03-24] — Initial framework build

### Claude Code
- Analyzed Claude Code Blueprint (github.com/Ninety2UA/claude-code-blueprint) for compatible patterns
- Created 18 specialized agent definitions in .claude/agents/
  - Core workflow: plan-checker, findings-synthesizer, integration-verifier, learnings-researcher, team-lead, research-synthesizer
  - Review: security-sentinel, performance-oracle, code-simplicity-reviewer, convention-enforcer, architecture-strategist, test-gap-analyzer
  - Research: best-practices-researcher, framework-docs-researcher, git-history-analyzer
  - Verification: bug-reproduction-validator, deployment-verifier, pr-comment-resolver
- Created 12 portable skill files in .claude/skills/
  - codebase-mapping, writing-plans, shadow-path-tracing, wave-orchestration, test-driven-development, systematic-debugging, iterative-refinement, review-synthesis, verification-before-completion, knowledge-compounding, session-continuity, scope-cutting
- Created 16 slash commands in .claude/commands/
  - Pipeline: /ship, /coordinate
  - Phase: /plan, /build, /review, /test, /wrap
  - Lightweight: /quick, /debug
  - Research: /deep-research, /analyze
  - Session: /status, /pause, /resume, /compound, /resolve-pr
- Created 3 lifecycle hooks in .claude/hooks/
  - session-start.sh (SessionStart — orientation)
  - ship-loop.sh (Stop — inner loop guard)
  - context-monitor.sh (PostToolUse — analysis paralysis detection)
- Created scripts/coordinate.sh (outer loop for context exhaustion recovery)
- Created ops/solutions/ and ops/decisions/ directories for knowledge compounding
- Wrote comprehensive docs/multi-agent-framework.md with all phases, protocols, and patterns
- Updated CLAUDE.md with full framework reference
- Created README.md with SVG hero banner, sprint lifecycle diagram, review swarm diagram, quality gates visualization, and knowledge loop diagram
- Published to GitHub: github.com/Ninety2UA/multi-agent-framework
