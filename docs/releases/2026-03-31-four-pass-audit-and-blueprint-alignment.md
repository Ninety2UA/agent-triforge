# 2026-03-31 — Four-pass audit and Blueprint alignment

Four full audit passes (**20 parallel agents** + manual 11-point verification) reviewed all 49 framework components (5 hooks, 16 commands, 12 skills, 19 agents). Each pass caught issues the previous missed — converging to zero remaining defects.

| Pass | Found | Fixed |
|---|---|---|
| 1st (5 agents) | 4 critical, 10 high, ~20 medium | Hooks stdin parsing, README config, coordinate.md guard, all high+medium |
| 2nd (5 agents) | 1 critical, 8 high, 4 medium | JSON injection, PID captures, path consistency, reviewer coverage |
| 3rd (5 agents) | 3 critical, 7 high, 6 medium | mkdir .claude in hooks, stale docs, deep-research PID, ops refs |
| 4th (5 agents + manual) | 1 high | ship-loop.sh mkdir guard (last hook missing it) |

<details>
<summary><strong>Critical fixes</strong></summary>

- **Hooks were completely non-functional** — both `ship-loop.sh` and `context-monitor.sh` read environment variables (`$CLAUDE_STOP_ASSISTANT_MESSAGE`, `$CLAUDE_TOOL_NAME`) that Claude Code does not set. Hook data arrives via stdin JSON. Both hooks now parse stdin correctly. This means completion detection and analysis paralysis detection were silently broken since the framework's creation.
- **README shipped broken hook config** — the Getting Started section used the flat `{ "command", "timeout" }` format that Claude Code rejects. Migrated to the correct `{ "matcher", "hooks": [{ "type": "command", "command" }] }` format.
- **`/coordinate` ran full sprints unguarded** — the command executed Phase 0–6 without activating the ship-loop Stop hook, so context exhaustion could silently kill mid-sprint. Now creates the state file and emits `<promise>DONE</promise>` on completion.
- **Ship-loop JSON injection** (found in second pass) — the heredoc embedded raw `$PROMPT_TEXT` into JSON output. Any goal containing double quotes or newlines produced malformed JSON, silently breaking the Stop hook. Now uses `python3 json.dumps()` for safe encoding.
</details>

<details>
<summary><strong>Ship-loop rewrite (Blueprint alignment)</strong></summary>

The Stop hook was rewritten to match the [Claude Code Blueprint](https://github.com/Ninety2UA/claude-code-blueprint)'s architecture:

| Before | After |
|---|---|
| Plain text output | JSON `{decision, reason, systemMessage}` |
| No session isolation | Session-isolated via `session_id` matching |
| Basic stdin grep for promise | Transcript-based JSONL promise detection |
| `sed -i.bak` state updates | Atomic temp file + `mv` |
| No input validation | Integer validation + `set -euo pipefail` |
| Simple 2-field state file | Rich frontmatter: `active`, `session_id`, `iteration`, `max_iterations`, `completion_promise` + prompt body |
| Raw shell variable in JSON | `python3 json.dumps()` for safe JSON encoding |
</details>

<details>
<summary><strong>High-severity fixes</strong></summary>

- **`session-start.sh`** now cleans stale `context-monitor.local.md` on startup (was documented but never implemented)
- **`build.md`** replaced hardcoded `src/auth/` paths with `<scope>` placeholders in agent team examples
- **`deep-research.md`** Gemini invocation now injects `codebase-mapping` skill (was the only Gemini call without it)
- **`review.md`** added `wait $GEMINI_PID $CODEX_PID` before synthesis (was racing on incomplete review files)
- **`test.md`** Codex invocation now uses proper `> /tmp/... 2>&1 &` redirect + PID capture pattern
- **`security-sentinel.md`** removed unnecessary Bash tool (least-privilege for static analysis)
- **`team-lead.md`** added structured output format (was the only agent without one)
- **`wave-orchestration`** skill flagged team mode as Claude-specific + experimental
- **`review.md --full`** now includes `architecture-strategist` (was designed for Phase 3 but never wired in)
- **`build.md`** agent team bash block now captures PIDs and waits (was fire-and-forget)
- **`ship.md`**, **`plan.md`**, **`coordinate.md`** Phase 0 Gemini invocations now capture `GEMINI_PID` and `wait` (were backgrounded with no wait)
- **`coordinate.md`** Phase 3 now includes all 5 review agents (was missing `convention-enforcer` and `architecture-strategist`)
- **`pr-comment-resolver.md`** now checks `gh auth status` before fetching PR comments (was a hard failure if `gh` CLI unavailable)
- **All 3 hook scripts** now have `mkdir -p .claude` guards for project-local state files (`.claude/` dir no longer exists after plugin migration)
- **`deep-research.md`** added `GEMINI_PID` capture + `wait` for background Gemini process
- **`docs/agent-triforge.md`** rewrote repo tree + settings section for plugin layout (was still showing old structure)
- **`ops/solutions/settings-json`** updated for plugin `hooks/hooks.json` approach
- **Stale comment cleanup** in hook script headers (referenced old `.claude/settings.json`)
</details>

<details>
<summary><strong>Medium-severity fixes</strong></summary>

- Fixed missing `ops/` path prefixes across `ship.md`, `plan.md`, `quick.md`, `coordinate.md`
- `plan-checker.md` now accepts "Claude subagent" as a valid assignment category
- `git-history-analyzer.md` replaced interactive `git bisect` with non-interactive `git log -S` alternative
- `deployment-verifier.md` added explicit "never execute rollbacks" safety rule
- `session-start.sh` replaced `echo -e` with POSIX-portable `printf '%b\n'`
- Fixed bare `ops/` path prefixes in `debug.md`, `review.md`, `coordinate.md`
- `status.md` now lists all 16 commands (was missing `/coordinate`, `/analyze`, `/resolve-pr`)
- `coordinate.md` Phase 5 now specifies max 3 fix cycles (was open-ended)
- Standardized archive path wording to `[today's date]` across `ship.md` and `coordinate.md`
</details>

Documented solutions: [`ops/solutions/2026-03-31-hooks-stdin-json-parsing.md`](../../ops/solutions/2026-03-31-hooks-stdin-json-parsing.md)

## Verification

The framework has been validated through:
- **20 parallel audit agents** across 4 passes (hooks, commands, skills, agents, infrastructure)
- **Manual 11-point verification**: bash syntax, JSON validity, stale path scans, file counts, skill injection paths, executable permissions, mkdir guards, stdin parsing, agent cross-references, plugin hook paths, state file template compatibility
- All checks pass. Runtime behavior (plugin installation, hook firing, `${CLAUDE_PLUGIN_ROOT}` expansion) requires live testing via `claude --plugin-dir .`
