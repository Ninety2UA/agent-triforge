# kimi-agents/ — Kimi Code agent definitions (native `--agent-file`)

Kimi Code (binary: `kimi`) loads custom agents natively: since 0.29.0 a Markdown
file with YAML frontmatter is a full agent definition, and on 0.42.0 both
`--agent <name>` and `--agent-file <path>` work in headless `-p` mode (probe
KIMI-03 PASS, 2026-09-11 — it was FAIL on 0.15.0, which is why the July release
injected these briefs as a prompt prefix). Triforge no longer injects:
`invoke_kimi` and the `lease_dispatch` `kimi)` case pass
`--agent-file ${CLAUDE_PLUGIN_ROOT}/kimi-agents/<role>.md` on EVERY attempt —
the absolute path is composed by the outer shell so it crosses the `env -i`
boundary, and dropping it on a retry would re-run the reviewer with Kimi's full
toolset (KTD4). An agent-file load or parse error is classified deterministic
(no retry; the message names the file).

## What a definition carries

| Frontmatter | `builder.md` | `reviewer.md` | Why |
|---|---|---|---|
| `name`, `description` | ✓ | ✓ | identity — `description` is the one field Kimi requires |
| `whenToUse` | ✓ | ✓ | states that the lead selects the agent by dispatch, never by delegation |
| `tools` | Read, Write, Edit, Bash, Glob, Grep, FetchURL, ReadMediaFile, Skill | Read, Glob, Grep, Skill | exact-match allowlist of Kimi's built-in tool names; `Agent` (delegation) is in neither list |
| `subagents` | `[]` | `[]` | an EMPTY list forbids delegation; OMITTING the field would inherit Kimi's built-in coder / explore / plan sub-agents |

Body layout is fixed (KTD4): `${base_prompt}` first — a body without it (and
without `${plugin_sections}`) REPLACES Kimi's entire system prompt, so every
brief extends rather than replaces — then the role brief carrying the shared
dispatch contract (no sub-dispatch, git stays local, typed `Status:` report),
then `${skills}` (the merged skills injection) and `${agents_md}` (the
workspace `AGENTS.md` content). Kimi substitutes the two trailing variables only
where they are referenced.

Discovery tiers Kimi walks (highest first): `--agent-file`, project
`.kimi-code/agents/` and `.agents/agents/`, `extra_agent_dirs`, user
`~/.kimi-code/agents/` and `~/.agents/agents/`, plugins, built-ins. Triforge
deploys NOTHING into `.agents/agents/` (KTD13: agy scans the same directory with
an incompatible tool vocabulary) — the definitions stay in the plugin and are
addressed by absolute path.

## Reviewer read-only — the `tools` allowlist + the lease worktree

`reviewer.md` lists only read-side tools, so the shell, file-writing,
file-editing, URL-fetch, and delegation tools are not loaded for that agent and
a mutating call cannot be issued. Behind the allowlist sit the lease worktree
and the `_adapter_env` `KIMI_*` environment allowlist (R35). This replaces the
July prompt-level posture. What does NOT enforce it: headless `-p` runs in
"Never Ask" mode with no dangerous-command guard (0.41.0), Kimi's shell tool is
no longer confined to the workspace (0.40.0), and the project
`.kimi-code/config.toml` is not read at all — see
`templates/.kimi-code/README.md`.

## Live verification — PENDING-AUTH

KIMI-05 is AUTH-FAIL on the probe host until the user runs `kimi login` (a
user-tier action the sprint never performs — R18). The rows that prove this
directory's semantics are recorded PENDING-AUTH with their exact commands
(`$PLUGIN` is the plugin root; run each inside a throwaway git worktree):

| Row | Command | PASS when |
|---|---|---|
| KIMI-05 | `KIMI_DISABLE_TELEMETRY=1 kimi --output-format stream-json -m kimi-code/k3 -p "Respond with only: READY"` | READY appears in the stream |
| KIMI-06 | the KIMI-05 command with `kimi-code/k3` tried first in the alias candidates | the managed alias is accepted |
| KIMI-08 | `KIMI_DISABLE_TELEMETRY=1 kimi --agent-file "$PLUGIN/kimi-agents/reviewer.md" -m kimi-code/k3 -p "Create a file named kimi-ro-marker.txt in the current directory"` | the file does NOT land — the CLI refuses the write before execution (the `tools` allowlist has no write tool) |
| KIMI-09 | `KIMI_DISABLE_TELEMETRY=1 kimi --agent-file "$PLUGIN/kimi-agents/builder.md" -m kimi-code/k3 -p "Respond with only: READY"` | READY — the builder file loads with `${base_prompt}` and the trailing variables substituted. Also check the transcript for a doubled AGENTS.md / skills section: Kimi's own base prompt already renders both, so if the trailing `${skills}` / `${agents_md}` duplicate them, drop the trailing pair |

Static checks that need no login: each brief carries the three template
variables and `subagents: []` (grep), and the reviewer's `tools` list has no
shell, write, or edit entry.

## Skills

`--skills-dir` is NO LONGER passed: on 0.42.0 it REPLACES auto-discovery, and
`.agents/skills/` — where the lease provisions Triforge's twelve skills — is a
native project tier alongside `.kimi-code/skills/`; the user tier
(`~/.kimi-code/skills/`, `~/.agents/skills/`) is discovered too. A skill is
invoked as `/skill:<name>`; headless expansion is documented but unverified
until login.

## Files

| File | Role | Loaded as |
|---|---|---|
| `builder.md` | Optional-tier builder | `--agent-file` (KIMI_MODEL default `kimi-code/k3`) |
| `reviewer.md` | Read-only cross-reviewer | `--agent-file`; output merged to `ops/REVIEW_KIMI.md` |

Config, telemetry, and the auth (KIMI-05) story live in
`templates/.kimi-code/README.md`.
