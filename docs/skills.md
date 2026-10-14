[← Agent Triforge](../README.md#documentation)

# Skills reference

The plugin ships 27 skills in one `skills/` tree: the 10 portable skills below, which any agent can use (`wave-orchestration` also needs the plugin's lease helpers), and the 17 lead workflows [listed on the Workflow page](workflows.md#lead-workflows-reference), which only the lead runs. The portable skills are embedded in the native Antigravity and Codex agent definitions (`antigravity-agents/agents/`, `codex-agents/`) at install time. When a CLI doesn't surface native agent definitions, the helper injects the agent body as a prompt prefix instead.

| Skill | Primary consumer | What it teaches the agent |
|---|---|---|
| [`codebase-mapping`](../skills/codebase-mapping/SKILL.md) | [Antigravity](https://antigravity.google/cli) (Phase 0) | Full-repo analysis: structure, data flow, patterns, debt |
| [`writing-plans`](../skills/writing-plans/SKILL.md) | Lead (Phase 1) | Task decomposition with shadow paths, error maps, interface context |
| [`shadow-path-tracing`](../skills/shadow-path-tracing/SKILL.md) | Lead (Phase 1) | Enumerate every failure path alongside the happy path |
| [`wave-orchestration`](../skills/wave-orchestration/SKILL.md) | Lead (Phase 2) | Dependency-grouped parallel execution with integration checks |
| [`iterative-refinement`](../skills/iterative-refinement/SKILL.md) | Lead (Phase 4) | Review-fix-review loops with convergence modes |
| [`review-synthesis`](../skills/review-synthesis/SKILL.md) | Lead (Phase 4) | Merge multi-reviewer findings with confidence tiering |
| [`verification-before-completion`](../skills/verification-before-completion/SKILL.md) | All agents | Evidence-based completion checklist |
| [`knowledge-compounding`](../skills/knowledge-compounding/SKILL.md) | Lead (Phase 6) | Document solutions to [`ops/solutions/`](../ops/solutions/) for future sprints |
| [`session-continuity`](../skills/session-continuity/SKILL.md) | Lead | Save and resume via [`STATE.md`](../ops/STATE.md) across sessions |
| [`scope-cutting`](../skills/scope-cutting/SKILL.md) | Lead | Systematically cut scope by unblocking value and risk |

## Portable skills across the eight CLIs

The project bootstrap (`triforge_bootstrap`, run at session start and by `at-setup`, `at-build` and `at-review`) copies the 10 portable skills from the plugin's `skills/` into `.agents/skills/`, the agentskills.io path, and refreshes the copy whenever the plugin version changes. The stamp `.agents/skills/.triforge-plugin-version` records a content digest for each directory Triforge wrote, and only Triforge's own unchanged copies are replaced or retired. An edited copy, or your own directory under a shipped name, is kept with a notice; customizations are safest in a directory with a different name. Fixture evidence from the 2026-09-11 watch cycle ([`ops/research/2026-09-11-cli-updates.md`](../ops/research/2026-09-11-cli-updates.md) §3.1) shows which path each CLI reads:

| Path | Claude Code | agy | Codex | OpenCode | Cursor | Kimi (docs) |
|---|---|---|---|---|---|---|
| `.agents/skills/` (Triforge's copy) | ✗ | ✓ (workspace bound via `--add-dir` or trust) | ✓ | ✓ | ✓ | ✓ |
| `.claude/skills/` | ✓ | ✗ | ✗ | ✓ | ✓ | ✗ |
| `.codex/skills/` | ✗ | ✗ | ✓ | ✗ | ✓ | ✗ |
| `.opencode/skill(s)/` | ✗ | ✗ | ✗ | ✓ | ✗ | ✗ |
| `.cursor/skills/` | ✗ | ✗ | ✗ | ✗ | ✓ | ✗ |
| `.kimi-code/skills/` | ✗ | ✗ | ✗ | ✗ | ✗ | ✓ |

Claude Code is the one CLI that does not read `.agents/skills/`; it reads the plugin's skills directly. Grok Build reads `.agents/skills/` too, and a Grok Build worker gets this copy in its lease worktree (SELF-06g). Devin (`devin skills paths`), which Triforge can also enroll as a worker, and Pi (per its skills docs) read `.agents/skills/` as well, so inside a Triforge project they see this copy; a Devin worker gets it in its lease worktree like the others (SELF-06h). Elsewhere they install the skills [from their own manifests](installation.md#portable-skills-in-devin-and-pi).

Each harness invokes a skill in its own form: Claude `/name` · agy `agy --add-dir "$PWD" -p "/name"` (headless expansion; `agy -p "/skills"` lists them without a model call) · Codex `$name` · OpenCode `/name` through its native `skill` tool (commands via `opencode run --command <name>` from `.opencode/command/`) · Cursor `/name` in `-p` · Kimi `/skill:name` (live verification pending `kimi login`).

The 17 lead workflows (`skills/at-*/`) are not in this copy. A lead gets them only from its plugin install (KTD12) and runs them as `/at-<name>` under Claude Code or `$agent-triforge:at-<name>` in a Codex prompt. They are skills rather than slash commands because slash commands are per-harness: Codex custom prompts are deprecated and not expanded under `codex exec`. Agent definitions are never deployed into `.agents/agents/`, because agy and Kimi both scan it with incompatible tool vocabularies; agy stays on `agy plugin install`, and Kimi loads its definitions through `--agent-file`.
