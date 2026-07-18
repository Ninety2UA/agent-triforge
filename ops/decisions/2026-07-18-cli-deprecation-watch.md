# ADR: CLI deprecation watch — six-CLI update cycle 2026-05-12 → 2026-07-18

**Date:** 2026-07-18
**Status:** Accepted (Triforge v3.0.0 forthcoming)
**Tested against:** Codex 0.144.4, Antigravity `agy` 1.1.3 (1.1.4 released 2026-07-18 — re-probe pending, D-018), Claude Code 2.1.212, OpenCode 1.18.3, Kimi Code 0.15.0 (installed; 0.27.0 latest), Cursor `2026.07.16-*`

## Context

Gap-analysis report `ops/research/2026-07-18-cli-updates.md` audited the first cycle since the May 2026 audit, now over **six** CLIs (the registry grew from two to six: Claude Code, Antigravity, Codex, OpenCode, Kimi Code, Cursor). This is also the **first live run of `/cli-watch`**. Unlike the May cycle — which found live breakage to patch — most of this cycle's findings are **already resolved** by the in-flight v3.0.0 modernization (units U1–U13); this ADR records those as ratified decisions, adds the **new/forward** verdicts this cycle surfaced, and maps which May decisions still stand.

Capability claims rest on the U1 machine probe record `ops/research/2026-07-probe-record.md` (30 PASS / 14 FAIL / 1 AUTH-FAIL / 1 PENDING). Per the watch-cycle method, a verdict that flips a prior ADR must cite a re-run probe row; the D-004 reversal does (CDX-04) and is recorded in full in its own ADR — this one references it rather than duplicating it.

> **Probe-record note (first-run method deviation).** Stage 6 of `commands/cli-watch.md` says to re-run `scripts/probe-capabilities.sh`. In this orchestrated first run the probe record was already generated fresh this cycle (2026-07-17, U1) and the run was scoped to author only the report + this ADR, so the existing record is **cited, not regenerated** (re-running would rewrite a file outside this run's scope and could collide with concurrent units). Recorded as a `/cli-watch` refinement (see the report's method notes).

## Decisions

### D-004 (reversed). Codex hooks under `codex exec` — **ADOPT** (ratified; recorded separately)

Reverses May's D-004 DEFER. Hooks **fire** under `codex exec` on 0.144.4 (probe **CDX-04**) with the nested `hooks.json` shape + project-tier `.codex/hooks.json` + `--dangerously-bypass-hook-trust`. Shipped: `templates/.codex/hooks.json` (PostToolUse attribution) + conditional flag in `invoke_codex`. Full record + preconditions + verification table in `ops/decisions/2026-07-18-codex-hooks-under-exec.md` — not duplicated here. Affects: `templates/.codex/hooks.json`, `scripts/invoke-external.sh`, `hooks/handlers/session-start.sh`.

### D-009. Gemini CLI → Antigravity (`agy`) lane migration — **ADOPT** (done)

Gemini CLI's hosted consumer service stopped **2026-06-18** with no grace period ([Discussion #28017](https://github.com/google-gemini/gemini-cli/discussions/28017); [Google deprecation page](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals)); Antigravity CLI is the designated successor. Enterprise + API-key auth are unaffected and the OSS `google-gemini/gemini-cli` repo is **not archived** (v0.51.0), so legacy users can pin plugin v2.4.3 — but the strategic direction is `agy`. Triforge replaced the Gemini lane: `scripts/invoke-external.sh:71 invoke_antigravity()` (model pin `Gemini 3.1 Pro (High)` — never the Flash default, probes AGY-02/AGY-05), the `antigravity-agents/` plugin (four migrated agent defs + `permissions.json`), and `hooks/handlers/session-start.sh:30-38` bootstrap. Retires the Gemini compatibility floor. Affects: `scripts/invoke-external.sh`, `antigravity-agents/`, `session-start.sh`, `.claude/CLAUDE.md`, `templates/CLAUDE.md`. **Supersedes** the Gemini-lane assumptions in May D-003/D-005 (see prior-decision status).

### D-010. Codex flagship `gpt-5.6-sol` — **ADOPT** (done)

