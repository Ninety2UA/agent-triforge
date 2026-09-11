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
- [ ] `bash scripts/validate-versions.sh` exits 0 — ladder hash: `<paste the hash it prints>`
- [ ] `bash -n scripts/*.sh hooks/handlers/*.sh` exits 0
- [ ] Probe record regenerated and cited: `ops/research/<YYYY-MM>-probe-record.md` — rows: <!-- e.g. AGY-05, CDX-03 -->

## Protected paths touched?

<!-- Protected: permission configs, deny rules, ops/roster.toml (incl. [promotion]),
shipped agent configs, scripts/invoke-external.sh, scripts/coordinate.sh,
scripts/probe-capabilities.sh, hooks/handlers/*, .claude/settings*.json -->

- [ ] No
- [ ] Yes — cross-reviewed by the lead or the user: <!-- name --> (an external-CLI-only review does not satisfy this gate)

## New CLI adapter

<!-- Delete this section unless the PR adds a CLI adapter. Every item is required. -->

- [ ] READY-probe transcript (command + verbatim output):

  ```text
  $ <cli> <headless flags> "Respond with only: READY"
  READY
  ```

- [ ] Roster default: `[members.<cli>]` shape documented in `templates/ops/roster.toml`; `CLI_DEFAULT_MODEL` (both copies) and `roster_member_default` carry the pin
- [ ] Env allowlist entry: `_adapter_env` case arm in `scripts/invoke-external.sh` hands the adapter only its own provider key (KTD-14)
- [ ] Probe rows added to `scripts/probe-capabilities.sh` and present in the regenerated record: <!-- IDs -->
- [ ] Compatibility table and provider data-egress list updated in `.claude/CLAUDE.md` and `README.md`

## Unapplied review findings

<!-- One line per finding you chose not to apply: "<reviewer>: <finding> — <why not>". -->

- [ ] None
- [ ] Listed below:
  -
