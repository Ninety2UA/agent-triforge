<!--
Agent Triforge pull request template (S20). Fill every section; delete the
"New CLI adapter" section unless this PR adds an adapter. Keep the
provenance table — it is the audit trail for which models and harness
versions produced this change.
-->

## Summary

<!-- What changed and why, in 2-5 lines. Lead with the user-visible effect. -->

## Plan / ADR

- Plan: `docs/plans/<file>.md` (or "none — small change")
- ADR: `ops/decisions/<file>.md` (or "none")

## Provenance

| Field | Value |
|---|---|
| Model(s) used | <!-- lead model @ effort; builder(s); reviewer(s) — e.g. "<lead model> @ max (lead), <reviewer model> @ xhigh (Codex reviewer)" --> |
| Harness / CLI versions | <!-- claude X.Y.Z, agy X.Y.Z, codex X.Y.Z, plus any optional-tier CLI that took part --> |
| Plugin version | <!-- `.claude-plugin/plugin.json` version this PR ships (must match `antigravity-agents/plugin.json` and the README "What's new" heading) --> |
| Human reviewer | <!-- @handle — the person who read the diff --> |

## Verification

- [ ] `claude plugin validate --strict .` passes (warnings are errors)
- [ ] `bash scripts/validate-skills.sh` exits 0
- [ ] `bash scripts/validate-versions.sh` exits 0 — summary line: `<paste it: ladder: one definition (scripts/lib/registry.sh)>`
- [ ] `bash -n scripts/*.sh hooks/handlers/*.sh` exits 0
- [ ] Probe record regenerated and cited: `ops/research/<YYYY-MM>-probe-record.md` — rows: <!-- e.g. AGY-05, CDX-03 -->
- [ ] Version bump PRs only: README "Recent changes" has the `### <date> — v<version>: <title>` entry — it becomes the GitHub release when this merges (`.github/workflows/release.yml`; preview with `bash scripts/release-notes.sh --body`)

## Protected paths touched?

<!-- The protected-path lists live in scripts/lib/registry.sh. In every project:
ops/roster.toml (incl. [promotion]); each CLI's config and permission tree (.claude/,
.codex/, .agents/, .antigravity/, .gemini/, .opencode/, .kimi-code/, .cursor/, plus
opencode.json, opencode.jsonc, .cursorrules and .gitmodules at the root); and every AGENTS.md,
AGENTS.override.md, CLAUDE.md, CLAUDE.local.md and .mcp.json at any depth. In this
repo (the Triforge checkout) also the framework's control plane: the enforcement,
probe and release scripts, hooks/, skills/, commands/, the shipped agent configs,
.claude-plugin/, settings.json, templates/, personas/, .github/ and every
.gitattributes (full list in the "Protected paths" bullet of AGENTS.md, "Do not touch").
The lease_promote scan is case-folded, sees both sides of a rename, and fails
closed (rc 42). -->

- [ ] No
- [ ] Yes — cross-reviewed by the lead or the user: <!-- name --> (an external-CLI-only review does not satisfy this gate)

## New CLI adapter

<!-- Delete this section unless the PR adds a CLI adapter. Every item is required. -->

- [ ] READY-probe transcript (command + verbatim output):

  ```text
  $ <cli> <headless flags> "Respond with only: READY"
  READY
  ```

- [ ] Roster default: `[members.<cli>]` shape documented in `templates/ops/roster.toml`; the CLI's registry entry (`model` in `scripts/lib/registry.sh`) carries the pin — `validate-versions.sh` check 3 keeps `DEFAULTS`, the template and the lane defaults in line with it
- [ ] Env allowlist entry: `_adapter_env` case arm in `scripts/invoke-external.sh` hands the adapter only its own provider key (KTD-14)
- [ ] Probe rows added to `scripts/probe-capabilities.sh` and present in the regenerated record: <!-- IDs -->
- [ ] Compatibility table and provider data-egress list updated in `README.md` (and the moved notes in `docs/agent-triforge.md`); `AGENTS.md` still within budget (`validate-versions.sh` check 6)

## Unapplied review findings

<!-- One line per finding you chose not to apply: "<reviewer>: <finding> — <why not>". -->

- [ ] None
- [ ] Listed below:
  -
