# ADR: CLI deprecation watch — six-CLI update cycle 2026-07-18 → 2026-09-11

**Date:** 2026-09-11
**Status:** Accepted (Triforge v3.3.0 forthcoming — adoption sprint runs immediately after this cycle per user direction)
**Tested against:** Claude Code 2.1.268, Antigravity `agy` 1.2.0, Codex 0.154.0, OpenCode 1.18.30, Kimi Code 0.42.0 (AUTH-FAIL, not logged in), Cursor `2026.09.10-fd3934a` — all upgraded to latest on this host during the cycle.

## Context

Gap-analysis report `ops/research/2026-09-11-cli-updates.md` audited the second `/cli-watch` cycle. Unlike July, where the in-flight v3.0.0 modernization had already closed most gaps, this cycle found **live drift**: every one of the six model pins is a generation stale, four July probe rows reverse (two of them because the July probe was wrong, not the CLI), and three CLIs changed discovery or permission mechanics in ways that make shipped Triforge files inert or mis-named.

Capability claims rest on the fresh machine record `ops/research/2026-09-probe-record.md` (2026-09-11, 53 probes: 37 PASS / 12 FAIL / 1 AUTH-FAIL / 1 SKIPPED / 1 PENDING / 1 INFO) plus three lead re-probes recorded in the report (§1, §3.1). Per the watch-cycle method, every verdict that flips a prior ADR cites a probe row or a lead re-probe; where the harness itself is stale, the ADR says so and schedules the harness fix rather than trusting the stale row.

> **User direction recorded (2026-09-11).** The user directed this cycle to "update the models to the latest (e.g. Fable 5.1 is the latest, GPT Astra is the latest for Codex, Gemini 3.8 Flash, etc.)" and to apply the findings immediately. D-020–D-025 record the model moves; D-022 explicitly supersedes the KTD-8 never-Flash rule for the shipped agy default on that direction.

## Decisions

### D-020. Claude Fable 5.1 as the top ladder rung; Opus 5 as the `opus` rung — **ADOPT**

Fable 5.1 (`claude-fable-5-1`) is GA since 2026-09-01 and the `fable` alias resolves to it from Claude Code 2.1.257 (probe **CC-02** PASS on 2.1.268 already spawns it). The `opus` alias resolves to Opus 5 (`claude-opus-5`) since 2.1.219, so the ladder rung labelled "opus (4.8)" has silently meant Opus 5 for seven weeks. Reword the ladder (`.claude/CLAUDE.md`, `agents/team-lead.md`, `skills/wave-orchestration/SKILL.md`, `templates/CLAUDE.md` — byte-identical set), `README.md`, `docs/`, agent descriptions: top tier **Fable 5.1** (`fable`, `max`), then **Opus 5** (`opus`, `xhigh`/`high`), then **Sonnet 5** (`sonnet`, `high`). Opus 4.8 is no longer a rung (retire ≥ 2027-05-28). Mythos 5.1 stays invite-only (D-016 stands). Affects: ladder files, `README.md`, `docs/agent-triforge.md`, `docs/index.html`, `agents/*.md` descriptions.

### D-021. Codex flagship `gpt-6-astra` at `xhigh` — **ADOPT**

`gpt-6-astra` is the flagship and the bundled default since 0.153.4 (PR 42874); `minimal_client_version 0.153.0`; efforts low…xhigh, `max`, `ultra`. Lead live probe 2026-09-11: `codex exec -m gpt-6-astra -c model_reasoning_effort="xhigh"` → READY on 0.154.0. Move `codex-agents/agents.toml` (3×), `resolve_role` + `roster_member_default` in `scripts/invoke-external.sh`, `templates/ops/roster.toml`, `commands/setup.md` to `gpt-6-astra` / `xhigh`; keep `max`/`ultra` as commented opt-ins until CDX-06/07 re-probe on Astra (harness fix D-028). `gpt-5.6-sol` remains valid as a fallback. Supersedes July D-010. Affects: `codex-agents/agents.toml`, `scripts/invoke-external.sh`, `templates/ops/roster.toml`, `commands/setup.md`, docs.

