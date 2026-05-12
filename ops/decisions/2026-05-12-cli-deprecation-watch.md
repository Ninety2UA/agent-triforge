# ADR: CLI deprecation watch — Gemini & Codex updates 2026-03-12 → 2026-05-12

**Date:** 2026-05-12
**Status:** Accepted (Triforge v2.4.1 forthcoming)
**Tested against:** Codex 0.130.0, Gemini 0.41.2

## Context

Gap-analysis report at `ops/research/cli-updates-2026-05.md` audited 21 Gemini stable releases + 14 Codex stable releases over the last 60 days. Several upstream changes broke or threatened to break Triforge's invocation layer; others offered no-cost adoption wins. This ADR records the decisions taken on each.

## Decisions

### D-001. Replace removed `--full-auto` flag — **ADOPT**

Codex v0.128.0 removed `--full-auto`. `scripts/invoke-external.sh:147-155` previously passed it as a fallback when no agent overrides were set; under Codex 0.130.0 this would error. Now the helper passes the prior semantics explicitly: `-s workspace-write` + `-c approval_policy="never"`. Affects: `scripts/invoke-external.sh`.

### D-002. Disable Codex auto-memory by default — **ADOPT**

Codex v0.129.0 introduced a two-phase auto-memory pipeline that writes `~/.codex/memories/{MEMORY.md, raw_memories.md, rollout_summaries/, skills/}`. Triforge maintains its own `ops/MEMORY.md` and `ops/solutions/`; running both creates two parallel sources of truth that drift. Triforge now ships `templates/.codex/config.toml` with `[memories] use_memories = false` and `generate_memories = false`. Users who want Codex memories can remove the block or override in `~/.codex/config.toml`. Affects: `templates/.codex/config.toml` (new), `hooks/handlers/session-start.sh`.

### D-003. Wire `.agents/skills/` interop path — **ADOPT**

Gemini v0.36.0+ recognizes `.agents/skills/` as a workspace skills tier per the open `agentskills.io` standard. `hooks/handlers/session-start.sh` now copies `${CLAUDE_PLUGIN_ROOT}/skills/` to `.agents/skills/` on first session start (copy, not symlink — some loaders refuse symlinks across filesystem boundaries). Gemini agents can `activate_skill <name>` instead of requiring per-prompt `$(cat ...)` injection. Affects: `hooks/handlers/session-start.sh`.

### D-004. Codex hooks under `codex exec` — **DEFER (upstream gap)**

Hypothesis: ship `templates/.codex/hooks.json` to enforce `ops/CHANGELOG.md` updates via `PostToolUse` hooks. Verification on 2026-05-12 with `codex 0.130.0` against multiple hook events (`SessionStart`, `Stop`, `UserPromptSubmit`, `PreToolUse`) showed **none fire under `codex exec`** despite `CodexHooks` being in the active feature list and the workspace being trusted (`~/.codex/config.toml` had `[projects."/Users/dbenger"] trust_level = "trusted"`). Both inline `[hooks.X]` TOML in `config.toml` and `hooks.json` JSON file forms were tested; both ignored. Hooks appear to be TUI-only at this version. **Defer until upstream extends hooks to `codex exec`.** No changes shipped for this candidate.

### D-005. Gemini hooks under `gemini -p` — **ADOPT (opt-in)**

Verification on 2026-05-12 with `gemini 0.41.2` confirmed `SessionStart`, `BeforeAgent`, `AfterAgent`, `AfterTool` all fire under `gemini -p`. Shipped as `templates/.gemini/hooks.example.json` with an `AfterTool` matcher on `write_file` that appends to `ops/CHANGELOG.md`. **Not auto-copied** because Gemini emits a per-session "project hooks detected" trust warning that adds friction; users who want enforcement merge the `hooks` block into their `.gemini/settings.json` manually. Affects: `templates/.gemini/hooks.example.json` (new).

### D-006. Externalize Codex agents (`agents.<name>.config_file`) — **DEFER**

The report flagged Codex's `agents.<name>.config_file` schema as cleaner than Triforge's 242-line inline `codex-agents/agents.toml`. On inspection: Triforge does not use Codex's official `[agents]` schema at all — it ships `.codex/agents/agents.toml` as a Triforge-internal config that the helper script parses via Python and then invokes `codex exec` with `-m`/`-s`/`-c` overrides. Codex CLI itself never sees `developer_instructions`. So `config_file` externalization would require migrating to Codex's official agent system (which uses `spawn_agent` from inside a session, not the helper). This is an architectural change outside this audit's scope.

### D-007. `permission_profile = ":read-only"` in `[agents.<name>]` — **DEFER**

Only meaningful if D-006 is adopted (Codex doesn't read Triforge's `agents.toml`). Deferred for the same reason.

### D-008. Compatibility floor — **DOCUMENT**

`CLAUDE.md` now declares minimum supported versions: **Codex ≥ 0.128.0** (first without `--full-auto`) and **Gemini ≥ 0.39.0** (first with unified `invoke_subagent` after legacy wrappers were removed). Older versions still partially work via fallback paths but are not tested.

## Verification record

| Probe | Outcome | Date | Method |
|---|---|---|---|
| `codex --version` | 0.130.0 | 2026-05-12 | direct |
| `gemini --version` | 0.41.2 | 2026-05-12 | direct |
| `codex exec` hooks fire? | **NO** | 2026-05-12 | hook touched marker file; marker absent after 90s+ |
| `gemini -p` SessionStart fires? | **YES** | 2026-05-12 | marker present |
| `gemini -p` BeforeAgent fires? | **YES** | 2026-05-12 | marker present |
| `gemini -p` AfterAgent fires? | **YES** | 2026-05-12 | marker present |
| `gemini -p` AfterTool fires? | **YES** (when a tool is invoked) | 2026-05-12 | marker present after a tool-using prompt |
| Triforge Gemini agent tools (`read_file`, `write_file`, `grep_search`, `glob`, `list_directory`, `run_shell_command`) still valid on v0.41.2? | **YES** | 2026-05-12 | static — names match `docs/cli/tools/file-system.md` etc. on main |
| `wait_agent` (not `wait_subagent`) used in Triforge? | **YES** | 2026-05-12 | grep — no `wait_subagent` references repo-wide |

## Open watches

| Risk | Source | Trigger to revisit |
|---|---|---|
| Codex hooks come to `codex exec` | upstream | release notes mention non-interactive hook support |
| `--full-auto` resurrected under a new name | upstream | release notes show flag |
| Codex memories made on-by-default | upstream | `codex features list` shows `memories = stable true` |
| Gemini `activate_skill` consent prompt blocks headless runs | upstream | release notes touch skill consent in non-interactive mode |
| `developer_instructions` field name collision with Codex's `[agents]` schema | upstream + Triforge | Codex starts reading project `.codex/agents/agents.toml` directly |

Review on every minor version bump of either CLI.

## References

- Gap-analysis report: `ops/research/cli-updates-2026-05.md`
- Codex release notes (window): https://github.com/openai/codex/releases (filter `rust-v*`, `published_at >= 2026-03-12`)
- Gemini release notes (window): https://github.com/google-gemini/gemini-cli/releases (filter `published_at >= 2026-03-12`)
- Codex config docs: https://developers.openai.com/codex/config-reference, /config-advanced
- Gemini hooks reference: `docs/cli/hooks/reference.md` (upstream repo)
