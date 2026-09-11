# .codex/ — Triforge-shipped Codex project config

Bootstrapped at session start, copy-if-absent so your edits survive:

| File | Purpose |
|---|---|
| `triforge-agents.toml` | The three Triforge Codex roles (`logic_reviewer`, `test_writer`, `debugger`) — a Triforge-internal file that `scripts/invoke-external.sh` parses and replays as `codex exec` flags. **Deployed under this name, not `.codex/agents/`**: Codex ≥ 0.147 sweeps `.codex/agents/*.toml` as standalone role files and prints `Ignoring malformed agent role definition` for a multi-agent file (D-026). A pre-3.3.0 `.codex/agents/agents.toml` is moved here once by `session-start.sh`. |
| `AGENTS.md` | Codex custom instructions for this project. |
| `config.toml` | Disables Codex's auto-memory pipeline (see its inline comments). |
| `hooks.json` | `PostToolUse` hook appending one `codex` attribution line per session to `ops/CHANGELOG.md`. |

## Project trust (D-026) — the durable path, and the automation path

Since Codex 0.147.0 (0.150.0 for `AGENTS.md`), `codex exec` reads project-tier files
only in a **trusted** project: `.codex/hooks.json`, `.codex/config.toml`, `.codex/.rules`,
and `.codex/AGENTS.md` are skipped when the project is untrusted (unset = untrusted;
`exec` never prompts). Linked worktrees inherit the root checkout's trust.

- **Durable path (user tier, human-written):** add the project to
  `~/.codex/config.toml` — Triforge never writes this file:
  ```toml
  [projects."/absolute/path/to/your/project"]
  trust_level = "trusted"
  ```
  `/setup` detects the exact-path entry and prints the block to add when it is missing.
  Whether a parent-directory entry covers subdirectories is unverified — add the exact path.
- **Automation path (what the helper does today):** `invoke_codex` passes
  `--dangerously-bypass-hook-trust` whenever the project ships `.codex/hooks.json` and
  `codex features list` reports `hooks` enabled, so the CHANGELOG hook fires under `exec`
  in an untrusted checkout (probe CDX-04 PASS on 0.154.0). The flag covers hooks only —
  `config.toml` and `AGENTS.md` still need the trust entry; the role instructions in
  `triforge-agents.toml` ride as a prompt prefix regardless of trust.

Hook firing under `exec` was verified 2026-07-17 (codex 0.144.4) and re-verified 2026-09-11
(0.154.0); see `ops/decisions/2026-07-18-codex-hooks-under-exec.md` and the newest
`ops/research/*-probe-record.md` (row CDX-04). To disable the hook: delete the project's
`.codex/hooks.json` (the helper then omits the bypass flag automatically).

## `--full-auto` is gone

Codex **removed** `--full-auto` in 0.147.0 (`error: unexpected argument` on 0.154.0).
`invoke_codex` supplies its former semantics explicitly (`-s workspace-write` +
`-c approval_policy="never"`) when an agent carries no overrides; never add the flag back.
