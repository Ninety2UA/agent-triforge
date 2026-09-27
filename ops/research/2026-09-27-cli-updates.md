# CLI deprecation-watch: six-CLI update gap analysis + lead-orchestrator research for Agent Triforge

**Cycle:** third `/cli-watch` run (manual; no commit/branch/PR)
**Window:** 2026-09-11 → 2026-09-27 (previous cutoff: `ops/research/2026-09-11-cli-updates.md`)
**Triforge baseline:** v3.3.1 (`.claude-plugin/plugin.json`)
**Probe record:** `ops/research/2026-09-probe-record.md`, regenerated 2026-09-27 21:19 UTC. 88 probes: 68 PASS · 12 FAIL · 1 AUTH-FAIL · 1 PENDING-U15 · 4 PENDING-AUTH · 2 INFO. The run started by this cycle was killed when the headless session ended (see §9, cross-check 8). The lead session then re-ran it to completion, and this report cites that run.
**Tested (record):** Claude Code 2.1.283 · agy 1.2.12 · Codex 0.155.1 · OpenCode 1.18.30 · Kimi 0.42.0 (AUTH-FAIL) · Cursor `2026.09.10-fd3934a`
**Upstream latest at cutoff:** Claude Code 2.1.283 · agy 1.2.12 · Codex 0.157.1 (0.158/0.159 alphas) · OpenCode 1.18.32 (V1) / **2.0.18 (V2, `@opencode/cli`)** · Kimi **2.1.1** · Cursor `2026.09.26-dd393fe`
**ADR:** `ops/decisions/2026-09-27-cli-deprecation-watch.md` (D-037 – D-053)
**Sibling:** `ops/research/2026-09-27-repo-mining.md` (/repo-watch, same day)

---

## 1. Executive summary

The window is sixteen days, but it carries more live drift than its length suggests. Items are listed in priority order.

1. **The release gate is red on current Claude Code.** On 2.1.283, `claude plugin validate --strict .claude-plugin/plugin.json` **fails**. Since 2.1.281 the validator warns when a shell-form hook leaves `${CLAUDE_PLUGIN_ROOT}` unquoted, and all four commands in `hooks/hooks.json` do that. The lead re-ran the check 2026-09-27. Probe **CC-06 still reports PASS** because it validates `"$REPO_ROOT"`, and a bare path resolves to the marketplace manifest only (`scripts/probe-capabilities.sh:1528`). This is a harness false green (D-039).
2. **The `opus` alias is now Claude Opus 5.5** (`claude-opus-5-5`, Claude Code ≥ 2.1.280, 1M context, default effort `medium`). The shipped ladder text says "`opus` (Opus 5)" in four byte-identical files (D-037).
3. **Claude Code reads `AGENTS.md` natively from 2.1.277**, but only when no `CLAUDE.md` exists in the working directory or above it. The user has since decided that Triforge ships **only AGENTS.md** and raises the Claude floor to **2.1.277**. D-038 records what that implies:
   - This repo's 57,066-byte `.claude/CLAUDE.md` is over Codex's 32 KiB AGENTS.md budget.
   - Any surviving `CLAUDE.md` in a user project silently suppresses AGENTS.md.
   - The ladder byte-identity set in `validate-versions.sh` needs retargeting.
4. **Three pre-agreed revisit triggers fired:**
   - **CC-03 is 3/3** on 2.1.283 (was 2/3). `/goal` gating is promoted per the D-030 watch (D-041).
   - **AGY-12 and AGY-16 PASS in two consecutive records** (2026-09-12 and 2026-09-27). The KTD10 condition for flipping `TRIFORGE_AGY_MODE` to `auto` is met (D-042).
   - **OpenCode V2 shipped** (2026-09-11, npm `@opencode/cli`). It uses the same `opencode` binary, drops `--command` and `--variant`, runs a shared background service by default, and **does not read `OPENCODE_PERMISSION`**. Triforge's deny set would be silently dropped on a V2 host (D-049).
5. **agy's headless contract changed** across 1.2.5–1.2.10:
   - Model/agent errors now exit **3** with an `AGY_ERROR:` JSON line on stderr.
   - A partial stream followed by an error exits 3 (was 0).
   - The default `-p` timeout is unlimited.
   - Headless runs kill daemon children at exit.
   - The legacy `find_by_name`/`grep_search`/`list_dir` tools left the default toolset.

   Triforge already fails these runs closed, because non-zero exits go to the classifier. It just doesn't use the new structured signal. **AGY-08 flipped FAIL→PASS** on 1.2.12: headless hooks fire again, consistent with the 1.2.4 fix for "hooks.json silently dropped under token-budget truncation" (D-043).
6. **Cursor's Grok 4.7 ids carry no `cursor-` prefix** (`grok-4.7-xhigh`). **CUR-12 flipped PASS→FAIL** because the effort-suffix composer always prepends `cursor-`. The shipped `cursor-grok-4.6-xhigh` pin still works (D-050).
7. **Research questions for the "Claude Code or Codex as lead" plan are answered in §4.** Headlines:
   - D-026 **stands**.
   - A Codex lead needs **`danger-full-access`**. Live lead re-probes on Codex 0.155.1 show that `.git` is read-only under `workspace-write`, `$HOME` writes are denied, and a nested `codex exec` **cannot start at all** inside a Codex Seatbelt sandbox.
   - One plugin tree can serve both hosts, because Codex falls back to `.claude-plugin/plugin.json`.
   - CLAUDE.md overstates the Codex AGENTS.md trust gate. It triggers only on an *explicit* `untrusted`, not on unset (D-045).
8. **Nothing forces a Codex, Gemini, or GLM pin change.**
   - `gpt-6-astra` is still Codex's first-ranked, "most capable" model. `gpt-6-sol`/`luna` arrived in 0.156.1/0.157.0.
   - No Gemini newer than 3.8 Flash exists.
   - `glm-5.3` is live; `glm-5.3-prime` is a new candidate.
   - OpenAI's effort guidance for Astra (start `low`, reviewers `high`, `xhigh` "only when evals show a clear benefit") is recorded as a finding. The `xhigh` pin is **unchanged** by instruction (D-044).
9. **Kimi Code went 0.42.0 → 2.1.1** with no break to Triforge's invoke shape. PR #3879 removed the "stay in cwd" line from Kimi's system prompt, which raises the weight of the prompt confinement already present in `kimi-agents/builder.md:34-39`. The host is AUTH-FAIL: the subscription returns 403 "does not have access" (D-051).

---

## 2. Per-CLI changelog (Triforge-relevant only)

Every row carries a primary-source URL, or a pattern given under the table heading. Pre-release rows are tagged. UI, voice, and telemetry noise is omitted.

### Claude Code: `anthropics/claude-code` (2.1.269 → 2.1.283; 14 releases, none pre-release; no 2.1.279)

