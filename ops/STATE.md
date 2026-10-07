---
saved: 2026-10-07T14:10:00Z
phase: 2c and 3 merged; 4 merging (no further per-phase review), then 5 and 6
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

**2026-10-06 night: the user is asleep; Claude is in charge** under the 2026-10-01 grant (merges to `release/4.0` included; nothing merges to `main`; the plan's stop conditions hold). A session cron (every 30 min, :13/:43) checks for stalled workers and nudges them. Every phase runs under its own `/ce-work` invocation (see below).

- **Phase 2b** merged (PR #18, 5ac2e54).
- **Phase 2c** (`feat/v4-phase-2c`, worktree `mafw-wt-phase-2c`, head 0eda3cd on e907e52): round-3 review fixes in progress. u25 (`mafw-wt-2c-u25`): persona_spawn/persona_wait/persona_stop (detached personas, budgeted waits: foreground persona calls exceed the leads' 600 s / 900 s tool limits), the @import attachment gap (CLAUDE_CODE_DISABLE_ATTACHMENTS), baseline-before-check, the worker-writable `ran` marker, the codex read fallback's credential reach, cleanup reaping, CC-24, the ref check vs the lead's own merges. u8 (`mafw-wt-2c-u8`): every persona-bearing skill block to spawn + wait, deep-research stale analyst report, learnings rc, at-debug scope, persona_snapshot_diff in at-review, SELF-23 (skill blocks under zsh/bash). Batch: session scratchpad `fix2c-r3/batch.md`. This is the third review round: if its review still says FIX, record a blocker for the user and stop the phase.
- **Phase 3** (`feat/v4-phase-3`, worktree `mafw-wt-phase-3`, head ee6f80e on 4117340): U14 built, two review-fix batches and the simplify pass committed. fix3-mention is replacing every Codex-facing `$at-<name>` with `$agent-triforge:at-<name>` (the user-approved scratch check on 2026-10-06 showed only the namespaced mention attaches a skill under `codex exec` 0.160.0). Then the re-review (final3 + Codex), PR, merge.
- **Phase 4** (`feat/v4-phase-4`, worktrees `mafw-wt-phase-4`, `mafw-wt-4-grok`, `mafw-wt-4-devin`, on 592688f): started 2026-10-06 in parallel. u16 builds the Grok adapter (U16), u17 the Devin adapter (U17) incl. `~/.local/share/devin` in the claude credential deny list.
- Residual lists per phase live in the session scratchpad (`phase2c-residuals.md`, `phase3/residuals.md`, `phase4/notes.md`); they go into each PR's "Unapplied review findings".

## Authorization in force (2026-10-01)

The user, before sleeping: "review the PR and if it passes fully 5/5, then merge … I'm going to sleep so you are in full charge. Make sure everything is running smoothly and that everything is delivered (all phases, continue running all the phases that are left after this one)." This supersedes, for this program only, the plan's "no autonomous /lfg" and "only the user merges" lines. Standing rules that still hold: each PR gets a real review (independent Opus 5.5 reviewers on the final diff + `gates.yml` green) and merges only on 5/5 (correctness vs the unit specs; gates + negative controls; guards not weakened; docs/release consistency; bash 3.2 + zsh + upgrade compatibility). The plan's stop conditions hold: a settled decision that can't work, a probe row a unit depends on failing with no designed fallback, or a change that would weaken a protected-path/push/approval/git-integrity guard → record the blocker here and in the PR, continue with independent work, leave the decision for the user. Never write user-tier config, never run CLI logins, never launch `danger-full-access` (R50). Memory: `autonomy_grant_2026_09_30.md`.

**Review flow from Phase 2b on (user, 2026-10-04):** no PR babysitting. Each phase PR is reviewed by an independent final-diff reviewer plus Codex CLI on `gpt-6-astra` at `xhigh` (read-only), findings fixed and verified, one check that `gates.yml` is green, then the squash-merge. The per-phase ce-code-review is skipped; a full review plus ce-code-review over the whole `release/4.0` diff runs once at the end, before the release PR to `main`. Every phase is still built through `/ce-work`.

**Review flow from now on (user, 2026-10-07): code review happens once, at the end.** "Let's make sure that we leave code-review for the final code-review, not at every step/phase." This replaces the paragraph above and the per-PR review and 5/5 rule in the authorization, for the rest of this program:
- Phase 4 (already through five review rounds) and Phases 5 and 6 get no per-phase review: no final-diff reviewer, no Codex review, no ce-code-review, no simplify-review pass.
- Each phase is built through `/ce-work` and verified by its own tests: a SELF case per behavior, the full `--self-only` under Python 3.14 and 3.12, validate-skills (+ `--self-test`), validate-versions, both manifests `--strict`, `/bin/bash -n`. Then the PR, one green `gates.yml` run, and the squash-merge.
- The one code review is the end-of-program review over `release/4.0` vs `main`: ce-code-review plus Codex CLI `gpt-6-astra` at `xhigh`, then one fix round, then the release PR (only the user approves the merge to `main`).

**All work runs through `/ce-work` (user, 2026-10-06):** every phase, review-fix batch, simplify pass and the final release run inside a `/ce-work` invocation scoped to that work, following its references (triage, workspace, engine, execution strategy, implementation loop, shipping workflow) as read, never from memory. After a context compaction, re-invoke `/ce-work` for the current scope before continuing; a run started before the compaction does not carry over. Phase 2b had no `/ce-work` run of its own (its units ran under the run that finished 2a); don't repeat that.

## Program plan (PR by PR on release/4.0; each built with ce-work on Fable 5.1 @ high, reviewed on Opus 5.5 @ high)

| PR | Units | Status |
|---|---|---|
| 0 | U21 validator prep + ladder source; U3 AGENTS.md + rule inventory; U22 session-start floor/stale-template; U4 removal test + pruning | **merged** — PR #13 squash b647f3b on release/4.0 (2026-10-03); review run 20261001-225426-98b630ed + final cross-review PASS |
| 1a | U5 plugin-root resolver + locator; U26 CLI registry; U6 skill conformance validator | **merged** — PR #14 squash be6962a |
| 1b | U7 commands → at- skills; U24 split oversized skills; U23 remove commands/ | **merged** — PR #15 squash 3e99675 |
| 2a | U29 capability/survival probe rows; U13 detached leases + lease_wait + lead exit; U11 worker marker (+ U18 manifests, docs copy pass) | **merged** — PR #16 squash 4d4b054; ce-code-review run 20261004-175229-90f65ad6, final-diff review 5/5, Codex gpt-6-astra xhigh FIX → all applied |
| 2b | U9 [lead] table + resolution; U12 claude -p lane; U10 ledger lead CLI / reviewer class / approvals | **merged** — PR #18 squash 5ac2e54; final-diff re-review 5/5, Codex gpt-6-astra xhigh FIX → all applied |
| 2c | U25 dispatch_persona lane; U8 personas home, agents/ removed | **merged**: PR #19, squash 84d3d37 (2026-10-07). Rounds 1–4 reviewed; round 5 fixed and verified under the user's "fix all, verify, merge" decision; gates green on Python 3.14 and 3.12 and in CI |
| 3 | U14 Codex lead: bootstrap, monitors, coordinator | **merged**: PR #20, squash dd0bb14 (2026-10-07). Rounds 1–4 reviewed; round 5 fixed and verified under the user's "fix all, verify, merge" decision; the first CI run exposed a ledger-write race (SELF-18), fixed in 676af5b; gates green on Python 3.14 and 3.12 and in CI |
| 4 | U16 Grok Build adapter; U17 Devin CLI adapter (U18 shipped in 2a) | **stopped at the review cap** — round 3: Codex FIX (2 P1), final-diff 5/5 MERGE (see Blockers) |
| 5 | U15 at-setup lead step + instruction-file detection | pending |
| 6 | U19 watch-cycle carry-ins; U20 two-lead fixture sprint + 4.0 release | pending |
| final | release/4.0 → main as v4.0.0 (release.yml publishes) | pending |

Update this table and the frontmatter at every PR boundary; the plan is `docs/plans/2026-09-28-1946-feat-lead-choice-v4-plan.md`.

## Next actions

1. Phase 2c: collect u25's L1–L9, commit it in its worktree and cherry-pick onto `feat/v4-phase-2c`; rebase onto `release/4.0` (`--onto origin/release/4.0 2e9e57a`); full gate both ways plus `--only CC-21,CC-22,CC-23,CDX-20`; a re-review by final2c and Codex of the fixes; ce-simplify-code; PR → `release/4.0` (ce-commit-push-pr, branding:on, babysit:off); one gates check; squash-merge; remove the `mafw-wt-2c-*` worktrees.
2. Phase 3: collect u14-coord's model/effort follow-up; commit it and cherry-pick onto `feat/v4-phase-3` (one conflict: `SELF_EXPECTED` needs both SELF-21 and SELF-22); add the gitconfig-capture ADR; rebase onto `release/4.0` after 2c (expect probe-self-tests.sh conflicts with 2b's simplify helpers: `_SELF_PTY`, `_self_repo`, `_self_wait_rc`); gate; final-diff review + Codex; simplify; PR; merge.
3. Phases 4–6 per the table, each started with `/ce-work`. U15 (Phase 5) inherits: hook-trust detection by `hooks.state` trusted_hash, the live `$at-ship` vs `$agent-triforge:at-ship` check (needs a human-logged-in CODEX_HOME), the interactive launch line apart from the headless `launch_argv`, user-tier auth not reaching claude workers, agy builders needing a user-tier allow rule. **Devin (user, 2026-10-07):** the user chooses the Devin model. `swe-1-6-slow` stays the shipped default because it works on every account, Devin Free included. When Devin is enrolled, at-setup offers the models `devin models list` prints and writes the choice into the roster's `model` field for Devin's roles. at-setup also tells the user that Devin plugins they or their org installed load in every Devin run, read class included, and prints `devin plugins list` (fix5d). The consent and opt-in writers from U17 already exist (`roster_write_member --consent user --opt-in`).
4. End of program: full review + ce-code-review over `release/4.0` vs `main`, then the release PR (only the user approves the merge to `main`).

## Blockers recorded for the user

**2026-10-07 ~03:00: Phase 2c and Phase 3 stopped at the 3-review-round cap** (both third Codex gpt-6-astra xhigh reviews say FIX; gates green on both heads: 27 SELF rows, none FAIL). Nothing from either phase is merged; both branches are intact (`feat/v4-phase-2c` 115b9b1, `feat/v4-phase-3` 5b50bbc, both on release/4.0 fa612c9). Full reviews: session scratchpad `codex-2c-r3/review.md`, `codex-3-r3/review.md`; the final-diff reviewers' third-round verdicts are added below when they report. Your call: approve a fourth fix round (recommended scope below), or accept some findings as documented residuals.

Lead's triage and recommendation:
- **Functional bugs, fix regardless (2c):** at-review's dispatch block launches the two core reviewers twice (dispatch.md:151 repeats :80–89; only the second pair is awaited, the first can overwrite reports); a default review with no persona to wait on fails, because `persona_wait` returns 64 on an empty run dir (dispatch.md:234) — plain `/at-review` breaks. SELF-23 missed both (its stub accepts an empty run dir and it doesn't count launches).
- **Policy-relevant, recommend fixing:** (3) the HOME refusal is bypassable by path casing on macOS (`pwd -P` vs `env pwd -P`; compare filesystem identity) → user-tier writes possible; (3) deleting `ops/leases.toml` and restarting under another TMPDIR passes the coordinator's integrity check (no session should start when the anchors elsewhere can't be checked); (3) headless enrollment writes through a symlinked `ops/` and its temp file is a plain open (predates 3, reachable through the hook); (3) a roster model value can put a `{`-leading line on hook stdout via `printf '%b'`; (2c) a moved integration branch / switched HEAD before dispatch supplies the "trusted" instruction bundle (validate the recorded integration SHA first).
- **Same-user race hardening, could be documented instead:** skills-sync parent swap after validation; the `.codex/agents` migration `mv` racing a symlink swap; non-sticky shared TMPDIR races in the hook's and coordinator's temp dirs; a FIFO planted at a monitor state path blocking the hook; persona cleanup leaving descendants of a successful run, and `persona_stop` on an orphaned run returning 0. AGENTS.md "Confinement, stated as it is" already says a worker with a shell can write anything the user can and Triforge detects rather than prevents; these extend that.
- Phase 4 (Grok, Devin) continues independently; Phases 5–6 wait on 3 and 4.

