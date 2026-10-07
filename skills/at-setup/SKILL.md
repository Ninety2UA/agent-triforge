---
name: at-setup
description: "Use when onboarding or re-checking the roster: core trio live, optional CLIs enrolled or declined, roles assigned."
argument-hint: "[opencode|kimi|cursor|devin|grok|roles]"
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Roster Setup

**Goal:** a working, user-chosen roster in `ops/roster.toml` (R39): the core trio live, every optional CLI enrolled with a chosen model or declined, and each role running the shipped default or the user's customization. This is the one guided path from a fresh install to a live roster (AE6/AE8); it is idempotent and safe to re-run.

**Done when** the closing status table (one row per registered CLI, core trio first) and, on a loadable roster, the role table have printed and the verdict is stated: `resolved`; `resolved, with warnings` (naming every auth-failed member in a role chain and its fix); or `UNRESOLVED` with the exact install, login or roster fix the user must apply.

**Safe failure:** UNRESOLVED stays loud until the trio is live and the roster loads, and the closing table still prints. Nothing here runs an installer or a login, writes user-tier config, or edits `ops/roster.toml` by hand: every member write is `roster_write_member`, every role write `roster_write_role`, and a nonzero write rc means nothing changed, so relay the stderr rule and re-ask. The user's instructions outrank this skill.

Invoked with one optional CLI name (`opencode`, `kimi`, `cursor`, `devin` or `grok`) to walk only that member (the closing table still prints); with `roles` to jump to role assignment (trio and members assumed set up); when absent, the full walk in order: trio, Codex trust, members, roles, closing table.

## Reach the helpers

`$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`.

```bash
set -uo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
set +e   # sourcing folds the helper's errexit into this shell; the enrollment helpers return nonzero as control flow, so turn it back off
triforge_bootstrap || [ $? -eq 80 ] || exit 1   # 80: finished with warnings (stderr names them); 45: refused in a worker
```

`triforge_bootstrap` sets the project up the way session start does: `ops/`, the `.agents/skills` copy, the per-CLI files, the agy pack, and the untracked pointer `.agents/triforge-plugin-root.local` that the locator falls back to. A Codex-led project works before any plugin hook is trusted, and a second run changes nothing.

Functions used: `triforge_bootstrap`, `ensure_core_trio_live`, `cli_list`, `devin_env_reimport`, `roster_enroll_member`, `roster_member_default`, `roster_member_auth`, `roster_write_member`, `roster_member_status`, `roster_role_entry`, `roster_write_role`, `resolve_role`, `_registry_binary`, `cli_install_fix`.

## Facts the tree does not tell you

- The core trio (claude, antigravity/`agy`, codex) is required: never enrolled, never optional, never disabled. `ensure_core_trio_live` names the failing member and its fix on stderr; `cli_install_fix <cli>` prints the install-then-login line. Gate and re-run rules: [core trio](references/core-trio.md).
- Codex project trust lives at the user tier (`~/.codex/config.toml`), detected and printed, never written (R18, D-026, D-045): [Codex trust](references/codex.md).
- `roster_enroll_member <cli> interactive` returns 0 already enrolled or declined (never re-ask, AE6), 10 not installed (relay the printed install command; not an error, AE8), 20 needs-ask (participate? which model?), 30 unsupported (OpenCode V2, or a version that cannot be read, D-049: relay the V1 pin, record nothing). A decline persists as `enabled = false`. Devin also needs the user's recorded consent (`--consent user`) and builds only with a recorded opt-in. Shipped default models, live-list commands and the Devin consent step: [optional members](references/optional-members.md).
- Roles are the task types (builder, reviewer, tester, analyst, documenter), each CLI · model · effort with a validated fallback chain ending at a core member. Probe first with `resolve_role builder`: rc 0 or 6 loadable, 3 no TOML parser (not a roster problem), any other rc ROSTER-INVALID (4 parse, 5 content). The single ask offers keep current (recommended), customize, and, only when `[roles.*]` overrides exist, restore shipped defaults: [roles](references/roles.md).
- The closing table is derived from the live roster, never hardcoded; on a broken roster it prints without the ROLES column and the run is UNRESOLVED. The table script and the verdict rules: [status table](references/status-table.md).
- agy soft-denies `read_url` headless, so the research skills need a user-tier allow rule the user merges by hand: [agy research permissions](references/agy-research-permissions.md).

## Output

- The `triforge_bootstrap:` notices, if any (none on a project that is already set up).
- `CORE-TRIO: live` or `CORE-TRIO: UNRESOLVED` with the named fix; `CODEX-TRUST: <state>` and, when the entry is missing, the `[projects."<absolute project path>"]` block for the user to add.
- One `rc=` line per optional member walked, and each enrollment or decline recorded through `roster_write_member`.
- The role-assignment table (ROLE · CLI · MODEL · EFFORT · FALLBACKS) and any `roster_write_role` rc lines.
- The closing status table, CLI · INSTALLED · AUTH · ENROLLED-MODEL · ROLES (ROLES omitted on a broken roster), followed by the role table when the roster loads.
- The verdict (resolved; resolved, with warnings; UNRESOLVED with the exact fix) and the `read_url(*)` permissions block for the user to merge.
