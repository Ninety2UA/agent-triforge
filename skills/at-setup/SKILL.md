---
name: at-setup
description: "Use when onboarding or re-checking the roster: core trio live, optional CLIs enrolled or declined, roles assigned."
argument-hint: "[opencode|kimi|cursor|roles]"
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Roster Setup

**Goal:** a working, user-chosen roster in `ops/roster.toml` (R39): the core trio live, every optional CLI enrolled with a chosen model or declined, and each role running the shipped default or the user's customization. This is the one guided path from a fresh install to a live roster (AE6/AE8); it is idempotent and safe to re-run.

**Done when** the closing status table (six rows, core trio first) and, on a loadable roster, the role table have printed and the verdict is stated: `resolved`; `resolved, with warnings` (naming every auth-failed member in a role chain and its fix); or `UNRESOLVED` with the exact install, login or roster fix the user must apply.

**Safe failure:** UNRESOLVED stays loud until the trio is live and the roster loads, and the closing table still prints. Nothing here runs an installer or a login, writes user-tier config, or edits `ops/roster.toml` by hand: every member write is `roster_write_member`, every role write `roster_write_role`, and a nonzero write rc means nothing changed, so relay the stderr rule and re-ask. The user's instructions outrank this skill.

Invoked with one optional CLI name (`opencode`, `kimi` or `cursor`) to walk only that member (the closing table still prints); with `roles` to jump to role assignment (trio and members assumed set up); when absent, the full walk in order: trio, Codex trust, members, roles, closing table.

## Reach the helpers

Paths are relative to this skill's directory.

```bash
set -uo pipefail
ROOT=$(bash scripts/locate-triforge.sh) || exit $?; source "$ROOT/scripts/invoke-external.sh"
set +e   # sourcing folds the helper's errexit into this shell; the enrollment helpers return nonzero as control flow, so turn it back off
```

Functions used: `ensure_core_trio_live`, `roster_enroll_member`, `roster_member_default`, `roster_member_auth`, `roster_write_member`, `roster_member_status`, `roster_role_entry`, `roster_write_role`, `resolve_role`, `_roster_binary`, `_roster_install_cmd`.

## Facts the tree does not tell you

- The core trio (claude, antigravity/`agy`, codex) is required: never enrolled, never optional, never disabled. `ensure_core_trio_live` names the failing member and its fix on stderr; `_roster_install_cmd <cli>` prints an install line. Gate and re-run rules: [core trio](references/core-trio.md).
- Codex project trust lives at the user tier (`~/.codex/config.toml`), detected and printed, never written (R18, D-026, D-045): [Codex trust](references/codex.md).
- `roster_enroll_member <cli> interactive` returns 0 already enrolled or declined (never re-ask, AE6), 10 not installed (relay the printed install command; not an error, AE8), 20 needs-ask (participate? which model?), 30 unsupported (OpenCode V2, or a version that cannot be read, D-049: relay the V1 pin, record nothing). A decline persists as `enabled = false`. Shipped default models and live-list commands: [optional members](references/optional-members.md).
- Roles are the task types (builder, reviewer, tester, analyst, documenter), each CLI · model · effort with a validated fallback chain ending at a core member. Probe first with `resolve_role builder`: rc 0 or 6 loadable, 3 no TOML parser (not a roster problem), any other rc ROSTER-INVALID (4 parse, 5 content). The single ask offers keep current (recommended), customize, and, only when `[roles.*]` overrides exist, restore shipped defaults: [roles](references/roles.md).
- The closing table is derived from the live roster, never hardcoded; on a broken roster it prints without the ROLES column and the run is UNRESOLVED. The table script and the verdict rules: [status table](references/status-table.md).
- agy soft-denies `read_url` headless, so the research skills need a user-tier allow rule the user merges by hand: [agy research permissions](references/agy-research-permissions.md).

## Output

- `CORE-TRIO: live` or `CORE-TRIO: UNRESOLVED` with the named fix; `CODEX-TRUST: <state>` and, when the entry is missing, the `[projects."<absolute project path>"]` block for the user to add.
- One `rc=` line per optional member walked, and each enrollment or decline recorded through `roster_write_member`.
- The role-assignment table (ROLE · CLI · MODEL · EFFORT · FALLBACKS) and any `roster_write_role` rc lines.
- The closing status table, CLI · INSTALLED · AUTH · ENROLLED-MODEL · ROLES (ROLES omitted on a broken roster), followed by the role table when the roster loads.
- The verdict (resolved; resolved, with warnings; UNRESOLVED with the exact fix) and the `read_url(*)` permissions block for the user to merge.
