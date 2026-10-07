# devin-agents/ — Devin CLI role briefs and per-run configs

Devin CLI (binary `devin`, by Cognition) joins the roster as an optional
member. It reviews and analyzes by default, builds only after the roster
records an opt-in, and is enrolled only once the user's consent is on record. The
registry entry in `scripts/lib/registry.sh` holds those rules (`role_limit`,
`opt_in_roles`, `consent`), and `resolve_role` refuses a roster that breaks
them.

## How a role reaches Devin

Devin has no headless agent selector, so the brief for the role
(`<role>.md`, frontmatter stripped) goes in front of the prompt. `invoke_devin`
does this for `dispatch_role`, and `lease_dispatch` does it for a lease. A
persona name with no brief of its own gets its role's brief, because the brief
carries the typed report contract.

Devin prints plain text and has no result envelope, so completion is the
`Status:` line plus the exit code. A clean run with no `Status:` line is
"report missing" (rc 80), and an empty one is a failure. A `-p` run stops at
the first refused tool call and exits 0 with no answer (probe row DVN-05), so
the read briefs tell Devin to use only its read, grep and glob tools, never
the shell.

## Two permission classes

| Class | Roles | Flags | Config |
|---|---|---|---|
| read | reviewer, analyst | `--permission-mode auto` (read-only tools only; a non-interactive run cannot ask for more) | `config-read.json`: allows no command and denies the `exec` and `edit` tools, `Write(**)` and every MCP tool. `git diff`, `git log` and `git show` can write a file through `--output`, and Devin has no OS sandbox, so the read class runs no command at all. |
| edit | builder (opt-in) | `--permission-mode dangerous` (every tool approved, like the Cursor and Kimi builder lanes) | `config-edit.json`: denies `git push`, `pull`, `fetch`, `commit`, `rebase`, `checkout`, `switch` |

Every run also passes `--respect-workspace-trust false`, because `-p` fails
in a directory Devin has not been told to trust, and the lease worktree is
always new.

`--config` replaces the user's `~/.config/devin/config.json`, so the user's
own Devin hooks and settings never load in a worker. `read_config_from` keeps
only `agents_standard` (`AGENTS.md`, `.agents/skills/`). Devin imports Claude
Code's configuration by default (`CLAUDE.md`, `.claude/` hooks and skills),
and these configs turn that off. Devin writes into the file it is given (an
org id, the theme, mode 600), so each run gets a fresh copy and the files here
never change. `shell.setup_complete` is set so the first-run banner stays off
stdout.

## The login shell's environment

When `$SHELL` is set, Devin runs it once per session as an interactive login
shell and copies every variable the profile exports into its tool shell. That
would undo the lease lane's environment allowlist. Without `$SHELL`, Devin
logs "login-shell env snapshot skipped" and copies nothing. The lease lane
and `invoke_devin` both start Devin under the lease environment allowlist,
which has no `SHELL` and none of the lead's other variables. Probe row DVN-04 checks
this with a `.zshrc`-only variable, and `devin_env_reimport` reads its verdict
so setup can say whether Devin sees the user's exported secrets.

`DEVIN_REFUSAL_FALLBACK` would let Devin switch models when a provider refuses
a request, so the model that answered could differ from the pinned one. The
allowlist leaves it out on both lanes.

## Model

The pin is `swe-1-6-slow`, Cognition's own model and the one a Devin Free
account can run. Free answers most other models with "Upgrade to Pro", which
Triforge treats as a deterministic plan failure. A paid account can pin any id
from `devin models list` in the roster. Devin has no effort flag; some ids
carry the effort (`swe-2-high`, `swe-2-max`).

## Files

| File | What it is |
|---|---|
| `reviewer.md` | read-only cross-reviewer brief; findings go to `ops/REVIEW_DEVIN.md` |
| `analyst.md` | read-only analysis brief |
| `builder.md` | builder brief, used only with the roster's opt-in |
| `config-read.json` | per-run config for the read class |
| `config-edit.json` | per-run config for the edit class |
