# Grounding dossier — Triforge external-CLI integration refresh

Repo: /Users/dbenger/projects/multi-agent-framework. Extraction only — verbatim quotes + file:line pointers, no interpretation.

## 1. Gemini blast radius

**File count:** 43 files mention "gemini" case-insensitively outside `ops/` (`grep -ril "gemini" --include="*.md,*.sh,*.toml,*.json" . | grep -v '^./ops/'`); 50 including `ops/` runtime-state files.

Load-bearing files:
- `scripts/invoke-external.sh:26-98` — `invoke_gemini()`. Three modes: native (`.gemini/agents/${AGENT_NAME}.md` exists → `FULL_PROMPT="@${AGENT_NAME} ${PROMPT}"`), `legacy-injection` (extracts plugin template body via `awk`, prefixes prompt), `raw` (warns, no system prompt). Policy file resolution at :35-40 (`.gemini/policies.toml` then plugin fallback). Retry-once-with-raw-prompt on nonzero exit at :86-95. No `-y`/`--yolo` by design (:72-77 comment: "YOLO installs a max-priority allow rule that overrides every policies.toml deny").
- `hooks/handlers/session-start.sh:30-44` — bootstraps `.gemini/agents/*.md` (copy-if-absent from `gemini-agents/`), `.gemini/policies.toml`, `.gemini/settings.json`. `:46-52` — copies `skills/` → `.agents/skills/` ("Gemini v0.36.0+ auto-discovers SKILL.md files here"). `:54-67` — G12 guard warns if `~/.gemini/settings.json` has `experimental.enableAgents=false`.
- `gemini-agents/codebase-analyst.md:1-8` frontmatter: `tools: [read_file, write_file, grep_search, glob, list_directory, run_shell_command]`, `model: gemini-3.1-pro-preview`, `max_turns: 50`, `timeout_mins: 10`. Same shape in `architecture-reviewer.md`, `targeted-researcher.md`, `documentation-writer.md` (all `model: gemini-3.1-pro-preview`).
- `gemini-agents/policies.toml` (65 lines) — universal denies (`rm -rf`, `git push`, `sudo` at priority 999) + per-subagent shell denial for `architecture-reviewer`/`documentation-writer`. Header notes schema quirk: "`pathGlob` / `pathPrefix` do NOT exist — file-path scoping must come from tool-list restrictions."
- Commands with live `invoke_gemini` calls: `commands/coordinate.md:39`, `commands/build.md:63`, `commands/plan.md:40`, `commands/deep-research.md:34`, `commands/ship.md:55`, `commands/review.md:36` (all background-bash, `${TMPDIR:-/tmp}/gemini_*_$$_$(date +%s).txt` output paths).
- `templates/.gemini/settings.json` — disables built-in `codebase_investigator` ("We use our own gemini-agents/codebase-analyst.md ... Disabling the built-in avoids routing ambiguity").
- `templates/.gemini/hooks.example.json` — opt-in `AfterTool` hook on `write_file` appending to `ops/CHANGELOG.md`; `"_verified_on": "Gemini CLI v0.41.2 (2026-05-12)"`.
- ops/ convention (`CLAUDE.md` table): `REVIEW_GEMINI.md` "Gemini writes, Claude reads"; `RESEARCH_GEMINI.md` "Gemini writes, Claude reads" — both temporary, not present in repo listing (created transiently).
- `docs/agent-triforge.md:282-284` — "Subagents cannot call other subagents... Our architecture complies because Claude (the lead) is the only agent that spawns Gemini subagents." `:286-291` — explicitly rejects native `gemini skills install` / `gemini hooks migrate` in favor of portable `skills/`.

## 2. Codex integration surface

- `scripts/invoke-external.sh:111-188` — `invoke_codex()`. No native subagent CLI flag ("Codex has no CLI flag to pick a subagent... So we simulate it"). Looks up `.codex/agents/agents.toml` then plugin `codex-agents/agents.toml`, extracts config via `_extract_codex_agent_config` (:223), builds `CMD=(codex exec)` with `-m "$AGENT_MODEL"`, `-s` (default `workspace-write`), `-c approval_policy=...` (default `"never"`). `:147-149` comment: "Codex v0.128.0 removed `--full-auto`; supply its prior semantics ... explicitly." Same retry-once pattern as Gemini (:176-185).
- `codex-agents/agents.toml:1-25` — top-level `[agents]` caps: `max_depth = 2`, `max_threads = 4`, `job_max_runtime_seconds = 1800` (comment: "logic_reviewer and test_writer spawn sub-agents for 5+ file scopes... max_depth = 2 raises the cap by exactly one level"). Per-agent: `model = "gpt-5.4"`, `model_reasoning_effort = "xhigh"`, `sandbox_mode`, `approval_policy = "never"`, `tools = [...]`, `include_plan_tool = false`, `developer_instructions = """..."""` (confirmed identical model/effort at lines 20-21, 99-100, 180-181 for `logic_reviewer`, `test_writer`, `debugger`).
- `templates/.codex/config.toml` (12 lines) — `[memories] use_memories = false` / `generate_memories = false` ("Codex v0.129.0 added an auto-memory pipeline... Triforge maintains its own ops/MEMORY.md... disable Codex's parallel system to avoid divergence").
- `hooks/handlers/session-start.sh:77-94` — bootstraps `.codex/agents/agents.toml`, `.codex/AGENTS.md`, `.codex/config.toml` (all copy-if-absent).