**2026-10-07 ~08:55: Phase 4 stopped at the 3-review-round cap too.** Branch `feat/v4-phase-4` at 6ec6839 (on 592688f, 14 commits). Its worktree is `mafw-wt-phase-4`, nothing is merged, and the gate is green (29 SELF rows, none FAIL). Round 1 was Codex FIX (3 P1, 5 P2) and final4 3/5. Round 2 was Codex FIX (3 P1, 5 P2) and final4b 4/5. Every round-1 and round-2 finding was fixed, with SELF cases that go red when the fix is removed (final4c: 17 of 19 mutations). Round 3 split, the same way Phase 3 did: final4c **5/5 MERGE**, Codex **FIX**. Reports are in the session scratchpad: `codex-4-r3/review.md`, `final4-r3.md`, and `phase4/notes.md`, which also holds the residuals.
- **Codex round-3 P1s.**
  - at-review's new review-package diff (`optional-lanes.md:40`, `_lgr diff`) runs before any integrity check, so a clean filter planted in `.git/config` runs in the lead's shell. final4c rates this P3, because the learnings gate's plain `git diff` already runs the same exposure. Its fix: one `_lead_integrity_check at-review` at the top of at-review.
  - A grok reviewer still runs user-tier startup code from `~/.grok/config.toml` (hooks, LSP, MCP), which a grok builder's sandbox can write. This is the round-1 P3-4 residual, raised to P1. The fix would refuse or suppress user-tier hooks, LSP and MCP for the read class.
