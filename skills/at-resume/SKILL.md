---
name: at-resume
description: "Use when starting a session on existing work: restores ops/STATE.md, re-proves the baseline and continues the phase."
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Resume

**Goal:** the sprint continues from where the last session stopped, with the saved state proven current rather than assumed. **Done when** the user has the summary (sprint goal, current phase, tasks completed vs remaining, blockers or pending decisions, recommended next action), has said whether to continue automatically or review the state first, and work has resumed at the recorded phase. **Safe failure:** when `ops/STATE.md` is missing, say so and stop; a stale baseline is re-proven before anything else; a merged lease is never redone; when the saved state and the tree disagree, ask before acting.

Invoked with no arguments. The user's instructions outrank the saved plan: a user who says what to do next overrides "Next actions".

This is the `session-continuity` skill's resume protocol (full text: `$ROOT/skills/session-continuity/SKILL.md`). The helper and the sibling skills are reached through `ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"`; the locator fails closed naming `at-setup`. `$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`.

## Step 1: Load state

Read, in order: `ops/STATE.md` (where you left off — phase, progress, next actions; a `Type: checkpoint` marker means a pause, not a wrap), `ops/TASKS.md` (task status), `ops/MEMORY.md` (decisions and gotchas from previous sessions), `ops/CHANGELOG.md` (what was already done), `ops/CONTRACTS.md` (current interface definitions).

## Step 2: Assess the current state

- Baseline: when `git rev-parse HEAD` differs from `state_head`, or `verification_baseline.commit` differs from HEAD, or the baseline is missing, re-run `verification_command` and record the fresh result before continuing. A baseline from another commit proves nothing about this one.
- Uncommitted changes (`git status`); the phase active at pause; remaining tasks by status (active, in progress, blocked, review); review files present (`ops/REVIEW_ANTIGRAVITY.md`, `ops/REVIEW_CODEX.md`, `ops/TEST_RESULTS.md`).
- Leases: when `ops/leases.toml` exists, `lease_heartbeat_check` reclaims orphans (rc 44 means a git-integrity change the lead did not make — inspect it, then `lease_rebaseline`); open leases are requeued or finished, `building` ones waited on with `lease_wait` as the harness reference says ([references/claude.md](references/claude.md), [references/codex.md](references/codex.md)); merged leases are already on the integration branch and are never redone. See [references/lease-resume.md](references/lease-resume.md).

## Step 3: Report to the user

Summarise: sprint goal, current phase, tasks completed vs remaining, blockers or pending decisions, recommended next action. Then ask whether to continue automatically or review the state first, and wait.

## Step 4: Resume execution

Pick up from the phase recorded in `ops/STATE.md`: mid-Phase 2 → the remaining build tasks under the wave protocol (`wave-orchestration`, driven by `at-build`); mid-Phase 3–4 → check whether the reviews are complete and process them (`at-review`); mid-Phase 5 → check the test results and fix failures (`at-test`); Phase 6 needed → `at-wrap`. Sub-agents a resumed phase needs are spawned through the lead's harness, model and effort pinned on every spawn — see [references/claude.md](references/claude.md) and [references/codex.md](references/codex.md).

## Output

No artifact of its own. The summary to the user (sprint goal, current phase, tasks completed vs remaining, blockers or pending decisions, recommended next action), the fresh baseline recorded in `ops/STATE.md` when HEAD had moved, and then the resumed phase's own outputs.