Codex flagship is now `gpt-5.6-sol` (default; shipped 2026-07-09), two generations ahead of Triforge's stored `gpt-5.4`. `codex-agents/agents.toml:27,113,196` now pin `gpt-5.6-sol` at `model_reasoning_effort = "xhigh"`; `max` and `ultra` ship as commented opt-ins (probes **CDX-06/CDX-07** PASS; `ultra` fans out to internal subagents, noted inline). Affects: `codex-agents/agents.toml`.

### D-011. Structured Codex review verdicts via `--output-schema` — **ADOPT** (done)

`--output-schema` constrains the final `codex exec` message to schema-valid JSON (probe **CDX-05**), retiring the May pattern of text-scraping `ops/REVIEW_CODEX.md`. Wired as `output_schema` in `codex-agents/agents.toml:37` → `invoke_codex --output-schema` (feature-gated on `codex features list`, with a warn-and-fallback when the capability or schema file is absent). Affects: `codex-agents/agents.toml`, `codex-agents/review-verdict.schema.json`, `scripts/invoke-external.sh`.

### D-012. Optional CLI lanes — OpenCode / Kimi Code / Cursor — **DOCUMENT** (done)

Three optional-tier adapters landed (U11/U12/U13): `invoke_opencode` (`:406`), `invoke_kimi` (`:693`), `invoke_cursor` (`:1031`). Probe-grounded posture recorded so the security model is explicit: reviewer read-only rests on `--mode plan` (Cursor **CUR-08**) / prompt-level (Kimi) — **not** `--sandbox`, which **CUR-07** and **AGY-10** proved does not confine; write confinement is the lease worktree + env allowlist (R35); attribution is the U9 lead-side ledger where headless hooks are silent (**CUR-06**). Affects: `scripts/invoke-external.sh`, `session-start.sh`, roster/onboarding (U8/U17).

### D-013. Builder-pool / roster / lease-ledger + wave protocol — **DOCUMENT** (done)

U8/U9/U10 shifted multi-agent builds from ad-hoc team spawning to a **roster** (`ops/roster.toml`) + **lease ledger** (`ops/leases.toml`, gitignored runtime state) + worktree lifecycle + a builder-pool wave protocol. Probe **CC-04** confirmed Claude Code dynamic workflows can express external-CLI dispatch + requeue + a pinned reviewer; U10 dogfooded a live wave. Recorded as architecture (not a CLI-deprecation adoption). Affects: `ops/roster.toml`, `ops/leases.toml`, `skills/wave-orchestration/`, `agents/team-lead.md`.

### D-014. Compatibility floors re-baselined — **DOCUMENT** (done)

`.claude/CLAUDE.md:310-314` now declares: **Codex ≥ 0.144.0** (`--output-schema`, `codex features list`, hooks-under-exec), **Antigravity `agy` ≥ 1.1.3**, **Claude Code ≥ 2.1.212** (session caps / monitors; `/goal`, workflows, worktree isolation landed earlier). Older versions degrade via documented fallbacks. **Supersedes May D-008** (Codex ≥ 0.128.0 / Gemini ≥ 0.39.0). The `agy` floor bump to 1.1.4 is gated on D-018's re-probe.

### D-015. Codex `multi_agent_v2` / path-based addressing — **DEFER**

Still `under development / false` in `codex features list` (probe appendix A). Open bug **#31097**: GPT-5.5/5.6 force `multi_agent_v2` on despite `features.multi_agent_v2=false`, and `-c` override is ignored for those models. Path-based inter-agent addressing (May report candidate) is not adoptable while experimental **and** while the flag is silently overridden for the exact models Triforge runs. `permission_profile` inside `[agents.<name>]` also **still does not exist** (config-reference verified) — the May report's candidate #5 remains un-specced. Revisit on `multi_agent_v2` stable graduation. No change.

### D-016. Mythos 5 model tier — **DEFER**

Claude Mythos 5 (`claude-mythos-5`) is **invitation-only** (Project Glasswing), not GA. Fable 5 (`claude-fable-5`, GA 2026-06-09) is Triforge's GA ceiling and is already the lead + never-downgrade-trio spawn override when probe **CC-02** shows it available. Revisit on Mythos 5 GA. No change.

