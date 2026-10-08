# ops/ and the roster live at the checkout top

- Date: 2026-10-07
- Sprint: lead-choice v4, end-of-program review round 1 (run 20261007-221650-10a4e988, findings #7 and #11)
- Decided by: the lead (Claude Opus 5.5), under the 2026-09-30 autonomy grant
- Related: README.md "Upgrading from 3.x", scripts/lib/bootstrap.sh (`_tb_anchor`), scripts/lib/roster.sh (`_checkout_top`, `_lead_roster_path`), scripts/lib/lease.sh (`_lease_ctx`)

## Decision

4.0 keeps one project per git checkout: `triforge_bootstrap` creates `ops/` in the nearest directory above the session that holds `.git`, and every roster read and write uses `<checkout top>/ops/roster.toml`, wherever the session starts. A 3.x project that was bootstrapped in a subdirectory is not read from there. Instead, the bootstrap warns on every session that names the subdirectory roster until the user moves it into the top-level `ops/` (finding #7's fix).

## Why

3.3.3 already kept the lease ledger at the checkout top (`_LEASE_LEDGER="${_LEASE_REPO}/ops/leases.toml"` at 79db9c0) while it read `ops/roster.toml` relative to the session's directory. A project started from a subdirectory therefore had its roster in one place and its ledger in another. 4.0 puts the `[lead]` table in the roster, and the lead-only helpers compare the running CLI with it before they touch the ledger. If the roster and the ledger lived in different directories, a session started elsewhere could resolve another lead for the same ledger. One anchor keeps the lead, the roles, the consent records and the ledger together. The ledger's position is unchanged, so open 3.x leases still merge after the upgrade (SELF-17).

Keeping 3.x's session-directory anchoring for projects that already have a subdirectory `ops/` would bring the split back for exactly those projects. It would also let a stray `ops/roster.toml` in any subdirectory become the roster for a session started there.

## Evidence

- Review round 1, finding #11 (advisory: the plan never asked for checkout-top anchoring) and #7 (no runtime warning for an orphaned subdirectory roster).
- 79db9c0 `scripts/lib/lease.sh:115` (ledger at the repository top) and `scripts/lib/roster.sh:126` (roster relative to the working directory).

## Revisit when

A user needs several Triforge projects inside one git checkout. That would need a project marker other than `.git`, and the ledger would have to follow it.
