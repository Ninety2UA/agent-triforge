---
name: at-setup
description: "Use when onboarding or re-checking a project: lead chosen, core trio live, roles assigned, optional CLIs enrolled or declined, instruction files checked, egress shown."
argument-hint: "[lead|opencode|kimi|cursor|devin|grok|roles]"
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Roster Setup

**Done when** the closing status table (one row per registered CLI, core trio first) and, on a loadable roster, the role table have printed and the verdict is stated: `resolved`; `resolved, with warnings` (naming each auth-failed member in a role chain with its fix, and each unverified one); or `UNRESOLVED` with the exact install, login or roster fix. When the lead changed, the run ends on the new lead's launch line.

**Goal:** a user-chosen lead and roster in `ops/roster.toml`: the core trio live, each role on the shipped default or the user's choice, every optional CLI enrolled with a chosen model or declined, the project's instruction files reaching the lead, and the user told what leaves the machine. It is the one guided path from a fresh install (AE6/AE8), idempotent and safe to re-run. The user's instructions outrank this skill.

**What holds, and what enforces it:**

- Every roster write goes through `roster_write_lead`, `roster_write_role` or `roster_write_member`, which validate before writing. A nonzero rc means nothing changed: relay the stderr line and ask again.
- Role and member writes run only from the lead's session (`_lead_host_gate`, rc 45). So the lead is asked first and written last, unless this session's CLI becomes the lead (the lead reference).
- Devin enrolls only with the user's recorded yes (`roster_write_member --consent user`, else rc 2; `member_rules` at load).
- An instruction-file writer changes nothing without `--yes` (rc 20). Pass it only after the user said yes.
- Installers, logins, user-tier config, Codex trust and hook trust are the user's: setup prints them (AGENTS.md, human-only actions).

Invoked with `lead`, it walks only the lead step; with one optional CLI name (`opencode`, `kimi`, `cursor`, `devin`, `grok`), only that member; with `roles`, only role assignment. The closing table prints every time. With no argument, it runs the whole walk below.

## Reach the helpers

`$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`.

```bash
set -uo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
set +e   # sourcing folds the helper's errexit into this shell; the enrollment helpers return nonzero as control flow, so turn it back off
triforge_bootstrap || [ $? -eq 80 ] || exit 1   # 80: finished with warnings (stderr names them); 45: refused in a worker
```

`triforge_bootstrap` sets the project up the way session start does: `ops/`, the `.agents/skills` copy, the per-CLI files, the agy pack, and the untracked pointer `.agents/triforge-plugin-root.local` that the locator falls back to. A Codex-led project works before any plugin hook is trusted, and a second run changes nothing.

Every block in the references starts with the same locate-and-source line, so each runs on its own in either lead's shell (bash or zsh). A block takes the user's answers as named variables (`LEAD_CHOICE`, `ROLE`, `MEMBER`, `DEVIN_MODEL`, `INSTR_OP`), set at its top. Skills carry no positional tokens (C17).

## The walk

1. Core trio: [core trio](references/core-trio.md). Codex project trust: [Codex](references/codex.md).
2. The lead, asked: detect, default, the user's choice, then the checks for it (pointer visibility, hook trust, full access, launch line). Not written yet: [lead](references/lead.md).
3. Roles: keep, customize or restore: [roles](references/roles.md).
4. Optional members: enroll or decline each; Devin's consent, model and plugins; Grok's NOTE: [optional members](references/optional-members.md).
5. Instruction files: list them for the lead, then apply each change only after the user's yes: [instruction files](references/instruction-files.md).
6. Egress: show `roster_egress_disclosure`'s lines: [status table](references/status-table.md).
7. The lead, written: where the check's `LEAD-WRITE` line says (`first` runs it right after step 2).
8. Closing status table and verdict.
9. Commit offer: workers start from HEAD, so offer to commit what setup wrote (the instruction-files reference).

Each step is also one validated helper call that an agent can make without the dialogue; the lead reference lists them.

## Facts the tree does not tell you

- `ensure_core_trio_live` names a failing core member and its fix on stderr; `cli_install_fix <cli>` prints the install-then-login line.
- `roster_enroll_member <cli> interactive` returns 0 already on record (never ask again, AE6), 10 not installed (relay the install command, AE8), 20 needs-ask, 30 unsupported (OpenCode V2 or an unreadable version, D-049). Its `auth=unverified` means the check ran inside a Codex sandbox: not a sign-out.
- Probe the roster with `resolve_role builder`: rc 0 or 6 loadable, 3 no TOML parser (not a roster problem), any other rc ROSTER-INVALID.
- agy soft-denies `read_url` headless, so the research skills need a user-tier allow rule the user merges by hand: [agy research permissions](references/agy-research-permissions.md).

## Output

- The `triforge_bootstrap:` notices, if any (none on a project that is already set up).
- `CORE-TRIO: live` or `CORE-TRIO: UNRESOLVED` with the named fix; `CODEX-TRUST: <state>` and, when absent, the `[projects."<path>"]` block for the user to add.
- The `LEAD-*` lines, the pointer visibility, the `HOOKS:` lines with any trust step, the launch line and, for a full-access lead, the confinement statements.
- The role table and any `roster_write_role` rc lines; one `rc=` line per member walked and each enrollment or decline written.
- The instruction-file table, each plan, and each write the user said yes to.
- The `egress:` and `home:` lines.
- The closing status table, CLI · INSTALLED · AUTH · ENROLLED-MODEL · ROLES (ROLES omitted on a broken roster), then the role table when the roster loads.
- The verdict, the commit offer, the `read_url(*)` permissions block for the user to merge and, when the lead changed, its launch line last.
