[← Agent Triforge](../README.md#documentation)

# Compatibility

Floors and tested versions come from the newest capability probe record, [`ops/research/2026-09-probe-record.md`](../ops/research/2026-09-probe-record.md), generated 2026-09-27. "The current record" always means the newest `ops/research/*-probe-record.md`. No full probe run has been recorded since. The rows added after that record ran live during development with `probe-capabilities.sh --only`: DVN-01 to DVN-07, CC-21 to CC-25, CDX-20 to CDX-23, GRK-02 to GRK-12 and SELF-06g. Where the table says "dev-time rows", it gives the version those rows ran on. A full run would currently record Grok Build as QUOTA-FAIL (the xAI quota ran out) and Kimi as AUTH-FAIL. The core trio is required, and the optional tier is enrolled through `at-setup`. This baseline supersedes the July 2026 one (D-034).

| CLI | Tier | Floor (KTD-13) | Tested | READY probe |
|---|---|---|---|---|
| Claude Code (`claude`) | core | ≥ 2.1.277 (a claude worker: ≥ 2.1.285; a persona: a build with `--safe-mode`) | 2.1.283; dev-time rows on 2.1.289 and 2.1.291 | `claude --version` |
| Antigravity (`agy`) | core | ≥ 1.1.27 | 1.2.12 | `agy --model "Gemini 3.8 Flash (High)" -p "Respond with only: READY"` |
| Codex (`codex`) | core | ≥ 0.153.0 | 0.155.1; dev-time rows on 0.160.0 | `codex exec "Respond with only: READY"` |
| OpenCode (`opencode`) | optional | ≥ 1.18.20 | 1.18.30 | `opencode run --format json -m openrouter/z-ai/glm-5.3 "…"` |
| Kimi Code (`kimi`) | optional | ≥ 0.33.0 | 0.42.0 (AUTH-FAIL on the probe host; live rows PENDING-AUTH until `kimi login`) | `kimi -p "…"` |
| Cursor (`cursor-agent`; `agent` fallback) | optional | date-versioned | 2026.09.10 | `cursor-agent -p --trust --model cursor-grok-4.6-xhigh "…"` |
| Devin CLI (`devin`) | optional | ≥ 3000.10.31 | 3000.11.3 (dev-time rows) | `devin --model swe-1-6-slow --respect-workspace-trust false -p "…"` |
| Grok Build (`grok`) | optional | ≥ 1.0.34 | 1.0.34 (dev-time rows) | `grok --model grok-4.7 -p "…"` |

Why these floors:

- Claude Code 2.1.277 is the first build that reads a root `AGENTS.md`, Triforge's only instruction file (D-037). It includes the 2.1.267 fix that honors `effort:` frontmatter on pinned-default models.
- A claude worker needs 2.1.285, the first build that ignores the repository settings that loosen its sandbox. It refuses to start on an older one unless `TRIFORGE_CLAUDE_SANDBOX=off` is set.
- Every persona runs with Claude Code's `--safe-mode`, so `dispatch_persona` refuses a `claude` without the flag (rc 69) and prints the fix, `claude update`. The persona lane was tested on 2.1.289 and 2.1.291, and an exec persona, which runs Bash, also needs the 2.1.285 sandbox floor.
- agy 1.1.27 adds `denied_actions` to the JSON envelope that `invoke_antigravity` reads as its completion signal.
- Codex 0.153.0 is `gpt-6-astra`'s minimal client. `gpt-6.1-sol`, which a role can pick, answered on Codex 0.160.0 and was refused on 0.155.1.
- OpenCode 1.18.20 answers subagent permission asks under `run`.
- Kimi 0.33.0 is the agent-core-v2 engine with `--agent-file`.
- Devin 3000.10.31 is the first build where a deny rule wins over an allow rule, which its per-run config relies on. Its versions jumped from 2026.x to 3000.x in July 2026.
- Grok Build 1.0.34 is the build the GRK probe rows passed on: `dontAsk` with deny rules, the workspace sandbox, streaming JSON, and the switches that stop it reading Claude Code's config.

The Gemini CLI floor was removed with the Antigravity migration, after Google's hosted service stopped serving consumer tiers on 2026-06-18; legacy Gemini users pin plugin `v2.4.3`. An absent or declined optional CLI is skipped silently, because every fallback chain ends at a core-trio member, which can't be disabled.
