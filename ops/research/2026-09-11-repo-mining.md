# External-repo mining — adopt/defer recommendations for Agent Triforge

**Window:** 2026-07-18 → 2026-09-11 (second `/repo-watch` cycle)
**Repos:** the four `[repo.*]` entries in `ops/watch-registry.toml` — `addyosmani/agent-skills` (0.6.5 → 0.6.9, 125 commits), `EveryInc/compound-engineering-plugin` (v3.20.0 → v3.24.0 + 20 unreleased, 315 commits), `obra/superpowers` (v6.2.0 → v6.3.0 + 2 dev commits, 53 commits on main), `open-gsd/gsd-core` (1.8.0 → 1.13.0 on `next`, 1,176 commits).
**Method:** `/repo-watch` — registry validated HTTPS/public-host (4/4 OK; all four live, pushed within the last week, none archived), one read-only mining worker per repo against **primary sources** (each repo's own files at raw.githubusercontent.com, GitHub API commits/releases/PRs, in-tree docs and ADRs; gsd via a shallow clone of `next`), lead-synthesized here with every **Concrete change** grounded in a real Triforge path. **Recommends only** — no source was changed; adoption is the follow-up sprint the user directed for this cycle (see §0).
**Sibling artifacts:** the same-day `/cli-watch` report `ops/research/2026-09-11-cli-updates.md` and ADR `ops/decisions/2026-09-11-cli-deprecation-watch.md` (D-020–D-036). Where a mining candidate is already adopted by that ADR it is cross-referenced rather than re-decided.

## 0. Executive summary

- **69 candidates** this cycle: **14 new from agent-skills** (AS-1…AS-12 + 2 informational), **10 new from compound-engineering** (CE-1…CE-10), **24 new from superpowers** (S1…S24), **14 new from gsd-core** (G1…G14), plus **status updates on all 27 July candidates** (C1–C18, D1–D9 — none implemented since July; 12 strengthened, 2 re-ranked, 1 superseded, rest unchanged).
- **Verdicts:** **36 ADOPT** (19 for this sprint — Tier 1, all text-level or small-script changes with a stated verification; 17 for the next sprint — Tier 2, script/protected-path work), **1 conditional**, **32 DEFER**. Full breakdown in §2.
- **Convergent themes (three or four repos independently):** (1) `.agents/skills/` is the cross-client skills path and copy-once staleness is the bug to fix (AS-1; adopted as D-029); (2) skill bodies must stay portable and small — six spec fields top-level, vendor fields under `metadata`, an 8 KB Codex cap and a 5 000-token Claude Code compaction cap keep only the *start* of a body (AS-2, CE-4); (3) dispatched builders must not spawn their own reviewers and must return a typed report (S5, S14, G7); (4) "unknown ≠ clean": probes, gates and hooks must return three-valued results (G7, G3, CE-3, S6); (5) approval binds to the stage presented and ceremony ratchets one way (S16, C3); (6) the knowledge bar is a counterfactual, not a duration (CE-1).
- **Lead grounding corrections:** (a) gsd's worker proposed replacing prose isolation with a PreToolUse guard hook (G2) — Triforge's builders are external CLIs dispatched into worktrees by the lead, so the guard applies only to the Claude `Agent`-tool builder lane; scoped accordingly. (b) superpowers' remote-safety PR (#2228) is mostly N/A: `lease_create` branches from HEAD with no upstream (`scripts/invoke-external.sh:2219`); only the "git stays local" sentence transfers (S13). (c) CE's 8 KB cap applies to **Agent-Plugin** skills on Codex ≥ 0.147 (`$schema`-routed); Triforge ships no Agent-Plugins manifest, so the cap bites only if one is added — but Claude Code's compaction cap is real, and `skills/wave-orchestration/SKILL.md` is 15 122 bytes (CE-4 re-ranked to Tier 2, measured).
- **Local drift surfaced while grounding** (not mining candidates; handed to the sprint): `antigravity-agents/plugin.json` 3.0.0 vs `.claude-plugin/plugin.json` 3.2.0; `templates/CLAUDE.md` says "13 skills" (shipped: 12); `lease_reclaim` force-removes worktrees (`invoke-external.sh:2592`); `commands/review.md` never spawns `learnings-researcher` (July C4 still open).

### Top 10 (highest value, lowest risk — do these first)

1. **CE-1** Durable-knowledge counterfactual gate (replaces the "30 minutes" heuristic in `skills/knowledge-compounding/SKILL.md`; standing directive in templates).
2. **S5 + S14 + S13** Builder dispatch contract: no sub-dispatch, four status codes + "Discoveries for later tasks", git stays local — one header in `lease_dispatch` + the four agent briefs.
3. **S10 + C9** `verification-before-completion` rewrite: Iron Law, gate function, evidence table, no-test-command evidence.
4. **S1** Rulings, not stalls (+ "Rulings I made" at `/wrap`) — unattended `/ship` runs stop parking.
5. **AS-2 + C10 + C2** Portable frontmatter (vendor fields under `metadata`), "Use when" descriptions, anti-rationalization tables across the 12 shipped skills (S17 method).
6. **AS-3 + C1 + AS-4 + AS-5** `scripts/validate-skills.sh` + `scripts/validate-versions.sh` + component-count guard, wired into the release checklist.
7. **S6 + S7** Reviewer rules (do not trust the report; rationale never downgrades severity; re-read, never re-run) and no pre-judging in review dispatches.
8. **S11 + S12** `writing-good-tests.md` falsifiability + characterization guard for refactors in `test-driven-development`.
9. **G6 + C8 + G11** Per-task `Accept:` / `Fails when:` / `Precondition:` / `Reversibility:` fields in `writing-plans` + plan-checker checks.
10. **CE-6** Scrub host-attestation env markers (`CLAUDECODE`, `CODEX_*`, `CURSOR_*`, …) in `_adapter_env` before every external dispatch.

## 1. Per-repo profiles

### 1.1 addyosmani/agent-skills — the skill-authoring standard (0.6.5 → 0.6.9)

Hardening-and-governance window, no format change. Tier-2 evals are CI-enforced with a rank-1 floor that only ratchets up (80 → 95); the validator grew workflow-step coverage, `references/` link and artifact-path checks, a version-lockstep check, and an `Object.hasOwn` exemption fix; a canonical **portable-frontmatter rule** landed 09-04 (six spec fields top-level, vendor fields under `metadata`, `disallowed-tools` is Claude-only and fails packaging); `constraint-driven-development` shipped a reference **floor guard** (tightening is silent, loosening is loud); an append-only rejected-change ledger; Codex install is two commands (marketplace add + plugin add); Antigravity install path corrected to `~/.gemini/config/plugins/`; SessionStart hook moved to the standard `hookSpecificOutput` envelope. The worker verified all six of Triforge's CLIs scan `.agents/skills/` against each CLI's own docs (matching the lead's fixture test in the cli-watch report §3.1, with the Claude Code exception).

### 1.2 EveryInc/compound-engineering-plugin — the compounding-knowledge loop (v3.20.0 → v3.24.0)

Now a **self-contained skills package**: 35 skills, zero agents/commands/hooks, 14 hosts each installed through the host's own manifest (`.claude-plugin`, `.codex-plugin`, `.cursor-plugin`, `.kimi-plugin`, `.devin-plugin`, `.grok-plugin`, `.omp-plugin`, `.agy/`, `.opencode/plugins`, `.pi/extensions`, `.cline/scripts`) — "when a platform has a manifest and marketplace contract, ship a manifest, not a converter target". Window highlights: the **durable-knowledge counterfactual bar** (09-02, applied to CE's own store 09-03), corpus-first frontmatter vocabulary (08-15), compound-refresh rewritten around falsifiable gates with a worth lens and "unverifiable is not false" (08-01/25), an **8 KB sweep** turning ~20 skills into phase-loaded kernels after measuring Codex's `MAX_SKILL_PROMPT_BYTES` and Claude Code compaction truncation (08-18/21), the Agent-Plugins `$schema` dropped permanently because two hosts route on it (08-17), a host-CLI skill-eval cell (08-19), requested-vs-verified model receipts, host-marker env scrubbing, `ce-bakeoff` / `ce-noslop` (09-08), Compound Packs (09-09, experimental).

### 1.3 obra/superpowers — reliability through skill discipline (v6.2.0 → v6.3.0)

`main`'s last commit is 2026-08-12; September activity is PR branches plus two `dev` commits. v6.2.0 restructured the SDD fix loop (resume implementer rounds 1–3, fresh implementer on a stronger model rounds 4–5, scoped re-review, five-round breaker with controller adjudication), compressed the library into `Excuse | Reality` rows (and measured that *deleting* TDD's "Why Order Matters" dropped test-first compliance 8/10 → 5/10), replaced testing-anti-patterns with `writing-good-tests.md`, and fixed `find-polluter.sh` (the July-era script was broken). v6.3.0 added rulings-not-stalls, the evidence-bearing preflight table, same-shape task batching, **no worker-spawned subagents** (9/9 depth-2 spawns were duplicate reviews), `Spec:` pointers, reviewers re-read illegible evidence, Codex spawn hygiene, and never-`--force` worktree removal. Cross-harness: one skill body + a bootstrap injected at session start (three hook shapes) + a per-harness tool mapping; no `.agents/skills/` symlinks in-tree; every SKILL.md uses only `name` + `description`.

