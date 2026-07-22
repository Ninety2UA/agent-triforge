---
description: "Guided roster onboarding: verify the core trio is live, enroll (or decline) each optional CLI with a chosen model, then accept the shipped role defaults or customize who does what (CLI · model · effort per role). Idempotent — re-run any time."
allowed-tools: Read, Grep, Bash
argument-hint: "[optional: a single cli to (re)check — opencode|kimi|cursor — or 'roles' to jump to role assignment]"
---

You are running the guided roster setup (R39). Walk every roster member — the
core trio first, then the optional CLIs — then offer role assignment (accept
the shipped defaults or customize), and leave the user with a working,
user-chosen roster in `ops/roster.toml`. This is the one guided path from a
fresh install to a live roster (AE6/AE8).

All enrollment state lives in `ops/roster.toml` under `[members.<cli>]` tables,
and role assignment under `[roles.<name>]` tables. Every member write goes
through `roster_write_member` and every role write through `roster_write_role`
(the single writers). Never edit `ops/roster.toml` by hand from this command.

Optional argument `$ARGUMENTS`: if the user named a single optional CLI, only
walk that one (still print the closing table for context). If the user passed
`roles`, skip straight to Step 3 (role assignment) — core trio and members are
assumed already set up.

## Step 0 — Source the helpers

```bash
set -uo pipefail
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh
# invoke-external.sh sets `set -euo pipefail` at its top, which sourcing folds
# into THIS shell. /setup deliberately runs without errexit — the enrollment
# helpers return nonzero by design (10 = not installed, 20 = needs interactive
# ask), and those are normal control-flow, not failures to abort on. Reset -e
# off after the source so a not-installed/needs-ask member does not kill the
# guided walk before its status row prints.
set +e
```

Everything below calls functions from that file: `ensure_core_trio_live`,
`roster_enroll_member`, `roster_member_default`, `roster_member_auth`,
`roster_write_member`, `roster_member_status`, `roster_role_entry`,
`roster_write_role`, `_roster_binary`, `_roster_install_cmd`.

## Step 1 — Core trio (required; loud until live)

The core trio (claude, antigravity/`agy`, codex) is required — it is never
enrolled and never optional. Gate it first:

```bash
ensure_core_trio_live && echo "CORE-TRIO: live" || echo "CORE-TRIO: UNRESOLVED"
```

- If it prints `live`: the trio is installed and answered its liveness probe.
- If it prints `UNRESOLVED`: `ensure_core_trio_live` already named exactly which
  member failed and its install/login fix on stderr. **Setup stays UNRESOLVED
  (loud) until the user installs/logs in that member** (AE8). Print the exact
  fix (or `_roster_install_cmd <cli>` for the install line), tell the user setup
  cannot complete until the trio is live, and still print the closing table so
  they can see the whole picture. Do NOT run any installer yourself — only the
  user runs installers.

## Step 2 — Optional members (guided ask)

For each optional CLI in order — `opencode`, `kimi`, `cursor` (or just the one in
`$ARGUMENTS`) — run the preflight, then act on its return code:

```bash
roster_enroll_member <cli> interactive; echo "rc=$?"
```

- **`already-enrolled: ...` (rc 0)** — the member already has an entry (enrolled
  or declined). Show its current state from the message. Do NOT re-ask (AE6).
- **`not-installed: ...` (rc 10)** — the helper PRINTED the official install
  command. Relay it verbatim for the user to run themselves. Record nothing.
  This is not an error — the row shows "not installed" / skipped and setup
  continues (AE8).
- **`needs-ask: <cli> installed=yes default-model=<default> auth=<...>` (rc 20)**
  — installed and not yet enrolled. Run the ask:
  1. **Participate?** Ask whether to enroll `<cli>` in the roster.
     - **No** → record the decline (persists as `enabled=false`, shown "skipped";
       no error, AE8):
       ```bash
       roster_write_member <cli> false ""
       ```
     - **Yes** → **which model?** Offer the shipped default (recommended) plus
       the CLI's own live model list, then write the choice:
       ```bash
       roster_write_member <cli> true "<chosen-model>"
       ```
  - If the `auth=` field (or `readiness:` line) reported `auth-failed: <fix>`,
    surface that fix — the member can still enroll (enrollment records intent),
    but it will not dispatch until the user completes the named login step.

**Live model lists** (offer the shipped default first, recommended):

| CLI | Shipped default (recommended) | Live list command | Notes |
|---|---|---|---|
| opencode | `openrouter/z-ai/glm-5.2` | `opencode models openrouter` | needs the openrouter provider connected (`OPENROUTER_API_KEY` or `opencode auth login`) |
| kimi | `kimi-k3` | (no list flag; `kimi --help` shows `-m`) | offer the default; sign in with `kimi login` |
| cursor | `grok-4.5` | `cursor-agent --list-models` | pin `grok-4.5` explicitly — never the Auto router |

Fetch a list only when the user wants to see options, e.g.:

```bash
cursor-agent --list-models 2>/dev/null | head -40
opencode models openrouter 2>/dev/null | grep -i glm
```

If a list command fails or is unavailable, fall back to the shipped default —
never block enrollment on a missing list.

## Step 3 — Roles: shipped defaults or customize (who does what)

Roles ARE the task types — builder, reviewer, tester, analyst, documenter —
and each maps to a CLI · model · effort with a validated fallback chain.
Show the current assignment surface first:

