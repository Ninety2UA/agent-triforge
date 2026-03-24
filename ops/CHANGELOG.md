# Changelog

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
