# Capability probe record — 2026-09 cycle

**Generated:** 2026-09-12 03:46 UTC by `scripts/probe-capabilities.sh` (rerunnable; `/cli-watch` re-runs it each cycle)
**Host:** Darwin 25.5.0; timeout via `timeout`
**Mode:** full (live probes)

Outcome vocabulary: **PASS** capability demonstrated · **FAIL** capability absent or not demonstrated (consuming units take their documented fallback) · **UNAVAILABLE** CLI not installed · **AUTH-FAIL** CLI present but not authenticated on this machine · **QUOTA-FAIL** CLI authenticated but the provider's usage quota is exhausted this cycle (dependent rows gate on it, not on a login) · **SKIPPED / SKIPPED-GATED** not run (`--skip-live` or gated on a failed READY probe) · **PENDING-U15** resolved by a later unit, with the absorbing design noted · **PENDING-AUTH** a live row that needs a login this sprint never performs (R18), with the exact command to run afterwards · **INFO** an honest boundary note, not a pass/fail (e.g. a by-design non-confinement recorded so the record does not overclaim).

## Summary

88 probes: 68 PASS · 12 FAIL · 0 AUTH-FAIL · 1 QUOTA-FAIL · 0 UNAVAILABLE · 4 SKIPPED · 1 PENDING-U15 · 0 PENDING-AUTH · 2 INFO (counters sum to 88)

## Probe rows

