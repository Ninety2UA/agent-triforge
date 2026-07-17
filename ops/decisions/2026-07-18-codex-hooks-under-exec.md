# ADR: Codex hooks under `codex exec` — D-004 reversal

**Date:** 2026-07-18
**Status:** Accepted (supersedes D-004 in `2026-05-12-cli-deprecation-watch.md`)
**Tested against:** codex-cli 0.144.4

## Context

D-004 (2026-05-12) deferred shipping `templates/.codex/hooks.json` because no hook event fired under `codex exec` on 0.130.0, even with a trusted workspace and the `CodexHooks` feature active — hooks appeared TUI-only. Convergent evidence accumulated since (factsheet `ops/research/2026-07-17-factsheet-codex.md` §4): 0.131.0 added `--dangerously-bypass-hook-trust` on all exec variants ("intended only for automation"), 0.141.0 fixed hook-trust bypass persistence through exec start and resume (a fix that presupposes hooks running in exec threads), 0.133.0–0.134.0 added SubagentStart/SubagentStop events with subagent identity in payloads, and the official docs now say "Hooks are enabled by default". The 2026-07 probe cycle re-ran the 2026-05-12 marker-file method on 0.144.4 (row CDX-04 in `ops/research/2026-07-probe-record.md`): hooks **fire** under `codex exec`.

## Decision

**ADOPT** — ship `templates/.codex/hooks.json` (deployed copy-if-absent to `.codex/hooks.json` by `hooks/handlers/session-start.sh`) with a `PostToolUse` attribution hook appending one `| codex |` line per session to `ops/CHANGELOG.md`, and have `invoke_codex` enable hook firing at invocation time. Firing under `codex exec` requires all three preconditions the probe isolated:

1. **Nested hooks.json shape** — `{"hooks": {"<Event>": [{"matcher": ".*", "hooks": [{"type": "command", "command": "..."}]}]}}`. Flat event→command forms and inline `[hooks.X]` TOML (the 2026-05-12 attempts) do not fire.
2. **Project-tier file** — `.codex/hooks.json` in the workspace `codex exec` runs in.
3. **`--dangerously-bypass-hook-trust`** — project trust is not persisted for arbitrary dirs, and the flag is the documented automation path (0.131.0+). `invoke_codex` appends it only when `.codex/hooks.json` exists AND `codex features list` reports `hooks ... true`. Trust posture: Triforge ships and vets these hooks itself — same trusted-pipeline rationale as `approval_policy = "never"` (security model, `.claude/CLAUDE.md`).

## Verification record

| Probe | Outcome | Date | Method |
|---|---|---|---|
| `codex --version` | codex-cli 0.144.4 | 2026-07-17 | direct |
| `codex features list` → `hooks` | stable, true | 2026-07-17 | direct |
| `codex exec` SessionStart fires? | **YES** | 2026-07-17 | marker-file |
| `codex exec` UserPromptSubmit fires? | **YES** | 2026-07-17 | marker-file |
| `codex exec` PreToolUse fires? | **YES** | 2026-07-17 | marker-file |
| `codex exec` Stop fires? | **YES** | 2026-07-17 | marker-file |

All four events probed with the nested shape + project file + bypass-trust flag in one `codex exec` run (`scripts/probe-capabilities.sh`, CDX-04). PostToolUse itself was not in the probed set; it ships on the same mechanism and the U7 fixture run verifies it live.

## Affected files

- `templates/.codex/hooks.json` (new) — shipped PostToolUse attribution hook (session-keyed marker guard)
- `templates/.codex/README.md` (new) — what the hook enforces, why bypass-trust is passed, how to disable
- `hooks/handlers/session-start.sh` — copy-if-absent deploy of hooks.json
- `scripts/invoke-external.sh` — conditional `--dangerously-bypass-hook-trust` + `codex features list` gating
- `.claude/CLAUDE.md`, `README.md` — compatibility floors re-baselined (Codex ≥ 0.144.0)

## Open watches

| Risk | Source | Trigger to revisit |
|---|---|---|
| Bypass-trust requirement relaxes (persistent project trust for exec) | upstream | release notes mention exec-mode trust persistence or a `codex trust` command |
| hooks.json schema evolves (nested shape, matcher semantics, new events) | upstream | 0.140.0-style validation warnings appear in `invoke_codex` output |
| `PostToolUse` payload/env gains a stable session id (better marker keying than `$PPID`) | upstream | hooks docs list hook environment variables |
| Hooks made to fire without the flag but gated on new consent UX that blocks automation | upstream | exec runs hang or warn on hook consent |

Review on every minor version bump of Codex CLI.

## References

- Probe record: `ops/research/2026-07-probe-record.md` (CDX-02, CDX-04)
- Fact sheet: `ops/research/2026-07-17-factsheet-codex.md` §4
- Superseded decision: `ops/decisions/2026-05-12-cli-deprecation-watch.md` D-004
- Codex hooks docs: https://learn.chatgpt.com/docs/hooks
