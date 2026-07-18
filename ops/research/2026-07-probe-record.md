# Capability probe record — 2026-07 cycle

**Generated:** 2026-07-18 12:58 UTC by `scripts/probe-capabilities.sh` (rerunnable; `/cli-watch` re-runs it each cycle)
**Host:** Darwin 25.5.0; timeout via `timeout`
**Mode:** full (live probes)

Outcome vocabulary: **PASS** capability demonstrated · **FAIL** capability absent or not demonstrated (consuming units take their documented fallback) · **UNAVAILABLE** CLI not installed · **AUTH-FAIL** CLI present but not authenticated on this machine · **SKIPPED / SKIPPED-GATED** not run (`--skip-live` or gated on a failed READY probe) · **PENDING-U15** resolved by a later unit, with the absorbing design noted.

## Summary

49 probes: 31 PASS · 15 FAIL · 1 AUTH-FAIL · 0 UNAVAILABLE · 1 SKIPPED · 1 PENDING

## Probe rows

| ID | CLI | Capability | Outcome | Evidence | Date | Method |
|---|---|---|---|---|---|---|
| AGY-01 | agy | Version capture | **PASS** | 1.1.3  | 2026-07-18 | direct |
| AGY-02 | agy | Model list (latest Pro for KTD-8 pin) | **PASS** | 3.5 Pro NOT listed (GA slipped); latest Pro=Gemini 3.1 Pro (High); full list in Appendix B | 2026-07-18 | direct |
| AGY-03 | agy | Native agent listing (agy agents) | **PASS** | Available agents: | 2026-07-18 | direct |
| AGY-04 | agy | Headless READY (agy -p) | **PASS** | READY | 2026-07-18 | live |
| AGY-05 | agy | Explicit Pro model pin (--model) | **PASS** | accepted form: --model "Gemini 3.1 Pro (High)" | 2026-07-18 | live |
| AGY-06 | agy | /goal command exists in CLI | **FAIL** | output indistinguishable from model-mediated canary — not a registered CLI command; probe: jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for, so it was auto-denied. Add an allow-rule under permissions.allow in settings.json (e.g. command(<target>)). Alte | 2026-07-18 | live |
| AGY-07 | agy | /teamwork-preview command exists in CLI | **FAIL** | output indistinguishable from model-mediated canary — not a registered CLI command; probe: jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for, so it was auto-denied. Add an allow-rule under permissions.allow in settings.json (e.g. command(<target>)). Alte | 2026-07-18 | live |
| AGY-08 | agy | Hooks fire under agy -p (project tier) | **FAIL** | no markers (SessionStart/AfterAgent/AfterTool); global tier untested by design; jetski: no output produced — a tool required the "command" permission that headless mode cannot prompt for, so it was auto-denied. Add an allow-rule under permissions.allow in settings.json (e.g. command(<target>)). Alte | 2026-07-18 | marker-file |
| AGY-09 | agy | Explicit deny survives --dangerously-skip-permissions | **FAIL** | denied command executed (fixture); adapter must never pass the skip-permissions flag; I have successfully executed the command `touch deny-marker-agy.txt` in the current working directory. | 2026-07-18 | negative |
| AGY-10 | agy | --sandbox confines writes to workspace | **FAIL** | write escaped to sentinel dir; I have successfully run the exact command you requested: ```bash touch /var/folders/h_/65shk8nj7_791wv94ds_g55c0000gn/T//triforge-probes.yNQkvN/sentinel/agy-sbx.txt ``` | 2026-07-18 | negative |
| AGY-11 | agy | Headless thinking/effort control | **PASS** | no dedicated flag; thinking level selected via --model variant suffix (Low/Medium/High) — roster effort maps to the variant string | 2026-07-18 | static |
| AGY-12 | agy | Triforge plugin agents respond through their definitions | **FAIL** | installed (agy plugin list) but not in `agy agents` (missing: codebase-analyst architecture-reviewer targeted-researcher documentation-writer) — native discovery not functional on this agy; invoke helper falls back to injection | 2026-07-18 | live |
| AGY-13 | agy | architecture-reviewer cannot run shell (tools-allowlist negative) | **FAIL** | marker absent but not attributable to the tools allowlist — native discovery not functional (see AGY-12); denial currently rests on headless auto-deny + prompt rules (injection mode) | 2026-07-18 | negative |
| CDX-01 | codex | Version capture | **PASS** | codex-cli 0.144.4 | 2026-07-18 | direct |
| CDX-02 | codex | codex features list (runtime capability detection) | **PASS** | notable: goals                                stable             true;guardian_approval                    stable             true;hooks                                stable             true;memories                             experimental       false;multi_agent                          stable             true;multi_agent_mode                     removed            false;full capture in Appendix A | 2026-07-18 | direct |
| CDX-03 | codex | Headless READY on gpt-5.6-sol | **PASS** | READY | 2026-07-18 | live |
| CDX-04 | codex | Hooks fire under codex exec (D-004 re-probe) | **PASS** | fired: SessionStart UserPromptSubmit PreToolUse Stop; hook-lines: Run this shell command: echo hooktest;warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.;warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.; | 2026-07-18 | marker-file |
| CDX-05 | codex | --output-schema constrains final message to schema-valid JSON | **PASS** | {"verdict":"2+2=4 is true.","confidence":"HIGH"} | 2026-07-18 | live |
| CDX-06 | codex | model_reasoning_effort="max" accepted on gpt-5.6-sol | **PASS** | READY | 2026-07-18 | live |
| CDX-07 | codex | model_reasoning_effort="ultra" accepted on gpt-5.6-sol | **PASS** | READY | 2026-07-18 | live |
| CDX-08 | codex | read-only sandbox rejects writes (negative) | **PASS** | write did not land under -s read-only | 2026-07-18 | negative |
| OC-01 | opencode | Version capture | **PASS** | 1.18.3 | 2026-07-18 | direct |
| OC-02 | opencode | OpenRouter model list (GLM id for KTD-8 default) | **FAIL** | [91m[1mError: [0mProvider not found: openrouter | 2026-07-18 | direct |
| OC-03 | opencode | Headless READY (run --format json parses) | **PASS** | JSON events parsed; READY present | 2026-07-18 | live |
| OC-04 | opencode | OpenRouter GLM pin (-m openrouter/z-ai/glm-5.2) | **FAIL** | {"type":"error","timestamp":1784379670248,"sessionID":"ses_08aaf020dffeDwWoiEfLsvjl5I","error":{"name":"UnknownError","data":{"message":"Unexpected server error. Check server logs for details.","ref":"err_ea8a8ce7"}}} | 2026-07-18 | live |
| OC-05 | opencode | --variant (reasoning effort) accepted | **FAIL** | {"type":"error","timestamp":1784379670949,"sessionID":"ses_08aaeff59ffeXOv6GbFDaDSoSP","error":{"name":"UnknownError","data":{"message":"Unexpected server error. Check server logs for details.","ref":"err_ffe1b9f1"}}} | 2026-07-18 | live |
| OC-06 | opencode | Explicit deny survives --auto | **FAIL** | denied command executed anyway; [0m > build · nemotron-3-ultra-free [0m [0m$ [0mtouch deny-marker-oc.txt (no output) [0m Done. The file `deny-marker-oc.txt` has been created. | 2026-07-18 | negative |
| KIMI-01 | kimi | Version capture | **PASS** | 0.15.0 | 2026-07-18 | direct |
| KIMI-02 | kimi | Config/auth validation (kimi doctor) | **PASS** | Kimi doctor OK config.toml /Users/dbenger/.kimi-code/config.toml OK tui.toml /Users/dbenger/.kimi-code/tui.toml All checked config files are valid. | 2026-07-18 | direct |
| KIMI-03 | kimi | Custom agent definitions (CLI surface) | **FAIL** | no --agent/--agent-file flag in kimi-code --help (legacy kimi-cli only); fallback: AGENTS.md sections + per-invocation prompts | 2026-07-18 | static |
| KIMI-04 | kimi | Skills directory flag (--skills-dir) for .agents/skills interop | **PASS** | --skills-dir present in help (repeatable) | 2026-07-18 | static |
| KIMI-05 | kimi | Headless READY (stream-json parses) | **AUTH-FAIL** |  error: failed to run prompt: No model configured. Run `kimi` and use /login to sign in, then retry; or set default_model in config.toml. See log: /Users/dbenger/.kimi-code/logs/kimi-code.log | 2026-07-18 | live |
| KIMI-06 | kimi | K3 model pin (-m) | **SKIPPED-GATED** | gated on KIMI-05 | 2026-07-18 | live |
| KIMI-07 | kimi | KIMI_DISABLE_TELEMETRY honored | **PASS** | env accepted on live runs without complaint; network-level verification out of probe scope (documented limitation) | 2026-07-18 | static |
| CUR-01 | cursor | Version capture (no published semver) | **PASS** | 2026.07.16-899851b | 2026-07-18 | direct |
| CUR-02 | cursor | Auth status (cursor-agent status) | **PASS** | ✓ Logged in as domi.benger@gmail.com | 2026-07-18 | direct |
| CUR-03 | cursor | Model list (Grok pin + Composer alternative present) | **PASS** | grok-pick=grok-4.5; composer-lines=2; full list in Appendix B | 2026-07-18 | direct |
| CUR-04 | cursor | Headless READY (-p --trust from non-TTY) | **PASS** | READY | 2026-07-18 | live |
| CUR-05 | cursor | Explicit Grok pin (--model grok-4.5, never Auto) | **PASS** | READY | 2026-07-18 | live |
| CUR-06 | cursor | Headless hook events fire (community-reported gap re-probe) | **FAIL** | no markers (beforeShellExecution/afterFileEdit/stop); attribution falls back to lead-side ledger (U9) | 2026-07-18 | marker-file |
| CUR-07 | cursor | --sandbox enabled confines writes to workspace | **FAIL** | write escaped to sentinel dir; Command ran successfully (exit code 0). The sentinel file was created. | 2026-07-18 | negative |
| CUR-08 | cursor | --mode plan is read-only (reviewer-role enforcement) | **PASS** | write did not land under --mode plan | 2026-07-18 | negative |
| CC-01 | claude | Version capture (floor 2.1.212 per KTD-13) | **PASS** | 2.1.214 (Claude Code) | 2026-07-18 | direct |
| CC-02 | claude | Fable 5 availability (KTD-8 ladder top tier) | **PASS** | READY | 2026-07-18 | live |
| CC-03 | claude | /goal hard-gates a multi-condition checklist in -p | **PASS** | both goal conditions satisfied before session ended | 2026-07-18 | live |
| CC-04 | claude | Dynamic workflows can express external-CLI dispatch + requeue + pinned reviewer | **PASS** | version 2.1.214 (Claude Code) >= 2.1.154; JS script API expresses all three; live dogfood deferred to U10 wave | 2026-07-18 | static |
| CC-05 | claude | Monitors reproduce both watcher hooks' alert behaviors | **FAIL** | behavioral parity not demonstrable by probe (component experimental); validate --strict on monitors manifest said: Validating plugin manifest: /var/folders/h_/65shk8nj7_791wv94ds_g55c0000gn/T/triforge-probes.yNQkvN/miniplugin/.claude-plugin/plugin.json ✘ Found 1 error: ❯ monitors: Invalid input ⚠ Found 1 warning: ❯ monitors: 'monitor; KTD-7 fallback: keep context-monitor.sh + tool-failure-monitor.sh | 2026-07-18 | validate |
| CC-06 | claude | claude plugin validate --strict (baseline on this repo) | **PASS** | Validating plugin manifest: /Users/dbenger/projects/multi-agent-framework/.claude-plugin/plugin.json ✔ Validation passed | 2026-07-18 | validate |
| RTN-01 | claude | Scheduled Routine env: checkout, push/PR, binaries, non-interactive auth, research tools | **PENDING-U15** | resolved by the diagnostic first run in U15; delivery mode self-selects at runtime via KTD-11 preflight (commit+PR, else draft-PR-with-pending-probes, else output artifact) | 2026-07-18 | deferred |

## Consumption map (probe → consuming unit and branch)

- **AGY-02/AGY-05** → U2/U3: the Pro id pinned in every `invoke_antigravity` call and agent definition (KTD-8; never the Flash default).
- **AGY-03** → U3: native agent format reference for the four migrated definitions.
- **AGY-06/AGY-07** → U5: absent /goal or /teamwork in agy changes nothing — Claude Code owns goal gating; rows exist because the Product Contract required the probe.
- **AGY-08** → U3/U5: hooks not firing project-tier ⇒ guardrails stay at agent `tools` allowlist + permission deny rules, not hook enforcement.
- **AGY-09/AGY-10** → U2: deny-survival decides whether `--dangerously-skip-permissions` is ever passed by the adapter; sandbox result feeds the R35 confinement profile.
- **AGY-11** → U8: roster `effort` field is inert for the agy adapter unless a headless control exists (documented per KTD-8).
- **AGY-12/AGY-13** → U3: native-lane health for the four migrated plugin agents — FAIL while agy does not surface installed plugin agents headless (injection fallback operative; probed 2026-07-17 on 1.1.3); flips to PASS when native discovery lands.
- **CDX-02** → U7/U8: `codex features list` replaces version-string detection.
- **CDX-04** → U7: positive ⇒ ship `templates/.codex/hooks.json` + flip D-004 in a new ADR; negative ⇒ AE5 (prompt-enforced conventions, ADR records the negative with date).
- **CDX-05** → U7: structured review verdicts via `--output-schema`.
- **CDX-06/CDX-07** → U7: max/ultra ship as commented opt-ins only where accepted.
- **CDX-08** → U7/R25: read-only sandbox negative test evidence.
- **OC-02/OC-04** → U11/U17: pinned GLM default id + enrollment-time validation against the live list.
- **OC-05** → U8: roster effort maps to `--variant` for the OpenCode adapter.
- **OC-06** → U11: deny rules that survive `--auto` gate whether `--auto` is ever used by the adapter.
- **KIMI-03** → U12: no custom agent definitions ⇒ roles via AGENTS.md sections + per-invocation prompts (fallback documented here).
- **KIMI-04** → U12: `--skills-dir` gives .agents/skills interop without injection.
- **KIMI-05/KIMI-06** → U12: stream-json capture shape; K3 alias for the shipped default.
- **CUR-01/CUR-03/CUR-05** → U13: version capture into roster registration; Grok pin (never Auto router).
- **CUR-06** → U13: hook events not firing headless ⇒ afterFileEdit attribution hook does not ship; lead-side ledger attribution (U9) covers it.
- **CUR-07/CUR-08** → U13: sandbox + plan-mode read-only are the reviewer-role enforcement mechanisms.
- **CC-02** → U6/U10: Fable availability decides the spawn-time model override for lead + never-downgrade agents (KTD-8).
- **CC-03** → U5: /goal capability gate for retiring ship-loop.sh and the promise convention (KTD-7: mechanism stays until its replacement's probe passes).
- **CC-04** → U5/U10: wave-orchestration delegates 5+-task waves to dynamic workflows; U10's dogfooded wave is the live evidence.
- **CC-05** → U5: monitors parity not demonstrated ⇒ context-monitor.sh and tool-failure-monitor.sh stay, with this row as the recorded reason.
- **CC-06** → U6/U16: `claude plugin validate --strict` release gate baseline.
- **RTN-01** → U14/U15: headless watch delivery mode; runtime preflight absorbs all three outcomes.

## Appendix A: codex features list

```
apply_patch_freeform                 removed            false
apply_patch_streaming_events         under development  false
apps                                 stable             true
apps_mcp_path_override               removed            false
artifact                             under development  false
auth_elicitation                     stable             true
browser_use                          stable             true
browser_use_external                 stable             true
browser_use_full_cdp_access          stable             true
chronicle                            under development  false
code_mode                            under development  false
code_mode_host                       stable             true
code_mode_only                       under development  false
codex_git_commit                     removed            false
collaboration_modes                  removed            true
computer_use                         stable             true
concurrent_reasoning_summaries       under development  false
current_time_reminder                under development  false
default_mode_request_user_input      under development  false
deferred_executor                    under development  false
elevated_windows_sandbox             removed            false
enable_fanout                        under development  false
enable_mcp_apps                      under development  false
enable_request_compression           stable             true
exec_permission_approvals            under development  false
experimental_windows_sandbox         removed            false
external_migration                   removed            false
fast_mode                            stable             true
goals                                stable             true
guardian_approval                    stable             true
hooks                                stable             true
image_detail_original                removed            false
image_generation                     stable             true
in_app_browser                       stable             true
item_ids                             under development  false
js_repl                              removed            false
js_repl_tools_only                   removed            false
local_thread_store_compression       under development  false
memories                             experimental       false
mentions_v2                          stable             true
multi_agent                          stable             true
multi_agent_mode                     removed            false
multi_agent_v2                       under development  false
network_proxy                        experimental       false
non_prefixed_mcp_tool_names          under development  false
personality                          stable             true
plugin_hooks                         removed            false
plugin_sharing                       stable             true
plugins                              stable             true
prevent_idle_sleep                   experimental       false
realtime_conversation                under development  false
remote_compaction_v2                 stable             true
remote_control                       removed            false
remote_models                        removed            false
remote_plugin                        stable             true
request_permissions_tool             under development  false
request_rule                         removed            false
resize_all_images                    removed            true
respect_system_proxy                 under development  false
responses_websockets                 removed            false
responses_websockets_v2              removed            false
rollout_budget                       under development  false
runtime_metrics                      under development  false
search_tool                          removed            false
secret_auth_storage                  stable             false
shell_snapshot                       stable             true
shell_tool                           stable             true
shell_zsh_fork                       under development  false
skill_env_var_dependency_prompt      removed            false
skill_mcp_dependency_install         stable             true
sqlite                               removed            true
standalone_web_search                under development  false
steer                                removed            true
terminal_resize_reflow               removed            true
terminal_visualization_instructions  under development  false
token_budget                         under development  false
tool_call_mcp_elicitation            stable             true
tool_search                          removed            false
tool_search_always_defer_mcp_tools   removed            true
tool_suggest                         stable             true
tui_app_server                       removed            true
unavailable_dummy_tools              removed            false
undo                                 removed            false
unified_exec                         stable             true
unified_exec_zsh_fork                under development  false
use_agent_identity                   under development  false
use_legacy_landlock                  deprecated         false
use_linux_sandbox_bwrap              removed            false
web_search_cached                    deprecated         false
web_search_request                   deprecated         false
workspace_dependencies               stable             true
workspace_owner_usage_nudge          removed            false
```

## Appendix B: model lists

### agy models
```
Gemini 3.5 Flash (Medium)
Gemini 3.5 Flash (High)
Gemini 3.5 Flash (Low)
Gemini 3.1 Pro (Low)
Gemini 3.1 Pro (High)
Claude Sonnet 4.6 (Thinking)
Claude Opus 4.6 (Thinking)
GPT-OSS 120B (Medium)
```

### agy agents
```
Available agents:
```

### opencode models openrouter (GLM lines)
```
(not captured)
```

### cursor-agent --list-models
```
Available models

auto - Auto (default)
gpt-5.3-codex-low - Codex 5.3 Low
gpt-5.3-codex-low-fast - Codex 5.3 Low Fast
gpt-5.3-codex - Codex 5.3
gpt-5.3-codex-fast - Codex 5.3 Fast
gpt-5.3-codex-high - Codex 5.3 High
gpt-5.3-codex-high-fast - Codex 5.3 High Fast
gpt-5.3-codex-xhigh - Codex 5.3 Extra High
gpt-5.3-codex-xhigh-fast - Codex 5.3 Extra High Fast
gpt-5.2 - GPT-5.2
gpt-5.2-codex-low - Codex 5.2 Low
gpt-5.2-codex-low-fast - Codex 5.2 Low Fast
gpt-5.2-codex - Codex 5.2
gpt-5.2-codex-fast - Codex 5.2 Fast
gpt-5.2-codex-high - Codex 5.2 High
gpt-5.2-codex-high-fast - Codex 5.2 High Fast
gpt-5.2-codex-xhigh - Codex 5.2 Extra High
gpt-5.2-codex-xhigh-fast - Codex 5.2 Extra High Fast
gpt-5.1-codex-max-low - Codex 5.1 Max Low
gpt-5.1-codex-max-low-fast - Codex 5.1 Max Low Fast
gpt-5.1-codex-max-medium - Codex 5.1 Max
gpt-5.1-codex-max-medium-fast - Codex 5.1 Max Medium Fast
gpt-5.1-codex-max-high - Codex 5.1 Max High
gpt-5.1-codex-max-high-fast - Codex 5.1 Max High Fast
gpt-5.1-codex-max-xhigh - Codex 5.1 Max Extra High
gpt-5.1-codex-max-xhigh-fast - Codex 5.1 Max Extra High Fast
cursor-grok-4.5-high - Cursor Grok 4.5
cursor-grok-4.5-high-fast - Cursor Grok 4.5 Fast
composer-2.5 - Composer 2.5
claude-opus-4-8-thinking-high - Opus 4.8 1M Thinking
claude-opus-4-8-thinking-high-fast - Opus 4.8 1M Thinking Fast
gpt-5.6-sol-high - GPT-5.6 Sol 1M High
gpt-5.6-sol-high-fast - GPT-5.6 Sol High Fast
gpt-5.6-sol-xhigh - GPT-5.6 Sol 1M Extra High
gpt-5.6-sol-xhigh-fast - GPT-5.6 Sol Extra High Fast
gpt-5.5-high - GPT-5.5 1M High
gpt-5.5-high-fast - GPT-5.5 High Fast
claude-fable-5-thinking-high - Fable 5 1M Thinking (NO ZDR)
claude-fable-5-thinking-xhigh - Fable 5 1M Extra High Thinking (NO ZDR)
claude-opus-4-7-thinking-high - Opus 4.7 1M High Thinking
claude-opus-4-7-thinking-high-fast - Opus 4.7 1M High Thinking Fast
gpt-5.4-high - GPT-5.4 1M High
gpt-5.4-high-fast - GPT-5.4 High Fast
cursor-grok-4.5-low - Cursor Grok 4.5 Low
cursor-grok-4.5-low-fast - Cursor Grok 4.5 Low Fast
cursor-grok-4.5-medium - Cursor Grok 4.5 Medium
cursor-grok-4.5-medium-fast - Cursor Grok 4.5 Medium Fast
composer-2.5-fast - Composer 2.5 Fast
claude-opus-4-8-low - Opus 4.8 1M Low
claude-opus-4-8-low-fast - Opus 4.8 1M Low Fast
claude-opus-4-8-medium - Opus 4.8 1M Medium
claude-opus-4-8-medium-fast - Opus 4.8 1M Medium Fast
claude-opus-4-8-high - Opus 4.8 1M
claude-opus-4-8-high-fast - Opus 4.8 1M Fast
claude-opus-4-8-xhigh - Opus 4.8 1M Extra High
claude-opus-4-8-xhigh-fast - Opus 4.8 1M Extra High Fast
claude-opus-4-8-max - Opus 4.8 1M Max
claude-opus-4-8-max-fast - Opus 4.8 1M Max Fast
claude-opus-4-8-thinking-low - Opus 4.8 1M Low Thinking
claude-opus-4-8-thinking-low-fast - Opus 4.8 1M Low Thinking Fast
claude-opus-4-8-thinking-medium - Opus 4.8 1M Medium Thinking
claude-opus-4-8-thinking-medium-fast - Opus 4.8 1M Medium Thinking Fast
claude-opus-4-8-thinking-xhigh - Opus 4.8 1M Extra High Thinking
claude-opus-4-8-thinking-xhigh-fast - Opus 4.8 1M Extra High Thinking Fast
claude-opus-4-8-thinking-max - Opus 4.8 1M Max Thinking
claude-opus-4-8-thinking-max-fast - Opus 4.8 1M Max Thinking Fast
gpt-5.6-sol-none - GPT-5.6 Sol 1M None
gpt-5.6-sol-none-fast - GPT-5.6 Sol None Fast
gpt-5.6-sol-low - GPT-5.6 Sol 1M Low
gpt-5.6-sol-low-fast - GPT-5.6 Sol Low Fast
gpt-5.6-sol-medium - GPT-5.6 Sol 1M
gpt-5.6-sol-medium-fast - GPT-5.6 Sol Fast
gpt-5.6-sol-max - GPT-5.6 Sol 1M Max
gpt-5.6-sol-max-fast - GPT-5.6 Sol Max Fast
gpt-5.5-none - GPT-5.5 1M None
gpt-5.5-none-fast - GPT-5.5 None Fast
gpt-5.5-low - GPT-5.5 1M Low
gpt-5.5-low-fast - GPT-5.5 Low Fast
gpt-5.5-medium - GPT-5.5 1M
gpt-5.5-medium-fast - GPT-5.5 Fast
gpt-5.5-extra-high - GPT-5.5 1M Extra High
gpt-5.5-extra-high-fast - GPT-5.5 Extra High Fast
claude-fable-5-low - Fable 5 1M Low (NO ZDR)
claude-fable-5-medium - Fable 5 1M Medium (NO ZDR)
claude-fable-5-high - Fable 5 1M (NO ZDR)
claude-fable-5-xhigh - Fable 5 1M Extra High (NO ZDR)
claude-fable-5-max - Fable 5 1M Max (NO ZDR)
claude-fable-5-thinking-low - Fable 5 1M Low Thinking (NO ZDR)
claude-fable-5-thinking-medium - Fable 5 1M Medium Thinking (NO ZDR)
claude-fable-5-thinking-max - Fable 5 1M Max Thinking (NO ZDR)
claude-sonnet-5-low - Sonnet 5 1M Low
claude-sonnet-5-medium - Sonnet 5 1M Medium
claude-sonnet-5-high - Sonnet 5 1M
claude-sonnet-5-xhigh - Sonnet 5 1M Extra High
claude-sonnet-5-max - Sonnet 5 1M Max
claude-sonnet-5-thinking-low - Sonnet 5 1M Low Thinking
claude-sonnet-5-thinking-medium - Sonnet 5 1M Medium Thinking
claude-sonnet-5-thinking-high - Sonnet 5 1M Thinking
claude-sonnet-5-thinking-xhigh - Sonnet 5 1M Extra High Thinking
claude-sonnet-5-thinking-max - Sonnet 5 1M Max Thinking
gpt-5.6-terra-none - GPT-5.6 Terra 1M None
gpt-5.6-terra-none-fast - GPT-5.6 Terra None Fast
gpt-5.6-terra-low - GPT-5.6 Terra 1M Low
gpt-5.6-terra-low-fast - GPT-5.6 Terra Low Fast
gpt-5.6-terra-medium - GPT-5.6 Terra 1M
gpt-5.6-terra-medium-fast - GPT-5.6 Terra Fast
gpt-5.6-terra-high - GPT-5.6 Terra 1M High
gpt-5.6-terra-high-fast - GPT-5.6 Terra High Fast
gpt-5.6-terra-xhigh - GPT-5.6 Terra 1M Extra High
gpt-5.6-terra-xhigh-fast - GPT-5.6 Terra Extra High Fast
gpt-5.6-terra-max - GPT-5.6 Terra 1M Max
gpt-5.6-terra-max-fast - GPT-5.6 Terra Max Fast
claude-4.6-sonnet-medium - Sonnet 4.6 1M
claude-4.6-sonnet-medium-thinking - Sonnet 4.6 1M Thinking
claude-opus-4-7-low - Opus 4.7 1M Low
claude-opus-4-7-low-fast - Opus 4.7 1M Low Fast
claude-opus-4-7-medium - Opus 4.7 1M Medium
claude-opus-4-7-medium-fast - Opus 4.7 1M Medium Fast
claude-opus-4-7-high - Opus 4.7 1M High
claude-opus-4-7-high-fast - Opus 4.7 1M High Fast
claude-opus-4-7-xhigh - Opus 4.7 1M
claude-opus-4-7-xhigh-fast - Opus 4.7 1M Fast
claude-opus-4-7-max - Opus 4.7 1M Max
claude-opus-4-7-max-fast - Opus 4.7 1M Max Fast
claude-opus-4-7-thinking-low - Opus 4.7 1M Low Thinking
claude-opus-4-7-thinking-low-fast - Opus 4.7 1M Low Thinking Fast
claude-opus-4-7-thinking-medium - Opus 4.7 1M Medium Thinking
claude-opus-4-7-thinking-medium-fast - Opus 4.7 1M Medium Thinking Fast
claude-opus-4-7-thinking-xhigh - Opus 4.7 1M Thinking
claude-opus-4-7-thinking-xhigh-fast - Opus 4.7 1M Thinking Fast
claude-opus-4-7-thinking-max - Opus 4.7 1M Max Thinking
claude-opus-4-7-thinking-max-fast - Opus 4.7 1M Max Thinking Fast
gpt-5.4-low - GPT-5.4 1M Low
gpt-5.4-medium - GPT-5.4 1M
gpt-5.4-medium-fast - GPT-5.4 Fast
gpt-5.4-xhigh - GPT-5.4 1M Extra High
gpt-5.4-xhigh-fast - GPT-5.4 Extra High Fast
claude-4.6-opus-high - Opus 4.6 1M
claude-4.6-opus-max - Opus 4.6 1M Max
claude-4.6-opus-high-thinking - Opus 4.6 1M Thinking
claude-4.6-opus-max-thinking - Opus 4.6 1M Max Thinking
claude-4.5-opus-high - Opus 4.5
claude-4.5-opus-high-thinking - Opus 4.5 Thinking
gpt-5.2-low - GPT-5.2 Low
gpt-5.2-low-fast - GPT-5.2 Low Fast
gpt-5.2-fast - GPT-5.2 Fast
gpt-5.2-high - GPT-5.2 High
gpt-5.2-high-fast - GPT-5.2 High Fast
gpt-5.2-xhigh - GPT-5.2 Extra High
gpt-5.2-xhigh-fast - GPT-5.2 Extra High Fast
gpt-5.6-luna-none - GPT-5.6 Luna 1M None
gpt-5.6-luna-none-fast - GPT-5.6 Luna None Fast
gpt-5.6-luna-low - GPT-5.6 Luna 1M Low
gpt-5.6-luna-low-fast - GPT-5.6 Luna Low Fast
gpt-5.6-luna-medium - GPT-5.6 Luna 1M
gpt-5.6-luna-medium-fast - GPT-5.6 Luna Fast
gpt-5.6-luna-high - GPT-5.6 Luna 1M High
gpt-5.6-luna-high-fast - GPT-5.6 Luna High Fast
gpt-5.6-luna-xhigh - GPT-5.6 Luna 1M Extra High
gpt-5.6-luna-xhigh-fast - GPT-5.6 Luna Extra High Fast
gpt-5.6-luna-max - GPT-5.6 Luna 1M Max
gpt-5.6-luna-max-fast - GPT-5.6 Luna Max Fast
gemini-3.1-pro - Gemini 3.1 Pro
gpt-5.4-mini-none - GPT-5.4 Mini None
gpt-5.4-mini-low - GPT-5.4 Mini Low
gpt-5.4-mini-medium - GPT-5.4 Mini
gpt-5.4-mini-high - GPT-5.4 Mini High
gpt-5.4-mini-xhigh - GPT-5.4 Mini Extra High
gpt-5.4-nano-none - GPT-5.4 Nano None
gpt-5.4-nano-low - GPT-5.4 Nano Low
gpt-5.4-nano-medium - GPT-5.4 Nano
gpt-5.4-nano-high - GPT-5.4 Nano High
gpt-5.4-nano-xhigh - GPT-5.4 Nano Extra High
claude-4.5-sonnet - Sonnet 4.5
claude-4.5-sonnet-thinking - Sonnet 4.5 Thinking
gpt-5.1-low - GPT-5.1 Low
gpt-5.1 - GPT-5.1
gpt-5.1-high - GPT-5.1 High
gemini-3-flash - Gemini 3 Flash
gemini-3.5-flash - Gemini 3.5 Flash
gpt-5.1-codex-mini-low - Codex 5.1 Mini Low
gpt-5.1-codex-mini - Codex 5.1 Mini
gpt-5.1-codex-mini-high - Codex 5.1 Mini High
claude-4-sonnet - Sonnet 4
claude-4-sonnet-thinking - Sonnet 4 Thinking
gpt-5-mini - GPT-5 Mini
kimi-k2.7-code - Kimi K2.7 Code
glm-5.2-high - GLM 5.2
glm-5.2-max - GLM 5.2 Max

Tip: use --model <id> (or /model <id> in interactive mode) to switch. Parameterized models also accept quoted overrides, e.g. --model 'claude-opus-4-8[context=1m,effort=high,fast=false]'.
```
