---
saved: 2026-10-01T00:45:00Z
phase: 0-starting
wave: 0
tasks:
  total: 29
  done: 4
  blocked: 0
verification_baseline:
  command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json; bash scripts/probe-capabilities.sh --self-only"
  result: "All PASS on main 79db9c0 (= release/4.0 start): validate-versions PASS, ladder 24a7ee2039c8c2e4907472e4cf82fdfd; 12 skills OK; both manifests --strict; SELF gate 17 rows none FAIL; gates.yml green (run 36786228612)."
  commit: 79db9c0
verification_command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json; bash scripts/probe-capabilities.sh --self-only"
state_head: 79db9c0
---
# Session state
<!-- Saved: 2026-10-01T00:45:00Z -->
<!-- Type: program handoff — Phase H released as v3.3.3; Phases 0–6 running autonomously on release/4.0 -->

## Current phase

**Phase H is done:** PR #12 squash-merged to `main` as 79db9c0 on 2026-10-01 and `release.yml` published v3.3.3 (run 36786584796). `release/4.0` was cut from that commit and pushed. **Phase 0 (U21, U3, U22, U4) is next**, on `release/4.0`.

## Authorization in force (2026-10-01)

The user, before sleeping: "review the PR and if it passes fully 5/5, then merge … I'm going to sleep so you are in full charge. Make sure everything is running smoothly and that everything is delivered (all phases, continue running all the phases that are left after this one)." This supersedes, for this program only, the plan's "no autonomous /lfg" and "only the user merges" lines. Standing rules that still hold: each PR gets a real review (independent Opus 5.5 reviewers on the final diff + `gates.yml` green) and merges only on 5/5 (correctness vs the unit specs; gates + negative controls; guards not weakened; docs/release consistency; bash 3.2 + zsh + upgrade compatibility). The plan's stop conditions hold: a settled decision that can't work, a probe row a unit depends on failing with no designed fallback, or a change that would weaken a protected-path/push/approval/git-integrity guard → record the blocker here and in the PR, continue with independent work, leave the decision for the user. Never write user-tier config, never run CLI logins, never launch `danger-full-access` (R50). Memory: `autonomy_grant_2026_09_30.md`.

## Program plan (PR by PR on release/4.0; each built with ce-work on Fable 5.1 @ high, reviewed on Opus 5.5 @ high)

| PR | Units | Status |
|---|---|---|
| 0 | U21 validator prep + ladder source; U3 AGENTS.md + rule inventory; U22 session-start floor/stale-template; U4 removal test + pruning | next |
| 1a | U5 plugin-root resolver + locator; U26 CLI registry; U6 skill conformance validator | pending |
| 1b | U7 commands → at- skills; U24 split oversized skills; U23 remove commands/ | pending |
| 2a | U29 capability/survival probe rows; U13 detached leases + lease_wait + lead exit; U11 worker marker | pending |
| 2b | U9 [lead] table + resolution; U12 claude -p lane; U10 ledger lead CLI / reviewer class / approvals | pending |
| 2c | U25 dispatch_persona lane; U8 personas home, agents/ removed | pending |
| 3 | U14 Codex lead: bootstrap, monitors, coordinator | pending |
| 4 | U16 Grok Build adapter; U17 Devin CLI adapter; U18 other-harness manifests | pending |
| 5 | U15 at-setup lead step + instruction-file detection | pending |
| 6 | U19 watch-cycle carry-ins; U20 two-lead fixture sprint + 4.0 release | pending |
| final | release/4.0 → main as v4.0.0 (release.yml publishes) | pending |

Update this table and the frontmatter at every PR boundary; the plan is `docs/plans/2026-09-28-1946-feat-lead-choice-v4-plan.md`.

## Next actions

1. Phase 0 on `release/4.0`: `/ce-work` scoped to U21, U3, U22, U4 (read this file first). U3's `/doctor` baseline can't be taken headless — note it as "not taken (headless)" and rely on the validator budgets. U4's removal test uses `claude -p` (3 runs per arm minimum).
2. Ship: PR to `release/4.0` (template, provenance table, protected paths = Yes, cross-reviewer = the lead under the authorization above), independent Opus reviewers on the final diff, `gates.yml` green, then squash-merge.
3. Repeat per the table. At the end: regenerate the probe record (U20), bump to 4.0.0, PR `release/4.0` → `main`, confirm `gh release view v4.0.0`.