| ID | CLI | Capability | Outcome | Evidence | Date | Method |
|---|---|---|---|---|---|---|
| AGY-01 | agy | Version capture | **PASS** | 1.2.1  | 2026-09-12 | direct |
| AGY-02 | agy | Model list (newest Gemini at its highest thinking level — D-022 pin; newest Pro alongside) | **PASS** | pick=Gemini 3.8 Flash (High); newest Pro=Gemini 3.1 Pro (High); full list in Appendix B | 2026-09-12 | direct |
| AGY-03 | agy | Native agent listing (agy agents) | **PASS** | architecture-reviewer codebase-analyst documentation-writer flutter_a11y_agent targeted-researcher | 2026-09-12 | direct |
| AGY-04 | agy | Headless READY (agy -p) | **PASS** | READY | 2026-09-12 | live |
| AGY-05 | agy | Explicit model pin (--model) | **PASS** | accepted form: --model "Gemini 3.8 Flash (High)" | 2026-09-12 | live |
| AGY-06 | agy | /goal command exists in CLI | **FAIL** | output indistinguishable from model-mediated canary — not a registered CLI command; probe: I see you've activated the `/goal` command, which is great for kicking off long-running, autonomous tasks (like those you might want to leave running overnight)! However, it looks like you didn't specify a task. What wou | 2026-09-12 | live |
| AGY-07 | agy | /teamwork-preview command exists in CLI | **FAIL** | output indistinguishable from model-mediated canary — not a registered CLI command; probe: I've created a draft artifact for our teamwork project prompt (you can find it in the sidebar). We'll build this up together before handing it off to the teamwork multi-agent system. To get started with **Step 1**, could | 2026-09-12 | live |
| AGY-08 | agy | Hooks fire under agy -p (.agents/hooks.json named-hook shape, workspace bound via --add-dir) | **FAIL** | no markers (PreInvocation/PostInvocation/PreToolUse/PostToolUse/Stop) with the documented shape + --add-dir; probe fixture | 2026-09-12 | marker-file |
| AGY-09 | agy | Explicit deny survives --dangerously-skip-permissions | **FAIL** | denied command executed (fixture); adapter must never pass the skip-permissions flag; I have successfully run the command `touch deny-marker-agy.txt` in your current working directory. The file has been created. | 2026-09-12 | negative |
| AGY-10 | agy | --sandbox confines writes to workspace | **FAIL** | write escaped to sentinel dir; I have started the command `touch /var/folders/h_/65shk8nj7_791wv94ds_g55c0000gn/T//triforge-probes.PIK5JC/sentinel/agy-sbx.txt` in the background. I will let you know once it finishes. I have successfully executed the r | 2026-09-12 | negative |
| AGY-11a | agy | Suffix form accepted (--model "Gemini 3.8 Flash (Low)") | **PASS** | READY on the (Low) suffix variant | 2026-09-12 | live |
| AGY-11b | agy | Bare slug + --effort accepted (--model gemini-3.8-flash --effort low) | **PASS** | READY on the bare slug family with --effort | 2026-09-12 | live |
| AGY-11c | agy | Display name + --effort rejected (negative) | **PASS** | rejected (rc=1): error: invalid model selection (--model "Gemini 3.8 Flash (High)" --effort "low"): --effort is not supported for model "Gemini 3.8 Flash (High)" | 2026-09-12 | negative |
| AGY-14 | agy | /skills lists the shipped skills from .agents/skills (--add-dir) | **PASS** | all 12 shipped names listed; tf-agents-skill listed | 2026-09-12 | live |
| AGY-14b | agy | /<skill> expands headless from .agents/skills (--add-dir) | **PASS** | SKILL-OK tf-agents-skill | 2026-09-12 | live |
| AGY-15 | agy | --output-format json envelope (status / response / denied_actions) | **PASS** | denied_actions carried: read_url; status=SUCCESS response_len=0 denied=read_url keys=conversation_id,denied_actions,duration_seconds,num_turns,response,status,usage | 2026-09-12 | live |
| AGY-11 | agy | Headless thinking/effort control | **PASS** | dedicated flag present: --effort                        Reasoning effort for the current CLI session (low\|medium\|h; adapter keeps the model-suffix form (KTD1) — see AGY-11a/11b/11c | 2026-09-12 | static |
| AGY-12 | agy | Triforge plugin agents respond through their definitions | **PASS** | all four listed; codebase-analyst round-trip: READY | 2026-09-12 | live |
| AGY-13 | agy | architecture-reviewer cannot run shell (tools-allowlist negative) | **PASS** | marker absent in fixture and scratch; I cannot execute shell commands, and as the Architecture Reviewer agent, I am restricted from modifying files outside of the `ops/` directory. My role is to review code design based on the documentation in `ops/` and wri | 2026-09-12 | negative |
| AGY-16 | agy | Native-mode negative (--agent targeted-researcher, TRIFORGE_AGY_MODE=native): rm -rf sentinel + git push executed by neither | **PASS** | sentinel dir survived; no push-execution signature; jetski: no output produced — a tool required the "write_file" permission that headless mode cannot prompt for, so it was auto-denied. Add an allow-rule under permissions.allow in settings.json (e.g. write_file(<target>)) | 2026-09-12 | negative |
| CDX-01 | codex | Version capture | **PASS** | codex-cli 0.154.0 | 2026-09-12 | direct |
| CDX-02 | codex | codex features list (runtime capability detection) | **PASS** | notable: goals                                    stable             true;guardian_approval                        stable             true;guardian_enhanced_node_repl_transcripts  under development  false;guardian_ext                             under development  false;guardian_node_repl_transcript_images     under development  false;guardian_reuse_parent_compaction         under development  false;full capture in Appendix A | 2026-09-12 | direct |
| CDX-03 | codex | Headless READY on gpt-6-astra | **PASS** | READY | 2026-09-12 | live |
| CDX-04 | codex | Hooks fire under codex exec (D-004 re-probe) | **PASS** | fired: SessionStart UserPromptSubmit PreToolUse Stop; hook-lines: Run this shell command: echo hooktest;warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.;warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.; | 2026-09-12 | marker-file |
| CDX-05 | codex | --output-schema constrains final message to schema-valid JSON (gpt-6-astra) | **PASS** | {"verdict":"Correct: 2 + 2 = 4.","confidence":"HIGH"} | 2026-09-12 | live |
| CDX-06 | codex | model_reasoning_effort="max" accepted on gpt-6-astra | **PASS** | READY | 2026-09-12 | live |
| CDX-07 | codex | model_reasoning_effort="ultra" accepted on gpt-6-astra | **PASS** | READY | 2026-09-12 | live |
| CDX-08 | codex | read-only sandbox rejects writes on gpt-6-astra (negative) | **PASS** | write did not land under -s read-only | 2026-09-12 | negative |
| CDX-09 | codex | $<skill> expands under exec from the fixture (.codex/skills) | **PASS** | SKILL-OK tf-codex-skill | 2026-09-12 | live |
| CDX-09b | codex | $<skill> expands under exec from a linked worktree under TMPDIR | **PASS** | SKILL-OK tf-codex-skill from cdx-wt | 2026-09-12 | live |
| CDX-10 | codex | Project trust gate: AGENTS.md marker visible under exec | **PASS** | exact trust entry present; marker visible via: root-AGENTS.md | 2026-09-12 | live |
| CDX-11 | codex | No 'malformed agent role' warning with .codex/triforge-agents.toml (no .codex/agents/) | **PASS** | READY; stderr carries no 'malformed agent role' line | 2026-09-12 | live |
| CDX-11b | codex | Control: .codex/agents/agents.toml still triggers the sweep warning | **PASS** | warning emitted for the old location: /var/folders/h_/65shk8nj7_791wv94ds_g55c0000gn/T//triforge-probes.PIK5JC/cdx-role-b-err.txt:warning: Ignoring malformed agent role definitio | 2026-09-12 | negative |
| OC-01 | opencode | Version capture | **PASS** | 1.18.30 | 2026-09-12 | direct |
| OC-02 | opencode | OpenRouter model list (GLM id for the shipped default — D-023) | **PASS** | glm-pick=openrouter/z-ai/glm-5.3; full list in Appendix B | 2026-09-12 | direct |
| OC-03 | opencode | Headless READY (run --format json parses) | **PASS** | JSON events parsed; READY present | 2026-09-12 | live |
| OC-04 | opencode | OpenRouter GLM pin (-m openrouter/z-ai/glm-5.3) | **PASS** | {"type":"step_start","timestamp":1789185062124,"sessionID":"ses_f6c4293b0ffeBRJUbU23DBV9bl","part":{"id":"prt_093bd74e9001HfjP0uiK3OLzK7","messageID":"msg_093bd6d13001qyLE2P9NY11qy1","sessionID":"ses_f6c4293b0ffeBRJUbU23 | 2026-09-12 | live |
| OC-05 | opencode | --variant (reasoning effort) accepted | **PASS** | {"type":"step_start","timestamp":1789185064907,"sessionID":"ses_f6c428842ffemxi6uDTftCLfJu","part":{"id":"prt_093bd7fc7001LoAXm6gZq3xNui","messageID":"msg_093bd787e001Hx3PCSJzRzp6qz","sessionID":"ses_f6c428842ffemxi6uDTf | 2026-09-12 | live |
| OC-06 | opencode | Explicit deny survives --auto (OPENCODE_PERMISSION + project rule, -m pinned, 300 s) | **FAIL** | denied command executed anyway — adapter stays off --auto (D-033); {"type":"step_start","timestamp":1789185067339,"sessionID":"ses_f6c427de9ffeg8Zj0pjkYs0yk5","part":{"id":"prt_093bd8949001MNsLEw4X639UmO","messageID":"msg_093bd82d6001SKeRl25yOa2Ly2","sessionID":"ses_f6c427de9ffeg8Zj0pjk | 2026-09-12 | negative |
| OC-06b | opencode | Explicit deny holds without --auto (control: the adapter's posture) | **FAIL** | denied command executed without --auto — the deny rule itself is not honored headless; {"type":"step_start","timestamp":1789185071463,"sessionID":"ses_f6c427003ffeaPPaiQ1yybm8bJ","part":{"id":"prt_093bd99640011d3EDxr32UOfhY","messageID":"msg_093bd90bc001iFadaRdP2x842N","sessionID":"ses_f6c427003ffeaPPaiQ1y | 2026-09-12 | negative |
| OC-07 | opencode | /<skill> expands from .agents/skills (native skill tool event) | **PASS** | skill tool event + SKILL-OK | 2026-09-12 | live |
| OC-08 | opencode | --command runs .opencode/command/<name>.md | **PASS** | CMD-OK tf-cmd-opencode | 2026-09-12 | live |
| KIMI-01 | kimi | Version capture | **PASS** | 0.42.0 | 2026-09-12 | direct |
| KIMI-02 | kimi | Config/auth validation (kimi doctor) | **PASS** | Kimi doctor OK config.toml /Users/dbenger/.kimi-code/config.toml OK tui.toml /Users/dbenger/.kimi-code/tui.toml All checked config files are valid. | 2026-09-12 | direct |
| KIMI-03 | kimi | Custom agent definitions (--agent / --agent-file CLI surface) | **PASS** | --agent <name>                Agent profile to start the new session with. Custom profiles are discovered from agent directories or loaded via --agent-file. Can | 2026-09-12 | static |
| KIMI-04 | kimi | Skills directory flag (--skills-dir) present (documented; adapter no longer passes it — D-024) | **PASS** | --skills-dir present in help (repeatable) | 2026-09-12 | static |
| KIMI-05 | kimi | Headless READY (stream-json parses) | **QUOTA-FAIL** | signed in, but the provider quota is exhausted for this cycle — re-run after the refresh or extra usage: {"role":"meta","type":"system.version","version":"0.42.0"} error: failed to run prompt: provider.auth_error: 403 You've reached your monthly usage limit for this billing cycle. Your quota will be refreshed in the next cycle. To continue now, purchase extra usage or upgrade your  | 2026-09-12 | live |
| KIMI-06 | kimi | K3 model pin (-m; kimi-code/k3 first) | **SKIPPED-GATED** | KIMI-05 is QUOTA-FAIL (usage quota exhausted this cycle) — re-run the harness after the quota refresh | 2026-09-12 | live |
| KIMI-08 | kimi | Reviewer --agent-file is read-only (tools allowlist negative) | **SKIPPED-GATED** | KIMI-05 is QUOTA-FAIL (usage quota exhausted this cycle) — re-run the harness after the quota refresh | 2026-09-12 | live |
| KIMI-09 | kimi | /skill:<name> expands from .agents/skills | **SKIPPED-GATED** | KIMI-05 is QUOTA-FAIL (usage quota exhausted this cycle) — re-run the harness after the quota refresh | 2026-09-12 | live |
| KIMI-07 | kimi | KIMI_DISABLE_TELEMETRY honored | **PASS** | env accepted on live runs without complaint; network-level verification out of probe scope (documented limitation) | 2026-09-12 | static |
| CUR-01 | cursor | Version capture (no published semver; resolved binary: cursor-agent) | **PASS** | 2026.09.10-fd3934a | 2026-09-12 | direct |
| CUR-02 | cursor | Auth status (cursor-agent status) | **PASS** | ✓ Logged in as domi.benger@gmail.com | 2026-09-12 | direct |
| CUR-03 | cursor | Model list (Grok pin — prefers cursor-<family>-xhigh; Composer alternative present) | **PASS** | grok-pick=cursor-grok-4.6-xhigh (family grok-4.6); composer-lines=2; full list in Appendix B | 2026-09-12 | direct |
| CUR-04 | cursor | Headless READY (-p --trust from non-TTY) | **PASS** | READY | 2026-09-12 | live |
| CUR-05 | cursor | Explicit Grok pin (--model cursor-grok-4.6-xhigh, never Auto) | **PASS** | READY | 2026-09-12 | live |
| CUR-06 | cursor | Headless hook events fire (community-reported gap re-probe) | **FAIL** | no markers (beforeShellExecution/afterFileEdit/stop); attribution stays lead-side from the lease ledger | 2026-09-12 | marker-file |
| CUR-07 | cursor | --sandbox enabled confines writes to workspace | **FAIL** | write escaped to sentinel dir; The command completed successfully (exit code 0). The sentinel file `cursor-sbx.txt` is in place. | 2026-09-12 | negative |
| CUR-08 | cursor | --mode plan is read-only (reviewer-role enforcement) | **PASS** | write did not land under --mode plan | 2026-09-12 | negative |
| CUR-09 | cursor | /<skill> expands in -p from .cursor/skills | **PASS** | SKILL-OK tf-cursor-skill | 2026-09-12 | live |
| CUR-10 | cursor | Bracket effort form rejected (--model "grok-4.6[effort=xhigh]", negative) | **PASS** | rejected (rc=1): Cannot use this model: grok-4.6[effort=xhigh]. Available models: auto, gpt-5.3-codex-low, gpt-5.3-codex-low-fast, gpt-5.3-codex, gpt-5.3-codex-fast, gpt-5.3-codex-high, gpt-5.3-codex-high-fast, gpt-5.3-codex-xhigh, gpt-5 | 2026-09-12 | negative |
| CUR-12 | cursor | Effort-suffix mapping target READY (--model cursor-grok-4.6-xhigh from bare grok-4.6 + xhigh) | **PASS** | READY | 2026-09-12 | live |
| CUR-11 | cursor | _cursor_bin rejects a non-Cursor `agent` first on PATH (resolver fixture; shipped resolver + harness replica) | **PASS** | fake agent rejected by both; real Cursor binary chosen as agent (2026.09.10-fd3934a) | 2026-09-12 | static |
| CC-01 | claude | Version capture (floor 2.1.267 per D-034) | **PASS** | 2.1.269 (Claude Code) | 2026-09-12 | direct |
| CC-02 | claude | Fable (alias) availability (ladder top rung) | **PASS** | READY | 2026-09-12 | live |
| CC-03 | claude | /goal hard-gates an un-instructed checklist condition (-p; best-effort, 3-run majority — D-030) | **PASS** | 2/3 runs gated (b.txt created despite the create-only-a.txt instruction): run1=no-gate(a=yes,b=no) run2=gated run3=gated | 2026-09-12 | live |
| CC-07 | claude | /<skill> expands in -p from .claude/skills | **PASS** | SKILL-OK tf-claude-skill | 2026-09-12 | live |
| CC-08 | claude | claude -p authenticates under the lease env -i allowlist (KTD-14 base allowlist incl. USER) | **PASS** | READY under env -i HOME PATH TMPDIR TERM LANG COLORTERM USER NO_COLOR | 2026-09-12 | live |
| CC-07b | claude | .agents/skills is not a Claude path (/<skill> negative) | **INFO** | not expanded, as documented (shipped skills reach Claude via the plugin path): Unknown command: /tf-agents-skill | 2026-09-12 | live |
| CC-04 | claude | Dynamic workflows can express external-CLI dispatch + requeue + pinned reviewer | **PASS** | version 2.1.269 (Claude Code) >= 2.1.154; JS script API expresses all three | 2026-09-12 | static |
| CC-05 | claude | Monitors reproduce both watcher hooks' alert behaviors | **FAIL** | behavioral parity not demonstrable by probe (component experimental); validate --strict on monitors manifest said: Validating plugin manifest: /var/folders/h_/65shk8nj7_791wv94ds_g55c0000gn/T/triforge-probes.PIK5JC/miniplugin/.claude-plugin/plugin.json ✘ Found 1 error: ❯ monitors: Invalid input ⚠ Found 1 warning: ❯ monitors: 'monitor; KTD-7 fallback: keep context-monitor.sh + tool-failure-monitor.sh | 2026-09-12 | validate |
| CC-06 | claude | claude plugin validate --strict (baseline on this repo) | **PASS** | Validating marketplace manifest: /Users/dbenger/projects/multi-agent-framework/.claude-plugin/marketplace.json ✔ Validation passed | 2026-09-12 | validate |
| RTN-01 | claude | Scheduled Routine env: checkout, push/PR, binaries, non-interactive auth, research tools | **PENDING-U15** | resolved by the diagnostic first scheduled run; delivery mode self-selects at runtime via KTD-11 preflight (commit+PR, else draft-PR-with-pending-probes, else output artifact) | 2026-09-12 | deferred |
| SELF-01 | claude | resolve_role rejects an all-optional fallback chain (R21) | **PASS** | exit 5 + terminus message: resolve_role: ERROR invalid ops/roster.toml: role 'tester' fallback chain ['opencode', 'kimi'] does  | 2026-09-12 | static |
| SELF-02 | claude | coordinate.sh --dry-run emits /goal line + lease-resume paragraph | **PASS** | both markers present in the composed prompt | 2026-09-12 | static |
| SELF-03 | claude | _adapter_env strips cross-adapter credentials (R35/KTD-14) | **PASS** | codex env carries no OPENROUTER/KIMI/CURSOR key; opencode carries its own (positive control held) | 2026-09-12 | static |
| SELF-04 | claude | R35 boundary: credential-store read + network egress are NOT confined (HOME forwarded, no net filter) | **INFO** | HOME reaches builder=yes; enforced boundary is worktree writes + env-var allowlist + prompt, NOT home-credential read-isolation or egress filtering (see .claude/CLAUDE.md KTD-14) | 2026-09-12 | static |
| SELF-05 | claude | _lease_parse_status reads the Status: contract line (KTD11 seam) | **PASS** | Status: DONE -> DONE; no Status line -> MISSING; Status: BLOCKED -> BLOCKED (DONE_WITH_CONCERNS / NEEDS_CONTEXT also parsed); the echoed contract template -> MISSING, and a real BLOCKED survives a later echo | 2026-09-12 | static |
| SELF-06a | agy | Lease-lane discovery under env -i from a TMPDIR worktree: agy /skills | **PASS** | tf-agents-skill listed from the lease worktree; shipped names present 12/12 (agy --add-dir <wt> -p /skills) | 2026-09-12 | live |
| SELF-06b | codex | Lease-lane discovery under env -i from a TMPDIR worktree: codex exec skill listing | **PASS** | tf-agents-skill listed from the lease worktree; shipped names present 12/12 (codex exec -s read-only -m gpt-6-astra) | 2026-09-12 | live |
| SELF-06c | opencode | Lease-lane discovery under env -i from a TMPDIR worktree: opencode run skill listing | **PASS** | tf-agents-skill listed from the lease worktree; shipped names present 12/12 (opencode run --format json -m openrouter/z-ai/glm-5.3) | 2026-09-12 | live |
| SELF-06d | cursor | Lease-lane discovery under env -i from a TMPDIR worktree: cursor -p skill listing | **FAIL** | tf-agents-skill NOT listed; shipped names present 6/12 (missing: shadow-path-tracing systematic-debugging test-driven-development verification-before-completion wave-orchestration writing-plans) (cursor-agent -p --trust --model cursor-grok-4.6-xhigh); codebase-mapping iterative-refinement knowledge-compounding review-synthesis scope-cutting session-continuity | 2026-09-12 | live |
| SELF-06e | kimi | Lease-lane discovery under env -i from a TMPDIR worktree: kimi -p skill listing | **SKIPPED-GATED** | KIMI-05 is QUOTA-FAIL (usage quota exhausted this cycle) — re-run after the refresh | 2026-09-12 | live |
| SELF-06f | claude | Lease-lane discovery under env -i from a TMPDIR worktree: claude -p skill listing (plugin path) | **FAIL** | tf-agents-skill NOT listed; shipped names present 0/12 (missing: codebase-mapping iterative-refinement knowledge-compounding review-synthesis scope-cutting session-continuity shadow-path-tracing systematic-debugging test-driven-development verification-before-completion wave-orchestration writing-plans) (claude -p --model sonnet; .agents/skills is not a Claude path — names come from the installed plugin); None are present. | 2026-09-12 | live |
| SELF-07 | claude | TRIFORGE_TEST_BUILDER lifecycle: DONE -> review; no Status line -> leased + rc 80 (re-dispatch once), echoed template -> report-missing, second miss -> escalated; BLOCKED -> escalated (KTD11) | **PASS** | s7done:rc=0:state=review s7none:rc=80:state=leased s7blocked:rc=1:state=escalated s7echo:rc=80:state=leased s7stream:rc=0:state=review s7none2:rc=1:state=escalated:misses=2 | 2026-09-12 | static |
| SELF-08 | claude | session-start.sh is idempotent (second run prints zero session-start: lines) | **PASS** | run1 rc=0 session-start: lines=2; run2 rc=0 lines=0 (throwaway project + HOME, stub agy on PATH, CLAUDE_PLUGIN_ROOT=this checkout) | 2026-09-12 | static |
| SELF-08b | claude | skills refresh: retires a stamp-listed skill that no longer ships, keeps user dirs; a symlinked .agents ancestor is left untouched (KTD7, CWE-59) | **PASS** | old-fake-skill removed + notice; my-own-skill kept; shipped set present; symlinked target: marker kept, no stamp, no copies | 2026-09-12 | static |
| SELF-09 | claude | lease env blocks git push mechanically (pre-push hook + no-push:// URL rewrite), reads untouched (CS1/KTD11) | **PASS** | push-name=1 push-path=1 status=0 hook=2; bare remote still at 1 commit | 2026-09-12 | static |

## Consumption map (probe → consuming decision and branch)

- **AGY-02/AGY-05** → the model pinned in every `invoke_antigravity` call, the agy lease lane, and the roster default: the newest Gemini model at its highest thinking level, Pro or Flash (D-022 — supersedes the July never-Flash rule for the shipped default). The newest Pro line is reported alongside as the documented roster opt-in; a new Pro line appearing is the D-022 open watch.
- **AGY-03** → native agent listing (`agy agents`) — the discovery surface AGY-12/AGY-13/AGY-16 key off.
- **AGY-06/AGY-07** → absent /goal or /teamwork in agy changes nothing — Claude Code owns goal gating; rows exist because the Product Contract required the probe.
- **AGY-08** → project-tier hooks from `.agents/hooks.json` (documented named-hook shape, workspace bound) fired on agy 1.2.0 (lead re-probe 2026-09-11) but not on 1.2.1 (this row) — an open watch, never an enforcement path; guardrails rest on the agent `tools` allowlist + prompt rules because AGY-09/AGY-10 stay FAIL.
- **AGY-09/AGY-10** → deny-survival decides whether `--dangerously-skip-permissions` is ever passed by the adapter; the sandbox result feeds the R35 confinement profile.
- **AGY-11/AGY-11a/AGY-11b/AGY-11c** → effort rides in the (Low|Medium|High) model-name suffix (KTD1): the suffix form is accepted, `--effort` is accepted only with a bare slug family and rejected with a display name — the roster contract keeps display names; `--effort` is documented, not adopted.
- **AGY-12/AGY-13** → native-lane health for the four plugin agents; the rows carry the live evidence (listing, round-trip, tools-allowlist negative) — read the outcome there. **AGY-16** → the native-mode negative that, together with AGY-12, gates flipping the `TRIFORGE_AGY_MODE` default from injection to auto (KTD10).
- **AGY-14/AGY-14b** → skills expansion in agy's own form: `/skills` lists the shipped skills from `.agents/skills/` when the workspace is bound, and `/<skill>` expands headless (R9, KTD7).
- **AGY-15** → the `--output-format json` envelope (status, response, denied_actions) that `invoke_antigravity` parses instead of trusting exit 0 (KTD2, D-032).
- **CDX-02** → `codex features list` replaces version-string detection.
- **CDX-03/CDX-05/CDX-06/CDX-07/CDX-08** → the `gpt-6-astra` pin (D-021): READY, `--output-schema` verdicts, max/ultra acceptance (commented opt-ins only where accepted), and the read-only reviewer sandbox on Astra (the ADR open watch).
- **CDX-04** → hooks under `codex exec` with `--dangerously-bypass-hook-trust` in an untrusted fixture (`templates/.codex/hooks.json` ships on the strength of this row).
- **CDX-09/CDX-09b** → `$<skill>` expansion under `exec` from the fixture and from a linked worktree under TMPDIR — the lease lane's shape (linked worktrees inherit root trust, D-026).
- **CDX-10** → the project trust gate: AGENTS.md marker visibility with/without a `[projects."<abs>"]` trust entry; INFO when no entry exists (R18: the sprint writes no user-tier setting; `/setup` reports trust without writing it).
- **CDX-11/CDX-11b** → `.codex/triforge-agents.toml` is the deployed name (D-026/KTD5): no "malformed agent role" sweep warning; 11b is the control that the old `.codex/agents/agents.toml` location still triggers it.
- **OC-02/OC-04** → the `glm-5.3` default (D-023) + enrollment-time validation against the live list.
- **OC-05** → roster effort maps to `--variant` for the OpenCode adapter.
- **OC-06/OC-06b** → `OPENCODE_PERMISSION` + project rule with and without `--auto` (D-033 open watch): the adapter stays off `--auto` until the deny survives it twice.
- **OC-07/OC-08** → `/<skill>` yields a native `skill` tool event from `.agents/skills/`; `--command` runs `.opencode/command/` files (R9).
- **KIMI-03** → `--agent-file` carries the builder/reviewer briefs (D-024, KTD4). **KIMI-04** → `--skills-dir` is still present but no longer passed (D-024). **KIMI-05/KIMI-06** → stream-json capture shape; the `kimi-code/k3` alias. **KIMI-08/KIMI-09** → reviewer read-only allowlist + `/skill:<name>` expansion; PENDING-AUTH until `kimi login`.
- **CUR-01/CUR-03/CUR-05/CUR-12** → `_cursor_bin` resolution (cursor-agent first, verified `agent` fallback — CUR-11 is its fixture), the `cursor-grok-4.6-xhigh` pin, and the bare-family + effort → suffixed-id mapping (D-025, KTD3); **CUR-10** proves the bracket form is rejected.
- **CUR-06** → hook events not firing headless ⇒ no afterFileEdit attribution hook ships; lead-side ledger attribution covers it. **CUR-07/CUR-08** → sandbox + plan-mode read-only are the reviewer-role enforcement mechanisms. **CUR-09** → `/<skill>` expansion in `-p` from `.cursor/skills/`.
- **CC-02** → the `fable` alias decides the spawn-time override for the lead + never-downgrade agents (ladder Fable 5.1 → Opus 5 → Sonnet 5, D-020).
- **CC-03** → best-effort (D-030): three runs, majority; `ops/.sprint-complete` + `coordinate.sh` stay the completion mechanism and `/goal` remains an assist composed into the prompt.
- **CC-04** → wave-orchestration may delegate 5+-task waves to dynamic workflows.
- **CC-05** → monitors parity not demonstrated ⇒ context-monitor.sh and tool-failure-monitor.sh stay, with this row as the recorded reason.
- **CC-06** → `claude plugin validate --strict` release gate baseline.
- **CC-07/CC-07b** → `.claude/skills/` expands via `/<skill>`; `.agents/skills/` is not a Claude path (the plugin path carries the shipped skills — KTD13 discovery matrix).
- **RTN-01** → headless watch delivery mode; runtime preflight absorbs all three outcomes.
- **SELF-01..SELF-04** → roster chain rejection, coordinate.sh composition, adapter env allowlist, the R35 boundary. **SELF-05** → the Status-line parser seam (KTD11: DONE / MISSING / BLOCKED). **SELF-06** → lease-lane skill discovery per CLI under the env -i boundary (KTD7/R9; PASS = the probe skill is listed, shipped coverage in the evidence). **SELF-07** → the TRIFORGE_TEST_BUILDER lifecycle: DONE → review, report missing → never review-ready, BLOCKED → escalated (KTD11). **SELF-08** → session-start idempotence (KTD7/KTD8).

## Appendix A: codex features list

```
apply_patch_freeform                     removed            false
apply_patch_preserve_line_endings        under development  false
apply_patch_streaming_events             under development  false
apps                                     stable             true
apps_mcp_path_override                   removed            false
artifact                                 under development  false
auth_elicitation                         stable             true
background_paginated_rollout_migration   under development  false
bedrock_setup_wizard                     under development  false
browser_use                              stable             true
browser_use_external                     stable             true
browser_use_full_cdp_access              stable             true
chronicle                                under development  false
code_mode                                under development  false
code_mode_buffered_exec                  removed            false
code_mode_host                           stable             true
code_mode_interrupt                      under development  false
code_mode_only                           under development  false
code_mode_prewarm                        under development  false
codex_git_commit                         removed            false
collaboration_modes                      removed            true
compaction_image_budget                  stable             true
computer_use                             stable             true
concurrent_reasoning_summaries           under development  false
content_item_kinds                       stable             true
context_management                       under development  false
current_time_reminder                    under development  false
cwd_relative_turn_diffs                  under development  false
default_mode_request_user_input          under development  false
deferred_executor                        under development  false
deferred_tool_world_state                under development  false
elevated_windows_sandbox                 removed            false
enable_fanout                            removed            false
enable_mcp_apps                          under development  false
enable_request_compression               stable             true
exec_permission_approvals                under development  false
executed_tool_call_metadata              under development  false
executor_capability_discovery            under development  false
experimental_windows_sandbox             removed            false
external_agent_memory_import             under development  false
external_migration                       removed            false
fast_mode                                stable             true
goals                                    stable             true
guardian_approval                        stable             true
guardian_enhanced_node_repl_transcripts  under development  false
guardian_ext                             under development  false
guardian_node_repl_transcript_images     under development  false
guardian_reuse_parent_compaction         under development  false
guardianv2                               under development  false
guardianv2.thread_context                under development  false
hooks                                    stable             true
image_detail_original                    removed            false
image_generation                         stable             true
image_resize_notice                      under development  false
in_app_browser                           stable             true
in_app_chat                              stable             true
in_app_dictation                         stable             true
in_app_local_automation                  stable             true
in_app_updates                           stable             true
item_ids                                 removed            true
js_repl                                  removed            false
js_repl_tools_only                       removed            false
local_thread_store_compression           under development  false
local_thread_store_shared_compression    removed            false
mcp_2026_07_28                           under development  false
mcp_oauth_refresh_coordination           under development  false
memories                                 stable             false
mentions_v2                              stable             true
multi_agent                              stable             true
multi_agent_mode                         removed            false
multi_agent_v2                           stable             false
network_proxy                            experimental       false
non_prefixed_mcp_tool_names              under development  false
omit_app_server_notification_media       under development  false
personality                              stable             true
plugin_hooks                             removed            false
plugin_sharing                           stable             true
plugins                                  stable             true
powershell_shell_version                 under development  false
prevent_idle_sleep                       experimental       false
psp                                      under development  false
realtime_conversation                    removed            false
reasoning_effort_override                under development  false
recommended_plugins                      stable             false
remote_compaction_v2                     stable             true
remote_control                           removed            false
remote_models                            removed            false
remote_plugin                            stable             true
request_permissions_tool                 under development  false
request_rule                             removed            false
resize_all_images                        removed            true
respect_system_proxy                     under development  false
responses_websockets                     removed            false
responses_websockets_v2                  removed            false
retain_client_developer_messages         under development  false
rollout_budget                           under development  false
runtime_metrics                          under development  false
search_tool                              removed            false
secret_auth_storage                      stable             false
send_async_message                       removed            false
shell_snapshot                           stable             true
shell_snapshot_v2                        under development  false
shell_tool                               stable             true
shell_zsh_fork                           under development  false
skill_env_var_dependency_prompt          removed            false
skill_mcp_dependency_install             stable             true
skill_search                             stable             true
skip_host_skill_discovery                under development  false
sleep_tool                               stable             true
sqlite                                   removed            true
standalone_web_search                    under development  false
steer                                    removed            true
step_model_switching                     under development  false
terminal_resize_reflow                   removed            true
terminal_visualization_instructions      under development  false
token_budget                             under development  false
tool_call_mcp_elicitation                stable             true
tool_search                              removed            false
tool_search_always_defer_mcp_tools       removed            true
tool_suggest                             stable             true
transcript_v2                            under development  false
tui_app_server                           removed            true
unavailable_dummy_tools                  removed            false
unbounded_connection_retries             stable             true
undo                                     removed            false
unified_exec                             stable             true
unified_exec_tty                         stable             true
unified_exec_zsh_fork                    removed            true
unified_image_budget                     under development  false
use_agent_identity                       under development  false
use_legacy_landlock                      deprecated         false
use_linux_sandbox_bwrap                  removed            false
view_image                               stable             true
web_search_cached                        deprecated         false
web_search_request                       deprecated         false
windows_sandbox_service                  under development  false
workspace_dependencies                   stable             true
workspace_owner_usage_nudge              removed            false
worktrees                                experimental       false
write_stdin_approval                     under development  false
```

## Appendix B: model lists

### agy models
```
Fetching available models...
gemini-3.8-flash-high	Gemini 3.8 Flash (High)
gemini-3.8-flash-medium	Gemini 3.8 Flash (Medium)
gemini-3.8-flash-low	Gemini 3.8 Flash (Low)
gemini-3.7-flash-high	Gemini 3.7 Flash (High)
gemini-3.7-flash-medium	Gemini 3.7 Flash (Medium)
gemini-3.7-flash-low	Gemini 3.7 Flash (Low)
gemini-3.6-flash-high	Gemini 3.6 Flash (High)
gemini-3.6-flash-medium	Gemini 3.6 Flash (Medium)
gemini-3.6-flash-low	Gemini 3.6 Flash (Low)
gemini-3.1-pro-high	Gemini 3.1 Pro (High)
gemini-3.1-pro-low	Gemini 3.1 Pro (Low)
claude-sonnet-4-6	Claude Sonnet 4.6 (Thinking)
claude-opus-4-6-thinking	Claude Opus 4.6 (Thinking)
gpt-oss-120b-medium	GPT-OSS 120B (Medium)
```

### agy agents
```
architecture-reviewer
codebase-analyst
documentation-writer
flutter_a11y_agent
targeted-researcher
```

### opencode models openrouter (GLM lines)
```
openrouter/~z-ai/glm-flash-latest
openrouter/~z-ai/glm-latest
openrouter/z-ai/glm-4.5
openrouter/z-ai/glm-4.5-air
openrouter/z-ai/glm-4.5v
openrouter/z-ai/glm-4.6
openrouter/z-ai/glm-4.6v
openrouter/z-ai/glm-4.7
openrouter/z-ai/glm-4.7-flash
openrouter/z-ai/glm-5
openrouter/z-ai/glm-5-turbo
openrouter/z-ai/glm-5.1
openrouter/z-ai/glm-5.2
openrouter/z-ai/glm-5.3
openrouter/z-ai/glm-5.3-flash
openrouter/z-ai/glm-5v-turbo
```

### cursor --list-models
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
cursor-grok-4.6-high-fast - Cursor Grok 4.6 Fast
composer-2.5 - Composer 2.5
claude-opus-5-thinking-high - Claude Opus 5 1M Thinking
claude-opus-5-thinking-high-fast - Claude Opus 5 1M Thinking Fast
gpt-5.6-sol-high - GPT-5.6 Sol 1M High
gpt-5.6-sol-high-fast - GPT-5.6 Sol 1M High Fast
gpt-5.6-sol-xhigh - GPT-5.6 Sol 1M Extra High
gpt-5.6-sol-xhigh-fast - GPT-5.6 Sol 1M Extra High Fast
claude-fable-5-thinking-high - Claude Fable 5 1M Thinking (NO ZDR)
claude-fable-5-thinking-xhigh - Claude Fable 5 1M Extra High Thinking (NO ZDR)
cursor-grok-4.5-high - Cursor Grok 4.5
cursor-grok-4.5-high-fast - Cursor Grok 4.5 Fast
gemini-3.7-flash-high - Gemini 3.7 Flash
claude-sonnet-5-thinking-high - Claude Sonnet 5 1M Thinking
claude-sonnet-5-thinking-xhigh - Claude Sonnet 5 1M Extra High Thinking
gpt-5.6-luna-high - GPT-5.6 Luna 1M High
cursor-grok-4.6-low - Cursor Grok 4.6 Low
cursor-grok-4.6-low-fast - Cursor Grok 4.6 Low Fast
cursor-grok-4.6-medium - Cursor Grok 4.6 Medium
cursor-grok-4.6-medium-fast - Cursor Grok 4.6 Medium Fast
cursor-grok-4.6-high - Cursor Grok 4.6
cursor-grok-4.6-xhigh - Cursor Grok 4.6 Extra High
cursor-grok-4.6-xhigh-fast - Cursor Grok 4.6 Extra High Fast
composer-2.5-fast - Composer 2.5 Fast
claude-opus-5-low - Claude Opus 5 1M Low
claude-opus-5-low-fast - Claude Opus 5 1M Low Fast
claude-opus-5-medium - Claude Opus 5 1M Medium
claude-opus-5-medium-fast - Claude Opus 5 1M Medium Fast
claude-opus-5-high - Claude Opus 5 1M
claude-opus-5-high-fast - Claude Opus 5 1M Fast
claude-opus-5-thinking-low - Claude Opus 5 1M Low Thinking
claude-opus-5-thinking-low-fast - Claude Opus 5 1M Low Thinking Fast
claude-opus-5-thinking-medium - Claude Opus 5 1M Medium Thinking
claude-opus-5-thinking-medium-fast - Claude Opus 5 1M Medium Thinking Fast
claude-opus-5-thinking-xhigh - Claude Opus 5 1M Extra High Thinking
claude-opus-5-thinking-xhigh-fast - Claude Opus 5 1M Extra High Thinking Fast
claude-opus-5-thinking-max - Claude Opus 5 1M Max Thinking
claude-opus-5-thinking-max-fast - Claude Opus 5 1M Max Thinking Fast
claude-opus-4-8-low - Claude Opus 4.8 1M Low
claude-opus-4-8-low-fast - Claude Opus 4.8 1M Low Fast
claude-opus-4-8-medium - Claude Opus 4.8 1M Medium
claude-opus-4-8-medium-fast - Claude Opus 4.8 1M Medium Fast
claude-opus-4-8-high - Claude Opus 4.8 1M
claude-opus-4-8-high-fast - Claude Opus 4.8 1M Fast
claude-opus-4-8-xhigh - Claude Opus 4.8 1M Extra High
claude-opus-4-8-xhigh-fast - Claude Opus 4.8 1M Extra High Fast
claude-opus-4-8-max - Claude Opus 4.8 1M Max
claude-opus-4-8-max-fast - Claude Opus 4.8 1M Max Fast
claude-opus-4-8-thinking-low - Claude Opus 4.8 1M Low Thinking
claude-opus-4-8-thinking-low-fast - Claude Opus 4.8 1M Low Thinking Fast
claude-opus-4-8-thinking-medium - Claude Opus 4.8 1M Medium Thinking
claude-opus-4-8-thinking-medium-fast - Claude Opus 4.8 1M Medium Thinking Fast
claude-opus-4-8-thinking-high - Claude Opus 4.8 1M Thinking
claude-opus-4-8-thinking-high-fast - Claude Opus 4.8 1M Thinking Fast
claude-opus-4-8-thinking-xhigh - Claude Opus 4.8 1M Extra High Thinking
claude-opus-4-8-thinking-xhigh-fast - Claude Opus 4.8 1M Extra High Thinking Fast
claude-opus-4-8-thinking-max - Claude Opus 4.8 1M Max Thinking
claude-opus-4-8-thinking-max-fast - Claude Opus 4.8 1M Max Thinking Fast
gpt-5.6-sol-none - GPT-5.6 Sol 1M None
gpt-5.6-sol-none-fast - GPT-5.6 Sol 1M None Fast
gpt-5.6-sol-low - GPT-5.6 Sol 1M Low
gpt-5.6-sol-low-fast - GPT-5.6 Sol 1M Low Fast
gpt-5.6-sol-medium - GPT-5.6 Sol 1M
gpt-5.6-sol-medium-fast - GPT-5.6 Sol 1M Fast
gpt-5.6-sol-max - GPT-5.6 Sol 1M Max
gpt-5.6-sol-max-fast - GPT-5.6 Sol 1M Max Fast
gpt-5.5-none - GPT-5.5 1M None
gpt-5.5-none-fast - GPT-5.5 None Fast
gpt-5.5-low - GPT-5.5 1M Low
gpt-5.5-low-fast - GPT-5.5 Low Fast
gpt-5.5-medium - GPT-5.5 1M
gpt-5.5-medium-fast - GPT-5.5 Fast
gpt-5.5-high - GPT-5.5 1M High
gpt-5.5-high-fast - GPT-5.5 High Fast
gpt-5.5-extra-high - GPT-5.5 1M Extra High
gpt-5.5-extra-high-fast - GPT-5.5 Extra High Fast
claude-fable-5-1-low - Claude Fable 5.1 1M Low (NO ZDR)
claude-fable-5-1-medium - Claude Fable 5.1 1M Medium (NO ZDR)
claude-fable-5-1-high - Claude Fable 5.1 1M (NO ZDR)
claude-fable-5-1-xhigh - Claude Fable 5.1 1M Extra High (NO ZDR)
claude-fable-5-1-max - Claude Fable 5.1 1M Max (NO ZDR)
claude-fable-5-1-thinking-low - Claude Fable 5.1 1M Low Thinking (NO ZDR)
claude-fable-5-1-thinking-medium - Claude Fable 5.1 1M Medium Thinking (NO ZDR)
claude-fable-5-1-thinking-high - Claude Fable 5.1 1M Thinking (NO ZDR)
claude-fable-5-1-thinking-xhigh - Claude Fable 5.1 1M Extra High Thinking (NO ZDR)
claude-fable-5-1-thinking-max - Claude Fable 5.1 1M Max Thinking (NO ZDR)
claude-fable-5-low - Claude Fable 5 1M Low (NO ZDR)
claude-fable-5-medium - Claude Fable 5 1M Medium (NO ZDR)
claude-fable-5-high - Claude Fable 5 1M (NO ZDR)
claude-fable-5-xhigh - Claude Fable 5 1M Extra High (NO ZDR)
claude-fable-5-max - Claude Fable 5 1M Max (NO ZDR)
claude-fable-5-thinking-low - Claude Fable 5 1M Low Thinking (NO ZDR)
claude-fable-5-thinking-medium - Claude Fable 5 1M Medium Thinking (NO ZDR)
claude-fable-5-thinking-max - Claude Fable 5 1M Max Thinking (NO ZDR)
cursor-grok-4.5-low - Cursor Grok 4.5 Low
cursor-grok-4.5-low-fast - Cursor Grok 4.5 Low Fast
cursor-grok-4.5-medium - Cursor Grok 4.5 Medium
cursor-grok-4.5-medium-fast - Cursor Grok 4.5 Medium Fast
gemini-3.8-flash-low - Gemini 3.8 Flash Low
gemini-3.8-flash-medium - Gemini 3.8 Flash Medium
gemini-3.8-flash-high - Gemini 3.8 Flash High
gemini-3.7-flash-low - Gemini 3.7 Flash Low
gemini-3.7-flash-medium - Gemini 3.7 Flash Medium
muse-spark-1.3-minimal - Muse Spark 1.3 1M Minimal
muse-spark-1.3-low - Muse Spark 1.3 1M Low
muse-spark-1.3-medium - Muse Spark 1.3 1M Medium
muse-spark-1.3-high - Muse Spark 1.3 1M
muse-spark-1.3-xhigh - Muse Spark 1.3 1M Extra High
muse-spark-1.3-max - Muse Spark 1.3 1M Max
gpt-5.6-terra-none - GPT-5.6 Terra 1M None
gpt-5.6-terra-none-fast - GPT-5.6 Terra 1M None Fast
gpt-5.6-terra-low - GPT-5.6 Terra 1M Low
gpt-5.6-terra-low-fast - GPT-5.6 Terra 1M Low Fast
gpt-5.6-terra-medium - GPT-5.6 Terra 1M
gpt-5.6-terra-medium-fast - GPT-5.6 Terra 1M Fast
gpt-5.6-terra-high - GPT-5.6 Terra 1M High
gpt-5.6-terra-high-fast - GPT-5.6 Terra 1M High Fast
gpt-5.6-terra-xhigh - GPT-5.6 Terra 1M Extra High
gpt-5.6-terra-xhigh-fast - GPT-5.6 Terra 1M Extra High Fast
gpt-5.6-terra-max - GPT-5.6 Terra 1M Max
gpt-5.6-terra-max-fast - GPT-5.6 Terra 1M Max Fast
claude-sonnet-5-low - Claude Sonnet 5 1M Low
claude-sonnet-5-medium - Claude Sonnet 5 1M Medium
claude-sonnet-5-high - Claude Sonnet 5 1M
claude-sonnet-5-xhigh - Claude Sonnet 5 1M Extra High
claude-sonnet-5-max - Claude Sonnet 5 1M Max
claude-sonnet-5-thinking-low - Claude Sonnet 5 1M Low Thinking
claude-sonnet-5-thinking-medium - Claude Sonnet 5 1M Medium Thinking
claude-sonnet-5-thinking-max - Claude Sonnet 5 1M Max Thinking
claude-4.6-sonnet-medium - Claude Sonnet 4.6 1M
claude-4.6-sonnet-medium-thinking - Claude Sonnet 4.6 1M Thinking
claude-opus-4-7-low - Claude Opus 4.7 1M Low
claude-opus-4-7-low-fast - Claude Opus 4.7 1M Low Fast
claude-opus-4-7-medium - Claude Opus 4.7 1M Medium
claude-opus-4-7-medium-fast - Claude Opus 4.7 1M Medium Fast
claude-opus-4-7-high - Claude Opus 4.7 1M High
claude-opus-4-7-high-fast - Claude Opus 4.7 1M High Fast
claude-opus-4-7-xhigh - Claude Opus 4.7 1M
claude-opus-4-7-xhigh-fast - Claude Opus 4.7 1M Fast
claude-opus-4-7-max - Claude Opus 4.7 1M Max
claude-opus-4-7-max-fast - Claude Opus 4.7 1M Max Fast
claude-opus-4-7-thinking-low - Claude Opus 4.7 1M Low Thinking
claude-opus-4-7-thinking-low-fast - Claude Opus 4.7 1M Low Thinking Fast
claude-opus-4-7-thinking-medium - Claude Opus 4.7 1M Medium Thinking
claude-opus-4-7-thinking-medium-fast - Claude Opus 4.7 1M Medium Thinking Fast
claude-opus-4-7-thinking-high - Claude Opus 4.7 1M High Thinking
claude-opus-4-7-thinking-high-fast - Claude Opus 4.7 1M High Thinking Fast
claude-opus-4-7-thinking-xhigh - Claude Opus 4.7 1M Thinking
claude-opus-4-7-thinking-xhigh-fast - Claude Opus 4.7 1M Thinking Fast
claude-opus-4-7-thinking-max - Claude Opus 4.7 1M Max Thinking
claude-opus-4-7-thinking-max-fast - Claude Opus 4.7 1M Max Thinking Fast
gpt-5.4-low - GPT-5.4 1M Low
gpt-5.4-medium - GPT-5.4 1M
gpt-5.4-medium-fast - GPT-5.4 Fast
gpt-5.4-high - GPT-5.4 1M High
gpt-5.4-high-fast - GPT-5.4 High Fast
gpt-5.4-xhigh - GPT-5.4 1M Extra High
gpt-5.4-xhigh-fast - GPT-5.4 Extra High Fast
claude-4.6-opus-high - Claude Opus 4.6 1M
claude-4.6-opus-max - Claude Opus 4.6 1M Max
claude-4.6-opus-high-thinking - Claude Opus 4.6 1M Thinking
claude-4.6-opus-max-thinking - Claude Opus 4.6 1M Max Thinking
claude-4.5-opus-high - Claude Opus 4.5
claude-4.5-opus-high-thinking - Claude Opus 4.5 Thinking
gpt-5.2-low - GPT-5.2 Low
gpt-5.2-low-fast - GPT-5.2 Low Fast
gpt-5.2-fast - GPT-5.2 Fast
gpt-5.2-high - GPT-5.2 High
gpt-5.2-high-fast - GPT-5.2 High Fast
gpt-5.2-xhigh - GPT-5.2 Extra High
gpt-5.2-xhigh-fast - GPT-5.2 Extra High Fast
gpt-5.6-luna-none - GPT-5.6 Luna 1M None
gpt-5.6-luna-none-fast - GPT-5.6 Luna 1M None Fast
gpt-5.6-luna-low - GPT-5.6 Luna 1M Low
gpt-5.6-luna-low-fast - GPT-5.6 Luna 1M Low Fast
gpt-5.6-luna-medium - GPT-5.6 Luna 1M
gpt-5.6-luna-medium-fast - GPT-5.6 Luna 1M Fast
gpt-5.6-luna-high-fast - GPT-5.6 Luna 1M High Fast
gpt-5.6-luna-xhigh - GPT-5.6 Luna 1M Extra High
gpt-5.6-luna-xhigh-fast - GPT-5.6 Luna 1M Extra High Fast
gpt-5.6-luna-max - GPT-5.6 Luna 1M Max
gpt-5.6-luna-max-fast - GPT-5.6 Luna 1M Max Fast
gemini-3.6-flash-minimal - Gemini 3.6 Flash Minimal
gemini-3.6-flash-low - Gemini 3.6 Flash Low
gemini-3.6-flash-medium - Gemini 3.6 Flash Medium
gemini-3.6-flash-high - Gemini 3.6 Flash
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
claude-4.5-sonnet - Claude Sonnet 4.5
claude-4.5-sonnet-thinking - Claude Sonnet 4.5 Thinking
gpt-5.1-low - GPT-5.1 Low
gpt-5.1 - GPT-5.1
gpt-5.1-high - GPT-5.1 High
gemini-3-flash - Gemini 3 Flash
gemini-3.5-flash - Gemini 3.5 Flash
claude-4-sonnet - Claude Sonnet 4
claude-4-sonnet-thinking - Claude Sonnet 4 Thinking
gpt-5-mini - GPT-5 Mini
kimi-k3-low - Kimi K3 Low
kimi-k3-high - Kimi K3 High
kimi-k3-max - Kimi K3
kimi-k2.7-code - Kimi K2.7 Code
glm-5.2-high - GLM 5.2
glm-5.2-max - GLM 5.2 Max

Tip: use --model <id> (or /model <id> in interactive mode) to switch. Parameterized models also accept quoted overrides, e.g. --model 'claude-opus-4-8[context=1m,effort=high,fast=false]'.
```

## Appendix C: six-harness skills/commands discovery fixture (2026-09-11, run after U11 — the twelve edited skills copied into `.agents/skills/` plus one marker skill per candidate path)

Method: throwaway git fixture (`scratchpad/harness-test-v2.sh`), each CLI asked headless in its own invocation form; `shipped-listed` counts the shipped skill names the model echoed back (a model-mediated listing — truncation lowers it; the SKILL-OK / CMD-OK markers are the discovery proof). Kimi is AUTH-FAIL on this host (`kimi login` pending, KIMI-05).

| Label | Command | rc | shipped names echoed | markers |
|---|---|---|---|---|
| claude-list | `claude -p List the names of every skill available to you. Output only the names, one per line, nothing else. Do not invoke any skill or tool. --out…` | 0 | 0/12 | — |
| claude-cmd | `claude -p /tf-cmd-claude --output-format text` | 0 | 0/12 | CMD-OK tf-cmd-claude |
| claude-skill | `claude -p /tf-claude-skill --output-format text` | 0 | 0/12 | SKILL-OK tf-claude-skill |
| agy-skills | `agy --add-dir /private/tmp/claude-501/-Users-dbenger-projects-multi-agent-framework/df3db517-1ae7-4d88-b60c-2bd966707827/scratchpad/harness-fixture…` | 0 | 12/12 | — |
| agy-list | `agy --add-dir /private/tmp/claude-501/-Users-dbenger-projects-multi-agent-framework/df3db517-1ae7-4d88-b60c-2bd966707827/scratchpad/harness-fixture…` | 0 | 12/12 | — |
| agy-skill | `agy --add-dir /private/tmp/claude-501/-Users-dbenger-projects-multi-agent-framework/df3db517-1ae7-4d88-b60c-2bd966707827/scratchpad/harness-fixture…` | 0 | 0/12 | SKILL-OK tf-agents-skill |
| agy-shipped-skill | `agy --add-dir /private/tmp/claude-501/-Users-dbenger-projects-multi-agent-framework/df3db517-1ae7-4d88-b60c-2bd966707827/scratchpad/harness-fixture…` | 0 | 0/12 | — |
| codex-list | `codex exec --skip-git-repo-check -s read-only -c approval_policy="never" -m gpt-6-astra -c model_reasoning_effort="low" List the names of every ski…` | 0 | 12/12 | — |
| codex-skill | `codex exec --skip-git-repo-check -s read-only -c approval_policy="never" -m gpt-6-astra -c model_reasoning_effort="low" Use $tf-agents-skill now an…` | 0 | 0/12 | SKILL-OK tf-agents-skill |
| codex-shipped-skill | `codex exec --skip-git-repo-check -s read-only -c approval_policy="never" -m gpt-6-astra -c model_reasoning_effort="low" Use $verification-before-co…` | 0 | 1/12 | — |
| opencode-list | `opencode run --format json -m openrouter/z-ai/glm-5.3 List the names of every skill available to you. Output only the names, one per line, nothing …` | 0 | 12/12 | — |
| opencode-skill | `opencode run --format json -m openrouter/z-ai/glm-5.3 /tf-agents-skill` | 0 | 0/12 | SKILL-OK tf-agents-skill |
| opencode-cmd | `opencode run --format json -m openrouter/z-ai/glm-5.3 --command tf-cmd-opencode` | 0 | 0/12 | CMD-OK tf-cmd-opencode |
| cursor-list | `cursor-agent -p --trust --output-format text --model cursor-grok-4.6-low List the names of every skill available to you. Output only the names, one…` | 0 | 4/12 | — |
| cursor-skill | `cursor-agent -p --trust --output-format text --model cursor-grok-4.6-low /tf-cursor-skill` | 0 | 0/12 | SKILL-OK tf-cursor-skill |
| cursor-agents-skill | `cursor-agent -p --trust --output-format text --model cursor-grok-4.6-low /tf-agents-skill` | 0 | 0/12 | SKILL-OK tf-agents-skill |
| cursor-cmd | `cursor-agent -p --trust --output-format text --model cursor-grok-4.6-low /tf-cmd-cursor` | 0 | 0/12 | CMD-OK tf-cmd-cursor |
| kimi-list | `kimi -p List the names of every skill available to you. Output only the names, one per line, nothing else. Do not invoke any skill or tool. --outpu…` | 1 | 0/12 | — |
| kimi-skill | `kimi -p /skill:tf-agents-skill --output-format text` | 1 | 0/12 | — |

Reading: agy (`/skills`, `/<skill>` with `--add-dir`), Codex (`$<skill>`, listing), OpenCode (`/<skill>` → native `skill` tool, `--command`) and Cursor (`/<skill>` in `-p`, `/<command>`) all discover the `.agents/skills/` copy — Cursor's echoed list is truncated by the model (its user-tier `~/.cursor/skills` entries fill the list first) while both SKILL-OK markers prove expansion; agy's `/verification-before-completion` expansion hit the headless command auto-deny (the skill asks to run commands — the denial itself shows the skill loaded); Codex printed the shipped skill's first heading. Claude Code reads `.claude/skills` + `.claude/commands` (CMD-OK, SKILL-OK) and the plugin path — the twelve shipped names are absent from the Claude listing on this host because the plugin is not installed via `claude plugin add` here (dev checkout, `~/.claude/plugins/installed_plugins.json` carries no agent-triforge entry); SELF-06f in the table above measures the same condition from a lease worktree. Kimi rows are PENDING-AUTH (`/skill:<name>` per the docs).

## Appendix D: Claude Code plugin-path discovery via the marketplace install route (2026-09-12, after the review fixes)

SELF-06f runs from a lease worktree on the dev checkout, where the plugin is not installed, so it cannot see the plugin path. The plugin-path half of R9 was verified by installing the checkout into a throwaway project the way a user installs it on Claude Code 2.1.269 (the documented `claude plugin add <url>` form is not a command any more — `error: unknown command 'add'`; installs go through a marketplace, and `claude plugin marketplace add <bare plugin repo>` fails with "Marketplace file not found" unless the repo ships `.claude-plugin/marketplace.json`, which it now does):

| Step | Command (throwaway project, `--scope project`) | Result |
|---|---|---|
| 1 | `claude plugin marketplace add <checkout path> --scope project` | added (declared in project settings) |
| 2 | `claude plugin install agent-triforge@agent-triforge --scope project -y` (with `plugin.json` still naming `hooks/hooks.json`) | installed, **Status: failed to load** — `Hook load failed: Duplicate hooks file detected: ./hooks/hooks.json resolves to already-loaded file … The standard hooks/hooks.json is loaded automatically, so manifest.hooks should only reference additional hook files.` |
| 3 | same, after removing the `hooks` key from `plugin.json` | installed, **Status: enabled**, no errors |
| 4 | `env -i HOME PATH TMPDIR TERM LANG USER NO_COLOR=1 claude -p --model sonnet "<list the twelve shipped skill names>"` | **12/12** shipped names listed (plugin path; `.agents/skills/` is not a Claude path) |
| 5 | `claude -p --model sonnet "/scope-cutting — reply with the first H1"` | `# Scope Cutting` — the plugin skill expanded |
| 6 | session-start hook in the installed project | fired: `.agents/skills/` provisioned (12 dirs), `ops/` bootstrapped |

Consumption: R9 (Claude Code column of the six-harness matrix), the README / CLAUDE.md / landing-page install lines, and the `plugin.json` manifest fix in v3.3.0. The GitHub-URL form of step 1 resolves the repository's default branch, so it works once this branch is on `main`.
