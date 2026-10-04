---
name: at-build
description: "Use when ops/TASKS.md holds assigned tasks and Phase 2 should run: leased builder-pool waves, cross-review, merge."
argument-hint: "[--team] [--wave N]"
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Build (Phase 2)

**Goal:** every task in `ops/TASKS.md` built by a roster-assigned builder under its own lease in an isolated worktree, cross-reviewed by a pinned non-author reviewer, merged as one squash commit per task on the sprint integration branch, verified at wave end and promoted to the main branch through the `[promotion]` gate. The builder pool replaces the single-writer rule: safety is leases + worktree isolation + cross-review, not write-restriction.

**Done when** all waves are merged, the full test suite and a build from a clean state pass, `integration-verifier` has passed against the integration branch, the promotion gate is satisfied, and `ops/TASKS.md`, `ops/CHANGELOG.md` (one `lease_attribution` line per merged task) and `ops/CONTRACTS.md` reflect the result.

**Safe failure:** a merge `lease_merge` refuses (self-review, AE3; an unknown reviewer; no pin; the checkout on the default branch) stays unmerged: fix the cause, never bypass it. A failed `integration-verifier` blocks the next wave. Findings re-dispatch the same lease and builder with the same pinned reviewer while the cycle is below 3; the third cycle escalates to the user. Halt a builder at risk above 20 % or more than 50 changed files. Promotion blocks when approval is required or a protected path is touched; the user approves. The user's instructions outrank this skill.

Prerequisites: `ops/TASKS.md` with assigned tasks (`at-plan` writes it) and a passed Phase 1.5 plan validation. Read `ops/TASKS.md`, `ops/CONTRACTS.md`, `ops/MEMORY.md` and `ops/ARCHITECTURE.md` first. Invoked with `--team` to force agent-team mode and `--wave N` to resume from wave N (completed waves skipped); when absent, the mode follows the task count below. Alternatives: `at-ship` runs the whole Phase 0–6 sprint; `at-quick` takes a small focused change (fewer than 3 files, obvious fix) without the review swarm.

## Preflight

`$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`. Core-trio liveness is gated here, never at session start (fast non-model `--version` checks, cached per session; on failure it names the failing member and its install or login fix):

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
ensure_core_trio_live || exit 1
```

## Facts the tree does not tell you

- **Ceremony (S16):** the `Ceremony:` line at the top of `ops/TASKS.md` governs. `high-ceremony`: plan-checker must have passed (never skip Phase 1.5), the wave ends with `integration-verifier`, and the follow-on review runs as `--full`. `trivial`: may skip Phase 0 and Phase 1.5. `standard`, or no line: the default posture.
- **Mode:** fewer than 5 independent tasks → sub-agent mode (default); 5 or more tasks, cross-dependent work, or `--team` → agent-team mode with the `team-lead` persona; `--wave N` → start from wave N. Personas (`integration-verifier`, and `continuous-reviewer` in team mode) run through `dispatch_persona`, whose manifest entry sets tools, model tier and turns, so a call pins nothing. Agent teams are harness-specific: [Claude](references/claude.md), [Codex](references/codex.md).
- **Per-task lease loop** (`lease_create` → `lease_dispatch` → `lease_wait` in bounded slices, collecting, until nothing builds or it returns rc 80 → `lease_pin_reviewer` → review → `lease_merge`), its refusals, the fix-cycle rule and attribution: [lease lifecycle](references/lease-lifecycle.md).
- **Wave grouping, risk scoring and between-wave verification** in sub-agent mode: [subagent mode](references/subagent-mode.md). The team-lead flow and a teammate's own review/test dispatch with the promotion guard: [team mode](references/team-mode.md).
- **Wave end:** the `integration-verifier` persona against the integration branch, then `lease_promote`, which reads `[promotion] require_user_approval` (default false), scans the integration diff and blocks (no merge) when approval is required or a protected path is touched (permission configs, deny rules, `ops/roster.toml`, shipped agent configs). Those diffs need the lead or the user as reviewer, never an external-CLI-only review: a merge approval per protected task, and the user's promotion approval (`lease_approve`).

## Output

- One squash commit per approved task on the sprint integration branch, recorded with builder, reviewer and merge commit in the ledger (`lease_status`).
- `ops/CHANGELOG.md` rows from `lease_attribution` (builder, reviewer and class, lead, approval origin, merge commit); completed build tasks moved to Done and review tasks to Review in `ops/TASKS.md`; `ops/CONTRACTS.md` updated when new interfaces were introduced.
- The `integration-verifier` result per wave and the promotion result: promoted, or blocked with the reason and the `lease_approve` call the user must make.
