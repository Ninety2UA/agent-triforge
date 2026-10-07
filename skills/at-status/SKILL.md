---
name: at-status
description: "Use when you need the sprint's phase, task counts, blockers, pending reviews and uncommitted changes in one report."
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Sprint Status

**Goal:** one concise report of where the sprint stands, built from the `ops/` files, git and the review files, so the user can diagnose a stuck sprint or choose the next workflow. **Done when** the report is printed with every section present; a section with nothing to say says "none". **Safe failure:** this skill reads and reports. It writes nothing, dispatches no CLI and never dumps file contents at the user. When `ops/` or a file is missing, the report says "no active sprint" or "none" for that section instead of guessing.

Invoked with no arguments.

## What to look at

- `ops/STATE.md` — the last saved checkpoint: phase, next actions. Its `## Current phase` value sits on the line after the heading.
- `ops/TASKS.md` — the task table; the sprint goal is its header. Counts come from the status column: done, in progress, active (pending), blocked, in review.
- `ops/CHANGELOG.md` — the last 3–5 entries are the recent activity.
- `ops/MEMORY.md` — recent decisions, for the blockers and context.
- `git status` — uncommitted changes.
- `ops/REVIEW_ANTIGRAVITY.md`, `ops/REVIEW_CODEX.md`, `ops/TEST_RESULTS.md` — a file that exists is a review the lead has not archived. It counts as processed when `ops/TASKS.md` carries a `## Review dispositions — Cycle N` block for its cycle; the wrap moves processed files to `ops/archive/<date>/`.
- `ops/leases.toml`, when it exists — open leases. `lease_status` prints them once the helper is sourced: `ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"`. The locator fails closed naming `at-setup`; in that case read the ledger file directly. `$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`.

Phases are 0 codebase analysis, 1 plan (1a pre-plan research, 1b planning, 1.1 ambiguity resolution, 1.5 plan validation), 2 build, 3 parallel review, 4 process reviews, 5 test, 6 wrap. Completion is the `ops/.sprint-complete` sentinel, created only by the lead after the verification checklist passes.

## Output

The overview, in the shape of [references/status-template.md](references/status-template.md): `## Sprint status` with **Goal** and **Phase**, then `### Tasks`, `### Blockers`, `### Recent activity`, `### Pending reviews`, `### Uncommitted changes` and `### Available commands` — the seventeen Triforge workflows, printed in the form the lead's harness uses (`/at-name` under Claude Code, `$agent-triforge:at-name` under Codex; one form only). Nothing is written to disk.