### 1.4 open-gsd/gsd-core — the closest architectural analog (1.8.0 → 1.13.0)

The largest delta: per-host **`capability.json` descriptors** with `engines.gsd` semver gates, artifact layouts + converters per host, nine negotiated axes (`dispatch.isolation`, `maxConcurrency`, `effortSurface`, …) with an `undocumented` sentinel that **fails closed**; isolation sentinel + PreToolUse dispatch guard ("a guard that cannot verify must not answer safe"); merge-time **scope conformance** + declared-deletions guard; quick-batch wave-order merges with crash-window reconciliation; `<fails_when>`, `<precondition>`, `<reversibility>` task elements; an **exit-code registry** and hook `ON_CRASH` policy after a 30-bug systemic review ("absence, emptiness and failure all encode as success"); reviewer provenance (`models:`/`model_sources:`) and dropped-lane semantics; `state.json` machine contract; Review Dispositions Ledger; rate-limit escalation in the fallback chain; Codex per-agent model omitted by default ("passive posture"). Kimi-code split into a skills-only install with built-in-only dispatch (`coder|explore|plan`) plus persona injection.

## 2. Prioritized adoption candidates

Verdict vocabulary: **ADOPT (T1)** = this sprint; **ADOPT (T2)** = next sprint (script/protected-path work or needs a probe); **DEFER** = revisit on trigger. Cross-references to the cli-watch ADR use its D-numbers.

### Tier 1 — ADOPT this sprint (text-level or small-script; each with a stated verification)

#### CE-1 — Durable-knowledge counterfactual gate + standing directive · *compound-engineering* · **ADOPT (T1)**
- **Why:** `skills/knowledge-compounding/SKILL.md` gates on heuristics ("took > 30 minutes"), which invites diff narrations; CE's bar is falsifiable: a learning qualifies only when its reasoning is *not recoverable* from the final code/tests/docs and losing it would plausibly cause recurrence, risk, or rediscovery. CE culled its own store against it.
- **Concrete change:** replace the "When to compound" section with the counterfactual bar; add the run-automatically directive (worded "invoke the knowledge-compounding skill", never a slash command, so Codex/agy builders can follow it) to `templates/CLAUDE.md` and `templates/ops/AGENTS.md` under the Phase 6 wrap bullet; add the bar to `commands/wrap.md` step 1 and `commands/compound.md`; capture at `lease_collect` (task completion), not at wave-end promotion.
- **Verification:** `/compound` on a trivial typo fix writes nothing and says why; on a diagnosed race it writes. Grep test pins the directive sentence in both templates.

