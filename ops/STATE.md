---
saved: 2026-09-28T18:41:09Z
phase: 0
wave: 0
tasks:
  total: 29
  done: 0
  blocked: 0
verification_baseline:
  command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json"
  result: "validate-versions: PASS — plugin 3.3.2, ladder 24a7ee2039c8c2e4907472e4cf82fdfd, 19 agents / 12 skills / 17 commands. validate-skills: 12 skills OK. Both manifests pass --strict."
  commit: 7352e99
verification_command: "bash scripts/validate-versions.sh; bash scripts/validate-skills.sh; claude plugin validate --strict .claude-plugin/plugin.json; claude plugin validate --strict .claude-plugin/marketplace.json"
state_head: 7352e99
---
# Session state
<!-- Saved: 2026-09-28T18:41:09Z -->
<!-- Type: handoff before build — lead-choice (v4.0) plan written and reviewed; nothing built yet -->

## Current phase

Planning is complete; building has not started. The next step is Phase H of the plan: the v3.3.3 safety hotfix, as one PR to `main`.

## Active sprint

Let the user choose Claude Code or Codex as Triforge's lead, with every other CLI (Claude included) as a worker, while rebuilding instructions and skills to current best practice. Plan: `docs/plans/2026-09-28-1946-feat-lead-choice-v4-plan.md` (29 units, 7 phases, R1–R50, KTD1–KTD22). The plan is the authority; read its Goal Capsule first, and scan headings rather than reading it whole.

## Next actions

1. Run `ce-work` on **Phase H only**: U28 (SELF-row gate and PR workflow), U1 (protected-path lists), U2 (digest-stamped skill refresh), U27 (lead git hardening, integrity, snapshot-only merge). One PR to `main`, released as v3.3.3.
2. The user cross-reviews and merges every PR; each one touches protected paths. Only the user approves promotion to `main`. No autonomous `/lfg`.
3. After 3.3.3 ships: create `release/4.0` from `main`, then land Phases 0–6 PR by PR on it (KTD13), and merge to `main` once as v4.0.0.

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
- Commands and agents become skills per the Agent Skills spec plus compound-engineering conventions.
- Skills carry the `at-` prefix (`/at-build` in Claude Code, `$at-build` in Codex).
- Context audit first (PR 0), and must-hold rules are enforced by scripts, not prose.
- Protected-path cross-review: the lead or the user. Promotion to `main`: the user only.
- The never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) always runs as top-tier Claude, under either lead.
- Approvals are recorded (audit, not prevention).
- Grok Build and Devin CLI become optional workers. Pi, oh-my-pi and Hermes are not workers.
- The Codex pin stays `gpt-6-astra` at `xhigh`.
- Integration branch `release/4.0`, plus the v3.3.3 hotfix first.
- Completion gate: `/goal` under a Claude lead; the sentinel under a Codex lead.
- **Skipped on purpose:** per-worker login isolation and sandbox-only safety builds. Non-Codex workers run as the user with no OS sandbox. The plan discloses this; it is deliberately not tracked as a follow-up.

## What happened this session (2026-09-27 → 09-28)

- **Watch cycle** (PR #10, merged):
  - `/cli-watch` wrote report `ops/research/2026-09-27-cli-updates.md`, ADR `ops/decisions/2026-09-27-cli-deprecation-watch.md` (D-037–D-053) and a new `ops/research/2026-09-probe-record.md`.
  - `/repo-watch` wrote `ops/research/2026-09-27-repo-mining.md` (36 recommendations and a 26-check skill list).
  - A fact sheet covers Grok, Devin, Pi and Hermes: `ops/research/2026-09-27-factsheet-grok-devin-pi-hermes.md`.
  - The requirements brief is `docs/brainstorms/2026-09-27-lead-choice-requirements.md`. The plan supersedes it where they differ; for example, its R5 "required Claude reviewer" is superseded.
- **Watch registry:**
  - Now 9 `[cli.*]` entries: 6 CLIs plus firecrawl, chrome-devtools and gh as `tier = "tooling"`, which aren't probed.
  - Now 7 `[repo.*]` entries.
  - The watch-cycle skill routes GitHub content to gh or raw, docs pages to firecrawl, and pages firecrawl can't render to chrome-devtools (lead only).
- **v3.3.2 hotfix** (PR #11, merged, released): quoted `${CLAUDE_PLUGIN_ROOT}` in hooks, CC-06 validates both manifests, a fail-closed OpenCode V2 guard plus the `resolve_role` skip, Cursor Grok 4.7 ids through `_CURSOR_ID_PY`, and no `$N` in `commands/setup.md`.
- **Plan:** written with `ce-plan`, deepened by architecture, units and security reviews, then document-reviewed by five in-process personas plus a Codex cross-model pass. 25 fixes were applied. The review record is in the session scratch (not kept).
- **Tools:**
  - `plugin-dev` is installed at local scope (`.claude/settings.local.json`).
  - chrome-devtools-mcp was updated to 1.10.1 (`evaluate_script` now needs `--pageId`; run `chrome-devtools start --headless --isolated` if the profile is locked).
  - firecrawl was updated to 1.24.6.

## Gotchas for the next session

- **Live gap on `main` until 3.3.3 ships:**
  - `lease_promote`'s protected list misses `scripts/lib/`, `scripts/lease-git-hooks/` and `scripts/probe-self-tests.sh`.
  - A shell-capable worker can plant git config in the shared `.git/config`, edit `ops/leases.toml`, or make its own commits.

  Phase H fixes these.
- **`scripts/probe-capabilities.sh --skip-live`** exits 0 on FAIL rows and overwrites this month's committed probe record. Use a scratch `--record` path until U28 adds `--self-only`.
- **Never edit the probe harness while a probe run is in progress** (`pgrep -f probe-capabilities`).
- **Headless `claude -p` sessions exit when the model ends its turn to wait on a background job,** killing the job. Keep long jobs in the foreground, or resume with `claude -p --resume <id>`.
- **Git worktrees don't carry gitignored `.claude/settings.local.json`.** Copy it in for compound-engineering and plugin-dev to load there.
- **Auth and quota:** Devin CLI 3000.11.3 is installed but not logged in, and Kimi returns 403 (AUTH-FAIL). Live rows for both stay PENDING-AUTH.
- **Only 8 of 17 commands exceed Codex's 4,000-byte command limit** (not 9).
- **Squash-merge PRs:** `gh pr merge <n> --squash --delete-branch`. With a worktree still open, remove the worktree first, then delete the branch.
