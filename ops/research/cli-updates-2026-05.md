# Gemini CLI & Codex CLI updates — gap analysis for Agent Triforge

**Window:** 2026-03-12 → 2026-05-12 (60 days)
**Sources:** GitHub releases for `google-gemini/gemini-cli` and `openai/codex` (Rust workspace, `rust-v*` tags); in-repo docs (`docs/cli/`, `docs/hooks/`, `codex-rs/docs/`, `codex-rs/<crate>/`); official Codex config docs at `developers.openai.com/codex/config-*`. Filtered to features relevant to Triforge (categories: `command|flag|config|agent-primitive|mcp|context|hook|fs-convention|breaking|perf`). UI/voice/browser/telemetry-only changes omitted.
**Versions covered:** Gemini v0.33.1 → v0.41.2 (21 stable) + v0.42.0-preview.2 (preview). Codex v0.115.0 → v0.130.0 (14 stable) + v0.131.0-alpha.9 (alpha — no release-note content).

## 1. Executive summary

1. **BREAKING for Triforge:** Codex v0.128.0 (2026-04-30) **deprecated `--full-auto`** in favor of explicit permission profiles + trust flows ([#20133](https://github.com/openai/codex/pull/20133)). Triforge uses this flag in `scripts/invoke-external.sh:154` — flag still works but is on the deprecation path.
2. **Codex hooks went stable** in v0.124.0 (2026-04-23, [#18893/#18385/#18391/#18888/#19012](https://github.com/openai/codex/pull/18893)) with 6 events (`PreToolUse`, `PostToolUse`, `PermissionRequest`, `SessionStart`, `UserPromptSubmit`, `Stop`) configurable inline in `config.toml` or via `requirements.toml`. Triforge has no Codex hooks today.
3. **Gemini hooks are fully documented** as a first-class system with 11 events (`BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent`, `BeforeModel`, `BeforeToolSelection`, `AfterModel`, `SessionStart`, `SessionEnd`, `Notification`, `PreCompress`) and JSON stdin/stdout protocol (v0.38.0 first UI surface via [#24616](https://github.com/google-gemini/gemini-cli/pull/24616)). Triforge has zero Gemini hooks.
4. **Gemini subagents are now general** (v0.36.0 [#22386](https://github.com/google-gemini/gemini-cli/pull/22386), with `invoke_subagent` unified tool in v0.39.0 [#24489](https://github.com/google-gemini/gemini-cli/pull/24489)). Legacy wrapping tools removed in v0.39.0 ([#25053](https://github.com/google-gemini/gemini-cli/pull/25053)) — Triforge's `@agent` routing already aligns with this.
5. **Codex multi-agent v2 uses path-based addresses** (`/root/agent_a`) with structured inter-agent messaging and `agents listing` (v0.117.0 [#15313/#15515/#15556/#15570/#15621/#15647](https://github.com/openai/codex/pull/15313)). Triforge currently spawns via `spawn_agent` only — no inter-agent comms.
6. **Codex memories pipeline** (v0.129.0 [#20622/#20986–#21205](https://github.com/openai/codex/pull/20622)) is a two-phase auto-memory system (rollout extraction → global consolidation) writing `~/.codex/memories/{raw_memories.md, rollout_summaries/, MEMORY.md, skills/}`. Direct overlap with Triforge's `ops/MEMORY.md` and `ops/solutions/`.
7. **Codex permission profiles** (v0.128.0 [#19900/#20117/#20118/#20095](https://github.com/openai/codex/pull/19900)) replace ad-hoc `sandbox_mode + approval_policy` combos with named, reusable profiles (`:read-only`, `:workspace`, `:danger-no-sandbox`). Glob-based filesystem permissions and network domain allowlists.
8. **Codex `agents.<name>.config_file`** pattern lets each agent role load a separate TOML overlay — cleaner than Triforge's current 242-line inline `codex-agents/agents.toml`.
9. **Codex MCP servers** now support OAuth (scopes, `oauth_resource`, `mcp_oauth_callback_port`), bearer-token env vars, HTTP+stdio transports, `enabled_tools`/`disabled_tools` allowlists, and `experimental_environment = "local"|"remote"` (v0.121.0–v0.123.0). Triforge configures no MCP servers.
10. **Gemini `.agents/skills/` interoperable path** (v0.36.0+, see `docs/cli/skills.md`) is a portable skill standard (`agentskills.io`). Triforge's `skills/` directory could be repackaged for Gemini discovery without code changes.

## 2. Per-CLI changelog (Triforge-relevant only)

### Gemini CLI — `google-gemini/gemini-cli`

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-05-06 | v0.41.2 | (patch fixes only) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.41.2) |
| 2026-05-05 | v0.41.1 | (patch fixes only) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.41.1) |
| 2026-05-05 | v0.41.0 | Secure `.env` loading + workspace trust in headless mode | config | [#25814](https://github.com/google-gemini/gemini-cli/pull/25814) |
| 2026-05-05 | v0.41.0 | Shell command validation + core tools allowlist | config | [#25720](https://github.com/google-gemini/gemini-cli/pull/25720) |
| 2026-05-05 | v0.41.0 | Persist auto-memory scratchpad for skill extraction | context | [#25873](https://github.com/google-gemini/gemini-cli/pull/25873) |
| 2026-05-05 | v0.41.0 | Wire ContextManager + AgentChatHistory | context | [#25409](https://github.com/google-gemini/gemini-cli/pull/25409) |
| 2026-05-05 | v0.41.0 | Manual session UUID via command-line arg | flag | [#26060](https://github.com/google-gemini/gemini-cli/pull/26060) |
| 2026-05-05 | v0.41.0 | Bool/number casting for env vars in `settings.json` | config | [#26118](https://github.com/google-gemini/gemini-cli/pull/26118) |
| 2026-04-30 | v0.40.1 | (patch fixes) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.40.1) |
| 2026-04-28 | v0.40.0 | Tools to list and read MCP resources | mcp | [#25395](https://github.com/google-gemini/gemini-cli/pull/25395) |
| 2026-04-28 | v0.40.0 | Resolve custom seatbelt profiles from `$HOME/.gemini` first | fs-convention | [#25427](https://github.com/google-gemini/gemini-cli/pull/25427) |
| 2026-04-28 | v0.40.0 | Disable topic updates for subagents | agent-primitive | [#25567](https://github.com/google-gemini/gemini-cli/pull/25567) |
| 2026-04-28 | v0.40.0 | Split `memoryManager` flag into `autoMemory` | breaking-config | [#25601](https://github.com/google-gemini/gemini-cli/pull/25601) |
| 2026-04-28 | v0.40.0 | Vertex AI request routing settings | config | [#25513](https://github.com/google-gemini/gemini-cli/pull/25513) |
| 2026-04-28 | v0.40.0 | `/new` alias for `/clear` | command | [#17865](https://github.com/google-gemini/gemini-cli/pull/17865) |
| 2026-04-28 | v0.40.0 | Skill-creator integrated into skill-extraction agent | agent-primitive | [#25421](https://github.com/google-gemini/gemini-cli/pull/25421) |
| 2026-04-24 | v0.39.1 | (patch fixes) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.39.1) |
| 2026-04-23 | v0.39.0 | **Refactor subagent → unified `invoke_subagent`** | agent-primitive | [#24489](https://github.com/google-gemini/gemini-cli/pull/24489) |
| 2026-04-23 | v0.39.0 | **Remove legacy subagent wrapping tools** | **BREAKING** | [#25053](https://github.com/google-gemini/gemini-cli/pull/25053) |
| 2026-04-23 | v0.39.0 | `useAgentStream` hook + wire in AppContainer | hook | [#24292](https://github.com/google-gemini/gemini-cli/pull/24292), [#24297](https://github.com/google-gemini/gemini-cli/pull/24297) |
| 2026-04-23 | v0.39.0 | Persist subagent `agentId` in tool-call records | agent-primitive | [#25092](https://github.com/google-gemini/gemini-cli/pull/25092) |
| 2026-04-23 | v0.39.0 | Decoupled `ContextManager` + Sidecar architecture | context | [#24752](https://github.com/google-gemini/gemini-cli/pull/24752) |
| 2026-04-23 | v0.39.0 | Auth block in MCP servers config in agents | mcp | [#24770](https://github.com/google-gemini/gemini-cli/pull/24770) |
| 2026-04-23 | v0.39.0 | Skill patching with `/memory inbox` integration | command | [#25148](https://github.com/google-gemini/gemini-cli/pull/25148) |
| 2026-04-23 | v0.39.0 | `/memory inbox` for reviewing extracted skills | command | [#24544](https://github.com/google-gemini/gemini-cli/pull/24544) |
| 2026-04-23 | v0.39.0 | Silent fallback for Plan Mode model routing | config | [#25317](https://github.com/google-gemini/gemini-cli/pull/25317) |
| 2026-04-23 | v0.39.0 | `activate_skill` requires user confirm in Plan Mode | agent-primitive | [#24946](https://github.com/google-gemini/gemini-cli/pull/24946) |
| 2026-04-17 | v0.38.2 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.38.2) |
| 2026-04-15 | v0.38.1 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.38.1) |
| 2026-04-14 | v0.38.0 | **Display hook system messages in UI** | hook | [#24616](https://github.com/google-gemini/gemini-cli/pull/24616) |
| 2026-04-14 | v0.38.0 | Context-aware persistent policy approvals | config | [#23257](https://github.com/google-gemini/gemini-cli/pull/23257) |
| 2026-04-14 | v0.38.0 | `web_fetch` in plan mode w/ ask_user | config | [#24456](https://github.com/google-gemini/gemini-cli/pull/24456) |
| 2026-04-14 | v0.38.0 | `experimental.adk.agentSessionNoninteractiveEnabled` | config | [#24439](https://github.com/google-gemini/gemini-cli/pull/24439) |
| 2026-04-14 | v0.38.0 | Default values for environment variables | config | [#24469](https://github.com/google-gemini/gemini-cli/pull/24469) |
| 2026-04-14 | v0.38.0 | Background memory service for skill extraction | context | [#24274](https://github.com/google-gemini/gemini-cli/pull/24274) |
| 2026-04-14 | v0.38.0 | `ContextCompressionService` | context | [#24483](https://github.com/google-gemini/gemini-cli/pull/24483) |
| 2026-04-14 | v0.38.0 | Scope subagent workspace dirs via AsyncLocalStorage | agent-primitive | [#24445](https://github.com/google-gemini/gemini-cli/pull/24445) |
| 2026-04-14 | v0.38.0 | Migrate `nonInteractiveCli` to `LegacyAgentSession` | breaking-config | [#22987](https://github.com/google-gemini/gemini-cli/pull/22987) |
| 2026-04-14 | v0.38.0 | Agent protocol UI types + experimental flag | agent-primitive | [#24275](https://github.com/google-gemini/gemini-cli/pull/24275) |
| 2026-04-13 | v0.37.2 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.37.2) |
| 2026-04-09 | v0.37.1 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.37.1) |
| 2026-04-08 | v0.37.0 | Unified Context Management + Tool Distillation | context | [#24157](https://github.com/google-gemini/gemini-cli/pull/24157) |
| 2026-04-08 | v0.37.0 | Project-level memory scope to `save_memory` tool | fs-convention | [#24161](https://github.com/google-gemini/gemini-cli/pull/24161) |
| 2026-04-08 | v0.37.0 | `memoryBoundaryMarkers` setting | config | [#24020](https://github.com/google-gemini/gemini-cli/pull/24020) |
| 2026-04-08 | v0.37.0 | **Promote planning feature to stable** | command | [#24282](https://github.com/google-gemini/gemini-cli/pull/24282) |
| 2026-04-08 | v0.37.0 | `forbiddenPaths` in `GlobalSandboxOptions` | config | [#23936](https://github.com/google-gemini/gemini-cli/pull/23936) |
| 2026-04-08 | v0.37.0 | Inline `agentCardJson` for remote agents | agent-primitive | [#23743](https://github.com/google-gemini/gemini-cli/pull/23743) |
| 2026-04-08 | v0.37.0 | Event-driven subagent history infrastructure | agent-primitive | [#23914](https://github.com/google-gemini/gemini-cli/pull/23914) |
| 2026-04-08 | v0.37.0 | Subagent isolation + cleanup hardening | agent-primitive | [#23903](https://github.com/google-gemini/gemini-cli/pull/23903) |
| 2026-04-08 | v0.37.0 | New `ci` skill for automated failure replication | agent-primitive | [#23720](https://github.com/google-gemini/gemini-cli/pull/23720) |
| 2026-04-08 | v0.37.0 | `--admin-policy` flag (supplemental admin policies) | flag | [#20360](https://github.com/google-gemini/gemini-cli/pull/20360) (landed earlier; promoted) |
| 2026-04-01 | v0.36.0 | **Enable subagents (general availability)** | agent-primitive | [#22386](https://github.com/google-gemini/gemini-cli/pull/22386) |
| 2026-04-01 | v0.36.0 | Multi-registry architecture + tool filtering for subagents | agent-primitive | [#22712](https://github.com/google-gemini/gemini-cli/pull/22712) |
| 2026-04-01 | v0.36.0 | Subagent local execution + tool isolation | agent-primitive | [#22718](https://github.com/google-gemini/gemini-cli/pull/22718) |
| 2026-04-01 | v0.36.0 | Inject memory + JIT context into subagents | context | [#23032](https://github.com/google-gemini/gemini-cli/pull/23032) |
| 2026-04-01 | v0.36.0 | Cap JIT context upward traversal at git root | context | [#23074](https://github.com/google-gemini/gemini-cli/pull/23074) |
| 2026-04-01 | v0.36.0 | Resilient subagent tool rejection with contextual feedback | agent-primitive | [#22951](https://github.com/google-gemini/gemini-cli/pull/22951) |
| 2026-04-01 | v0.36.0 | Experimental memory-manager agent replaces `save_memory` | agent-primitive | [#22726](https://github.com/google-gemini/gemini-cli/pull/22726) |
| 2026-04-01 | v0.36.0 | Admin-forced MCP server installations | mcp | [#23163](https://github.com/google-gemini/gemini-cli/pull/23163) |
| 2026-04-01 | v0.36.0 | `AgentSession` + rename stream events to agent events | breaking-config | [#23159](https://github.com/google-gemini/gemini-cli/pull/23159) |
| 2026-04-01 | v0.36.0 | **Git worktree support for isolated parallel sessions** | fs-convention | [#22973](https://github.com/google-gemini/gemini-cli/pull/22973) |
| 2026-04-01 | v0.36.0 | Enable JIT context loading by default | config | [#22736](https://github.com/google-gemini/gemini-cli/pull/22736) |
| 2026-04-01 | v0.36.0 | Crypto integrity verification for extension updates | config | [#21772](https://github.com/google-gemini/gemini-cli/pull/21772) |
| 2026-04-01 | v0.36.0 | Strict macOS sandboxing using Seatbelt allowlist | config | [#22832](https://github.com/google-gemini/gemini-cli/pull/22832) |
| 2026-03-28 | v0.35.3 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.35.3) |
| 2026-03-26 | v0.35.2 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.35.2) |
| 2026-03-26 | v0.35.1 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.35.1) |
| 2026-03-24 | v0.35.0 | Subagent-specific policies in TOML | config | [#21431](https://github.com/google-gemini/gemini-cli/pull/21431) |
| 2026-03-24 | v0.35.0 | `disableAlwaysAllow` setting | config | [#21941](https://github.com/google-gemini/gemini-cli/pull/21941) |
| 2026-03-24 | v0.35.0 | Increase sub-agent turn + time limits | config | [#22196](https://github.com/google-gemini/gemini-cli/pull/22196) |
| 2026-03-24 | v0.35.0 | Custom base URL via env vars | config | [#21561](https://github.com/google-gemini/gemini-cli/pull/21561) |
| 2026-03-24 | v0.35.0 | Model-driven parallel tool scheduler | perf | [#21933](https://github.com/google-gemini/gemini-cli/pull/21933) |
| 2026-03-24 | v0.35.0 | Allow safe tools to execute concurrently while agent busy | perf | [#21988](https://github.com/google-gemini/gemini-cli/pull/21988) |
| 2026-03-24 | v0.35.0 | `SandboxManager` interface + config schema | config | [#21774](https://github.com/google-gemini/gemini-cli/pull/21774) |
| 2026-03-17 | v0.34.0 | **Native gVisor (runsc) sandboxing** | config | [#21062](https://github.com/google-gemini/gemini-cli/pull/21062) |
| 2026-03-17 | v0.34.0 | Experimental LXC container sandbox | config | [#20735](https://github.com/google-gemini/gemini-cli/pull/20735) |
| 2026-03-17 | v0.34.0 | `--acp` rename (was `--experimental-acp`) | **BREAKING flag** | [#21171](https://github.com/google-gemini/gemini-cli/pull/21171) |
| 2026-03-17 | v0.34.0 | Auto-add to policy by default + scoped persistence | config | [#20361](https://github.com/google-gemini/gemini-cli/pull/20361) |
| 2026-03-17 | v0.34.0 | Enable Plan Mode by default | config | [#21713](https://github.com/google-gemini/gemini-cli/pull/21713) |
| 2026-03-17 | v0.34.0 | Concurrency safety guidance for subagent delegation | agent-primitive | [#21278](https://github.com/google-gemini/gemini-cli/pull/21278) |
| 2026-03-17 | v0.34.0 | Skill activation via slash commands | command | [#21758](https://github.com/google-gemini/gemini-cli/pull/21758) |
| 2026-03-17 | v0.34.0 | OAuth2 Authorization Code provider for A2A | mcp | [#21496](https://github.com/google-gemini/gemini-cli/pull/21496) |
| 2026-03-16 | v0.33.2 | (patch) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.33.2) |
| 2026-03-12 | v0.33.1 | (patch fixes — cutoff release) | — | [release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.33.1) |
| 2026-05-06 | **[preview]** v0.42.0-preview.2 | Cherry-pick patch on preview.1 (no new features here; preview.0 work pending stable) | — | [#26590](https://github.com/google-gemini/gemini-cli/pull/26590) |

### Codex CLI — `openai/codex` (Rust workspace `rust-v*`)

| Date | Version | Feature | Category | Source |
|---|---|---|---|---|
| 2026-05-08 | v0.130.0 | `codex remote-control` — headless remotely-controllable app-server entrypoint | command | [#21424](https://github.com/openai/codex/pull/21424) |
| 2026-05-08 | v0.130.0 | App-server thread pagination (unloaded/summary/full views) | agent-primitive | [#21566](https://github.com/openai/codex/pull/21566) |
| 2026-05-08 | v0.130.0 | Live app-server threads pick up config changes w/o restart | config | [#21187](https://github.com/openai/codex/pull/21187) |
| 2026-05-08 | v0.130.0 | Plugin details show bundled hooks; share metadata + discoverability | hook | [#21447](https://github.com/openai/codex/pull/21447), [#21495](https://github.com/openai/codex/pull/21495), [#21637](https://github.com/openai/codex/pull/21637) |
| 2026-05-08 | v0.130.0 | Built-in MCPs as first-class runtime servers | mcp | [#21356](https://github.com/openai/codex/pull/21356) |
| 2026-05-08 | v0.130.0 | Remove string-keyed MCP tool maps (internal simplification) | breaking-internal | [#21454](https://github.com/openai/codex/pull/21454) |
| 2026-05-08 | v0.130.0 | Add stdio exec-server client transport | agent-primitive | [#20664](https://github.com/openai/codex/pull/20664) |
| 2026-05-08 | v0.130.0 | `CODEX_HOME` environments TOML provider | fs-convention | [#20666](https://github.com/openai/codex/pull/20666) |
| 2026-05-08 | v0.130.0 | Bedrock auth uses AWS console-login creds (`aws login`) | config | [#21623](https://github.com/openai/codex/pull/21623) |
| 2026-05-08 | v0.130.0 | Configurable OpenTelemetry trace metadata | config | [#21556](https://github.com/openai/codex/pull/21556) |
| 2026-05-07 | v0.129.0 | **Memories MCP v1 + read/write/search APIs** | mcp + context | [#20622](https://github.com/openai/codex/pull/20622), [#20986–#21205](https://github.com/openai/codex/pull/20986) |
| 2026-05-07 | v0.129.0 | Ad-hoc instructions (memories) + seed extension instructions | context | [#20602](https://github.com/openai/codex/pull/20602), [#20606](https://github.com/openai/codex/pull/20606) |
| 2026-05-07 | v0.129.0 | Hooks: browse + toggle from `/hooks`, before/after compaction, `PreToolUse` additionalContext | hook | [#19882](https://github.com/openai/codex/pull/19882), [#19905](https://github.com/openai/codex/pull/19905), [#20692](https://github.com/openai/codex/pull/20692) |
| 2026-05-07 | v0.129.0 | Selected turn environments for runtime context | agent-primitive | [#20281](https://github.com/openai/codex/pull/20281), [#20646](https://github.com/openai/codex/pull/20646) |
| 2026-05-07 | v0.129.0 | TUI retires `/approvals`, renames `/autoreview` → `/approve` | **BREAKING command** | [#21034](https://github.com/openai/codex/pull/21034) |
| 2026-05-07 | v0.129.0 | Workspace plugin sharing APIs + access controls | config | [#20278](https://github.com/openai/codex/pull/20278), [#21124](https://github.com/openai/codex/pull/21124) |
| 2026-05-07 | v0.129.0 | Agent identity → access token rename | breaking-config | [#21059](https://github.com/openai/codex/pull/21059) |
| 2026-05-07 | v0.129.0 | Inject state DB, agent-graph store | agent-primitive | [#20689](https://github.com/openai/codex/pull/20689) |
| 2026-05-07 | v0.129.0 | Cloud executor registration to exec-server | agent-primitive | [#19575](https://github.com/openai/codex/pull/19575) |
| 2026-04-30 | v0.128.0 | **`--full-auto` DEPRECATED** | **BREAKING flag** | [#20133](https://github.com/openai/codex/pull/20133) |
| 2026-04-30 | v0.128.0 | Built-in permission profile defaults + sandbox CLI profile selection | config | [#19900](https://github.com/openai/codex/pull/19900), [#20117](https://github.com/openai/codex/pull/20117), [#20118](https://github.com/openai/codex/pull/20118) |
| 2026-04-30 | v0.128.0 | Active-profile metadata for clients | config | [#20095](https://github.com/openai/codex/pull/20095) |
| 2026-04-30 | v0.128.0 | Persisted `/goal` workflows (app-server + model tools + TUI) | command + context | [#18073-18077](https://github.com/openai/codex/pull/18073), [#20082](https://github.com/openai/codex/pull/20082) |
| 2026-04-30 | v0.128.0 | `codex update` command | command | [#19933](https://github.com/openai/codex/pull/19933) |
| 2026-04-30 | v0.128.0 | Configurable TUI keymaps | config | [#18593](https://github.com/openai/codex/pull/18593) |
| 2026-04-30 | v0.128.0 | External agent session import (background imports + titles) | fs-convention | [#19895](https://github.com/openai/codex/pull/19895), [#20284](https://github.com/openai/codex/pull/20284), [#20261](https://github.com/openai/codex/pull/20261) |
| 2026-04-30 | v0.128.0 | MultiAgentV2 thread caps, wait-time, root/subagent hints | agent-primitive | [#19360](https://github.com/openai/codex/pull/19360), [#19792](https://github.com/openai/codex/pull/19792), [#20052](https://github.com/openai/codex/pull/20052), [#20180](https://github.com/openai/codex/pull/20180) |
| 2026-04-30 | v0.128.0 | Plugin marketplace install + remote bundle caching + plugin-bundled hooks | hook + config | [#18704](https://github.com/openai/codex/pull/18704), [#19914](https://github.com/openai/codex/pull/19914), [#19840](https://github.com/openai/codex/pull/19840) |
| 2026-04-30 | v0.128.0 | Checked-in `codex-core` public API listing + ThreadManager sample | breaking-internal | [#20243](https://github.com/openai/codex/pull/20243), [#20141](https://github.com/openai/codex/pull/20141) |
| 2026-04-24 | v0.125.0 | App-server Unix socket transport + sticky environments | agent-primitive | [#18255](https://github.com/openai/codex/pull/18255), [#18897](https://github.com/openai/codex/pull/18897) |
| 2026-04-24 | v0.125.0 | Permission profiles round-trip across TUI, turns, MCP, escalation, app-server | config | [#18284-18287](https://github.com/openai/codex/pull/18284), [#19231](https://github.com/openai/codex/pull/19231) |
| 2026-04-24 | v0.125.0 | `codex exec --json` reports reasoning-token usage | flag | [#19308](https://github.com/openai/codex/pull/19308) |
| 2026-04-24 | v0.125.0 | Reject conflicting MultiAgentV2 thread limits, MCP bearer-token field validation | breaking-config | [#19129](https://github.com/openai/codex/pull/19129), [#19294](https://github.com/openai/codex/pull/19294) |
| 2026-04-24 | v0.125.0 | Rollout tracing records tool/code-mode/session/multi-agent relationships | context | [#18878](https://github.com/openai/codex/pull/18878), [#18879](https://github.com/openai/codex/pull/18879), [#18880](https://github.com/openai/codex/pull/18880) |
| 2026-04-23 | v0.124.0 | **Hooks now stable** — inline `config.toml` + `requirements.toml`, observe MCP/apply_patch/Bash | hook | [#18893](https://github.com/openai/codex/pull/18893), [#18385](https://github.com/openai/codex/pull/18385), [#18391](https://github.com/openai/codex/pull/18391), [#18888](https://github.com/openai/codex/pull/18888), [#19012](https://github.com/openai/codex/pull/19012) |
| 2026-04-23 | v0.124.0 | Multi-environment sessions + per-turn env choice | agent-primitive | [#18401](https://github.com/openai/codex/pull/18401), [#18416](https://github.com/openai/codex/pull/18416) |
| 2026-04-23 | v0.124.0 | First-class Amazon Bedrock + SigV4 | config | [#17820](https://github.com/openai/codex/pull/17820) |
| 2026-04-23 | v0.124.0 | TUI reasoning controls Alt+,/Alt+. + reset-on-upgrade | config | [#18866](https://github.com/openai/codex/pull/18866), [#19085](https://github.com/openai/codex/pull/19085) |
| 2026-04-23 | v0.124.0 | Fast service tier default for ChatGPT plans | config | [#19053](https://github.com/openai/codex/pull/19053) |
| 2026-04-23 | v0.123.0 | Built-in `amazon-bedrock` provider | config | [#18744](https://github.com/openai/codex/pull/18744) |
| 2026-04-23 | v0.123.0 | `/mcp verbose` — full MCP diagnostics/resources | command | [#18610](https://github.com/openai/codex/pull/18610) |
| 2026-04-23 | v0.123.0 | Plugin MCP loading: both `mcpServers` + top-level server maps in `.mcp.json` | mcp | [#18780](https://github.com/openai/codex/pull/18780) |
| 2026-04-23 | v0.123.0 | `remote_sandbox_config` host-specific requirements | config | [#18763](https://github.com/openai/codex/pull/18763) |
| 2026-04-23 | v0.123.0 | `codex exec` inherits root-level shared flags (sandbox/model) | flag | [#18630](https://github.com/openai/codex/pull/18630) |
| 2026-04-20 | v0.122.0 | Filesystem permissions: deny-read glob policies, managed deny-read, platform sandbox enforcement | config | [#15979](https://github.com/openai/codex/pull/15979), [#17740](https://github.com/openai/codex/pull/17740), [#18096](https://github.com/openai/codex/pull/18096) |
| 2026-04-20 | v0.122.0 | Isolated `codex exec` runs ignore user config/rules | flag | [#18646](https://github.com/openai/codex/pull/18646) |
| 2026-04-20 | v0.122.0 | Tool discovery + image generation enabled by default | config | [#17854](https://github.com/openai/codex/pull/17854), [#17153](https://github.com/openai/codex/pull/17153) |
| 2026-04-20 | v0.122.0 | Project hooks + exec policies require trusted workspaces | hook + config | [#14718](https://github.com/openai/codex/pull/14718), [#18443](https://github.com/openai/codex/pull/18443) |
| 2026-04-20 | v0.122.0 | Plan Mode can start implementation in fresh context | command | [#17499](https://github.com/openai/codex/pull/17499) |
| 2026-04-15 | v0.121.0 | `codex marketplace add` + app-server marketplace install (GitHub/git/local/URL) | command | [#17087](https://github.com/openai/codex/pull/17087), [#17717](https://github.com/openai/codex/pull/17717), [#17756](https://github.com/openai/codex/pull/17756) |
| 2026-04-15 | v0.121.0 | TUI memory mode + memory reset/deletion + extension cleanup | command + context | [#17632](https://github.com/openai/codex/pull/17632), [#17626](https://github.com/openai/codex/pull/17626), [#17913](https://github.com/openai/codex/pull/17913) |
| 2026-04-15 | v0.121.0 | MCP Apps tool calls, namespaced MCP, parallel-call opt-in, sandbox-state metadata | mcp | [#17364](https://github.com/openai/codex/pull/17364), [#17404](https://github.com/openai/codex/pull/17404), [#17667](https://github.com/openai/codex/pull/17667), [#17763](https://github.com/openai/codex/pull/17763) |
| 2026-04-15 | v0.121.0 | Secure devcontainer profile + bubblewrap | config | [#10431](https://github.com/openai/codex/pull/10431), [#17547](https://github.com/openai/codex/pull/17547) |
| 2026-04-15 | v0.121.0 | Removed `danger-full-access` denylist-only network mode | **BREAKING config** | [#17732](https://github.com/openai/codex/pull/17732) |
| 2026-04-11 | v0.120.0 | `SessionStart` hooks distinguish `/clear` vs fresh startup vs resume | hook | [#17073](https://github.com/openai/codex/pull/17073) |
| 2026-04-11 | v0.120.0 | Code-mode tool declarations include MCP `outputSchema` | mcp | [#17210](https://github.com/openai/codex/pull/17210) |
| 2026-04-11 | v0.120.0 | Realtime V2 stream background agent progress while running | agent-primitive | [#17264](https://github.com/openai/codex/pull/17264), [#17306](https://github.com/openai/codex/pull/17306) |
| 2026-04-10 | v0.119.0 | Egress websocket transport + remote `--cd` forwarding + runtime remote-control + sandbox-aware FS APIs + experimental `codex exec-server` | agent-primitive | [#15951](https://github.com/openai/codex/pull/15951), [#16700](https://github.com/openai/codex/pull/16700), [#16751](https://github.com/openai/codex/pull/16751), [#16973](https://github.com/openai/codex/pull/16973) |
| 2026-04-10 | v0.119.0 | MCP resource reads, custom-server tool search, server-driven elicitations, file-parameter uploads | mcp | [#16082](https://github.com/openai/codex/pull/16082), [#16465](https://github.com/openai/codex/pull/16465), [#16944](https://github.com/openai/codex/pull/16944), [#17043](https://github.com/openai/codex/pull/17043) |
| 2026-04-10 | v0.119.0 | `codex-core` slim-down — crate extractions for MCP/tools/config/auth/feedback/protocol | breaking-internal | [#15919](https://github.com/openai/codex/pull/15919), [#16379](https://github.com/openai/codex/pull/16379), [#16508](https://github.com/openai/codex/pull/16508) |
| 2026-03-31 | v0.118.0 | Windows sandbox proxy-only networking via OS egress rules | config | [#12220](https://github.com/openai/codex/pull/12220) |
| 2026-03-31 | v0.118.0 | App-server device-code ChatGPT sign-in | config | [#15525](https://github.com/openai/codex/pull/15525) |
| 2026-03-31 | v0.118.0 | `codex exec` prompt-plus-stdin workflow | flag | [#15917](https://github.com/openai/codex/pull/15917) |
| 2026-03-31 | v0.118.0 | Custom model providers fetch + refresh short-lived bearer tokens | config | [#16286](https://github.com/openai/codex/pull/16286), [#16287](https://github.com/openai/codex/pull/16287), [#16288](https://github.com/openai/codex/pull/16288) |
| 2026-03-26 | v0.117.0 | **Sub-agents: path-based addresses `/root/agent_a` + structured inter-agent messaging** | agent-primitive | [#15313](https://github.com/openai/codex/pull/15313), [#15515](https://github.com/openai/codex/pull/15515), [#15556](https://github.com/openai/codex/pull/15556), [#15570](https://github.com/openai/codex/pull/15570), [#15621](https://github.com/openai/codex/pull/15621), [#15647](https://github.com/openai/codex/pull/15647) |
| 2026-03-26 | v0.117.0 | Plugins first-class workflow — sync, `/plugins`, install/remove, auth handling | command + config | [#15041](https://github.com/openai/codex/pull/15041), [#15042](https://github.com/openai/codex/pull/15042), [#15195](https://github.com/openai/codex/pull/15195), [#15217](https://github.com/openai/codex/pull/15217) |
| 2026-03-26 | v0.117.0 | App-server `!` shell commands + filesystem watch + remote ws with bearer auth | mcp + agent-primitive | [#14988](https://github.com/openai/codex/pull/14988), [#14533](https://github.com/openai/codex/pull/14533), [#14847](https://github.com/openai/codex/pull/14847), [#14853](https://github.com/openai/codex/pull/14853) |
| 2026-03-26 | v0.117.0 | App-server-backed TUI default | config | [#15661](https://github.com/openai/codex/pull/15661) |
| 2026-03-26 | v0.117.0 | Retire legacy `read_file` / `grep_files` handlers | **BREAKING config** | [#15773](https://github.com/openai/codex/pull/15773), [#15775](https://github.com/openai/codex/pull/15775) |
| 2026-03-19 | v0.116.0 | **`userpromptsubmit` hook** | hook | [#14626](https://github.com/openai/codex/pull/14626) |
| 2026-03-19 | v0.116.0 | App-server TUI device-code ChatGPT sign-in + token refresh | config | [#14952](https://github.com/openai/codex/pull/14952) |
| 2026-03-19 | v0.116.0 | Plugin install prompts + suggestion allowlist + remote install/uninstall sync | config | [#14896](https://github.com/openai/codex/pull/14896), [#15022](https://github.com/openai/codex/pull/15022), [#14878](https://github.com/openai/codex/pull/14878) |
| 2026-03-16 | v0.115.0 | Subagent inherits sandbox + network rules; project-profile layering, persisted host approvals | agent-primitive | [#14619](https://github.com/openai/codex/pull/14619), [#14650](https://github.com/openai/codex/pull/14650), [#14674](https://github.com/openai/codex/pull/14674) |
| 2026-03-16 | v0.115.0 | Subagent wait tool renamed `wait_agent` (with `spawn_agent`, `send_input`) | **BREAKING command** | [#14631](https://github.com/openai/codex/pull/14631) |
| 2026-03-16 | v0.115.0 | v2 app-server filesystem RPCs (read/write/copy/dirs/watch) + Python SDK | agent-primitive | [#14245](https://github.com/openai/codex/pull/14245), [#14435](https://github.com/openai/codex/pull/14435) |
| 2026-03-16 | v0.115.0 | Smart Approvals + guardian subagent in core/app-server/TUI | agent-primitive | [#13860](https://github.com/openai/codex/pull/13860), [#14668](https://github.com/openai/codex/pull/14668) |
| 2026-03-16 | v0.115.0 | Realtime websocket sessions w/ transcription mode + v2 handoff via `codex` tool | agent-primitive | [#14554](https://github.com/openai/codex/pull/14554), [#14556](https://github.com/openai/codex/pull/14556) |
| 2026-05-12 | **[alpha]** v0.131.0-alpha.9 | Release tag only — no user-visible feature notes in alpha series | — | [release](https://github.com/openai/codex/releases/tag/rust-v0.131.0-alpha.9) |

## 3. Gap analysis vs current Triforge

| Feature | CLI | Used in Triforge? | Action | Reasoning |
|---|---|---|---|---|
| `--full-auto` flag (deprecated v0.128.0) | Codex | **Y** | **Adopt** replacement | `scripts/invoke-external.sh:154` uses `--full-auto`. Migrate to explicit `--sandbox-mode` + `--approval-policy` per-call (already set via `-s`/`-c` overrides at lines 150–151) — drop the `--full-auto` fallback. |
| Hooks (`PreToolUse`/`PostToolUse`/`SessionStart`/`UserPromptSubmit`/`Stop`) | Codex | **N** | **Adopt** | None of Triforge's 6 ops/ write conventions (REVIEW_CODEX.md, TEST_RESULTS.md) are enforced by Codex itself. A `PostToolUse` hook in `.codex/hooks.json` could append to `ops/CHANGELOG.md` directly — moving file conventions from agent prose to platform-enforced. |
| Hooks 11-event system | Gemini | **N** | **Adopt** | Same as Codex: `SessionStart` and `AfterTool` hooks in `.gemini/settings.json` could enforce ops/ writes. Currently `gemini-agents/codebase-analyst.md` body asks Gemini to write `ARCHITECTURE.md` — hook would make this deterministic. |
| Native subagents (`@<agent>` routing + frontmatter) | Gemini | **Y** | Keep | Already used in `scripts/invoke-external.sh:42-44` with legacy fallback at lines 51–56. Aligns with v0.39.0 unified `invoke_subagent` model. |
| `invoke_subagent` unified tool (v0.39.0) | Gemini | partial | **Evaluate** | The `@agent` syntax may now route through `invoke_subagent` internally. Verify against latest Gemini; the legacy injection branch in `invoke-external.sh:51-56` may be obsolete. |
| Subagent-specific policies in TOML (v0.35.0) | Gemini | partial | **Adopt** | `gemini-agents/policies.toml` already has per-agent rules (architecture-reviewer / documentation-writer denies). Investigate whether new `subagent`-scoped TOML extends what's possible (e.g. nested `[subagents.<name>]` blocks). |
| MCP servers (zero MCP today) | Both | **N** | **Evaluate** | Codex supports OAuth, stdio+HTTP, allowlists, env placement. Gemini supports auth blocks in agent MCP config (v0.39.0). Triforge could expose `ops/` as an MCP file-system server for both CLIs — eliminates per-prompt ops/ injection. Defer until concrete need; non-trivial to wire. |
| MCP resource read tools (v0.40.0) | Gemini | **N** | Skip | Triforge doesn't model ops/ as MCP resources — would require restructure. |
| Permission profiles (`:read-only`, `:workspace`) | Codex | **N** | **Adopt** | `codex-agents/agents.toml` has `sandbox_mode = "read-only"` and `"workspace-write"` per agent. v0.128.0 lets you reference named profiles instead. Cleaner schema and unlocks `default_permissions = "workspace"` global default. |
| `agents.<name>.config_file` externalization | Codex | **N** | **Adopt** | `codex-agents/agents.toml` is 242 lines with three inline `developer_instructions = """..."""` blocks. Splitting into `codex-agents/{logic_reviewer,test_writer,debugger}.toml` referenced by `config_file` improves diffability and review. |
| Path-based subagent addresses (`/root/agent_a`) | Codex | **N** | **Evaluate** | Useful for multi-instance agent teams (the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` mode). Triforge's `team-lead.md` currently has no equivalent of structured inter-agent messaging — Codex's v0.117.0 protocol could replace ad-hoc team coordination. |
| `spawn_agent` / `wait_agent` rename (v0.115.0) | Codex | **Y** | Keep | `CLAUDE.md:122` documents `spawn_agent` use — confirm Triforge's agent prompts use new `wait_agent` (not legacy `wait_subagent`). |
| `[agents]` top-level caps | Codex | **Y** | Keep | `codex-agents/agents.toml:11-13` sets `max_depth=2`, `max_threads=4`, `job_max_runtime_seconds=1800`. Aligns with current docs. |
| `[agents] max_threads` default raised to 6 | Codex | **Y** | **Evaluate** | Triforge caps at 4; new default is 6. Test whether 6 parallel agents stay within Codex CLI runtime cost/perf envelope before raising. |
| Memories MCP / two-phase pipeline | Codex | **N (overlaps)** | **Evaluate (conflict)** | Codex v0.129.0 writes its own `~/.codex/memories/{MEMORY.md, raw_memories.md, rollout_summaries/, skills/}` — direct conflict with Triforge's `ops/MEMORY.md` and `ops/solutions/`. Either disable Codex memories (`use_memories = false`) or migrate Triforge to consume Codex's output. |
| Git worktree support | Gemini | partial | **Adopt** | v0.36.0 [#22973](https://github.com/google-gemini/gemini-cli/pull/22973). Triforge has `isolation: "worktree"` for some Claude subagents; Gemini can now run in a worktree too — useful for parallel reviewers without cross-contaminating `.gemini/agents/`. |
| Gemini Plan Mode promoted to stable | Gemini | **N** | **Evaluate** | If Triforge plan-checker workflows could trigger via `gemini --approval-mode=plan`, Triforge would gain Gemini-side planning for Phase 0/1. Currently `agents/plan-checker.md` is Claude-only. |
| `.agents/skills/` interoperable path | Gemini | **N** | **Adopt (low cost)** | Add `.agents/skills/` symlink to Triforge's `skills/` (or copy at session start). Gemini will auto-discover `skills/codebase-mapping/SKILL.md` etc. — no agent definition changes needed. |
| `.codex/hooks.json` plugin-bundled hooks | Codex | **N** | **Adopt** | v0.128.0 [#19840](https://github.com/openai/codex/pull/19840). Triforge could ship `templates/.codex/hooks.json` for users so plugin install auto-wires Codex hooks. |
| OpenTelemetry trace metadata (Codex v0.130.0) | Codex | **N** | Skip | Triforge doesn't emit traces today. Optional later. |
| Gemini `auto-memory` (v0.40.0+) | Gemini | **N (overlaps)** | Skip / disable | Per-user feature, not per-project. Triforge users opt in via `~/.gemini/settings.json`; not a framework concern. |
| Gemini hooks: `SessionStart` source field | Gemini | **N** | **Adopt** | Triforge's bootstrap is in Claude Code's `hooks/handlers/session-start.sh`; Gemini's equivalent would let Triforge own `.gemini/agents/` propagation without going through Claude's hook (faster cold-start). |
| Multi-environment Codex sessions (v0.124.0) | Codex | **N** | Skip | Triforge uses one workspace per session; multi-env adds complexity without payoff. |
| Codex `/mcp verbose` | Codex | **N** | Skip | Triforge config has no MCP servers to diagnose. |
| Plugin marketplace install (v0.121.0+) | Codex | **N** | **Evaluate** | Triforge is distributed as Claude Code plugin already. Codex marketplace would let Triforge's Codex agents (`logic_reviewer`/`test_writer`/`debugger`) be installable as a Codex plugin too. Cross-platform reach. |
| Removed legacy subagent wrapping tools (v0.39.0) | Gemini | partial | **Verify** | If Triforge's `gemini-agents/*.md` reference any tools that v0.39.0 removed, prompts will fail. Audit `tools:` arrays. |
| `--acp` rename (v0.34.0 `--experimental-acp` → `--acp`) | Gemini | **N** | Skip | Triforge doesn't use ACP mode. |
| `experimental.adk.agentSessionNoninteractiveEnabled` (v0.38.0) | Gemini | **N** | **Evaluate** | Triforge invokes Gemini via `-p` (non-interactive). If this flag improves headless reliability for Gemini agents, set in `.gemini/settings.json`. |
| `codex exec` inherits root flags (v0.123.0) | Codex | partial | Keep / verify | `scripts/invoke-external.sh:148–154` passes `-m/-s/-c` per-call; root-level inheritance would let Triforge set defaults in `.codex/config.toml`. Net positive but not urgent. |

## 4. Top 5 prioritized adoption candidates

### #1. Replace `--full-auto` with explicit profiles (BLOCKER)

**Why:** Codex v0.128.0 deprecated `--full-auto` ([#20133](https://github.com/openai/codex/pull/20133)). Triforge sets it as a fallback in `scripts/invoke-external.sh:154` after `-m/-s/-c` overrides. Today it still works; on a future minor it may be removed.

**Concrete change:** In `scripts/invoke-external.sh:147-155`, drop the `--full-auto` fallback. Per-agent `sandbox_mode` and `approval_policy = "never"` are already set in `codex-agents/agents.toml:21-22, 101-102, 183-184`. The `_run_with_timeout` wrapper passes `-s "$AGENT_SANDBOX"` and `-c "approval_policy=$AGENT_APPROVAL"` explicitly when an agent is found. Only the no-agent fallback path needs replacement — substitute `-s workspace-write -c approval_policy=never` (or read `default_permissions` from `.codex/config.toml`).

**Verification:** Run `commands/review.md` and `commands/test.md` end-to-end with Codex 0.128.0+; confirm parallel Codex invocations still produce `ops/REVIEW_CODEX.md` and `ops/TEST_RESULTS.md`.

### #2. Externalize Codex agent definitions into per-role TOML files

**Why:** `codex-agents/agents.toml` is now 242 lines with three inline 50–70-line `developer_instructions = """..."""` heredocs. Codex docs (developers.openai.com/codex/config-reference) show the supported `agents.<name>.config_file = "..."` pattern.

**Concrete change:** Split `codex-agents/agents.toml` into:
- `codex-agents/agents.toml` — global `[agents]` caps + per-agent stubs with `config_file = "logic_reviewer.toml"` etc.
- `codex-agents/logic_reviewer.toml`, `codex-agents/test_writer.toml`, `codex-agents/debugger.toml` — full per-agent config + developer_instructions
- Update `hooks/handlers/session-start.sh:69-74` to copy all four files to `.codex/agents/`
- Update `_extract_codex_agent_config` in `scripts/invoke-external.sh:220-239` to follow `config_file` references (or rely on Codex CLI resolving them natively)

**Verification:** `commands/review.md` parallel fan-out still spawns three Codex agents; diff `ops/REVIEW_CODEX.md` byte-for-byte before/after split.

### #3. Adopt Codex hooks for ops/ file conventions

**Why:** Today Triforge encodes "write to `ops/REVIEW_CODEX.md`" inside `developer_instructions`. A hook would enforce it deterministically and survive any prompt drift.

**Concrete change:** Create `templates/.codex/hooks.json` that wires:
- `PostToolUse` matcher `^(apply_patch|write)$` → append summary to `ops/CHANGELOG.md` with agent attribution
- `Stop` → check that `logic_reviewer` runs wrote `ops/REVIEW_CODEX.md`; warn if absent
- `SessionStart` (source filter excluding `/clear`) → seed reviewer agents with `ops/TASKS.md` content via `additionalContext`

Wire `hooks/handlers/session-start.sh` to copy `templates/.codex/hooks.json` to `.codex/hooks.json` (alongside existing agents.toml copy at line 70). Enable via `[features] codex_hooks = true` in `.codex/config.toml`.

**Verification:** Run any Codex agent and confirm `ops/CHANGELOG.md` gets a row without the agent writing it explicitly.

### #4. Symlink `skills/` to `.agents/skills/` for Gemini discovery

**Why:** Gemini's `docs/cli/skills.md` documents `.agents/skills/` as the workspace skills tier with interop guarantee. Triforge's 12 skills in `skills/` could be auto-discovered by Gemini without any agent-definition changes.

**Concrete change:** In `hooks/handlers/session-start.sh`, after the `.gemini/agents/` setup (line ~40), add:
```bash
if [ -d "${CLAUDE_PLUGIN_ROOT}/skills" ] && [ ! -e ".agents/skills" ]; then
  mkdir -p .agents
  ln -s "${CLAUDE_PLUGIN_ROOT}/skills" .agents/skills
fi
```
Then drop the legacy `$(cat ${CLAUDE_PLUGIN_ROOT}/skills/<skill>/SKILL.md)` prompt injection in commands that target Gemini (`commands/deep-research.md`, `commands/review.md`). Gemini's `activate_skill` tool now handles discovery + activation.

**Verification:** Run `/deep-research` → Gemini agent should call `activate_skill codebase-mapping` and the skill body should appear in conversation without manual injection.

### #5. Adopt Codex permission profiles to clean up agents.toml

**Why:** Codex v0.128.0 [#19900](https://github.com/openai/codex/pull/19900) adds built-in profiles (`:read-only`, `:workspace`, `:danger-no-sandbox`) referenced by name. Triforge currently writes `sandbox_mode = "read-only"` literal in three places.

**Concrete change:** In `codex-agents/agents.toml`, replace per-agent `sandbox_mode` with profile references:
- `[agents.logic_reviewer]`: `permission_profile = ":read-only"` (drop `sandbox_mode` line)
- `[agents.test_writer]` / `[agents.debugger]`: `permission_profile = ":workspace"`
Add `default_permissions = ":workspace"` at root of `agents.toml`. Audit that Codex v0.130.0 supports the `permission_profile` key inside `[agents.<name>]` blocks (config docs imply yes; verify with `codex agent run --help`).

**Verification:** `commands/review.md` Codex fan-out still runs read-only for `logic_reviewer`; check that an attempted `write` from logic_reviewer is rejected (negative test).

## 5. Risks — breaking changes that could affect Triforge

1. **`--full-auto` deprecation** — Codex v0.128.0 [#20133](https://github.com/openai/codex/pull/20133). Triforge `scripts/invoke-external.sh:154`. Today warns (per docs), could hard-remove on a future minor. **Mitigation: candidate #1.**
2. **Gemini legacy subagent wrappers removed** — v0.39.0 [#25053](https://github.com/google-gemini/gemini-cli/pull/25053). If any Triforge `gemini-agents/*.md` `tools:` array references a tool that the unified `invoke_subagent` replaced, those agents will error. **Mitigation: audit each frontmatter `tools:` against current Gemini tool list at `docs/cli/cli-reference.md`.**
3. **Gemini `memoryManager` → `autoMemory` split** — v0.40.0 [#25601](https://github.com/google-gemini/gemini-cli/pull/25601). If any Triforge user copied an example settings.json using `memoryManager`, the new flag name is required. **Mitigation: ship `.gemini/settings.json` in `hooks/handlers/session-start.sh:40-43` with current keys.**
4. **Codex `read_file` / `grep_files` retired** — v0.117.0 [#15773](https://github.com/openai/codex/pull/15773), [#15775](https://github.com/openai/codex/pull/15775). Triforge `codex-agents/agents.toml` uses canonical short names (`read`, `grep`, `glob`, `write`, `bash`) — verified safe.
5. **Codex `/autoreview` → `/approve`** — v0.129.0 [#21034](https://github.com/openai/codex/pull/21034). Triforge doesn't surface `/autoreview` to users; no impact.
6. **Codex `agent identity` → `access token`** — v0.129.0 [#21059](https://github.com/openai/codex/pull/21059). Renamed internal API. Triforge doesn't reference; no impact.
7. **Codex `danger-full-access` denylist-only network mode removed** — v0.121.0 [#17732](https://github.com/openai/codex/pull/17732). Triforge uses `workspace-write` and `read-only` only.
8. **Gemini `--experimental-acp` → `--acp`** — v0.34.0 [#21171](https://github.com/google-gemini/gemini-cli/pull/21171). Triforge doesn't use ACP.
9. **Codex memories writes `~/.codex/memories/` by default if enabled** — v0.129.0. If a user enables `[features] memories = true`, Codex will create memory artifacts that may confuse Triforge's `ops/MEMORY.md` workflow. **Mitigation: ship `[memories] use_memories = false` in `templates/.codex/config.toml` until Triforge decides whether to consume Codex's output.**
10. **Codex memories include a `skills/` directory** — same release. If a user enables memories, Codex will write into `~/.codex/memories/skills/`, potentially clashing with Gemini's `.agents/skills/` discovery if a user symlinks them. **Mitigation: keep paths separate.**

## 6. Sources appendix

- Gemini CLI releases (all 21 stable in window): https://github.com/google-gemini/gemini-cli/releases (filter `published_at >= 2026-03-12`)
- Codex CLI releases (all 14 stable + alphas): https://github.com/openai/codex/releases (filter `rust-v*` tags, `published_at >= 2026-03-12`)
- Gemini hooks reference: `docs/cli/hooks/reference.md` (in-repo, latest main)
- Gemini skills reference: `docs/cli/skills.md`, `docs/cli/using-agent-skills.md`, `docs/cli/creating-skills.md`
- Gemini plan-mode: `docs/cli/plan-mode.md`
- Gemini auto-memory: `docs/cli/auto-memory.md`
- Gemini git-worktrees: `docs/cli/git-worktrees.md`
- Codex memories crate: `codex-rs/memories/README.md`
- Codex rollout-trace crate: `codex-rs/rollout-trace/README.md`
- Codex official config reference: https://developers.openai.com/codex/config-reference
- Codex official config advanced: https://developers.openai.com/codex/config-advanced
- All PR / issue URLs are inline in section 2 tables for direct provenance.

**Cross-checks performed (per plan §verification):**
1. Source verification — 5 random release-tag URLs from §2 (Gemini v0.39.0, Gemini v0.36.0, Codex v0.128.0, Codex v0.124.0, Codex v0.115.0) — all resolved via `gh release view` during fetch (Pass 1).
2. Version coverage — every stable release in window present in §2 (Gemini 21, Codex 14). Patch-only releases marked `(patch fixes)`.
3. Gap-table grounding — every Y/partial cell in §3 cites a Triforge file path (verified during write).
4. Pre-release flagging — only two pre-release rows in §2 (`**[preview]** v0.42.0-preview.2`, `**[alpha]** v0.131.0-alpha.9`) both tagged.
