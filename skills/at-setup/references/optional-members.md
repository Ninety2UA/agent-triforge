# Optional members (Step 2, guided ask)

For each optional CLI in order, `opencode`, `kimi`, `cursor`, `devin`, `grok` (or just the one named in the invocation; `roles` is not a CLI and routes straight to role assignment), run the preflight, then act on its return code:

```bash
roster_enroll_member <cli> interactive; echo "rc=$?"
```

- **`already-enrolled: ...` (rc 0)**: the member already has an entry (enrolled or declined). Show its current state from the message. Do not re-ask (AE6).
- **`not-installed: ...` (rc 10)**: the helper printed the official install command. Relay it verbatim for the user to run themselves. Record nothing. This is not an error: the row shows "not installed" / skipped and setup continues (AE8).
- **`unsupported: ...` (rc 30)**: installed, but an unsupported line. Today that is only OpenCode V2 (`opencode --version` 2.x, npm `@opencode/cli`, D-049), or an OpenCode whose version cannot be read (refused fail-closed; the message says so and what to check). V2 ignores `OPENCODE_PERMISSION`, so Triforge's deny set would be dropped. Report the row as "unsupported (V2)" and relay the printed V1 pin (`npm i -g opencode-ai@1`) for the user to run themselves. Do not offer enrollment and record nothing; setup continues. Never suggest the npm package `opencode2`: it is a third-party decoy, not V2.
- **`needs-ask: <cli> installed=yes default-model=<default> auth=<...>` (rc 20)**: installed and not yet enrolled. Run the ask:
  1. **Participate?** Ask whether to enroll `<cli>` in the roster.
     - **No**: record the decline (persists as `enabled=false`, shown "skipped"; no error, AE8):

       ```bash
       roster_write_member <cli> false ""
       ```

     - **Yes**: **which model?** Offer the shipped default (recommended) plus the CLI's own live model list, then write the choice:

       ```bash
       roster_write_member <cli> true "<chosen-model>"
       ```

  2. If the `auth=` field (or `readiness:` line) reported `auth-failed: <fix>`, surface that fix. The member can still enroll (enrollment records intent), but any dispatch to it will fail at the adapter's auth preflight until the user completes the named login step. `resolve_role` does not skip auth-failed members (only declined or binary-absent ones), so the fix is to complete the login, or to set the member `enabled = false` so every chain falls back past it.


## Devin: consent first

Devin's `needs-ask` output has a `consent: required` line, and Devin is never enrolled headless. Before you ask whether to enroll it:

1. Run `devin_env_reimport`. It prints `yes`, `no` or `unknown`.
2. Tell the user what enrolling Devin means:
   - Devin sends prompts and code to Cognition. Cognition may train on them unless the account opts out, which paid plans can do. A model outside Cognition's SWE family also sends them on to that model's provider.
   - Devin can read the credential files in the user's home directory, like every worker.
   - On `yes` or `unknown`, add that Devin re-imports the login shell's environment and so sees every secret the shell profile exports. On `no`, say that Triforge starts Devin with only an allowlist of environment variables and no `$SHELL`, so none of those exports reach it (probe row DVN-04).
3. On a yes, record the consent with the write: `roster_write_member devin true "<model>" --consent user`. Without `--consent user` the write is refused. On a no, record the decline as for any member.
4. Devin reviews and analyzes by default. It builds only after a second yes: `roster_write_member devin true "<model>" --opt-in builder`. Ask this only when the user wants Devin as a builder.

## Live model lists

Offer the shipped default first (recommended):

| CLI | Shipped default (recommended) | Live list command | Notes |
|---|---|---|---|
| opencode | `openrouter/z-ai/glm-5.3` | `opencode models openrouter` | needs the openrouter provider connected (`OPENROUTER_API_KEY` or `opencode auth login`) |
| kimi | `kimi-code/k3` | (no list flag) | the OAuth-managed alias; `kimi login` provisions it; offer the default |
| cursor | `cursor-grok-4.6-xhigh` | `cursor-agent --list-models` (or `agent --list-models` when only the new binary name exists) | pin the suffixed Grok id explicitly, never the Auto router; effort rides in the `-low`, `-medium`, `-high`, `-xhigh` suffix. An unrelated `~/.grok/bin/agent` can shadow `agent`, so the helper (`_cursor_bin`) resolves `cursor-agent` first and accepts `agent` only when its `--version` matches `YYYY.MM.DD-<hex>` |
| devin | `swe-1-6-slow` | `devin models list` | Cognition's own model, and the one a Devin Free account can run: Free answers most other models with "Upgrade to Pro". Devin has no effort flag; some model ids carry it (`swe-2-high`, `swe-2-max`) |
| grok | `grok-4.7` | `grok models` | Grok builds, reviews and analyzes, and is never the tester or documenter. Triforge pins the model with `--model` and passes the roster effort as `--effort` (low, medium, high, xhigh; max runs as xhigh). The readiness check looks only for `XAI_API_KEY` or a cached `grok login` and makes no model call, so a lapsed login shows up on the first dispatch, which fails at once with "Not signed in" |

Fetch a list only when the user wants to see options, for example:

```bash
CURSOR_BIN=$(_cursor_bin) && "$CURSOR_BIN" --list-models 2>/dev/null | head -40   # cursor-agent, else a version-verified `agent`
opencode models openrouter 2>/dev/null | grep -i glm
```

If a list command fails or is unavailable, fall back to the shipped default; never block enrollment on a missing list.
