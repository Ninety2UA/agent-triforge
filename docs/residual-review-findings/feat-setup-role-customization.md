# Residual review findings — feat/setup-role-customization

Source: TWO ce-code-review iterations (2026-07-22, base `e6a73bd`, mode:agent;
reviewers each round: correctness, project-standards, testing, maintainability,
agent-native + independent cross-model adversarial pass via Codex,
`independence_verified: true`).

- **Iteration 1** (run `20260722-135830-f2ddec9a`): all actionable findings
  applied (custom-Codex-model ignored → `CODEX_MODEL` override; agy
  effort/suffix contradiction → writer normalization; DEFAULTS triplication →
  composition; false load-rule parity claim → superset rewording;
  display/dispatch model divergence → primary-model display rule) plus four
  agent-native gaps.
- **Iteration 2** (run `20260722-145320-9077062b`): re-review of the fixed
  tree. Confirmed all iteration-1 fixes closed (correctness traced each
  before/after by execution). New findings applied: the roster guard now runs
  `resolve_role`'s full load validation (content-invalid rosters — unknown
  CLIs, non-core-terminating chains, non-list fields — are LOUD, not rendered
  as clean tables; dual-corroborated cross-family), rc 3 (missing TOML parser)
  distinguished from roster errors, Step 4 gained an executable
  no-ROLES-column branch, the role ask became truthful on re-runs
  (keep-current / restore-shipped-defaults / customize), the closing verdict
  now warns on auth-failed role primaries (dispatch does not skip them), the
  "every dispatch lane" claim was scoped to external-CLI lanes (claude stays
  ladder-governed by design), the normalization NOTE moved after all rejecting
  validation, an empty agy model is auto-filled with the effort-matched pin,
  and model strings are stripped. One iteration-2 finding was
  validator-REJECTED and deliberately not applied: reverting
  `roster_write_role`'s composition of `roster_role_entry` (the double
  read/TSV coupling is a documented, deliberate trade against re-duplicating
  the DEFAULTS table; no supported failure scenario).

The items below were accepted as known residuals — recorded, not dropped.

## Accepted residuals

1. **[P2-demoted] Concurrent roster writers are last-writer-wins**
   (`scripts/invoke-external.sh`, `roster_write_role` + `roster_write_member`).
   Both single-writer helpers do read-modify-verify-replace with no
   cross-process lock; two concurrent sessions in one project dir can silently
   drop the earlier write — in any writer pairing: role-vs-member (e.g.
   `/setup roles` overlapping a session-start enrollment) or role-vs-role
   (two setup sessions each customizing a different role; the iteration-3
   cross-model pass re-derived this variant). The pattern is pre-existing in
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

4. **[P3, anchor-50, narrowed by iteration 2] `roster_write_role` verifies
   only the written role's block** — a pre-existing load-invalid hand edit
   elsewhere (e.g. a stray `[roles.reviewers]` or `[members.typo]` table —
   the iteration-3 cross-model pass re-derived the members variant) still
   parses at write time, so a write can succeed while `resolve_role` exits 5.
   Narrowed: the `/setup` Step 3/4 guard now runs `resolve_role`'s full load
   validation before any role work, so the guided flow catches this loudly
   BEFORE any write; the residual applies only to direct `roster_write_role`
   calls outside `/setup`. Full-file validation inside the writer would need
   `resolve_role` to accept an alternate roster path — a control-plane change
   deliberately deferred.

5. **[P3, anchor-50] Canonical-header requirement for block replace** — a
   TOML-valid header spelled `[roles.builder]  # comment` is not matched by
   the block finder; the write falls through to append and fails safe with a
   duplicate-table round-trip error (roster untouched, misleading message).

6. **[info] Interior same-line comments on replaced field lines are dropped**
   on first customize (e.g. the `# (High) suffix = agy effort control` notes
   in the shipped template) — replace semantics; trailing standalone comment
   blocks are preserved. Documented in the function header.