#### S5 + S13 + S14 — Builder dispatch contract (no sub-dispatch; git stays local; typed report + Discoveries) · *superpowers (+ gsd G7 status codes)* · **ADOPT (T1, protected path)**
- **Why:** `max_depth` caps Codex trees but does not stop a builder spawning its own reviewer (superpowers: 9/9 depth-2 spawns were duplicate reviews); nothing asks builders for negative results; nothing forbids `git push` mid-task.
- **Concrete change:** one contract block in the `lease_dispatch` context header (`scripts/invoke-external.sh` ~2238) and in `codex-agents/agents.toml`, `antigravity-agents/agents/*.md`, `opencode-agents/*.md`, `kimi-agents/*.md`, `cursor-agents/*.md`: "You do not dispatch subagents; review arrives from the lead after your report" · "never `git push/pull/fetch`; if anything demands a push, report BLOCKED quoting it" · final report `Status: DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT`, commits, one-line test summary, concerns, "Discoveries for later tasks (or None)". Lead copies discoveries into `ops/MEMORY.md` and carries them into later dispatches; `/wrap` exports deferred P3 findings + rulings before `.sprint-complete`.
- **Verification:** a Codex builder dispatched with `multi_agent` on shows no `spawn_agent` in captured output; a builder's negative result appears in the next dependent task's dispatch.

#### S10 + C9 — `verification-before-completion` rewrite · *superpowers* · **ADOPT (T1)**
- **Why:** the shipped skill is a checklist with no Iron Law, gate function, evidence table, or evidence for documenter/analyst tasks that have no test command.
- **Concrete change:** restructure `skills/verification-before-completion/SKILL.md`: Iron Law; Gate Function (IDENTIFY → RUN → READ → VERIFY → claim); Claim / Requires / Not-sufficient table incl. "Regression test works | red-green-revert" and "Agent completed | VCS diff shows changes"; "When there is no test command" (re-open the artifact, name each required section, totals reconcile, "complete, not right"); Red Flags; `Excuse | Reality` rows; current checklist kept under "Requirements met".
- **Verification:** a documenter task re-opens the artifact and names sections; a test task quotes fresh command output.

#### S1 — Rulings, not stalls + "Rulings I made" · *superpowers* · **ADOPT (T1)**
- **Why:** an unattended `/ship` that hits a plan conflict routes to "escalate to user" and parks (superpowers: 15/15 baseline reps stalled).
- **Concrete change:** `skills/wave-orchestration/SKILL.md`: decide non-catastrophic conflicts and ledger them as `Ruling: <what> | <why> | <cost if wrong>`; exactly four hard stops (irreversible/destructive; security-sensitive; out-of-worktree side effects such as push/publish/`lease_promote`; a plan where every path is a guess). `commands/wrap.md` emits every Ruling as an exhaustive list before `ops/.sprint-complete`.
- **Verification:** seeded-conflict `ops/TASKS.md`; the lead rules and continues; the wrap report lists the ruling.

#### AS-2 + C10 + C2 (+ S17 method) — Portable frontmatter, "Use when" descriptions, anti-rationalization rows · *agent-skills + superpowers* · **ADOPT (T1)**
- **Why:** all twelve `skills/*/SKILL.md` descriptions lead with "Primary consumer: … (Phase N)" prose that consumes the routing signal and none says "Use when"; the canonical portable rule (09-04) limits top-level keys to `name`, `description`, `license`, `compatibility`, `metadata` (+ experimental `allowed-tools`); only `test-driven-development` has an iron law and no skill has an `Excuse | Reality` table. superpowers measured that deleting arguments degrades behavior — they must survive as table rows.
- **Concrete change:** per skill: description → "Use when …" trigger (imperative, near-miss negatives), move consumer/phase into `metadata: {triforge-consumer, triforge-phase, version}`; add `## Common Rationalizations` (`Excuse | Reality`) and `## Red Flags` to the discipline skills (verification, TDD, debugging, wave, iterative-refinement, scope-cutting). Keep `.claude/skills/watch-cycle/` free to use Claude-only fields (never ships). Record the rule in `.claude/CLAUDE.md` "Portable skills".
- **Verification:** AS-3 linter passes all twelve; `claude plugin validate --strict .` green; a fixture with `model:` at top level fails the linter.

#### AS-3 + C1 + AS-4 + AS-5 — Validators + release-checklist guards · *agent-skills* · **ADOPT (T1)**
- **Why:** Triforge has zero validators; manifest versions already drift (3.0.0 vs 3.2.0); an explicit `agents` array in `plugin.json` once suppressed Claude Code auto-discovery (Agents 0 → 4 after removal).
- **Concrete change:** `scripts/validate-skills.sh` (name == dir, kebab, description ≤ 1024 with a non-negated "Use when", spec-only top-level keys, `## Step N:` coverage for declared numbered steps, size warning > 500 lines, no relative link escaping the skill dir); `scripts/validate-versions.sh` comparing `.claude-plugin/plugin.json`, `antigravity-agents/plugin.json`, and the newest README "What's new" heading; release checklist: both scripts + "plugin details show 19 agents / 12 skills / 17 commands".
- **Verification:** run now → versions check fails on 3.0.0; after the sprint both pass; a fixture skill with a declared step and no heading fails.

#### S6 + S7 — Reviewer rules; no pre-judging · *superpowers* · **ADOPT (T1)**
- **Why:** reviewers receive builder output and `ops/TEST_RESULTS.md` with no stance on trust (5/8 superpowers reps re-ran whole suites on "truncated" evidence); review dispatches can ship flaws via "do not flag X".
- **Concrete change:** `codex-agents/agents.toml` `logic_reviewer`, `agents/continuous-reviewer.md`, `commands/review.md`, `skills/iterative-refinement/SKILL.md`: treat the builder report as unverified claims; a stated rationale never lowers severity; re-read the file at its path when evidence looks truncated, report a gap, never re-run suites (tester role owns that); never instruct a reviewer to ignore a specific issue — adjudicate in `findings-synthesizer`; keep the "Suppressions" section category-level.
- **Verification:** a reviewer handed a truncated test report re-reads and reports a gap; grep review dispatch prompts for "do not flag" / "at most Minor" / "the plan chose".

