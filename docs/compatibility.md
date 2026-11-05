[← Agent Triforge](../README.md#documentation)

# Compatibility

Floors and tested versions come from the newest capability probe record, the 2026-11 cycle, kept in the maintainer's own records. "The current record" always means the newest `ops/research/*-probe-record.md`. A CLI the probe host could not exercise says so in its row and why. The core trio is required, and the optional tier is enrolled through `at-setup`. This baseline supersedes the September 2026 one, as that one superseded July's (D-034).

| CLI | Tier | Floor (KTD-13) | Tested | READY probe |
|---|---|---|---|---|
| Claude Code (`claude`) | core | ≥ 2.1.277 (a claude worker: ≥ 2.1.314; a persona: a build with `--safe-mode`) | 2.1.318 | `claude --version` |
| Antigravity (`agy`) | core | ≥ 1.1.27 | 1.5.1 (the expiry shapes were read on 1.5.0) | `agy --model "Gemini 3.8 Flash (High)" -p "Respond with only: READY"` |
| Codex (`codex`) | core | ≥ 0.153.0 | 0.166.0 (`--disable plugins` also run on 0.153.0) | `codex exec "Respond with only: READY"` |
| OpenCode (`opencode`) | optional | ≥ 1.18.20, V1 line (V2 refused) | Not tested in this cycle: the probe host has V2 (2.1.4), which the lane refuses. V1 last tested on 1.18.30 | `opencode run --format json -m openrouter/z-ai/glm-5.3 "…"` |
| Kimi Code (`kimi`) | optional | ≥ 0.33.0 | Not tested: 2.5.1 is on the probe host, whose plan refuses Kimi Code | `kimi -p "…"` |
| Cursor (`cursor-agent`; `agent` fallback) | optional | date-versioned | 2026.11.05 | `cursor-agent -p --trust --model grok-4.7-xhigh "…"` |
| Devin CLI (`devin`) | optional | ≥ 3000.10.31 | 3000.11.234 | `devin --model swe-1-6-slow --respect-workspace-trust false -p "…"` |
| Grok Build (`grok`) | optional | ≥ 1.0.34 | 1.0.70 | `grok --model grok-4.7 -p "…"` |

Why these floors:

- Claude Code 2.1.277 is the first build that reads a root `AGENTS.md`, Triforge's only instruction file (D-037). A `CLAUDE.md` beside it hides it, under the default `instructionFiles` mode, `claude-md-or-agents-md`; a user-tier setting changes this. It includes the 2.1.267 fix that honors `effort:` frontmatter on pinned-default models.
- A claude worker needs 2.1.314, the build carrying the sandbox isolation fixes: the shell's startup files stay inside the sandbox from 2.1.309, a worktree entered by `--resume` is sandboxed from 2.1.314, and from 2.1.285 the repository settings that loosen the sandbox are ignored. It refuses to start on an older one unless `TRIFORGE_CLAUDE_SANDBOX=off` is set, and session start prints a `worker-floor` line on such a build.
- Every persona runs with Claude Code's `--safe-mode`, so `dispatch_persona` refuses a `claude` without the flag (rc 69) and prints the fix, `claude update`. The persona lane was tested on 2.1.289 and 2.1.291, and an exec persona, which runs Bash, also needs the 2.1.314 sandbox floor.
- agy 1.1.27 adds `denied_actions` to the JSON envelope that `invoke_antigravity` reads as its completion signal.
- Every Codex worker passes `--disable plugins`. The flag needs no higher floor: `codex exec --help` on 0.153.0 lists `--disable <FEATURE>`, and a run there stopped an enabled plugin's hook, while `-c plugins._default.enabled=false` did not (D-061, CDX-24).
- Codex 0.153.0 is `gpt-6-astra`'s minimal client. `gpt-6.1-sol`, which a role can pick, answered on Codex 0.160.0 and was refused on 0.155.1.
- OpenCode 1.18.20 answers subagent permission asks under `run`. On a host with OpenCode V2 the V1 lane refuses it (D-049), and every OC probe row reports `UNAVAILABLE` saying so: pin V1 with `npm i -g opencode-ai@1` (`@opencode/cli` and Homebrew Core track V2).
- Kimi 0.33.0 is the agent-core-v2 engine with `--agent-file`.
- Devin 3000.10.31 is the first build where a deny rule wins over an allow rule, which its per-run config relies on. Its versions jumped from 2026.x to 3000.x in July 2026.
- Grok Build 1.0.34 is the build the GRK probe rows passed on: `dontAsk` with deny rules, the workspace sandbox, streaming JSON, and the switches that stop it reading Claude Code's config.

The Gemini CLI floor was removed with the Antigravity migration, after Google's hosted service stopped serving consumer tiers on 2026-06-18; legacy Gemini users pin plugin `v2.4.3`. An absent or declined optional CLI is skipped silently, because every fallback chain ends at a core-trio member, which can't be disabled.