## 3. Hardcoded CLI names, versions, model IDs

- Model IDs: `gemini-3.1-pro-preview` (4x in `gemini-agents/*.md`), `gpt-5.4` (3x in `codex-agents/agents.toml`), `model: opus` (all 19 files in `agents/*.md`).
- `CLAUDE.md:85`: "Gemini (`gemini-agents/*.md`) uses `max_turns`/`timeout_mins` plus `gemini-3.1-pro-preview`-style model IDs... Codex (`codex-agents/agents.toml`) uses `model_reasoning_effort`, `sandbox_mode`, `approval_policy`, and `include_plan_tool`."
- Version floors (`CLAUDE.md` Compatibility section, mirrored in `ops/decisions/2026-05-12-cli-deprecation-watch.md` D-008): "**Codex ≥ 0.128.0** — first version after `--full-auto` was removed"; "**Gemini ≥ 0.39.0** — first version after legacy subagent wrappers were retired and `invoke_subagent` was unified." Tested-against line: "Tested against **Codex 0.130.0** and **Gemini 0.41.2** (2026-05-12)."
- `README.md:301-317` Prerequisites section — same three READY-probe commands as `CLAUDE.md:250-251`, `docs/agent-triforge.md:1157-1158`, `templates/CLAUDE.md` (4 total locations).
- `.claude-plugin/plugin.json` — `"version": "2.4.3"`, `"keywords": [..., "gemini", "codex", ...]`.

## 4. Seams for adding a new CLI

- `scripts/invoke-external.sh` structure to mirror for `invoke_opencode`/`invoke_cursor`: agent-file lookup (native vs. legacy-injection vs. raw) → policy/permission resolution → `_run_with_timeout` wrapper → retry-once-on-failure → helper functions `_list_gemini_agents` (:249) / `_list_codex_agents` (:264) for the "available agents" warning message.
- `hooks/handlers/session-start.sh` per-CLI bootstrap pattern (repeated 2x, would become 3x+): `mkdir -p .<cli>/agents` → copy-if-absent agent defs → copy-if-absent settings/config → optional `.agents/skills/` interop (currently Gemini-only, :46-52).
- `commands/review.md:26-58` — the parallel-fan-out template: background `invoke_gemini` + `invoke_codex` with per-PID `wait`, explicit `GEMINI_RC`/`CODEX_RC` capture ("a silent failure in either helper leaves the downstream ops/REVIEW_*.md ... empty and looks like 'no findings'"), then Phase 4 (:70-81) spawns `findings-synthesizer` which "reads ops/REVIEW_GEMINI.md, ops/REVIEW_CODEX.md, and subagent outputs."
- `commands/deep-research.md:15-49` — 5-agent swarm pattern (3 Claude subagents + 1 `invoke_gemini` targeted-researcher + 1 more Claude agent), all launched "in a SINGLE message for maximum parallelism," then `research-synthesizer` merges.

## 5. Claude-side model/effort conventions

- `agents/*.md` frontmatter: `model: opus` (verified in 15+ files by grep, e.g. `agents/security-sentinel.md:9`, `agents/team-lead.md:10`).
- `agents/team-lead.md:143-155` "Model routing discretion" — downgrade ladder table: Tier 1 `opus`+`xhigh` ("preferred first step"), Tier 2 `opus`+`high`, Tier 3 `sonnet`+`high` ("only when Opus/high still feels overkill"). "Never downgrade security-sentinel, plan-checker, or findings-synthesizer." Same table duplicated in `skills/wave-orchestration/SKILL.md:130-132` and `CLAUDE.md`.
- `settings.json` (repo root, 5 lines): `{"env": {"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"}}`.

## 6. Prior-art process (template for a new cycle)

`ops/research/cli-updates-2026-05.md` (322 lines) shape: `1. Executive summary` (10 numbered findings, each tagged BREAKING/stable/adoption-candidate with PR links) → `2. Per-CLI changelog` (`### Gemini CLI`, `### Codex CLI`) → `3. Gap analysis vs current Triforge` → `4. Top 5 prioritized adoption candidates` (each: **Why** / **Concrete change** with file:line targets / **Verification** step) → `5. Risks` → `6. Sources appendix`. Header states scope discipline: "Filtered to features relevant to Triforge... UI/voice/browser/telemetry-only changes omitted."

`ops/decisions/2026-05-12-cli-deprecation-watch.md` (77 lines) shape: `Context` → `Decisions` (D-001..D-008, each **ADOPT**/**DEFER**/**DOCUMENT** verdict with affected files) → `Verification record` (table: Probe / Outcome / Date / Method) → `Open watches` (table: Risk / Source / Trigger to revisit) → `References`. Sample verdict language: "D-004... **DEFER (upstream gap)**... Hooks appear to be TUI-only at this version." "D-006... **DEFER**... This is an architectural change outside this audit's scope."

No dedicated `/deep-research`-style command produced these two files — `commands/deep-research.md` exists but targets feature research (5-agent swarm), not CLI-changelog audits; the two `ops/research`/`ops/decisions` files appear to be a manual/ad-hoc research cycle.
