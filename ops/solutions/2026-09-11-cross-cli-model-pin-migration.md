---
problem: "Every shipped model pin across six CLIs was one generation stale, and the pins lived in eleven agy sites plus five mirrored constant blocks that had to move together"
context: "v3.3.0 watch-cycle adoption sprint (ADR D-020..D-025): Fable 5.1 / Opus 5 ladder, gpt-6-astra, Gemini 3.8 Flash (High), glm-5.3, kimi-code/k3, cursor-grok-4.6-xhigh"
solution: "One atomic pin-sweep unit over an enumerated site list, a DEFAULTS-drift check in scripts/validate-versions.sh, and a stale-pin sweep scoped to shipped surfaces (archival ops/research, ops/decisions, docs/plans, ops/solutions, docs/images excluded)"
date: 2026-09-11
agent: Claude Code (lead)
sprint_id: v3.3.0-watch-cycle-adoption
task_id: U1, U4, U10, U14
evidence_files: [scripts/invoke-external.sh, scripts/validate-versions.sh, templates/ops/roster.toml, ops/research/2026-09-probe-record.md]
related_decisions: [2026-09-11-cli-deprecation-watch]
---

## Problem

A model pin is not one string. In `scripts/invoke-external.sh` the Antigravity pin alone
lived at eleven sites (the `invoke_antigravity` default and its comment, the
`resolve_role` DEFAULTS and CLI_DEFAULT_MODEL literals, the duplicated copies of both
inside `roster_role_entry`, `roster_member_default`, the lease-lane agy case, and the
`roster_write_role` auto-fill string), and every other CLI had a `${X_MODEL:-…}` default in
its `invoke_*` helper **and** a duplicate in its `lease_dispatch` case (the two cannot share
code because the lease lane execs the CLI under `env -i`). Docs repeated the pins in
`templates/ops/roster.toml`, `commands/setup.md`, the three CLAUDE.md variants, README,
`docs/index.html`, and the probe harness. A partial edit leaves `/setup` and dispatch
disagreeing silently.

## Solution

1. **Enumerate, then edit once.** The plan (KTD6) listed every site by line before the
   edit; U1 moved the constant blocks, the roster template, and both manifests in one
   commit; U2–U4 moved each lane's `invoke_*` default and its lease-lane twin together.
2. **Make drift mechanical.** `scripts/validate-versions.sh` parses the DEFAULTS and
   CLI_DEFAULT_MODEL literals out of both `resolve_role` and `roster_role_entry` with
   `ast.literal_eval` and fails on any difference, then checks `roster_member_default`'s
   case arms and the roster template against them.
3. **Sweep shipped surfaces only.** The stale-pin sweep greps the previous generation's
   strings (`gpt-5.6-sol`, `grok-4.5`, `glm-5.2`, `kimi-k3`, `Fable 5 →`, `Opus 4.8`,
   `2026-07-probe-record`, and `Gemini 3.1 Pro (High)` only on lines that also say
   "default") and excludes `ops/research/`, `ops/decisions/`, `docs/plans/`,
   `ops/solutions/` (this note names the old pins on purpose), `docs/images/` (the
   deferred `roster.svg` export), and README's release ledger — history stays history.

## Key lessons

- **Effort is a model-id suffix on two CLIs, not a flag.** agy encodes thinking level as
  `(Low|Medium|High)` and rejects `--effort` for display names (accepted only with a bare
  slug); Cursor encodes it as `cursor-grok-4.6-low|medium|high|xhigh` and rejects the
  documented bracket form `grok-4.6[effort=xhigh]`. So the roster writer must normalize
  effort INTO the model string for both, and "effort inert" claims for Cursor were wrong.
- **Exit 0 is not a completion signal on agy.** Since 1.1.20/1.1.28 benign tool errors and
  `--print-timeout` expiry exit 0, and a denied tool leaves `status: SUCCESS` with an empty
  `response` plus `denied_actions`. Parse `--output-format json`; treat empty response +
  denial as a deterministic failure that names the user-tier allow rule.
- **Aliases move under you.** The `fable`/`opus` aliases already resolved to Fable 5.1 and
  Opus 5 weeks before the docs said so; a pin rule about "latest" needs the alias floor
  (Claude Code ≥ 2.1.257 / 2.1.219) written down beside it.
- **Archival artifacts must be excluded, not edited.** The July ADR, probe records, and
  plans legitimately name the old pins; a sweep that flags them forces history rewrites.
- **Migrate the deployed copies too.** User projects keep the pins they were bootstrapped
  with (`ops/roster.toml`, `.codex/triforge-agents.toml` are copy-if-absent); session start
  now prints one drift line per differing pin instead of rewriting them.
