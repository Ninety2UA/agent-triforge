# Optional members (step 4, guided ask)

**Done when** each optional CLI walked (all of them, or the one named in the invocation) is enrolled with a chosen model, declined, reported not installed or unsupported, or already on record, and an enrolled Devin carries the user's recorded consent. Every block here starts with the line that locates and sources the helpers, so each runs on its own.

## Contents

- Preflight each member: `roster_enroll_member` and what each rc means.
- Enroll or decline: the write.
- Devin: consent first (the environment re-import, installed plugins), the model, recording the answer, the builder opt-in.
- Grok: check the read roles first.
- Live model lists.

## Preflight each member

Leave `MEMBER` unset to walk every optional CLI in registry order, or set it to the one named in the invocation (`roles` is not a CLI; it goes straight to the role step):

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
MEMBERS=$(cli_list optional)
if [ -n "${MEMBER:-}" ]; then MEMBERS=$MEMBER; fi
for M in $(printf '%s\n' "$MEMBERS"); do
  roster_enroll_member "$M" interactive; echo "$M: rc=$?"
done
```

- **`already-enrolled: ...` (rc 0)**: the member already has an entry, enrolled or declined. Show its state from the message. Do not ask again (AE6).
- **`not-installed: ...` (rc 10)**: the helper printed the official install command. Relay it for the user to run. Record nothing. This is not an error: the row shows "not installed" and setup continues (AE8).
- **`unsupported: ...` (rc 30)**: installed, but a line Triforge can't run. Today that is only OpenCode V2 (`opencode --version` 2.x, npm `@opencode/cli`, D-049), or an OpenCode whose version can't be read (refused fail-closed; the message says what to check). V2 ignores `OPENCODE_PERMISSION`, so Triforge's deny set would be dropped. Report the row as "unsupported (V2)" and relay the printed V1 pin (`npm i -g opencode-ai@1`) for the user to run. Offer no enrollment and record nothing; setup continues. Never suggest the npm package `opencode2`: it is a third-party decoy, not V2.
- **`needs-ask: <cli> installed=yes default-model=<default> auth=<...>` (rc 20)**: installed and not yet enrolled. Ask whether to enroll it and, on a yes, which model: the shipped default (recommended) or one from the CLI's live list (below). Devin goes through its consent section first.
  - `auth=auth-failed: <fix>`: pass the fix on. Enrollment records intent, so the member can still enroll, but every dispatch to it fails at the adapter's auth preflight until the user completes the login. `resolve_role` skips only declined or binary-absent members, so the fix is the login, or a decline so every chain falls back past it.
  - `auth=unverified: relaunch with ...`: the check ran inside a Codex sandbox (workspace-write), which can block it, so it says nothing about the login. Enroll as usual. The user checks the login by relaunching the lead with the printed line; nothing is cached, and no member is marked signed out (`roster_member_auth` rc 80, SELF-16).

## Enroll or decline

Set `MEMBER` and `MEMBER_MODEL` to enroll. To record a decline, set `MEMBER_ENABLED=false` and no model: it persists as `enabled = false`, shows as "skipped", and is never asked again (AE8). Devin enrolls through its own block below.

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
roster_write_member "${MEMBER:?set MEMBER to the CLI}" "${MEMBER_ENABLED:-true}" "${MEMBER_MODEL-}"; echo "rc=$?"
```

A nonzero rc means nothing was written, and the stderr line names the rule. Relay it and ask again.

## Devin: consent first

Devin's `needs-ask` output has a `consent: required` line, and Devin is never enrolled headless. Before you ask whether to enroll it, run:

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
echo "DEVIN-ENV-REIMPORT: $(devin_env_reimport)"
echo "DEVIN-PLUGINS: Devin plugins you or your org installed load in every Devin run, reviews and analyses included. devin plugins list:"
if ! _run_with_timeout 15 devin plugins list < /dev/null 2>&1 | sed 's/^/  /'; then
  echo "  (the list could not be read; the user can run devin plugins list)"
fi
```

Then tell the user what enrolling Devin means:

- Devin sends prompts and code to Cognition. Cognition may train on them unless the account opts out, which paid plans can do. A model outside Cognition's SWE family also sends them on to that model's provider.
- Devin can read the credential files in the user's home directory, like every worker.
- On `DEVIN-ENV-REIMPORT: yes` or `unknown`, add that Devin re-imports the login shell's environment and so sees every secret the shell profile exports. On `no`, say that Triforge starts Devin with only an allowlist of environment variables and no `$SHELL`, so none of those exports reach it (probe row DVN-04).
- Each plugin under `DEVIN-PLUGINS` runs inside Triforge's Devin runs too, with its skills, hooks and rules. A plugin the user doesn't want there is removed in Devin (`devin plugins remove`); Triforge has no switch for it.

## Devin: the model

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
echo "DEFAULT: $(roster_member_default devin)"
devin_model_choices; echo "rc=$?"
```