### D-022. Antigravity default pin → `Gemini 3.8 Flash (High)` — **ADOPT (user-directed; supersedes KTD-8 never-Flash for the shipped default)**

Facts (probe **AGY-02**, worker primary sources): Gemini 3.8 Flash is GA (2026-09-02), agy's default is `Gemini 3.8 Flash (Medium)`, **no Pro newer than 3.1 Pro exists** (still `gemini-3.1-pro-preview`; 3.5 Pro "coming soon"), and no primary like-for-like coding benchmark between them is published. The July 3.6 Flash note deferred adoption under KTD-8 ("never Flash by default; revisit on the next Pro"). The user's explicit 2026-09-11 direction names Gemini 3.8 Flash as the latest to adopt; this ADR records that as the new default policy: **pin the newest Gemini model at its highest thinking level (`(High)`), Pro or Flash**. `Gemini 3.1 Pro (High)` stays a documented one-line roster opt-in. Move the pin in `resolve_role`, `roster_member_default`, `invoke_antigravity` default, `templates/ops/roster.toml`, `antigravity-agents/agents/*.md`, `commands/setup.md`, docs; update the `roster_write_role` suffix normalization to accept `(Medium)`. Revisit trigger: 3.5 Pro GA (AGY-02 each cycle) — the user decides then whether "latest" means the Pro line again. Affects: as listed; memory rule updated in lockstep.

### D-023. OpenCode default → `openrouter/z-ai/glm-5.3` — **ADOPT**

`z-ai/glm-5.3` (2026-08-18) is preloaded in models.dev and needs no `provider.openrouter.models` entry; used live in the fixture test. Probe **OC-04** PASS on 5.2 confirms the OpenRouter lane is connected on this host (FAIL→PASS since July). Move `opencode-agents/*.md`, `templates/.opencode/opencode.json`, `resolve_role`/`roster_member_default`, `commands/setup.md`, docs. `~z-ai/glm-latest` is documented as an alias, not pinned (non-deterministic attribution). Affects: as listed.

### D-024. Kimi default → `kimi-code/k3`; native `--agent-file`; drop `--skills-dir` — **ADOPT**

Probe **KIMI-03** flipped FAIL → PASS (0.42.0: `--agent <name>`, `--agent-file <path>` in `-p`). Docs: OAuth login provisions `kimi-code/k3` (the shipped `kimi-k3` is an open-platform ID that fails on OAuth hosts); `.agents/skills/` is native and `--skills-dir` *replaces* auto-discovery; the project `.kimi-code/config.toml` is **not read** (only the user file is). Changes: `invoke_kimi` + `lease_dispatch kimi)` use `--agent-file kimi-agents/<role>.md` (drop prompt-prefix injection), drop `--skills-dir`, default `kimi-code/k3` (KIMI-06 candidates add it first); `templates/.kimi-code/config.toml` + README mark the project file as documentation-only and rely on `KIMI_DISABLE_TELEMETRY` (honored in `-p` since 0.41.0); registry `docs` URL → `https://moonshotai.github.io/kimi-code/`. KIMI-05 stays AUTH-FAIL until the user runs `kimi login`. Supersedes the July KIMI-03 fallback posture (injection + AGENTS.md sections). Affects: `scripts/invoke-external.sh`, `kimi-agents/*.md`, `templates/.kimi-code/*`, `hooks/handlers/session-start.sh`, `commands/setup.md`, `ops/watch-registry.toml`.

### D-025. Cursor → Grok 4.6 with effort as a model-id suffix; keep `cursor-agent` first, verified `agent` fallback — **ADOPT**

