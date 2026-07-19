# CLI deprecation-watch — six-CLI update gap analysis for Agent Triforge

**Window:** 2026-05-12 → 2026-07-18 (67 days, the first cycle since the May audit)
**CLIs:** Claude Code (`claude`), Antigravity (`agy`, successor to Gemini CLI), Codex (`codex`), OpenCode (`opencode`), Kimi Code (`kimi`), Cursor (`cursor-agent`) — the six `[cli.*]` entries in `templates/ops/watch-registry.toml`.
**Method:** `/cli-watch` (first live run) — registry validated HTTPS/public-host (Stage 1, 18/18 URLs OK, no flagged targets), one read-only research worker per CLI verifying the 2026-07-17 grounding fact sheets against **primary sources** (GitHub `rust-v*`/tag releases, official changelogs, first-party docs), lead-synthesized here. Capability claims rest on the U1 machine probe record `ops/research/2026-07-probe-record.md` (30 PASS / 14 FAIL / 1 AUTH-FAIL / 1 PENDING). Filtered to Triforge-relevant change (categories: `command|flag|config|agent-primitive|mcp|context|hook|fs-convention|breaking|perf|model`); UI/voice/telemetry-only noise omitted.
**Versions covered:** Claude Code 2.1.139 → **2.1.214** (2.1.213 skipped); Antigravity `agy` → **1.1.4** (2026-07-18) + Gemini CLI service cutoff 2026-06-18 (OSS repo alive at v0.51.0); Codex 0.130.0 → **0.144.5** stable (+ 0.145.0-alpha train); OpenCode → **v1.18.3**; Kimi Code → **0.27.0** (near-daily cadence); Cursor → changelog **2026-07-17** (date-based, no semver).

> **Framing.** The May cycle's gap list is now almost entirely **CLOSED** — by this very effort (units U1–U13: builder-pool/roster/lease-ledger, the Antigravity lane replacing Gemini, `gpt-5.6-sol`, `/goal`+sentinel completion gating, structured Codex verdicts, the D-004 hooks reversal, and the three optional CLI lanes). This report records what closed, verifies the load-bearing facts still hold as of 2026-07-18, flags what **drifted in the 67-day window**, and prioritizes the **new/forward** items for the next cycle. The adopt/defer verdicts are in the companion ADR `ops/decisions/2026-07-18-cli-deprecation-watch.md`.

## 1. Executive summary

