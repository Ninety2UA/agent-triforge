---
name: at-wrap
description: "Use when a sprint or session ends: compound knowledge, archive review files, write STATE.md, mark completion."
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Wrap Up (Phase 6)

**Goal:** the session's knowledge compounded, the shared `ops/` files current, every ruling and deferred finding surfaced to the user, the temporary review files archived, `ops/STATE.md` written for the next session, and only then the completion marker created.

**Done when** the sprint summary has printed (what was accomplished; what remains; decisions that need user input; the exhaustive **Rulings I made** list, or "none"; where deferred findings were exported; metrics: tasks completed, tests passing, review cycles), `ops/STATE.md` exists, and `ops/.sprint-complete` has been created as the LAST action after every verification item passed.

**Safe failure:** when any verification item fails, do not create `ops/.sprint-complete`; document the blocker instead. Rulings are listed and deferred findings exported BEFORE anything is archived and BEFORE the marker exists: a completion marker with unreported rulings is a hidden decision. Compounding that fails the counterfactual bar writes nothing and says so. The user's instructions outrank this skill.

This order must hold: knowledge compounding → shared files → rulings → deferred-findings export → archive → verification → `ops/STATE.md` → sprint summary → marker. Commits for the sprint's work carry decision trailers.

## Facts the tree does not tell you

- **Counterfactual bar (CE-1):** compound only when a future agent without the note would plausibly repeat the mistake or re-derive the decision (the reasoning is not recoverable from the final code, tests and docs); duration and effort are not the bar. Solutions go to `ops/solutions/YYYY-MM-DD-slug.md`, decisions to `ops/decisions/YYYY-MM-DD-slug.md`. The rulings ledger grep and the deferred-findings thresholds (fewer than ten rows → `ops/MEMORY.md` under `## Deferred findings`; ten or more → `ops/archive/<YYYY-MM-DD>-deferred-findings.md` plus a pointer): [knowledge and ledger](references/knowledge-and-ledger.md).
- **Ceremony (S16):** when `ops/TASKS.md` opens with `Ceremony: high-ceremony`, the session summary cites the plan-checker pass, the `--full` review and the integration-verifier result by name; a missing one is recorded as a gap in `ops/STATE.md`, never papered over.
- **Archive, checklist, continuity:** which files move to `ops/archive/<today>/`, the verification checklist (`verification-before-completion`), what `ops/STATE.md` carries (`session-continuity`), the summary contents and the marker command: [archive, verify, state](references/archive-verify-state.md).
- **Git trailers** on this sprint's commits (`Constraint`, `Rejected`, `Confidence`, `Scope-risk`, `Not-tested`) and when each is required: [commit trailers](references/commit-trailers.md).
- `ops/.sprint-complete` is gitignored and never committed; outer tooling (`$ROOT/scripts/coordinate.sh`, where `ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh")`) detects sprint completion solely by its existence. `$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`.

## Output

- `ops/solutions/` and `ops/decisions/` entries that pass the bar, or the line "Not compounded: reasoning recoverable from <file or diff>".
- Updated `ops/CHANGELOG.md` (final session summary), `ops/MEMORY.md` (decisions, patterns, gotchas; `## Deferred findings`), `ops/TASKS.md` (completed tasks in Done with result summaries).
- `ops/archive/<today>/` holding `REVIEW_ANTIGRAVITY.md`, `REVIEW_CODEX.md` and `TEST_RESULTS.md` when they existed; `ops/archive/<date>-deferred-findings.md` when ten or more rows were deferred.
- `ops/STATE.md`; the sprint summary with **Rulings I made** and the deferred-findings location; `ops/.sprint-complete`, or the documented blocker.