#### S11 + S12 — `writing-good-tests.md` + characterization guard · *superpowers* · **ADOPT (T1)**
- **Why:** the TDD skill has no rule against mirror assertions, change detectors, or string-presence tests, and its RED step ("if it passes, rewrite it") dead-ends refactors of untested code (0/5 compliant → 5/5 with the guard).
- **Concrete change:** add `skills/test-driven-development/writing-good-tests.md` (Name the Break, Exercise the Real Thing, mutation check, warning signs) linked from `SKILL.md`; add a "behavior must not change" branch: name the mutation, see the test pass, mutate, see it fail, `git restore --source=HEAD --worktree -- <paths>` to an empty diff, then refactor green; red flag becomes "test for *new or changed* behavior passes immediately"; mirror the mutation check into `agents/test-gap-analyzer.md` and `test_writer`.
- **Verification:** `test_writer` asked to test a bash helper writes an execution test with exit-code assertions, not a grep of source; a refactor task runs the guard instead of refusing.

#### G6 + C8 + G11 — `Accept:` / `Fails when:` / `Precondition:` / `Reversibility:` task fields · *gsd-core* · **ADOPT (T1)**
- **Why:** July C8 (executable per-task verify) is still prose-only; gsd added the failing-direction sibling (placeholders `TBD/N/A/none/unknown/?` are blockers), read-only preconditions, and a one-way-door checkpoint.
- **Concrete change:** `skills/writing-plans/SKILL.md` task format gains `Accept:` (runnable), `Fails when:` (observable failure signal), optional `Precondition:` and `Reversibility: reversible|costly|one-way`; `agents/plan-checker.md` checks every command-shaped `Accept:` has a `Fails when:`, rejects placeholders, flags one-way tasks lacking a user checkpoint; `skills/wave-orchestration/SKILL.md` pauses on one-way tasks unless `--no-reversibility-gates`.
- **Verification:** plan-checker fixture with a placeholder → NEEDS_REVISION; `Reversibility: one-way` without a checkpoint → warning.

#### CE-6 — Scrub host-attestation env markers in `_adapter_env` · *compound-engineering* · **ADOPT (T1, protected path)**
- **Why:** a peer CLI launched from Claude Code inherits `CLAUDECODE=1` and attests itself as running under Claude Code; CE scrubs `CLAUDECODE`, `CODEX_SANDBOX*`, `CODEX_SESSION_ID`, `CODEX_THREAD_ID`, `CODEX_CI`, `GROK_AGENT`, `GROK_SESSION_ID`, `CURSOR_AGENT`, `CURSOR_CONVERSATION_ID`, `OPENCODE_TERMINAL`, `CLICOLOR_FORCE`, `GH_FORCE_TTY` and sets `NO_COLOR=1`. `_adapter_env` allowlists provider keys but does not drop these.
- **Concrete change:** `_adapter_env` (`scripts/invoke-external.sh:2120`) unsets the marker list before every dispatch; record the attested host in the lease ledger row.
- **Verification:** dispatch a Codex lease from a Claude Code session and print the env inside the builder — only Codex's own markers appear (extend `SELF-03`).

#### S16 (+ C3 evolution) — Ceremony classification with a one-way ratchet · *superpowers* · **ADOPT (T1)**
- **Why:** `/quick` vs `/plan` exists but nothing makes the lead classify out loud, forbids downgrading mid-task, or binds approval to the stage presented.
- **Concrete change:** `commands/quick.md` and `commands/plan.md` Phase 1.1: state the classification (spike / bounded / architectural); "when in doubt take the heavier path"; "hidden complexity upgrades the path, never downgrades"; "approval of an idea is not approval of an unseen plan".
- **Verification:** a `/quick` that uncovers a shared-interface change upgrades to `/plan` and says so.

#### AS-6 — `/plan` incomplete-plan overwrite guard · *agent-skills* · **ADOPT (T1)**
- **Why:** `commands/plan.md` rewrites `ops/TASKS.md` unconditionally (grep confirmed).
- **Concrete change:** one paragraph in `commands/plan.md` and `skills/writing-plans/SKILL.md`: if `ops/TASKS.md` has unchecked rows for a different goal, stop and ask (or, unattended, rule and ledger per S1).
- **Verification:** seed open rows for another goal, run `/plan`, expect stop-and-ask rather than a rewrite.

#### AS-8 + C14 — `verification_baseline` + machine-readable STATE.md frontmatter · *agent-skills + gsd* · **ADOPT (T1)**
- **Why:** a recorded "tests pass" is a claim about a specific baseline; `ops/STATE.md` is prose only.
- **Concrete change:** `skills/session-continuity/SKILL.md` snapshot gains YAML frontmatter (`phase`, `wave`, `tasks: {total, done, blocked}`, `verification_baseline: <sha>`, `verification_command`, `state_head`); `/resume` re-runs the recorded checks when HEAD differs; `hooks/handlers/pre-compact.sh` writes the same fields. (`state.json`, G12, stays T2.)
- **Verification:** pause, add a commit, resume → the resume path re-runs the recorded checks.

#### AS-9 — Outbound-endpoint hygiene for fetched docs · *agent-skills* · **ADOPT (T1)**
- **Why:** a KTD-11 sibling for research lanes: never hardcode outbound endpoints (telemetry/analytics) from fetched examples without surfacing them, even when docs mark them required (A/B 2/2 vs 0/2).
- **Concrete change:** one rule + verification checkbox in `commands/deep-research.md`, `antigravity-agents/agents/targeted-researcher.md`, `agents/framework-docs-researcher.md`.
- **Verification:** fixture doc with a "required" telemetry URL → the agent surfaces it instead of embedding it.

#### C4 (gated) — `learnings-researcher` in the Phase-3 review fan-out · *compound-engineering* · **ADOPT (T1)**
- **Why:** `commands/review.md` never spawns it (confirmed); CE gates the persona on a cheap title/path pre-search of the solutions store so a review never pays a subagent on an empty corpus.
- **Concrete change:** `commands/review.md`: pre-search `ops/solutions/` by changed-module names; spawn `learnings-researcher` only on a plausible match; its findings feed `findings-synthesizer` as "known-issue" context.
- **Verification:** empty `ops/solutions/` → no spawn; a matching solution → the review cites it.

