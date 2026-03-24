---
title: Skills are portable across CLIs via prompt injection
date: 2026-03-24
tags: [skills, gemini, codex, architecture]
agent: Claude Code
---

## Problem
The Claude Code Blueprint's skills are Claude-only. Our framework uses three different CLIs (Claude, Gemini, Codex). How do we share workflow methodologies across all agents?

## Root cause
Skills are just markdown files with structured prompts. Any LLM can consume markdown as part of its prompt context.

## Solution
Inject skills into external agents via bash prompt expansion:
```bash
gemini -p "$(cat .claude/skills/codebase-mapping/SKILL.md) Analyze the codebase..."
codex exec "$(cat .claude/skills/test-driven-development/SKILL.md) Write tests..."
```

This works because:
- Gemini CLI's 1M token context easily absorbs skill files (typically 1-10KB)
- Codex CLI has native skill support and can consume markdown prompts
- GEMINI.md instruction files can reference skills for automatic loading

## Prevention
When creating new skills, write them model-agnostically — no Claude-specific tool references, no assumptions about native skill loading. Frame as methodology, not tool instructions.

## Related
- .claude/skills/ directory (12 skills)
- docs/multi-agent-framework.md (Portable skill protocol section)
