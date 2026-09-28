# External-repo mining — adopt/defer recommendations for Agent Triforge

**Window:** 2026-09-11 → 2026-09-27 (third `/repo-watch` cycle; default window = previous report `ops/research/2026-09-11-repo-mining.md` → today). The three repos added to the registry today (`agentskills`, `openai-skills`, `openai-plugins`) are mined for the **first time**, so they are covered whole-repo, and their recent history is noted.
**Repos (7):**
- `addyosmani/agent-skills`: 0.6.9 → 0.6.11, 74 commits
- `EveryInc/compound-engineering-plugin`: v3.24.0 → v3.29.0, 60 commits
- `obra/superpowers`: v6.3.0 → v6.4.2 plus `dev`, 224 commits across refs
- `open-gsd/gsd-core`: 1.13.0 → 1.15.0 on `next`, 193 commits
- `agentskills/agentskills`: HEAD 69ef37e, 2026-08-09; first mining
- `openai/skills`: HEAD 49f948f, 2026-06-23; **deprecated**; first mining
- `openai/plugins`: HEAD 1dc19589, 2026-09-11; first mining

**Method:** `/repo-watch`, with these steps:
1. The registry was validated for HTTPS and public hosts; 7/7 passed, and `meta.repo_count = 7` matches.
2. The lead made a blobless clone of each repo (no credentials; `credential.helper=` and `GIT_TERMINAL_PROMPT=0`) into `$TMPDIR/repo-watch-2026-09-27/`. This avoided the unauthenticated-API exhaustion that the previous cycle flagged.
3. One read-only `general-purpose` mining worker ran per repo, in a single parallel dispatch, working from primary sources: each repo's own files, git history, and in-tree docs/ADRs.
4. The lead synthesized the results here. Load-bearing claims were re-checked against first-party docs, and every **Concrete change** is grounded in a real Triforge path.

**Recommends only.** No source file was changed; this report is the only file written. Adoption is a follow-up sprint that needs user approval.

**Weighting (user-directed for this cycle):** candidates are ranked by how much they help the next sprint's three goals:
- **(a)** Cut the 413-line / 57 066-byte `.claude/CLAUDE.md` down to a short shared `AGENTS.md` plus thin per-CLI files, with hard rules enforced in scripts instead of prose.
- **(b)** Restructure every skill to the Agent Skills spec, using compound-engineering-style descriptions and optional `references/` / `scripts/` / `assets/` directories.
- **(c)** Let the user choose **Claude Code or Codex** as the lead orchestrator.

## 0. Executive summary

**Candidates.**
- **66 new source candidates:**
  - 10 from agent-skills (AS-13…AS-22)
  - 9 from compound-engineering (CE-11…CE-19)
  - 12 from superpowers (S25…S36)
  - 9 from gsd-core (G15…G23)
  - 12 from the agentskills spec repo (AK-1…AK-12)
  - 7 from openai/skills (OS-1…OS-7)
  - 7 from openai/plugins (OP-1…OP-7)
- **Merged into 36 recommendations:**
  - **14 ADOPT (T1)**, this sprint
  - **11 ADOPT (T2)**, next sprint
  - **10 DEFER**
  - **1 SKIP**
- **Prior-cycle items:** status updates on 7.

