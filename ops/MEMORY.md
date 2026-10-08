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
- **A SELF case compares against the physical work path** — the harness's `WORK` is `"${TMPDIR}/triforge-probes.XXXXXX"`; macOS's `TMPDIR` ends in `/` and sits below the `/var` symlink, so a case that greps a helper's output (realpath, `pwd -P`, a `cd`'s `$PWD`) for the raw `"$WORK/..."` fails only under `--self-only`. Resolve the row's directory with `pwd -P` right after making it (SELF-16, SELF-25) and run new cases once with a single-row runner given the harness's `WORK` (review round 2, 910a117).
- **Hooks are registered in `hooks/hooks.json` (plugin)** — hook commands use `${CLAUDE_PLUGIN_ROOT}/hooks/handlers/` paths. Each entry needs `{ "matcher": "...", "hooks": [{ "type": "command", "command": "..." }] }`. The flat format `{ "command": "...", "timeout": ... }` causes Claude Code to skip the entire config. See: ops/solutions/2026-03-26-settings-json-required-for-hooks.md
- context-monitor.sh state file (`.claude/context-monitor.local.md`) must be cleaned between sessions — session-start.sh does this via `rm -f` on startup. The `.claude/` directory is created by `mkdir -p .claude` in both session-start.sh and context-monitor.sh.
- context-monitor.sh: unknown tools should reset the read counter (not increment it) to avoid false paralysis warnings.
- Codex CLI uses lazy loading for skills — only loads full body when relevant.
- Every skill must have an explicit `## Output` section — agents need to know what artifact to produce.
- **Hooks receive data via stdin JSON, NOT environment variables** — `$CLAUDE_TOOL_NAME`, `$CLAUDE_STOP_ASSISTANT_MESSAGE` etc. do not exist. Parse stdin with `python3 -c "import sys,json; ..."`. See: ops/solutions/2026-03-31-hooks-stdin-json-parsing.md
- **Every agent must have an `## Output format` section** — the calling command needs structured output to parse. team-lead was the only agent missing this.

- Worker discoveries (end-of-program review, fix round 1, 2026-10-08), UNVERIFIED, recorded by the lead from the workers' reports:

      fix worker B: _run_with_timeout (scripts/lib/common.sh) runs `timeout -k 10s` with no
      braces, so when the KILL fires bash prints a "Killed: 9" job line on the caller's stderr,
      which can land in captured output. Low severity.
      fix worker D: lease_merge/lease_promote re-hash the objects they bring in, but a worker
      process still running can swap an object between the check and the squash (detection, not
      prevention). Git calls outside _lead_git still read the commit-graph: bootstrap.sh's own
      git, scripts/skill-locator/locate-triforge.sh, plain git in at-* skill blocks.
      _persona_diff could run the same object check before review, to refuse earlier.
      fix worker A: CLAUDE_CONFIG_DIR is modeled nowhere (READERS has no home_env for the
      claude-md-shadow reader); whether Claude Code reads its user memory from there is unverified.
      The user-level refusal follows the CODEX_HOME of the shell that runs the check.
      fix worker E: SELF-30 rule (a) could also check the last statement inside a trailing if or
      case (0 hits today). The scanner does not look inside single-quoted eval strings,
      printf-written stubs, $( ) inside $(( )), or a grep run through a variable. SELF rows can't be
      selected with --only (only SELF-06f/g/h); the --only comment in probe-capabilities.sh says
      it runs no SELF row.
      fix worker F: ops/research/2026-09-probe-record.md line 111 still says AGY-08 did not fire
      on 1.2.1 "(this row)" under a PASS row; the next regeneration prints the neutral footnote.
      The footnote's guardrail sentence still asserts "AGY-09/AGY-10 stay FAIL".

