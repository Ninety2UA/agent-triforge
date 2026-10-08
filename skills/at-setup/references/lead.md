# The lead (steps 2 and 7): asked first, written last

The lead is the CLI that plans, dispatches, cross-reviews and merges. `LEAD-CAN` below lists the CLIs the registry lets lead (Claude Code and Codex). **Done when** the user has chosen a lead, the check block has printed for that choice, and the lead block has run where the check's `LEAD-WRITE` line says (nothing to run for `none`).

Why the order: role and member writes run only from the lead's own session. `_lead_host_gate` refuses them with rc 45 under the other CLI's host markers (SELF-13). A Claude Code session that writes `[lead] cli = "codex"` first is refused on every role and member write after it (SELF-16). The lead write itself runs from either lead's session or a terminal, and `roster_write_lead` refuses it while leases are open (rc 1).

## Contents

- Detect the lead: this session's CLI, the current `[lead]`, the default, the CLIs that can lead.
- Check the choice: when the lead write runs, whether the pointer block reaches that lead, hook trust, the launch line, and for a full-access lead the confinement statements.
- Write the lead: the write, then, when the lead changed, the new lead's launch line.
- Without the dialogue: one helper per step.

## Detect the lead

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
LEAD_HOST=$(lead_host_detect)
LEAD_ROW=$(roster_lead_entry) || LEAD_ROW=""
LEAD_NOW=$(printf '%s' "$LEAD_ROW" | cut -f1)
LEAD_FROM=$(printf '%s' "$LEAD_ROW" | cut -f4)
LEAD_DEFAULT=$LEAD_NOW
if [ "$LEAD_FROM" != roster ] && lead_resolve_as "$LEAD_HOST" >/dev/null 2>&1; then LEAD_DEFAULT=$LEAD_HOST; fi
TAB=$(printf '\t')
LEAD_CAN=$(cli_table all lead | while IFS="$TAB" read -r CLI FIELDS; do if [ -n "$FIELDS" ]; then printf '%s\n' "$CLI"; fi; done | paste -sd ' ' -)
echo "LEAD-HOST: ${LEAD_HOST}"
echo "LEAD-NOW: ${LEAD_NOW:-unreadable} (${LEAD_FROM:-the [lead] table does not load: see the error above})"
echo "LEAD-DEFAULT: ${LEAD_DEFAULT:-$LEAD_HOST}"
echo "LEAD-CAN: ${LEAD_CAN}"
```

- `LEAD-HOST`: the CLI this session runs under (`lead_host_detect`): `claude`, `codex`, `none` (a terminal, or no markers), or `ambiguous` (both CLIs' markers are set).
- `LEAD-NOW`: the lead the roster names now. `roster` means an explicit `[lead]` table; `default` means none, as in a 3.x project, which resolves to Claude Code.
- `LEAD-DEFAULT`: the existing `[lead]` value; without one, this session's CLI when it can lead; else the current lead.

Ask once which CLI leads this project. Offer `LEAD-DEFAULT` first (recommended), then the rest of `LEAD-CAN`. Write nothing yet. Invoked as `at-setup lead`, the walk is this step, the check, the lead block and the closing table.

## Check the choice

Run it with `LEAD_CHOICE` set to the user's answer:

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
: "${LEAD_CHOICE:?set LEAD_CHOICE to the CLI the user chose}"
lead_resolve_as "$LEAD_CHOICE" >/dev/null || exit 2
LEAD_NOW=$(resolve_lead 2>/dev/null | cut -f1)
LEAD_HOST=$(lead_host_detect)
if [ "$LEAD_CHOICE" = "$LEAD_NOW" ]; then
  echo "LEAD-WRITE: none (${LEAD_CHOICE} leads already)"
elif [ -z "$LEAD_NOW" ] || [ "$LEAD_CHOICE" = "$LEAD_HOST" ]; then
  echo "LEAD-WRITE: first (run the lead block now: this session becomes the lead, and role and member writes run only from the lead's session)"
else
  echo "LEAD-WRITE: last (run the lead block after the egress step: role and member writes pass only while ${LEAD_NOW} still leads)"
fi
if [ -n "$LEAD_NOW" ] && [ "$LEAD_HOST" != "$LEAD_NOW" ] && [ "$LEAD_CHOICE" != "$LEAD_HOST" ]; then
  echo "LEAD-WRITE: this shell runs under ${LEAD_HOST}, not the lead (${LEAD_NOW}), so its role and member writes are refused (rc 45) unless it is a terminal"
fi
TOP=$(_checkout_top) && cd "$TOP"
instruction_pointer_visibility "$LEAD_CHOICE" | sed 's/^/AGENTS-MD: /'
TAB=$(printf '\t')
_lead_hooks_detect "$LEAD_CHOICE" | while IFS="$TAB" read -r EVENT STATE WHY; do echo "HOOKS: ${EVENT#hooks_trusted.} ${STATE}${WHY:+ ($WHY)}"; done
echo "LAUNCH: the line the user types to start this lead:"
lead_launch_line "$LEAD_CHOICE" interactive 2>&1 | sed 's/^/  /'
if [ "$(cli_field "$LEAD_CHOICE" lead.full_access 2>/dev/null)" != false ]; then
  echo "FULL-ACCESS: this lead runs with no sandbox and no approval prompts. What confines it:"
  confinement_statements
fi
```

