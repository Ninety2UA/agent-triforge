# Instruction files (step 5) and the commit offer (step 9)

**Done when** the instruction files in the project, in every directory above it and at the user level have been listed, the pointer block's visibility has been shown for each CLI that can lead, each change the user said yes to has been applied, and the commit offer has been made.

Each writer here asks first by construction. Without `--yes` it prints the change it would make (`needs-ask: ...`), returns 20 and writes nothing. `--yes` stands for the user's yes to that plan (`instruction_add_import`, `instruction_merge_pointer` and `instruction_convert_stale` in `scripts/lib/instructions.sh`; SELF-16). The writers also refuse, with rc 2, a symlinked target, a file that is not a regular file, and the user-level files Claude Code and Codex read (`~/.claude/CLAUDE.md`; `AGENTS.md` and `AGENTS.override.md` in `${CODEX_HOME:-~/.codex}`) under any path that leads to them, plus any other file in those directories. Triforge reads those files and never writes them. They refuse, the same way, any file in the user's home directory or a directory above it, because every project under that directory reads it. Every block starts with the line that locates and sources the helpers, then moves to the checkout top, the project the writers act on.

## Contents

- Detect the files: the table and what to offer for each state.
- Apply one change: the plan first, the write only after a yes, and what each rc means.
- Offer the commit: why, and what goes in it.

## Detect the files

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
TOP=$(_checkout_top) && cd "$TOP"
instruction_files_detect | sed 's/^/FILE: /'
TAB=$(printf '\t')
cli_table all lead | while IFS="$TAB" read -r CLI FIELDS; do
  if [ -n "$FIELDS" ]; then instruction_pointer_visibility "$CLI" < /dev/null | sed 's/^/VISIBLE: /'; fi
done
```

`FILE:` lines carry the kind, where it is (`project`, `above`, `user`), its state, its path, and the line that would import the project's `AGENTS.md` from that file. That last column is `-` when no line can: a user-level file, an `AGENTS.md` or `AGENTS.override.md`, or a file whose import line would not read back as this project's import, because the path down to the project holds whitespace (an import path ends there) or starts with `~/` (read from the home directory). A `VISIBLE:` line says, for each CLI that can lead, whether the pointer block reaches it and why; `hidden` names the fix. A `hidden` line starting `not a project:` means the checkout top is the user's home directory or a directory above it: every file listed there is read for every project under it, and the writers refuse it. Offer nothing then, and tell the user to start in a project directory. Otherwise, what to offer, by state:

- A CLAUDE.md-family file with `no-import`, in the project or above it: Claude Code reads `AGENTS.md` only while no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` exists there or above, unless one of them imports it. Only an `@AGENTS.md` in the Markdown text imports it; one inside a code block, a code span, an HTML comment or front matter does not, so that file is `no-import` too. It matters when Claude Code leads or builds.
  - In the project (`project`): offer to add the import line from the last column (`import`).
  - Above the project (`above`): an import there loads this project's `AGENTS.md` in every project under that directory too. Offer, in this order: (1) a `CLAUDE.md` in the project whose only line is `@AGENTS.md`, which loads `AGENTS.md` for this project alone. No writer creates a `CLAUDE.md`, so print that exact content for the user to create the file; if the project already has one, it is a `project` row, so offer the import line into it instead. (2) The import into the file above (`import`, `INSTR_FILE` set to it), whose plan names every project it reaches; for a `stale-3x-exact` copy, the conversion below instead. (3) Removing that file, which the user does. When the plan for (2) is refused with rc 2 because the file is in the user's home directory or a directory above it, offer (1) alone: that file belongs to the user, and every project under it reads it. When the row's `import` column is `-`, offer no import into that file: no import line there can load this project's `AGENTS.md`, and the writer refuses one (rc 2). The conversion of a `stale-3x-exact` copy needs no import line and still applies.
