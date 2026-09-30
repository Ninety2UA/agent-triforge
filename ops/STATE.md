---
saved: 2026-09-30T21:40:00Z
phase: H-built
wave: 0
tasks:
  total: 29
  done: 4
  blocked: 0
verification_baseline:
  command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json"
  result: "validate-versions: PASS — plugin 3.3.3, ladder 24a7ee2039c8c2e4907472e4cf82fdfd. validate-skills: 12 skills OK. Both manifests pass --strict. probe-capabilities.sh --self-only: 17 SELF rows, none FAIL."
  commit: e91e5bb
verification_command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json; bash scripts/probe-capabilities.sh --self-only"
state_head: b77338a
---
# Session state
<!-- Saved: 2026-09-30T21:40:00Z -->
<!-- Type: handoff after build — Phase H (v3.3.3) built, reviewed and fixed; PR #12 to main open, unmerged -->

## Current phase

Phase H is built on `fix/v3.3.3` and reviewed. One PR to `main` for v3.3.3 is open — https://github.com/Ninety2UA/agent-triforge/pull/12 (branch pushed 2026-09-30, base `main`) — and must NOT be merged by an agent: the user cross-reviews every protected-path diff and merges. Nothing from Phases 0–6 has started.

## Active sprint

Plan: `docs/plans/2026-09-28-1946-feat-lead-choice-v4-plan.md` (29 units, 7 phases). Phase H = U28, U1, U2, U27, all delivered on this branch (commits 0ca243e, 0ea29a0, fa8dfc6, 7ba19ed), followed by a simplify pass (708ea30), the ce-code-review fix waves (6e01170, ee43dd9, 06364ab, fcda556, 4541b58) and a plugin-dev pass (e91e5bb).

## Next actions

1. The user reviews and merges PR #12 (squash: `gh pr merge 12 --squash --delete-branch`). `gates.yml` runs for the first time on it; a red run is a finding against the PR. The release workflow tags v3.3.3 and publishes the GitHub release from the README ledger; confirm with `gh release view v3.3.3`.
2. After 3.3.3 is on `main`: create `release/4.0` from `main`, then land Phases 0–6 PR by PR on it (KTD13), merging to `main` once as v4.0.0. Phase 0 starts with U21 (validator prep and ladder source), then U3.
3. Follow-ups recorded in the PR body (not blocking 3.3.3): the plugin-level `settings.json` `env` block may be dropped by current Claude Code (confirm live); `tool-failure-monitor.sh` should also register on `PostToolUseFailure`; leases open across the 3.3.2→3.3.3 upgrade are snapshotted at merge time; the probe record was not regenerated for this hotfix.

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
