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

For each optional CLI in order — `opencode`, `kimi`, `cursor` (or just the one
in `$ARGUMENTS`; `roles` is not a CLI — it routes straight to Step 3 per the
argument note above) — run the preflight, then act on its return code:

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
    but any dispatch to it will FAIL at the adapter's auth preflight until the
    user completes the named login step. `resolve_role` does not skip
    auth-failed members (only declined or binary-absent ones), so the fix is
    to complete the login — or set the member `enabled = false` so every
    chain falls back past it.

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

**Broken-roster guard first.** A broken roster must be LOUD, not rendered as
clean-looking tables. `resolve_role` runs its full load validation (unknown
role/CLI names, non-list fields, chains not terminating at a core-trio member,
disabled core members — across ALL roles and members) on every call, so one
probe covers the whole file, including TOML-valid-but-content-invalid states
that a bare parse check would miss:

```bash
resolve_role builder >/dev/null
case $? in
  0|6) : ;;                        # content valid (rc 6 = a binary is absent — Step 1's concern, not a roster problem)
  3)   echo "NO-TOML-PARSER" ;;    # missing python tomllib/tomli — NOT a roster problem
  *)   echo "ROSTER-INVALID" ;;    # rc 4 = TOML doesn't parse; rc 5 = content fails load validation
esac
```

- **`NO-TOML-PARSER`** — the host lacks a TOML parser; the stderr line names
  the exact fix (Python 3.11+ or `pip install tomli`). Relay it. Do NOT tell
  the user to fix or delete `ops/roster.toml` — the file is not the problem.
- **`ROSTER-INVALID`** — relay the exact stderr error (it names the line or
  rule), tell the user to fix `ops/roster.toml` (or delete it — the shipped
  defaults then apply). Then: skip the role tables and every
  `roster_write_role` in this step, and render Step 4's closing table without
  its ROLES column (Step 4 shows the exact branch) — never skip Step 4
  entirely; the member install/auth summary must still print.
- Neither marker → the roster is loadable; show the current assignment
  surface:

```bash
printf '%-11s  %-12s  %-26s  %-7s  %s\n' ROLE CLI MODEL EFFORT FALLBACKS
for role in builder reviewer tester analyst documenter; do
  entry=$(roster_role_entry "$role") || { echo "roster_role_entry failed for $role — see stderr"; break; }
  printf '%-11s  %-12s  %-26s  %-7s  %s\n' "$role" \
    "$(printf '%s' "$entry" | cut -f1)" \
    "$(printf '%s' "$entry" | cut -f2 | sed 's/^$/<host default>/')" \
    "$(printf '%s' "$entry" | cut -f3)" \
    "$(printf '%s' "$entry" | cut -f4)"
done
```

Then check whether the roster already carries role overrides — the ask's
options must be truthful about what "current" means:

```bash
# Hook-safety rule: grep -c already prints 0 on zero matches before exiting 1,
# so `|| echo 0` would duplicate it into a multiline "0\n0" — use || true and
# reserve the echo for the file-absent case.
if [ -f ops/roster.toml ]; then grep -c '^\[roles\.' ops/roster.toml || true; else echo 0; fi
```

Run ONE ask, offering (the third option only when the count above is nonzero):

- **Keep current assignments (recommended)** — record nothing; the table above
  stays live. On a fresh install this IS the shipped posture (Claude leads
  builds, Codex reviews and tests, Antigravity analyzes and documents — an
  unwritten role always inherits it per-field). On a re-run after earlier
  customization, "current" includes those customizations — the table shows
  exactly what stays. Continue to Step 4.