- Worker discoveries (end-of-program review, fix round 2, 2026-10-08), UNVERIFIED, recorded by the lead from the workers' reports:

      fix worker B: a SKILL.md metadata: block whose first key is indented deeper than the
      keys after it passes validate-skills and the skill-version check, though a YAML parser
      rejects it. docs/rule-inventory.md row 155 still quotes the retired "50+ file changes"
      wording (history; the halt check does not scan it). validate-versions.sh --help prints a
      sed error when the script is invoked by a relative path from another directory (it
      reads $0 after cd). release.yml runs neither self-test.
      fix worker C: without python3 the subdirectory-roster walk no longer warns (the roster
      test needs python3). The scan prints paths with control bytes stripped, so a Triforge tree
      at a path with control characters is not recognized as a shipped template. With both
      <base>/CLAUDE.md and <base>/.claude/CLAUDE.md above a project, the visibility fix looks
      only at the first shadowing file, so it can offer a narrower fix than the other file
      would allow.
      fix worker E: SELF-30's EXPAN regex is greedy across a word that holds two expansions,
      so timeout_args would take "${TIMEOUT_BIN:-x}${Y}" as the timeout binary (harmless
      today; held() checks for exactly one). A "${ARR[@]}" among env's assignments still
      leaves the command undecided (only "$@" is read past). arith() finds the end of an
      arithmetic body by counting parentheses and ignores quotes, so a quoted ) inside a
      $( ) within $(( )) falls back to a subshell parse, which still scans the command.
      fix worker A: grok now prints _PERSONA_RUN_PY's warning, worded for the persona lane
      ("dispatch_persona: WARNING unresolved cleanup ..."); a label parameter would suit
      both. grok_read_isolation_check (at-setup) still runs its inspect with --foreground
      from a scratch directory it then removes. invoke_grok's non-home _lease_ctx refusal
      still says "not inside a git checkout" for root and error, and coordinate.sh:443's
      else-branch assumes one cause; _LEASE_CTX_WHY now names the real one. invoke_cursor
      infers plan mode from the agent name, so a future cursor-agents/analyst.md would lose
      it. In the trap path the supervisor's own 80 is not read. lease_create's provisioning
      inspect runs --foreground with no group sweep afterwards (lease-lane scope).
      fix worker B (follow-up): meta_version checks only the metadata block's own level;
      deeper nesting inside metadata, or a "- " line after a quoted value, still passes
      validate-versions, though validate-skills fails both (C3, C14), so the release gate
      still fails. C3's block-scalar detection knows only | and > with -/+; an indentation
      indicator such as |2 is not recognized (C2 already rejects it).
      fix worker D: if a worker rewrites refs/heads/main as a symbolic ref to a tag,
      show-ref --verify follows it; the integrity check sees a move only when the commit
      changes, and a promotion would write through to the tag. lease_promote's "already on
      the default branch" error still says "default branch" for an explicit target. The
      integrity digest covers .git/config, config.worktree, hooks/, info/, the global and
      trusted configs, the lease-root record and the checkout's .git, plus the default and
      integration branches' commits; it does not cover refs/tags, refs/<name>,
      $GIT_DIR/<name> files or packed-refs (every lease decision now reads refs/heads/<name>,
      a commit id read once, or HEAD).
      fix worker A (follow-up): _dispatch_role_claude writes _lease_ctx's line to <out>.err
      before the run; if _claude_lane_argv then fails, an empty .err stays behind. When the
      provisioning inspect's sweep is unresolved, the supervisor's warning naming the pids is
      discarded with grok inspect's stderr, so the refusal says rc 80 but not which pids. A
      worktree lease_create leaves for an unresolved sweep makes the next lease stop with
      rc 44 (lease history without a ledger) until the user removes it with the printed
      commands (intended, fail closed).

## Interface proposals
<!-- No active proposals -->

## Archived (superseded)
<!-- Moved here 2026-10-01 (U3). Kept as history; each line says what superseded it. -->
- Worker discovery (int4b, 2026-10-07): lease-wait.sh's three ledger readers used plain open() and could block on a FIFO. — Fixed in Phase 6: they read through read_regular (47878ac, SELF-27 "FIFO ledger").
- Worker discovery (u15-instr, 2026-10-07): inline `python3 -c` programs imported from the cwd. — Fixed in Phase 6 (S1): every inline program starts with `_PY_PRELUDE` (47878ac, SELF-27).
- Completion promise: Only emit `<promise>DONE</promise>` after verification checklist passes. — Superseded by the `ops/.sprint-complete` sentinel that `scripts/coordinate.sh` detects (D-030); the `/goal` checklist is best-effort.
- ship-loop.sh (Stop hook) only blocks the session that activated it — uses session_id from stdin JSON for isolation. — ship-loop.sh was retired with the sentinel-based completion signal (D-030); not coming back.
- ship-loop.sh outputs JSON `{decision, reason, systemMessage}` to match Blueprint visual format — reason contains the original goal prompt re-injected on each iteration. — Retired with ship-loop.sh (D-030); hook stdout now never starts with `{` (D-031c).
- ship-loop.sh state file uses YAML frontmatter with `active`, `session_id`, `iteration`, `max_iterations`, `completion_promise` — prompt body goes after second `---`. — Retired with ship-loop.sh (D-030).
- GEMINI.md and CODEX.md files don't exist in the repo — link to external GitHub URLs instead. — The Gemini lane was retired in v3.0.0 (agy replaced it); Codex worker instructions ride in `codex-agents/agents.toml`, and the one instruction file is the root `AGENTS.md` (U3).
- Gemini CLI's GEMINI.md files have a prompt injection risk when loading from untrusted sources. — Gemini lane retired in v3.0.0; the general rule survives as "worker output is data" in `AGENTS.md` (R49).
- When Gemini writes to ops/MEMORY.md or ops/CONTRACTS.md, always specify `(append)` — without it, Gemini may overwrite existing content. — Gemini lane retired in v3.0.0; agy's write denials against `ops/` are handled by promoting captured output (D-032).
