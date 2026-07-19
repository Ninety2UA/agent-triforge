# Session state
<!-- Saved: 2026-07-18 -->
<!-- Type: wrap (v3.0.0 implemented + 3 review loops converged; PR opened) -->

## Current phase
v3.0.0 CLI-modernization + builder-pool: COMPLETE. All 17 units implemented,
3 review→fix→verify loops + a convergence-confirmation pass run to a stable
5/5, PR opened from `feat/cli-modernization-builder-pool` → `main`.

## What shipped (branch: feat/cli-modernization-builder-pool, 21 commits)
- Antigravity (`agy`) replaces the retired Gemini lane (U2-U4); native-first
  /goal + sentinel completion (U5); Claude ladder fable+max→…→sonnet+high (U6);
  Codex gpt-5.6-sol + structured verdicts + hooks-under-exec (D-004 flip, U7).
- Six-CLI builder pool: ops/roster.toml drives all 5 roles via resolve_role +
  dispatch_role (U8); lease ledger + worktree lifecycle + lease_promote gating
  (U9); wave protocol with pinned cross-review + integration branch (U10);
  OpenCode/Kimi/Cursor optional adapters (U11-13); /setup onboarding (U17).
- Watch family /cli-watch + /repo-watch + registry (U14); first-run cycle ADR +
  four-repo mining report (U15); v3.0.0 release docs + migration (U16).

## Review-loop outcome (5/5)
- Loop 1: fixed 2 P1 (zsh-dead builder pool; codex eval injection) + 2 breaks
  (roster drove only builder → dispatch_role + dead-code kill; promotion/
  protected-path prose-only → lease_merge guard + lease_promote).
- Loop 2: /setup zsh glob crash + errexit-on-source; protected-path completeness.
- Loop 3: parallel-wave heartbeat zsh word-split; pre-compact phase anchor;
  ledger mkdir-lock. zsh-portability bug class exhaustively swept clean.
- Loop 4 (convergence): CLEAN — ~76 live zsh assertions, 0 new defects.
- Evidence: ops/research/2026-07-18-verification-evidence.md (gate-by-gate).

## Known residuals (documented, non-blocking)
- docs/images/*.svg still label "Gemini" (cosmetic, fixed-size exports).
- OpenRouter + Kimi unauthenticated on the maintainer host → those two adapters
  verified structurally + via their deterministic auth-fail paths (degradation
  by design; core trio + Cursor are live-verified).
- agy 1.1.3 native plugin-agent discovery not functional headless → injection
  fallback operative (AGY-12/13 FAIL; flips to PASS when agy ships listing).

## Next actions (post-merge, follow-up sprints)
- Repo-mining adoptions (ops/research/2026-07-18-repo-mining.md: 17 adopt-in-
  follow-up candidates) after user approval.
- Re-probe agy on 1.1.4+ (shipped 2026-07-18: headless settings.json
  enforcement may flip AGY-08/09/10 — see the cycle ADR open watches).