- **Customize** — walk the sub-choices below for any subset of roles.
- **Restore shipped defaults** (offer only when `[roles.*]` overrides exist) —
  write every role back to the shipped posture explicitly (values from
  `templates/ops/roster.toml` — keep this list in sync with it):
  ```bash
  roster_write_role builder    claude      ""                      max   "codex,antigravity"
  roster_write_role reviewer   codex       "gpt-5.6-sol"           xhigh "antigravity,claude"
  roster_write_role tester     codex       "gpt-5.6-sol"           xhigh "claude"
  roster_write_role analyst    antigravity "Gemini 3.1 Pro (High)" high  "claude"
  roster_write_role documenter antigravity "Gemini 3.1 Pro (High)" high  "claude"
  ```
  Note the trade: these are explicit pins, so a future plugin release that
  changes a shipped default will NOT auto-flow into this roster (an unwritten
  role would inherit it). Mention that to the user.

For **Customize**, ask which role(s) to change (any subset). For each chosen
  role, walk three sub-choices, then write:
  1. **CLI** — any core-trio member, or any optional member that enrolled in
     Step 2. If the user picks an optional CLI that has NOT enrolled, run its
     Step 2 enrollment first — dispatch skips a member only when it is
     declined (`enabled = false`) or its binary is absent; an
     installed-but-unenrolled member WOULD dispatch, just without the auth
     check and recorded model Step 2 provides.
  2. **Model** — offer that CLI's shipped default first (recommended:
     `roster_member_default <cli>`), or a custom pin. Notes: agy pins are
     `"Gemini 3.1 Pro (High)"`/`(Low)` — Flash only when the user explicitly
     wants it; cursor pins `grok-4.5` — never the Auto router; claude's model
     may stay empty (the shell builder lane runs the host default; the
     Fable/downgrade ladder governs Agent-tool spawns).
  3. **Effort** — one of `low|medium|high|xhigh|max`. Notes: for agy the
     effort IS the model-variant `(High)`/`(Low)` suffix — when the model
     carries such a suffix the writer normalizes it to match the chosen effort
     (`low`/`medium` → `(Low)`, `high`/`xhigh`/`max` → `(High)`) with a stderr
     NOTE, and an EMPTY agy model is auto-filled with the effort-matched Pro
     pin; a suffix-less model (e.g. an explicit Flash pin) is written through
     untouched with no note. Cursor has no effort control (`effort` is inert
     for it).
  ```bash
  roster_write_role <role> <cli> "<model>" <effort>; echo "rc=$?"
  ```
  **Check the rc:** nonzero means the write was REJECTED and nothing changed —
  the stderr line names the violated rule (unknown CLI, bad effort, chain not
  terminating at a core member, malformed roster, or a missing TOML parser —
  rc 3, same fix as the guard above). Relay it and re-ask; never silently
  move on.

  Fallback chains keep a validated shape automatically — the displaced primary
  becomes the first fallback and the chain still terminates at a core-trio
  member. Pass an explicit fifth argument (`"cli1,cli2"`) only when the user
  asks for a specific chain.

The writer enforces a strict superset of the rules `resolve_role` validates at
load: unknown role/CLI and a chain that does not terminate at a core-trio
member are rejected (mirroring load validation), and the writer additionally
rejects an effort outside the enum and normalizes the agy effort→suffix pair —
so a written roster always still loads.

Re-runs are safe (AE6-style): the table above always shows the CURRENT merged
values, so re-running `/setup` (or `/setup roles`) lets the user revise any
earlier choice; writing a role is idempotent.

## Step 4 — Closing status table (all six rows)

Always end with one row per CLI (core trio first). Build it mechanically so it
reflects the roster you just wrote — the ROLES column is DERIVED from the live
roster (Step 3 may have customized it), never hardcoded. The block below
re-probes roster health itself (same probe as Step 3 — `/setup <cli>` runs can
reach here without Step 3), and on a broken roster prints the member table
WITHOUT the ROLES column: the install/auth summary must still print, but a
column of misleading role guesses must not. In that branch, mark the run
UNRESOLVED and relay the exact stderr error:

```bash
ROSTER_OK=yes
resolve_role builder >/dev/null || case $? in 0|6) : ;; *) ROSTER_OK=no ;; esac

_roles_for() {  # _roles_for <cli> -> "builder, reviewer(fb)" from the live roster
  local cli=$1 out="" role entry primary fb
  for role in builder reviewer tester analyst documenter; do
    entry=$(roster_role_entry "$role") || { printf 'roster-unreadable'; return 1; }
    primary=$(printf '%s' "$entry" | cut -f1)
    fb=$(printf '%s' "$entry" | cut -f4)
    if [ "$primary" = "$cli" ]; then out="${out:+$out, }$role"
    elif printf ',%s,' "$fb" | grep -q ",$cli,"; then out="${out:+$out, }$role(fb)"
    fi
  done
  printf '%s' "${out:-none — enroll and add to a role or its fallbacks to activate}"
}

if [ "$ROSTER_OK" = yes ]; then
  printf '%-12s  %-10s  %-8s  %-24s  %s\n' CLI INSTALLED AUTH ENROLLED-MODEL ROLES
else
  printf '%-12s  %-10s  %-8s  %-24s\n' CLI INSTALLED AUTH ENROLLED-MODEL
fi
for cli in claude antigravity codex opencode kimi cursor; do
  bin=$(_roster_binary "$cli")
  if command -v "$bin" >/dev/null 2>&1; then inst=yes; else inst=no; fi
  st=$(roster_member_status "$cli")
  if [ "$ROSTER_OK" = yes ]; then role=$(_roles_for "$cli"); else role=""; fi
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
  if [ "$ROSTER_OK" = yes ]; then
    printf '%-12s  %-10s  %-8s  %-24s  %s\n' "$cli" "$inst" "$auth" "$model" "$role"
  else
    printf '%-12s  %-10s  %-8s  %-24s\n' "$cli" "$inst" "$auth" "$model"
  fi
done
```

When `ROSTER_OK=yes`, follow it with the role-assignment table (the Step 3
print — role → CLI · model · effort · fallbacks) so the run closes on the full
picture: who is enrolled AND who does what.

Present the table(s), then the verdict:

- **All core-trio rows installed and live** → setup resolved. Summarize which
  optional members enrolled (and their model), which were skipped, which are
  not installed — and whether roles run the shipped defaults or were customized
  (name the changed roles).
  - **Auth warning (required):** if any role's chain — the PRIMARY (field 1
    of its `roster_role_entry` line) or any member of its fallbacks list
    (field 4) — contains an enabled optional member whose table row shows
    `auth=failed`, the verdict must name it: dispatch does NOT skip
    auth-failed members, so that member will fail at its adapter's auth
    preflight instead of the chain walking past it — as the primary that
    breaks the role's next dispatch outright; as a fallback it lies in wait
    and blocks recovery exactly when the primary degrades. State the fix —
    complete the named login, or `roster_write_member <cli> false ""` to
    disable the member so resolution skips it — and call the run "resolved,
    with warnings", never a bare "resolved".
- **Any core-trio row `no`/unresolved** → setup UNRESOLVED. Repeat the exact
  install/login fix for the missing core member(s); tell the user to install and
  re-run `/setup`.
- **`ROSTER_OK=no`** → setup UNRESOLVED regardless of the rows above. Relay
  the roster error (or the missing-parser fix for rc 3) exactly as the Step 3
  guard describes.

## Idempotency & re-runs

`/setup` is safe to re-run at any time. Already-enrolled and already-declined
members show their current state and are not re-asked (AE6). To change a member,
the user can re-run `roster_write_member <cli> true "<new-model>"` (or set
`enabled=false` to disable it — disabled = absent everywhere, R38). The core
trio can never be disabled. Role assignment is equally revisable: `/setup roles`
jumps straight to Step 3, where the current merged values are always shown and
any role can be rewritten via `roster_write_role` — an unwritten role keeps
inheriting the shipped default per-field.
