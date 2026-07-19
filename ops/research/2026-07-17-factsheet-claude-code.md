# Claude Code fact sheet — verified July 17, 2026

Official sources only (code.claude.com/docs, platform.claude.com/docs, raw CHANGELOG.md anthropics/claude-code v2.1.139–2.1.212). All items VERIFIED by cc-docs-researcher.

## 1. /goal — EXISTS
Sets a completion condition; after each turn a small fast model (default Haiku) judges whether it's met — if not, Claude keeps working without re-prompting. Session-scoped, restorable on `--resume`, works in `-p`/headless/Remote Control. Requires v2.1.139+.
https://code.claude.com/docs/en/goal
Triforge relevance: ship-loop.sh's `<promise>DONE</promise>` Stop-hook gate is a hand-rolled /goal.

## 2. /workflows + Workflow tool + ultracode — EXISTS
Dynamic workflow = JS orchestration script executed by a background runtime (up to 16 concurrent / 1,000 total agents per run). `/workflows` lists/monitors runs. Trigger: `ultracode` prompt keyword (renamed from `workflow` at v2.1.160), natural language, or session-wide `/effort ultracode` (xhigh + auto workflow planning, v2.1.203+). Bundled `/deep-research` workflow. Requires v2.1.154+.
https://code.claude.com/docs/en/workflows
Triforge relevance: overlaps wave-orchestration skill.

## 3. Loops/scheduling — three tiers; /schedule semantics CHANGED
- `/loop`: local, session-scoped, fixed or self-paced interval (min 1m, 7-day expiry, CronCreate/CronList/CronDelete, max 50/session).
- `/schedule`: NOW creates cloud "Routines" — Anthropic-managed, session-independent, min 1h interval, API + GitHub-event triggers (research preview).
- Desktop scheduled tasks: separate third local option.
https://code.claude.com/docs/en/scheduled-tasks · /routines

## 4. Agent teams — still experimental, env var unchanged
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` still exact name, opt-in. v2.1.178: TeamCreate/TeamDelete tools REMOVED — one implicit team per session; spawn teammates via Agent tool `name` param; `team_name` deprecated/ignored. Limits unchanged: no session-resume for in-process teammates, one team/session, no nested teams.
https://code.claude.com/docs/en/agent-teams

## 5. Model lineup (IDs verified)
| Model | API ID | Alias | Notes |
|---|---|---|---|
| Claude Fable 5 | claude-fable-5 | fable | Mythos-class, GA June 9 2026, never default — select explicitly |
| Claude Mythos 5 | claude-mythos-5 | — | invitation-only (Project Glasswing), NOT GA |
| Claude Mythos Preview | claude-mythos-preview | — | invitation-only |
| Claude Opus 4.8 | claude-opus-4-8 | opus | complex agentic coding |
| Claude Sonnet 5 | claude-sonnet-5 | sonnet | GA ~June 30 2026, native 1M context (no 200k variant), default for Pro/Team-Standard/Enterprise |
| Claude Haiku 4.5 | claude-haiku-4-5-20251001 | haiku-4-5 / haiku | unchanged |
Bedrock IDs drop dates/-v1 from 4.6 gen (anthropic.claude-fable-5). Alias resolution varies by provider (Bedrock `sonnet` still = 4.5). Frontmatter `model:` accepts sonnet|opus|haiku|fable, full ID, or inherit.
https://platform.claude.com/docs/en/about-claude/models/overview · /model-ids-and-versions
Strategic note: Sonnet 5's native 1M context erodes Gemini's founding differentiator (Phase 0 full-repo analysis).

## 6. Effort levels / /effort / /fast
Levels: low, medium, high, xhigh, max (API-level). Fable 5, Sonnet 5, Opus 4.8, Opus 4.7 support all five; Opus 4.6/Sonnet 4.6 lack xhigh. low–xhigh persist across sessions; max is session-only. `ultracode` = Claude-Code-only /effort menu setting (sends xhigh + standing workflow permission), session-only, NOT an API effort level. /fast = research-preview Opus-only speed mode (~2.5x faster, higher $/Mtok), Opus 4.8/4.7 only — Opus 4.7 fast deprecated June 25 2026, removed July 24 2026.
https://platform.claude.com/docs/en/build-with-claude/effort · code.claude.com/docs/en/model-config · /fast-mode

## 7. Subagent frontmatter fields (current full list)
Required: name, description. Optional: tools, disallowedTools, model, permissionMode, maxTurns, skills, mcpServers, hooks, memory, background, effort, isolation, color, initialPrompt (NEW — auto-submitted first turn when agent runs as main session via --agent).
Plugin-shipped agents do NOT support hooks, mcpServers, permissionMode (security restriction). isolation only accepts "worktree".
https://code.claude.com/docs/en/sub-agents
Triforge doc drift: CLAUDE.md lists permissionMode/hooks/mcpServers as available; missing initialPrompt.

## 8. Plugin-system changes (May–July 2026)
- defaultEnabled: false (v2.1.154+) — install disabled.
- displayName (v2.1.143+).
- Experimental components: monitors (background shell watchers → notifications), themes (JSON), channels (bind plugin MCP server to inject external messages into sessions — e.g. CI failures).
- Unrecognized top-level plugin.json fields tolerated (warn, not error); `claude plugin validate --strict` for CI.
- SECURITY (v2.1.207+): ${user_config.*} no longer substitutes into shell-form hook commands / monitor commands / MCP headersHelper — use exec-form args or CLAUDE_PLUGIN_OPTION_<KEY> env var.
- LSP servers: restartOnCrash/shutdownTimeout (v2.1.205+).
- ${CLAUDE_PLUGIN_DATA} persistent-data dir (survives updates).
- Skills-directory plugins (claude plugin init → <name>@skills-dir, no marketplace step).
- No breaking changes to Triforge's existing ${CLAUDE_PLUGIN_ROOT}/hooks.json mechanics found.
https://code.claude.com/docs/en/plugins-reference

## 9. Other adoptable features
- Nested subagents (v2.1.172+), fixed depth-5 limit.
- Subagents background-by-default (v2.1.198+); Explore inherits session model (capped at Opus).
- Subagent output scanning for prompt-injection-shaped text (v2.1.210+).
- isolation: worktree per subagent, auto-cleaned.
- Session safety caps (v2.1.212): WebSearch 200/session, subagent spawns 200/session, env-tunable; MCP calls >2min auto-background.
- Auto mode (background permission classifier); Channels (external event injection).
- /fork (v2.1.212) → background session instead of in-session subagent.
