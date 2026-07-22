# Residual review findings — feat/setup-role-customization

Source: ce-code-review run `20260722-135830-f2ddec9a` (2026-07-22, base `e6a73bd`,
mode:agent; reviewers: correctness, project-standards, testing, maintainability,
agent-native + independent cross-model adversarial pass via Codex,
`independence_verified: true`). Verdict: Ready with fixes. All actionable
findings (#1 custom-Codex-model ignored, #2 agy effort/suffix contradiction,
#3 DEFAULTS triplication, #5 false load-rule parity claim, #6 display/dispatch
model divergence) and all four agent-native gaps were applied on this branch in
the `fix(review)` commit. The items below were accepted as known residuals —
recorded, not dropped.

## Accepted residuals

1. **[P2-demoted] Concurrent roster writers are last-writer-wins**
   (`scripts/invoke-external.sh`, `roster_write_role` + `roster_write_member`).
   Both single-writer helpers do read-modify-verify-replace with no
   cross-process lock; two concurrent sessions in one project dir (e.g.
   `/setup roles` overlapping a session-start enrollment in another session)
   can silently drop the earlier write. The pattern is pre-existing in
   `roster_write_member`; this branch extends it to a second table family.
   Fix if it ever bites: a shared lock file or changed-since-read detection
   around the replace. Single-session use (the designed posture — the roster
   is lead-owned) is unaffected.

2. **[testing] No committed regression guard for the roster helpers.**
   `roster_role_entry` / `roster_write_role` (~250 lines incl. text surgery,
   derive, normalization, rejection paths) were verified by scratch-directory
   functional exercise this session (replace incl. trailing-comment
   preservation, absent-file append, derived + explicit chains, agy suffix
   normalization, malformed-roster rc4 paths, `resolve_role` round-trip,
   fake-codex `-m` plumbing) — but the repo has no test suite, so nothing
   re-runs this automatically.

3. **[testing] DEFAULTS mirror discipline has no forcing function.** After the
   review-driven consolidation the role-defaults table exists in two functions
   (`resolve_role`, `roster_role_entry`) plus `templates/ops/roster.toml`
   (prose), and `CLI_DEFAULT_MODEL` is mirrored in `resolve_role`,
   `roster_role_entry`, and `roster_member_default`. Sync is comment-enforced
   only. A release-checklist grep analogous to the ladder byte-identity check
   would catch drift; not added on this branch.

4. **[P3, anchor-50] `roster_write_role` verifies only the written role's
   block** — a pre-existing load-invalid hand edit elsewhere (e.g. a stray
   `[roles.reviewers]` table) still parses, so a write succeeds while every
   `resolve_role` call exits 5. The write itself can never turn a loading
   roster into a non-loading one (verified). Mitigation available: `/setup`
   could run `resolve_role builder >/dev/null` once after the role step.

5. **[P3, anchor-50] Canonical-header requirement for block replace** — a
   TOML-valid header spelled `[roles.builder]  # comment` is not matched by
   the block finder; the write falls through to append and fails safe with a
   duplicate-table round-trip error (roster untouched, misleading message).

6. **[info] Interior same-line comments on replaced field lines are dropped**
   on first customize (e.g. the `# (High) suffix = agy effort control` notes
   in the shipped template) — replace semantics; trailing standalone comment
   blocks are preserved. Documented in the function header.