#### S18 — Codex `[agents]` backstop keys + wait discipline · *superpowers* · **ADOPT (T1, version-gated — confirmed on 0.153.4 by the cli-watch Codex worker)**
- **Why:** child spawns that omit `model` inherit the session's most expensive model; setting `model` without `reasoning_effort` resets effort; 60–78 % of short `wait_agent` polls timed out.
- **Concrete change:** `codex-agents/agents.toml` `[agents]` gains `default_subagent_model = "gpt-6-astra"` and `default_subagent_reasoning_effort = "xhigh"` (keys verified in `config_toml.rs` at 0.153.4); `codex-agents/AGENTS.md`: set model AND effort on every spawn; bounded 5–10 minute event waits, never short polls; note `max_depth` is V1-only (D-026).
- **Verification:** `codex features list`; a spawn with no model uses the backstop.

#### G13 — Review Dispositions Ledger · *gsd-core* · **ADOPT (T1)**
- **Why:** dispositions across fix cycles are improvised; gsd promotes an append-only per-round table.
- **Concrete change:** `skills/iterative-refinement/SKILL.md` writes `## Review dispositions — Round N (<REVIEW_* snapshot commit>)` (concern | severity | how addressed / reason deferred) into `ops/TASKS.md`; later rounds add rows, never edit.
- **Verification:** a two-cycle fixture yields two round blocks, none edited.

#### G9 — Per-task `Agent-hint:` routing (Claude lane) · *gsd-core* · **ADOPT (T1)**
- **Why:** a plan can name the specialist that should execute a task; unknown hints must fall back byte-identically.
- **Concrete change:** optional `Agent-hint:` in the `ops/TASKS.md` row; the `lease_dispatch` claude case passes it as `subagent_type` when `agents/<name>.md` exists.
- **Verification:** an unknown hint → default builder.

#### S20 — Contributor disclosure block · *superpowers* · **ADOPT (T1, cheap)**
- **Concrete change:** `.github/PULL_REQUEST_TEMPLATE.md` with model / harness / version / plugins / human-reviewer table and a "new CLI adapter" section requiring a READY-probe transcript.
- **Verification:** template renders on a new PR.

#### G7 (scoped) — Hook crash policy + exit-code registry · *gsd-core* · **ADOPT (T1, scoped)**
- **Why:** "absence, emptiness and failure all encode as success" — Triforge's four handlers `set -euo pipefail` with no declared crash outcome; helpers conflate "could not verify" with "verified".
- **Concrete change:** each `hooks/handlers/*.sh` gets a one-line `# ON_CRASH: ALLOW|DENY — <reason>` and a matching final exit path; an exit-code table (0 ok · 2 hook deny · 64 usage · 66 no-input · 69 unavailable · 70 internal · 80 degraded) in the header of `scripts/invoke-external.sh` and `.claude/CLAUDE.md` "Hook safety"; `lease_heartbeat_check` / `ensure_core_trio_live` / `lease_status` return distinct rc for "could not verify" (T2 for the rc changes).
- **Verification:** grep gate in the release checklist; hook test for the crash path.

### Tier 2 — ADOPT (next sprint; script or protected-path work, or needs a probe first)

#### AS-1 — `.agents/skills/` refresh on plugin version change · **ADOPTED by D-029** (cli-watch ADR) — implement there.
#### AS-4 (lockstep) — **ADOPTED by D-027/D-028** — implement in T1 via the validator above.
#### AS-7 — Diff-scoped floor guard for `lease_merge` · *agent-skills* · **ADOPT (T2)**
- **Why:** nothing mechanical checks a lease diff for a weakened bar (`.skip`, deleted tests, `eslint-disable`, `@ts-ignore`, new exception rows, empty catch). Contract: merge-base diff + untracked; exit 0 clean / 1 violation / 2 could-not-run, never let 2 read as 0.
- **Concrete change:** `scripts/floor-guard.sh` run in `lease_collect` or as a `lease_merge` pre-check; findings to the pinned reviewer; the five moves added to `verification-before-completion`.
- **Verification:** plant `.skip` + `eslint-disable` in a lease branch → guard exits 1 and `lease_merge` refuses; shallow clone → exit 2, not treated as clean.

#### CE-2 + D1 (re-ranked) — Corpus-first retrieval frontmatter · **ADOPT (T2)**
- **Why:** July deferred D1 for migration cost; CE's 08-15 design keeps closed enums only for `problem_type`/`severity`/`resolution_type`, open vocabulary for the rest, date in frontmatter, no migration.
- **Concrete change:** `problem_type` (bug | knowledge), `applies_when`, `tags` added to the `knowledge-compounding` frontmatter and `commands/compound.md`; two section shapes; `agents/learnings-researcher.md` greps frontmatter before reading bodies; no migration of existing `ops/solutions/`.
- **Verification:** 20 seeded learnings → the right 3–5 from frontmatter grep within `maxTurns` 8.

#### CE-3 + C5 — `compound-refresh` with worth lens and "unverifiable is not false" · **ADOPT (T2)**
- **Concrete change:** new `skills/compound-refresh/SKILL.md` (Keep / Update / Consolidate / Replace / Delete; accuracy always, worth on request; contradiction checks bounded to guidance files the learning names; `status: stale` fallback; Applied vs Recommended split; unattended worth-deletes recommend-only; git history is the archive).
- **Verification:** an uncorroborated operational learning is kept with a gap note; a rule a test asserts verbatim is recommended for deletion quoting the test line.

#### CE-4 — Skill body budget + phase-loaded kernels (measure first) · **ADOPT (T2)**
- **Why:** Claude Code re-attaches each invoked skill at its first 5 000 tokens on compaction (25 000 combined); Codex caps Agent-Plugin skills at 8 000 bytes. `skills/wave-orchestration/SKILL.md` is 15 122 bytes; the other eleven are < 4 400.
- **Concrete change:** split wave-orchestration into a kernel (outcome, done bar, lease lifecycle, stop conditions above routing blocks) + `references/` per phase named as a required read at its step ("an earlier read does not satisfy the acting-point read"); shrink-only byte ratchet in the release checklist.
- **Verification:** `wc -c` < 8 000 for all twelve; a headless Codex wave opens the phase reference before dispatching.

