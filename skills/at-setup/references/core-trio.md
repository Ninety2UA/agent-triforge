# Core trio (Step 1) and re-runs

The core trio (claude, antigravity/`agy`, codex) is required: it is never enrolled and never optional, and it cannot be disabled. Gate it first, with the helpers sourced:

```bash
ensure_core_trio_live && echo "CORE-TRIO: live" || echo "CORE-TRIO: UNRESOLVED"
```

- `live`: the trio is installed and answered its liveness probe (fast non-model `--version` checks, 15 s each, cached per session).
- `UNRESOLVED`: `ensure_core_trio_live` already named exactly which member failed and its install or login fix on stderr. Setup stays UNRESOLVED (loud) until the user installs or logs in that member (AE8). Print the exact fix (or `_roster_install_cmd <cli>` for the install line), say that setup cannot complete until the trio is live, and still print the closing table so the user sees the whole picture. Only the user runs installers and logins; nothing here does.

## Idempotency and re-runs

Setup is safe to re-run at any time. Already-enrolled and already-declined members show their current state and are not re-asked (AE6). To change a member, the user re-runs `roster_write_member <cli> true "<new-model>"` (or sets `enabled = false` to disable it: disabled means absent everywhere, R38). The core trio can never be disabled. Role assignment is equally revisable: the `roles` argument jumps straight to the role step, where the current merged values are always shown and any role can be rewritten through `roster_write_role`; an unwritten role keeps inheriting the shipped default per field.
