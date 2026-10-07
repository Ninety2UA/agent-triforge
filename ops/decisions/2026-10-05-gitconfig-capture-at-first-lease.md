# The trusted git config is captured at the first lease, not at bootstrap

- Date: 2026-10-05
- Sprint: lead-choice v4, Phase 3 (U14)
- Decided by: the lead (Claude Opus 5.5), from u14-boot's report (concern 5)
- Related: KTD18 (hardened lead git), KTD9 (lease root), plan line 590, ops/decisions/2026-10-04-codex-hook-trust-bypass-retired.md

## Decision

`lease_create` keeps capturing the trusted git config (`_lead_gitconfig_capture`) into the lease root on first use. `triforge_bootstrap` does not capture it, although the plan's KTD18 unit (line 590) says U14 would move the capture there.

## Why

The lease root is `<TMPDIR or TRIFORGE_LEASE_ROOT>/<repo>-<hash>`, so it depends on the shell that resolves it. `triforge_bootstrap` runs from the session-start hook (a Claude Code host even when `[lead]` names Codex), from an at- skill preamble and from a terminal. Those shells can resolve different lease roots, the same split that wiped approvals in Phase 2b until every ledger write recorded `[baseline].lease_root`. A capture at bootstrap time could land in a root the lead never uses, and the lead's first `lease_create` would capture again anyway.

The first-use capture already happens before any worker exists, because `lease_create` is the call that starts the first worker. Moving it earlier gains no trust.

## Evidence

- u14-boot's U14 report, concern 5 (bootstrap.sh built without the move).
- Phase 2b fix 96fb70f: `[baseline].lease_root` and `_lease_at_ledger_root`, added because a terminal's TMPDIR differed from the lead's.

## Revisit when

The lease root stops depending on TMPDIR (for example a root under the git common dir), or a Codex lead's first lease shows the capture reading a config a worker could already have touched.