#### CE-5 — Host-CLI skill-eval cell · **ADOPT-lite (T2)** — `scripts/skill-eval.sh` reusing the invoke lanes; three cells (verification refuses to claim without a run; wave refuses self-merge; compounding writes nothing for a trivial fix), graded on artifacts. Prerequisite for July D8.
#### CE-7 — Requested-vs-verified model receipts · **ADOPT-lite (T2)** — record `model_requested` + `model_actual` in `lease_merge` attribution when the lane exposes a receipt (`claude -p --output-format json` `modelUsage`); label codex/agy "requested, unverified"; add a probe row per lane.
#### S2 + C13 + C17 — Evidence-bearing preflight conflict table in plan-checker · **ADOPT (T2)** — one row per task pair sharing a `Files:` path or `CONTRACTS` type; plus gsd's rubric additions (3b undeclared coupling INFO-only; 7b scope reduction always BLOCKER); persisted dependency graph per task.
#### S3 + C3 — `Spec:` pointer, Global Constraints block, per-task `Interfaces:`; `commands/brainstorm.md` with three paths mapped onto `/quick` vs `/plan` · **ADOPT (T2)**.
#### S4 — Task right-sizing + same-shape batching into one lease · **ADOPT (T2)** (reviewer checks file-by-file for a hunk).
#### S8 — Scoped re-reviews + breaker adjudication within the 3-cycle cap · **ADOPT (T2)**.
#### S9 — Review packages as files; `base_sha` recorded at `lease_create` · **ADOPT (T2, protected)** — `lease_review_package <task>` → `ops/reviews/<task>-<base7>..<head7>.diff`.
#### S15 — `lease_reclaim` snapshots untracked output before `--force` removal · **ADOPT (T2, protected)** (`invoke-external.sh:2592`).
#### S19 — SessionStart bootstrap as structured hook output + shape test · **ADOPT (T2)** — `hooks/hooks.json` matcher `startup|clear|compact`, `shell: "bash"`; `session-start.sh` emits `hookSpecificOutput.additionalContext` with a compact "using-triforge" index and a SUBAGENT-STOP line; `tests/hooks/test-session-start.sh`. (Note the cli-watch finding: hook stdout that *looks* like JSON but is not is now a hook error — D-031.)
#### G1 + G5 + D6 (re-ranked) — Declared per-member capability axes with fail-closed negotiation · **ADOPT (T2)** — `[members.<cli>.capabilities]` (`isolation`, `max_concurrency`, `effort_surface`, `named_dispatch`) seeded from the probe record and emitted by `probe-capabilities.sh`; missing key ⇒ sequential + no effort flag; effective concurrency = min(tasks, jobs, capacity).
#### G2 — Isolation sentinel + PreToolUse `Agent` guard (Claude builder lane only) · **ADOPT (T2)** — lead grounding: external-CLI builders are worktree-dispatched by the lead, so the guard applies to Agent-tool builder spawns lacking `isolation: worktree`.
#### G3 + D4 (superseded) — Scope conformance at `lease_merge` + declared-deletions guard · **ADOPT (T2, protected)** — advisory `scope_warnings` in the ledger + CHANGELOG; refuse undeclared deletions unless the task row carries `Deletes:`.
#### G4 — Wave-order merges + crash-window reconciliation · **ADOPT (T2, partial)** — "merge in wave order, never completion order"; `lease_collect` routes a complete output with ledger state `building` to `review`, not requeue; keep the worktree on merge failure.
#### G8 — Reviewer provenance + dropped-lane semantics · **ADOPT (T2, partial)** — `model:`/`effort:`/`source:` frontmatter in `ops/REVIEW_*.md`; `findings-synthesizer` treats an empty file as "lane failed", never "no findings".
#### G10 — Verification fingerprint gating the sentinel · **ADOPT (T2)** — `coordinate.sh` refuses `ops/.sprint-complete` when the recorded sha/hash no longer matches HEAD.
#### G12 + C15 — `ops/state.json` contract (every key present, `null` for unknown) consumed by `coordinate.sh`; structured `HANDOFF.json` · **ADOPT (T2)**.
#### G14 — Rate-limit escalation in the fallback chain · **ADOPT (T2)** — `lease_heartbeat_check` classifies `rate_limited` → `lease_requeue` to the next roster member honoring `Retry-After`.
#### C6 — Grounding-validation gate (vendor CE's stdlib `validate-doc-claims.py`, FLAG vs NOTE tiers) · **ADOPT (T2)**.
#### C7 (+ CE detached-job lifecycle) — Async-job manifest + `external_job_waiting` · **ADOPT (T2)** — unchanged contract; add CE's start-returns-in-1s / durable job dir / watchdog / bounded-wait refinements.
#### C12 — Write-time overlap/dedup in compounding · **ADOPT (T2)** (with CE-1's bar reducing what is written at all).
#### C16 + C18 — Commit-range ledger completion lines + rulings export; numbered requirement IDs for multi-phase builds · **ADOPT (T2)**.

### Tier 3 — DEFER (revisit on trigger)