```bash
printf '%-11s  %-12s  %-26s  %-7s  %s\n' ROLE CLI MODEL EFFORT FALLBACKS
for role in builder reviewer tester analyst documenter; do
  entry=$(roster_role_entry "$role")
  printf '%-11s  %-12s  %-26s  %-7s  %s\n' "$role" \
    "$(printf '%s' "$entry" | cut -f1)" \
    "$(printf '%s' "$entry" | cut -f2 | sed 's/^$/<host default>/')" \
    "$(printf '%s' "$entry" | cut -f3)" \
    "$(printf '%s' "$entry" | cut -f4)"
done
```

Then run ONE ask — **proceed with these defaults (recommended), or customize?**

- **Defaults** — record nothing. The shipped posture (Claude leads builds,
  Codex reviews and tests, Antigravity analyzes and documents) is already live
  via the per-field overlay; an unwritten role always inherits it. Continue to
  Step 4.
- **Customize** — ask which role(s) to change (any subset). For each chosen
  role, walk three sub-choices, then write:
  1. **CLI** — any core-trio member, or any optional member that enrolled in
     Step 2 (an unenrolled/declined member would be skipped at dispatch — warn
     and steer back to Step 2 if the user picks one).
  2. **Model** — offer that CLI's shipped default first (recommended:
     `roster_member_default <cli>`), or a custom pin. Notes: agy pins are
     `"Gemini 3.1 Pro (High)"`/`(Low)` — Flash only when the user explicitly
     wants it; cursor pins `grok-4.5` — never the Auto router; claude's model
     may stay empty (the shell builder lane runs the host default; the
     Fable/downgrade ladder governs Agent-tool spawns).
  3. **Effort** — one of `low|medium|high|xhigh|max`. Notes: for agy the
     effort maps into the model-variant `(High)`/`(Low)` suffix; cursor has no
     effort control (`effort` is inert for it).
  ```bash
  roster_write_role <role> <cli> "<model>" <effort>
  ```
  Fallback chains keep a validated shape automatically — the displaced primary
  becomes the first fallback and the chain still terminates at a core-trio
  member. Pass an explicit fifth argument (`"cli1,cli2"`) only when the user
  asks for a specific chain.

The writer enforces the same rules `resolve_role` validates at load: unknown
role/CLI rejected, effort outside the enum rejected, and a chain that does not
terminate at a core-trio member rejected — a written roster always still loads.

Re-runs are safe (AE6-style): the table above always shows the CURRENT merged
values, so re-running `/setup` (or `/setup roles`) lets the user revise any
earlier choice; writing a role is idempotent.

## Step 4 — Closing status table (all six rows)

Always end with one row per CLI (core trio first). Build it mechanically so it
reflects the roster you just wrote — the ROLES column is DERIVED from the live
roster (Step 3 may have customized it), never hardcoded:

```bash
_roles_for() {  # _roles_for <cli> -> "builder, reviewer(fb)" from the live roster
  local cli=$1 out="" role entry primary fb
  for role in builder reviewer tester analyst documenter; do
    entry=$(roster_role_entry "$role") || continue
    primary=$(printf '%s' "$entry" | cut -f1)
    fb=$(printf '%s' "$entry" | cut -f4)
    if [ "$primary" = "$cli" ]; then out="${out:+$out, }$role"
    elif printf ',%s,' "$fb" | grep -q ",$cli,"; then out="${out:+$out, }$role(fb)"
    fi
  done
  printf '%s' "${out:-none — enroll and add to a role or its fallbacks to activate}"
}

printf '%-12s  %-10s  %-8s  %-24s  %s\n' CLI INSTALLED AUTH ENROLLED-MODEL ROLES
for cli in claude antigravity codex opencode kimi cursor; do
  bin=$(_roster_binary "$cli")
  if command -v "$bin" >/dev/null 2>&1; then inst=yes; else inst=no; fi
  st=$(roster_member_status "$cli")
  role=$(_roles_for "$cli")
  case "$cli" in
    claude|antigravity|codex)
      auth="(core)"; model="(required)" ;;
    *)
      if [ "$inst" = yes ]; then
        if roster_member_auth "$cli" >/dev/null 2>&1; then auth=ok; else auth=failed; fi
      else auth="-"; fi
      case "$st" in
        enrolled\(*\)) model="${st#enrolled\(}"; model="${model%\)}" ;;  # escape ( ) — glob metachars in zsh param-expansion patterns
        declined)      model="skipped" ;;
        *)             model="-" ;;
      esac ;;
  esac
  printf '%-12s  %-10s  %-8s  %-24s  %s\n' "$cli" "$inst" "$auth" "$model" "$role"
done
```

Follow it with the role-assignment table (the Step 3 print — role → CLI ·
model · effort · fallbacks) so the run closes on the full picture: who is
enrolled AND who does what.

Present both tables, then a one-line verdict:

- **All core-trio rows installed and live** → setup resolved. Summarize which
  optional members enrolled (and their model), which were skipped, which are
  not installed — and whether roles run the shipped defaults or were customized
  (name the changed roles).
- **Any core-trio row `no`/unresolved** → setup UNRESOLVED. Repeat the exact
  install/login fix for the missing core member(s); tell the user to install and
  re-run `/setup`.

## Idempotency & re-runs

`/setup` is safe to re-run at any time. Already-enrolled and already-declined
members show their current state and are not re-asked (AE6). To change a member,
the user can re-run `roster_write_member <cli> true "<new-model>"` (or set
`enabled=false` to disable it — disabled = absent everywhere, R38). The core
trio can never be disabled. Role assignment is equally revisable: `/setup roles`
jumps straight to Step 3, where the current merged values are always shown and
any role can be rewritten via `roster_write_role` — an unwritten role keeps
inheriting the shipped default per-field.
