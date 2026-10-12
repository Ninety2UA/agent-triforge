# Ceremony classification (S16)

Before touching anything, classify the change out loud from its blast radius — files touched, shared interfaces (`ops/CONTRACTS.md` types), protected paths (permission configs, `ops/roster.toml`, hook handlers, the `invoke-external.sh` helper, `.claude/settings*.json`), and migrations or other one-way steps:

- **trivial** — fewer than 3 files, no shared interface, no protected path, no migration. The only level this skill serves: it skips Phase 0 and plan-checker and uses self-review.
- **standard** — anything larger that stays inside module boundaries. Run the default pipeline (`at-plan` then `at-build`, or `at-ship`).
- **high-ceremony** — a shared interface, a protected path, a migration, or anything security-sensitive. `at-ship`, with plan-checker, the parallel review swarm and integration-verifier all forced on.

State the level in one line before step 1:

```
Ceremony: trivial — 2 files, no contracts
```

The classification is a one-way ratchet: it may be raised at any point during the work and is never lowered. When in doubt, take the heavier path. If hidden complexity surfaces mid-change (a contract edit, a third file that turns out to be a fourth, a protected path), stop, say "raising to standard" or "raising to high-ceremony", and hand off to `at-plan` or `at-ship` — never keep going under this skill.
