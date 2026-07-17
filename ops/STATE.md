# Session state
<!-- Saved: 2026-07-17 -->
<!-- Type: wrap (planning complete, execution not started) -->

## Current phase
Planning complete for the v3.0.0 CLI modernization + builder pool. Implementation not started.

## The plan
`docs/plans/2026-07-17-001-feat-cli-modernization-builder-pool-plan.md` — implementation-ready unified plan (ce-brainstorm → ce-plan → two ce-doc-review rounds; 23 + 13 findings applied). Self-contained: Product Contract (R1–R39, AE1–AE8), Planning Contract (KTD-1–14 + diagrams + risks), 17 implementation units in 3 phases, Verification Contract, Definition of Done. One open question deferred in-doc: release cadence (single v3.0.0 vs Phase-A-first split).

Scope in one line: migrate the Gemini lane to Antigravity (`agy`), absorb Claude Code/Codex updates native-first, replace single-writer with a configurable six-CLI builder pool (worktree leases + cross-review), add OpenCode/Kimi Code/Cursor as optional members, ship `/cli-watch` + `/repo-watch`, produce the four-repo mining report, release as v3.0.0.

## Task status snapshot
- All 17 units pending. U1 (capability probe harness) gates everything — run it first. U17 (onboarding/enrollment) follows U8.
- Delivery order (user-directed): Phase A (modernize incumbents, U1–U7) → Phase B (pool + optional CLIs, U8–U13) → Phase C (watch family + first runs + release, U14–U16).
- U11→U12→U13 are serialized (all edit scripts/invoke-external.sh).

## Research artifacts (verified 2026-07-17)
- `ops/research/2026-07-17-factsheet-claude-code.md` — /goal, workflows/ultracode, models (Fable 5, Sonnet 5 1M ctx), effort levels, plugin-system changes
- `ops/research/2026-07-17-factsheet-antigravity.md` — Gemini service cutoff 2026-06-18, `agy` CLI, migration paths, Flash-default trap, permission-system rewrite
- `ops/research/2026-07-17-factsheet-codex.md` — 0.144.5, gpt-5.6-sol, hooks-under-exec likely fixed (re-probe → D-004 flip), features list, --output-schema
- `ops/research/2026-07-17-factsheet-new-clis.md` — OpenCode/Kimi Code/Cursor headless embedding facts + fragility flags
- `ops/research/2026-07-17-grounding-dossier.md` — repo file:line quotes (42-file gemini footprint, invocation seams; may drift as code changes)

## Known issues
- None blocking. Working tree has uncommitted changes: the plan, these fact sheets, this STATE.md (memory files live outside the repo). Commit before or at the start of execution.

## Recommended next actions
1. New session, from repo root: `/compound-engineering:ce-work docs/plans/2026-07-17-001-feat-cli-modernization-builder-pool-plan.md`
2. ce-work reads Goal Capsule → units in dependency order → Verification Contract gates. U1's probe record steers the probe-gated branches (Codex hooks, Kimi agents, Cursor hooks, monitors, Routine delivery).
3. Alternative: run the plan as a `/goal` (thin objective pointing at the plan; see plan's Goal Capsule).
4. Scope changes go back through `/ce-brainstorm`; plan adjustments via `/ce-plan` on the same file (it resumes/deepens in place).
