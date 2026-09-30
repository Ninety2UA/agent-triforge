# Changelog

## [2026-10-01] — v3.3.3: protected-path registry, digest-stamped skills, lead git integrity

### Claude Code (builder: lead, Fable 5.1 session via ce-work; reviewer: the user, on the PR — every file here is a protected path)
- **Gate (U28, KTD15):** `scripts/probe-capabilities.sh --self-only` runs only the static SELF rows (the per-CLI sections are skipped, SELF-06 records SKIPPED), writes its record under `${TMPDIR}` and refuses a dated probe-record `--record`, and exits 3 naming every SELF FAIL. SELF-07 resolves its builder through stub core-trio binaries, so the rows pass on a host with no CLI. `.github/workflows/gates.yml` (new) runs shell syntax, both validators and the gate under `/bin/bash` 3.2 on macOS for PRs to `main` and `release/4.0`, and proves the gate can fail (pre-push hook removed from a scratch copy → exit 3 naming SELF-09).
- **Fix (U1, R30/KTD8):** `scripts/lib/registry.sh` (new, in the loader after `common.sh`) holds `FRAMEWORK_PROTECTED` (Triforge checkout only, detected from `.claude-plugin/plugin.json` in the working tree, HEAD or the default branch; an unparseable manifest counts) and `PROJECT_PROTECTED` (everywhere), with a case-folded match and any-depth instruction files. `lease_promote` diffs with `-z --no-renames` and blocks with rc 42 when the diff or the classifier fails. `.claude/CLAUDE.md` keeps one canonical protected-path line; SELF-10 checks it against the registry (planted-path negative control) and runs the promotion scenarios on Triforge- and user-shaped fixtures.
- **Fix (U2, R31/KTD12):** `scripts/lib/skills-sync.py` (new) is the one refresh for `session-start.sh` and `_lease_provision_skills`: a digest per written directory in the stamp (format 2), legacy 3.3.0–3.3.2 stamps migrated against `scripts/lib/skill-digests.txt` (generated from the `v3.*` tags), empty slots only without a stamp, symlinked or escaping `.agents` left alone. `_lease_provision_skills` no longer falls back to the project's own `skills/`. SELF-08b rewritten; against the old code it fails eight checks, including a forged stamp deleting a user directory and provisioning writing through a committed symlink.
- **Fix (U27, R46/R47/R49, KTD18/KTD19):** `_lead_git` for every git call in `scripts/lib/lease.sh` (the trusted-config capture is the one documented exception); the checkout root is found without git. `[baseline]` in the ledger plus per-lease base/pointer/admin digests; a digest and copy of each lead ledger write in `<lease root>/lead/`. `_lead_integrity_check` at create, dispatch, pin, collect, merge, promote, requeue and heartbeat restores `.git/config`, hooks and the ledger (`.git/info` is detect-only), escalates, names the surface, returns 44; `lease_rebaseline` accepts and resumes. `lease_collect` kills the builder's tree and takes the snapshot; `lease_merge` squashes the recorded SHA only (refuses builder commits, `ops/` paths, a changed worktree, a moved integration branch). SELF-18 covers twelve scenarios plus a static `_lead_git` check. Security-model and SELF-04 wording: the worktree limits where a builder starts, not where it writes.
- **Review (ce-code-review run 20260928-220309-a35b0d09; six Opus 5.5 reviewers + an independent Codex pass; verdict "Ready with fixes", 4 P1):** the lead's trusted git config is a digested, restorable surface (#1); a protected directory entry matches its bare name, and `opencode.json`, `opencode.jsonc`, `.cursorrules` join the project list (#2); a restore saves the changed version first (#3) and uses only a lead copy that still matches the baseline (#11); the lead checkout's own `.git` is a surface (#4); the identity capture follows includes (#5); `.git/info` is detect-only and `info/refs` is ignored (#10, #26); create/merge/promote refuse a switched lead branch, and the default branch is never recorded as the integration branch (#12); `lease_rebaseline` records each acceptance (#24); one guarded ledger tamper check (#8); plus the follow-up items listed in the PR.
- **Cross-review on PR #12 (three Opus 5.5 reviewers on the final diff, 2026-10-01; merged by the lead under the user's standing authorization):** `.git/config.worktree` (read once `extensions.worktreeConfig` is on) is a digested, restorable integrity surface (`config_worktree`); a deleted integrity anchor is a change, never a first use — a missing `ledger.sha256` beside an existing `ledger.copy` sets `ledger_alert`, a ledger whose `[baseline]` table is gone while its rows or the lead copies show one was recorded reports `baseline_missing` (rc 44; `lease_rebaseline` records a new one), and a deleted ledger + digest with copies still in the lead state dir refuses the next lease call (rc 44) and names the recovery; `lease_collect` re-runs the integrity check right before the snapshot's `add -A`; the `ops/` diff check in `_lease_verify_snapshot` reads the diff from a file and refuses on a failed diff (fails closed); a dispatch whose subshell exited before `ps` ran records `pid_started = "exited-before-record"`, so neither collect nor heartbeat ever signals that pid; `lease_promote` reads `ops/roster.toml` and `_lease_copy_discoveries` writes `ops/MEMORY.md` under the lead checkout, not the cwd. SELF-18 gains the `cfgwt`, `sha`, `table` and `ledger-gone` cases. Residuals kept (documented): every anchor lives in builder-writable storage, so a consistent rewrite of ledger + digest + copies is undetectable (detection, not prevention); `include.path` targets are not digested; the check-to-snapshot window closes fully only with U13's process groups.
- **Behavior changes:** `lease_merge`'s commit no longer runs repository hooks and is never GPG-signed; a lead commit on the integration branch between merges, a switched lead checkout, or a manual promotion needs `lease_rebaseline` before the next lease call; a `.git/config`/hook change the lead or user made is reverted at the next lease call and saved as `<lease root>/lead/<name>.changed-<UTC>`; more promotions are gated (this repo: `commands/`, `skills/`, `hooks/`, `templates/`, `.github/`; every project: all of `.claude/` and `.agents/`, root `opencode.json`/`.cursorrules`, instruction files at any depth).
- Version 3.3.3 in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `antigravity-agents/plugin.json`; README "What's new" and ledger entry; `docs/index.html` badge and note. The probe record is not regenerated (hotfix; `--self-only` passes with 17 SELF rows).

## [2026-09-28] — v3.3.2: release gate green, OpenCode V2 guard, Cursor Grok 4.7 ids

### Claude Code (builder: Opus 5.5 session, review fixes by the lead; reviewer: lead, Fable 5.1, PR #11)
- **Fix (D-039):** `hooks/hooks.json` quotes the placeholder in all four commands (`bash "${CLAUDE_PLUGIN_ROOT}/hooks/handlers/<name>.sh"`). Since Claude Code 2.1.281, `claude plugin validate` warns on an unquoted `${CLAUDE_PLUGIN_ROOT}` in shell-form hooks, and `--strict` made `.claude-plugin/plugin.json` fail with 4 warnings. Both manifests pass `--strict` on 2.1.283. The `docs/agent-triforge.md` example matches.
- **Fix (D-039):** probe CC-06 (`scripts/probe-capabilities.sh`) validates `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` separately and passes only when both do. `validate --strict "$REPO_ROOT"` resolved to the marketplace manifest only, so CC-06 reported PASS while the gate was red. The row ID, name and evidence style are unchanged.
- **Fix (D-049):** OpenCode V2 guard. `_opencode_v2_check` / `_opencode_v2_refusal` (`scripts/lib/opencode.sh`) read `opencode --version`. On major ≥ 2, `invoke_opencode` fails as a deterministic preflight (rc 1, reason `unsupported-version`, guidance in the output file), and the lease `opencode)` arm (`scripts/lib/lease.sh`) writes the refusal to `<out>` with class `deterministic`. `roster_enroll_member` returns a new `unsupported:` (rc 30) instead of offering or auto-enrolling V2, and `commands/setup.md` documents it. `roster_member_status` reports `unsupported-version(<ver>)`, so `/setup`'s closing table shows the row as "unsupported (V2)" rather than enrolled (review finding #2). The message names the V1 pin `npm i -g opencode-ai@1`. An unreadable version is not refused.
- **Fix (D-049, review):** the V2 check fails closed. `_opencode_v2_check` sets `_OPENCODE_CHECK` to `v1`, `v2` or `unreadable`, and returns 0 only for a confirmed V1. A version that can't be read (timeout, crash, no x.y output) is refused like V2, with its own message and reason `unreadable-version`; `roster_member_status` reports `unsupported-version(unreadable)`, which `/setup` shows as "unsupported (version unreadable)".
- **Fix (D-049, review):** `resolve_role` walks past a refused OpenCode through `RESOLVE_ROLE_EXCLUDE`, with one stderr WARNING, so a role whose primary is OpenCode falls back to the next CLI instead of failing every task. The version probe runs only when `ops/roster.toml` names opencode; no shipped default chain does.
- **Fix (D-050):** Cursor ids take the `cursor-` prefix from the Grok family. `_CURSOR_ID_PY` (`scripts/lib/cursor.sh`) is the one place the Grok id is parsed and prefixed; the families that carry `cursor-` are 4.5 and 4.6. `_cursor_model_for_effort`, `resolve_role`, `roster_role_entry` and `roster_write_role` all splice it in, and each keeps its own explicit-suffix precedence. `roster_role_entry` (the `/setup` role table) is a fourth composer the plan did not list; it is included so the table cannot drift from dispatch. The shipped pin stays `cursor-grok-4.6-xhigh`.
- **Fix (S28, reproduced):** `commands/setup.md`'s `_roles_for` reads the CLI from `ROLES_CLI` instead of `$1`. A throwaway project command showed Claude Code 2.1.283 substitutes positional tokens in command bodies, code blocks included, counting from zero: `$0` is the first argument and `$1` the second. No other positional tokens exist in `commands/` or `skills/`.
- Version 3.3.2 in `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` and `antigravity-agents/plugin.json`. README "What's new" and the ledger entry are added, and the `docs/index.html` badge is bumped.

## [2026-04-20] — v2.4.0: Framework self-audit — two blockers + four HIGH fixes

### Claude Code
- **BLOCKER fix:** Removed broken session_id comparison in `ship-loop.sh`. The slash commands wrote `session_id: "<current-branch-name>"` into the state file; the hook compared against Claude Code's runtime session UUID. Mismatch → the guard took the "different session" exit every call → the inner loop never blocked premature exits during autonomous `/ship`/`/coordinate` runs. State-file presence with `active: true` now indicates the active loop.
- **BLOCKER fix:** `PostToolUseFailure` is not a valid Claude Code hook event — loader silently ignored the registration, so `tool-failure-monitor.sh` was dead code. Merged the handler into the existing `PostToolUse` hook and added in-handler filtering on `tool_response.is_error` / `tool_response.error`. Smoke-tested both success (no state change) and failure (counter increment) paths.
- **HIGH fix:** Removed `-y` (YOLO) default from `invoke_gemini`. YOLO installs a max-priority allow rule that overrides every policies.toml deny (documented in the policy file itself) — the `rm -rf`/`git push`/`sudo` guardrails were effectively inert. Now gated on `GEMINI_YOLO=1` env var for the rare environment that genuinely needs it.
- **HIGH fix:** Migrated `agents/team-lead.md` from legacy `gemini -p "$(cat SKILL.md) ..."` direct invocations to `invoke_gemini` / `invoke_codex`. Team-mode builds now get policy loading, timeout enforcement, retry, and native-agent routing like the rest of the framework.
- **HIGH fix:** `templates/CLAUDE.md` and `README.md` updated — both documented the legacy invocation pattern as if current. New adopters now see `invoke_gemini` / `invoke_codex` as the primary pattern.
- **MEDIUM fix:** `grep -c … || echo "0"` produced `"0\n0"` on zero matches because `grep -c` already prints `0` before exiting 1. Replaced with `|| true` in `session-start.sh` + `pre-compact.sh`. Fixed the broken CLAUDE.md "Hook safety" guidance that documented the buggy pattern.
- **MEDIUM fix:** `pre-compact.sh` `CURRENT_PHASE` default was clobbered when `ops/STATE.md` existed but lacked a `## Current phase:` line (sed with no match exits 0, so `|| echo "unknown"` never fired). Fixed via explicit empty-check.
- **MEDIUM fix:** `session-start.sh` commands banner now lists all 16 commands (was 13 — missing `/analyze`, `/coordinate`, `/resolve-pr`).
- **MEDIUM fix:** State-file writes in `ship-loop.sh` and `tool-failure-monitor.sh` switched from `sed` to `python3` to eliminate sed-metacharacter injection risk.
- **MEDIUM fix:** `_run_with_timeout` now emits a one-shot stderr warning the first time it falls back to no-timeout execution (neither `timeout` nor `gtimeout` on PATH).
- **LOW fix:** Added `ops/RESEARCH_GEMINI.md` (written by `targeted-researcher`) to the shared-file tables in CLAUDE.md and templates/CLAUDE.md.
- **LOW fix:** `scripts/coordinate.sh` now does a `claude` CLI preflight and fails fast instead of silently looping with empty output.
- **LOW fix:** Removed redundant `agents`/`skills`/`commands` path declarations from `.claude-plugin/plugin.json` (auto-discovered under the current plugin spec).
- **Verified upstream:** Gemini subagent frontmatter uses snake_case `max_turns`/`timeout_mins` per official spec — current frontmatter is correct. Codex `nickname_candidates` is a real, documented field — not dead config.
- Smoke-tested: grep -c zero-match produces single `"0"` (length 1), sed-empty-output fallback yields `"unknown"`, tool-failure-monitor writes state only on `is_error:true` payloads.

## [2026-04-01] — Fourth audit, README polish, SVG cleanup

### Claude Code
- Fourth audit pass (5 agents + manual 11-point verification) found and fixed last remaining issue: `ship-loop.sh` missing `mkdir -p .claude` guard
- Documented plugin conversion solution in ops/solutions/2026-04-01-plugin-conversion.md
- Updated README: complete 4-pass audit history, convergence table, verification section
- Added "What's new (v2.0.0)" section to README (plugin install, ship-loop rewrite, audit summary, bootstrapping)
- Fixed hero SVG: "8 reviewers" → "7 reviewers"
- Fixed TASKS.md table entry: marked as `(runtime)` since it's generated, not committed
- Removed outer border strokes from all 10 diagram SVGs for cleaner appearance
- All 49 framework components verified clean across 20 parallel agents + manual checks

## [2026-03-31] — v2.0.0: Claude Code plugin conversion

### Claude Code
- **Breaking:** Converted from git-clone installation to Claude Code plugin system
- Created `.claude-plugin/plugin.json` (v2.0.0), `hooks/hooks.json`, root `settings.json`
- Moved all components from `.claude/` to root: `agents/`, `skills/`, `commands/`, `hooks/handlers/`
- Updated all skill injection paths: `.claude/skills/` → `${CLAUDE_PLUGIN_ROOT}/skills/`
- Added ops/ bootstrapping to `session-start.sh` (creates dirs + copies templates on first run)
- Created `templates/CLAUDE.md` and `templates/ops/` for project bootstrapping
- Install: `claude plugin add https://github.com/Ninety2UA/agent-triforge`
- Update: `claude plugin update agent-triforge`
- Updated README, CLAUDE.md, and docs for plugin structure

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
- Wrote comprehensive docs/agent-triforge.md with all phases, protocols, and patterns
- Updated CLAUDE.md with full framework reference
- Created README.md with SVG hero banner, sprint lifecycle diagram, review swarm diagram, quality gates visualization, and knowledge loop diagram
- Published to GitHub: github.com/Ninety2UA/agent-triforge
