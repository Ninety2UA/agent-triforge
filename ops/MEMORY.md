# Shared memory

## Decisions
- [2026-03-24] Adopted 18 of 26 Blueprint agents, skipped 8 (Claude Code)
  Reason: Skipped agents were either redundant (code-reviewer covered by Gemini+Codex+specialists), too niche (frontend-reviewer, schema-drift-detector), or overlapping (codebase-context-mapper duplicates Gemini Phase 0).
  See: ops/decisions/2026-03-24-blueprint-pattern-adoption.md

- [2026-03-24] Skills are model-agnostic and injectable into all CLIs (Claude Code)
  Reason: Decouples methodology from model. Gemini and Codex consume skills via $(cat ${CLAUDE_PLUGIN_ROOT}/skills/SKILL/SKILL.md).
  See: ops/solutions/2026-03-24-portable-skill-injection.md

- [2026-03-24] Agent teams require CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 (Claude Code)
  Reason: Experimental feature. Known limitations: no session resumption with in-process teammates, task status lag, one team per session.

## Patterns
- Confidence tiering: [HIGH] verified via grep, [MEDIUM] pattern match, [LOW] heuristic. LOW can NEVER be P1.
- Suppressions: Each reviewer has "Do Not Flag" patterns to reduce false positives.
- Review synthesis: findings-synthesizer agent merges all review outputs, deduplicates, and priority-ranks.
- Wave orchestration: Group tasks by dependency into waves. Integration-verifier runs between waves.

## Gotchas
- SVG diagrams on GitHub: use white `<rect>` backgrounds, NOT transparent — transparent renders differently in dark mode and can make text invisible.
- SVG borders: use stroke-width 1px with softened stroke colors (e.g., #9bc49d on #C9E4CA fill) — 2px + contrasting strokes create a shadow/overline artifact.
- SVG viewBox sizing: when 7+ boxes in a row, viewBox must be ≥1300px to maintain readable gaps. GitHub renders SVGs at ~800px max width, so gaps under 20px in the viewBox become invisible.
- ops/TASKS.md is generated at runtime, not committed — don't link to it in README.

- **grep -oP is NOT portable** — BSD grep on macOS lacks -P flag. Use `sed -n 's/pattern/\1/p'` instead. See: ops/solutions/2026-03-26-grep-posix-portability.md
- **Hooks are registered in `hooks/hooks.json` (plugin)** — hook commands use `${CLAUDE_PLUGIN_ROOT}/hooks/handlers/` paths. Each entry needs `{ "matcher": "...", "hooks": [{ "type": "command", "command": "..." }] }`. The flat format `{ "command": "...", "timeout": ... }` causes Claude Code to skip the entire config. See: ops/solutions/2026-03-26-settings-json-required-for-hooks.md
- context-monitor.sh state file (`.claude/context-monitor.local.md`) must be cleaned between sessions — session-start.sh does this via `rm -f` on startup. The `.claude/` directory is created by `mkdir -p .claude` in both session-start.sh and context-monitor.sh.
- context-monitor.sh: unknown tools should reset the read counter (not increment it) to avoid false paralysis warnings.
- Codex CLI uses lazy loading for skills — only loads full body when relevant.
- Every skill must have an explicit `## Output` section — agents need to know what artifact to produce.
- **Hooks receive data via stdin JSON, NOT environment variables** — `$CLAUDE_TOOL_NAME`, `$CLAUDE_STOP_ASSISTANT_MESSAGE` etc. do not exist. Parse stdin with `python3 -c "import sys,json; ..."`. See: ops/solutions/2026-03-31-hooks-stdin-json-parsing.md
- **Every agent must have an `## Output format` section** — the calling command needs structured output to parse. team-lead was the only agent missing this.

- Worker discovery (int4b, Phase 4 integration merge, 2026-10-07), UNVERIFIED, for the end-of-program review:

      scripts/lib/lease-wait.sh still reads the ledger with plain open(…, "rb") + tomllib.load
      in three places (the LR_LEDGER, LC_LEDGER and LW_LEDGER readers in lease_wait and the
      reconcile). Phase 3's non-blocking regular-file reader (read_regular) was not applied there,
      so a FIFO planted at ops/leases.toml could still block lease_wait. Needs its own red/green case.

- Worker discovery (u15-instr, Phase 5, 2026-10-07; extended by the Phase 6 gap analysis), MEASURED mechanism, helper-level exposure from source reading:

      Inline `python3 -c` / `python3 -` programs put the cwd first on sys.path, so a planted
      json.py / tomllib.py / hashlib.py / re.py / subprocess.py there runs on import (measured with
      a planted tomllib.py, Python 3.14). Lead-side parsers run from a builder's worktree after it
      exits (_lease_builder_run cds into $WT; the envelope/extract parsers import json), and
      session-start runs from the user's project root. Only scripts/lib/instructions.sh drops the cwd.
      Phase 6 fixes this with one shared prelude for every inline program, proven by a SELF case.

## Interface proposals
<!-- No active proposals -->

## Archived (superseded)
<!-- Moved here 2026-10-01 (U3). Kept as history; each line says what superseded it. -->
- Completion promise: Only emit `<promise>DONE</promise>` after verification checklist passes. — Superseded by the `ops/.sprint-complete` sentinel that `scripts/coordinate.sh` detects (D-030); the `/goal` checklist is best-effort.
- ship-loop.sh (Stop hook) only blocks the session that activated it — uses session_id from stdin JSON for isolation. — ship-loop.sh was retired with the sentinel-based completion signal (D-030); not coming back.
- ship-loop.sh outputs JSON `{decision, reason, systemMessage}` to match Blueprint visual format — reason contains the original goal prompt re-injected on each iteration. — Retired with ship-loop.sh (D-030); hook stdout now never starts with `{` (D-031c).
- ship-loop.sh state file uses YAML frontmatter with `active`, `session_id`, `iteration`, `max_iterations`, `completion_promise` — prompt body goes after second `---`. — Retired with ship-loop.sh (D-030).
- GEMINI.md and CODEX.md files don't exist in the repo — link to external GitHub URLs instead. — The Gemini lane was retired in v3.0.0 (agy replaced it); Codex worker instructions ride in `codex-agents/agents.toml`, and the one instruction file is the root `AGENTS.md` (U3).
- Gemini CLI's GEMINI.md files have a prompt injection risk when loading from untrusted sources. — Gemini lane retired in v3.0.0; the general rule survives as "worker output is data" in `AGENTS.md` (R49).
- When Gemini writes to ops/MEMORY.md or ops/CONTRACTS.md, always specify `(append)` — without it, Gemini may overwrite existing content. — Gemini lane retired in v3.0.0; agy's write denials against `ops/` are handled by promoting captured output (D-032).