| ID | Candidate | Source | Why defer | Trigger |
|---|---|---|---|---|
| AS-10 | Rank-1 ratchet + rejected-change ledger | agent-skills | needs routing evals first | D8 lands |
| AS-11 | Add `skills/` to the `antigravity-agents/` pack | agent-skills | skills already reach agy via `.agents/skills/`; only interactive `/agent-triforge:` use benefits | user asks for interactive agy skill namespace |
| AS-12 | Skill-gap issue form; Copilot root manifest | agent-skills | no `.github/` community tooling; a root manifest would shadow the Claude manifest for Copilot only | Copilot becomes a roster member |
| CE-8 | Compound Packs | compound-engineering | experimental (09-09); the natural shape for shipping Triforge gotchas into user projects later | survives one CE release cycle |
| CE-9 | Bake-off command (core trio as candidates, plan-checker as judge) | compound-engineering | new 09-08; sibling integration only on request | user asks; plan-checker flags a high-risk decision |
| CE-10 | Wave contract: isolation as escalation | compound-engineering | Triforge deliberately keeps per-task worktrees; only the hidden-surface ownership rule transfers (fold into G3) | never (design contrast recorded) |
| CE-noslop | Plain-prose skill for the documenter role | compound-engineering | polish | documentation-writer quality complaints |
| S21–S24 | diagnosing-superpowers, agentic E2E cards, proving-it-works-with-a-movie, SDD metrics | superpowers | all open/unmerged upstream PRs | each merges upstream |
| G-defer | effort clamp tables, estimate/calibration loop, spine/detail split (ADR-4139), drift-ack commit trailers, tracker seam, broken-windows ledger | gsd-core | larger lifts or overlap with T2 items | after G1/G12 land |
| D2 | Cross-CLI session-history mining | compound-engineering | still Claude/Codex/Cursor/pi/omp only; cheaper first step is mining `ops/archive/reviews/` + the lease ledger | after C5/C6 |
| D3 (glossary half) | `ops/CONCEPTS.md` glossary | compound-engineering | gained a retention lifecycle that raises maintenance cost; the `/setup` directive offer half is promoted into CE-1 | after C5 |
| D5 | Declarative gate predicates | gsd-core | overlaps the sentinel + G10 fingerprint | Triforge adds a capability layer |
| D7 | condition-based waiting + `find-polluter.sh` | superpowers | valuable but narrow; port the **fixed** v6.2.0 script + its test if adopted (the July-era script was broken) | flaky-test churn in the Codex loop |
| D8 | Behavioral eval harness with pressure fixtures | agent-skills | high effort; CE-5 is the cheaper first cell | CE-5 + C1 + C10 land |
| D9 | Progressive-disclosure split | agent-skills | size audit: largest skill 209 lines; subsumed by CE-4 for wave-orchestration | a skill exceeds 500 lines |

## 3. Cross-cutting themes

