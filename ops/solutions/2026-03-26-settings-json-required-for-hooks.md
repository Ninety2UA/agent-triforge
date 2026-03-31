---
title: "Hooks won't fire without .claude/settings.json"
date: 2026-03-26
tags: [hooks, settings, configuration, claude-code]
agent: Claude Code (Opus)
---

## Problem
All 3 lifecycle hooks (session-start.sh, ship-loop.sh, context-monitor.sh) existed as executable scripts but never fired during sessions. The framework appeared non-functional despite all files being present and correct.

## Root cause
Claude Code hooks must be **registered** in `.claude/settings.json` under the `hooks` key. Without this file, Claude Code has no way to discover hook scripts regardless of their location or permissions.

## Solution
Created `.claude/settings.json` with all 3 hooks registered. Each hook event requires objects with a `matcher` string and a `hooks` array (not flat command objects):

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "hooks": {
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": ".claude/hooks/session-start.sh" }]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": ".claude/hooks/ship-loop.sh" }]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [{ "type": "command", "command": ".claude/hooks/context-monitor.sh" }]
      }
    ]
  }
}
```

**Important:** The flat format `{ "command": "...", "timeout": 5000 }` does NOT work. Each entry must have `matcher` (string — tool name, pipe-separated list, or `""` to match all) and `hooks` (array of `{ "type": "command", "command": "..." }` objects). Claude Code will skip the entire settings file if this format is wrong.

## Prevention
- Always include `.claude/settings.json` when distributing hooks
- Document required settings in README installation section
- Verify hooks fire after cloning by running `/status` (session-start hook should produce orientation message)
- Use the documented format: `{ "matcher": "...", "hooks": [{ "type": "command", "command": "..." }] }` — not the flat format