- **Codex round-3 P2s.**
  - The 200 KB diff cap drops whole files, with no file inventory.
  - An optional CLI in a core role (`dispatch.md`) gets no diff. final4c P3-3 found the same.
  - `_promote_ok` scans Codex's whole transcript, so a quoted `Status: BLOCKED` suppresses a good review.
  - Devin's retry skips the consent, role and guard re-check.
- **P3s.**
  - A wrong `REVIEW_BASE` silently reviews another scope.
  - Devin retries an interrupted run.
  - No SELF row gates at-review's promotion rule or the scratch traps; the harnesses exist (final4c).
  - The diff can exceed Linux's 128 KiB argument limit.
  - R25's per-CLI case arms.
- **2026-10-07 ~09:30: the user approved the fourth round** ("continue with your recommendation"). It runs under `/ce-work` with four workers: r4-2c (`mafw-wt-phase-2c`), r4-3 (`mafw-wt-phase-3`), r4-4a (at-review side, `mafw-wt-6-fixa`) and r4-4b (grok/devin side, `mafw-wt-6-fixb`). The batches are in the session scratchpad under `round4/`. Next: round-4 reviews, then merges in the order 2c → 3 → 4.
- **2026-10-07 ~12:45: round 4 results.**

  | Phase | Independent reviewer | Codex |
  |---|---|---|
  | 2c | 3/5 FIX: the supervisor's `os.waitid` is missing on macOS Python ≤3.12, which CI pins | FIX: 1 P1, 4 P2 |
  | 3 | final3d 5/5 MERGE | FIX: 1 P1, 3 P2 |
  | 4 | final4d 5/5 MERGE | FIX: 1 P1, 1 P2 |

  Gates are green on 3 and 4 under Python 3.12 and 3.14.
