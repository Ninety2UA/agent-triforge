# Codex: project trust and plugin hook trust (step 1 and the lead check; read-only, D-026)

Under a Codex lead this skill is invoked as `$agent-triforge:at-setup`; the walk is the same.

**Done when** `CODEX-TRUST` has printed with its state and, when Codex leads or is the chosen lead, each `HOOKS:` line that is `absent` has its trust step named for the user. Both are read-only: `codex_trust_status` and `_lead_hooks_detect` read the user's Codex config and never write it (R18, SELF-16).

## Project trust

Since Codex 0.147.0, `codex exec` reads the project-tier files (`.codex/hooks.json`, `.codex/config.toml`, `.codex/.rules`) only in a **trusted** project. It skips the root `AGENTS.md` only when trust is explicitly `untrusted` (D-045). Trust lives at the user tier, in `${CODEX_HOME:-~/.codex}/config.toml`:

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"; set +e
codex_trust_status | sed '1s/^/CODEX-TRUST: /'
```

The first line is the state, the second says which key matched (Codex looks a project up by the path as given; Triforge also tries its physical path), and the last two are the entry the user adds:

- `trusted`: the project-tier Codex files apply under `codex exec`. Nothing to do.
- `absent`: print the `[projects."<path>"]` block for the user to add to their Codex config. Codex can write the entry itself: `codex exec -s workspace-write`, which a Codex builder runs, adds it for the repo, so this reads `trusted` after the first Codex builder. Explain what works without it: the role instructions ride as a prompt prefix, and the root `AGENTS.md` still loads (D-045). `.codex/config.toml` (memories off) and `.codex/hooks.json` are skipped until the entry exists, because `invoke_codex` never passes `--dangerously-bypass-hook-trust`, so project hooks go through Codex's own trust under `exec`.
- `untrusted`: the user marked the project untrusted, so Codex skips the root `AGENTS.md` as well, and neither a Codex lead nor a Codex worker sees the pointer block. Say so; changing it is the user's call.
- `unknown` (rc 80): the config could not be read or parsed, or no TOML parser is installed. Report it as printed; setup continues.

## Plugin hook trust (a Codex lead)

The lead check's `HOOKS:` lines come from `_lead_hooks_detect codex`. An event is present only when `codex features list` shows hooks on and Codex's app-server `hooks/list` reports this plugin's hook as trusted, with the approval for the hook's `currentHash` in `hooks.state` in the user's Codex config. From Codex 0.164 `currentHash` is `<declaration hash>/<content hash>` and the approval is `trusted_hash` = the declaration hash plus `trusted_content_hash` = the content hash; an approval from before 0.164 holds that `trusted_hash` alone, and an older Codex holds `trusted_hash` = `currentHash`. For an `absent` line:

- `hooks is not on in codex features list`: hooks are off in this Codex. The user turns them on (`codex features enable hooks`).
- The hook is untrusted or modified, or no hash matches: the user trusts it in Codex. When an interactive Codex session starts with new or changed hooks, Codex shows "Hooks need review": pick "Review hooks" and trust the agent-triforge ones, or open `/hooks` in the session. Any change to the plugin's contents, this update included, asks for approval again, and until then a Codex lead runs without the plugin's hooks. After a fresh install from a Git marketplace Codex asks once more at the next launch: its first launch reinstalls the plugin, which changes those contents.
- The `hooks/list` call failed, or `codex` is not on PATH: hook trust is unknown. Report the reason.

Until the hooks are trusted, a Codex lead runs without the plugin's SessionStart, PostToolUse and PreCompact hooks (the session orientation, the context and failure monitors, the pre-compact state snapshot). Skills and helpers still work, because each `at-` preamble runs the project bootstrap itself.
