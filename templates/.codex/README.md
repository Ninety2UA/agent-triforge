# .codex/ — Triforge-shipped Codex project config

Bootstrapped at session start, copy-if-absent so your edits survive:

| File | Purpose |
|---|---|
| `triforge-agents.toml` | The three Triforge Codex roles (`logic_reviewer`, `test_writer`, `debugger`) — a Triforge-internal file that `scripts/invoke-external.sh` parses and replays as `codex exec` flags. **Deployed under this name, not `.codex/agents/`**: Codex ≥ 0.147 sweeps `.codex/agents/*.toml` as standalone role files and prints `Ignoring malformed agent role definition` for a multi-agent file (D-026). A pre-3.3.0 `.codex/agents/agents.toml` is moved here once by `session-start.sh`. |
| `AGENTS.md` | Codex custom instructions for this project. |
| `config.toml` | Disables Codex's auto-memory pipeline (see its inline comments). |
| `hooks.json` | Ships with no hooks since 4.0. The 3.x `PostToolUse` hook appended a `codex` attribution line to `ops/CHANGELOG.md` from every session, lease workers included; attribution now comes from the lease ledger (KTD9). Session start replaces an unchanged 3.x copy once. Add your own hooks here; Codex runs them under its own hook trust (see below). |

## Project trust (D-026)

Since Codex 0.147.0, `codex exec` reads project-tier files only in a **trusted**
project: `.codex/hooks.json`, `.codex/config.toml` and `.codex/.rules` are skipped while
trust is unset (unset = untrusted for these files; `exec` never prompts). The project's
root `AGENTS.md` is different (0.150.0, D-045): it is skipped only when trust is
explicitly `untrusted`, so an unset project still loads it. Linked worktrees inherit
the root checkout's trust.

To trust the project, add it to the user-tier `~/.codex/config.toml` yourself
(Triforge never writes this file):

```toml
[projects."/absolute/path/to/your/project"]
trust_level = "trusted"
```

`at-setup` detects the exact-path entry and prints the block to add when it is missing.
Whether a parent-directory entry covers subdirectories is unverified, so add the exact path.

`invoke_codex` never passes `--dangerously-bypass-hook-trust`, so project and plugin
hooks go through Codex's own trust under `exec`. In a project without the trust entry,
Codex skips `.codex/hooks.json` altogether. The role instructions in
`triforge-agents.toml` ride as a prompt prefix whether or not the project is trusted.

Probe row CDX-04 confirmed that hooks fire under `exec` on codex 0.144.4 (2026-07-17)
and 0.154.0 (2026-09-11); the probe passes the bypass flag in a scratch fixture to stand
in for trust. See `ops/decisions/2026-07-18-codex-hooks-under-exec.md` and the newest
`ops/research/*-probe-record.md`.

## `--full-auto` is gone

Codex **removed** `--full-auto` in 0.147.0 (`error: unexpected argument` on 0.154.0).
`invoke_codex` supplies its former semantics explicitly (`-s workspace-write` +
`-c approval_policy="never"`) when an agent carries no overrides; never add the flag back.