Offer `DEFAULT` first (recommended: Cognition's own model, and the one a Devin Free account can run; Free answers most others with "Upgrade to Pro"), then the ids the account lists. `rc=69` means the list could not be read (signed out, no network, or no models): offer the default. Devin has no effort flag; some ids carry it (`swe-2-high`, `swe-2-max`). The model reaches every Devin role whose own model is empty.

## Devin: record the answer

Set `DEVIN_MODEL` to the chosen model. Set `DEVIN_CONSENT=user` only when the user has just said yes to the disclosure above: the write then records `consent = "user <UTC> via=<origin>"`. On a rerun that only changes the model, leave it unset, and the consent on record is kept.

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
if [ "${DEVIN_CONSENT:-}" = user ]; then
  roster_write_member devin true "${DEVIN_MODEL:?set DEVIN_MODEL to the chosen model}" --consent user
else
  roster_write_member devin true "${DEVIN_MODEL:?set DEVIN_MODEL to the chosen model}"
fi
echo "rc=$?"
```

`rc=2` with no consent on record: `roster_write_member` refuses to enroll Devin without the user's recorded yes, and `member_rules` rejects a roster that enables it without one when the roster loads (rc 5). On a no, record the decline with the enroll-or-decline block (`MEMBER=devin`, `MEMBER_ENABLED=false`); a later enrollment asks again.

Devin reviews and analyzes by default. It builds only after a second yes, recorded with `roster_write_member devin true "<model>" --opt-in builder`. Ask it only when the user wants Devin as a builder.

## Grok: check the read roles first

An enrolled grok also gets an at-review reviewer lane. Grok runs the user's own hooks, LSP servers and config-layer commands in every session, reviews included, as it does when the user runs grok. Before you ask whether to enroll grok, run the check below. If it prints a NOTE line, pass it on to the user; the line names each of those and the file it comes from. On rc 1, relay the line it printed. A grok config file that doesn't parse, or a failed `grok inspect`, stops grok's review lane with rc 69 at every at-review, and grok can't take the reviewer or analyst role until the user fixes it.

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
grok_read_isolation_check; echo "rc=$?"
```

## Live model lists

Offer the shipped default first (recommended):

| CLI | Shipped default (recommended) | Live list command | Notes |
|---|---|---|---|
| opencode | `openrouter/z-ai/glm-5.3` | `opencode models openrouter` | needs the openrouter provider connected (`OPENROUTER_API_KEY` or `opencode auth login`) |
| kimi | `kimi-code/k3` | (no list flag) | the OAuth-managed alias; `kimi login` provisions it; offer the default |
| cursor | `cursor-grok-4.6-xhigh` | `cursor-agent --list-models` (or `agent --list-models` when only the new binary name exists) | pin the suffixed Grok id explicitly, never the Auto router; effort rides in the `-low`, `-medium`, `-high`, `-xhigh` suffix. An unrelated `~/.grok/bin/agent` can shadow `agent`, so the helper (`_cursor_bin`) resolves `cursor-agent` first and accepts `agent` only when its `--version` matches `YYYY.MM.DD-<hex>` |
| devin | `swe-1-6-slow` | `devin_model_choices` (the Devin model block above) | Cognition's own model, and the one a Devin Free account can run |
| grok | `grok-4.7` | `grok models` | Grok builds, reviews and analyzes, and is never the tester or documenter. Triforge pins the model with `--model` and passes the roster effort as `--effort` (low, medium, high, xhigh; max runs as xhigh). The readiness check looks only for `XAI_API_KEY` or a cached `grok login` and makes no model call, so a lapsed login shows up on the first dispatch, which fails at once with "Not signed in" |

Fetch a list only when the user wants to see options, for example:

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
CURSOR_BIN=$(_cursor_bin) && "$CURSOR_BIN" --list-models 2>/dev/null | head -40   # cursor-agent, else a version-verified `agent`
opencode models openrouter 2>/dev/null | grep -i glm
```

If a list command fails or is unavailable, fall back to the shipped default; never block enrollment on a missing list.
