---
saved: 2026-10-06T18:10:00Z
phase: 2c fixing; 3 integrating
wave: 0
tasks:
  total: 29
  done: 22
  blocked: 0
verification_baseline:
  command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json; bash scripts/probe-capabilities.sh --self-only"
  result: "All PASS on release/4.0 5ac2e54 (Phase 2b merged): validate-versions PASS (19 agents / 27 skills, AGENTS.md 16,364 bytes); validate-skills 27 OK, --self-test 32 OK; both manifests --strict; SELF gate 25 rows none FAIL, normal and CI-style (~6 min each under load); gates.yml green on PR #18 (run 37507263842)."
  commit: 5ac2e54
verification_command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json; bash scripts/probe-capabilities.sh --self-only"
state_head: 5ac2e54
---
# Session state
<!-- Saved: 2026-10-06T18:10:00Z -->
<!-- Type: program handoff — Phase H released as v3.3.3; Phases 0–6 running autonomously on release/4.0 -->

## Current phase

**Phase 2b is merged** into `release/4.0` (PR #18 → 5ac2e54, 2026-10-06): the `[lead]` table and host gate (U9), ledger approvals (U10), the `claude -p` lane with its 2.1.285 sandbox floor (U12), plus a simplify pass. Final-diff review 5/5 MERGE on the re-review; Codex gpt-6-astra xhigh FIX, all four fixed. `AGENTS.md` is at 16,364 of 16,384 bytes, so trim before adding.

**Phase 2c is fixing** on `feat/v4-phase-2c` (worktree `/Users/dbenger/projects/mafw-wt-phase-2c`, head a042a23, built on the pre-squash 2b head 2e9e57a; rebase with `git rebase --onto origin/release/4.0 2e9e57a`). Reviews: Codex FIX (3 P1, 3 P2) and final-diff 3/5 FIX on ab77a46. The fix batch is `scratchpad/fix2c/batch.md` (session scratchpad): u8's skill/docs half is in as a042a23; u25's persona-lane half (L1–L9, in `/Users/dbenger/projects/mafw-wt-2c-u25` on a77b9ea) is building. Residuals: `scratchpad/phase2c-residuals.md`.

**Phase 3 is integrating** on `feat/v4-phase-3` (worktree `/Users/dbenger/projects/mafw-wt-phase-3`, on 96fb70f): the bootstrap half (triforge_bootstrap, SELF-21) is in as d965a3c; the coordinator half (coordinate.sh lead split, monitors, SELF-22, CDX-21/22/23) waits in `/Users/dbenger/projects/mafw-wt-3-coord` for one follow-up (pass the `[lead]` model and effort through registry flag fields). Add `ops/decisions/2026-10-05-gitconfig-capture-at-first-lease.md` (draft in `scratchpad/phase3/`) with it. Residuals: `scratchpad/phase3/residuals.md`.

## Authorization in force (2026-10-01)

The user, before sleeping: "review the PR and if it passes fully 5/5, then merge … I'm going to sleep so you are in full charge. Make sure everything is running smoothly and that everything is delivered (all phases, continue running all the phases that are left after this one)." This supersedes, for this program only, the plan's "no autonomous /lfg" and "only the user merges" lines. Standing rules that still hold: each PR gets a real review (independent Opus 5.5 reviewers on the final diff + `gates.yml` green) and merges only on 5/5 (correctness vs the unit specs; gates + negative controls; guards not weakened; docs/release consistency; bash 3.2 + zsh + upgrade compatibility). The plan's stop conditions hold: a settled decision that can't work, a probe row a unit depends on failing with no designed fallback, or a change that would weaken a protected-path/push/approval/git-integrity guard → record the blocker here and in the PR, continue with independent work, leave the decision for the user. Never write user-tier config, never run CLI logins, never launch `danger-full-access` (R50). Memory: `autonomy_grant_2026_09_30.md`.

**Review flow from Phase 2b on (user, 2026-10-04):** no PR babysitting. Each phase PR is reviewed by an independent final-diff reviewer plus Codex CLI on `gpt-6-astra` at `xhigh` (read-only), findings fixed and verified, one check that `gates.yml` is green, then the squash-merge. The per-phase ce-code-review is skipped; a full review plus ce-code-review over the whole `release/4.0` diff runs once at the end, before the release PR to `main`. Every phase is still built through `/ce-work`.

**All work runs through `/ce-work` (user, 2026-10-06):** every phase, review-fix batch, simplify pass and the final release run inside a `/ce-work` invocation scoped to that work, following its references (triage, workspace, engine, execution strategy, implementation loop, shipping workflow) as read, never from memory. After a context compaction, re-invoke `/ce-work` for the current scope before continuing; a run started before the compaction does not carry over. Phase 2b had no `/ce-work` run of its own (its units ran under the run that finished 2a); don't repeat that.

## Program plan (PR by PR on release/4.0; each built with ce-work on Fable 5.1 @ high, reviewed on Opus 5.5 @ high)

| PR | Units | Status |
|---|---|---|
| 0 | U21 validator prep + ladder source; U3 AGENTS.md + rule inventory; U22 session-start floor/stale-template; U4 removal test + pruning | **merged** — PR #13 squash b647f3b on release/4.0 (2026-10-03); review run 20261001-225426-98b630ed + final cross-review PASS |
| 1a | U5 plugin-root resolver + locator; U26 CLI registry; U6 skill conformance validator | **merged** — PR #14 squash be6962a |
| 1b | U7 commands → at- skills; U24 split oversized skills; U23 remove commands/ | **merged** — PR #15 squash 3e99675 |
| 2a | U29 capability/survival probe rows; U13 detached leases + lease_wait + lead exit; U11 worker marker (+ U18 manifests, docs copy pass) | **merged** — PR #16 squash 4d4b054; ce-code-review run 20261004-175229-90f65ad6, final-diff review 5/5, Codex gpt-6-astra xhigh FIX → all applied |
| 2b | U9 [lead] table + resolution; U12 claude -p lane; U10 ledger lead CLI / reviewer class / approvals | **merged** — PR #18 squash 5ac2e54; final-diff re-review 5/5, Codex gpt-6-astra xhigh FIX → all applied |
| 2c | U25 dispatch_persona lane; U8 personas home, agents/ removed | **fixing** — review fixes from Codex FIX + final-diff 3/5; u8 half in, u25 half building |
| 3 | U14 Codex lead: bootstrap, monitors, coordinator | **integrating** — bootstrap half d965a3c; coordinator half in one follow-up |
| 4 | U16 Grok Build adapter; U17 Devin CLI adapter (U18 shipped in 2a) | pending |
| 5 | U15 at-setup lead step + instruction-file detection | pending |
| 6 | U19 watch-cycle carry-ins; U20 two-lead fixture sprint + 4.0 release | pending |
| final | release/4.0 → main as v4.0.0 (release.yml publishes) | pending |

Update this table and the frontmatter at every PR boundary; the plan is `docs/plans/2026-09-28-1946-feat-lead-choice-v4-plan.md`.

## Next actions

1. Phase 2c: collect u25's L1–L9, commit it in its worktree and cherry-pick onto `feat/v4-phase-2c`; rebase onto `release/4.0` (`--onto origin/release/4.0 2e9e57a`); full gate both ways plus `--only CC-21,CC-22,CC-23,CDX-20`; a re-review by final2c and Codex of the fixes; ce-simplify-code; PR → `release/4.0` (ce-commit-push-pr, branding:on, babysit:off); one gates check; squash-merge; remove the `mafw-wt-2c-*` worktrees.
2. Phase 3: collect u14-coord's model/effort follow-up; commit it and cherry-pick onto `feat/v4-phase-3` (one conflict: `SELF_EXPECTED` needs both SELF-21 and SELF-22); add the gitconfig-capture ADR; rebase onto `release/4.0` after 2c (expect probe-self-tests.sh conflicts with 2b's simplify helpers: `_SELF_PTY`, `_self_repo`, `_self_wait_rc`); gate; final-diff review + Codex; simplify; PR; merge.
3. Phases 4–6 per the table, each started with `/ce-work`. U15 (Phase 5) inherits: hook-trust detection by `hooks.state` trusted_hash, the live `$at-ship` vs `$agent-triforge:at-ship` check (needs a human-logged-in CODEX_HOME), the interactive launch line apart from the headless `launch_argv`, user-tier auth not reaching claude workers, agy builders needing a user-tier allow rule.
4. End of program: full review + ce-code-review over `release/4.0` vs `main`, then the release PR (only the user approves the merge to `main`).

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
- The SELF gate takes about 6 min under load (SELF-19 and SELF-13 are the long rows); SELF-18 alone runs ~25 fixture cases. Each SELF-10/SELF-18 case isolates its lease root and HOME; a run should leave nothing under `$TMPDIR/triforge-leases`.
- `lease_merge`'s commit no longer runs repository hooks and is never GPG-signed; a lead commit on the integration branch between merges, a switched checkout, or a manual promotion needs `lease_rebaseline` before the next lease call (see the wave-orchestration skill, "Integrity escalations (rc 44)").
- **Headless `claude -p` sessions exit when the model ends its turn to wait on a background job,** killing the job.
- **Git worktrees don't carry gitignored `.claude/settings.local.json`.** Copy it in for compound-engineering and plugin-dev to load there.
- **Auth and quota:** the user logged the Devin CLI in on 2026-10-06 (3000.11.3; `devin auth status` reads it, never run `devin auth login`); Kimi returns 403 (AUTH-FAIL).
- **Phase 4 carry-in:** the claude lane's credential read-deny list (`_CLAUDE_CRED_PATHS`) covers `~/.devin` and `~/.config/devin` but not `~/.local/share/devin`, where the Devin CLI keeps `credentials.toml`. U17 adds it (with a CC-15-style read probe) and checks the other new CLIs' credential homes the same way.
- **Squash-merge PRs:** `gh pr merge <n> --squash --match-head-commit <full 40-char sha>` (a short sha is rejected). With a worktree still open, remove the worktree first, then delete the branch.
- **SELF fixtures that tamper with the ledger must wait for lease_dispatch's `state=building` row** (that write recreates the ledger anchors); the CI runner is faster than a local run and the `ledger-gone` case failed only there. The gate prints each FAIL row's evidence to stderr and fails when an expected SELF row is missing (`SELF_EXPECTED` in probe-capabilities.sh — add new rows there).
- **Inside the single-quoted `_LEAD_INTEGRITY_PY` block in lease.sh no apostrophe may appear** (a comment saying "checkout's" broke the whole library once).
- **The shell here is zsh:** an unquoted `$FILES` list does not word-split, so run multi-path `git add` / `git commit --` from a `/bin/bash` script with an array.
- **Since U9, lead-owned helpers refuse in a shell with no host markers and no TTY** unless `TRIFORGE_TEST_BUILDER` and `TRIFORGE_TEST_LEAD` are set (the SELF harness sets both). Gate a branch in CI style as well as normally.
