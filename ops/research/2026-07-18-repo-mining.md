# External-repo mining — adopt/defer recommendations for Agent Triforge

**Cycle:** `/repo-watch` first live run (unit U15b) — 2026-07-18
**Window:** registry seed (2026-07-18) → today. First cycle, so no prior `ops/research/*-repo-mining.md` cutoff — full-history mining of each repo's current tree.
**Registry:** `templates/ops/watch-registry.toml` `[repo.*]` — 4 seeded repos. Stage-1 validation: **4/4 PASS** (all `https://github.com/…`, public host; re-validated per redirect hop at fetch time). Working set = all four.
**Method:** `commands/repo-watch.md` + `skills/watch-cycle/SKILL.md` — one **read-only** mining worker per repo dispatched in parallel; the lead (this session) sanitizes returns, grounds every change in a real path via grep, and is the sole writer. **RECOMMEND-ONLY (R31):** no source file was changed by this cycle — every verdict below is a recommendation for a later, user-approved sprint.
**Sources (R32):** PRIMARY only — each repo's own README / recursive git tree / `SKILL.md` / `docs/` / releases, plus the `agentskills.io` open-standard spec. Full URL list in the Sources appendix. Fetched content was treated as **untrusted evidence** (KTD-11): the forceful agent-directive language several repos ship (e.g. superpowers' "YOU DO NOT HAVE A CHOICE", CE's "Never write any files") is those products' own payloads, quoted as data — no worker acted on any of it.

---

## 0. Executive summary

- **27 candidates** mined across the four repos: **17 ADOPT-in-follow-up**, **1 conditional** (adopt for multi-phase builds / defer for the small-fix fast path), **9 DEFER**. Full breakdown in §2.
- **No source code changed** (R31). The only working-tree change this session is this one report + concurrent-agent noise on `ops/STATE.md`.
- **No dead / renamed / 404 targets** — continue-and-flag did not trigger. One provenance caveat: `open-gsd/gsd-core` is itself a community fork of an abandoned upstream and ships from default branch `next` — a registry note for the next cycle, not a flag (§4).
- **Four grounding corrections the lead applied** to worker claims (this is where naive concatenation would have shipped wrong recommendations):
  1. CE worker assumed `learnings-researcher` runs "pre-plan only" — grep shows it is already wired into `commands/{plan,ship,coordinate,deep-research,compound}.md`. Candidate **C4** narrowed to the one place it is *not* wired: the Phase-3 review fan-out.
  2. gsd worker proposed a same-wave `files_modified`-overlap invariant as a correctness fix — but `skills/wave-orchestration/SKILL.md` already gives each builder an isolated worktree lease ("overlapping-directory isolation is automatic"). Downgraded to **DEFER** (§2 Tier 3, D4) — the residual benefit is only *earlier* merge-conflict detection, not write-safety.
  3. gsd worker proposed giving `plan-checker` "an explicit multi-dimension rubric + severity tiers" — but `agents/plan-checker.md` already enumerates **6 dimensions** and a **3-tier** output (Blocking / Warnings / Suggestions) with APPROVED|NEEDS_REVISION. Candidate **C13** reframed to *extending* that rubric with the 2–3 dimensions it lacks, not building one.
  4. CE worker's "staleness maintenance" gap is real, but `skills/knowledge-compounding/SKILL.md` already defines a `status: accepted | superseded | deprecated` frontmatter field — nothing *populates* it. Candidate **C5** is scoped to adding the *process*, reusing the existing field.
- **Local doc-drift found while grounding (not a mining candidate, flagged to team-lead, §5):** the root `CLAUDE.md` describes `hooks/handlers/ship-loop.sh` as a Stop hook / "inner loop", but on branch `feat/cli-modernization-builder-pool` that file does not exist, and `hooks/hooks.json` registers only PostToolUse / PreCompact / SessionStart (no Stop). The current completion-gating mechanism is `scripts/coordinate.sh` + the `ops/.sprint-complete` sentinel (per `templates/CLAUDE.md`). All candidates below are grounded against that real mechanism.

### Top 8 (highest value, lowest risk — do these first)

| # | Candidate | Source repo | Why it's top |
|---|---|---|---|
| C1 | SKILL.md validator/linter | agent-skills | Lowest effort; closes a confirmed zero-tooling gap; spec-aligned |
| C2 | Anti-rationalization sections in discipline skills | agent-skills + superpowers | Cheap text; two independent sources; hits Triforge's central failure mode |
| C3 | `brainstorming` skill + design-approval hard-gate | superpowers | Confirmed-missing lifecycle stage (no `skills/*brainstorm*`) |
| C5 | `compound-refresh` staleness-maintenance loop | compound-engineering | Biggest hole in the compounding loop; maps onto the scheduled watch family |
| C6 | Grounding-validation gate before a learning compounds | compound-engineering | Correctness gate — one wrong `ops/solutions/` entry compounds forever |
| C7 | Async-job manifest for background CLIs | gsd-core | Most architecture-specific — `invoke-external.sh` backgrounds CLIs with no durable job record |
| C8 | Per-task executable `verify`/`done` fields | gsd-core | Converts prose completion checklist into per-task machine gates |
| C9 | Red-green-**revert** proof + verify-subagent-via-VCS-diff | superpowers | Concrete anti-false-completion mechanisms `verification-before-completion` lacks |

---

## 1. Per-repo profiles

