# Shared memory

## Decisions
- [2026-03-24] Adopted 18 of 26 Blueprint agents, skipped 8 (Claude Code)
  Reason: Skipped agents were either redundant (code-reviewer covered by Gemini+Codex+specialists), too niche (frontend-reviewer, schema-drift-detector), or overlapping (codebase-context-mapper duplicates Gemini Phase 0).
  See: ops/decisions/2026-03-24-blueprint-pattern-adoption.md

- [2026-03-24] Skills are model-agnostic and injectable into all CLIs (Claude Code)
  Reason: Decouples methodology from model. Gemini and Codex consume skills via $(cat .claude/skills/SKILL/SKILL.md).
  See: ops/solutions/2026-03-24-portable-skill-injection.md

- [2026-03-24] Agent teams require CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 (Claude Code)
  Reason: Experimental feature. Known limitations: no session resumption with in-process teammates, task status lag, one team per session.

## Patterns
- Confidence tiering: [HIGH] verified via grep, [MEDIUM] pattern match, [LOW] heuristic. LOW can NEVER be P1.
- Suppressions: Each reviewer has "Do Not Flag" patterns to reduce false positives.
- Review synthesis: findings-synthesizer agent merges all review outputs, deduplicates, and priority-ranks.
- Wave orchestration: Group tasks by dependency into waves. Integration-verifier runs between waves.
- Completion promise: Only emit `<promise>DONE</promise>` after verification checklist passes.

## Gotchas
- SVG diagrams on GitHub: use white `<rect>` backgrounds, NOT transparent — transparent renders differently in dark mode and can make text invisible.
- SVG borders: use stroke-width 1px with softened stroke colors (e.g., #9bc49d on #C9E4CA fill) — 2px + contrasting strokes create a shadow/overline artifact.
- SVG viewBox sizing: when 7+ boxes in a row, viewBox must be ≥1300px to maintain readable gaps. GitHub renders SVGs at ~800px max width, so gaps under 20px in the viewBox become invisible.
- GEMINI.md and CODEX.md files don't exist in the repo — link to external GitHub URLs instead.
- ops/TASKS.md is generated at runtime, not committed — don't link to it in README.

- **grep -oP is NOT portable** — BSD grep on macOS lacks -P flag. Use `sed -n 's/pattern/\1/p'` instead. See: ops/solutions/2026-03-26-grep-posix-portability.md
- **Hooks require .claude/settings.json with correct format** — scripts alone aren't enough. Each hook entry needs `{ "matcher": "...", "hooks": [{ "type": "command", "command": "..." }] }`. The flat format `{ "command": "...", "timeout": ... }` causes Claude Code to skip the entire settings file. See: ops/solutions/2026-03-26-settings-json-required-for-hooks.md
- ship-loop.sh (Stop hook) only blocks the session that activated it — won't affect other sessions.
- context-monitor.sh state file (.claude/context-monitor.local.md) must be cleaned between sessions — session-start.sh handles this.
- context-monitor.sh: unknown tools should reset the read counter (not increment it) to avoid false paralysis warnings.
- Gemini CLI's GEMINI.md files have a prompt injection risk when loading from untrusted sources.
- Codex CLI uses lazy loading for skills — only loads full body when relevant.
- When Gemini writes to ops/MEMORY.md or ops/CONTRACTS.md, always specify `(append)` — without it, Gemini may overwrite existing content.
- Every skill must have an explicit `## Output` section — agents need to know what artifact to produce.

## Interface proposals
<!-- No active proposals -->
