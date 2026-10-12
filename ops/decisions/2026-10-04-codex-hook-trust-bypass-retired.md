# ADR: Retire the Codex hook-trust bypass in `invoke_codex`

**Date:** 2026-10-04
**Status:** Accepted (supersedes the `--dangerously-bypass-hook-trust` part of `2026-07-18-codex-hooks-under-exec.md`)
**Sprint / task:** lead-choice v4, Phase 2a (U11 worker marker; Phase 2a review run `20261004-175229-90f65ad6`)
**Agent:** lead (Claude), on a security reviewer's finding

## Context

The 2026-07-18 ADR shipped a Codex `PostToolUse` hook that appended attribution lines to `ops/CHANGELOG.md`, and had `invoke_codex` pass `--dangerously-bypass-hook-trust` whenever `.codex/hooks.json` existed and `codex features list` reported hooks enabled. The flag was justified because Triforge vetted the one hook it shipped.

U11 (KTD9) removed that hook: workers must never write `ops/`, and attribution now comes from the lease ledger. `templates/.codex/hooks.json` ships an empty hooks map, and session start replaces an unchanged 3.x copy once. After that change the bypass no longer runs any Triforge hook. It only lets whatever else a project puts in `.codex/hooks.json`, or a plugin hook, run inside every `invoke_codex` dispatch without Codex's own trust check.

The Phase 2a review's security lens raised this (CWE-284). The validator rejected it as a finding of that diff because the flag predates it (3.3.1, `bfdc6e52`) and the diff did not widen it. The exposure is still real, and nothing in 4.0 needs the flag.

## Decision

`invoke_codex` no longer passes `--dangerously-bypass-hook-trust`. Project and plugin hooks run under `codex exec` only when Codex's own trust allows them (a trusted project; the user-tier trust entry `at-setup` detects and prints, never writes). The probe rows that exercise hook firing on purpose (CDX-04, CDX-16, SELF-15c) keep passing the flag in their scratch fixtures; they test the mechanism, not a dispatch.

A second, related decision from the same review (its finding #6): session start replaces a project's `.codex/hooks.json` once, with a notice, only while the file is byte-identical to the 3.x template. This follows the KTD12 ownership-by-digest rule; an edited copy is left alone. A notice-only variant was rejected because it would leave the 3.x hook writing `ops/CHANGELOG.md` from every Codex session until the user acted. The choice is reversible: dropping the replacement turns it back into a notice.

## Consequences

- A user who relied on project Codex hooks firing inside Triforge dispatches in an untrusted project loses that; trusting the project restores it.
- An unchanged 3.x `.codex/hooks.json` becomes the empty 4.0 template on the first 4.0 session, with a notice naming the file.
- `templates/.codex/README.md`, `docs/agent-triforge.md`, `skills/at-setup/references/codex.md` and rule-inventory row 167 describe the new behavior.
- The marker-file evidence in the 2026-07-18 ADR stays valid as a record of how Codex hooks fire under exec.

## Related

- `ops/decisions/2026-07-18-codex-hooks-under-exec.md` (superseded in part)
- Evidence: `scripts/lib/codex.sh` (the removed branch), probe rows CDX-04 / CDX-16 / SELF-15c, review artifact `/tmp/compound-engineering-501/ce-code-review/20261004-175229-90f65ad6/security.json`