- No `AGENTS.md` in the project, or one with `no-pointer`: offer the pointer block (`merge`).
- `stale-3x-exact`: an unmodified copy of a Triforge 3.x template.
  - In the project: offer the conversion (`convert`). It merges the pointer block into `AGENTS.md` and removes the copy, so Claude Code reads `AGENTS.md` natively (R40).
  - Above the project: lead with the project's own `CLAUDE.md` holding `@AGENTS.md`, as for an `above` row with `no-import`. Offer the conversion after it, and only with its plan shown: it writes the `AGENTS.md` beside that copy and removes the copy, which changes what every project under that directory reads, and the plan says so. In the user's home directory or a directory above it the conversion is refused (rc 2): offer the project's own file alone.
- `stale-3x-edited`: a 3.x copy with the user's own edits. There is nothing to apply: tell the user, who moves their rules over by hand (the writer refuses it, rc 2).
- `override`: an `AGENTS.override.md`, which Codex reads instead of `AGENTS.md` at that level, so the pointer block there never reaches a Codex lead. Name it; what to do about it is the user's call.
- `symlink`, `unreadable`, or a `user` row: report only.

## Apply one change

Set `INSTR_OP` to `import`, `merge` or `convert`, and for `import` and `convert` set `INSTR_FILE` to the file's path from the table. Run the block once without `INSTR_YES`: it prints the plan and `rc=20` and writes nothing. Show the plan and ask. Only after the user says yes, run it again with `INSTR_YES=--yes`.

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
TOP=$(_checkout_top) && cd "$TOP"
case "${INSTR_OP:-}" in
  import)  instruction_add_import "${INSTR_FILE:?set INSTR_FILE to the file from the table}" ${INSTR_YES:-} ;;
  merge)   instruction_merge_pointer ${INSTR_YES:-} ;;
  convert) instruction_convert_stale "${INSTR_FILE:?set INSTR_FILE to the file from the table}" ${INSTR_YES:-} ;;
  *)       echo "set INSTR_OP to import, merge or convert" >&2; (exit 64) ;;
esac
echo "rc=$?"
```

- `rc=0`: `changed: ...`, or `unchanged: ...` when the change is already there, so a rerun is safe.
- `rc=20`: the plan; nothing was written.
- `rc=3`: over Codex's instruction budget. With the pointer block, the files Codex combines (the user-level `AGENTS.md`, then one per directory from the project root down) would pass 32,768 bytes, or the `project_doc_max_bytes` the user set. Nothing was written. Relay the sizes; the user trims a file or raises `project_doc_max_bytes` in their own Codex config.
- A `warning:` line about `AGENTS.override.md`: pass it on, as above.
- `rc=2`: refused, with the reason (for `import`, also a file that ends inside a code block or an HTML block, where an appended line would not be read: relay the block it names; the user closes it or adds the line outside it); `rc=64`: `INSTR_YES` held something other than `--yes`, or `INSTR_OP` was not set; `rc=45`: a lease worker or a lease root; `rc=80`: the file changed while the plan was made, so run the block again.

## Offer the commit

Workers start from the commit their lease is cut from, so an instruction-file or roster change setup made reaches them only once it is committed. The block lists what setup wrote that is not committed yet. Run it with `COMMIT_YES=yes` only after the user says yes:

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
TOP=$(_checkout_top) || { echo "COMMIT: not inside a git checkout; nothing to commit"; exit 0; }
cd "$TOP" || exit 1
SETUP_FILES=$(git status --porcelain --untracked-files=all -- ops/roster.toml AGENTS.md CLAUDE.md .claude/CLAUDE.md 2>/dev/null | cut -c4-)
if [ -z "$SETUP_FILES" ]; then
  echo "COMMIT: nothing setup wrote is uncommitted"
elif [ "${COMMIT_YES:-}" = yes ]; then
  printf '%s\n' "$SETUP_FILES" | xargs git add -- && printf '%s\n' "$SETUP_FILES" | xargs git commit -q -m "chore: Triforge setup (lead, roster, instruction files)" --
  echo "rc=$?"
else
  echo "COMMIT: workers start from HEAD, so these setup changes reach them once committed:"
  printf '%s\n' "$SETUP_FILES" | sed 's/^/  /'
fi
```

The commit holds only those files, whatever else is staged. `CLAUDE.local.md` stays out: it is a personal file and usually ignored. A file above the project belongs to another repository, or none: name it, and leave committing it to the user.