Probe **CUR-03/CUR-05** PASS with `--model grok-4.6` (2026.09.10). Docs: Cursor recommends 4.6 over 4.5 and describe bracket notation (`grok-4.6[effort=xhigh]`); **lead probe CUR-10 (2026-09-11) rejected every bracket form headless** (`Cannot use this model: grok-4.6[effort=xhigh]`), and the CLI's own accepted list carries effort as a **suffix**: `cursor-grok-4.6-low|medium|high|xhigh[-fast]`. So Cursor's headless effort control is the model-id suffix, exactly like agy's `(Low|Medium|High)` — the bracket syntax is a docs-only claim recorded as an open watch. The install script now marks `cursor-agent` legacy and `agent` primary. **Binary resolution caveat (lead check 2026-09-11):** on this host `which -a agent` resolves first to an unrelated `~/.grok/bin/agent`, with Cursor's symlink second — a bare "prefer `agent`" rule would misroute. Changes: `cursor-agents/*.md`, `resolve_role`/`roster_member_default`, `commands/setup.md`, docs → shipped default `cursor-grok-4.6-xhigh`; `invoke_cursor` and the lease lane map the roster `effort` onto the suffix (low→`-low`, medium→`-medium`, high→`-high`, xhigh/max→`-xhigh`) when the roster model is a bare Grok family name, and pass an explicit suffixed id through untouched (Cursor's `effort` field is no longer inert); `_roster_binary cursor` keeps `cursor-agent` first and falls back to `agent` **only when `agent --version` matches Cursor's `YYYY.MM.DD-<hex>` format**. Auto router still never pinned. Affects: as listed, `hooks/handlers/session-start.sh`, `templates/.cursor/README.md`, `scripts/probe-capabilities.sh` (CUR-05 on the suffixed id; new CUR-10 negative for the bracket form).

### D-026. Codex trust gate, `agents.toml` sweep, config-key corrections, `--full-auto` removed — **ADOPT**

Primary sources: 0.147.0 removed `--full-auto` (PR 36054; `error: unexpected argument` on 0.154.0) and made project trust gate `.codex/hooks.json`/`config.toml`/`.rules` under `exec` (PR 36960; unset = untrusted; no exec prompt); 0.150.0 extends that to project `AGENTS.md`; linked worktrees inherit root trust (PR 39616). Probe **CDX-04** still PASSES on 0.154.0 with `--dangerously-bypass-hook-trust` in an untrusted fixture, so the automation path holds today. Also: `.codex/agents/*.toml` is swept as standalone role files (Triforge's `agents.toml` triggers a non-fatal "Ignoring malformed agent role definition" warning); `include_plan_tool` was never a Codex key (real switch `tools.update_plan.enabled`, default false since 0.152.0); `max_depth` is V1-only (ignored by Astra/Sol); `job_max_runtime_seconds` is a no-op. Changes: deploy the TOML as `.codex/triforge-agents.toml` and update the lookup in `invoke_codex`/`_extract_codex_agent_config` + `session-start.sh`; replace `include_plan_tool`; document the durable trust entry `[projects."<abs>"] trust_level = "trusted"` in `templates/.codex/README.md` and `/setup`; fix the "deprecated (prints a warning)" wording in `.claude/CLAUDE.md` and `scripts/invoke-external.sh` to "removed (0.147.0)". May D-001 stands (action was already explicit). Affects: as listed.

### D-027. Antigravity agent pack → 1.1.6+ Markdown-agent format and agy tool vocabulary — **ADOPT**

Probe **AGY-12/AGY-13** still FAIL, root cause found this cycle: agy discovers Markdown agents carrying `mainAgent`/`subagent`/`commandExecutionPolicy` (the discovered `flutter_a11y_agent` has exactly that); Triforge's four definitions use `tools`/`max_turns`/`timeout_mins` with Gemini-CLI tool names agy does not have (`read_file`, `write_file`, `glob`, `list_directory`, `run_shell_command`; the spec warns unmapped names may hang the subagent). Migrate `antigravity-agents/agents/*.md` to `mainAgent: true`, `subagent: true`, `commandExecutionPolicy`, agy tool names (omit `run_command` for reviewer/documenter — the allowlist is still the primary guardrail), `model: inherit` (dispatch `--model` governs); bump `antigravity-agents/plugin.json` to the plugin version; make `session-start.sh` reinstall on version change. Expected flips: AGY-03 lists four Triforge agents; AGY-12 PASS (native `--agent` round-trip); AGY-13 PASS. Until verified, `invoke_antigravity` keeps its injection fallback. Affects: `antigravity-agents/`, `hooks/handlers/session-start.sh`, `scripts/invoke-external.sh`.

### D-028. Probe harness corrections (AGY-08 hook shape, Astra rows, grok pick, KIMI-06 alias, OC-06, dated record) — **ADOPT**

**AGY-08 reversal (probe-shape error, not a CLI change).** The harness writes a settings.json-style `hooks` object with `SessionStart/AfterAgent/AfterTool` into `.gemini/settings.json` and `.agents/hooks.json`; agy's documented workspace hooks file is `.agents/hooks.json` with **named hooks** and events `PreInvocation/PostInvocation/PreToolUse/PostToolUse/Stop`. Lead marker-file re-probe 2026-09-11 (agy 1.2.0, `--add-dir` bound, read-only turn): **all five events fired**; `agy -p "/hooks"` lists the workspace hook. The July D-018 "hooks inert headless" reading is therefore **withdrawn for hooks**; AGY-09 (deny vs skip-permissions) and AGY-10 (`--sandbox`) remain FAIL on 1.2.0 and their adapter postures stand. Harness changes: rewrite AGY-08 to the documented shape; CDX-03/05/06/07 on `gpt-6-astra`; CUR-05 on `grok-4.6`; KIMI-06 tries `kimi-code/k3` first; OC-06 uses `OPENCODE_PERMISSION` + explicit `-m` + 300 s; record path/title date-stamped (`ops/research/<YYYY-MM>-probe-record.md` — the 2026-09 record header still reads "2026-07 cycle" because the title is hard-coded); new rows for headless skill expansion (agy `/skills` + `/<skill>`, Codex `$skill`, OpenCode `--command`, Cursor `/skill`), agy `denied_actions`, Codex project-trust on/off. Affects: `scripts/probe-capabilities.sh`, `ops/research/2026-09-probe-record.md`.

### D-029. `.agents/skills/` refresh on plugin version change; document the six-harness discovery matrix — **ADOPT**

Fixture test (report §3.1): `.agents/skills/` is read by agy (workspace-bound), Codex, OpenCode, Cursor, and Kimi (docs) — **not** Claude Code, which reads plugin `skills/` and `.claude/skills/`. Triforge's copy is correct but copy-once (`session-start.sh:61`), so plugin updates strand five CLIs on stale skills. Add a version stamp (`.agents/skills/.triforge-plugin-version`) and re-copy on change; document the matrix and the per-harness invocation forms (`/name` Claude/agy/Cursor, `$name` Codex, `skill` tool OpenCode, `/skill:name` Kimi) in `.claude/CLAUDE.md` "Portable skills" and `templates/CLAUDE.md`. Slash commands stay per-harness (Codex custom prompts are deprecated and not expanded under `exec`; Triforge commands are lead-only). Affects: `hooks/handlers/session-start.sh`, `.claude/CLAUDE.md`, `templates/CLAUDE.md`, `README.md`.

### D-030. `/goal` headless gating is best-effort; sentinel stays authoritative — **DOCUMENT**

Probe **CC-03** flipped PASS → FAIL; two lead re-runs went PASS then FAIL (1/3 this cycle). The gate is model-behavior-dependent (evaluator = small fast model, Sonnet in the probe). `ops/.sprint-complete` + `scripts/coordinate.sh` remain the completion mechanism (unchanged); `/goal` stays composed into the prompt as an assist. Wording fix in `.claude/CLAUDE.md` "Context management". No behavior change.

### D-031. Claude Code operational corrections — **ADOPT**

(a) `settings.json` adds `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` (task tools are off on every current model since 2.1.233/2.1.268; agent-team shared task lists need them). (b) Floor → **Claude Code ≥ 2.1.267** (the `effort:` frontmatter fix; Fable 5.1 alias needs ≥ 2.1.257). (c) Audit `hooks/handlers/*.sh` for `{…}`-shaped non-JSON stdout (hook error since 2.1.246). (d) Note `--bare` as the announced future default for `-p` (open watch — `coordinate.sh` and the builder lease lane depend on hooks/skills/CLAUDE.md loading). (e) `defaultMode: bypassPermissions` in project settings is ignored (2.1.257) — no Triforge file relies on it. Affects: `settings.json`, `.claude/CLAUDE.md`, `README.md`, `hooks/handlers/`.

### D-032. agy headless research lanes: `read_url` now asks; exit 0 ≠ complete — **ADOPT**

1.1.28 changed `read_url` from always-allowed to Ask (headless soft-deny unless `permissions.allow` carries `read_url(*)` in the user-tier `~/.gemini/antigravity-cli/settings.json` — the only documented CLI settings path; `.antigravity/settings.json` remains undocumented and the July probe finding stands). 1.1.20/1.1.28 made benign tool errors and `--print-timeout` expiry exit 0. Changes: `invoke_antigravity` runs `--output-format json` and reads `status` + `denied_actions` (1.1.27) instead of trusting the exit code; `/setup` documents the `read_url(*)` allow rule for research lanes; `templates/.antigravity/settings.json` comment maps denies to `command(rm -rf)`/`command(git push)`/`command(sudo)` action syntax. Floor **agy ≥ 1.1.27** (≥ 1.1.10 hard minimum: `--model` was ignored under `-p` on 1.1.5–1.1.9). Affects: `scripts/invoke-external.sh`, `commands/setup.md`, `templates/.antigravity/`, `.claude/CLAUDE.md`.

### D-033. OpenCode `deny` vs `--auto` — **DEFER (open watch; adapter unchanged)**

Docs and source (`permission/index.ts` `evaluate()` → `DeniedError` before any ask) say an explicit deny is enforced under `--auto`; probe **OC-06** on 1.18.30 still recorded the denied command executing; two lead re-probes with a project rule and with `OPENCODE_PERMISSION` hung to timeout (inconclusive). `invoke_opencode` stays off `--auto` (no change) and gains `OPENCODE_PERMISSION` deny injection as defense-in-depth; the harness OC-06 is rewritten (D-028). Revisit on the rewritten probe. Affects: `scripts/invoke-external.sh`, `scripts/probe-capabilities.sh`.

### D-034. Compatibility floors re-baselined — **DOCUMENT**

`.claude/CLAUDE.md` / `README.md` compatibility table: Claude Code ≥ **2.1.267** (tested 2.1.268); agy ≥ **1.1.27** (tested 1.2.0); Codex ≥ **0.153.0** (Astra `minimal_client_version`; tested 0.154.0); OpenCode ≥ **1.18.20** (subagent permission answering; tested 1.18.30); Kimi ≥ **0.33.0** (v2 engine + `--agent`; tested 0.42.0, AUTH-FAIL); Cursor date-versioned (tested 2026.09.10). Supersedes July D-014.

### D-035. Registry corrections — **ADOPT**

`ops/watch-registry.toml`: `[cli.antigravity]` docs → `https://antigravity.google/docs/cli/getting-started`, changelog → `https://antigravity.google/changelog?tab=cli`, rewrite `note` (release notes are detailed; `agy changelog` is a bundled primary source); `[cli.kimi]` docs → `https://moonshotai.github.io/kimi-code/`; `[cli.cursor]` note: binary `agent` (legacy `cursor-agent`).

### D-036. Repo-mining adoptions — **DEFER to the sibling `/repo-watch` report**

The four `[repo.*]` verdicts are produced by this cycle's `/repo-watch` run (`ops/research/2026-09-11-repo-mining.md`); items that overlap this ADR (N1 `.agents/skills/` refresh → D-029; N4 manifest lockstep → D-027) are adopted here.

## Prior-decision status (July 2026 cycle → now)

| July decision | This cycle |
|---|---|
| D-004 (reversed) Codex hooks under exec — ADOPT | **Stands** — CDX-04 PASS on 0.154.0; project-trust gate documented (D-026) |
| D-009 Gemini → agy lane — ADOPT | **Stands**; default pin moves to 3.8 Flash (D-022) |
| D-010 `gpt-5.6-sol` — ADOPT | **Superseded by D-021** (`gpt-6-astra`) |
| D-011 `--output-schema` verdicts — ADOPT | **Stands** — CDX-05 PASS |
| D-012 optional lanes — DOCUMENT | **Stands & updated** — Kimi native agents (D-024), Cursor `agent` + bracket effort (D-025) |
| D-013 builder-pool / roster / leases — DOCUMENT | **Stands** |
| D-014 floors — DOCUMENT | **Superseded by D-034** |
| D-015 `multi_agent_v2` — DEFER | **Stands (DEFER)** — now `stable`/false; #31097 open; Astra forces V2 by catalog |
| D-016 Mythos — DEFER | **Stands** — Mythos 5.1 invite-only |
| D-017 repo-mining — DEFER | **Carried (D-036)** |
| D-018 agy headless settings.json / AGY-08/09/10 — DEFER | **Partially reversed** — hooks fire headless with the documented shape (D-028); deny/sandbox FAIL stand; settings.json enforcement is user-tier only (D-032) |
| D-019 doc drift — DOCUMENT | **Applied in the sprint** (`--full-auto` now *removed*, D-026) |

## Verification record

Machine probes from `ops/research/2026-09-probe-record.md` (2026-09-11, all CLIs at latest) and lead re-probes backing this cycle's verdicts:

| Probe | Capability | Outcome | Date | Method |
|---|---|---|---|---|
| CC-01 / CC-02 | Claude Code 2.1.268; `fable` alias READY (= Fable 5.1 on ≥ 2.1.257) | PASS / PASS | 2026-09-11 | direct / live |
| CC-03 | `/goal` hard-gates an un-instructed condition in `-p` | **FAIL** (harness) · lead re-run ×2: PASS, FAIL → **flaky 1/3** | 2026-09-11 | live |
| CC-04 / CC-06 | dynamic workflows expressible; `plugin validate --strict` | PASS / PASS | 2026-09-11 | static / validate |
| CDX-01 / CDX-02 | codex-cli 0.154.0; features list (`hooks` stable true, `multi_agent_v2` stable false, `memories` stable false, `plugins` stable true) | PASS / PASS | 2026-09-11 | direct |
| CDX-03 (lead) | headless READY on **`gpt-6-astra`** at `xhigh` | **PASS** | 2026-09-11 | live |
| CDX-03 / CDX-06 / CDX-07 (harness) | READY / `max` / `ultra` on `gpt-5.6-sol` (harness still pins Sol) | PASS / PASS / PASS | 2026-09-11 | live |
| CDX-04 | hooks fire under `codex exec` with `--dangerously-bypass-hook-trust` (untrusted fixture) | PASS (SessionStart UserPromptSubmit PreToolUse Stop) | 2026-09-11 | marker-file |
| CDX-05 / CDX-08 | `--output-schema` JSON; read-only sandbox rejects writes | PASS / PASS | 2026-09-11 | live / negative |
| AGY-01 / AGY-02 | agy 1.2.0; catalog: 3.8/3.7/3.6 Flash, 3.1 Pro only Pro | PASS / PASS | 2026-09-11 | direct |
| AGY-03 | `agy agents` lists `flutter_a11y_agent` (native listing works; Triforge agents absent) | PASS | 2026-09-11 | direct |
| AGY-04 / AGY-05 / AGY-11 | headless READY; `Gemini 3.1 Pro (High)` pin; dedicated `--effort` flag | PASS / PASS / PASS | 2026-09-11 | live / static |
| AGY-08 (harness) | hooks with settings.json-style shape + `SessionStart/AfterAgent/AfterTool` | FAIL (stale shape) | 2026-09-11 | marker-file |
| AGY-08 (lead) | `.agents/hooks.json` named-hook shape, `--add-dir` bound | **PASS — PreInvocation, PostInvocation, PreToolUse, PostToolUse, Stop all fired** | 2026-09-11 | marker-file |
| AGY-09 / AGY-10 | deny survives `--dangerously-skip-permissions`; `--sandbox` confines | FAIL / FAIL (postures stand) | 2026-09-11 | negative |
| AGY-12 / AGY-13 | Triforge plugin agents listed / reviewer cannot shell | FAIL / FAIL (root cause: frontmatter shape + tool names, D-027) | 2026-09-11 | live / negative |
| Lead fixture | `agy --add-dir … -p "/tf-agents-skill"` expands a `.agents/skills/` skill headless; `agy -p "/skills"` lists it | PASS | 2026-09-11 | live |
| OC-01 / OC-02 / OC-03 / OC-04 / OC-05 | 1.18.30; OpenRouter list; READY; `glm-5.2` pin; `--variant` | PASS ×5 (OC-02/04/05 FAIL→PASS since July) | 2026-09-11 | direct / live |
| OC-06 | explicit deny survives `--auto` | **FAIL** (harness); lead re-probes ×2 timed out (inconclusive) | 2026-09-11 | negative |
| Lead fixture | `opencode run --command tf-cmd-opencode` (`.opencode/command/` and `commands/`) → CMD-OK; `/tf-opencode-skill` → native `skill` tool | PASS | 2026-09-11 | live |
| KIMI-01 / KIMI-02 / KIMI-03 / KIMI-04 | 0.42.0; doctor OK; **`--agent`/`--agent-file` present** (FAIL→PASS); `--skills-dir` | PASS ×4 | 2026-09-11 | direct / static |
| KIMI-05 / KIMI-06 | headless READY / K3 pin | **AUTH-FAIL** / SKIPPED-GATED (no model configured — user must `kimi login`) | 2026-09-11 | live |
| CUR-01 / CUR-02 / CUR-03 / CUR-04 / CUR-05 | 2026.09.10; logged in; grok pick **grok-4.6**; READY; **`--model grok-4.6` READY** | PASS ×5 | 2026-09-11 | direct / live |
| CUR-06 / CUR-07 / CUR-08 | headless hooks fire / `--sandbox` confines / `--mode plan` read-only | FAIL / FAIL / PASS (postures stand) | 2026-09-11 | marker-file / negative |
| Lead fixture | Cursor lists skills from `.cursor/`, `.claude/`, `.codex/`, `.agents/`; `/tf-cmd-cursor` → CMD-OK; `/tf-cursor-skill` → SKILL-OK | PASS | 2026-09-11 | live |
| Lead fixture | Codex lists `.agents/skills/` + `.codex/skills/`; `$tf-codex-skill` → SKILL-OK; `/prompts:tf-cmd-codex` under `exec` **not expanded** (model searched the tree) | PASS / PASS / FAIL (as documented: prompts deprecated, interactive-only) | 2026-09-11 | live |
| Lead fixture | Claude Code lists `.claude/skills/` + `.claude/commands/`; `/tf-agents-skill` → "Unknown command" | PASS / (`.agents/skills/` not a Claude path — as documented) | 2026-09-11 | live |
| SELF-01 … SELF-04 | roster chain rejection; coordinate.sh dry-run; adapter env allowlist; R35 boundary | PASS / PASS / PASS / INFO | 2026-09-11 | static |
| RTN-01 | scheduled-Routine delivery | PENDING (manual run; delivery branch not exercised) | 2026-09-11 | — |

**Web verification (primary sources, 2026-09-11)** — drift found since the July report:

| Claim | Result | Source |
|---|---|---|
| Claude latest / `fable` alias | **DRIFT → 2.1.268; `fable` = Fable 5.1 (≥ 2.1.257), `opus` = Opus 5 (≥ 2.1.219)** | [model-config](https://code.claude.com/docs/en/model-config), [Fable 5.1](https://platform.claude.com/docs/en/models/fable-5-1/overview) |
| Codex flagship | **DRIFT → `gpt-6-astra` (default since 0.153.4)**; `--full-auto` **removed** 0.147.0 | [models](https://learn.chatgpt.com/codex/models), [PR 36054](https://github.com/openai/codex/pull/36054) |
| Gemini latest | **DRIFT → 3.8 Flash GA 2026-09-02; 3.1 Pro still the only Pro (preview)** | [ai.google.dev models](https://ai.google.dev/gemini-api/docs/models), [DeepMind](https://deepmind.google/models/gemini/) |
| OpenRouter GLM | **DRIFT → `z-ai/glm-5.3`** (2026-08-18) | [OpenRouter](https://openrouter.ai/api/v1/models), [models.dev](https://models.dev/api.json) |
| Kimi latest / alias / config tiers | **DRIFT → 0.42.0; managed alias `kimi-code/k3`; project config.toml not read** | [releases](https://github.com/MoonshotAI/kimi-code/releases), [config-files](https://moonshotai.github.io/kimi-code/en/configuration/config-files.md), [overrides](https://moonshotai.github.io/kimi-code/en/configuration/overrides.md) |
| Cursor latest / binary / model | **DRIFT → 2026.09.10; `agent` primary; `grok-4.6`** | [install](https://cursor.com/install), [Grok 4.6](https://cursor.com/docs/models/grok-4-6) |

## Open watches

| Risk | Source | Trigger to revisit |
|---|---|---|
| `--bare` becomes the default for `claude -p` | upstream (headless docs) | a Claude Code release note flips the default → pin explicit non-bare behavior in `coordinate.sh` + the lease lane |
| Gemini 3.5 Pro GA (or 3.1 Pro preview retirement) | upstream | AGY-02 shows a new Pro line → user decides whether "latest" moves back to Pro (D-022) |
| `gpt-6-astra` `max`/`ultra` acceptance and `code_mode_only` behavior under Triforge's read-only reviewer sandbox | upstream + harness | CDX-06/07/08 re-probed on Astra (D-028) |
| Codex project-trust gate without the bypass flag | upstream | CDX-04 re-probed with and without a `[projects]` trust entry; a release removes `--dangerously-bypass-hook-trust` |
| Codex `multi_agent_v2` default flips true / #31097 resolved | upstream | `codex features list` shows `multi_agent_v2 … true`, or #31097 closes |
| agy plugin agents surface after D-027 migration | harness | AGY-03 lists the four Triforge agents → AGY-12/13 PASS; else escalate to upstream (#788-style) |
| agy `read_url` Ask default blocks research lanes on hosts without the allow rule | upstream + host | `denied_actions` contains `read_url` in a `/deep-research` run |
| OpenCode deny vs `--auto` | upstream + harness | rewritten OC-06 (D-028) PASSes twice, or an upstream issue is filed |
| OpenCode V2 ships (`opencode2`, plural config keys, ordered `permissions`) | upstream | npm `opencode-ai` major bump → port `templates/.opencode/opencode.json` + agent frontmatter |
| Kimi lane unproven live (AUTH-FAIL) | host | user runs `kimi login`; KIMI-05/06 PASS; `--agent-file` round-trip verified |
| Kimi headless "Never Ask" without dangerous-command guard | upstream | a release restores a headless guard, or a lease-worktree incident |
| Cursor drops the `cursor-agent` symlink; headless hooks documented | upstream | `command -v cursor-agent` fails on a fresh install; docs add a `-p` hooks statement |
| `/goal` gating reliability | upstream | CC-03 passes 3/3 on a future build → promote to a hard gate; otherwise stays advisory |
| Mythos 5.1 reaches GA | upstream | model overview lists `claude-mythos-5-1` as GA |

Review on every minor version bump of any registry CLI; full cycle monthly via `/schedule`.

## References

- Gap-analysis report (this cycle): `ops/research/2026-09-11-cli-updates.md`
- Fresh probe record: `ops/research/2026-09-probe-record.md` (probe IDs cited above); July record `ops/research/2026-07-probe-record.md`
- Sibling repo-mining report: `ops/research/2026-09-11-repo-mining.md`
- Prior cycle: `ops/research/2026-07-18-cli-updates.md`, `ops/decisions/2026-07-18-cli-deprecation-watch.md`, `ops/decisions/2026-07-18-codex-hooks-under-exec.md`; Gemini 3.6 Flash note `ops/research/2026-07-22-gemini-3.6-flash.md`
- Method: `.claude/commands/cli-watch.md`, `.claude/skills/watch-cycle/SKILL.md`; registry `ops/watch-registry.toml`
- Primary sources: full URL set in the report's §6 Sources appendix