### D-017. Repo-mining adoptions (four seeded `[repo.*]`) — **DEFER (pending U15b)**

The adopt/defer verdicts for the four mined repos (`addyosmani/agent-skills`, `EveryInc/compound-engineering-plugin`, `obra/superpowers`, `open-gsd/gsd-core`) are produced by the **sibling `/repo-watch` run (U15b)**, which recommends-only and writes its own report. This `/cli-watch` ADR does not pre-empt them. Consume U15b's report in a later user-approved sprint. No change this cycle.

### D-018. `agy` 1.1.4 headless `settings.json` policy enforcement — **DEFER (re-probe next cycle)**

`agy` 1.1.4 (2026-07-18, one day after the U1 probe) states headless `-p`/`--print` now honors persisted `settings.json` policies (permissions, file access, sandbox, auto-execution, artifact review) — which **may reverse probe rows AGY-08/09/10** (hooks/deny/sandbox inert on 1.1.3) and the `session-start.sh:43-45` finding that no project-tier `settings.json` lifted the headless auto-deny. Two-sided: it could add defense-in-depth headless confinement, **or** newly block `invoke_antigravity` fan-out on artifact-review/auto-execution gates. **Do not bump the `agy` floor to 1.1.4** until AGY-08/09/10 are re-probed on 1.1.4 (report candidate #1). No change until re-probed.

### D-019. Drift / doc-accuracy corrections — **DOCUMENT** (fix pending, no behavior change)

Primary-source verification this cycle surfaced stale statements to correct (report §1 findings 4, 8, 11, 12):
- Codex `--full-auto` is **deprecated (prints a warning), not removed** — correct `.claude/CLAUDE.md:147` and `scripts/invoke-external.sh:229` ("removed" → "deprecated; prefer explicit `--sandbox workspace-write`"). The **action** (explicit `-s workspace-write -c approval_policy=never`) is correct and matches current docs; only the rationale wording is wrong. May **D-001 stands**.
- `max` effort is **not Opus-only** (Fable 5 / Sonnet 5 / Opus 4.8/4.7 support it) — correct `README.md:700`.
- Codex inter-agent tool is `send_input` — Triforge already correct at `codex-agents/AGENTS.md:59`; the 2026-07-17 fact sheet's "send_message" was a fact-sheet error (no code change).
- Kimi auth is **OAuth device-code OR API key** (not API-key-only), context **256K default** (not 1M), effort a **spectrum** (not max-only), and "K2.7/K3" are marketing names absent from the CLI catalog — update enrollment notes (U12/U17).
- Registry `[cli.kimi].docs` should be `https://moonshotai.github.io/kimi-code` (the current URL is an SPA shell) — report candidate #3.

## Prior-decision status (May 2026 cycle → now)

| May decision | This cycle |
|---|---|
| D-001 replace `--full-auto` — ADOPT | **Stands** (action correct); wording fix in D-019 |
| D-002 disable Codex auto-memory — ADOPT | **Stands** — memories still off by default (CDX-02) |
| D-003 `.agents/skills/` interop — ADOPT | **Stands & broadened** — now pays off across agy + OpenCode + Kimi (`--skills-dir`) + Cursor (`.claude/skills`) |
| D-004 Codex hooks under exec — DEFER | **REVERSED → ADOPT** (this cycle, dedicated ADR) |
| D-005 Gemini hooks opt-in — ADOPT | **Retired by D-009** — Gemini lane replaced by agy; agy hooks inert headless on 1.1.3 (AGY-08), pending D-018 |
| D-006 externalize Codex agents (`config_file`) — DEFER | **Stands (DEFER)** — Triforge parses `agents.toml` itself; unchanged |
| D-007 `permission_profile` — DEFER | **Stands (DEFER/Skip)** — field confirmed non-existent upstream (D-015) |
| D-008 compatibility floor — DOCUMENT | **Superseded by D-014** |

## Verification record

Machine probes from `ops/research/2026-07-probe-record.md` (U1, 2026-07-17) backing this cycle's verdicts:

| Probe | Capability | Outcome | Date | Method |
|---|---|---|---|---|
| CDX-01 | `codex --version` | codex-cli 0.144.4 | 2026-07-17 | direct |
| CDX-02 | `codex features list` (hooks stable/true; multi_agent stable/true; multi_agent_v2 under-dev/false; memories experimental/false) | PASS | 2026-07-17 | direct |
| CDX-03 | headless READY on `gpt-5.6-sol` | PASS | 2026-07-17 | live |
| CDX-04 | hooks fire under `codex exec` (D-004 re-probe) | **PASS** | 2026-07-17 | marker-file |
| CDX-05 | `--output-schema` → schema-valid JSON | PASS | 2026-07-17 | live |
| CDX-06 / CDX-07 | `model_reasoning_effort=max` / `=ultra` accepted on `gpt-5.6-sol` | PASS / PASS | 2026-07-17 | live |
| CDX-08 | read-only sandbox rejects writes | PASS | 2026-07-17 | negative |
| AGY-01 / AGY-02 | `agy` 1.1.3; latest Pro = `Gemini 3.1 Pro (High)` (3.5 Pro GA slipped) | PASS / PASS | 2026-07-17 | direct |
| AGY-04 / AGY-05 | headless READY; explicit Pro pin accepted | PASS / PASS | 2026-07-17 | live |
| AGY-08 | hooks fire under `agy -p` (project tier) | **FAIL** (1.1.3) | 2026-07-17 | marker-file |
| AGY-09 | explicit deny survives `--dangerously-skip-permissions` | **FAIL** → adapter never passes the flag | 2026-07-17 | negative |
| AGY-10 | `--sandbox` confines writes to workspace | **FAIL** → confinement via lease worktree (R35) | 2026-07-17 | negative |
| CC-01 / CC-02 | Claude Code 2.1.212; Fable 5 available | PASS / PASS | 2026-07-17 | direct / live |
| CC-03 | `/goal` hard-gates a multi-condition checklist in `-p` | PASS | 2026-07-17 | live |
| CC-04 | dynamic workflow expresses external-CLI dispatch + requeue + pinned reviewer | PASS | 2026-07-17 | static |
| OC-01 / OC-03 | opencode 1.18.3; headless READY (`run --format json`) | PASS / PASS | 2026-07-17 | direct / live |
| OC-06 | explicit deny survives `--auto` | **FAIL** → adapter stays off `--auto` (re-probe queued) | 2026-07-17 | negative |
| KIMI-01 / KIMI-04 / KIMI-05 | kimi 0.15.0 (stale vs 0.27.0); `--skills-dir` present; headless READY | PASS / PASS / **AUTH-FAIL** | 2026-07-17 | direct / static / live |
| CUR-01 / CUR-05 | cursor `2026.07.16-*`; explicit Grok pin (never Auto) | PASS / PASS | 2026-07-17 | direct / live |
| CUR-06 | headless hook events fire | **FAIL** → U9 lead-side ledger attribution | 2026-07-17 | marker-file |
| CUR-07 / CUR-08 | `--sandbox` confines / `--mode plan` read-only | **FAIL** / PASS | 2026-07-17 | negative |

**Web verification (this cycle, primary sources, 2026-07-18)** — drift found since the 2026-07-17 fact sheets; not machine-probed, so recorded separately from the probe table:

| Claim | Result | Source |
|---|---|---|
| `agy` latest | **DRIFT → 1.1.4** (2026-07-18); headless `-p` now honors `settings.json` policies | [release 1.1.4](https://github.com/google-antigravity/antigravity-cli/releases/tag/1.1.4) |
| Claude Code latest | **DRIFT → 2.1.214** (2.1.213 skipped); `subagentStatusLine` gains reasoning-effort | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| Codex `--full-auto` | **DRIFT → deprecated (warns), not removed** | [non-interactive docs](https://learn.chatgpt.com/docs/non-interactive-mode) |
| Codex latest stable | CONFIRMED 0.144.5 (0.145.0-alpha train active) | [releases](https://github.com/openai/codex/releases) |
| Kimi latest / auth / context | **DRIFT** → 0.27.0 latest; OAuth-or-API-key; 256K context | [releases](https://github.com/MoonshotAI/kimi-code/releases) |
| Cursor latest | **DRIFT (data point)** → changelog 2026-07-17; CLAUDE.md-at-root undocumented; skills not project-only | [changelog](https://cursor.com/changelog) |

## RTN-01 resolution (scheduled-Routine delivery)

Probe **RTN-01** ("Scheduled Routine env: checkout, push/PR, binaries, non-interactive auth, research tools") was recorded **PENDING-U15**. It is now **resolved as runtime-preflight-gated**, no longer an open UNKNOWN:

`/cli-watch`'s "Headless Routine delivery (KTD-11)" section preflights the environment and **self-selects** delivery per `commands/cli-watch.md`:

| Preflight result | Delivery mode |
|---|---|
| Pushable checkout **and** vendor auth present | commit report + ADR + probe record to a dated branch, open a **PR** |
| No pushable checkout | emit the report as the **Routine's output artifact** with land-it-manually instructions |
| Pushable checkout, vendor auth absent | open a **draft PR** with live-probe-dependent verdicts marked "pending local completion" |

A missing runtime prerequisite (binary, vendor auth, or research tooling) is **fail-loud**: emit a diagnostic artifact naming the exact gap and stop — never a half-empty report at exit 0.

**Disposition:** the preflight logic is specified and shipped (U14); this **manual** first run stopped at the manual-run branch (report + ADR in the working tree, no commit). A **live scheduled Routine invocation is the definitive end-to-end test**, deferred to the first scheduled run wired via `/schedule`. RTN-01 is therefore closed as **"runtime-preflight-gated, resolved by first scheduled invocation"** — it blocks nothing.

## Open watches

| Risk | Source | Trigger to revisit |
|---|---|---|
| `agy` 1.1.4 headless `settings.json` enforcement reverses AGY-08/09/10 or regresses fan-out | upstream (agy 1.1.4) | **already triggered** — re-probe AGY-08/09/10 on 1.1.4 before any floor bump (D-018) |
| Codex 0.145.0 stable changes hook shape / `multi_agent_v2` default | upstream | 0.145.0 leaves alpha → re-run CDX-04 + CDX-02 |
| `multi_agent_v2` forced-on for GPT-5.6 despite the flag (#31097) | upstream | issue #31097 resolved, or Codex spawn addressing changes under Triforge's caps |
| Kimi near-daily cadence / AUTH-FAIL leaves lane unproven | upstream + host | enrollment adds `kimi upgrade` + live auth (KIMI-05 → PASS); registry `docs` URL fixed |
| Cursor auto-update drift + undocumented headless hook firing | upstream | `cursor-agent --version` changes flag behavior, or docs add a headless-hooks section |
| OpenCode `deny` vs `--auto` contradiction (docs vs OC-06) | upstream | OC-06 re-probe on v1.18.3 (deny survives `--auto`) or upstream bug filed |
| Gemini 3.5 Pro GA / 3.1 Pro Preview retirement moves the `agy` pin | upstream | AGY-02 re-probe shows the model list changed |
| Mythos 5 reaches GA | upstream | model overview lists `claude-mythos-5` as GA |
| Codex `--full-auto` finally hard-removed | upstream | release notes remove the flag (Triforge already passes explicit flags — no action, wording only) |

Review on every minor version bump of any registry CLI; full cycle monthly via `/schedule`.

## References

- Gap-analysis report (this cycle): `ops/research/2026-07-18-cli-updates.md`
- Dedicated D-004 reversal ADR: `ops/decisions/2026-07-18-codex-hooks-under-exec.md`
- Prior cycle: `ops/research/cli-updates-2026-05.md`, `ops/decisions/2026-05-12-cli-deprecation-watch.md`
- Machine probe record (U1): `ops/research/2026-07-probe-record.md` (probe IDs cited above)
- Grounding fact sheets: `ops/research/2026-07-17-factsheet-{antigravity,codex,claude-code,new-clis}.md`, `ops/research/2026-07-17-grounding-dossier.md`
- Method: `commands/cli-watch.md`, `skills/watch-cycle/SKILL.md`; registry `templates/ops/watch-registry.toml`
- Primary sources: full URL set in the report's §6 Sources appendix