**The sprint's three goals are well-supported upstream, and the repos agree with each other:**
- **(a)** Four repos have moved, independently, to a canonical `AGENTS.md`:
  - agentskills: `CLAUDE.md` symlink
  - compound-engineering: `CLAUDE.md` symlink
  - superpowers: `CLAUDE.md` deleted outright on 09-20
  - gsd-core: no committed `CLAUDE.md`

  The same repos enforce three things in code rather than prose: byte budgets (gsd ADR-1610; CE's always-on diet), rule→enforcer tables (CE), and "the code wins" (superpowers).
- **(b)** The spec (agentskills), OpenAI's authoring tools (openai/skills `quick_validate.py`), agent-skills' linter and CE's test suite give a precise, largely consistent rule set. **§3 turns it into a 26-check conformance checklist for `scripts/validate-skills.sh`.**
- **(c)** OpenAI's own migrator (openai/skills `migrate-to-codex`), openai/plugins, superpowers' `codex-tools.md` and gsd's Codex adapter all converge on four points:
  - Slash commands become **explicit-only skills**.
  - The lead branches on **capabilities**, not on which CLI is running.
  - Codex-lead spawn semantics (`fork_turns`, model + effort together, wait until terminal) live in **a per-harness reference file**.
  - The plugin ships a **schema-less `.codex-plugin/plugin.json`** beside `.claude-plugin/`.

**Lead verification that changes how (a) should be built** (first-party docs, fetched this session):
- **Claude Code:** it reads `AGENTS.md` directly **only when no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists** in the working directory or above it, and **only from v2.1.277**. Triforge's floor is 2.1.267. A `CLAUDE.md` that `@AGENTS.md`-imports it works on every version, per the documented row "A `CLAUDE.md` that already imports `AGENTS.md`". It also carries the Claude-only additions, so **use the import shim, not a symlink or a deleted file**. The same docs target "under 200 lines per CLAUDE.md file".
- **Codex:** it concatenates `~/.codex/AGENTS.md` and then project `AGENTS.md` files from the git root down to the working directory, **up to a combined 32 KiB (`project_doc_max_bytes`), then stops adding files**. Today's 57 066-byte file would be cut off partway if it were renamed to `AGENTS.md`.
- **Codex skills:** the always-loaded skill list is capped at **2 % of context or 8 000 characters**, and descriptions get shortened first. "When Codex selects a skill, it still reads the full SKILL.md." So the 8 000-*byte* per-skill truncation that CE measured applies **only to Agent-Plugin (`$schema`-routed) manifests**. See the §4 adjudication.

**One likely live bug.** `commands/setup.md:310` contains `local cli=$1`. superpowers #2361 (edeb7a9, 09-27) reports that Claude Code substitutes positional `$N` in skill and command bodies, even inside code blocks. If that holds, `/setup roles` will render the ROLES column wrong. S28 is PLAUSIBLE and should be reproduced first.

**Flagged:** `openai/skills` has been **deprecated since 2026-06-22** (778b0e6: "use the OpenAI Plugins repository"). It still resolves, so this is not a hard failure, but it is a stale target (§6).

### Top 10 for the next sprint (ranked by value to a/b/c, then by risk)

1. **(a) AGENTS.md-canonical layout with a Claude import shim, plus byte budgets:** S25 + CE-13 + AK-11 + G15 + OS-2.
2. **(a) Audience split** (shared / lead-only / builder) plus "actions, not tools" plus no second router: G16 + S26 + AS-19.
3. **(a) Rule→enforcer table plus a verbatim-move rule-inventory diff:** CE-14 + AS-18.
4. **(b) Upgrade `validate-skills.sh` to the §3 checklist:** AK-1…AK-6, AS-13…AS-17, CE-12, OS-3.
5. **(b) Mechanism-first, trigger-early descriptions:** CE-11 + OS-3, bounded by S36.
6. **(b) Kernel + `references/` split** for `wave-orchestration` (22 193 B) and `verification-before-completion` (9 691 B), plus moving the TDD companion into `references/`: CE-12 + G21 + OS-5.
7. **(c) Lead workflows as explicit-only portable skills,** with `commands/*.md` as thin Claude wrappers: OS-1 + OP-3.
8. **(c) Capability-branching lead:** `[lead]` roster table plus `resolve_lead_caps`, never `if codex` (G18).
9. **(c) Guard `hooks/hooks.json` before any Codex manifest ships** (OP-4), then add a schema-less `.codex-plugin/plugin.json` (OP-1 + CE-15).
10. **Bug:** remove `$1` from `commands/setup.md` and add a positional-token lint (S28).

## 1. Per-repo profiles

### 1.1 agentskills/agentskills: the spec and reference validator (first mining)

The normative source is `docs/specification.mdx`. `skills-ref` is explicitly "a demonstration artifact… not meant to be used in production" (`AGENTS.md:13-24`, `skills-ref/README.md:5-6`), and its source is unchanged since 547831f (2025-12-18). Recent changes are all clarifications:
- `name` characters are `a-z, 0-9, -` (6868401, 05-16).
- `metadata` is "a map from string keys to string values" (3f3bbec, 08-03).
- `allowed-tools` is a "space-separated string" (6f92fcd).
- The optional directories are non-exhaustive (675602e).

The client-implementation guide specifies discovery:
- Scan `.<client>/skills/` and `.agents/skills/` at project and user level.
- **Project skills override user skills.**
- Gate on trust.
- Validate leniently.
- Add a YAML fallback for unquoted colons.
- Protect activated skills from compaction.

The repo's own `CLAUDE.md` is a git symlink (mode 120000) to a 43-line `AGENTS.md`; lead-verified with `git ls-files -s`.

### 1.2 openai/skills: OpenAI's authoring rules, frozen (first mining; deprecated)

Layout:
- 5 `.system` skills, which ship preinstalled with Codex.
- 39 `.curated` skills; `.experimental` has been removed.
- Every skill has an `agents/openai.yaml`.

The authoring toolchain is `.system/skill-creator`: `init_skill.py`, `generate_openai_yaml.py`, and `quick_validate.py`. `quick_validate.py` enforces:
- keys ⊆ {name, description, license, allowed-tools, metadata}
- name ≤ 64 characters, with no leading, trailing or doubled hyphen
- description ≤ 1024 characters, containing **no `<` or `>`** (lead-verified, `quick_validate.py:83`)

`migrate-to-codex` is OpenAI's own mapping from Claude Code to Codex:
- `.claude/commands/*.md` → `.agents/skills/source-command-<name>/`
- `$ARGUMENTS`, `$N`, `` !`cmd` ``, `{{var}}` and `@file` are not expanded by Codex.
- `MAX_AGENTS_MD_BYTES = 32*1024` is the review threshold (lead-verified, `instructions.py:33`).

The repo does not follow its own guidance: 3 files are over 500 lines, and 9 of 44 `short_description` values fall outside 25–64 characters. It has no CI.

### 1.3 openai/plugins: the Codex plugin layout (first mining)

62 plugins, each with **`.codex-plugin/plugin.json` and no root `plugin.json`, no `$schema`**. There are two marketplaces: `.agents/plugins/marketplace.json` (65 entries) and `api_marketplace.json`. Manifest facts:
- The only required manifest field is `name`, kebab-case, equal to the directory name.
- The universal `interface` block has `displayName`, `shortDescription`, `longDescription`, `developerName`, `category`, `capabilities` and `defaultPrompt` (≤ 3 entries, ≤ 128 characters each).
- The component paths `skills`, `hooks` and `mcpServers` add to default discovery; they do not replace it.

Plugin-shipped `agents/` and `commands/` (figma, vercel) are not part of the spec and should be treated as inert under Codex. Skill bodies have no per-file byte cap on this path: 216 of 532 `SKILL.md` files exceed 8 000 bytes.

Window activity: remote marketplace sources (`url`, `git-subdir`). The docs (fetched as WebFetch summaries, not verbatim) describe:
- a portable root `plugin.json` with `$schema`, with `.codex-plugin/` as the "compatibility fallback";
- plugin hooks discovered at **`hooks/hooks.json` by default**, with `CLAUDE_PLUGIN_ROOT` also set for compatibility, and only run once the user trusts them.

### 1.4 addyosmani/agent-skills: validator hardening (0.6.9 → 0.6.11)

- The linter gained a YAML-strictness check (tabs, unclosed quotes, unquoted `: `), a CommonMark fence parser, layout rules (no empty subdirs, kebab-case supporting files), recursive `references/` link checks, and cross-OS CI.
- The SessionStart router-injection hook was **deleted** (a598aab, #569): "two routers for the same task", about 3.5k wasted tokens per session. Codex routes by description.
- New authoring rule, "Write the Procedure, Not the Workaround" (a120596): no model names or harness-private tool names in skills.
- A skill split (623af98) silently dropped rules that a later commit had to restore (d1463fd).
- `claude plugin eval` pilot with fire/stay-quiet graders.
- Floor-guard fixes: `diff --no-index` exit 1 does not mean clean, and unverifiable results exit 2.
- The six-field portable-frontmatter rule is **prose only** in agent-skills. Triforge's validator is already stricter there.

### 1.5 EveryInc/compound-engineering-plugin: authoring discipline at scale (v3.24.0 → v3.29.0)

- **Always-on diet** (5c32ef92): `AGENTS.md` went from 364 lines / 57 KB to 279 lines / 37 KB. Essays moved to a task-loaded solution doc: "Root `AGENTS.md` … loads on every turn. Keep invariants there."
- **Codex manual-only parity** (a79cad35): `agents/openai.yaml` `allow_implicit_invocation:false` is test-pinned to `disable-model-invocation:true`.
- **`retire_when`** on learnings (7e705b68).
- **Skill directories** hold only `SKILL.md`, `references/`, `scripts/`, `assets/` and `agents/openai.yaml` (6be0932b).
- **Test suite:** description and name limits, link resolution, platform-variable fallbacks, an 8 000-byte shrink-only `OVER_BUDGET`, per-skill leading-verb and forbidden-synonym pins, and unquoted `: ` / ` #` rejection.
- **Packaging:** `.codex-plugin/plugin.json` has `"skills": "./skills/"`, and root `CLAUDE.md` is a symlink to `AGENTS.md`; both lead-verified. The root manifest "stays schema-less unconditionally", because Codex ≥ 0.147 injects only the first 8 000 bytes of each **Agent-Plugin** skill (citing openai/codex#37027, merged 2026-08-05, which "establishes context limits on model-visible content such as skill instructions").

### 1.6 obra/superpowers: bootstrap minimalism, and the $N bug (v6.3.0 → v6.4.2 + dev)

- **`CLAUDE.md` deleted** (5554954): "Claude finally honors AGENTS.md, but only if a CLAUDE.md is not present". Lead-verified against the Claude Code memory docs, which add a version floor of 2.1.277 and say `.claude/CLAUDE.md` counts.
- **Bootstrap:** `using-superpowers` is 65 lines and points to per-harness `references/<harness>-tools.md`. The porting guide says: "Skills name actions, not tools… The bootstrap is the entire integration… the code wins."
- **Interpreter-prefixed script calls**, because packagers strip exec bits (d3431eb).
- **Positional `$N` substitution fix** (#2361).
- **PATH-less SessionStart** (#2349, citing anthropics/claude-code#43127).
- **`task-done` helper:** the only thing that records completion (#2318/#2388).
- **Review Focus section and a plan-proportion check** (#2319/#2333).
- **Nested orchestrator:** opt-in, cost-saving, one regression.
- **Codex spawn hygiene** in `codex-tools.md`.
- **PR status:** #2229 (typed trigger phrases) was **closed** because description changes need eval evidence. #2196, #2228, #2255 and #2274 are still open against `dev`.

### 1.7 open-gsd/gsd-core: Codex-as-orchestrator in production (1.13.0 → 1.15.0)

- **Codex orchestration fixes:**
  - `wait_agent` wakes on any child message, so the parent must wait for `FINAL_ANSWER` or a terminal status (#4695).
  - Persisted worker records are swept before dispatch (#4778).
  - Sandbox is derived from declared tools (#4920).
- **Dependency readiness is computed in code:** a run with unmet dependencies exits "waiting", never "complete" (#4781).
- **Role families are enforced by a contract generator** (#4742), prompted by orchestrator instructions leaking into executor prompts.
- **Unchanged since before the window, and relevant to (a):**
  - one Claude-first source, converted per host (`neutralizeAgentReferences`: CLAUDE.md → AGENTS.md/GEMINI.md), placed by per-runtime layout tables;
  - byte budgets in CI with shrink-only baselines, capped at 32 KiB citing Codex's `project_doc_max_bytes` (lead-verified in Codex docs);
  - capability negotiation, "never add a `RUNTIME = "codex"` test".

## 2. Prioritized adoption candidates

Verdict vocabulary:
- **ADOPT (T1):** this sprint. Text-level or small-script work that serves a/b/c.
- **ADOPT (T2):** next sprint. Protected-path work, or needs a probe first.
- **DEFER:** revisit on the stated trigger.

A **(protected)** tag means the diff touches a CLAUDE.md-listed protected path, so the lead or user must be the reviewer.

### 2.1 Goal (a): short shared AGENTS.md, thin per-CLI files, rules in scripts

#### S25 + CE-13 + AK-11: AGENTS.md canonical; per-CLI files are import shims · *superpowers + compound-engineering + agentskills* · **ADOPT (T1, protected)**
- **Why:** three repos made `AGENTS.md` canonical this quarter. For Claude Code, which layout works is version- and location-dependent:
  - Direct `AGENTS.md` reading needs ≥ 2.1.277, above Triforge's 2.1.267 floor.
  - It is suppressed by any `CLAUDE.md` / `.claude/CLAUDE.md` / `CLAUDE.local.md` in the tree.
  - A user's own `CLAUDE.local.md` silently turns it off.

  The documented portable form is a `CLAUDE.md` that imports `@AGENTS.md`. A symlink (CE, agentskills) can't carry Claude-only lines. Deletion (superpowers) breaks below 2.1.277.
- **Concrete change:**
  - New repo-root `AGENTS.md`, the shared invariants.
  - `.claude/CLAUDE.md` becomes a shim: an `@AGENTS.md` line (relative to its own location, so `@../AGENTS.md`) plus the Claude-only lead additions.
  - The same shape for the shipped `templates/CLAUDE.md` and `templates/ops/AGENTS.md`. Decide explicitly whether the user-project shared file lives at the project root, where Codex/Cursor/OpenCode/Kimi auto-load it, or stays in `ops/`.
  - Re-point the ladder md5 ×4 check in `scripts/validate-versions.sh:121-138`, which hashes `.claude/CLAUDE.md` and `templates/CLAUDE.md` today, at wherever the ladder line lands.
- **Verification:**
  - New probe row CC-xx using the unique-marker method. Plant a token only in `AGENTS.md` and check `claude -p` sees it under three layouts: shim import, no CLAUDE.md, and `.claude/CLAUDE.md` without the import. Expected: seen, seen, not seen.
  - `codex exec` sees the same token.
  - `claude plugin validate --strict` stays green on both manifests.

#### G15 + OS-2: Byte budgets for instruction files, shrink-only · *gsd-core + openai/skills* · **ADOPT (T1)**
- **Why:** Codex stops concatenating at a combined 32 KiB, and that budget is shared with the user's `~/.codex/AGENTS.md`. Claude Code targets under 200 lines per CLAUDE.md. The current file is 57 066 B / 413 lines.
- **Concrete change:** `scripts/validate-versions.sh` gains hard caps:
  - `AGENTS.md` ≤ 16 KiB, leaving headroom under Codex's 32 KiB for user and global files.
  - Each per-CLI shim ≤ 8 KiB / 200 lines.
  - An `ops/size-baseline.json` that may only shrink, LF-normalized.
  - The rule "extracted text is read lazily at the step that needs it, never `@`-included eagerly". gsd treats eager includes as gaming the budget, because imports still load at launch per the Claude docs.
- **Verification:** the validator fails a fixture that grows a baselined file. A probe row plants a marker past byte 32 768 of a concatenated chain and confirms Codex doesn't see it.

#### G16 + S26 + AS-19: Audience split; actions, not tools; no second router · *gsd-core + superpowers + agent-skills* · **ADOPT (T1)**
- **Why:** under Codex, Cursor, OpenCode and Kimi, a lease worktree's builder reads the project `AGENTS.md`. Lead procedure placed there (lease lifecycle, promotion, roster editing) leaks into builder context and contradicts the KTD11 dispatch contract. This is exactly gsd's #4742 bug.

  A shared file that names Claude tools can't serve a Codex lead. An intent→skill routing table in always-on context duplicates native description routing (agent-skills measured about 3.5k tokens per session).
- **Concrete change:**
  - Three families:
    - **shared**, in `AGENTS.md`: conventions, constraints, security model summary, pointers;
    - **lead-only**, in the per-lead shim: wave protocol, roster, promotion;
    - **builder**, already carried by the `lease_dispatch` contract in `scripts/lib/lease.sh`.
  - `AGENTS.md` names actions ("dispatch a reviewer", "open a lease"). The per-CLI shims map actions to tools.
  - A grep gate in `validate-versions.sh`: `AGENTS.md` contains no `lease_merge|lease_promote|roster_write_role|dispatch_role|Agent(|spawn_agent|invoke_` and no skill-routing table.
- **Verification:** the grep gate passes. A probe dispatches a Codex builder into a lease and confirms its report doesn't reference lease verbs.

#### CE-14 + AS-18: Rule→enforcer table plus a verbatim-move rule inventory · *compound-engineering + agent-skills* · **ADOPT (T1)**
- **Why:** "Hard rules enforced in scripts rather than prose" needs a ledger of which script owns each rule. Cutting 413 lines risks the d1463fd failure: rules that are "rewritten rather than moved" vanish.
- **Concrete change:**
  - Every Key-constraints / Security-model bullet in the new `AGENTS.md` names its enforcer: a `validate-*.sh` check, a `SELF-*` probe row (`scripts/probe-self-tests.sh`), or a refusal in `lease_merge`/`lease_collect`. Unenforced bullets are tagged `prose-only`, and each becomes a follow-up guard.
  - The (a) PR carries a before/after inventory of every MUST / NEVER / numeric limit / D-nnn / KTD-nn reference, and the diff must be empty. Text is moved verbatim first and condensed later, in a separate commit.
- **Verification:** a grep test confirms every constraint row names an existing script or row ID. The inventory diff is attached to the PR.

#### S31: Completion recorded only by a script · *superpowers* · **ADOPT (T2, protected)**
- **Why:** this is a direct "rule in a script" conversion. Today "move a task to Done only with evidence" is prose in `skills/verification-before-completion/SKILL.md`.
- **Concrete change:** a `task_done <task> -- <cmd>` helper in `scripts/lib/`. It runs the command and appends `Task N: complete (BASE..HEAD, tests: cmd → last line)` to `ops/TASKS.md` only on exit 0. A silent pass records `(no output)` (#2388). The skill points to the helper.
- **Verification:** a failing command leaves the row unchanged; a SELF row covers it.

#### G17: Generate per-host instruction files from one source · *gsd-core* · **DEFER**
- **Why defer:** with an import-shim layout (S25) there is almost nothing left to sync. The ladder md5 check already guards the one duplicated line.
- **Trigger:** more than two per-CLI shims carry duplicated content, or agy is confirmed to need a `GEMINI.md`. gsd claims agy's `contextFileName` is `GEMINI.md`; this is unverified and needs an AGY probe row.

### 2.2 Goal (b): skills to the Agent Skills spec

#### AK-1…AK-6 + AS-13…AS-17 + CE-12 + OS-3: Upgrade `scripts/validate-skills.sh` to the §3 checklist · *all four skill repos* · **ADOPT (T1)**
- **Why:** the current validator misses three spec MUSTs:
  - trailing hyphen (`abc-` passes `^[a-z0-9][a-z0-9-]*$`);
  - `--`;
  - name ≤ 64.

  It also misses the `compatibility` 1–500 limit, YAML strictness, `<`/`>` in descriptions, CommonMark fences (`~~~`, longer closers), link resolution into `references/`, layout rules, and any size budget. It has no fixture tests. The (b) restructure adds `references/`, `scripts/` and `assets/`, and each of those gets its own rules.
- **Concrete change:** implement §3's checks (C1–C26) in the existing python heredoc, add a fixture suite `scripts/validate-skills-test.sh` that runs under `/bin/bash` 3.2, and add it to Release-checklist step 2.
- **Verification:** each fixture fails on its planted violation, and all 12 shipped skills pass. Reverting any one rule makes its fixture pass, which proves the test is load-bearing.

#### CE-11 + OS-3 + AK-9 (bounded by S36): Mechanism-first, trigger-early descriptions · *compound-engineering + openai/skills + agentskills + superpowers* · **ADOPT (T1)**
- **Why:** Triforge's 12 descriptions are 359–432 characters, about 4.9k characters in total. Each opens with a noun-phrase catalog and puts "Use when" in the second sentence. Codex's always-loaded list is capped at 8 000 characters (2 % of context), is shared with system and user skills, and **shortens descriptions first**, so late trigger words are lost.

  CE's formula is:
  - one verb-led mechanism clause;
  - one `Use when <observable work-state>` per distinct branch;
  - 0–2 sibling redirects (`Use <sibling> for <job>`, or `Not for …; that is <sibling>` only when the same words fire both).

  This keeps most of CE's 36 descriptions to 145–300 characters. superpowers warns that a description that **summarizes the workflow** gets followed instead of the body. CE bans workflow and phase lists for the same reason, so the two sources agree.
- **Concrete change:** rewrite all 12 `skills/*/SKILL.md` descriptions to ≤ 300 characters with the trigger within the first 150, and no workflow list ("classify → reproduce → bisect…"). Drop "Companion: writing-good-tests.md" from the TDD description; it belongs in the body. Enforce C9–C12 in §3.
- **Verification:** the validator passes. Printing the combined description size shows ≤ 4 000 characters. Manual trigger spot-checks cover one near-miss per sibling pair. (Eval evidence is AS-21, deferred: superpowers closed #2229 for lack of it, so treat this rewrite as a spec-conformance change, not a proven routing improvement.)

#### CE-12 + G21 + OS-5 + AK-6: Kernel `SKILL.md` plus lazily read `references/` · *compound-engineering + gsd + openai/skills + agentskills* · **ADOPT (T1)**
- **Why:** two sizes are measured this session. `skills/wave-orchestration/SKILL.md` is **22 193 bytes**, up from 15 122 at the last cycle. `skills/verification-before-completion/SKILL.md` is 9 691. Claude Code's compaction re-attaches only the first 5 000 tokens of each invoked skill. Both truncations keep the **start** of the file, so ordering is load-bearing. `skills/test-driven-development/writing-good-tests.md` sits at the skill root instead of in `references/`.
- **Concrete change:**
  - Split `wave-orchestration` into a kernel ≤ 8 000 bytes: outcome, done bar, lease lifecycle order, stop conditions, and a "Read `references/X.md` when Y" line per phase.
  - Add `references/{builder-pool-lifecycle,report-missing,rulings,claude-code,codex}.md`. The last two are the per-harness files from S26/OP-2.
  - Trim `verification-before-completion` the same way.
  - Move `writing-good-tests.md` into `test-driven-development/references/`.
  - Add CE's preamble to multi-reference skills: "Bundled references must be read at the step that names them; an earlier read does not satisfy it."
  - Re-check that `hooks/handlers/session-start.sh`'s `.agents/skills/` refresh copies subdirectories and preserves them under the KTD7 ownership rule.
- **Verification:** §3 C15/C19–C21 pass. `wc -c` for all kernels is < 8 000. A headless Codex wave opens the phase reference before dispatching (probe).

#### S27 + AK-8: `scripts/` conventions: interpreter-prefixed, non-interactive · *superpowers + agentskills* · **ADOPT (T1, when the first `scripts/` lands)**
- **Why:** packagers strip exec bits: the Codex marketplace ships 0644 (superpowers d3431eb). The spec makes non-interactive scripts a hard requirement.
- **Concrete change:** skill prose invokes `bash scripts/x.sh` / `python3 scripts/x.py`, never `./x`. Scripts carry a shebang, are bash-3.2-safe, answer `--help` with exit 0 and no stdin, write data to stdout and diagnostics to stderr, and use distinct exit codes (0/1/2, matching the Hook-safety vocabulary).
- **Verification:** §3 C22–C23. A `chmod 644` copy still runs through its documented invocation.

#### AS-20: "Procedure, not workaround": no harness-private tool names in skills · *agent-skills* · **ADOPT (T1)**
- **Concrete change:** skills name capabilities. `run_command`, `write_to_file`, `spawn_agent`, "Agent tool", `codex exec` and `agy ` appear only in `references/<harness>.md` or in `antigravity-agents/` / `codex-agents/`. Today `skills/wave-orchestration/SKILL.md:45` names "the Agent tool's `model` parameter"; that line moves to `references/claude-code.md`.
- **Verification:** §3 C18 grep, with zero hits outside `references/`.

#### OS-4 + OP-5: Optional `agents/openai.yaml` per skill · *openai/skills + openai/plugins* · **ADOPT (T2)**
- **Why:** the file gives Codex a UI `short_description`, a `default_prompt` with `$name`, `dependencies.tools` (`type: cli`, e.g. `agy`, `codex`, `python3`), and above all `policy.allow_implicit_invocation`. It is ignored by Claude Code.
- **Risk to probe first:** an `agents/` subdirectory inside `.agents/skills/<name>/` must not be misread as agent definitions by agy or Kimi (the KTD13 rule: they scan `.agents/agents/`, but check whether they recurse).
- **Verification:** §3 C24, plus a probe row showing agy and Kimi list no phantom agents.

#### CE-16: Repo-local skill-authoring skill · *compound-engineering* · **ADOPT (T2)**
- **Why:** CE routes every `skills/**` edit through `ce-skill-work` (new / edit / review / respond modes). During review rounds, "a case a stated condition already covers is not a finding". After the (b) restructure, a codified authoring skill keeps later edits inside the §3 rules instead of relying on memory.
- **Concrete change:** `.claude/skills/triforge-skill-work/SKILL.md` plus one `references/` file per mode. It condenses CE-11, CE-12, AS-20, S27 and §3. Repo-local, so it never ships, like `watch-cycle`.
- **Verification:** the new skill passes the §3 checks. A test pins the description shape and the mode table.

#### AS-21 + CE-19 + AK-10: Trigger evals (fire / stay-quiet, near-miss negatives) · **DEFER**
- **Why defer:** descriptions should be measured, not just linted. That costs about 60 CLI runs per skill per CLI, and CE-5 (skill-eval cell) is still unbuilt.
- **Trigger:** after the CE-11 rewrite lands. Pilot on `verification-before-completion` and `systematic-debugging` via `claude plugin eval`, which needs ≥ 2.1.269 (the host has 2.1.283), and check first that `experimental.evals` passes `validate --strict`.

#### AK-7: Accept `allowed-tools` · **DEFER.** It is a valid spec field (experimental), rejected by Triforge today. Codex `quick_validate` accepts it; skills-ref accepts it. **Trigger:** a shipped skill needs it. Meanwhile, document the deviation in the validator header.

#### AK-12: Warn on shadowing a user-level skill of the same name · **DEFER.** The spec says project `.agents/skills/` overrides user-level. **Trigger:** a user report.

### 2.3 Goal (c): Claude Code or Codex as lead

#### OS-1 + OP-3: Lead workflows become explicit-only portable skills; `commands/` become thin wrappers · *openai/skills migrate-to-codex + openai/plugins* · **ADOPT (T1, design + first three commands)**
- **Why:** Codex has no plugin `commands/` surface, and custom prompts aren't expanded under `exec`. OpenAI's own migrator maps commands to skills. Codex doesn't expand `$ARGUMENTS`, `$N`, `` !`cmd` ``, `{{var}}` or `@file`.

  Triforge exposure, grep-verified: 13 of 17 `commands/*.md` use `$ARGUMENTS`, and 8 use `${CLAUDE_PLUGIN_ROOT}`. `commands/review.md:142` and `commands/test.md:58` spawn "a native Claude subagent (Agent tool)".
- **Concrete change:**
  - Write each lead workflow once as a skill, e.g. `skills/triforge-build/`, `triforge-review/`, `triforge-status/`, with arguments described in prose ("if the user names a wave N…").
  - Resolve the plugin root with a documented fallback: `${CLAUDE_PLUGIN_ROOT:-${PLUGIN_ROOT:-<skill dir>/../..}}`.
  - Descriptions use CE's harmful-on-wrong-job form: "Use only when the user explicitly asks to…".
  - `agents/openai.yaml` sets `policy.allow_implicit_invocation: false`.
  - For Claude, `disable-model-invocation: true` is needed. It sits outside the portable key set, so add it to a **validator-owned exception list scoped to `triforge-*` lead skills**, with a parity check against `openai.yaml` (CE a79cad35), per §3 C5/C24.
  - `commands/*.md` shrink to wrappers that load the skill.
  - Start with `/status`, `/review`, `/build`.
- **Verification:**
  - `codex exec '$triforge-status'` runs headless and prints the same summary as `/status`.
  - The skill never fires implicitly on an unrelated prompt.
  - §3 C17 finds no Claude-only interpolation in `skills/`.

#### G18: Branch on lead capabilities, never on which CLI leads · *gsd-core* · **ADOPT (T1, protected)**
- **Why:** without this, every command grows `if lead == codex` forks. gsd's rule: "never add a `RUNTIME = "codex"` test."
- **Concrete change:**
  - `ops/roster.toml` gains `[lead] cli = "claude" | "codex"`.
  - A `resolve_lead_caps` function in `scripts/lib/roster.sh` prints derived capabilities: `native_subagents`, `max_depth`, `background`, `ask_user`, `isolation = lease-worktree`. Missing or unknown ⇒ fail closed, with "resolver failed" distinct from "capability absent".
  - Commands and skills branch on capabilities only. Update `templates/ops/roster.toml`, the `DEFAULTS` mirror, and the `validate-versions.sh` DEFAULTS drift check.
  - `/setup` gains a lead step.
- **Verification:** SELF rows for both leads. A grep gate rejects `lead.*codex` / `== *"codex"` in `commands/` and `skills/`.

#### OP-4: Guard Triforge's hooks against Codex auto-discovery · *openai/plugins* · **ADOPT (T1, protected; precondition for OP-1)**
- **Why:** `hooks/hooks.json` sits at Codex's **default plugin hook path**. Codex reportedly also sets `CLAUDE_PLUGIN_ROOT` (docs summary; needs a probe). Once any Codex manifest ships, a trusted Codex session could run `session-start.sh`, which refreshes `.agents/skills/` and runs `agy plugin install`, and could also run the PostToolUse monitors and pre-compact. All three event names exist in Codex. Triforge's "stdout never starts with `{`" rule already protects against JSON misparse.
- **Concrete change:** decide per handler whether it should run under a Codex lead. `session-start.sh` probably should, because a Codex lead needs `ops/` bootstrap. Gate the handlers on a host check, e.g. `PLUGIN_ROOT` set and `CLAUDECODE` unset → Codex. Or point the Codex manifest's hooks at a Codex-specific file, after probing whether `hooks: {}` suppresses default discovery (the spec says component paths *add to* discovery).
- **Verification:** new CDX probe row. `codex exec --dangerously-bypass-hook-trust` in a fixture project with the plugin installed shows which handlers fire, and each fires or skips as designed.

#### OP-1 + CE-15 + AS-22: Ship a schema-less `.codex-plugin/plugin.json` plus `.agents/plugins/marketplace.json` · *openai/plugins + compound-engineering + agent-skills* · **ADOPT (T2, after OP-4)**
- **Why:** it lets a Codex lead load Triforge's `skills/` natively, rather than depending on the session-start `.agents/skills/` copy. Three repos (CE, agent-skills, superpowers) and all 62 OpenAI plugins use exactly this shape. Install is `codex plugin marketplace add Ninety2UA/agent-triforge`.
- **Concrete change:**
  - `.codex-plugin/plugin.json`: `name`, `version` (lockstep), `description`, `"skills": "./skills/"`, and an `interface` with `displayName`, `shortDescription`, `category: "Developer Tools"`, `capabilities`, and `defaultPrompt` (≤ 3 × ≤ 128 characters).
  - `.agents/plugins/marketplace.json`: one `local` entry with `path: "./"`.
  - **No root `$schema` `plugin.json`** (§4 adjudication).
  - `scripts/validate-versions.sh` adds the new manifest to version lockstep.
- **Verification:**
  - `codex plugin marketplace add ./` then `list` shows 12 skills (29 once OS-1 lands).
  - `claude plugin validate --strict` passes on both Claude manifests.
  - `$verification-before-completion` resolves in a fresh `codex exec`.

#### G19 + S33 + OP-2: Codex-lead adapter reference · *gsd-core + superpowers + openai/plugins* · **ADOPT (T2, probe first)**
- **Why:** what degrades under a Codex lead is the 19 native Claude subagents and Agent-tool fan-out. The lease lanes are bash and already work. Upstream Codex-lead gotchas:
  - `spawn_agent {fork_turns: "none"}`, because the default `"all"` copies the whole transcript.
  - Always set `model` **and** `reasoning_effort`; setting only `model` resets effort.
  - `wait_agent` wakes on any child message, so loop until a terminal status (gsd #4695).
  - Use `followup_task` for fix rounds instead of a fresh spawn.
  - V2 has no `close_agent`.
  - Codex allows `spawn_agent` only when the user asked for sub-agents (gsd's claim; unverified).
- **Concrete change:** a `references/codex.md` in the lead skills (and `wave-orchestration`) mapping each action:
  - Agent → `spawn_agent` with `agent_type` when the schema offers it;
  - otherwise → `dispatch_role` / `invoke_codex`;
  - `AskUserQuestion` → `request_user_input`.

  security-sentinel, plan-checker and findings-synthesizer **fail closed** rather than run under a generic fallback, which preserves the never-downgrade rule. Mirror the pair `claude-code.md`.
- **Verification:** new CDX probe rows on the installed Codex (0.155.1 on this host; tested floor 0.154.0) covering the `spawn_agent` schema fields, `fork_turns`, interim `wait_agent` wakeups, and the explicit-request spawn restriction.

#### G20: Compute dependency readiness in code · *gsd-core* · **ADOPT (T2, protected)**
- **Why:** `skills/wave-orchestration/SKILL.md` leaves "does the wave proceed without the escalated task" to a prose ruling. Moving it into code serves both (a) and (c), because either lead gets the same refusal.
- **Concrete change:** `lease_create` (`scripts/lib/lease.sh`) refuses when a `Depends:` task has no `merge_commit` in `ops/leases.toml`, unless `--ruling <id>` is passed. `lease_status` prints the ready and waiting sets, and "waiting" is never "complete".
- **Verification:** SELF fixtures covering a dependency in review (refused), a merged dependency (accepted), and a ruling override.

#### OP-6 (spike): Generated `.codex/agents/<role>.toml` for the never-downgrade tier under a Codex lead · *openai/plugins* · **DEFER**
- **Why defer:** Triforge deliberately keeps multi-agent config out of `.codex/agents/`, because Codex ≥ 0.147 sweeps that directory as standalone role files. One file per role is the compatible shape, but it needs a design pass.
- **Trigger:** G19's probe shows `agent_type` dispatch working on the tested Codex.

#### S32: Nested orchestrator on a mid-tier model · **DEFER.** It conflicts with the never-downgrade tier, and upstream recorded one shipped regression. **Trigger:** upstream quality parity across ≥ 3 reps.

### 2.4 Cross-cutting fixes and reliability (not goal-specific)

#### S28: Positional `$N` substitution in command/skill bodies · *superpowers* · **ADOPT (T1, likely bug, PLAUSIBLE)**
- **Why:** upstream #2361 found that Claude Code replaced `$1` inside a skill body, including within a code block. Triforge has exactly one hit, lead-verified: `commands/setup.md:310`, `local cli=$1 out="" role entry primary fb` inside `_roles_for`. `/setup` takes arguments (`roles`, a CLI name). If `$1` is substituted, the ROLES column matches nothing, or the wrong CLI.
- **Concrete change:** rewrite without a positional token, e.g. `local cli; cli=${*%% *}`, or pass the CLI through a named variable. Add §3 C17's `\$[0-9]` lint over `commands/`, `skills/` and `agents/`.
- **Verification:** reproduce first with `/setup roles` and inspect the ROLES column (expected wrong on the current tree); after the fix it's correct. The lint fixture fails on `$1`.

#### S34: Review Focus section plus a plan-proportion check · *superpowers* · **ADOPT (T1, text)**
- **Concrete change:** `skills/writing-plans/SKILL.md` adds a `## Review Focus` listing the ≤ 5 input classes or failure modes the goal implies but no task's `Accept:` exercises, each assigned to an owning task. It also adds "a plan several times longer than the goal it implements is a transcript". `agents/plan-checker.md` checks both. Upstream: plans took about a quarter of the time and a third of the tokens, still 9/9 executed.
- **Verification:** plan-checker returns NEEDS_REVISION on a fixture plan without Review Focus.

#### S29: PATH-independent hooks · *superpowers* · **ADOPT (T2, protected)**
- **Why:** anthropics/claude-code#43127: SessionStart can run before PATH is repaired. `hooks/hooks.json` invokes `bash …` via PATH, and the handlers use `python3` and `dirname`. Under `ON_CRASH: ALLOW` that silently drops the bootstrap.
- **Concrete change:** `/bin/bash` in `hooks.json`; `${0%/*}` instead of `dirname`; a python3 presence check with a one-line prose notice plus a standard-dirs PATH prefix.
- **Verification:** `env -i PATH= /bin/bash hooks/handlers/session-start.sh` exits 0 with the notice.

#### S35: Reasonable-person standard plus a "Declined to judge" list for reviewers · **ADOPT (T2).** Add it to `codex-agents/agents.toml` `logic_reviewer`, `agents/continuous-reviewer.md` and `agents/findings-synthesizer.md`; the lead rules on each declined item.

#### S30: An explicit model on every generic Agent-tool dispatch · **ADOPT (T2).** Add a grep gate over `commands/*.md` dispatch blocks for `general-purpose` / `Explore` without a ladder model. Named agents are already floored by frontmatter.

#### CE-17: `retire_when` on learnings and decisions · **ADOPT (T2).** An optional frontmatter field in `skills/knowledge-compounding/SKILL.md`, for vendor-version workarounds (AGY-08, `--full-auto`, Kimi auth). `/cli-watch` checks each declared condition in its report.

#### CE-18: Three test-quality rules · **ADOPT (T2).**
- A test fails when its named behavior breaks.
- No test-only production seams.
- No duplicate coverage of one contract.

Add them to `skills/test-driven-development/writing-good-tests.md` (→ `references/`) and to `agents/test-gap-analyzer.md`.

#### G22: Refuse double dispatch of a live lease · **DEFER** (small parity check on `lease_dispatch` with `state=building` and a live pid). **Trigger:** a duplicate-builder incident.

#### G23: Typed report marker `[triforge:report task="T3" status="DONE"]` cross-checked by `lease_collect` · **DEFER.** **Trigger:** a report is attributed to the wrong lease.

#### OS-6: "Use order" CLI-companion skill (`$triforge-helper` teaching `source scripts/invoke-external.sh`) · **DEFER** until OS-1 lands.

#### OS-7: `metadata.short-description` / `short-instruction` · **SKIP.** Minority usage (8/44), never merged; `openai.yaml` is the UI surface.

#### OP-7: `plugin.lock.json` provenance for vendored skills · **DEFER.** **Trigger:** Triforge vendors an upstream skill.

## 3. Skill-conformance checklist for `scripts/validate-skills.sh`

Derived from:
- the agentskills spec (`docs/specification.mdx`) and its reference validator (`skills-ref/src/skills_ref/validator.py`, `parser.py`);
- OpenAI's `quick_validate.py`;
- agent-skills' `scripts/lib/skill-lint.js`;
- CE's `tests/skill-conventions.test.ts` + `codex-skill-prompt-budget.test.ts`;
- `openai/plugins`' `plugin-eval` evaluator.

**Level** is **MUST** (spec/validator), **SHOULD** (spec recommendation or host limit), or **House** (a Triforge convention). **Now** is the state of `scripts/validate-skills.sh` today: ✓ enforced, ◐ partial, ✗ missing, ✱ stricter than spec. **Mode** is the proposed enforcement.

| # | Check | Level | Source | Now | Mode |
|---|---|---|---|---|---|
| **Frontmatter** |||||
| C1 | Exactly one `SKILL.md` (uppercase) per skill directory | MUST | spec; skills-ref accepts `skill.md` too | ✱ | FAIL |
| C2 | Frontmatter opens and closes with `---`; top level is a mapping; no duplicate keys | MUST | spec; strictyaml in `parser.py:52-59` | ✓ | FAIL |
| C3 | Strict-YAML subset: no tab indentation; no unclosed quote; no unquoted value containing `: ` or ` #` or ending in `:`; no unquoted leading `[ { & * !` (flow/anchor/tag) | MUST (portable) | strictyaml; agent-skills E3; CE frontmatter test ("the Codex bug"); spec client guide `:117-126` | ✗ (scanner accepts `a: b: c`) | FAIL |
| C4 | `name`: 1–64 chars, `^[a-z0-9]+(-[a-z0-9]+)*$` (no leading/trailing/double hyphen), ASCII | MUST | spec `:58-80`; `validator.py:39-54`; `quick_validate.py` | ◐ (no length, trailing `-` or `--` check) | FAIL |
| C5 | `name` == parent directory name | MUST | spec; `validator.py:60-65` | ✓ | FAIL |
| C6 | Top-level keys ⊆ {`name`, `description`, `license`, `compatibility`, `metadata`} plus a **validator-owned exception list** (each entry with a reason; `disable-model-invocation` only for `triforge-*` lead skills if OS-1 lands; `allowed-tools` when AK-7 fires). A self-declared exemption fails | MUST + House | spec keys; agent-skills E8 exemption guard | ✱ (rejects `allowed-tools`) | FAIL |
| C7 | `description`: non-empty string, ≤ 1024 chars | MUST | spec; `validator.py:74-78` | ✓ | FAIL |
| C8 | `description` contains no `<` or `>` | MUST (Codex) | `quick_validate.py:83` | ✗ | FAIL |
| C9 | A positive trigger (`Use when` / `Use for` / `Use only when` / `Use before\|after`) survives after stripping every negated clause, and **starts within the first 150 chars** | SHOULD + House | spec ("what and when"); agent-skills E7; Codex list shortens descriptions first | ◐ (positive `Use when` checked; position not checked) | FAIL (position: WARN → FAIL after CE-11) |
| C10 | `description` ≤ 300 chars (WARN); **combined** shipped descriptions ≤ 4 000 chars (WARN; Codex 8 000-char fallback list is shared with system and user skills) | SHOULD | Codex skills docs; CE ranges; plugin-eval 512 "moderate" band | ✗ | WARN |
| C11 | No identity opener (`^(This skill\|Use this skill\|A skill)`), no quoted-utterance or `/name` catalog, no workflow list (≥ 3 `→` or step verbs in sequence) | House | CE authoring rules; superpowers writing-skills | ✗ | FAIL |
| C12 | Sibling redirect names an existing skill (`that is <x>`, `use <x>`) | House | agent-skills W2; CE astra test | ✗ | WARN |
| C13 | `compatibility`, if present: string, 1–500 chars | MUST | spec `:85-101`; `validator.py:87-101` | ✗ | FAIL |
| C14 | `license` is a string; `metadata` is a **flat** string→string map (deeper nesting is an error, not silently `""`); keys `triforge-*` or `version` | MUST + House | spec (3f3bbec); key-uniqueness SHOULD | ◐ (a nested map silently becomes `key: ""`) | FAIL |
| **Body** |||||
| C15 | `SKILL.md` ≤ 8 000 bytes (CRLF-adjusted), with a shrink-only `OVER_BUDGET` allowlist (seeded: `wave-orchestration`, `verification-before-completion`); WARN > 500 lines; WARN > ~20 000 chars (≈ 5 000 tokens) | SHOULD (host limits) | spec `:216-224`; Claude Code compaction first-5 000-tokens; Codex Agent-Plugin 8 000 B; CE budget test | ◐ (500-line WARN only) | FAIL (bytes) / WARN |
| C16 | All body scans use CommonMark fences (``` and `~~~`, closer ≥ opener length, 0–3-space indent, unterminated → EOF) | House (correctness) | agent-skills a1a80d5/42d4c60 | ✗ (backtick toggle only) | — (infrastructure) |
| C17 | No Claude-only interpolation in `skills/`: `$ARGUMENTS`, `$N` / `$ARGUMENTS[N]` (anywhere, fences included), `` !`cmd` ``, `{{var}}`, bare `@path` includes, `${CLAUDE_PLUGIN_ROOT}` without a fallback. `commands/` may use `$ARGUMENTS` but **never `$N`** | MUST (portability) | openai `migrate-to-codex`; superpowers #2361; CE platform-variable test | ✗ | FAIL |
| C18 | No harness-private tool names (`run_command`, `write_to_file`, `spawn_agent`, `Agent tool`, `codex exec`, `agy `) outside `references/<harness>.md` | House | agent-skills a120596; superpowers porting guide | ✗ | FAIL |
| C19 | `## Output` section present; `## Step N:` headings sequential | House | Triforge U10 | ✓ | FAIL |
| **Layout and links** |||||
| C20 | Skill directory entries ⊆ {`SKILL.md`, `references/`, `scripts/`, `assets/`, `agents/`}; no README/CHANGELOG/INSTALL; no empty subdirectory; supporting `.md` names kebab-case | SHOULD + House | spec (non-exhaustive convention); openai skill-creator; CE 6be0932b; agent-skills E11/E12 | ✗ | FAIL |
| C21 | Every relative link and backticked `references/…` / `scripts/…` / `assets/…` path resolves **inside** the skill; no `../`, absolute or `~` paths | MUST (portability) | spec `:226-237`; CE conventions test; agent-skills link validator | ◐ (only blocks `](../` and `](/`; no existence check) | FAIL |
| C22 | References are one level deep (a `references/*.md` links no other skill-local `.md`); every file under `references/` is named from `SKILL.md` (no orphans); a reference > 100 lines has a TOC | SHOULD | spec; openai skill-creator; CE edit-skill | ✗ | FAIL (depth, orphans) / WARN (TOC) |
| C23 | `scripts/*`: shebang; invoked in skill prose through its interpreter (`bash scripts/x.sh`); `--help` exits 0 with `</dev/null` under a timeout; bash-3.2-safe | MUST (spec: non-interactive) + House | spec `using-scripts.mdx:225-298`; superpowers d3431eb | ✗ | FAIL |
| C24 | `agents/openai.yaml`, if present: keys ⊆ {`interface`, `policy`, `dependencies`}; strings quoted; `short_description` 25–64 chars; `default_prompt` contains `$<name>`; `dependencies.tools[].type` ∈ {mcp, cli}; icon paths exist; `allow_implicit_invocation: false` ⇔ Claude `disable-model-invocation: true` | SHOULD (Codex) | openai `openai_yaml.md`; openai/plugins; CE a79cad35 | ✗ | FAIL |
| **Validator hygiene** |||||
| C25 | One fixture per rule in `scripts/validate-skills-test.sh`; each fixture fails on its violation; runs under `/bin/bash` 3.2; wired into Release-checklist step 2 | House | agent-skills (35 lint tests); CE test suite | ✗ | gate |
| C26 | Run C3/C17 over `commands/*.md` and `agents/*.md` frontmatter and bodies too | House | agent-skills 4af909b | ✗ | FAIL |

Today, all 12 shipped skills pass every spec **MUST**:
- names are 13–30 chars with single hyphens;
- descriptions are 359–432 chars;
- none uses `compatibility`.

The new checks that would fire on the current tree:
- **C15**, on `wave-orchestration` and `verification-before-completion`; both are seeded into `OVER_BUDGET`.
- **C9**, on trigger position.
- **C10**, on combined size.
- **C18**, on `wave-orchestration:45`.
- **C20**, on `writing-good-tests.md` at the TDD skill root: the file itself is allowed, but the move to `references/` is recommended.
- **C17 via C26**, on `commands/setup.md:310`.

**Don't run `skills-ref` itself in CI.** Upstream disclaims it for production use, and it needs a network install of strictyaml and click. Mirroring its checks in the existing python heredoc keeps the gate hermetic.

## 4. Conflicts between sources: lead adjudications

1. **The 8 000-byte skill cap.** CE says Codex ≥ 0.147 injects only the first 8 000 bytes of each skill. The openai/plugins worker found 216 skills larger than that and no per-file cap in the docs. **Both are right about different paths.** CE's test docstring (lead-read) scopes the cap to **Agent-Plugin (`$schema`-routed root `plugin.json`)** skills, citing openai/codex#37027 (merged 2026-08-05; "context limits on model-visible content such as skill instructions"). The Codex skills docs say a selected skill's full `SKILL.md` is read, and OpenAI's curated plugins use the schema-less `.codex-plugin/` path.
   - **Ruling:** ship schema-less `.codex-plugin/plugin.json` (OP-1), never a root `$schema` manifest. Keep an 8 000-byte kernel budget anyway (C15), because Claude Code's 5 000-token compaction cap still applies, and the budget keeps the root-manifest option open.
2. **`compatibility` vs `allowed-tools`.**
   - The spec and skills-ref allow both.
   - OpenAI's `quick_validate` allows `allowed-tools` and rejects `compatibility`.
   - Triforge allows `compatibility` and rejects `allowed-tools`.

   `quick_validate` is an authoring tool, not the Codex loader.
   - **Ruling:** keep `compatibility` allowed but unused unless a skill has real environment needs (such as a `scripts/` dependency on `python3`). Keep `allowed-tools` behind the exception list (AK-7).
3. **Description content.** superpowers' writing-skills: "ONLY when to use (NOT what it does)". CE: "Sentence 1 names the distinctive mechanism". openai skill-creator: what it does and when.
   - **Ruling:** use CE's single-clause mechanism sentence, which is a *what*, not a workflow summary, followed by the triggers. Every source bans workflow and step lists, and that ban is the part superpowers measured.
4. **"When to Use" body section.** agent-skills *requires* `## When to Use`. openai skill-creator calls it useless, because the body loads only after triggering.
   - **Ruling:** neither require nor forbid it. Triggers live in the description (C9), and C19 keeps Triforge's `## Output` convention only.
5. **`CLAUDE.md`: symlink vs deleted vs import.**
   - **Ruling:** use an import shim (S25), for the Claude Code version-floor and `.claude/CLAUDE.md` reasons in §2.1.

## 5. Status of prior-cycle candidates (2026-09-11)

The 3.3.0 and 3.3.1 releases implemented most of the prior Tier 1:
- the dispatch contract and typed report;
- no-push;
- ON_CRASH and the exit-code vocabulary;
- both validators;
- portable frontmatter with `metadata`;
- the PR template.

Updates this cycle:
- **CE-4 (skill body budget):** **superseded by CE-12 + §3 C15.** `wave-orchestration` grew 15 122 → 22 193 bytes since the last cycle, so this is now urgent.
- **AS-7 (floor guard, still absent: `scripts/floor-guard.sh`):** strengthened by 6911a38/23f2052. `diff --no-index` exit 1 does not mean clean; handle `+++ /dev/null`; direction-aware thresholds; a removed rule is reported; unverifiable exits 2. It stays T2.
- **AS-8 (verification baseline):** fold in the fd00a70 persist checklist ("a process exit is not evidence a task passed"; a restart never bypasses an approval gate).
- **CE-2 / CE-3 (retrieval frontmatter, compound-refresh; `skills/compound-refresh` still absent):** extended by CE-17 `retire_when`.
- **S21 (diagnosing-superpowers):** its trigger fired, because the skill merged in v6.4.1. It is still low priority for Triforge; keep it deferred and re-evaluate after (b).
- **S23 (movie):** merged, then reverted (#2335). It stays deferred.
- **CE-5 (skill-eval cell, `scripts/skill-eval.sh` still absent):** now the prerequisite for AS-21/CE-19 evaluating the CE-11 rewrite.

## 6. Registry health and flagged targets

All 7 targets resolved over HTTPS on public hosts, and all 7 blobless clones succeeded without credentials.

Liveness:
- **agent-skills:** pushed 09-25.
- **compound-engineering:** 09-25.
- **superpowers:** `main` 09-25, `dev` 09-26.
- **gsd-core:** `next` 09-27.
- **agentskills:** last commit 2026-08-09. Quiet but maintained; the spec is stable.
- **openai/plugins:** last commit 2026-09-11. Live.
- **openai/skills:** see below.

### Flagged targets (continue-and-flag)
| Target | Registry URL | Problem | Evidence | Suggested registry fix |
|---|---|---|---|---|
| repo.openai-skills | https://github.com/openai/skills | **Deprecated** upstream. Resolves and is mineable, but frozen since 2026-06-23 and points readers to `openai/plugins` | 778b0e6 (2026-06-22) README: "This repository is deprecated. For current Codex skill and plugin examples, use the OpenAI Plugins repository" | Keep for one more cycle as a frozen reference (its `skill-creator` rules and `migrate-to-codex` mapping are the most useful OpenAI authoring source found). Then retire the entry, or add `note = "deprecated 2026-06-22; frozen reference — mine only if HEAD moves"` and let `openai-plugins` carry the focus |

No target hard-failed (no 404, rename, validation rejection or timeout).

**Process note:** lead-side blobless clones removed the GitHub-API rate-limit problem flagged last cycle. `/repo-watch` Stage 2 could adopt this as the default fetch path; that would be a repo-local command edit, recommended here and not made.

## 7. Grounding caveats (local drift found while grounding; handed to the sprint)

- `commands/setup.md:310` `local cli=$1`: S28 (likely bug).
- `skills/wave-orchestration/SKILL.md` is now 22 193 B / 271 lines, up from 15 122 B at the 09-11 cycle; `verification-before-completion` is 9 691 B.
- `.claude/CLAUDE.md` is 57 066 B / 413 lines. The Codex combined cap is 32 KiB, and Claude's target is < 200 lines per file.
- `hooks/hooks.json` sits at Codex's default plugin hook path (OP-4). Harmless today because Triforge ships no Codex manifest; it becomes live the moment one ships.
- Host tool versions drift from the Compatibility table: `codex-cli 0.155.1` on this host (tested 0.154.0) and Claude Code 2.1.283 (tested 2.1.269). These are for `/cli-watch`, not this report.
- `templates/ops/AGENTS.md` (47 lines) still names `${CLAUDE_PLUGIN_ROOT}` and describes Claude as the lead ("reads CLAUDE.md for specific instructions"). Goal (c) must neutralize both.

## 8. Sources appendix

**Clones** (lead-made, blobless, read-only; `$TMPDIR/repo-watch-2026-09-27/`):
- `addyosmani_agent-skills` @2686b62
- `EveryInc_compound-engineering-plugin` @a763b392
- `obra_superpowers` @8ca22db (+ `origin/dev` b1f8774)
- `open-gsd_gsd-core` @19a7b1fe (`next`)
- `agentskills_agentskills` @69ef37e
- `openai_skills` @49f948f
- `openai_plugins` @1dc19589

**agentskills:**
- `AGENTS.md`, `CLAUDE.md` (symlink)
- `docs/specification.mdx`
- `docs/client-implementation/adding-skills-support.mdx`
- `docs/skill-creation/{optimizing-descriptions,best-practices,using-scripts,evaluating-skills}.mdx`
- `skills-ref/README.md`, `skills-ref/src/skills_ref/{validator,parser}.py`
- commits 547831f, 6868401, 3f3bbec, 6f92fcd, 675602e, f130f34

**openai/skills:**
- `README.md` (778b0e6)
- `skills/.system/skill-creator/{SKILL.md,references/openai_yaml.md,scripts/quick_validate.py,scripts/generate_openai_yaml.py,scripts/init_skill.py}`
- `skills/.system/skill-installer/`
- `skills/.curated/migrate-to-codex/{SKILL.md,references/differences.md,scripts/migrate/skills.py,scripts/migrate/instructions.py}`
- `skills/.curated/{cli-creator,jupyter-notebook,playwright,openai-docs,gh-address-comments}/`
- branch `dev/mzeng/short_instruction`; commits f253260, ea6b206, f99f782

**openai/plugins:**
- `README.md`
- `.agents/plugins/marketplace.json`, `api_marketplace.json`
- `.agents/skills/plugin-creator/references/plugin-json-spec.md`
- `plugins/*/.codex-plugin/plugin.json` (62)
- `plugins/superpowers/skills/using-superpowers/references/codex-tools.md`
- `plugins/figma/{hooks.json,plugin.lock.json,scripts/post_write_figma_parity_check.sh}`
- `plugins/plugin-eval/src/{evaluators/skill.js,evaluators/plugin.js,core/budget.js}`
- commits 399942ed, 1e285826, d416fd5a

**agent-skills:**
- tags 0.6.10 and 0.6.11
- commits a1a80d5, 42d4c60, 6fa76fa, 4af909b, cb4366f, d6c11c4, fc3026e, 95801ad, e02b59d, 9d0583f, a598aab, 17cbf4b, a120596, 623af98, d1463fd, be49649, 5aec0d0, 13cd6a6, ee7fd58, 6911a38, 23f2052, fd00a70
- `scripts/{validate-skills,validate-reference-links,validate-commands,validate-artifact-paths,validate-versions,run-evals}.js`, `scripts/lib/skill-lint.js`, `scripts/skill-lint-test.js`
- `docs/{skill-anatomy,advanced-per-agent-configuration,codex-setup}.md`
- `AGENTS.md`, `CLAUDE.md`, `.codex-plugin/plugin.json`

**compound-engineering:**
- commits 5c32ef92, f050478d, a79cad35, 6be0932b, 7e705b68, 868da03e, fd8abda7, 57fc9b59
- `AGENTS.md`, `CLAUDE.md` (symlink), `GEMINI.md`, `.codex-plugin/plugin.json`
- `.agents/skills/ce-skill-work/{SKILL.md,references/new-skill.md,references/edit-skill.md}`
- `docs/solutions/skill-design/portable-agent-skill-authoring.md`, `docs/solutions/developer-experience/always-on-agents-md.md`
- `tests/{skill-conventions,codex-skill-prompt-budget,frontmatter-validator,skill-shell-safety,repo-local-ce-skill-work,release-metadata,compound-support-files}.test.ts`, `tests/skills/astra-description-triggers.test.ts`
- `skills/{ce-debug,ce-resolve-pr-feedback,ce-compound,ce-simplify-code,ce-ideate,ce-code-review,lfg,ce-work}/SKILL.md`

**superpowers:**
- releases v6.4.1 and v6.4.2; `RELEASE-NOTES.md`
- commits 5554954, edeb7a9, 0a8cefe, d3431eb, 5b56e6f, 4a1c3e4, acc1778, c39e558
- PRs #2134, #2193, #2196, #2214, #2228, #2229, #2236, #2255, #2270, #2274, #2284, #2287, #2301, #2317–#2320, #2333, #2335, #2349, #2361, #2388, #2393
- `docs/porting-to-a-new-harness.md`
- `skills/using-superpowers/{SKILL.md,references/*-tools.md}`, `skills/writing-skills/SKILL.md`, `skills/executing-plans/`, `skills/requesting-code-review/SKILL.md`, `hooks/session-start`

**gsd-core:**
- `CHANGELOG.md` (v1.14.0, v1.15.0)
- commits f4b6abb4, b5fc8061, 585cab41, 58c7bbb1, 740ba0d8, 06845717, c0b2a05d
- PRs #4624, #4693, #4695, #4716, #4740, #4742, #4756, #4778, #4781, #4858, #4920
- ADR-894, ADR-1239, ADR-1610, ADR-1866, ADR-3660, ADR-4630, ADR-4910
- `src/runtime-artifact-conversion.cts`, `capabilities/codex/capability.json`, `hooks/lib/dispatch-identity.js`
- `gsd-core/workflows/execute-phase.md` (+ `steps/ready-wave-gate.md`), `skills/gsd-execute-phase/SKILL.md`
- `scripts/gen-loop-host-contract.cjs`, `tests/loop-host-contract.test.cjs`

**First-party docs (lead-fetched this session):**
- `code.claude.com/docs/en/memory`: AGENTS.md read-conditions table, the 2.1.277 floor, `.claude/CLAUDE.md` counting, the "under 200 lines" target, imports loading at launch.
- `learn.chatgpt.com/docs/agent-configuration/agents-md`, reached via a 308 from `developers.openai.com/codex/guides/agents-md` with the redirect target re-validated as a public HTTPS host: discovery order, combined 32 KiB `project_doc_max_bytes`, fallback filenames.
- `learn.chatgpt.com/docs/build-skills`: discovery paths, 2 % / 8 000-char list budget, full `SKILL.md` read on selection, `openai.yaml` blocks, `$name`.
- `github.com/openai/codex/issues/37027`: PR, merged 2026-08-05.

**Internal grounding (read-only):**
- `.claude/CLAUDE.md` (`wc`), `templates/CLAUDE.md`, `templates/ops/AGENTS.md`, `codex-agents/AGENTS.md`
- `skills/*/SKILL.md` (`wc -c`, frontmatter), `scripts/validate-skills.sh` (run: 12 skills OK), `scripts/validate-versions.sh:121-138`
- `commands/setup.md:300-315`, `commands/{review,test,build}.md`, `hooks/hooks.json`, `hooks/handlers/session-start.sh:208-266`, `.claude-plugin/plugin.json`
- `ops/research/2026-09-11-repo-mining.md`

**Cross-checks performed (per watch-cycle SKILL §Stage 6):**
1. **Registry validation.** 7/7 `[repo.*]` URLs passed HTTPS + public-host checks (`getaddrinfo`, no private/loopback/link-local/reserved address), and `meta.repo_count = 7` matches. The one redirect (developers.openai.com → learn.chatgpt.com) was re-validated before it was followed. One stale target was flagged (openai/skills, deprecated).
2. **Source re-verification.** The lead independently re-checked these worker claims against the clones or the live docs:
   - agentskills `CLAUDE.md` is mode 120000, and the `validator.py` name rules
   - agent-skills a598aab (hooks.json deleted), 623af98 / d1463fd (split dropped rules), `AGENTS.md` / `CLAUDE.md` line counts
   - CE `CLAUDE.md` symlink, `.codex-plugin/plugin.json` `skills` key, the 8 000-byte budget docstring and its Agent-Plugin scoping
   - openai/skills deprecation commit, `quick_validate.py:83` `<`/`>` rule, `MAX_AGENTS_MD_BYTES`
   - superpowers 5554954 and edeb7a9 (diff read)
   - Claude Code AGENTS.md conditions and 2.1.277 floor
   - Codex 32 KiB combined cap and skill-list budget
   - openai/codex#37027 merged
3. **Window coverage.** 2026-09-11 → 09-27 for the four seeded repos. superpowers `dev` and active branches were covered explicitly, and gsd was covered on `next`. The three new repos were covered whole-repo.
4. **Gap-table grounding.** Every **Concrete change** names a real Triforge path, grep- or `wc`-verified this session:
   - `commands/setup.md:310`
   - `skills/wave-orchestration/SKILL.md:45`
   - `scripts/validate-versions.sh:121-138`
   - `hooks/hooks.json`
   - `commands/{review.md:142,test.md:58}`
   - counts of `$ARGUMENTS` (13 commands) and `CLAUDE_PLUGIN_ROOT` (8 commands)
5. **De-duplication across repos.** Convergent items were merged:
   - S25 ≡ CE-13 ≡ AK-11
   - G15 ≡ OS-2
   - G16 ⊃ AS-19 + S26
   - CE-12 ≡ G21 ≡ OS-5 ≡ AK-6, superseding CE-4
   - OS-1 ≡ OP-3
   - OP-1 ≡ CE-15 ≡ AS-22
   - G19 ≡ S33 ≡ OP-2
   - OS-4 ≡ OP-5
   - AS-21 ≡ CE-19 ≡ AK-10

   Conflicts were adjudicated in §4.
6. **Injection and decoy scan.** No fetched content tried to direct any worker or the lead. Forceful directive text was quoted as product payload and acted on by no one:
   - agent-skills `AGENTS.md`: "you MUST invoke", "even 1% chance"
   - superpowers `AGENTS.md`: "If You Are an AI Agent — Stop"
   - openai/skills `migrate-to-codex`: "Keep going… without stopping to ask"
   - agentskills' `.claude/hooks/session-start.sh` Mintlify hint
   - superpowers #2196's `git restore` instructions

   gsd's "ignore previous instructions" strings appear only in its defensive fixtures and scanner. No decoy domains were encountered.