1. **BREAKING (service cutoff, already absorbed):** Gemini CLI's **hosted service for consumer tiers** (free, AI Pro, Ultra) stopped serving **2026-06-18** with no grace period; **Antigravity CLI (`agy`) is the designated successor** ([GitHub Discussion #28017](https://github.com/google-gemini/gemini-cli/discussions/28017); [Google deprecation page](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals)). Enterprise (Gemini Code Assist license) + API-key auth users are **unaffected**, and the OSS `google-gemini/gemini-cli` repo is **not archived** (Apache-2.0, latest v0.51.0 2026-07-16). Triforge **already migrated** the Gemini lane to `agy` (U2–U4); this report ratifies it. `[CLOSED this effort]`
2. **BREAKING → REVERSED (adoption-candidate landed):** Codex **hooks now fire under `codex exec`** on 0.144.4 (probe **CDX-04**) — reversing May's D-004 DEFER. Requires the nested `hooks.json` shape + project-tier `.codex/hooks.json` + `--dangerously-bypass-hook-trust`. Shipped this effort; recorded in the dedicated ADR `ops/decisions/2026-07-18-codex-hooks-under-exec.md`. `[CLOSED this effort]`
3. **stable → adopted:** Codex flagship is now **`gpt-5.6-sol`** (default; shipped 2026-07-09), with `max` and `ultra` reasoning tiers above `xhigh` (ultra fans out to internal subagents). Triforge moved `codex-agents/agents.toml` from the two-generations-old `gpt-5.4` to `gpt-5.6-sol` at `xhigh` (probes **CDX-03/06/07**), `max`/`ultra` shipped as commented opt-ins. `[CLOSED this effort]`
4. **DRIFT (correct the record):** Codex **`--full-auto` is NOT hard-removed** — it is a still-functional **deprecated compatibility flag that prints a warning**; the docs steer new scripts to `--sandbox workspace-write` ([non-interactive docs](https://learn.chatgpt.com/docs/non-interactive-mode)). Triforge's May D-001 **action** (pass `-s workspace-write -c approval_policy=never` explicitly) is correct and is exactly what the docs now recommend, but the **rationale wording** "v0.128.0 removed `--full-auto`" is imprecise at `.claude/CLAUDE.md:147` and `scripts/invoke-external.sh:229`. `[DRIFT]`
5. **stable → adopted:** Codex `--output-schema` gives **schema-valid JSON review verdicts** (probe **CDX-05**), retiring the May "text-scrape `ops/REVIEW_CODEX.md`" gap. Wired via `output_schema` in `codex-agents/agents.toml` → `invoke_codex --output-schema` (feature-gated on `codex features list`). `[CLOSED this effort]`
6. **stable (Claude Code):** `/goal` (v2.1.139+), dynamic **workflows**/`ultracode` (v2.1.154+, keyword renamed from `workflow` at 2.1.160), and `/schedule` → cloud **Routines** (min 1h, research preview) all verified present. Triforge's completion gating moved from `ship-loop.sh`'s `<promise>DONE</promise>` to the `ops/.sprint-complete` sentinel + `/goal` (probe **CC-03**). `[CLOSED this effort]`
7. **DRIFT (Claude Code, +1 version):** latest is now **v2.1.214** (2.1.213 never shipped). New since the fact sheet: **`reasoning effort` added to the `subagentStatusLine` payload** (renders the runtime-ladder tier per agent), an `EndConversation` tool, heavy **Bash permission-check hardening**, and a scheduled-tasks "own prompt refused as untrusted input" fix. `[new / adoption-candidate]`
8. **DRIFT (doc-accuracy):** **`max` effort is NOT Opus-only** — the `model-config` docs list `max` on **Fable 5, Sonnet 5, Opus 4.8/4.7** (and 4.6/Sonnet 4.6). The stale "max is Opus-only" note at `README.md:700` should be corrected. Does not change the downgrade ladder (bottom tier `sonnet`+`high`), but the assumption is wrong. `[DRIFT]`
9. **BREAKING (new, forward — the headline of this cycle):** **`agy` 1.1.4 shipped 2026-07-18** (one day after the U1 probe) with a directly load-bearing fix: *headless `-p`/`--print` runs now honor persisted `settings.json` policies (permissions, file access, sandbox mode, auto-execution, artifact review)* ([release 1.1.4](https://github.com/google-antigravity/antigravity-cli/releases/tag/1.1.4)). This **may reverse probe rows AGY-08/09/10** (which found hooks/deny/sandbox inert headless on 1.1.3) — and carries a **regression risk**: `invoke_antigravity`'s `agy -p` fan-out could newly block on artifact-review/auto-execution gates it previously bypassed. **Re-probe on 1.1.4 before bumping the agy floor.** `[adoption-candidate + risk]`
10. **stable (optional lanes landed):** OpenCode (v1.18.3), Kimi Code (0.27.0), and Cursor (date-based) each expose a clean headless one-shot mode and were integrated as optional-tier adapters (U11/U12/U13). Their probe-grounded posture: reviewer read-only rests on `--mode plan` (Cursor **CUR-08**) / prompt-level (Kimi) not `--sandbox` (**CUR-07**/**AGY-10** proved `--sandbox` does not confine), and attribution rests on the U9 lead-side ledger where headless hooks are silent (**CUR-06**). `[CLOSED this effort]`
11. **DRIFT (Kimi, correct the record):** Kimi Code auth is **OAuth device-code (RFC 8628) *or* API key** — **not API-key-only** as the fact sheet/probe assumed; context is **256K default** (not 1M); reasoning effort is a **spectrum** (`low…max`) not "max-only"; and the "K2.7 Code"/"K3" product names are **not in the CLI's own model catalog** (aliases are `kimi-for-coding`/`kimi-code` + a runtime-fetched managed list). The registry `docs` URL `kimi.com/code/docs` serves only an **SPA shell** — the real docs are `moonshotai.github.io/kimi-code`. `[DRIFT + registry fix]`
12. **DRIFT (Cursor, correct the record):** Cursor **does not document `CLAUDE.md`-at-root** as an instruction file (only `AGENTS.md` + `.cursor/rules/`); skills are **not project-scoped-only** (global `~/.cursor/skills/`, `~/.agents/skills/` supported); and reasoning effort **is** expressible via **model-id bracket params** (`[effort=high]`), softening the "no effort control" gap to "no standalone flag." `[DRIFT]`
13. **DEFER (unchanged forward watches):** Codex **`multi_agent_v2`** (path-based addressing) is still `under development / false` (probe appendix), with an open bug (#31097) where GPT-5.5/5.6 force it on despite the flag; **Mythos 5** is invitation-only (not GA — Fable 5 is Triforge's GA ceiling); and the **four seeded repo-mining adoptions** are produced by the sibling `/repo-watch` run (U15b), not this cycle. `[DEFER]`

## 2. Per-CLI changelog (Triforge-relevant only)

### Claude Code — `anthropics/claude-code`

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-07-18 | 2.1.214 | `reasoning effort` in `subagentStatusLine` payload (renders model+effort per agent) | agent-primitive | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| 2026-07-18 | 2.1.214 | `EndConversation` tool (end abusive/jailbreak sessions) | command | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| 2026-07-18 | 2.1.214 | Bash permission-check hardening (PowerShell 5.1, FD-redirects, >10k-char cmds, zsh `[[ ]]`, docker daemon-redirect flags now prompt) | breaking/security | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| 2026-07-18 | 2.1.214 | Scheduled task's own configured prompt no longer refused as untrusted input | config | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| ~2026-07 | 2.1.212 | Session-safety caps: WebSearch 200/session, subagent spawns 200/session (env-tunable); MCP calls >2min auto-background; `/fork` → background session | config | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| ~2026-07 | 2.1.212 | Task tool `mode` param deprecated (ignored) — subagents inherit parent permission mode | breaking-config | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| ~2026-06 | 2.1.203 | `/effort ultracode` (xhigh + standing workflow permission) | command | [docs/workflows](https://code.claude.com/docs/en/workflows) |
| ~2026-06 | 2.1.197 | Sonnet 5 becomes Claude Code default; native 1M context | model | [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) |
| ~2026-06 | 2.1.178 | Agent teams: `TeamCreate`/`TeamDelete` removed → one implicit team/session; spawn via Agent `name` | breaking-config | [docs/agent-teams](https://code.claude.com/docs/en/agent-teams) |
| ~2026-05/06 | 2.1.170 | Mythos-class model surface (Fable 5 GA 2026-06-09) | model | [models overview](https://platform.claude.com/docs/en/about-claude/models/overview) |
| ~2026-05 | 2.1.160 | Workflow trigger keyword renamed `workflow` → `ultracode` | command | [docs/workflows](https://code.claude.com/docs/en/workflows) |
| ~2026-05 | 2.1.154 | Dynamic workflows GA (16 concurrent / 1000 total agents per run); plugin `defaultEnabled:false` | command + agent-primitive | [docs/workflows](https://code.claude.com/docs/en/workflows) |
| ~2026-05 | 2.1.139 | `/goal` — completion condition judged each turn by a fast model; works in `-p`/headless/Routines | command + context | [docs/goal](https://code.claude.com/docs/en/goal) |

### Antigravity CLI (`agy`) — successor to Gemini CLI

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-07-18 | agy 1.1.4 | **Headless `-p`/`--print` now honors persisted `settings.json` policies (permissions, file access, sandbox, auto-execution, artifact review)** | breaking + config | [release 1.1.4](https://github.com/google-antigravity/antigravity-cli/releases/tag/1.1.4) |
| 2026-07-18 | agy 1.1.4 | Custom agents declaring `subagent:false` no longer appear as invocable subagents; stacked leading slash-commands in one prompt | agent-primitive | [release 1.1.4](https://github.com/google-antigravity/antigravity-cli/releases/tag/1.1.4) |
| 2026-07-16 | agy 1.1.3 | Prior release (the U1 probe target — version capture AGY-01) | — | [releases](https://github.com/google-antigravity/antigravity-cli/releases) |
| 2026-06-18 | (service) | **Gemini CLI hosted service stops for consumer tiers (free/AI Pro/Ultra); Antigravity = successor; enterprise + API-key unaffected** | **BREAKING** | [Discussion #28017](https://github.com/google-gemini/gemini-cli/discussions/28017), [Google deprecation](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals) |
| ~2026-06 | (models) | `agy` removed Gemini CLI's automatic Pro/Flash routing — a single model must be pinned; defaults to a Flash variant | config + model | [gemini-cli #27858](https://github.com/google-gemini/gemini-cli/issues/27858) |
| 2026-07-16 | gemini-cli v0.51.0 | OSS repo **not archived** — still shipping (Apache-2.0); README lags the service cutoff | fs-convention | [releases](https://github.com/google-gemini/gemini-cli/releases) |

Note (closed-source, sparse notes — per registry `note`): `agy` release bodies are terse; the service-cutoff detail comes from the maintainer discussion + Google's canonical deprecation page. Gemini 3.5 Pro is **not GA** (the model page lists 3.5 Flash *Stable*, 3.1 Pro *Preview*) — so Triforge's pin `Gemini 3.1 Pro (High)` (probe AGY-02/AGY-05) is the latest Pro `agy` exposes and correctly avoids the Flash default (never-Flash preference).

### Codex CLI — `openai/codex` (Rust workspace `rust-v*`)

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-07-17 | 0.145.0-alpha.23 | **[alpha]** next-minor prerelease train (0.145.0-alpha.13→.23) — not audited per-row | — | [releases](https://github.com/openai/codex/releases) |
| 2026-07-16 | 0.144.5 | Latest **stable**; improved dangerous-`rm` detection | perf/security | [releases](https://github.com/openai/codex/releases) |
| 2026-07-13 | 0.144.2–.4 | `spawn_agent` model / `reasoning_effort` overrides restored (partial fix for #33314) | agent-primitive | [releases](https://github.com/openai/codex/releases) |
| 2026-07-09 | 0.144.0 | **`gpt-5.6-sol/terra/luna`; first-class `max` reasoning effort; `writes` app-approval mode; remote plugins default-on** | model + config | [changelog](https://learn.chatgpt.com/docs/changelog?type=codex-cli) |
| ~2026-06 | 0.141.0 | Hook-trust bypass **persists through `codex exec` thread start AND resume** (presupposes hooks run in exec) | hook | [changelog](https://learn.chatgpt.com/docs/changelog?type=codex-cli) |
| ~2026-06 | 0.140.0 | `hooks.json` validation warnings | hook | [changelog](https://learn.chatgpt.com/docs/changelog?type=codex-cli) |
| ~2026-06 | 0.133.0–0.134.0 | `SubagentStart`/`SubagentStop` hook events + subagent identity in payloads; permission-profile inheritance | hook + agent-primitive | [changelog](https://learn.chatgpt.com/docs/changelog?type=codex-cli) |
| ~2026-05 | 0.131.0 | **`--dangerously-bypass-hook-trust`** (all exec variants — automation path); enable plugin hooks by default | hook + flag | [changelog](https://learn.chatgpt.com/docs/changelog?type=codex-cli) |
| — | (canonical) | `hooks` is the canonical config key; **`codex_hooks` is a deprecated alias**. "Hooks are enabled by default." | hook | [hooks docs](https://learn.chatgpt.com/docs/hooks) |
| — | (canonical) | `--full-auto` is a **deprecated compat flag (prints warning) — NOT removed**; prefer `--sandbox workspace-write` | flag | [non-interactive docs](https://learn.chatgpt.com/docs/non-interactive-mode) |
| — | (canonical) | `multi_agent` stable/on; **`multi_agent_v2` under development/off**; tools `spawn_agent, send_input, resume_agent, wait_agent, close_agent`; **no `permission_profile` in `[agents.<name>]`**; `/goal` not deterministic from `codex exec` (#26949 NOT_PLANNED) | agent-primitive + config | [config-reference](https://learn.chatgpt.com/docs/config-file/config-reference) |

### OpenCode — `anomalyco/opencode` (optional tier)

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-07-16 | v1.18.3 | Latest; headless `opencode run --model provider/model --format json`; `--attach http://…` to a running `opencode serve` | command + flag | [releases](https://github.com/anomalyco/opencode/releases), [docs/cli](https://opencode.ai/docs) |
| — | (docs) | Agents md+YAML (`.opencode/agents/`, global); `mode` primary/subagent/all; per-tool `permission` allow/ask/deny; built-ins build, plan (read-only), general/explore/**scout** | agent-primitive | [docs/agents](https://opencode.ai/docs) |
| — | (docs) | Skills SKILL.md discovered from `.opencode/skills`, `.claude/skills`, **`.agents/skills`** (+ globals); AGENTS.md + CLAUDE.md fallback honored | fs-convention | [docs/skills](https://opencode.ai/docs) |
| — | (docs) | `--auto` approves all-but-denied; **explicit `deny` documented to override `--auto`** (contradicts probe OC-06 — see risks) | config | [docs/permissions](https://opencode.ai/docs) |

Note: org renamed `sst/opencode` → `anomalyco/opencode`; official domain `opencode.ai` (the hyphenated `open-code.ai` is a decoy — not encountered this run). "agentskills.io standard" is **not named** in OpenCode's own docs — the interop is the de-facto SKILL.md + `.agents/skills` convention, which is what matters for Triforge (D-003).

### Kimi Code CLI — `MoonshotAI/kimi-code` (optional tier)

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-07-17 | 0.27.0 | Latest (**near-daily cadence** — 52 versions since 2026-05-22); headless `kimi -p` (stdout=assistant text, stderr=thinking); `--output-format text\|stream-json` | command + flag | [releases](https://github.com/MoonshotAI/kimi-code/releases) |
| — | (docs) | `-p` uses `auto` permission policy (static deny still enforced); cannot combine with `--yolo/--auto/--plan`; no allowlist flag; no `--sandbox` | config | [docs](https://moonshotai.github.io/kimi-code/) |
| — | (docs) | `--skills-dir <dir>` (repeatable; **replaces** auto-discovered dirs) → `.agents/skills` interop; built-in `coder`/`explore`/`plan` subagents; **no `--agent-file`** (legacy kimi-cli only) | agent-primitive + fs-convention | [docs](https://moonshotai.github.io/kimi-code/) |
| — | (docs) | Auth = **OAuth device-code (RFC 8628) OR API key**; API keys read from `config.toml` (not shell env, except `KIMI_MODEL_*`); telemetry ON by default (`KIMI_DISABLE_TELEMETRY=1`) | config | [docs/providers](https://moonshotai.github.io/kimi-code/) |

Note: the current product is **Kimi Code** (`@moonshot-ai/kimi-code`); the legacy PyPI "Kimi CLI" is a different, winding-down tool. The probe's installed 0.15.0 (KIMI-01) was a **stale binary**, not a version regression — 0.27.0 is the true latest.

### Cursor CLI (`cursor-agent`) — optional tier

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-07-17 | (date-based) | Latest changelog entry; **no published semver** — build id `2026.07.16-*`; auto-updates by default | fs-convention | [changelog](https://cursor.com/changelog) |
| — | (docs) | Headless `-p/--print`, `--output-format text\|json\|stream-json`; `-f/--force`(=`--yolo`); **`--trust` (headless-only)**; `--sandbox enabled\|disabled`; `--mode plan\|ask` | command + flag | [docs/cli](https://cursor.com/docs/cli) |
| — | (docs) | Agents md+YAML (`.cursor/agents/`, `.claude/agents/`, `.codex/agents/` + globals); fields name/description/model/`readonly`/`is_background`; effort via model-id brackets `[effort=high]` | agent-primitive | [docs/subagents](https://cursor.com/docs/cli) |
| — | (docs) | Catalog includes **Fable 5 + Sonnet 5** (+ Opus 4–4.8, GPT-5→5.6, Gemini, Grok 4.5, GLM 5.2, Kimi K2.7, Composer, Auto router); no default (Auto foregrounded) | model | [docs/models](https://cursor.com/docs/models) |
| — | (docs) | `hooks.json` (version + event→command); events incl. `beforeShellExecution`, `afterFileEdit`, `subagentStart`, `stop`; **docs do not claim headless hook support** (community reports only shell events fire under `cursor-agent`) | hook | [docs/hooks](https://cursor.com/docs) |

## 3. Gap analysis vs current (post-U1–U13) Triforge

Every "Used in Triforge?" cell is grounded in a real repo path (grep-verified).

| Feature | CLI | Used in Triforge? | Action | Reasoning |
|---|---|---|---|---|
| Gemini → Antigravity lane migration | agy | **Y (this effort)** | Keep | `scripts/invoke-external.sh:71 invoke_antigravity()` pins `Gemini 3.1 Pro (High)`, `--add-dir`, `--print-timeout`; `session-start.sh:30-38` installs the `antigravity-agents/` plugin; `.claude/CLAUDE.md:314` retires the Gemini floor. Service cutoff (2026-06-18) forced it; done. |
| `--full-auto` replacement | Codex | **Y** | **Adopt wording fix** | `invoke-external.sh:229` + `.claude/CLAUDE.md:147` say Codex "removed" `--full-auto`; it is **deprecated, not removed**. Action (explicit `-s workspace-write -c approval_policy=never`) is correct and matches current docs — only the "removed" rationale is stale. |
| Hooks under `codex exec` | Codex | **Y (this effort)** | Keep | Reversed May D-004: `templates/.codex/hooks.json` + conditional `--dangerously-bypass-hook-trust` in `invoke_codex` (probe CDX-04). See `ops/decisions/2026-07-18-codex-hooks-under-exec.md`. |
| `gpt-5.6-sol` flagship + `max`/`ultra` | Codex | **Y (this effort)** | Keep | `codex-agents/agents.toml:27,113,196` = `gpt-5.6-sol` at `xhigh`; `max`/`ultra` commented opt-ins (CDX-06/07). Supersedes stored `gpt-5.4`. |
| `--output-schema` structured verdicts | Codex | **Y (this effort)** | Keep | `agents.toml:37 output_schema` → `invoke_codex --output-schema` (feature-gated on `codex features list`); probe CDX-05. Retires text-scrape of `ops/REVIEW_CODEX.md`. |
| `codex features list` capability detection | Codex | **Y (this effort)** | Keep | `invoke-external.sh:33` caches `codex features list` for hooks/output-schema gating — replaces version-string parsing. |
| Inter-agent tool `send_input` (not `send_message`) | Codex | **Y (correct already)** | Keep | `codex-agents/AGENTS.md:59` names `spawn_agent, wait_agent, send_input, close_agent` — already correct; the 2026-07-17 fact sheet's "send_message" was a fact-sheet error, no code change. |
| `multi_agent_v2` path-based addressing | Codex | **N** | **Defer** | Still `under development / false` (probe appendix). Open bug #31097: GPT-5.5/5.6 force it on despite the flag. Revisit on stable graduation. |
| `permission_profile` in `[agents.<name>]` | Codex | **N** | Skip | Field **does not exist** (config-reference verified) — kills May report candidate #5 as specced. Triforge uses `sandbox_mode` + `approval_policy` per agent; correct. |
| Codex memories auto-pipeline | Codex | **N (disabled)** | Keep | `templates/.codex/config.toml` `use_memories=false`; memories still **off by default** upstream (May D-002 stands). |
| `/goal` + sentinel completion gating | Claude | **Y (this effort)** | Keep | `ship-loop.sh` retired; `ops/.sprint-complete` + `/goal` (probe CC-03). `scripts/coordinate.sh` leads each prompt with the `/goal` line. |
| Dynamic workflows / `ultracode` | Claude | partial | **Evaluate** | Probe CC-04: JS workflow API can express external-CLI dispatch + requeue + pinned reviewer; overlaps `wave-orchestration`. U10 dogfooded a wave, but workflows not yet the default orchestrator. Next-cycle evaluation. |
| `subagentStatusLine` reasoning-effort field (2.1.214) | Claude | **N (new)** | **Evaluate** | New in 2.1.214 — renders the runtime-ladder tier (opus/xhigh → sonnet/high) per agent row. Low-cost observability adoption for the builder pool. |
| `max` effort availability | Claude | **Y** | **Adopt doc fix** | `README.md:700` says "max is Opus-only"; docs list `max` on Fable 5/Sonnet 5/Opus 4.8/4.7. Correct the note; ladder unaffected. |
| Fable 5 spawn-time override | Claude | **Y (this effort)** | Keep | `.claude/CLAUDE.md:16` — lead spawns team-lead + never-downgrade trio with `model: fable` when probe CC-02 shows Fable 5 PASS. |
| `.agents/skills/` interop | agy/opencode/kimi/cursor | **Y (this effort)** | Keep | `session-start.sh:46-52` copies `skills/` → `.agents/skills/`. May D-003 now pays off across **four** CLIs (OpenCode, Kimi `--skills-dir`, Cursor `.claude/skills`, agy) — verified in each CLI's docs this run. |
| Optional lanes OpenCode/Kimi/Cursor | OC/Kimi/Cursor | **Y (this effort)** | Keep | `invoke_opencode:406`, `invoke_kimi:693`, `invoke_cursor:1031`. Reviewer read-only via `--mode plan` (CUR-08)/prompt-level; confinement via lease worktree not `--sandbox` (CUR-07/AGY-10). |
| agy 1.1.4 headless `settings.json` enforcement | agy | **N (new)** | **Verify** | 1.1.4 (2026-07-18) makes `-p` honor `settings.json` permissions/sandbox/artifact-review — may reverse AGY-08/09/10 and gate fan-out. Re-probe before adopting or bumping the floor. |
| OpenCode `deny` overriding `--auto` | OpenCode | partial | **Verify** | Docs say `deny` wins over `--auto`; probe OC-06 saw a denied command execute. Upstream bug or probe misconfig — targeted re-probe; `invoke_opencode` does not rely on `--auto` today. |
| Cursor `CLAUDE.md`-at-root instruction file | Cursor | **N** | Skip | **Not documented** by Cursor (only `AGENTS.md` + `.cursor/rules/`). Do not assume Cursor reads root `CLAUDE.md`. |
| Kimi auth = OAuth or API key | Kimi | **N (assumed API-key-only)** | **Evaluate** | Enrollment (U12/U17) assumed API-key-only; OAuth device-code is available. Broadens who can enroll Kimi. |
| Registry `docs` URL for Kimi | Kimi | **Y (registry)** | **Adopt registry fix** | `templates/ops/watch-registry.toml:98` = `kimi.com/code/docs` (SPA shell, no fetchable content). Change to `moonshotai.github.io/kimi-code`. |
| Compatibility floors | all | **Y (this effort)** | Keep | `.claude/CLAUDE.md:310-314`: Codex ≥ 0.144.0, agy ≥ 1.1.3, CC ≥ 2.1.212. Supersedes May D-008. agy floor pending a 1.1.4 re-probe. |
| Mythos 5 tier | Claude | **N** | Skip/Defer | Invitation-only (not GA). Fable 5 is Triforge's GA ceiling (probe CC-02). Revisit on Mythos 5 GA. |

## 4. Top prioritized adoption candidates for the NEXT cycle

The May gaps closed this effort, so these candidates are the **new/forward** items surfaced by this run — none are blockers.

### #1. Re-probe `agy` 1.1.4 headless `settings.json` policy enforcement (highest priority)

**Why:** `agy` 1.1.4 (2026-07-18) states headless `-p` now honors persisted `settings.json` policies (permissions, file access, sandbox, auto-execution, artifact review) — directly contradicting probe rows **AGY-08/09/10** (hooks/deny/sandbox inert on 1.1.3) and the `session-start.sh:43-45` note that "NO project-tier settings.json lifted the headless permission auto-deny." Two-sided impact: it could let Triforge add **defense-in-depth headless confinement** (settings.json `sandbox_mode` alongside the R35 lease-worktree), **or** newly **block** `invoke_antigravity` fan-out on artifact-review/auto-execution gates.

**Concrete change:** Extend `scripts/probe-capabilities.sh` to run AGY-08/09/10 against `agy` 1.1.4 with a project-tier `.antigravity/settings.json` carrying explicit `permissions.deny` + `sandbox` rules. If deny/sandbox now hold: add a shipped `templates/.antigravity/settings.json` confinement profile and bump the floor to `agy ≥ 1.1.4` in `.claude/CLAUDE.md:310-314`. If fan-out blocks: pin `invoke_antigravity` to a permissive headless profile and record the regression.

**Verification:** the re-probe rows themselves (deny-survival negative test + sandbox-escape negative test on 1.1.4) plus a live `invoke_antigravity "codebase-analyst"` fan-out that still writes its output.

### #2. Correct the drift in shipped docs (low-cost, high-accuracy)

**Why:** Three stale statements now contradict primary sources: (a) Codex `--full-auto` "removed" (it is deprecated-with-warning), (b) "max is Opus-only" (Fable 5/Sonnet 5 support `max`), (c) the fact sheet's "send_message"/"API-key-only Kimi"/"1M Kimi context".

**Concrete change:** edit `.claude/CLAUDE.md:147` and `scripts/invoke-external.sh:229` ("removed" → "deprecated (prints a warning); prefer explicit `--sandbox workspace-write`"); edit `README.md:700` ("max is Opus-only" → "max available on Fable 5, Sonnet 5, Opus 4.8/4.7"). No behavior change — `invoke_codex` already passes explicit flags and `codex-agents/AGENTS.md:59` already uses `send_input`.

**Verification:** grep shows no remaining "removed the `--full-auto`" / "max is Opus-only" strings; `claude plugin validate --strict` stays green.

### #3. Fix the Kimi registry `docs` URL + document version-staleness

**Why:** `templates/ops/watch-registry.toml:98` points at `kimi.com/code/docs`, an SPA shell that returns no fetchable content — a soft-fail that degrades every future Kimi watch worker. Kimi's near-daily cadence (52 versions since 2026-05-22) also means the installed binary goes stale within days (probe KIMI-01 caught 0.15.0 vs. latest 0.27.0).

**Concrete change:** set `[cli.kimi].docs = "https://moonshotai.github.io/kimi-code"`; add a `note` that the installed binary should be `kimi upgrade`-refreshed before a probe run (or the probe should record the delta as staleness, not regression).

**Verification:** a Kimi watch worker fetches doc content (not an SPA shell) from the new URL; `scripts/probe-capabilities.sh` KIMI-01 flags stale-vs-latest explicitly.

### #4. Evaluate `subagentStatusLine` reasoning-effort rendering for the builder pool

**Why:** Claude Code 2.1.214 adds `reasoning effort` to the `subagentStatusLine` payload — a free observability win for the builder-pool/roster, which routes agents across the `fable/max → opus/xhigh → opus/high → sonnet/high` ladder. Today the ladder tier is invisible at runtime.

**Concrete change:** add a `subagentStatusLine` handler (or extend the existing status line) that renders each roster agent's model + effort; wire into the U8 roster/U10 wave display.

**Verification:** a wave run shows per-agent model+effort rows; downgraded agents render `sonnet/high`, never-downgrade trio render `fable/max`.

### #5. Re-probe OpenCode `deny`-vs-`--auto` and hand off repo-mining adoptions

**Why:** OpenCode docs assert `deny` overrides `--auto`, but probe **OC-06** saw a denied command execute — an unresolved contradiction that decides whether `invoke_opencode` may ever use `--auto`. Separately, the four `[repo.*]` mining adoptions are produced by the sibling `/repo-watch` run (U15b), not this cycle.

**Concrete change:** add an OC-06 re-probe with an isolated `opencode.json` deny fixture on v1.18.3; keep `invoke_opencode` off `--auto` until it passes. For repo-mining, consume U15b's `ops/research/2026-07-18-repo-mining.md` recommendations in a later user-approved sprint.

**Verification:** OC-06 re-probe row (deny survives `--auto`, or confirmed upstream bug filed); U15b report referenced in the next ADR.

## 5. Risks — changes that could affect Triforge

1. **agy 1.1.4 headless policy regression** — if `-p` now enforces artifact-review/auto-execution gates, `invoke_antigravity`'s background fan-out (`invoke-external.sh:71`, `:2081`) could block or hang. **Mitigation: candidate #1 (re-probe before floor bump).** `[HIGH — new]`
2. **Codex 0.145.0-alpha train active** — the next minor (alpha.13→.23, 2026-07-15/17) may change hook shape or the `multi_agent_v2` default. Triforge floor is 0.144.0. **Mitigation: watch the 0.145.0 stable notes; re-run CDX-04 on bump.** `[MEDIUM]`
3. **Codex `multi_agent_v2` forced on for GPT-5.6 (bug #31097)** — flagship models ignore `features.multi_agent_v2=false` and the `-c` override. Triforge spawns Codex subagents (`agents.toml` caps `max_depth=2/max_threads=4`); a forced v2 path could change spawn addressing. **Mitigation: pin `multi_agent` behavior; watch #31097.** `[MEDIUM]`
4. **Kimi near-daily cadence** — a pinned version is stale within days; probe KIMI-01 already caught 0.15.0-vs-0.27.0. Also **KIMI-05 AUTH-FAIL** (no model configured) leaves the Kimi lane unproven live. **Mitigation: candidate #3 + enrollment-time `kimi upgrade` + auth check.** `[MEDIUM — optional tier]`
5. **Cursor auto-update drift + headless hook silence** — no semver, auto-updates by default, and docs are silent on which hook events fire under `cursor-agent` (probe CUR-06 saw none). Attribution rests on the U9 lead-side ledger, which is correct, but a Cursor auto-update could change flag behavior between runs. **Mitigation: capture `--version` each run (registry note already says so); keep ledger-based attribution.** `[LOW — optional tier]`
6. **OpenCode `deny`-vs-`--auto` contradiction** — docs vs. probe OC-06 disagree; until resolved, `--auto` is unsafe for `invoke_opencode`. **Mitigation: candidate #5; adapter stays off `--auto`.** `[LOW — optional tier]`
7. **Gemini 3.5 Pro still not GA** — Triforge pins `Gemini 3.1 Pro (High)` (Preview). If Google GA's 3.5 Pro or retires 3.1 Pro Preview, the pin must move. **Mitigation: AGY-02 re-probe each cycle.** `[LOW]`

## 6. Sources appendix

- Claude Code: [releases](https://github.com/anthropics/claude-code/releases) · [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) · [docs/goal](https://code.claude.com/docs/en/goal) · [docs/workflows](https://code.claude.com/docs/en/workflows) · [docs/routines](https://code.claude.com/docs/en/routines) · [docs/agent-teams](https://code.claude.com/docs/en/agent-teams) · [models overview](https://platform.claude.com/docs/en/about-claude/models/overview) · [model-config](https://code.claude.com/docs/en/model-config) · [fast-mode](https://code.claude.com/docs/en/fast-mode)
- Antigravity / Gemini: [antigravity-cli releases](https://github.com/google-antigravity/antigravity-cli/releases) (latest 1.1.4) · [Discussion #28017 (service cutoff)](https://github.com/google-gemini/gemini-cli/discussions/28017) · [Google deprecation page](https://developers.google.com/gemini-code-assist/docs/deprecations/code-assist-individuals) · [gemini-cli #27858 (routing removed)](https://github.com/google-gemini/gemini-cli/issues/27858) · [gemini-cli releases (v0.51.0, not archived)](https://github.com/google-gemini/gemini-cli/releases) · [ai.google.dev models](https://ai.google.dev/gemini-api/docs/models)
- Codex: [releases (`rust-v*`)](https://github.com/openai/codex/releases) (latest stable 0.144.5) · [changelog](https://learn.chatgpt.com/docs/changelog?type=codex-cli) · [hooks docs](https://learn.chatgpt.com/docs/hooks) · [non-interactive docs (`--full-auto` deprecated)](https://learn.chatgpt.com/docs/non-interactive-mode) · [config-reference](https://learn.chatgpt.com/docs/config-file/config-reference) · [models](https://learn.chatgpt.com/docs/models) · issues #26949 (goal-from-exec NOT_PLANNED), #31097 (multi_agent_v2 forced-on), #33314 (spawn_agent overrides)
- OpenCode: [releases (anomalyco)](https://github.com/anomalyco/opencode/releases) (v1.18.3) · [docs](https://opencode.ai/docs) — official domain `opencode.ai` (decoy `open-code.ai` avoided)
- Kimi Code: [releases](https://github.com/MoonshotAI/kimi-code/releases) (0.27.0) · [npm `@moonshot-ai/kimi-code`](https://registry.npmjs.org/@moonshot-ai/kimi-code) · [docs (real)](https://moonshotai.github.io/kimi-code/) — registry `docs` URL `kimi.com/code/docs` is an SPA shell
- Cursor: [changelog (date-based, latest 2026-07-17)](https://cursor.com/changelog) · [docs/cli](https://cursor.com/docs/cli) · [docs/cli parameters](https://cursor.com/docs/cli/reference/parameters) · [docs/models](https://cursor.com/docs/models) · [docs/hooks](https://cursor.com/docs) · [docs/subagents](https://cursor.com/docs/cli)
- Internal: probe record `ops/research/2026-07-probe-record.md` (U1) · fact sheets `ops/research/2026-07-17-factsheet-{antigravity,codex,claude-code,new-clis}.md` · grounding dossier `ops/research/2026-07-17-grounding-dossier.md` · prior cycle `ops/research/cli-updates-2026-05.md` · dedicated ADR `ops/decisions/2026-07-18-codex-hooks-under-exec.md`

**Cross-checks performed (per watch-cycle SKILL §Stage 6):**
1. **Registry validation** — Stage 1 ran over `templates/ops/watch-registry.toml`: 18/18 CLI URLs HTTPS + public-host OK; `meta.cli_count=6`/`repo_count=4` match; **no flagged targets** (no 404 / rename / validation reject this run).
2. **Source verification** — each of the 6 CLIs verified by an independent read-only worker against **primary sources** (GitHub releases/tags, official changelogs, first-party docs); load-bearing claims marked CONFIRMED/DRIFTED/UNVERIFIABLE with a primary-source URL per drift.
3. **Window coverage** — window 2026-05-12 → 2026-07-18; per-CLI changelog covers the load-bearing releases; the 67-day span picks up the Gemini service cutoff (2026-06-18) and the `gpt-5.6-sol` (2026-07-09) + `agy` 1.1.4 (2026-07-18) landings.
4. **Gap-table grounding** — every Y/partial cell in §3 cites a real repo path (grep-verified: `invoke-external.sh` line numbers, `codex-agents/agents.toml`, `.claude/CLAUDE.md`, `README.md`, `session-start.sh`, `templates/ops/watch-registry.toml`).
5. **Pre-release flagging** — the only pre-release row (`0.145.0-alpha.23`) is tagged `**[alpha]**` and excluded from the stable floor.
6. **Injection / decoy scan** — no prompt-injection encountered on any fetched page (workers flagged only benign install-command text and tool-preamble artifacts, not page-embedded directives); the OpenCode `open-code.ai` decoy was not encountered; all fetches stayed on public HTTPS hosts with no private/loopback redirect.

### Flagged targets (continue-and-flag)

No target hard-failed (no 404 / rename / validation reject). One **soft** issue, recorded for the next cycle rather than blocking this run:

| Target | Registry URL | Problem | Evidence | Suggested registry fix |
|---|---|---|---|---|
| cli.kimi (`docs`) | https://kimi.com/code/docs | Resolves (HTTPS/public, not a 404) but serves a **JavaScript SPA shell** with no fetchable doc content | Kimi worker: `kimi.com/code/docs` returned an empty SPA; real docs at `moonshotai.github.io/kimi-code` (per `kimi --help` "Documentation:" line) | set `[cli.kimi].docs = "https://moonshotai.github.io/kimi-code"` (candidate #3) |
