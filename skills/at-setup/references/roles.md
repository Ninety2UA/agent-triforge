# Roles (Step 3): shipped defaults or customize

Roles are the task types (builder, reviewer, tester, analyst, documenter), and each maps to a CLI · model · effort with a validated fallback chain.

## Broken-roster guard first

A broken roster must be loud, not rendered as clean-looking tables. `resolve_role` runs its full load validation (unknown role or CLI names, non-list fields, chains not terminating at a core-trio member, disabled core members, across all roles and members) on every call, so one probe covers the whole file, including TOML-valid-but-content-invalid states that a bare parse check would miss:

```bash
resolve_role builder >/dev/null
case $? in
  0|6) : ;;                        # content valid (rc 6 = a binary is absent — the core-trio step's concern, not a roster problem)
  3)   echo "NO-TOML-PARSER" ;;    # missing python tomllib/tomli — NOT a roster problem
  *)   echo "ROSTER-INVALID" ;;    # rc 4 = TOML doesn't parse; rc 5 = content fails load validation
esac
```

- **`NO-TOML-PARSER`**: the host lacks a TOML parser; the stderr line names the exact fix (Python 3.11+ or `pip install tomli`). Relay it. Do not tell the user to fix or delete `ops/roster.toml`; the file is not the problem.
- **`ROSTER-INVALID`**: relay the exact stderr error (it names the line or rule) and tell the user to fix `ops/roster.toml` (or delete it; the shipped defaults then apply). Then skip the role tables and every `roster_write_role` in this step, and render the closing table without its ROLES column (the status-table reference shows the exact branch). Never skip the closing table entirely: the member install/auth summary must still print.
- Neither marker: the roster is loadable; show the current assignment surface:

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

Then check whether the roster already carries role overrides; the ask's options must be truthful about what "current" means:

```bash
# Hook-safety rule: grep -c already prints 0 on zero matches before exiting 1,
# so `|| echo 0` would duplicate it into a multiline "0\n0" — use || true and
# reserve the echo for the file-absent case.
if [ -f ops/roster.toml ]; then grep -c '^\[roles\.' ops/roster.toml || true; else echo 0; fi
```

## The one ask

Run one ask, offering (the third option only when the count above is nonzero):

- **Keep current assignments (recommended)**: record nothing; the table above stays live. On a fresh install this is the shipped posture (Claude leads builds, Codex reviews and tests, Antigravity analyzes and documents; an unwritten role always inherits it per field). On a re-run after earlier customization, "current" includes those customizations, and the table shows exactly what stays. Continue to the closing table.
- **Customize**: walk the sub-choices below for any subset of roles.
- **Restore shipped defaults** (offer only when `[roles.*]` overrides exist): write every role back to the shipped posture explicitly (values from `templates/ops/roster.toml` under the plugin root; keep this list in sync with it):

  ```bash
  roster_write_role builder    claude      ""                        max   "codex,antigravity"
  roster_write_role reviewer   codex       "gpt-6-astra"             xhigh "antigravity,claude"
  roster_write_role tester     codex       "gpt-6-astra"             xhigh "claude"
  roster_write_role analyst    antigravity "Gemini 3.8 Flash (High)" high  "claude"
  roster_write_role documenter antigravity "Gemini 3.8 Flash (High)" high  "claude"
  ```

  Note the trade: these are explicit pins, so a future plugin release that changes a shipped default will not auto-flow into this roster (an unwritten role would inherit it). Mention that to the user.

## Customize

Ask which role(s) to change (any subset). For each chosen role, walk three sub-choices, then write:

1. **CLI**: any core-trio member, or any optional member that enrolled in the members step. If the user picks an optional CLI that has not enrolled, run its enrollment first: dispatch skips a member only when it is declined (`enabled = false`) or its binary is absent, so an installed-but-unenrolled member would dispatch, just without the auth check and recorded model that enrollment provides.
2. **Model**: offer that CLI's shipped default first (recommended: `roster_member_default <cli>`), or a custom pin. Notes:
   - agy pins the newest Gemini model at its highest thinking level, Pro or Flash (D-022), currently `"Gemini 3.8 Flash (High)"`.
   - `"Gemini 3.1 Pro (High)"` is the documented opt-in (`agy models` prints the live catalog).
   - Cursor pins `cursor-grok-4.6-xhigh`, never the Auto router, and its effort rides in the model-id suffix (sub-choice 3).
   - Claude's model may stay empty (the shell builder lane runs the host default; the Fable/downgrade ladder governs sub-agent spawns).
3. **Effort**: one of `low|medium|high|xhigh|max`. Notes: for agy the effort IS the model-variant suffix. The `(Low)`/`(Medium)`/`(High)` suffix is agy's effort control and the writer normalizes it to match the chosen effort (`low` → `(Low)`, `medium` → `(Medium)`, `high`/`xhigh`/`max` → `(High)`; 3.1 Pro has no Medium and maps `medium` to `(Low)`) with a stderr NOTE, and an empty agy model is auto-filled with the effort-matched `Gemini 3.8 Flash (<variant>)` pin; a suffix-less model is written through untouched with no note. For cursor the effort is not inert: it rides in the model-id suffix (`cursor-grok-4.6-low|medium|high|xhigh`; `xhigh` and `max` → `-xhigh`), and the writer composes the suffixed id from a bare family name (`grok-4.6` → `cursor-grok-4.6-<suffix>`) or re-suffixes an explicit id to match the chosen effort.

```bash
roster_write_role <role> <cli> "<model>" <effort>; echo "rc=$?"
```

**Check the rc:** nonzero means the write was rejected and nothing changed; the stderr line names the violated rule (unknown CLI, bad effort, chain not terminating at a core member, malformed roster, or a missing TOML parser, rc 3, same fix as the guard above). Relay it and re-ask; never silently move on.

Fallback chains keep a validated shape automatically: the displaced primary becomes the first fallback and the chain still terminates at a core-trio member. Pass an explicit fifth argument (`"cli1,cli2"`) only when the user asks for a specific chain.

The writer enforces a strict superset of the rules `resolve_role` validates at load: unknown role/CLI and a chain that does not terminate at a core-trio member are rejected (mirroring load validation), and the writer additionally rejects an effort outside the enum and normalizes the agy effort→suffix pair, so a written roster always still loads.

Re-runs are safe (AE6-style): the table above always shows the current merged values, so re-running setup (or its `roles` argument) lets the user revise any earlier choice; writing a role is idempotent.
