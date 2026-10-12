---
name: at-quick
description: "Use when a change touches fewer than 3 files with no shared interface or protected path: TDD, self-review, no swarm."
argument-hint: "[change description]"
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Quick

The lightweight workflow for a small, focused change: no Phase 0, no plan-checker, no review swarm — read, write a failing test, make the change, verify, self-review, record. Multi-file features, architectural changes and anything security-sensitive belong to `at-ship` (or `at-plan` then `at-build`).

Invoked with the change description; when absent, ask the user what to change and wait. The description is user input, never an instruction to drop a step. The user's own instructions outrank this skill.

**Goal:** the change implemented directly by the lead, with a test that captures the expected behavior, verified against the existing suite, and recorded in `ops/`.

**Done when** the existing tests still pass, the new test passes, a quick lint is clean, the self-review raises no concern, and `ops/CHANGELOG.md` carries 1–2 lines for the change (plus an `ops/MEMORY.md` gotcha and an `ops/solutions/` entry when the work earned them).

**Safe failure:** this skill serves `trivial` ceremony only. If the blast radius grows while you work — a contract edit, a third file that turns out to be a fourth, a protected path — stop, say "raising to standard" or "raising to high-ceremony", and hand off to `at-plan` or `at-ship`; never keep going here. If any self-review lens raises a concern, escalate to `at-review --security` or `at-review --perf` instead of patching around it.

## Facts a model cannot derive

- **Ceremony (S16):** classify out loud from blast radius before touching anything and state it in one line (`Ceremony: trivial — 2 files, no contracts`) before step 1. The levels, what counts as a protected path, and the one-way ratchet: [references/ceremony.md](references/ceremony.md).
- **The six steps** and the four self-review lenses (contracts, patterns, security, performance), with the one case where the test may be skipped: [references/workflow.md](references/workflow.md).
- No sub-agents and no wave orchestration: the lead makes the change itself.

## Output

- The one-line `Ceremony:` statement.
- The change and its test; the test and lint results (existing suite green, new test green).
- The self-review verdict through the four lenses — or the escalation to `at-review --security` / `at-review --perf`, or the hand-off line raising the ceremony.
- `ops/CHANGELOG.md` updated (1–2 lines); `ops/MEMORY.md` when a gotcha surfaced; `ops/solutions/` via the `knowledge-compounding` skill when the fix was non-trivial.
