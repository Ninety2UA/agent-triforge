# Closing status table (Step 4) and verdict

Always end with one row per CLI (core trio first). Build it mechanically so it reflects the roster just written: the ROLES column is derived from the live roster (the roles step may have customized it), never hardcoded. The block re-probes roster health itself (the same probe as the roles step; a single-CLI run reaches here without that step), and on a broken roster prints the member table without the ROLES column: the install/auth summary must still print, but a column of misleading role guesses must not. In that branch, mark the run UNRESOLVED and relay the exact stderr error.

```bash
ROSTER_OK=yes
resolve_role builder >/dev/null || case $? in 0|6) : ;; *) ROSTER_OK=no ;; esac

# _roles_for -> "builder, reviewer(fb)" for the CLI named in ROLES_CLI, from the
# live roster. The CLI rides in a NAMED variable, never a positional parameter:
# a host may substitute positional tokens in skill text before the model reads
# it, code blocks included (S28), and skills carry none (C17).
_roles_for() {
  local cli=${ROLES_CLI:?} out="" role entry primary fb
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
for cli in $(cli_list all); do   # every registered CLI, registry order: the core trio first
  bin=$(_registry_binary "$cli")
  if command -v "$bin" >/dev/null 2>&1; then inst=yes; else inst=no; fi
  st=$(roster_member_status "$cli")
  if [ "$ROSTER_OK" = yes ]; then role=$(ROLES_CLI=$cli _roles_for); else role=""; fi
  case "$cli" in
    claude|antigravity|codex)
      auth="(core)"; model="(required)" ;;
    *)
      if [ "$inst" = no ]; then auth="-"
      elif [ "${st#unsupported-version}" != "$st" ]; then auth="n/a"  # OpenCode V2: every dispatch refuses it — skip the readiness probe
      elif roster_member_auth "$cli" >/dev/null 2>&1; then auth=ok; else auth=failed; fi
      case "$st" in
        enrolled\(*\)) model="${st#enrolled\(}"; model="${model%\)}" ;;  # escape ( ) — glob metachars in zsh param-expansion patterns
        unsupported-version\(unreadable\)) model="unsupported (version unreadable)" ;;  # D-049 fail-closed
        unsupported-version\(*\)) model="unsupported (V2)" ;;  # OpenCode V2 (D-049) — never "enrolled"
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

When `ROSTER_OK=yes`, follow it with the role-assignment table (the roles-step print: role → CLI · model · effort · fallbacks) so the run closes on the full picture: who is enrolled and who does what.

## Verdict

Present the table(s), then the verdict:

- **All core-trio rows installed and live**: setup resolved. Summarize which optional members enrolled (and their model), which were skipped, which are not installed, and whether roles run the shipped defaults or were customized (name the changed roles).
  - **Auth warning (required):** if any role's chain, the primary (field 1 of its `roster_role_entry` line) or any member of its fallbacks list (field 4), contains an enabled optional member whose table row shows `auth=failed`, the verdict must name it. Dispatch does not skip auth-failed members, so that member will fail at its adapter's auth preflight instead of the chain walking past it: as the primary it breaks the role's next dispatch outright; as a fallback it lies in wait and blocks recovery exactly when the primary degrades. State the fix (complete the named login, or `roster_write_member <cli> false ""` to disable the member so resolution skips it) and call the run "resolved, with warnings", never a bare "resolved".
- **Any core-trio row `no` or unresolved**: setup UNRESOLVED. Repeat the exact install/login fix for the missing core member(s); tell the user to install and re-run setup.
- **`ROSTER_OK=no`**: setup UNRESOLVED regardless of the rows above. Relay the roster error (or the missing-parser fix for rc 3) exactly as the roles guard describes.
