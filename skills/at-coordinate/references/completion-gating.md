# Completion gating

The sprint's completion condition is this checklist; ALL items must hold: every phase is done (or explicitly skipped with a stated reason); the `verification-before-completion` checklist passes with evidence; `ops/STATE.md` is written; review files are archived to `ops/archive/`; the runtime marker `ops/.sprint-complete` is created LAST.

At sprint start, print this copyable line for the user. A skill cannot invoke it itself: under a Claude Code lead it is user-typed, or the leading line of a headless prompt, which is exactly how `$ROOT/scripts/coordinate.sh` composes its per-iteration prompt; a Codex lead has no such gate and completes on the sentinel alone (KTD14), so for a Codex lead the line is the standing checklist, printed for the record.

```
/goal Sprint complete ONLY when ALL of: every phase is done or explicitly skipped with a stated reason; the verification-before-completion checklist passes with evidence; ops/STATE.md is written; review files are archived to ops/archive/; ops/.sprint-complete is created last.
```

Whether or not the user types it, hold yourself to that checklist as your completion condition. Create `ops/.sprint-complete` ONLY in Phase 6 after the checklist passes, never earlier. Outer tooling (`$ROOT/scripts/coordinate.sh`) detects sprint completion solely by that file's existence; the marker is gitignored and never committed.

If any checklist item fails, do NOT create `ops/.sprint-complete`; document the blocker in `ops/TASKS.md` and `ops/STATE.md` instead.