## Blockers recorded for the user

- (none yet)

## Model and effort (user-approved)

| Work | Model | Effort |
|---|---|---|
| Every build phase, Phase H included | Fable 5.1 | high |
| Reviews | Opus 5.5 | high |
| Audit edits (U3/U4) | Opus 5.5 | medium |
| Watch cycles and research | Opus 5.5 | high |

## Decisions the user made (all recorded in the plan's Key Decisions)

- Lead is Claude Code or Codex only; Antigravity, OpenCode, Kimi and Cursor are workers only.
- Only AGENTS.md ships (no CLAUDE.md anywhere); the Claude Code floor rises to 2.1.277.
- Commands and agents become skills per the Agent Skills spec plus compound-engineering conventions, with the `at-` prefix.
- Context audit first (PR 0); must-hold rules are enforced by scripts, not prose.
- Protected-path cross-review: the lead or the user. Promotion to `main`: the user only.
- The never-downgrade trio always runs as top-tier Claude, under either lead.
- Approvals are recorded (audit, not prevention).
- Grok Build and Devin CLI become optional workers. Pi, oh-my-pi and Hermes are not workers.
- The Codex pin stays `gpt-6-astra` at `xhigh`.
- Integration branch `release/4.0`, plus the v3.3.3 hotfix first.
- Completion gate: `/goal` under a Claude lead; the sentinel under a Codex lead.
- Skipped on purpose: per-worker login isolation and sandbox-only safety builds.

## What Phase H shipped (for Phase 0 to build on)

- `scripts/lib/registry.sh`: `FRAMEWORK_PROTECTED` / `PROJECT_PROTECTED` and `_protected_classify` (KTD8). U21/U26 extend this file (ladder source, CLI registry).
- `scripts/lib/skills-sync.py` + `scripts/lib/skill-digests.txt`: the digest-stamped refresh (KTD12), used by `session-start.sh` and `_lease_provision_skills`. The table is frozen at the releases that wrote legacy stamps (v3.*); format-2 stamps carry their own digests.
- `scripts/lib/lease.sh`: `_lease_ctx`, `_lead_git`/`_lgr`/`_lgw`, `[baseline]` in the ledger, `_lead_integrity_check` (rc 44), `_lead_integration_check`, `lease_rebaseline` (audited), collect-time snapshot, snapshot-only `lease_merge` (KTD18/KTD19). U13 moves the process-group handling; U14 moves the trusted-config capture into `triforge_bootstrap`.
- `scripts/probe-capabilities.sh --self-only` (exit 3 on a SELF FAIL) and `.github/workflows/gates.yml`; new rows SELF-10 and SELF-18, SELF-08b rewritten (KTD15).

## Gotchas for the next session

- **Never edit the probe harness while a probe run is in progress** (`pgrep -f probe-capabilities`).
- The SELF gate takes about 60 s; SELF-18 alone runs ~25 fixture cases. Each SELF-10/SELF-18 case isolates its lease root and HOME; a run should leave nothing under `$TMPDIR/triforge-leases`.
- `lease_merge`'s commit no longer runs repository hooks and is never GPG-signed; a lead commit on the integration branch between merges, a switched checkout, or a manual promotion needs `lease_rebaseline` before the next lease call (see the wave-orchestration skill, "Integrity escalations (rc 44)").
- **Headless `claude -p` sessions exit when the model ends its turn to wait on a background job,** killing the job.
- **Git worktrees don't carry gitignored `.claude/settings.local.json`.** Copy it in for compound-engineering and plugin-dev to load there.
- **Auth and quota:** Devin CLI 3000.11.3 is installed but not logged in, and Kimi returns 403 (AUTH-FAIL).
- **Squash-merge PRs:** `gh pr merge <n> --squash --delete-branch`. With a worktree still open, remove the worktree first, then delete the branch.
- **SELF fixtures that tamper with the ledger must wait for lease_dispatch's `state=building` row** (that write recreates the ledger anchors); the CI runner is faster than a local run and the `ledger-gone` case failed only there. The gate prints each FAIL row's evidence to stderr and fails when an expected SELF row is missing (`SELF_EXPECTED` in probe-capabilities.sh — add new rows there).
- **Inside the single-quoted `_LEAD_INTEGRITY_PY` block in lease.sh no apostrophe may appear** (a comment saying "checkout's" broke the whole library once).