### 1.1 addyosmani/agent-skills — the skill-authoring standard
- **What:** "Production-grade engineering skills for AI coding agents" — ~24 lifecycle `SKILL.md` skills + 4 personas + 7 checklists + a **skill-validation + eval toolchain** (`scripts/validate-skills.js`, `scripts/lib/skill-lint.js`, `scripts/run-evals.js`). MIT; ~79k stars; created 2026-02-15; last push 2026-07-17; latest release 0.6.4 (2026-07-12). Not archived — healthy.
- **The adjacent find that matters most:** it implements the **`agentskills.io` open standard** ("originally developed by Anthropic, released as an open standard") with a formal frontmatter spec, a Python reference validator (`skills-ref validate ./my-skill`), and 70+ implementing clients — including most of Triforge's own builder-pool CLIs (Claude Code, Codex, Cursor, OpenCode, Gemini/Antigravity).
- **Transferable patterns:** (a) formal frontmatter contract with hard limits (`name` ≤64 kebab == dir; `description` ≤1024; optional `compatibility`, `metadata`, experimental `allowed-tools`); (b) a real linter enforcing name==dir, kebab regex, description length, a mandatory "use when" trigger, and dead cross-skill-reference detection (`scripts/lib/skill-lint.js`); (c) a three-tier eval framework (structural → trigger-routing → behavioral) with **adversarial "authority-pressure" fixtures** (`evals/`); (d) an anti-rationalization authoring convention — every skill carries `## Common Rationalizations` + `## Red Flags` + `## Verification` (`docs/skill-anatomy.md`); (e) description-as-classifier optimization (labeled near-miss queries, 60/40 train/val split); (f) progressive-disclosure token budgets (`SKILL.md` <500 lines, detail pushed to `references/`+`scripts/` with explicit load-triggers).

### 1.2 EveryInc/compound-engineering-plugin — the compounding-knowledge loop
- **What:** "Official Compound Engineering plugin" — a six-step loop Brainstorm → Plan → Work → Simplify → Review → **Compound**. MIT; ~23k stars; created 2025-10-09; last push 2026-07-18 (daily commits) — very healthy. Ships a TypeScript converter (`src/`) that transpiles Claude skills to Codex/Cursor/OpenCode/Kimi/Antigravity/etc., and 128 contract tests (`tests/`).
- **The compounding loop, end-to-end (the core comparison):** **RECORD** — `/ce-compound` fans out parallel subagents (Context Analyzer, Solution Extractor, Related-Docs Finder) + a session-history probe, then writes one doc to `docs/solutions/<category>/`. **INDEX** — controlled-enum YAML frontmatter (`problem_type`, `component`, `tags`, `severity`) + `problem_type→directory` mapping + a `CONCEPTS.md` glossary. **SURFACE** — a `learnings-researcher` persona embedded into ce-plan / ce-code-review / ce-ideate / ce-optimize. **MAINTAIN** — `/ce-compound-refresh` audits the store against the live tree (Keep / Update / Consolidate / Replace / Delete).
- **Transferable patterns:** (a) a dedicated **staleness-maintenance** skill (`skills/ce-compound-refresh/SKILL.md`); (b) **grounding validation** before a learning is trusted — deterministic `validate-doc-claims.py` (cited-path / SHA / dead-link / scaffold-leak checks) + a read-only semantic subagent that verifies code claims by quoting `file:line` (`skills/ce-compound/references/grounding-validation.md`); (c) **write-time overlap/dedup** scoring across 5 dimensions before a doc lands; (d) retrieval-oriented controlled frontmatter (`references/schema.yaml`); (e) a subagent "return the path, not the summary" rule guarding against summary-collapse.

### 1.3 obra/superpowers — reliability through skill discipline
- **What:** "An agentic skills framework & software development methodology that works" (Jesse Vincent). MIT; very large star count; created 2025-10-09; last push 2026-07-17; latest release v6.1.1 (2026-07-02). Multi-platform (Claude/Codex/Cursor/Kimi/OpenCode/Pi/Copilot/Antigravity).
- **Headline architectural finding (frames the candidates):** superpowers enforces workflow discipline **almost entirely through injected skills, not blocking hooks** — its *entire* hook surface is a single `SessionStart` hook injecting a `using-superpowers` router meta-skill; there is **no Stop/PreToolUse/PostToolUse gate**. So the transferable value is its *skill-level self-check discipline*, and it is independent proof that you can enforce discipline without a Stop hook — directly relevant given Triforge's own ship-loop Stop hook is now gone (§5).
- **Transferable patterns:** (a) "**Iron Law**" + "**Red Flags — STOP**" + "**Excuse | Reality**" tables opening every discipline skill (pre-empts the exact sentences an agent uses to skip a step); (b) a **brainstorming HARD-GATE** — no code/scaffolding/planning until a design is user-approved (`skills/brainstorming/SKILL.md`); (c) **subagent-driven development with a commit-range ledger** (`.superpowers/sdd/progress.md`) keyed by commit range so it survives compaction, plus structured status codes (DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED); (d) **verification proof-obligations** — regression tests require a red-green-**revert** cycle, and subagent success is verified *independently via the VCS diff*, never from self-report; (e) debugging companions (`root-cause-tracing.md`, `condition-based-waiting.md`, a `find-polluter.sh` test-bisection script); (f) skill-authoring rules — lazy `**REQUIRED SUB-SKILL:**` cross-refs, a ban on `@path` force-loading (context blow-up), and "description = *when to use*, not *what it does*".

### 1.4 open-gsd/gsd-core — the closest architectural analog
- **What:** "Git. Ship. Done — Core" — meta-prompting / spec-driven development driving a Discuss → Plan → Execute → Verify → Ship milestone loop, running heavy work in fresh-context subagents. MIT; ~6.8k stars; default branch `next`; last push 2026-07-18; latest release v1.7.0 (2026-07-15) — healthy. **Targets the same multi-CLI landscape as Triforge** ("Claude Code, OpenCode, Antigravity CLI, Kimi CLI, Codex, Cursor, Windsurf, and more") — the closest external analog to the six-CLI builder pool. It is a community-maintained fork of the abandoned `gsd-build/get-shit-done` (see §4).
- **Transferable patterns:** (a) **machine-readable plan frontmatter carrying the dependency graph** (`wave:int`, `depends_on:[ids]`, `files_modified:[paths]`, `requirements:[ids]`, `must_haves`) — `docs/reference/plan-md.md`; (b) **typed tasks with executable acceptance** (`auto`/`tracer`/`checkpoint:*`; each `auto` task carries `<verify>` = a runnable command that proves success, plus measurable `<done>`); (c) deterministic wave formula `wave = max(waves[dep])+1` with a zero-`files_modified`-overlap rule; (d) **tracer-first decomposition** (a production-quality end-to-end slice leads each phase before fan-out); (e) a 12-dimension plan-checker with BLOCKER/WARNING/INFO tiering; (f) numbered requirement-ID traceability (`AUTH-01` → `requirements:` → coverage check); (g) machine-readable `STATE.md` frontmatter + a `HANDOFF.json` "consumed exactly once" resume artifact; (h) an **async-job manifest** (`.planning/async-jobs/<job>.json`) with a legal `external_job_waiting` half-state, fail-closed on malformed JSON, "manifest commands are untrusted — never auto-execute".