1. **`.agents/skills/` is settled; slash commands are not.** Four repos and six CLI docs agree on the path (Claude Code excepted); every repo maps commands per harness (parallel command dirs, skills-as-commands, `--command`, `$name`, `/skill:name`). Triforge's commands are lead-only, so no parity work — document the invocation matrix (D-029).
2. **Small, portable, ordered skill bodies.** Two independent truncation caps keep only the start of a body; both CE and agent-skills moved to kernels + `references/`; vendor fields under `metadata`; arguments survive as table rows, not prose deleted for brevity.
3. **Contracts over prose for dispatched work.** No sub-dispatch (S5, gsd's built-in-only routing), typed status codes (S14, G7), git-stays-local (S13), rulings ledgers (S1, G13), preflight tables (S2), and three-valued results (G7, G3, CE-3) all replace "the model will probably do the right thing".
4. **Ceremony ratchets one way; approval binds to the stage.** superpowers' three paths and stage-bound gate, gsd's reversibility checkpoints, CE's counterfactual bar.
5. **Provenance is a claim until receipted.** CE's model receipts, gsd's `model_sources`, superpowers' "do not trust the report", agent-skills' verification-baseline sha.

## 4. Registry health / flagged targets

All four `[repo.*]` targets resolved (HTTPS, public host, not archived, pushed 2026-09-08 … 09-11). No hard-failed target. Notes: gsd's default branch is `next` (the registry `url` is fine; the worker cloned `next`); superpowers' `pushed_at` reflects PR-branch activity while `main` is frozen at v6.3.0 (2026-08-12) — the next cycle should mine `dev` explicitly. Unauthenticated GitHub API quota was exhausted by the four concurrent workers; all fell back to raw.githubusercontent.com / github.com tree pages, so **the next cycle should stagger workers or use an authenticated token** (a `/repo-watch` refinement, not a registry issue).

### Flagged targets (continue-and-flag)

No target hard-failed (no 404 / rename / validation reject / timeout). Nothing to flag.

## 5. Grounding caveats (local doc-drift surfaced while grounding — handed to the sprint, not mining candidates)

- `antigravity-agents/plugin.json` `version` 3.0.0 vs `.claude-plugin/plugin.json` 3.2.0 (AS-4; D-027 bumps both).
- `templates/CLAUDE.md:116` says "13 model-agnostic methodology skills"; `skills/` holds twelve since v3.2.0.
- `commands/review.md` never spawns `learnings-researcher` (July C4 open; T1 above).
- `lease_reclaim` runs `git worktree remove --force` (`scripts/invoke-external.sh:2592`) — S15.
- `lease_create` branches from HEAD with no upstream (`scripts/invoke-external.sh:2219`) — makes superpowers #2228 mostly N/A.
- The cli-watch report's fixture test independently confirms agent-skills' six-harness matrix (Claude Code does not read `.agents/skills/`; agy needs the workspace bound).

## 6. Sources appendix

- **agent-skills:** raw.githubusercontent.com/addyosmani/agent-skills/main/{README,CONTRIBUTING,AGENTS,CLAUDE}.md, docs/{skill-anatomy,advanced-per-agent-configuration,antigravity-setup,codex-setup,opencode-setup,cursor-setup,commandcode-setup,copilot-cli-setup,gemini-cli-setup}.md, scripts/{validate-skills,validate-commands,validate-reference-links,validate-artifact-paths,validate-versions,run-evals}.js, scripts/lib/skill-lint.js, evals/{README,skill-impact}.md, evals/fixtures/shipping-and-launch/authority-pressure.md, skills/constraint-driven-development/{SKILL.md,references/floor-guard.md}, .claude-plugin/, .codex-plugin/, .agents/plugins/marketplace.json, hooks/{hooks.json,session-start.sh}; releases 0.6.5–0.6.9; commits since 2026-07-18 (API pages 1–2; `.patch` endpoints after the rate limit); spec: agentskills.io/specification.md, /client-implementation/adding-skills-support.md, /skill-creation/*.md, skills-ref README, vercel-labs/skills README.
- **compound-engineering-plugin:** api.github.com commits since 2026-07-18 (pages 1–4, 315 commits); releases v3.20.0–v3.24.0; manifests `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `.kimi-plugin/`, `.omp-plugin/`, `.devin-plugin/`, `.grok-plugin/`, `.agents/plugins/marketplace.json`, `.agy/`, `.opencode/plugins/compound-engineering.js`, `.pi/extensions/`, `.cline/scripts/install-skills.sh`, `package.json`, `.github/release-please-config.json`, `scripts/release/validate.ts`; docs/specs/{agent-plugins,antigravity,omp,opencode,cursor,kimi,cline,copilot,devin}.md; docs/guides/{ce-compound,ce-compound-refresh,ce-noslop,ce-bakeoff,ce-pov,packs,configuration}.md; skills/ce-compound/{SKILL.md,references/*,scripts/validate-doc-claims.py}, skills/ce-compound-refresh/**, skills/ce-code-review/references/{select-and-route,dispatch-reviewers,cross-model-review}.md, skills/ce-work/references/execution-strategy.md, skills/ce-setup/assets/compounding-directive.md, tests/skill-eval-cell/*, tests/codex-skill-prompt-budget.test.ts; docs/solutions/integrations/{agent-plugins-schema-is-a-host-routing-switch,native-plugin-install-strategy}.md, docs/solutions/skill-design/{portable-agent-skill-authoring,size-driven-skill-restructure,bound-contradiction-checks-to-named-guidance,workspace-isolation-is-escalation-not-entry-fee,requested-vs-verified-model-identity,detached-job-lifecycle-for-delegated-work}.md; PRs 1154 … 1664 as cited inline.
- **superpowers:** api.github.com commits since 2026-07-18 (main + dev); releases v6.2.0, v6.3.0; RELEASE-NOTES.md; dev commits 3b4f2ca, 069edf3; `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `.devin-plugin/`, `.kimi-plugin/`, `.hermes-plugin/`, `.opencode/plugins/superpowers.js`, `.pi/extensions/superpowers.ts`, `gemini-extension.json`, hooks/{hooks.json,hooks-cursor.json,run-hook.cmd,session-start}, docs/porting-to-a-new-harness.md, docs/superpowers/specs/2026-07-15-sdd-fix-loop-redesign-design.md; skills read in full: using-superpowers (+ references), brainstorming, writing-plans, executing-plans, verification-before-completion, systematic-debugging (+ companions), test-driven-development (+ writing-good-tests.md), subagent-driven-development (+ implementer/task-reviewer/re-review prompts, scripts), requesting/receiving-code-review, finishing-a-development-branch, using-git-worktrees, writing-skills; tests/hooks/test-session-start.sh, tests/systematic-debugging/test-find-polluter.sh; PRs #2059–#2089 (merged), #2196, #2228, #2229, #2255, #2270, #2274 (open); closed #2226, #2244.
- **gsd-core:** shallow clone of `next` (HEAD 523be341, 2026-09-11); npm `@opengsd/gsd-core` publish times; CHANGELOG.md, VERSIONING.md; docs/reference/{host-integration-interface,host-integration-capability-matrix,capability-matrix,capability-manifest,plan-md,state-md,planning-artifacts,gate-predicates,exit-codes,long-running-operations}.md; docs/how-to/{install-on-your-runtime,add-or-update-a-host-integration,author-a-host-plugin,async-external-jobs,batch-quick-tasks,configure-model-profiles,enable-parallel-reviewer-lanes,consume-the-state-contract,consume-the-planning-snapshot,interpret-scope-conformance-warnings,state-a-failing-direction,declare-a-hook-crash-policy,set-up-cross-ai-review}.md; docs/adr/{2782,2866,3473,3574,3646,3806,3889,3942,4139}; capabilities/{codex,opencode,kimi-code}/capability.json; hooks/gsd-agent-isolation-guard.js; src/{file-overlap-partitioner,plan-dependency-graph}.cts; gsd-core/references/{runtime-aware-dispatch,dispatch-isolation-gate}.md; agents/gsd-plan-checker.md; PRs 2422 … 4618 as cited inline.
- **Internal grounding (read-only):** `ops/research/2026-07-18-repo-mining.md`, `ops/research/2026-09-11-cli-updates.md`, `ops/decisions/2026-09-11-cli-deprecation-watch.md`, `ops/research/2026-09-probe-record.md`, `skills/*/SKILL.md` (+ `wc -c`), `commands/{plan,quick,review,wrap,compound,deep-research}.md`, `agents/{plan-checker,findings-synthesizer,learnings-researcher,continuous-reviewer,test-gap-analyzer}.md`, `scripts/invoke-external.sh` (lease_* 2200–3051; `_adapter_env` 2120), `hooks/hooks.json`, `hooks/handlers/*.sh`, `codex-agents/agents.toml`, `templates/CLAUDE.md`, `templates/ops/roster.toml`, `.claude-plugin/plugin.json`, `antigravity-agents/plugin.json`.

**Cross-checks performed (per watch-cycle SKILL §Stage 6):**
1. **Registry validation** — 4/4 `[repo.*]` URLs HTTPS + public-host OK; `meta.repo_count=4` matches; liveness via the GitHub API (default branch, `pushed_at`, `archived=false`); no flagged targets.
2. **Source verification** — each repo mined by an independent read-only worker from its own files, commits, releases, PRs and in-tree docs; the lead spot-checked six load-bearing claims against the local tree (`lease_create` HEAD branching, `lease_reclaim --force`, `commands/review.md` lacking `learnings-researcher`, `templates/CLAUDE.md` "13 skills", manifest version drift, `wc -c` of `wave-orchestration`).
3. **Window coverage** — 2026-07-18 → 2026-09-11 for all four; superpowers' frozen `main` noted with `dev` covered explicitly.
4. **Gap-table grounding** — every **Concrete change** names a real Triforge path (grep-verified this session).
5. **De-duplication across repos** — convergent items merged (AS-1 ≡ D-029; AS-4 ≡ D-027; S2 ⊃ C13/C17; S10 ⊃ C9; G6 ⊃ C8; G3 supersedes D4; G1 supersedes D6; CE-2 supersedes D1; S16 evolves C3) and cross-referenced to the cli-watch ADR where already decided.
6. **Injection / decoy scan** — no fetched content attempted to direct any worker; forceful agent-directive text (superpowers' using-superpowers "non-negotiable" rules and OpenCode "fetch and follow" README line; agent-skills' AGENTS.md "you MUST invoke"; CE's upgrading.md "paste this into Codex" runbook and GEMINI.md; gsd's install-command lines) was quoted as product payload and acted on by no one. Two defensive practices worth copying are recorded (AS-9 outbound-endpoint rule; eval graders fencing traces as untrusted).
