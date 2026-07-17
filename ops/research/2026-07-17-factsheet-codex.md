# Codex CLI fact sheet — 0.130.0 → 0.144.5, verified July 17, 2026

Researched by codex-researcher; verified where possible against locally-installed codex 0.144.4 (/opt/homebrew/bin/codex) via `codex features list` and --help inspection ("direct CLI"), plus gh api release bodies, learn.chatgpt.com docs.

## 1. Versions
Latest stable **0.144.5** (2026-07-16); ~19 stable releases since 0.130.0, near-daily cadence. Repo's tested-against floor (0.130.0) is 14 versions old.
Notable: 0.131.0 `--dangerously-bypass-hook-trust` (hooks automation-aware); 0.133.0 SubagentStart/SubagentStop hook events + permission-profile inheritance; 0.134.0 subagent identity in hook payloads, plugin-hooks flag graduated; 0.140.0 hooks.json validation warnings; 0.141.0 hook-trust bypass persists through exec start AND resume; 0.143.0–0.144.0 GPT-5.6 (Sol/Terra/Luna), remote plugins default-on, `writes` app-approval mode; 0.144.2–.4 spawn_agent model/reasoning_effort overrides restored (PR #32749); 0.144.5 improved dangerous-rm detection. [VERIFIED]

## 2. Subagents & "agent teams"
- Core API current: spawn_agent, wait_agent, send_message, followup_task, list_agents, close_agent. [VERIFIED]
- **`multi_agent` = stable/true (default-on); `multi_agent_v2` = under development/false** — the path-based-addressing layer is still opt-in/experimental despite blog hype. [VERIFIED direct CLI]
- OPEN bug #33314: spawn_agent full-history fork rejects agent_type overrides selecting [agents.<role>] profiles; partial fix 07-13 (model/reasoning_effort restored via features.multi_agent_v2.expose_spawn_agent_model_overrides, default-on); profile-selector still broken.
- [agents] TOML unchanged: max_depth (default 1), max_threads (default 6), job_max_runtime_seconds, interrupt_message. Per-agent ~/.codex/agents/<name>.toml: name, description, developer_instructions (req), model, model_reasoning_effort, sandbox_mode, mcp_servers, config_file. **`permission_profile` field inside agent blocks does NOT exist** — still sandbox_mode + global default_permissions/[permissions.<name>] tables. [VERIFIED config-reference] (Kills May report's candidate #5 as literally specced.)
- **No "agent teams" terminology in official docs** — still subagents/multi-agent. User premise corrected.
- NEW: **Guardian** — stable/default-on reviewer subagent (guardian_approval flag) auto-approving/denying risky tool calls using codex-auto-review model. [VERIFIED]

## 3. /goal
Stable/default-on (goals flag). **NOT deterministically usable from codex exec** — issue #26949 (programmatic goal creation for exec) closed NOT_PLANNED 2026-06-08. `codex exec "/goal ..."` = ordinary prompt text (model-mediated). No --goal flag on exec/resume/review. [VERIFIED direct CLI]

## 4. Hooks under codex exec — LIKELY REVERSED (was D-004 DEFER)
Convergent evidence hooks now fire under exec: --dangerously-bypass-hook-trust on all exec variants ("Intended only for automation") since 0.131.0; 0.141.0 fix presupposes hooks running in exec threads; SubagentStart/Stop + subagent identity show hooks fire in subagent turns; official doc "Hooks are enabled by default"; canonical config key now `hooks` (`codex_hooks` = deprecated alias). No single primary-source sentence — **re-run the 2026-05-12-style marker-file probe on 0.144.x before flipping ops/decisions/2026-05-12-cli-deprecation-watch.md D-004.** [VERIFIED-convergent]

## 5. --full-auto / memories
- --full-auto **hard-removed** (absent from all --help surfaces on 0.144.4). Equivalents: --dangerously-bypass-approvals-and-sandbox ("yolo") or -a never -s workspace-write. D-001 stands. [VERIFIED direct CLI]
- Memories still experimental/false (off by default); config keys unchanged. templates/.codex/config.toml needs no change. D-002 stands. [VERIFIED direct CLI]

## 6. Models + effort
Newest first: **gpt-5.6-sol** (flagship, current default, shipped 07-09), gpt-5.6-terra, gpt-5.6-luna, gpt-5.5 (default 04-23→07-09), gpt-5.4/-mini (stored Triforge standard — two generations behind), gpt-5.3-codex-spark. [VERIFIED]
model_reasoning_effort enum unchanged: minimal|low|medium|high|xhigh — xhigh remains valid. GPT-5.6 adds **max** (extended CoT budget) and **ultra** (fans out to internal subagents) as higher tiers; whether same-field enum values or separate control is **UNVERIFIED** (no primary doc lists them in the enum). Suggested posture: xhigh universal default; max/ultra opt-in for gpt-5.6-sol only, noting ultra changes execution shape (auto-spawns subagents).

## 7. Exec-mode changes for the invocation layer
- **`codex features list|enable|disable`** — real feature-flag matrix introspection; better than version-string parsing for invoke-external.sh feature detection. [VERIFIED direct CLI]
- `--strict-config` — error on unrecognized config fields; CI guard for shipped templates.
- `--output-schema <FILE>` — constrain final exec message to JSON Schema → structured review verdicts instead of text-scraping ops/REVIEW_CODEX.md.
- `--json` — JSONL event stream to stdout.
- `--ignore-rules`; `--enable/--disable <FEATURE>` shorthand; `--profile <CONFIG_PROFILE_V2>` (-p) layering $CODEX_HOME/<name>.config.toml.
- **-m/-s/-c per-agent override pattern unchanged** across exec/resume/review — invoke-external.sh safe. [VERIFIED direct CLI]
- codex mcp-server / app-server / remote-control (experimental) — Codex drivable as MCP server/daemon; alternative integration surface, informational.

Sources: github.com/openai/codex/releases · learn.chatgpt.com/docs/changelog?type=codex-cli · /docs/hooks · /docs/config-file/config-reference · /docs/models · /docs/agent-configuration/subagents · direct CLI 0.144.4.