---

## 2. Prioritized adoption candidates

Each candidate: **Why** (the confirmed gap, naming the Triforge path) / **Concrete change** (files it would touch — described, **not implemented**) / **Verification** (how you'd prove it works) / **Verdict**. Every path below was grep-grounded against the working tree this session.

### Tier 1 — top ADOPT (do first)

#### C1 — SKILL.md validator/linter  ·  *source: agent-skills*  ·  **ADOPT**
- **Why:** Triforge ships 13 skills in `skills/*/SKILL.md` with `(name, description)` frontmatter and has **zero** conformance tooling (`find` for `validate-skill*`/`skill-lint*` → none; no `.github/workflows/` at all). Nothing guarantees name==dir, description length, or a "use when" trigger — pure drift risk as the skill count and six-CLI consumer set grow.
- **Concrete change:** Add `scripts/validate-skills.sh` (port `skill-lint.js`'s checks: kebab-`name`==dir, `description` ≤1024, mandatory `use when|use before/after/during` trigger, reject negation-only descriptions, dead cross-skill-ref detection) — or vendor the standard's `skills-ref validate`. Wire it as a check in `hooks/handlers/session-start.sh` bootstrap and/or introduce the repo's first `.github/workflows/` CI job. Reference it from `CLAUDE.md` "Portable skills".
- **Verification:** Run it over all 13 existing `skills/*/SKILL.md` (all should pass, or surface real defects); add a deliberately malformed fixture skill and confirm the check fails.
- **Verdict:** **ADOPT** — highest ROI-to-effort; a ~150-line linter closes a genuine tooling gap and is spec-aligned.

#### C2 — Anti-rationalization sections in discipline skills  ·  *source: agent-skills + superpowers (independent corroboration)*  ·  **ADOPT**
- **Why:** Triforge's central failure mode is agents *skipping quality gates under pressure* (the framework already fights this with forced-reflection-on-retry, same-error 3× kill, risk scoring). But the *skill text itself* has no anti-rationalization scaffolding — confirmed: `skills/verification-before-completion/SKILL.md`, `skills/systematic-debugging/SKILL.md`, `skills/test-driven-development/SKILL.md` contain no Iron Law, no "Red Flags — STOP" list, and no "Excuse | Reality" table. Both agent-skills and superpowers converge on the same fix.
- **Concrete change:** Prepend to each discipline skill (`verification-before-completion`, `systematic-debugging`, `test-driven-development`, `iterative-refinement`, `scope-cutting`, and the review skills) three sections: a one-line Iron Law, a "Red Flags — STOP" self-check, and an "Excuse | Reality" table. Pure prompt-shaping; no new infra.
- **Verification:** Adversarial before/after on a fixed prompt set — confirm the agent stops emitting success wording ("should pass", "looks done") without having run the command in-message; confirm each edited skill now contains the three sections (reuses C1's linter to enforce presence).
- **Verdict:** **ADOPT** — cheapest reliability upgrade that directly targets a stated Triforge goal; two independent sources raise confidence.

#### C3 — `brainstorming` skill + design-approval hard-gate  ·  *source: superpowers*  ·  **ADOPT**
- **Why:** Confirmed missing — `skills/*brainstorm*` returns nothing. Triforge jumps goal → `writing-plans`/`plan-checker` (Phase 1); its only upstream check is Phase-1.1 "ambiguity resolution" (a validation step), not a collaborative scoping + design-doc + explicit-approval front-gate. superpowers forbids code/scaffolding/planning until a design is presented and user-approved.
- **Concrete change:** New `skills/brainstorming/SKILL.md` + a `commands/brainstorm.md` wired as the mandated predecessor to `commands/plan.md`: one question at a time, 2–3 approaches with tradeoffs, design doc saved under `ops/decisions/` (or a specs dir), then hand off to `writing-plans`. Note the interop opportunity — CE's `ce-brainstorm` and gsd's Discuss phase are the same idea; Triforge can align naming.
- **Verification:** Run a "build X" prompt; confirm the agent brainstorms and secures approval *before* any planning/scaffolding, and that a design doc is written.
- **Verdict:** **ADOPT** — closes a named lifecycle gap (the superpowers focus hint's target); low risk, high clarity payoff.

#### C5 — `compound-refresh` staleness-maintenance loop  ·  *source: compound-engineering*  ·  **ADOPT**
- **Why:** `skills/knowledge-compounding/` writes to `ops/solutions/` + `ops/decisions/` and never revisits them. The schema already *defines* `status: accepted | superseded | deprecated`, but **nothing populates it** — no process detects a learning that has gone stale, been superseded, or duplicated. `agents/learnings-researcher.md` will keep surfacing outdated guidance as fact.
- **Concrete change:** Add `skills/compound-refresh/SKILL.md` (mirror CE's 5-outcome model: Keep / Update / Consolidate / Replace / Delete, setting the existing `status:` field, marking `status: stale` when ambiguous) auditing `ops/solutions/` + `ops/decisions/` against the current tree. Wire a headless invocation into the existing `skills/watch-cycle/` scheduled family (it already runs unattended) so it reports Applied vs Recommended actions. Rank staleness candidates by the existing provenance dates.
- **Verification:** Seed a solution citing a path you then rename; run the refresh headless; confirm it reclassifies to Update / rewrites the ref (or marks `status: stale`), and leaves a still-accurate learning untouched.
- **Verdict:** **ADOPT** — closes the single biggest hole in Triforge's compounding loop; the headless mode maps cleanly onto the watch family.

#### C6 — Grounding-validation gate before a learning compounds  ·  *source: compound-engineering*  ·  **ADOPT**
- **Why:** Triforge captures provenance (`sprint_id`, `task_id`, `evidence_files`, `related_decisions` — confirmed in `knowledge-compounding/SKILL.md`) but never verifies a learning is *true against current code* before it becomes trusted. One wrong `ops/solutions/` entry compounds into every future `learnings-researcher` retrieval.
- **Concrete change:** Add a validation phase to `skills/knowledge-compounding/SKILL.md`: (1) a small deterministic checker (flag cited paths that don't exist, bare commit SHAs, dead relative links, `{{scaffold}}` leaks) over the new `ops/solutions|decisions/*.md`; (2) a read-only Claude subagent verifying code-behavior claims by quoting `file:line` and merge-state via `gh pr view`. Adjudicate flags (fix / annotate-as-historical / confirm) rather than auto-fail. Pairs with the existing `verification-before-completion` skill.
- **Verification:** Write a learning asserting a function returns X when it returns Y; confirm the semantic pass flags "contradicted" with the quoted defining line and the claim is corrected before finalize.
- **Verdict:** **ADOPT** — correctness gate; cheap relative to the cost of a wrong learning propagating.

#### C7 — Async-job manifest + `external_job_waiting` half-state for background CLIs  ·  *source: gsd-core*  ·  **ADOPT**
- **Why:** Most architecture-specific gap. `scripts/invoke-external.sh` invokes builder/reviewer CLIs as **background subshells** (grep-confirmed: `) &` and "background invocations/subagents/subshells" comments). If the lead session dies while a background CLI is still running, nothing durably records the in-flight job — a resume via `scripts/coordinate.sh` can spawn a duplicate.
- **Concrete change:** Have `invoke-external.sh` write `ops/async-jobs/<id>.json` (job id, task id, output file, start time, expected artifact) when backgrounding a CLI; teach `coordinate.sh` to detect in-flight jobs on resume and wait/reclaim rather than re-spawn. Adopt gsd's safety rules verbatim (exact-`plan_id` match, fail-closed on malformed JSON, never auto-execute a manifest-supplied command — aligns with Triforge's untrusted-evidence posture).
- **Verification:** Start a long Codex run, simulate session death, resume; confirm `coordinate.sh` finds the manifest and waits for the existing output file instead of launching a duplicate.
- **Verdict:** **ADOPT** — closes a real duplicate-external-run gap unique to Triforge's background-CLI architecture.

#### C8 — Per-task executable `verify`/`done` fields (the "Nyquist rule")  ·  *source: gsd-core*  ·  **ADOPT**
- **Why:** `skills/writing-plans/SKILL.md` carries shadow paths + error maps (failure enumeration) but per-task *machine-checkable acceptance* is not in the TASKS.md schema; verification is a separate end-of-sprint skill. gsd requires every task to carry a runnable `<verify>` (<60s, distinguishes pass/fail) + measurable `<done>`, and if no test exists yet, scaffolds it in an earlier wave.
- **Concrete change:** Add required `verify:` (command) and `done:` (criteria) fields to the TASKS.md task schema authored by `skills/writing-plans/`; add the "no test yet → create it in an earlier wave" rule; have `agents/integration-verifier.md` + `verification-before-completion` consume `verify`. (TASKS.md is runtime-authored, so the change lives in the skill, not a static file.)
- **Verification:** Retrofit an existing sprint; confirm each task's `verify` command runs and gates completion, and a testless task spawns an earlier scaffolding task.
- **Verdict:** **ADOPT** — converts Triforge's prose completion checklist into per-task executable gates; complements shadow-path tracing rather than replacing it.

#### C9 — Red-green-**revert** proof + verify-subagent-via-VCS-diff  ·  *source: superpowers*  ·  **ADOPT**
- **Why:** `skills/verification-before-completion/SKILL.md` says "tests actually test behavior" but gives no procedure to *prove* it (grep-confirmed: no revert/red-green/`git diff`/self-report handling), and the orchestration path trusts subagent completion reports. superpowers mandates the regression revert cycle (Write → pass → revert fix → **must fail** → restore → pass) and "agent reports success → reconcile against `git diff` before believing it".
- **Concrete change:** Add two sections to `skills/verification-before-completion/SKILL.md`: the regression revert cycle, and "never accept a subagent's self-reported success — reconcile against `git diff` first". Reinforce in `agents/integration-verifier.md` and `agents/team-lead.md`.
- **Verification:** Plant a regression test that passes even with the fix reverted → confirm the cycle catches it. Plant a subagent that reports success but made no diff → confirm the gate flags it.
- **Verdict:** **ADOPT** — concrete, testable anti-false-completion mechanisms the current checklist lacks.

### Tier 2 — ADOPT (follow-up, after Tier 1)

#### C4 — Wire `learnings-researcher` into the Phase-3 review fan-out  ·  *source: compound-engineering (narrowed by lead)*  ·  **ADOPT**
- **Why:** CE surfaces its learnings persona at plan, review, ideate, and optimize time. Triforge already invokes `learnings-researcher` broadly (grep: `commands/{plan,ship,coordinate,deep-research,compound}.md`) — so the worker's "pre-plan only" premise is wrong. The one place it is *not* present is the **Phase-3 parallel review** (alongside security-sentinel / performance-oracle), so a lesson learned in one PR does not yet change *review* behavior.
- **Concrete change:** Add `learnings-researcher` (or a distilled retrieval query) to the Phase-3 review fan-out in `commands/review.md`, passing a `<work-context>` block; optionally add a "previous-review-comments" lens (CE's `previous-comments-reviewer`).
- **Verification:** Introduce a change in an area with a prior documented learning; confirm the *review* phase cites that learning as a finding, not just the planning phase.
- **Verdict:** **ADOPT** — low effort (reuses an existing agent), surgical scope after grounding.

#### C10 — "Use when" description convention for skills  ·  *source: agent-skills + superpowers*  ·  **ADOPT**
- **Why:** With 13 skills fanned across six CLIs + 19 subagents, description collisions cause mis-routing. Triforge has no documented description convention, and at least one skill embeds workflow in its description (`verification-before-completion`'s description enumerates its triggers) — which superpowers' eval evidence says makes agents follow the blurb instead of reading the skill.
- **Concrete change:** Document in `CLAUDE.md`/a `CONVENTIONS.md` section: descriptions open third-person + contain an explicit "Use when …" trigger + list non-obvious contexts; forbid negation-only descriptions; prefer *when-to-use* over *what-it-does*. Enforced by C1's linter.
- **Verification:** Confirm each skill description contains a valid trigger (linter check); optionally measure rank-1 routing accuracy on 20 labeled prompts/skill against the standard's 80% floor.
- **Verdict:** **ADOPT** the convention + linter check; the full per-skill routing eval set is **DEFER** (see D8).

#### C11 — `agentskills.io`-spec frontmatter conformance (`compatibility` + `metadata`/`version`)  ·  *source: agent-skills*  ·  **ADOPT (partial)**
- **Why:** Triforge's skills are consumed by Claude + Antigravity/Codex/OpenCode/Kimi/Cursor — most are already `agentskills.io` standard clients. Triforge uses only `(name, description)`; the spec adds `compatibility` (declare "requires the six-CLI pool / git worktrees / coreutils `timeout`") and `metadata` (e.g. `version`, which Triforge skills lack entirely). Conforming makes Triforge skills portable into the 70+ client ecosystem and unlocks the standard validator.
- **Concrete change:** Extend each `skills/*/SKILL.md` frontmatter with optional `compatibility:` and `metadata: {version, …}`; document the field set in `CLAUDE.md`. Do **not** adopt `allowed-tools` yet (spec marks it experimental; Triforge already governs tools via agent frontmatter + `gemini-agents/policies.toml` + Codex `tools` allowlist).
- **Verification:** `skills-ref validate ./skills/<name>` passes for every skill; load one unmodified Triforge skill into a stock client (e.g. OpenCode) and confirm it activates.
- **Verdict:** **ADOPT** for `compatibility`/`metadata`/formalized limits; **DEFER** `allowed-tools`.

#### C12 — Write-time overlap/dedup detection in compounding  ·  *source: compound-engineering*  ·  **ADOPT**
- **Why:** Nothing in `skills/knowledge-compounding/` checks whether a new learning duplicates an existing `ops/solutions/` entry. Triforge's flat, date-prefixed filenames (confirmed: `ops/solutions/2026-03-24-portable-skill-injection.md`, …) make silent duplication likely; duplicates drift apart and eventually contradict.
- **Concrete change:** Add a "related-docs" step to `knowledge-compounding` that greps `ops/solutions/` before writing and scores overlap; High → update the existing file in place (add `last_updated:`), Moderate → create + flag for the C5 refresh loop, Low → create new.
- **Verification:** Compound the same problem twice; confirm the second run updates the first file instead of creating a near-duplicate.
- **Verdict:** **ADOPT** — small, high-leverage; strongest paired with C5.

#### C13 — Extend `plan-checker`'s rubric with the missing dimensions  ·  *source: gsd-core (reframed by lead)*  ·  **ADOPT (partial)**
- **Why:** The worker proposed "add a multi-dimension rubric + severity tiers", but `agents/plan-checker.md` already enumerates **6 dimensions** (Task completeness, Assignment correctness, Dependency correctness, Scope assessment, Shadow-path coverage, Architecture alignment) and a **3-tier** output (Blocking / Warnings / Suggestions) with APPROVED|NEEDS_REVISION. The real gap is the specific gsd dimensions it lacks: **requirement-coverage** (→ C18), **per-task `verify`/`done` presence** (→ C8, the Nyquist check), and **cross-plan data-contract consistency**.
- **Concrete change:** Add those 2–3 dimensions to `agents/plan-checker.md`'s existing "What to check" list, tiered into the existing Blocking/Warnings/Suggestions output (only Blocking consumes one of the max-3 iterations).
- **Verification:** Run against a plan with a missing per-task `verify` + an uncovered requirement; confirm one correctly-tiered finding per new dimension.
- **Verdict:** **ADOPT** — extends an existing agent; sequence *after* C8/C18 land (it validates their fields).

#### C14 — Machine-readable `STATE.md` frontmatter + status derivation  ·  *source: gsd-core*  ·  **ADOPT**
- **Why:** `ops/STATE.md` (via `skills/session-continuity/`) records phase/progress/next-action as prose. gsd pairs strict YAML frontmatter (`status` enum, `next_action`, `progress.percent`, `active_phase`) driving a status line + a "rebuild state from artifacts" command. `hooks/handlers/pre-compact.sh` already snapshots STATE.md, so the write-point exists. (Note: there is no `templates/ops/STATE.md` — STATE.md is runtime-authored, so the change lives in `session-continuity` + `pre-compact.sh`.)
- **Concrete change:** Teach `skills/session-continuity/` + `pre-compact.sh` to write/read a frontmatter block (`status`, `next_action`, `progress`); optionally seed a `templates/ops/STATE.md` skeleton.
- **Verification:** Pause mid-sprint → frontmatter `status` flips to `paused` with `next_action` set; resume consumes those fields.
- **Verdict:** **ADOPT** — small, self-contained; improves resumability + enables progress reporting.

#### C15 — Structured `HANDOFF.json` for the context-exhaustion outer loop  ·  *source: gsd-core*  ·  **ADOPT**
- **Why:** `scripts/coordinate.sh` recovers from context exhaustion but re-reads prose STATE.md; there is no structured resume schema. gsd's `HANDOFF.json` (machine-readable, "consumed exactly once") gives the resume path an exact anchor.
- **Concrete change:** Have `skills/session-continuity/` write `ops/HANDOFF.json` (resume point, in-progress task id, continuation instructions) on pause; have `coordinate.sh` consume-and-clear it on resume. Composes with C14 (shared resume cluster) and C16.
- **Verification:** Kill a session mid-wave; confirm `coordinate.sh` resumes at the right task from `HANDOFF.json` and marks it consumed (no double-run).
- **Verdict:** **ADOPT** — strengthens a documented mechanism that currently lacks a schema.

#### C16 — Commit-range resume ledger + structured subagent status codes  ·  *source: superpowers*  ·  **ADOPT (scoped)**
- **Why:** Triforge has `skills/session-continuity/` + STATE.md + `pre-compact.sh`, but resume is phase/task-count oriented, not an idempotent **per-task ledger keyed by commit range** that lets the controller *skip already-completed tasks* after a crash/compaction. superpowers' `.superpowers/sdd/progress.md` does exactly this; its DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED codes are more structured than Triforge's task states.
- **Concrete change:** Extend `skills/wave-orchestration/SKILL.md` + `agents/team-lead.md` to write/read a commit-range-keyed ledger in `ops/`, adopt the four status codes and the "cannot-verify-from-diff → controller reconciles" rule. Scope carefully against existing team-lead logic; relate to C14/C15.
- **Verification:** Kill a build mid-wave, resume, confirm completed tasks are *skipped* (not re-run) and a BLOCKED subagent halts dispatch.
- **Verdict:** **ADOPT** — concrete durability win composing with existing continuity primitives; scope to the delta to avoid duplication.

#### C17 — Persist the dependency graph as per-task fields  ·  *source: gsd-core*  ·  **ADOPT**
- **Why:** `skills/wave-orchestration/SKILL.md` builds the dependency graph at *runtime* ("Step 1: Build the dependency graph") from task rows; the DAG + wave assignment aren't durably stored, so they're recomputed and not resumable/inspectable. gsd bakes `wave`/`depends_on`/`files_modified` into each plan's frontmatter.
- **Concrete change:** Extend the TASKS.md schema authored by `skills/writing-plans/` with per-task `wave:`, `depends_on:[ids]`, `files_modified:[paths]`; have `skills/wave-orchestration/` consume `depends_on` + apply the `wave = max(deps)+1` formula rather than re-deriving grouping. (`files_modified` also feeds C13's overlap dimension and D4.)
- **Verification:** Author a TASKS.md with a known DAG; confirm wave-orchestration reproduces identical wave numbers deterministically from the fields.
- **Verdict:** **ADOPT** — durability/resumability/inspectability win for the parallel builder pool; pairs with C16.

#### C18 — Numbered requirement IDs + coverage checking  ·  *source: gsd-core*  ·  **ADOPT (multi-phase) / DEFER (small-fix fast path)**
- **Why:** `agents/plan-checker.md` validates TASKS.md but has no numbered requirement IDs traced goal→task, nor a coverage check. gsd numbers criteria (`AUTH-01`), threads them into `requirements:`, and fails any uncovered requirement (checker Dimension 1).
- **Concrete change:** Add numbered requirement IDs to `ops/GOALS.md` (or a new `ops/REQUIREMENTS.md`); add `requirements:[ids]` to the TASKS.md task schema (`writing-plans`); add the coverage dimension to `plan-checker` (see C13).
- **Verification:** Author a goal with 5 numbered requirements, drop one from all tasks, confirm plan-checker flags the gap.
- **Verdict:** **ADOPT for multi-phase builds / DEFER for the small-bug-fix fast path** — gate behind sprint size so it doesn't tax Phase-0-skippable small fixes.

### Tier 3 — DEFER (revisit next cycle or on trigger)

Each still carries the full four fields, compactly.

#### D1 — Retrieval-oriented controlled frontmatter + category tree  ·  *compound-engineering*  ·  **DEFER**
- **Why:** Triforge's `ops/solutions/` frontmatter is provenance-oriented (who/when/sprint); CE's is retrieval-oriented (controlled `problem_type`/`component`/`tags` enums + category dirs) for reliable grep-first pre-filtering at scale. **Concrete change:** layer a controlled-vocabulary `schema.yaml` on top of existing provenance fields + an optional `ops/solutions/<category>/` convention. **Verification:** 20 tagged learnings → `learnings-researcher` returns the right 3–5 via frontmatter grep without reading every file. **Verdict:** **DEFER** — schema churn + migration of existing entries; do after C5/C6/C12, and tune enums to Triforge's plugin domain (CE's are Rails-flavored — don't copy verbatim).

#### D2 — Cross-CLI session-history auto-mining  ·  *compound-engineering*  ·  **DEFER**
- **Why:** Capture is a deliberate step in both frameworks; CE compensates by mining prior session transcripts (Claude/Codex/Cursor/Pi JSONL) to recover uncaptured learnings — a fit for Triforge's six-CLI pool. **Concrete change:** port CE's `session-history/` scripts + a read-only `session-historian` subagent into `knowledge-compounding`, taught Triforge's CLIs' log formats. **Verification:** solve a problem across two CLI sessions; confirm the probe surfaces the earlier dead-ends into "What Didn't Work". **Verdict:** **DEFER** — real engineering (six distinct transcript formats); some of this may already live in `ops/MEMORY.md`/`CHANGELOG.md`. Revisit after C5/C6.

#### D3 — Discoverability self-check + `CONCEPTS.md` glossary  ·  *compound-engineering*  ·  **DEFER**
- **Why:** CE edits `AGENTS.md`/`CLAUDE.md` after writing so the store stays findable, and grounds retrieval in a shared vocabulary. Triforge's always-on pre-plan `learnings-researcher` already partly covers discoverability. **Concrete change:** a post-write check confirming `templates/CLAUDE.md`/`AGENTS.md` describe `ops/solutions/`; maintain `ops/CONCEPTS.md` glossary read first by `learnings-researcher`. **Verification:** strip the store mention from a test CLAUDE.md → check re-adds one line; synonym query resolves via glossary. **Verdict:** **DEFER** — polish; sequence behind the correctness/maintenance candidates.

#### D4 — Same-wave `files_modified`-overlap invariant  ·  *gsd-core (downgraded by lead)*  ·  **DEFER**
- **Why:** The worker framed this as a concurrent-write **correctness** fix, but `skills/wave-orchestration/SKILL.md` already isolates each builder in its own worktree lease ("overlapping-directory isolation is automatic"), so writes don't race. The residual benefit is only catching a *logical* same-file edit earlier (at plan time) instead of at wave-integration merge time. **Concrete change:** add an overlap check to `plan-checker` using C17's `files_modified` field (demote the later task a wave). **Verification:** two dependency-free same-file tasks → plan-checker flags or one is demoted. **Verdict:** **DEFER** — worktree isolation already provides the safety; adopt only alongside C17 as an earlier-conflict-detection optimization.

#### D5 — Declarative gate predicates for the ship loop  ·  *gsd-core*  ·  **DEFER**
- **Why:** Triforge's 5 quality gates are prose; completion gating runs through `scripts/coordinate.sh` + the `ops/.sprint-complete` sentinel (the ship-loop Stop hook is gone — §5). gsd models gates as declarative `command-exit-zero` predicates at named loop points. **Concrete change:** an `ops/gates.json` mapping loop points → runnable commands, consumed by `coordinate.sh`/the sentinel path. **Verification:** an `npm test` gate at build:post — red blocks, green passes. **Verdict:** **DEFER** — overlaps the existing sentinel mechanism; adopt only if Triforge wants declarative gates. Medium effort.

#### D6 — Formalize CLI compat notes into a capability matrix  ·  *gsd-core*  ·  **DEFER**
- **Why:** Triforge tracks per-CLI min versions in prose (Codex ≥0.128.0, Gemini ≥0.39.0) + ad-hoc feature detection in `invoke-external.sh`. gsd declares Role/Tier/Host-compat with `engines.*` semver gates + SHA-512 integrity. **Concrete change:** a declared `capabilities.json` consumed by `invoke-external.sh` feature detection, replacing scattered prose. **Verification:** point at an under-min CLI → matrix refuses/falls back deterministically. **Verdict:** **DEFER** — larger architectural lift; current feature detection + `scripts/probe-capabilities.sh` already work.

#### D7 — Debugging companion techniques (condition-based waiting + polluter bisection)  ·  *superpowers*  ·  **DEFER**
- **Why:** `skills/systematic-debugging/` already has root-cause + 5-whys + 3× kill criterion (good parity). It lacks superpowers' `condition-based-waiting.md` (replace `sleep`s with polling) and a `find-polluter.sh` test-bisection script — both cut flaky-test churn in Triforge's Codex-driven loop. **Concrete change:** add companion files under `skills/systematic-debugging/`, referenced via lazy `**REQUIRED SUB-SKILL:**` markers. **Verification:** seed a sleep-based flaky test + a state-polluting test; confirm the techniques locate/fix them. **Verdict:** **DEFER** — valuable but narrow; adopt after Tier 1–2.

#### D8 — Behavioral (Tier-3) eval harness with adversarial fixtures  ·  *agent-skills*  ·  **DEFER**
- **Why:** Triforge has quality *gates* but no evidence its skills change agent behavior. agent-skills materializes fixtures into throwaway git repos, runs the agent, and grades whether the workflow held — including under "authority pressure" (maps onto Triforge's skip-under-pressure risk). **Concrete change:** `evals/cases/*.json` + `evals/fixtures/` + a runner à la `scripts/run-evals.js`. **Verification:** run the behavioral eval for `test-driven-development`/`verification-before-completion`; confirm the agent writes the failing test / produces evidence under a planted authority-pressure fixture. **Verdict:** **DEFER** — high value, high effort; sequence after C1 (structural) + C10 (routing) land as cheaper prerequisites.

#### D9 — Progressive-disclosure split for oversized skills  ·  *agent-skills*  ·  **DEFER**
- **Why:** The spec caps `SKILL.md` at <500 lines / <5,000 tokens, pushing detail into `references/`+`scripts/` with explicit load-triggers. Any large Triforge skill (candidates: `wave-orchestration`, `writing-plans`) risks context bloat on every activation. **Concrete change:** audit `skills/*/SKILL.md` line counts; for any >500 lines, move detail into `skills/<name>/references/*.md` with "Read X when Y" triggers + extract helpers into `skills/<name>/scripts/`. **Verification:** each `SKILL.md` <500 lines post-split; the agent only loads the reference file when its trigger fires. **Verdict:** **DEFER** pending a size audit — adopt only for skills that actually exceed budget; premature splitting adds indirection.

---

## 3. Cross-cutting themes

Three themes recur across all four repos and are worth reading as programs rather than isolated edits:

1. **Skill hygiene as infrastructure** (agent-skills + superpowers): a linter (C1), a description convention (C10), spec-conformant frontmatter (C11), anti-rationalization scaffolding (C2), and eventually behavioral evals (D8) form one coherent "trust your skills" workstream. C1+C2+C10 are the cheap, high-value core; the `agentskills.io` standard is the north star (most of Triforge's own CLIs already implement it).
2. **Make the knowledge loop self-correcting** (compound-engineering): Triforge already has RECORD + RETRIEVE; the mined gaps are all *quality-of-knowledge* — grounding before trust (C6), staleness maintenance (C5), dedup (C12), and wider retrieval (C4). These extend files Triforge already owns.
3. **Durable, machine-readable run state** (gsd-core + superpowers): async-job manifests (C7), per-task verify/done (C8), persisted dependency graphs (C17), STATE.md frontmatter (C14), HANDOFF.json (C15), and the commit-range ledger (C16) together make a build resumable and inspectable after a crash/compaction — the highest-leverage cluster for a six-CLI background-process orchestrator.

---

## 4. Registry health / flagged targets

**Flagged targets (continue-and-flag): none.** All four repos resolved HTTP 200, live, actively maintained (all pushed within the last two days). No 404 / rename / redirect / validation failure — the continue-and-flag path was not exercised this cycle.

**Registry provenance note (not a flag — for the next cycle):**

| Target | Registry URL | Observation | Suggested registry action |
|---|---|---|---|
| repo.gsd-core | https://github.com/open-gsd/gsd-core | Resolves 200, but is a **community fork** of the abandoned `gsd-build/get-shit-done`; default branch is `next` (not `main`); a sibling `open-gsd/gsd-pi` exists. | Add a `note = "fork of gsd-build/get-shit-done; default branch next; re-check lineage"` to the `[repo.gsd-core]` block so the next cycle watches for another move. |

The other three repos are canonical upstreams with no lineage ambiguity.

---

## 5. Grounding caveats (local doc-drift surfaced while grounding — flagged to team-lead, not a mining candidate)

While grep-grounding candidate paths, the superpowers worker flagged and I **independently confirmed** a stale-doc issue in Triforge itself:

- The root `CLAUDE.md` (and this cycle's task brief) describe `hooks/handlers/ship-loop.sh` as a **Stop hook** that "blocks premature exit during sprints" (the "inner loop"). On branch `feat/cli-modernization-builder-pool`: `find . -name 'ship-loop*'` returns **nothing**, and `hooks/hooks.json` registers only **PostToolUse / PreCompact / SessionStart** (no `Stop`). `hooks/handlers/` contains `context-monitor.sh`, `pre-compact.sh`, `session-start.sh`, `tool-failure-monitor.sh`.
- The current completion-gating mechanism is `scripts/coordinate.sh` + the `ops/.sprint-complete` sentinel, as documented in `templates/CLAUDE.md`. The v3 refactor evidently replaced the Stop-hook inner loop with the sentinel model, and the root `CLAUDE.md` was not updated.
- **Impact on this report:** candidates that touch the ship loop (D5) and any "inner loop" reference are grounded against the sentinel mechanism, not the missing hook. **Recommended follow-up (separate from adoption):** reconcile the root `CLAUDE.md` "Context management" + "Reliability patterns" sections with the actual hook set — a doc fix, likely belongs with the U16 release-hardening pass, not a repo-mining adoption.

---

## 6. Sources appendix

All URLs below were fetched from PRIMARY sources by the four read-only workers (full per-repo lists preserved from their returns).

**addyosmani/agent-skills:** repo landing + `api.github.com/repos/addyosmani/agent-skills` (+ `/git/trees/main?recursive=1`); raw `scripts/validate-skills.js`, `scripts/lib/skill-lint.js`, `docs/skill-anatomy.md`, `evals/README.md`, `evals/cases/test-driven-development.json`, `.claude/rules/skills-contributing.md`, `CONTRIBUTING.md`, `skills/test-driven-development/SKILL.md`; `agentskills.io` (home, `/specification`, `/llms.txt`, `/skill-creation/optimizing-descriptions.md`, `/skill-creation/best-practices.md`); `github.com/agentskills/agentskills` (+ `/tree/main/skills-ref`).

**EveryInc/compound-engineering-plugin:** `api.github.com/repos/EveryInc/compound-engineering-plugin` (+ `/git/trees/HEAD?recursive=1`); raw `README.md`, `CONCEPTS.md`, `skills/ce-compound/SKILL.md`, `skills/ce-compound-refresh/SKILL.md`, `skills/ce-compound/references/{schema.yaml,yaml-schema.md,grounding-validation.md,agents/session-historian.md}`, `skills/ce-compound/scripts/session-history/{discover-sessions.sh,extract-metadata.py}`, `skills/ce-plan/references/agents/learnings-researcher.md`, `docs/solutions/skill-design/discoverability-check-for-documented-solutions.md`, `skills/lfg/SKILL.md`.

**obra/superpowers:** repo landing + `api.github.com/repos/obra/superpowers` (+ `/git/trees/main?recursive=1`); raw `hooks/{hooks.json,session-start,run-hook.cmd}`, `skills/{using-superpowers,verification-before-completion,systematic-debugging,systematic-debugging/root-cause-tracing.md,brainstorming,subagent-driven-development,test-driven-development,writing-skills,requesting-code-review,receiving-code-review,dispatching-parallel-agents}/SKILL.md`, `.claude-plugin/marketplace.json`, `CLAUDE.md`.

**open-gsd/gsd-core:** repo landing (200) + `api.github.com/repos/open-gsd/gsd-core` (+ `/contents?ref=next`, `/contents/{commands/gsd,skills,.plans,docs,docs/reference,agents}?ref=next`); raw `README.md`, `.plans/1755-install-audit-fix.md`, `skills/{gsd-plan-phase,gsd-execute-phase,gsd-plan-review-convergence}/SKILL.md`, `docs/reference/{plan-md.md,gate-predicates.md,state-md.md,planning-artifacts.md,capability-matrix.md}`, `docs/whats-new-1.7.0.md`, `agents/{gsd-plan-checker.md,gsd-planner.md}`; WebSearch "open-gsd gsd-core" (fork-lineage provenance).

**Triforge grounding (local, read-only, this session):** `templates/ops/watch-registry.toml`, `commands/repo-watch.md`, `skills/watch-cycle/SKILL.md`, `ops/research/cli-updates-2026-05.md`, `skills/` + `agents/` + `hooks/handlers/` + `scripts/` + `ops/{solutions,decisions}/` + `templates/ops/` listings, and grep of `skills/{knowledge-compounding,wave-orchestration,verification-before-completion,writing-plans}/SKILL.md`, `agents/plan-checker.md`, `scripts/invoke-external.sh`, `hooks/hooks.json`.

---

## 7. Cross-checks performed

1. **Registry validation (Stage 1):** all 4 `[repo.*]` URLs validated HTTPS + public-host before dispatch; `meta.repo_count=4` matched the actual `[repo.*]` count (asserted).
2. **Primary-source discipline (R32):** every candidate traces to a repo's own file/tree/spec, not worker memory — cross-checked that each worker returned a Sources list and that load-bearing schema facts (gsd plan frontmatter, the `wave=max(deps)+1` formula, CE's 5-outcome refresh model, agent-skills' linter checks) were corroborated across ≥2 files or by direct raw-file fetch.
3. **Gap grounding (Stage 4):** every "Concrete change" path was grep-verified against the working tree — this caught four worker over-claims (learnings-researcher wiring, worktree write-safety, plan-checker's existing rubric, the `status:` field) and one Triforge doc-drift (ship-loop.sh), all corrected inline above.
4. **Untrusted-evidence handling (KTD-11):** all four workers reported no injection targeting them; the forceful agent-directive text they quoted (superpowers' "YOU DO NOT HAVE A CHOICE", CE's session-historian "Never write any files", gsd's plan-checker "Assume every plan is flawed") was confirmed to be each product's own payload and treated as data — no worker acted on any of it.
5. **Recommend-only invariant (R31):** `git status` confirms no source file was modified by this cycle — only this report is added (plus pre-existing concurrent-agent noise on `ops/STATE.md`). Every verdict is a recommendation for a later, user-approved sprint.
6. **Continue-and-flag coverage:** all 4 targets resolved; the flag path was not needed, and its absence is itself recorded (§4) rather than left implicit.