- **The user then decided (AskUserQuestion: "Fix all, verify, merge").** Fix every round-4 finding in all three phases. Prove each fix with a SELF case that fails on the old head and passes on the new one. Gate under Python 3.12 and 3.14, then run gates.yml, then merge 2c → 3 → 4. There is no further external review round per phase. Codex reviews everything once, in the end-of-program review.
- **User decision (2026-10-07):** v4.0.0 ships without a fresh full live probe run. The user skipped that release step and marked it complete: Grok's rows would read QUOTA-FAIL (xAI quota) and Kimi's AUTH-FAIL (403). The release notes cite the newest existing record. They name the live rows that ran during 4.0 development under `--only` (DVN-01..07, CC-21..25, CDX-20..23, GRK-02/03/04/06/12, and GRK-05/07..11 plus SELF-06g before the quota ran out) as development evidence. They do not present any of it as a regenerated record.
- **Gotcha (2c round 4):** the local gate must also run under Python 3.12. gates.yml pins 3.12, and this host's `python3` is 3.14. Put a dir whose `python3` is uv's cpython-3.12.12 first in PATH.
- **Lead's recommendation:** a fourth round, scoped to the items above. Each is local: at-review's integrity check, review package and core-lane prompt; the grok read class's user-tier surfaces; Devin's retry. The live grok rows still wait on the xAI quota.
- **Third-round final-diff verdicts (added 03:20):** final2c **4/5 FIX** at 115b9b1 — the one blocking finding is the duplicate core-lane dispatch (dispatch.md:72-90 and :143-160, the same as Codex's 2c #4); every earlier finding fixed; P3: rerunning a synthesis start block while a synthesizer runs orphans it. final3 **5/5 MERGE** at 5b50bbc — all eight Codex round-2 findings and its four P3s fixed; it did not have Codex's round-3 list, so the reviewers disagree on Phase 3 (Codex's round-3 P1s stand until checked). Reports: session scratchpad `final2c-r3.md`, `phase3/final3-r3.md`.

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