- `LEAD-WRITE: none`: the choice leads already; there is nothing to write. `first`: this session's CLI becomes the lead, so run the lead block now, before roles and members. `last`: this session leads now, so run the lead block after the egress step, while the role and member writes still pass the host check.
- A second `LEAD-WRITE` line: this session is not the lead's, so its role and member writes are refused. Tell the user and offer the two ways out: run setup from the current lead, or choose this session's CLI as the lead.
- `AGENTS-MD:` comes from `instruction_pointer_visibility`. It says whether the project's `AGENTS.md`, the file that holds the pointer block, reaches that lead, and why. A `hidden` line names the fix, and the instruction-files step offers it. One starting `not a project:` names none: the checkout top is the user's home directory or a directory above it, so tell the user to start setup in a project directory. For Codex the line includes the instruction budget: Codex reads the user-level file and the project chain into 32 KiB (`project_doc_max_bytes`) and drops the rest.
- `HOOKS:` comes from `_lead_hooks_detect`: each event the plugin's hooks declare, `present` or `absent` with the reason. Claude Code runs an enabled plugin's hooks. Codex runs a plugin hook only after the user trusts it, so for an `absent` line under Codex, give the user the trust step from the Codex reference. Setup never writes that trust (user tier, R18).
- `LAUNCH:`: the line the user types to start this lead (`lead_launch_line <cli> interactive`).
- `FULL-ACCESS:` and the three statements under it print when the registry marks the lead's launch line full access (`lead.full_access`). Codex runs with `-s danger-full-access` and no approval prompts. Show the statements as they are written: they are what confines a full-access lead. Typing the line is the user's step (AGENTS.md, human-only actions).

Codex as the lead also needs the project trust entry that the Codex step reports (`CODEX-TRUST`). While it is `absent`, Codex skips the project's `.codex/` files in its headless runs until the user adds the printed entry. When it is `untrusted`, Codex also skips the root `AGENTS.md`, so the pointer block never reaches the lead. Name the consequence; the edit is the user's.

If the user changes the choice after seeing this, ask again and rerun the check.

## Write the lead

Run it where `LEAD-WRITE` said, with the same `LEAD_CHOICE`:

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
: "${LEAD_CHOICE:?set LEAD_CHOICE to the CLI the user chose}"
if [ "$LEAD_CHOICE" = "$(resolve_lead 2>/dev/null | cut -f1)" ]; then
  echo "LEAD: ${LEAD_CHOICE} leads already; nothing written"
  exit 0
fi
roster_write_lead "$LEAD_CHOICE"
LEAD_RC=$?
echo "rc=${LEAD_RC}"
if [ "$LEAD_RC" -eq 0 ] && [ "$LEAD_CHOICE" != "$(lead_host_detect)" ]; then
  echo "LEAD: $(cli_field "$LEAD_CHOICE" name) leads this project from its next session, and this session no longer leads. The user starts it with:"
  lead_launch_line "$LEAD_CHOICE" interactive 2>&1 | sed 's/^/  /'
  if [ "$(cli_field "$LEAD_CHOICE" lead.full_access 2>/dev/null)" != false ]; then confinement_statements; fi
fi
exit "$LEAD_RC"
```

- `rc=0`: written. When the new lead is not this session's CLI, the block prints its launch line and, for a full-access lead, the confinement statements. This session no longer leads, so role, member and lease writes from it are refused (rc 45). Print the closing table and make the commit offer (both only read the roster or run git), then end setup on the launch line: the user starts the new lead.
- `rc=1`: leases are open, and `roster_write_lead` names them. Finish or reclaim them first, or hand them over with `roster_write_lead <cli> --force` from the new lead (R38).
- `rc=2`: the CLI cannot lead, or an argument is invalid. `rc=45`: no stated origin, or both CLIs' markers are set. Relay the stderr line and ask again.

The lead's model and effort default to the registry's lead pins. A user who wants others sets them with `roster_write_lead <cli> <model> <effort>`.

## Without the dialogue

Each step is one validated helper call. An agent that has the user's answers can call them directly, in the order the check block's `LEAD-WRITE` line gives:

| Step | Helper | Refuses with |
|---|---|---|
| Lead | `roster_write_lead <cli> [<model> [<effort>]]` | 1 open leases, 2 a CLI that cannot lead, 45 no stated origin |
| Roles | `roster_write_role <role> <cli> <model> <effort> [<fallbacks>]` | 2 a broken rule (named), 45 not the lead's session |
| Members | `roster_write_member <cli> true <model>`, or `<cli> false ""` to decline; Devin adds `--consent user` | 2 Devin with no consent on record, 45 not the lead's session |
| Instruction files | `instruction_add_import <file>`, `instruction_merge_pointer`, `instruction_convert_stale <file>`, each with `--yes` only after the user said yes | 20 without `--yes`, 3 over the Codex budget, 2 a refused target |
| Disclosure | `roster_egress_disclosure` | 3 no TOML parser, 4 an unreadable roster |

Every writer validates before it writes, so a scripted run and a guided one with the same answers leave the same roster (SELF-16).