Source pattern: `https://github.com/anthropics/claude-code/releases/tag/v<ver>`. The same text appears in the [CHANGELOG](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md).

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 09-11 | 2.1.269 | `/goal` retries with backoff or pauses with a reason after API/network/token errors (no silent stall) | hook | v2.1.269 |
| 09-11 | 2.1.269 | Headless sessions report "running" while background agents run (`CLAUDE_CODE_BG_TASKS_REPORT_RUNNING=0` restores old behavior) | agent-primitive | v2.1.269 |
| 09-11 | 2.1.269 | `claude plugin eval` (runs a plugin eval suite, emits JSON and HTML) | command | v2.1.269 |
| 09-14 | 2.1.271 | `omitClaudeMd` agent frontmatter / `--agents` JSON (subagent runs without CLAUDE.md) | agent-primitive | v2.1.271 |
| 09-14 | 2.1.271 | Monitor watches always have a deadline (30 min; 10 min in `-p`); the `persistent` option is removed | breaking | v2.1.271 |
| 09-15 | 2.1.273 | Subagent/background-agent final reports no longer lost (usage-less reply; stream-json after backgrounding) | agent-primitive | v2.1.273 |
| 09-17 | 2.1.274 | Active `/goal` survives `--continue`/`--resume` after compaction; `$schema` in `hooks/hooks.json` accepted | hook | v2.1.274 |
| 09-17 | 2.1.274 | Background commands stopped only at critical memory (was 30 idle minutes) | perf | v2.1.274 |
| 09-17 | 2.1.275 | claude.ai skills and plugins sync to terminal (`syncClaudeAiSkills` / `syncClaudeAiPlugins: false` opt-out) | config | v2.1.275 |
| 09-18 | 2.1.277 | **AGENTS.md support**: read when no CLAUDE.md is present; "Project instructions" in `/config` | fs-convention | v2.1.277 |
| 09-18 | 2.1.277 | TaskOutput tool removed; `taskOutputMaxChars` and `TASK_MAX_OUTPUT_LENGTH` inert | breaking | v2.1.277 |
| 09-18 | 2.1.277 | Hung `-p` after an internal error now reports and exits 1 | context | v2.1.277 |
| 09-22 | 2.1.280 | **Opus 5.5 (`claude-opus-5-5`) becomes the default Opus**: 1M context, default effort `medium` | agent-primitive | v2.1.280; [model-config](https://code.claude.com/docs/en/model-config) |
| 09-22 | 2.1.280 | Pre-per-model saved effort no longer applies to new models; agent-type `PermissionRequest` hooks error | breaking | v2.1.280 |
| 09-22 | 2.1.280 | Marketplaces whose name imitates a reserved name are refused | breaking | v2.1.280 |
| 09-23 | 2.1.281 | **`plugin validate` warns on unquoted `${CLAUDE_PLUGIN_ROOT}` in shell-form hooks**; gains MCP checks | hook | v2.1.281 |
| 09-23 | 2.1.281 | AGENTS.md support on Bedrock, Vertex, Foundry, gateways, and telemetry-off sessions; `--agents` accepts a JSON file path | fs-convention | v2.1.281 |
| 09-24 | 2.1.282 | Skill/command folders in the `anthropic-skills` namespace stop loading | breaking | v2.1.282 |
| 09-25 | 2.1.283 | `plugin validate` fails uninstallable names and out-of-root component paths; `-p` skips interactive UI load; `/doctor prompt-audit` | breaking | v2.1.283 |

No `--bare` default change appeared in the window.

### Antigravity CLI (`agy`): `google-antigravity/antigravity-cli` (1.2.1 → 1.2.12; 12 releases, none pre-release)

Source pattern: `https://github.com/google-antigravity/antigravity-cli/releases/tag/<ver>`. The web changelog (`antigravity.google/changelog?tab=cli`) lags at 1.2.9.

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 09-11 | 1.2.1 | `excludeDefaultComponents: true` agent frontmatter (drop default prompt sections and built-in tools) | agent-primitive | 1.2.1 |
| 09-12 | 1.2.2 | Deprecated `unsandboxed` permission rules warned per file, with migration to `command` rules | config | 1.2.2 |
| 09-15 | 1.2.3 | Subagents with `enable_mcp_tools` inherit parent MCP servers; `/hooks` lists plugin-bundled hooks | agent-primitive | 1.2.3 |
| 09-16 | 1.2.4 | **Fix: `hooks.json` silently dropped under customization token-budget truncation**; `/skills reload` | hook | 1.2.4 |
| 09-17 | 1.2.5 | Signal-killed commands recorded as canceled (no longer success/exit 0) | breaking | 1.2.5 |
| 09-18 | 1.2.6 | **Headless default timeout 5 min → unlimited** unless `--print-timeout` is set | breaking | 1.2.6 |
| 09-18 | 1.2.6 | **Headless API failures print `AGY_ERROR: {…}` (status, code, retryability, id) on stderr and exit 3** (was 1) | breaking | 1.2.6 |
| 09-19 | 1.2.7 | **Legacy `find_by_name` / `grep_search` / `list_dir` removed from the default toolset** (still available when listed in an agent's `tools`) | breaking | 1.2.7 |
| 09-19 | 1.2.7 | Rules get their own 20k-token budget; plugin skill commands no longer double-prefixed | context | 1.2.7 |
| 09-23 | 1.2.9 | Headless runs terminate daemon background processes on exit, and wait for background tasks up to `--print-timeout` (≤ 30 min) | breaking | 1.2.9 |
| 09-24 | 1.2.10 | **Partial stream then error exits 3 (was 0)**; JSON error output includes the partial response | breaking | 1.2.10 |
| 09-24 | 1.2.10 | `skills.json`/`agents.json` directory entries load direct children only (like `.agents/skills/`) | fs-convention | 1.2.10 |
| 09-25 | 1.2.11 | **Project agents in `.agents/agents/` found under `--agent`, headless `-p`, and trusted workspaces**; `--effort` reworked | agent-primitive | 1.2.11 |
| 09-27 | 1.2.12 | `GEMINI_API_KEY` sessions stop immediately on exhausted daily quota / spend cap | perf | 1.2.12 |

Model catalog (`agy models`, remote-served): Gemini 3.8 / 3.7 / 3.6 Flash (High|Medium|Low) and 3.1 Pro (High|Low). **Nothing newer than 3.8 Flash; no 3.5 Pro.** AGY-02 confirms the pick (`Gemini 3.8 Flash (High)`; newest Pro `Gemini 3.1 Pro (High)`).

### Codex CLI: `openai/codex` (`rust-v*`; 0.155.0 → 0.157.1 stable; 0.158.0-alpha.* / 0.159.0-alpha.* pre-release)

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 09-17 | 0.155.0 | gpt-5.2 and gpt-5.4-mini removed from the bundled catalog | breaking | [#44250](https://github.com/openai/codex/pull/44250) |
| 09-17 | 0.155.0 | `memories.version` (v1 default / v2 opt-in), `memories.dual_write`; `use_memories` still valid | config | [#43797](https://github.com/openai/codex/pull/43797) |
| 09-17 | 0.155.0 | Quota 429s map to "Quota exceeded. Check your plan and billing details." (matches `common.sh` quota regex) | breaking (error surface) | [#44492](https://github.com/openai/codex/pull/44492) |
| 09-17 | 0.155.0 | Command hooks can no longer hang on stdin; `SessionStart` gains a `fork` source | hook | [#44288](https://github.com/openai/codex/pull/44288), [#44349](https://github.com/openai/codex/pull/44349) |
| 09-22 | 0.156.0 | **Warnings for unrecognized config fields and feature keys** (per-project at thread start) | config | [#44691](https://github.com/openai/codex/pull/44691) |
| 09-22 | 0.156.0 | No implicit trust for projectless dirs; trust check after resume/fork resolution | fs-convention | [#46328](https://github.com/openai/codex/pull/46328), [#44746](https://github.com/openai/codex/pull/44746) |
| 09-22 | 0.156.0 | Path syntax rejected in `project_doc_fallback_filenames` | fs-convention | [#45865](https://github.com/openai/codex/pull/45865) |
| 09-22 | 0.156.0 | `worktrees` feature stable and on; `personality` retired | config | [#44870](https://github.com/openai/codex/pull/44870), [#45809](https://github.com/openai/codex/pull/45809) |
| 09-22 | 0.156.0 | Agent message board wired into multi-agent runtimes; subagents can request MCP elicitation | agent-primitive | [#47017](https://github.com/openai/codex/pull/47017), [#46877](https://github.com/openai/codex/pull/46877) |
| 09-23 | 0.156.1 | Hotfix: `gpt-6-sol`, `gpt-6-luna` added to the catalog | config | [rust-v0.156.1](https://github.com/openai/codex/releases/tag/rust-v0.156.1) |
| 09-25 | 0.157.0 | Migrations gpt-5.5 / 5.6-sol / 5.6-terra → gpt-6-sol and 5.6-luna → gpt-6-luna; **none target astra** | config | [#47332](https://github.com/openai/codex/pull/47332) |
| 09-26 | 0.157.1 | Windows-only daemon/MCP fixes (release body is a generation-failure notice) | perf | [rust-v0.157.1](https://github.com/openai/codex/releases/tag/rust-v0.157.1) |
| 09-23 | alpha **[pre-release]** | Portable project-trust lookup incl. linked-worktree validation | fs-convention | [#47620](https://github.com/openai/codex/pull/47620) |
| 09-24 | alpha **[pre-release]** | `write_stdin_approval` stable and default-on | config | [#47799](https://github.com/openai/codex/pull/47799) |

The `codex exec` flag surface is byte-identical between rust-v0.154.0 and rust-v0.157.1 (`exec/src/cli.rs`, `utils/cli/src/shared_options.rs`). `multi_agent_v2` is still `stable false`, and [#31097](https://github.com/openai/codex/issues/31097) is still open. The full `codex features list` is in the probe record, Appendix A.

### OpenCode: `anomalyco/opencode` (V1 1.18.31 – 1.18.32; **V2 2.0.0 – 2.0.18**)

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 09-11 | V2 2.0.0 | **OpenCode V2 released as npm `@opencode/cli`**; same `opencode` binary; the curl installer replaces V1 | breaking | [npm @opencode/cli](https://registry.npmjs.org/@opencode%2fcli), [migrate-v1](https://opencode.ai/v2/docs/migrate-v1/) |
| 09-11 | V2 2.0.0 | **Shared per-user background service by default**; `--standalone` for a private server | breaking | [v2 cli](https://opencode.ai/v2/docs/cli/) |
| 09-11 | V2 2.0.0 | `run`: `-m provider/model#variant`; **`--command` and `--variant` removed**; non-`--auto` rejects asks and exits 1 | breaking | `packages/cli/src/commands/commands.ts@v2` |
| 09-11 | V2 2.0.0 | Ordered `permissions` array (last match wins; `bash`→`shell`); plural config keys; V1 map still normalized | config | [v2 permissions](https://opencode.ai/v2/docs/permissions/) |
| 09-11 | V2 2.0.0 | Instructions: **only AGENTS.md; CLAUDE.md fallback dropped**; `.agents/skills` still discovered | context | [migrate-v1](https://opencode.ai/v2/docs/migrate-v1/), [v2 skills](https://opencode.ai/v2/docs/skills/) |
| 09-11 | V2 2.0.0 | **`OPENCODE_PERMISSION` not referenced by the V2 config loader** (`OPENCODE_CONFIG_CONTENT` is) | config | `packages/core/src/config.ts@v2` |
| 09-14 | 1.18.31 | ACP/Copilot fixes (no `run`/permission/skills change) | perf | [v1.18.31](https://github.com/anomalyco/opencode/releases/tag/v1.18.31) |
| 09-17 | V2 2.0.7 | Hard-deny permission policies (`experimental.policies`) | config | [fa126d68e](https://github.com/anomalyco/opencode/commit/fa126d68e) |
| 09-21 | 1.18.32 | Bedrock/Together fixes; Grok 4.7 in Zen/Go | perf | [v1.18.32](https://github.com/anomalyco/opencode/releases/tag/v1.18.32) |
| 09-23 | catalog | `openrouter/z-ai/glm-5.3-prime` (newest GLM, ~2× price); `glm-5.3` still listed | config | [openrouter models](https://openrouter.ai/api/v1/models) |

**Supply-chain decoy:** the npm package `opencode2` (created 2026-09-25, maintainer `thanhvinh1`, repo `game-libgdx-unity/opencode2`) is a third-party fork. Its version numbers shadow the official ones. It is not V2.

### Kimi Code CLI: `MoonshotAI/kimi-code` (0.43.0 → 2.1.1; 7 releases, none pre-release)

Source pattern: `https://github.com/MoonshotAI/kimi-code/releases/tag/%40moonshot-ai/kimi-code%40<ver>`. PR pattern: `https://github.com/MoonshotAI/kimi-code/pull/<n>`.

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 09-14 | 0.43.0 | `rm -rf` limited to /tmp paths no longer asks; `loop_control.compaction_max_attempts` | agent-primitive | #3714, #3750 |
| 09-17 | 2.0.0 | Major bump; only `major` changeset is `/desktop` + `install-app` (no documented break) | command | #3849 |
| 09-18 | 2.0.1 | **Fix: `kimi -p` exited early when a cron task fired** | flag | #3875 |
| 09-18 | 2.0.1 | **System prompt no longer forbids file access outside cwd** (path-access layer + permission mode govern) | context | #3879 |
| 09-18 | 2.0.1 | `api_key_env` provider option | config | #3762 |
| 09-23 | 2.1.0 | Trust hardening (symlink realpath, `local.toml` trust gate, background git `core.hooksPath=/dev/null`) | breaking (reverted) | #3964 |
| 09-24 | 2.1.1 | **Reverts all of #3964** except "failed trust read = untrusted" | breaking | #4013 |

The headless contract is unchanged: `-p` cannot combine with `--yolo`/`--auto`; `--output-format stream-json`; `--agent-file` takes a single file. The model id `kimi-code/k3` is unchanged, but the docs now lean on `kimi-code/kimi-for-coding`.

### Cursor CLI (`cursor-agent` / `agent`): changelog only through "August 26, 2026"; build `2026.09.26-dd393fe` published

| Date | Build | Feature | Category | Source |
|---|---|---|---|---|
| 09-21 | server-side | **Grok 4.7** (xhigh / high (default) / medium / low; effort levels "more separated than 4.6"); 4.6 still available | config | [forum](https://forum.cursor.com/t/grok-4-7-is-now-live/172526), [grok-4-7 docs](https://cursor.com/docs/models/grok-4-7.md) |
| ≤ 09-26 | 2026.09.26-dd393fe | New build; no changelog entry; installer still links **both** `agent` and `cursor-agent` | fs-convention | [install script](https://cursor.com/install) (read, not executed) |
| 09-27 | host catalog | Grok 4.7 ids are **`grok-4.7-{low,medium,high,xhigh}[-fast]`, with no `cursor-` prefix**; 4.6 keeps `cursor-grok-4.6-*` | config | probe record Appendix B (CUR-03) |

---

## 3. Gap analysis vs current Triforge (v3.3.1)

Every "Used in Triforge?" cell was grep-verified 2026-09-27.

| Feature | CLI | Used in Triforge? | Action | Reasoning |
|---|---|---|---|---|
| Unquoted `${CLAUDE_PLUGIN_ROOT}` fails `validate --strict` (2.1.281) | Claude | **Y (4 hooks)** | **Adopt** | `hooks/hooks.json:9,20,24,35` use `bash ${CLAUDE_PLUGIN_ROOT}/…`. The lead ran `claude plugin validate --strict .claude-plugin/plugin.json` on 2.1.283: ✘ 4 warnings → failed. Quote the placeholder (or use exec form). Release checklist item 1 is red today. |
| CC-06 validates the marketplace only | harness | **Y (false green)** | **Adopt (harness, follow-up sprint)** | `scripts/probe-capabilities.sh:1528` validates `"$REPO_ROOT"`; its evidence line reads "Validating marketplace manifest … passed". Validate both manifests, as release checklist item 1 already requires. This cycle does not edit the harness (protected path). |
| `opus` alias = Opus 5.5 (≥ 2.1.280) | Claude | **N ("Opus 5")** | **Adopt** | `.claude/CLAUDE.md:15,26,112,395`, `templates/CLAUDE.md:15,25`, `skills/wave-orchestration/SKILL.md:232`, `agents/team-lead.md`, `README.md:33`. Ladder md5 set changes together. Shipped agents set `effort:` explicitly, so the `medium` default does not bite. |
| AGENTS.md read natively (2.1.277; precedence: CLAUDE.md wins) | Claude | **N (CLAUDE.md everywhere)** | **Adopt (user-directed, D-038)** | Ship AGENTS.md only; floor → 2.1.277. `.claude/CLAUDE.md` (57,066 B) would suppress a root AGENTS.md; `templates/CLAUDE.md` (16,508 B) becomes the AGENTS.md template. |
| `omitClaudeMd` frontmatter (2.1.271) | Claude | N | Document | Add to the frontmatter field list. Whether it also omits an AGENTS.md read through the built-in is **not documented**, so no Triforge agent adopts it yet. |
| TaskOutput removed; Monitor `persistent` removed; agent-type PermissionRequest hooks error | Claude | **N (grep: no hits in agents/commands/skills/scripts)** | Keep | No Triforge usage. |
| `/goal` 3/3 (CC-03) | Claude | **Y (best-effort, `scripts/coordinate.sh`)** | **Adopt (trigger met)** | The D-030 open-watch trigger fired: CC-03 went from 2/3 (2026-09-12) to 3/3 (2026-09-27). |
| agy rc 3 + `AGY_ERROR` JSON; partial-then-error exits 3 | agy | **partial** | **Evaluate** | `scripts/lib/antigravity.sh:147-151` routes any non-zero exit to `_classify_invoke_failure` (fails closed). It does not read `AGY_ERROR` retryability or keep the partial response. |
| Headless default timeout unlimited (1.2.6) | agy | **Y (safe)** | Keep | `antigravity.sh:122` always passes `--print-timeout "${TIMEOUT}s"` inside an outer `_run_with_timeout`. |
| Legacy search tools out of the default toolset (1.2.7) | agy | **Y (injection default)** | **Adopt (via D-042)** | `antigravity-agents/agents/*.md:8` list `list_dir`/`find_by_name`/`grep_search`, which native mode keeps. Injection mode runs the *default* agent, which no longer has them. Another reason to flip to `auto`. |
| AGY-12/AGY-16 PASS two consecutive records | agy | **Y (injection default, KTD10)** | **Adopt** | Flip `TRIFORGE_AGY_MODE` default to `auto` (KTD10 condition met). |
| Headless hooks fire again (AGY-08 PASS on 1.2.12) | agy | N (ships none) | Document | Update the "open watch" wording in `.claude/CLAUDE.md` Security model. Triforge still relies on no agy hooks. |
| `.agents/agents/` now found headless (1.2.11) | agy | **N (never deploy there)** | Keep | Strengthens the KTD13 rule (agy and Kimi both scan it). |
| `excludeDefaultComponents` (1.2.1) | agy | N | Evaluate | Could harden `architecture-reviewer` / `documentation-writer`; optional. |
| `gpt-6-sol` / `gpt-6-luna` (0.156.1/0.157.0) | Codex | N | Keep (Astra) | Astra is still priority 1 and "most capable". The user's rule is the latest flagship. |
| Astra effort guidance (start `low`; reviewers `high`) | Codex | **Y (`xhigh`)** | **Document only** | `codex-agents/agents.toml` `model_reasoning_effort = "xhigh"`. User instruction: record, do not change the pin. |
| Unknown-config-key warnings (0.156.0) | Codex | **partial** | Verify | `templates/.codex/config.toml` keys are valid. `codex-agents/agents.toml` `[agents]` carries non-schema keys (`job_max_runtime_seconds`, `max_threads`); harmless because Codex never loads that file. |
| AGENTS.md trust gate is *explicit untrusted* only | Codex | **Y (wording wrong)** | **Adopt doc fix** | `.claude/CLAUDE.md:161` and the Compatibility section say project AGENTS.md is skipped when unset. Source gates on `is_untrusted()` (PR #39837). |
| AGENTS.md 32 KiB combined budget, silent mid-file truncation | Codex | **N (would bite AGENTS.md-only)** | **Adopt (constraint on D-038)** | 57,066 B → ~43% truncated, cut inside "Security model". |
| `.codex/agents/<name>.toml` native custom agents | Codex | N (`.codex/triforge-agents.toml`) | Keep (D-026 stands) | §4 Q3. |
| OpenCode V2 (`@opencode/cli`) | OpenCode | **Y (V1 flags)** | **Adopt guard / Defer port** | `scripts/lib/lease.sh:618-619` uses `--variant`; `scripts/lib/opencode.sh` rides `OPENCODE_PERMISSION` (V2 ignores it); `.claude/CLAUDE.md` lists `opencode run --command`. Fail closed on `opencode --version` ≥ 2 until ported. |
| OC-06 deny under `--auto` | OpenCode | **N (adapter off `--auto`)** | Keep (D-033) | Source reading says deny holds; the live probe FAILs again on 1.18.30. |
| `glm-5.3-prime` | OpenCode | N (`glm-5.3`) | Evaluate | New top tier at ~2× price; the pin decision goes to the user. |
| Grok 4.7 ids have no `cursor-` prefix | Cursor | **Y (composer)** | **Adopt fix** | `scripts/lib/roster.sh:664-667` and `_cursor_model_for_effort` always emit `cursor-<fam>-<sfx>` → `cursor-grok-4.7-xhigh` is rejected (CUR-12 FAIL). Keep the 4.6 pin until the composer uses the catalog's actual form. |
| Cursor reads root AGENTS.md and CLAUDE.md as rules | Cursor | **Y (lease builders)** | Verify | With AGENTS.md-only, Cursor lease builders load the project AGENTS.md from the worktree. Confirm the lease contract prompt takes precedence. |
| Kimi 2.x; #3879 no cwd-confinement line | Kimi | **Y (`kimi-agents/builder.md:34-39`)** | Keep + Verify | Explicit confinement already present. Avoid pinning 2.1.0 (reverted hardening). Floor unchanged until live-proven (AUTH-FAIL). |
| Watch-cycle tooling (firecrawl 1.24.6, chrome-devtools-mcp 1.10.1, gh 2.97.0) | tooling | n/a | — | Changelog and routing check only (§5), per the registry `tier = "tooling"` rule. |

---

## 4. Lead-orchestrator research questions (input to the "Claude Code or Codex as lead" plan)

### Q1. Claude Code AGENTS.md support
- **Version:** **2.1.277**. [CHANGELOG](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md): "Added AGENTS.md support: in a project with no CLAUDE.md, Claude Code reads AGENTS.md instead". It was extended in 2.1.281 to Bedrock, Vertex, Foundry, gateways, and telemetry-off sessions.
- **Discovery** ([memory docs](https://code.claude.com/docs/en/memory)):
  - "every `AGENTS.md` and `.claude/AGENTS.md` in your working directory and the directories above it" at session start.
  - A subdirectory's AGENTS.md loads when Claude Reads a file there and that directory has no CLAUDE.md.
  - `@path` imports are expanded.
  - `AGENTS.local.md`, `AGENTS.override.md`, and `.agents/` are **not** read.
- **Precedence:**
  - "By default, Claude reads `AGENTS.md` only when you have no `CLAUDE.md` in your working directory or above it." `CLAUDE.md`, `.claude/CLAUDE.md`, and `CLAUDE.local.md` all count. `~/.claude/CLAUDE.md` and managed CLAUDE.md do not.
  - If both exist and disagree, **CLAUDE.md wins by exclusion**: AGENTS.md is not loaded at all.
  - The alternative mode `claude-md-and-agents-md` loads each directory's CLAUDE.md first, then its AGENTS.md. It is set only via `pluginConfigs["agents-md@builtin"].options.instructionFiles` in **user/managed** settings. "Claude Code ignores it in project and local settings files", so a plugin or repo cannot change it.
- **`claude -p`:** there is no AGENTS.md-specific statement. `-p` "loads the same context as an interactive session" unless `--bare` ([headless](https://code.claude.com/docs/en/headless)). Medium confidence; there is no probe row yet.
- **Triforge note:** `ops/AGENTS.md` sits in a subdirectory. Claude will now auto-load it when it Reads a file under `ops/` (no `ops/CLAUDE.md` exists). That is desirable for the protocol file, but it is a new behavior to be aware of.

### Q2. Plugin layout interop
- **Claude Code reads only `.claude-plugin/plugin.json`**, which is optional ("Without it, Claude Code loads the components it finds in the standard layout"; [plugins-reference](https://code.claude.com/docs/en/plugins-reference)). There is no root `plugin.json` or `.codex-plugin/` support in primary sources.
- **Codex manifest resolution:**
  - A root `plugin.json` counts only when it declares the agent-plugins schema. Otherwise the order is `.codex-plugin/plugin.json` → **`.claude-plugin/plugin.json`** → `.cursor-plugin/plugin.json` (`codex-rs/exec-server-protocol/src/lib.rs`).
  - Codex also reads `.claude-plugin/marketplace.json` (`core-plugins/src/marketplace.rs`).
  - Install: `codex plugin marketplace add owner/repo`, then `codex plugin add PLUGIN@MARKETPLACE`.
- **What Codex's plugin format supports:**
  - **skills/:** discovered.
  - **hooks/hooks.json:** discovered, with `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` set "for compatibility". Plugin hooks are trust-gated until reviewed, and prompt/agent hook types are not run.
  - **MCP:** root `mcp.json` (portable) or `.mcp.json` (legacy).
  - **commands/*.md:** migrated to skills. Anything over **4,000 bytes is silently skipped** (`command_migration.rs`); 9 of Triforge's 17 commands exceed that.
  - **Agents:** plugin-bundled **agents are not supported**.
  - Sources: [build plugins](https://developers.openai.com/plugins/build/plugins), [submit-claude-plugin](https://developers.openai.com/plugins/guides/submit-claude-plugin).
- **Answer:** one tree and **one manifest works today**, because Codex falls back to `.claude-plugin/plugin.json`. This is from source and docs, not yet probed live.
  - Add an optional `.codex-plugin/plugin.json` only to control Codex-specific fields.
  - Do **not** add a root agent-plugins `plugin.json`: it would become Codex's canonical manifest, and Claude Code ignores it.
  - Shareable: `skills/`, `hooks/hooks.json` (after a Codex audit).
  - Claude-only: `agents/`, `settings.json`.
  - Lossy on Codex: `commands/`.
  - Marketplace entries should gain `policy.installation` / `policy.authentication` for Codex.

### Q3. Codex native custom agents: does this reverse D-026? **No. D-026 stands.**
- **Schema** ([subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)):
  - Documented: "Each file defines one custom agent … must define: `name`, `description`, `developer_instructions`", plus any `config.toml` key (`model`, `model_reasoning_effort`, `sandbox_mode`, `mcp_servers`, `skills.config`).
  - Source: `RawAgentRoleFileToml` is `deny_unknown_fields` + `nickname_candidates`.
- **Invocation:** custom agents are **spawn targets only**. `codex exec` has no agent selector on 0.155.1 or 0.157.1. A child also "reapplies the parent turn's live runtime overrides", including sandbox and approval.
- **Trust:** project `.codex/agents/` is not loaded unless the project is trusted.
- **Why the current files can't simply move there:**
  - Triforge's `tools = [...]` array collides with Codex's `tools` table.
  - `output_schema` is not a config key.

  So a straight split would still be "malformed". It would also give headless dispatch nothing, since exec cannot select the agent and the replay model in `scripts/lib/codex.sh` already delivers every key.
- **Revisit only if** a Codex lead should spawn Triforge roles *as native subagents*. That is a lead-choice-plan item, not a D-026 reversal.

### Q4. Settings for a Codex LEAD that launches `claude -p` / `agy` / `codex exec`, creates worktrees, and waits 600–900 s

**Docs and source:**
- **Sandbox:**
  - "`<writable_root>/.git` is protected as read-only … `.agents` … `.codex` … Protection is recursive" ([approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security)). `writable_roots` / `--add-dir` do not lift it (issues #15505, #23661, #48717).
  - Network is off by default in `workspace-write`. `[sandbox_workspace_write] network_access = true` applies to subprocesses. An optional domain allowlist exists via `features.network_proxy`.
- **Approvals:**
  - Values are `on-request | never | granular`. `untrusted` is unsupported and `on-failure` is deprecated ([config reference](https://learn.chatgpt.com/docs/config-file/config-reference)).
  - `codex exec` forces `never` (`exec/src/lib.rs`) and rejects any approval request that still arrives.
  - "In non-interactive flows … an action that needs new approval fails."
- **Subagents:** "Subagents inherit your current sandbox policy" and re-apply the parent's live overrides ([subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents)).
- **Long jobs:**
  - Unified exec is on (`unified_exec stable true`).
  - `exec_command` yields after ≤ 30 s and keeps the process alive. The lead polls with empty `write_stdin`, up to `background_terminal_max_timeout` (default 300,000 ms; set 900,000).
  - It is not established whether background processes survive the end of an `exec` run. Assume the lead must wait inside its turn.

**Lead re-probes** (2026-09-27, Codex 0.155.1, macOS Seatbelt, throwaway git fixture, via `codex sandbox -c sandbox_mode="workspace-write"`):

| Probe | Result |
|---|---|
| LEAD-01 write in cwd | PASS |
| LEAD-02 `git worktree add ../wt -b probe` | **FAIL**: `cannot lock ref … .git/refs/heads/probe.lock: Operation not permitted` |
| LEAD-03 `git commit` | **FAIL**: `.git/index.lock: Operation not permitted` |
| LEAD-04 write under `$HOME` (outside cwd) | **FAIL** (`Operation not permitted`) |
| LEAD-05 read `~/.claude` | PASS |
| LEAD-06 network default → `curl https://api.anthropic.com` | **FAIL** (`000`, rc 6) |
| LEAD-07 `network_access=true` → same curl | PASS (HTTP 404 from the API root = reachable). #10390 did not reproduce. |
| LEAD-08 nested `codex sandbox` (inner read-only) | **FAIL**: `sandbox-exec: sandbox_apply: Operation not permitted` (rc 71) |
| LEAD-09 nested `codex sandbox` (inner danger-full-access) | PASS |
| LEAD-10 `CODEX_SANDBOX` inside the sandbox | `seatbelt` (detectable) |
| LEAD-11 `git worktree add` under `danger-full-access` | PASS |
| LEAD-12 `claude -p "Respond with only: READY"` under workspace-write + network | **PASS** (READY) |
| LEAD-13 `agy --output-format json -p READY` under workspace-write + network (agy 1.2.2 at the time) | **PASS, degraded**: `status=SUCCESS response=READY`, but 23 `operation not permitted` state-write denials (`~/.gemini/antigravity-cli/…`) |
| LEAD-14 `codex exec -s read-only READY` under workspace-write + network | **FAIL**: `failed to initialize in-process app-server client: Operation not permitted` |
| LEAD-15 `codex exec -s danger-full-access --ephemeral READY` under the same | **FAIL** (same app-server error) |

**Answer:** a `workspace-write` Codex lead cannot:
- create lease worktrees or commit (`.git` is protected);
- launch any `codex exec` worker (LEAD-14/15);
- give agy durable state.

The workable profile today is **`-s danger-full-access -c approval_policy="never" -c background_terminal_max_timeout=900000`**. Prefer `-s danger-full-access` over `--yolo`, which also skips the git-repo check. Safety then rests on Triforge's leases, cross-review, and the lease env allowlist, the same trust model as the shipped Codex agents' `approval_policy = "never"`.

A hardened profile is a later probe target: `workspace-write` + network + user-tier execpolicy `prefix_rule(decision="allow")` for a dispatch wrapper outside the workspace, or a permission profile with `".git" = "write"`. Candidate harness rows are listed in the ADR open watches.

### Q5. Codex AGENTS.md size cap and trust gating
- **Cap:** `project_doc_max_bytes` defaults to **32 KiB (32,768 bytes)** (`config_toml.rs:74`; [agents-md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)).
  - It is **one combined budget** across the root→cwd chain, and the overflowing file is truncated mid-file (`agents_md.rs`, `data.truncate(remaining)`) with only a `tracing::warn`. The model is not told.
  - config-advanced.md's "per file" wording contradicts the source.
  - Discovery: project root by `.git`, walk root→cwd, one file per directory (`AGENTS.override.md` > `AGENTS.md` > `project_doc_fallback_filenames`). Path syntax in fallbacks is rejected since 0.156.0.
- **Trust:**
  - 0.150.0 "Untrusted projects no longer supply project-level `AGENTS.md`" (PR #39837). The gate is `is_untrusted()`, i.e. **explicit** `trust_level = "untrusted"` only. Unset still loads AGENTS.md.
  - `.codex/config.toml`, hooks, and rules differ: unset = untrusted.
  - CDX-10 PASS (trust entry present; root-AGENTS.md marker visible).
- **Size check:** this repo's `.claude/CLAUDE.md` is **57,066 bytes**. As a Codex AGENTS.md it would lose ~24 KB (~43%), cut inside "Security model". `templates/CLAUDE.md` (16,508 B) fits.

### Q6. Reasoning effort for `gpt-6-astra` (finding only; pin unchanged)
- **Levels:**
  - API: `low | medium | high | xhigh | max` ([gpt-6-astra](https://developers.openai.com/api/docs/models/gpt-6-astra.md)).
  - Codex adds `ultra` ("Available levels depend on the model and client").
  - The bundled catalog's default is `low`.
  - CDX-06/07 PASS (`max`, `ultra` accepted).
- **Start:** "Start with **Medium** for Sol, **High** for Luna, or **Light** for Astra. In configuration, Astra's Light setting is `low`." ([models](https://learn.chatgpt.com/docs/models.md))
- **Reviewers:**
  - Codex subagents doc: "**`high`**: … (for example, reviewer or security-focused agents)."
  - The API reasoning guide lists "security and code review" under **`xhigh`**, "Only use when your evals show a clear benefit that justifies the extra latency and cost" ([reasoning](https://developers.openai.com/api/docs/guides/reasoning.md)).
- **Finding:** Triforge's `xhigh` sits within the API guide's code-review band, but above the Codex docs' `high` for reviewers and well above the `low` start. **No pin change** (user instruction). A cost/latency A/B is a candidate for a future cycle.

---

## 5. Watch-cycle tooling (`tier = "tooling"`: changelog + routing check only; no gap analysis, no probe rows)

The routing under check is `.claude/skills/watch-cycle/SKILL.md` Stage 2:
- `gh api` / raw for GitHub;
- `firecrawl scrape "<url>" --only-main-content` and `firecrawl search` for docs pages;
- `chrome-devtools new_page` → `list_pages` → `evaluate_script … --pageId <id>` / `take_snapshot` for pages firecrawl cannot render.

### firecrawl (`firecrawl/cli`): installed 1.24.6 (lead upgraded from 1.16.2 today)

| Date | Version | Change relevant to the routing | Source |
|---|---|---|---|
| 09-21 | 1.24.0 | `scrape --max-pages` caps PDF parsing (#243); search sends the documented default limit (#250); provider/capability shorthand in `scrape` (#254); `credits`/`status`/`formats` aliases (#242) | [v1.24.0](https://github.com/firecrawl/cli/releases/tag/v1.24.0) |
| 09-22 | 1.24.1 – 1.24.4 | Alexandria (catalogue) docs and feedback; `search` highlights/categories clarified; init fixes | [releases](https://github.com/firecrawl/cli/releases) |
| 09-25 | 1.24.5 – 1.24.6 | Experimental Alexandria syntax; new top-level `sql` command | [v1.24.6](https://github.com/firecrawl/cli/releases/tag/v1.24.6) |

**Routing check (2026-09-27):**
- `firecrawl scrape "https://github.com/cli/cli/releases/tag/v2.101.0" --only-main-content` → rc 0, markdown returned.
- `firecrawl search "chrome-devtools-mcp 1.10 release" --limit 2` → web results returned.
- **Routing intact.** Node prints an `ExperimentalWarning` (localStorage) on stderr, which is harmless.

### chrome-devtools (`ChromeDevTools/chrome-devtools-mcp`): installed 1.10.1 (lead upgraded from 1.5.0 today)

| Date | Version | Change relevant to the routing | Source |
|---|---|---|---|
| 09-23 | 1.10.0 | Config-file support (#2661); `cli: forward explicit false options on start` (#2702); page-routing option renamed in docs (#2748); tools disabled rather than unregistered (#2636); MCP SDK v2 (#2408) | [v1.10.0](https://github.com/ChromeDevTools/chrome-devtools-mcp/releases/tag/chrome-devtools-mcp-v1.10.0) |
| 09-23 | 1.10.1 | Rollup bundle export-condition fix | [v1.10.1](https://github.com/ChromeDevTools/chrome-devtools-mcp/releases/tag/chrome-devtools-mcp-v1.10.1) |

**Routing check (2026-09-27):**
- `new_page "https://example.com"` → listed as page 3.
- `list_pages` → IDs present.
- `evaluate_script "() => document.title" --pageId 3` → `"Example Domain"`.
- **The same call without `--pageId` errors:** `Error: specify either a pageId or a serviceWorkerId.` This confirms the lead's note that `--pageId` is now required. The skill's routing already passes it.
- `close_page 3` → OK.
- **Routing intact**, provided `--pageId` is always passed. `start --headless --isolated` was not needed; the shared instance was already running.

### gh (`cli/cli`): installed 2.97.0 (2026-07-31); latest 2.101.0

| Date | Version | Change relevant to the routing | Source |
|---|---|---|---|
| 09-15 | 2.101.0 | `gh auth login/refresh` copy device codes to the clipboard by default (`gh config set clipboard disabled`); Linux APT/RPM signing-key rotation; API SSH URLs for clones; multi-account migration retired | [v2.101.0](https://github.com/cli/cli/releases/tag/v2.101.0) |

**Routing check (2026-09-27):**
- `gh api repos/cli/cli/releases/latest` → `v2.101.0`.
- `gh release list/view` → used across this cycle; `gh release view v3.3.1` → `v3.3.1 2026-09-12`.
- `gh workflow run --help` → `-f/-F` field flags present.
- **Routing intact.** The host is four minor versions behind (2.98.0–2.101.0 all shipped after 2.97.0). No routing command is affected.

---

## 6. Top prioritized adoption candidates (for the follow-up sprint)

### #1. Make the release gate green again (D-039)
- **Why:** `validate --strict` on `plugin.json` fails on 2.1.283, and CC-06 hides it.
- **Change:**
  - Quote `"${CLAUDE_PLUGIN_ROOT}"` in all four `hooks/hooks.json` commands, or use exec form.
  - Change CC-06 to validate `.claude-plugin/plugin.json` **and** `.claude-plugin/marketplace.json` (protected path: lead or user review).
- **Verify:** both strict validations ✔; CC-06 evidence names both manifests.

### #2. AGENTS.md-only + Claude floor 2.1.277 + Opus 5.5 rung (D-037, D-038; user-directed)
- **Change:**
  - `templates/CLAUDE.md` → `templates/AGENTS.md`.
  - Replace this repo's `.claude/CLAUDE.md` with a root `AGENTS.md` **≤ 32 KiB**. Move the long reference sections into `docs/` and link them. For Codex, stay under budget including any `ops/`-level file on the walk path.
  - Session-start: warn when a user project already has `CLAUDE.md`, `.claude/CLAUDE.md`, or `CLAUDE.local.md`, since those suppress AGENTS.md. Never delete the user's file.
  - Retarget the ladder md5 set in `scripts/validate-versions.sh` from the CLAUDE.md files to AGENTS.md.
  - Update the ladder text to "`opus` (Opus 5.5 on ≥ 2.1.280; Opus 5 on 2.1.277–2.1.279)".
  - Update the floors table.
- **Verify:**
  - `claude -p` in a fixture with only AGENTS.md sees a marker. Needs a new CC row; `-p` loading is not yet documented explicitly.
  - CDX-10 still PASS.
  - `wc -c AGENTS.md` < 32768.

### #3. Promote `/goal` and flip agy routing to `auto` (D-041, D-042)
- **Change:**
  - `scripts/coordinate.sh` and `/ship`: the `/goal` line goes from advisory to required. `ops/.sprint-complete` stays the detector.
  - `TRIFORGE_AGY_MODE` default `injection` → `auto` in `scripts/lib/antigravity.sh` and docs.
- **Verify:** CC-03 ≥ 3/3 and AGY-12/16 PASS in the next record; revert either on regression.

### #4. OpenCode V2 fail-closed guard (D-049)
- **Change:** `invoke_opencode` / the lease `opencode)` arm refuse when `opencode --version` major ≥ 2, naming the V1 pin (`npm i -g opencode-ai@1`). `/setup` detects V2. The V2 port (`--standalone`, `#variant`, `OPENCODE_CONFIG_CONTENT` with an ordered `permissions` array) is a separate sprint.
- **Verify:** a stub `opencode --version` → `2.0.18` fixture → deterministic refusal.

### #5. Cursor composer handles un-prefixed families (D-050)
- **Change:** `roster.sh:664-667` and `_cursor_model_for_effort` choose `cursor-` only when the catalog lists that form (`cursor-agent models`), or keep the prefix as written. Then evaluate `grok-4.7-xhigh` as the pin.
- **Verify:** CUR-12 PASS on `grok-4.7-xhigh`.

### #6. agy structured failure signal + Codex AGENTS.md wording (D-043, D-045)
- **Change:**
  - Parse `AGY_ERROR:` retryability in `invoke_antigravity`'s non-zero branch.
  - Fix the Codex trust wording in `.claude/CLAUDE.md` Security model + Compatibility, and in `templates/.codex/README.md`.
- **Verify:** an rc-3 fixture maps to retryable/deterministic from the JSON field.

---

## 7. Risks: changes that could affect Triforge

| Risk | Severity | Note |
|---|---|---|
| Release blocked by strict validation | **High** | Every release until #1 lands; CC-06 masks it |
| A stray CLAUDE.md silently disables AGENTS.md (Claude) | **High** under D-038 | Project settings can't switch modes; only warn and document |
| Codex truncates an oversized AGENTS.md silently | **High** under D-038 | 32 KiB combined; no model-visible signal |
| OpenCode V2 on a host drops the deny set | **High** (optional tier) | `OPENCODE_PERMISSION` ignored; shared service escapes the `env -i` boundary unless `--standalone` |
| agy exit semantics moved twice in 10 days | Medium | Fails closed today; watch for further changes |
| Kimi 2.x confinement relies on Triforge's prompt | Medium | #3879 and the 2.1.1 revert; live lane unproven (AUTH-FAIL) |
| `opencode2` npm decoy | Medium | Never install; registry note |
| Grok 4.7 composer breakage if a user writes `grok-4.7` via `/setup` | Medium | `roster_write_role` would store a rejected id |
| Hosts behind upstream (Codex 0.155.1 vs 0.157.1; Cursor 09.10 vs 09.26; Kimi 0.42 vs 2.1.1; gh 2.97 vs 2.101) | Low | Re-probe after upgrade |

---

## 8. Flagged targets (continue-and-flag)

No target hard-failed Stage 1. 27/27 registry URLs are HTTPS + public-host OK. The registry now has 9 `[cli.*]` entries (6 dispatched + 3 tooling); `meta.cli_count = 9`. Soft issues:

| Target | Registry URL | Problem | Evidence | Suggested registry fix |
|---|---|---|---|---|
| cli.antigravity `docs` | https://antigravity.google/docs/cli/getting-started | Redirects to `/docs/getting-started?tab=cli`; install and slash commands only | worker fetch 2026-09-27 | Point at the redirect target; keep `agy changelog` + GitHub releases as primary |
| cli.antigravity `changelog` | https://antigravity.google/changelog?tab=cli | Lags GitHub (stops at 1.2.9, summaries only) | worker fetch 2026-09-27 | Note "GitHub releases are the full text" |
| cli.cursor `changelog` | https://cursor.com/changelog | CLI changelog frozen at "August 26, 2026" while builds ship (09.26) | worker fetch 2026-09-27 | Add `https://cursor.com/docs/cli/changelog` and note "builds outpace the changelog; read the installer" |
| cli.opencode `docs` / `note` | https://opencode.ai/docs | V2 docs live at `/v2/docs`; the npm decoy `opencode2` exists | worker fetch + npm registry 2026-09-27 | Add a V2 docs URL; extend `note` with "`@opencode/cli` = V2; `opencode2` on npm is a decoy" |
| cli.kimi `note` | — | Docs now prefer `kimi-code/kimi-for-coding` over versioned ids | `docs/AGENTS.md` in repo | Note the alias drift |

---

## 9. Sources appendix

- **Claude Code:**
  - [releases](https://github.com/anthropics/claude-code/releases) · [CHANGELOG (raw)](https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md)
  - docs: [memory (AGENTS.md)](https://code.claude.com/docs/en/memory) · [plugins-reference](https://code.claude.com/docs/en/plugins-reference) · [plugins troubleshooting](https://code.claude.com/docs/en/plugins/troubleshooting) · [headless](https://code.claude.com/docs/en/headless) · [model-config](https://code.claude.com/docs/en/model-config) · [sub-agents](https://code.claude.com/docs/en/sub-agents)
  - [models overview](https://platform.claude.com/docs/en/about-claude/models/overview)
- **Antigravity:**
  - `agy changelog` (bundled) · `agy --help` · `agy models`
  - [releases 1.2.1–1.2.12](https://github.com/google-antigravity/antigravity-cli/releases) · [web changelog](https://antigravity.google/changelog?tab=cli)
- **Codex:**
  - [releases (`rust-v*`)](https://github.com/openai/codex/releases) · [changelog](https://learn.chatgpt.com/docs/changelog?type=codex-cli)
  - docs: [subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents) · [agents-md](https://learn.chatgpt.com/docs/agent-configuration/agents-md) · [sandboxing](https://learn.chatgpt.com/docs/sandboxing) · [approvals & security](https://learn.chatgpt.com/docs/agent-approvals-security) · [permissions](https://learn.chatgpt.com/docs/permissions) · [rules](https://learn.chatgpt.com/docs/agent-configuration/rules) · [non-interactive](https://learn.chatgpt.com/docs/non-interactive-mode) · [config reference](https://learn.chatgpt.com/docs/config-file/config-reference) · [models](https://learn.chatgpt.com/docs/models.md) · [plugins](https://learn.chatgpt.com/docs/plugins) · [build plugins](https://developers.openai.com/plugins/build/plugins) · [submit-claude-plugin](https://developers.openai.com/plugins/guides/submit-claude-plugin)
  - API: [gpt-6-astra](https://developers.openai.com/api/docs/models/gpt-6-astra.md) · [reasoning](https://developers.openai.com/api/docs/guides/reasoning.md)
  - source at `rust-v0.155.1` / `rust-v0.157.1` (`exec/src/{cli,lib}.rs`, `core/src/agents_md.rs`, `config/src/{config_toml,state}.rs`, `config/src/loader/mod.rs`, `agent-roles/src/*`, `core-plugins/src/{marketplace,command_migration}.rs`, `exec-server-protocol/src/lib.rs`, `protocol/src/permissions.rs`, `sandboxing/src/*`, `core/src/unified_exec/*`)
  - issues [#31097](https://github.com/openai/codex/issues/31097), #10390, #14338, #15505, #15524, #23661, #24461, #26262, #30615, #45657, #48717
  - [openai/plugins](https://github.com/openai/plugins)
- **OpenCode:**
  - [releases](https://github.com/anomalyco/opencode/releases) · branch `v2` (tags v2.0.0–v2.0.18)
  - [v2 docs](https://opencode.ai/v2/docs/) ([migrate-v1](https://opencode.ai/v2/docs/migrate-v1/), [cli](https://opencode.ai/v2/docs/cli/), [permissions](https://opencode.ai/v2/docs/permissions/), [skills](https://opencode.ai/v2/docs/skills/))
  - npm [`opencode-ai`](https://registry.npmjs.org/opencode-ai) · [`@opencode/cli`](https://registry.npmjs.org/@opencode%2fcli) · [`opencode2` (decoy)](https://registry.npmjs.org/opencode2)
  - [OpenRouter models](https://openrouter.ai/api/v1/models)
  - The decoy domain `open-code.ai` was never contacted.
- **Kimi Code:**
  - [releases](https://github.com/MoonshotAI/kimi-code/releases) · PRs #3714, #3750, #3762, #3849, #3864, #3869, #3875, #3879, #3894, #3929, #3964, #4013
  - [docs](https://moonshotai.github.io/kimi-code/) (kimi-command, agents, skills, providers, config-files)
- **Cursor:**
  - [changelog](https://cursor.com/changelog) · [CLI changelog](https://cursor.com/docs/cli/changelog.md)
  - docs: [parameters](https://cursor.com/docs/cli/reference/parameters.md) · [permissions](https://cursor.com/docs/cli/reference/permissions.md) · [configuration](https://cursor.com/docs/cli/reference/configuration.md) · [skills](https://cursor.com/docs/skills.md) · [subagents](https://cursor.com/docs/subagents.md) · [rules](https://cursor.com/docs/rules.md) · [hooks](https://cursor.com/docs/hooks.md) · [grok-4-7](https://cursor.com/docs/models/grok-4-7.md)
  - [Grok 4.7 forum post](https://forum.cursor.com/t/grok-4-7-is-now-live/172526) · [xAI](https://x.ai/news/grok-4-7) · [install script](https://cursor.com/install)
- **Tooling:** [firecrawl/cli releases](https://github.com/firecrawl/cli/releases) · [chrome-devtools-mcp releases](https://github.com/ChromeDevTools/chrome-devtools-mcp/releases) · [cli/cli releases](https://github.com/cli/cli/releases)
- **Internal:**
  - probe record `ops/research/2026-09-probe-record.md` (2026-09-27; prior version at `HEAD`, generated 2026-09-12 03:46 UTC)
  - prior cycle `ops/research/2026-09-11-cli-updates.md`, `ops/decisions/2026-09-11-cli-deprecation-watch.md`
  - sibling `ops/research/2026-09-27-repo-mining.md`

**Cross-checks performed (per watch-cycle SKILL §Stage 6):**
1. **Registry validation.** Stage 1 over `ops/watch-registry.toml`: 27/27 `[cli.*]` URLs are HTTPS + public-host OK. That covers the 18 dispatched-CLI URLs, checked at the start of the run, and the 9 tooling URLs, re-run after the registry gained them mid-cycle. `meta.cli_count = 9` matches 9 entries; `repo_count = 7`.
2. **Source verification.** Each dispatched CLI was covered by an independent read-only worker against primary sources. Three extra workers answered Q1–Q6 from docs **and** Codex/Claude source. The lead re-verified the load-bearing claims live:
   - strict validation (✘ on `plugin.json`, ✔ on `marketplace.json`, 2.1.283);
   - the Codex sandbox behaviors (LEAD-01 … LEAD-15);
   - the Grok 4.7 id form (Appendix B);
   - the tooling routing.
3. **Window coverage.** 2026-09-11 → 2026-09-27 per CLI: Claude 2.1.269–2.1.283, agy 1.2.1–1.2.12, Codex 0.155.0–0.157.1 (+ alphas), OpenCode 1.18.31–1.18.32 and V2 2.0.0–2.0.18, Kimi 0.43.0–2.1.1, Cursor through build 09.26, firecrawl 1.24.0–1.24.6, chrome-devtools-mcp 1.10.0–1.10.1, gh 2.101.0.
4. **Gap-table grounding.** Every Y/partial cell cites a path grep-verified today: `hooks/hooks.json`, `scripts/probe-capabilities.sh:1528`, `scripts/lib/{antigravity,opencode,lease,roster,cursor,codex}.sh`, `antigravity-agents/agents/*.md`, `kimi-agents/builder.md`, `codex-agents/agents.toml`, `.claude/CLAUDE.md`, `templates/CLAUDE.md`, `README.md`.
5. **Pre-release flagging.** Codex 0.158.0-alpha.* / 0.159.0-alpha.* are tagged **[pre-release]** and excluded from floors. OpenCode `opencode-ai` `dev`/`beta` dist-tags are snapshots, not releases. No other pre-release rows.
6. **Probe-backed flips.** Every reversal cites the fresh record:
   - AGY-08 FAIL→PASS (D-043);
   - CUR-12 PASS→FAIL (D-050);
   - CC-03 2/3→3/3 (D-041);
   - AGY-12/16 second consecutive PASS (D-042);
   - KIMI-05 QUOTA-FAIL→AUTH-FAIL, with KIMI-06/08/09 and SELF-06e SKIPPED-GATED→PENDING-AUTH (D-051).

   CC-06 PASS is recorded as a **harness false green**, contradicted by a lead re-run (D-039).
7. **Injection / decoy scan.**
   - No prompt-injection on any fetched page. Workers quoted only benign doc directives (Claude docs' `llms.txt` header, learn.chatgpt.com's "Markdown versions … append .md", Cursor and OpenCode sample prompts) and acted on none.
   - One worker's return (Q4) was flagged by the harness as matching an instruction-shaped pattern (`settings-json`). Lead review found quoted config snippets offered as evidence, not directives. It was sanitized and kept as evidence.
   - Decoys: `open-code.ai` avoided; npm `opencode2` identified as a third-party fork.
8. **Process deviations (recorded, not hidden).**
   - **One research worker (Q1/Q2) wrote and then deleted `/tmp/.x`** while redirecting a web fetch. That breaks the read-only worker rule (Security rule 3); no repo files were touched.
   - The same kind of lapse occurred in three more workers:
     - Q3/Q5/Q6 wrote `/tmp/cw_*` and `/tmp/x.out`, deleted them, and read `~/.codex/models_cache.json` (a model catalog, no credentials; its claims are marked "[local cache]" and corroborated by the bundled `models.json` at the tag).
     - The OpenCode worker wrote `/tmp/oc_v2_*.ts|txt`, then deleted them.
     - The Q4 worker wrote `/tmp/cx_*.html`, then deleted them.
   - The agy worker ran `agy models` (a catalog listing, no model call) beyond its brief.
   - No worker wrote to the repo, `ops/`, or any credential store. Next cycle's worker briefs should say "pipe; never redirect to a file, not even /tmp".
   - The probe run started by this cycle was killed when the headless session ended while it ran in the background. The lead re-ran it to completion, and `cli-watch.md` now carries the foreground-or-poll note. The lead's Codex-sandbox re-probes ran in a throwaway `$TMPDIR` fixture that was deleted afterward. The `~/.tf-leadprobe-marker` write was denied, so nothing was created under `$HOME`.
