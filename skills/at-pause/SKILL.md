---
name: at-pause
description: "Use when stopping mid-sprint: writes the ops/STATE.md checkpoint a later session resumes from, and nothing else."
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Pause (checkpoint)

**Goal:** `ops/STATE.md` records where this session stopped — phase, sprint, task counts, in-progress work, decisions, review-cycle state, next actions and what was last proven green — so a resume continues without re-deriving it. **Done when** the file is written in the shape of [references/state-template.md](references/state-template.md) and the user has been told the state is saved and how to resume. **Safe failure:** a checkpoint overwrites only `ops/STATE.md`. Nothing is archived, summarised, compounded or moved. Never fabricate a baseline: when nothing was proven green this session, record `command: none` and `result: "not verified"` rather than copying an older one.

Invoked with no arguments.

## A checkpoint is not a wrap

- A pause is a mid-sprint save, not a clean end. It does NOT archive `ops/REVIEW_*.md` or `ops/TEST_RESULTS.md`, write a sprint summary, compound knowledge into `ops/solutions/` or `ops/decisions/`, or move tasks to Done in `ops/TASKS.md`. Those belong to `at-wrap`.
- The file is the `session-continuity` skill's pause snapshot (its full text: `$ROOT/skills/session-continuity/SKILL.md` after `ROOT=$(bash scripts/locate-triforge.sh) || exit $?`): machine-readable YAML frontmatter first (`saved`, `phase`, `wave`, `tasks`, `verification_baseline`, `verification_command`, `state_head`), then the prose sections, marked `Type: checkpoint (not wrap)` so a reader can tell a checkpoint from a wrap.
- `verification_baseline` is a claim about one commit: the command exactly as run, its result verbatim, and the commit it ran against. `state_head` is `git rev-parse HEAD` at save time, even with a dirty tree; the dirty paths go under "In-progress work".
- The `## Current phase` value goes on the line after the heading, never inline — the pre-compaction hook reads and rewrites that shape (its own checkpoint carries no baseline; a resume treats a missing baseline as "not verified").
- The lease snapshot section is written only when `ops/leases.toml` exists; `lease_status` prints the counts once the helper is sourced (`source "$ROOT/scripts/invoke-external.sh"`).

## Output

- `ops/STATE.md` — the frontmatter plus the sections `Current phase`, `Active sprint`, `Task status snapshot` (N done, N in progress, N remaining, N blocked), `In-progress work` (what was active, uncommitted files, branch), `Context` (decisions this session, blockers, open questions), `Review cycle state` (cycle N of 3, convergence mode fast | standard | deep, outstanding P1 and P2 counts), `Next actions (when resuming)` (numbered, first thing first), and `Lease snapshot` when a ledger exists — per [references/state-template.md](references/state-template.md).
- One line to the user: "State saved. Use /at-resume to continue." — `$at-resume` when the lead is Codex.
