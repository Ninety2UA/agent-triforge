# Ceremony classification (S16)

Classify the goal out loud before any phase runs, from its blast radius — files touched, shared interfaces (`ops/CONTRACTS.md` types), protected paths (permission configs, `ops/roster.toml`, hook handlers, the `invoke-external.sh` helper, `.claude/settings*.json`), and migrations or other one-way steps:

- **trivial** — fewer than 3 files, no shared interface, no protected path, no migration. Skips Phase 0 and plan-checker. `at-quick` is the natural home; if you are here anyway, say why.
- **standard** — larger work that stays inside module boundaries. The default pipeline.
- **high-ceremony** — a shared interface, a protected path, a migration, or anything security-sensitive. Plan-checker, the parallel review swarm and integration-verifier are all forced on, and Phase 1.1 is never skipped.

Write the level as the first line of `ops/TASKS.md`:

```
Ceremony: <level> — <one-line reason>
```

The build, review and wrap skills read it there. The classification is a one-way ratchet: it may be raised at any point in the sprint (hidden complexity, a contract edit discovered mid-build) and is never lowered. When in doubt, take the heavier path. Approval of an idea is not approval of an unseen plan — a user's yes to the goal does not carry over to an `ops/TASKS.md` they have not read.
