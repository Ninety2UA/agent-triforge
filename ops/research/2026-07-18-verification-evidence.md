# v3.0.0 Verification Contract — captured evidence

**Purpose:** satisfies Definition of Done bullet 1 ("every Verification Contract
gate green and its evidence captured in `ops/research/2026-07-probe-record.md`
or the release notes"). This file is the release-notes evidence companion to the
probe record. Each gate below names the dogfood that exercised it and the
observed result. Dogfoods ran in disposable fixtures under `${TMPDIR}` against
the real CLIs (or the documented test seam where a live model call is not the
thing under test); the repo tree was never mutated by a dogfood.

**Host reality (read this first — it scopes two gates):** on the maintainer
machine at capture time the core trio (Claude Code, Antigravity `agy`, Codex) is
fully live and authenticated, and Cursor is logged in. **OpenRouter is not
connected** (OpenCode's shipped default provider) and **Kimi is not signed in**.
The two affected adapters are therefore verified structurally + through their
deterministic auth-failure paths, not through a live provider round-trip — the
optional tier is designed to degrade exactly this way (AE1/R21), and enrollment
records intent while readiness is a separate, per-host concern. See gates
"E2E build" and "Degradation" below.

## Gate-by-gate evidence

| Gate | Result | Evidence |
|---|---|---|
| Probe record | **PASS** | `bash scripts/probe-capabilities.sh` regenerates `ops/research/2026-07-probe-record.md` (47+ rows across all six CLIs, credential-isolated fixture, sentinel escape detection, fail-closed timeout preflight). Re-run 2026-07-18 to refresh AGY-12/13 and the CC-06 validate row. |
| READY probes | **PASS (core trio + Cursor); AUTH-scoped (OpenCode/Kimi)** | Core trio + Cursor round-tripped READY live (AGY-04, CDX-03, CC-02/03, CUR-04 PASS). OpenCode READY worked via its default provider (OC-03 PASS); the OpenRouter GLM pin AUTH-FAILs on this host (OC-04). Kimi AUTH-FAILs (KIMI-05: "No model configured / use /login"). Both are host-auth gaps, not adapter defects. |
| Plugin validity | **PASS** | `claude plugin validate --strict .` → "✔ Validation passed" on the current tree. |
| E2E review | **PASS** | Live `invoke_antigravity "architecture-reviewer"` found all three planted bugs in a sample file and the resilience path promoted them into `ops/REVIEW_ANTIGRAVITY.md` (U4). Live `invoke_codex "logic_reviewer"` with `--output-schema` emitted a schema-valid verdict JSON — 2 findings, severities [P1,P2], confidences [HIGH,HIGH] — catching a SQL-injection P1 and a resource-leak P2 (U7). |
| E2E build | **PASS (with 1 non-Claude builder)** | U9 live codex lease dogfood: `lease_create → lease_dispatch` (real codex builder in an isolated worktree) `→ lease_collect` (state=review) `→ lease_merge <task> claude` produced the single squash commit `lease(live): merged from codex, reviewed by claude` (sha 207c257) with `hello_lease.txt`=`LEASED` landing in the main tree. U10 two-task wave dogfood: task1 + task2 both built by **codex** (non-Claude), each cross-reviewed by **claude** (non-author), landed as two squash commits (7ad6a65, b080e92) on the `sprint/dogfood` integration branch; CHANGELOG rows carried builder+reviewer+merge-commit from the ledger; `lease_status` showed both merged. A live OpenCode/Kimi builder was not run (OpenRouter/Kimi auth gap above); the non-Claude-builder requirement is met by codex. |
| Kill-and-recover | **PASS** | U9 lifecycle harness: SIGKILL a mid-lease builder → heartbeat expiry marks orphaned → `lease_reclaim` prunes the worktree → `lease_requeue` re-leases to a **different** builder (codex → antigravity, via the fallback chain) → a second failure escalates. Ledger round-tripped tomllib-parseable after every transition. 23/23 scenarios green. |
| Negative permissions | **PASS** | Read-only/reviewer roles reject writes per CLI: CDX-08 (codex read-only sandbox rejects a write), CUR-08 (Cursor `--mode plan` refused to modify a file, live: "Plan mode is read-only, so I won't modify scratch.txt"), OpenCode reviewer permission-map denies edit/bash (no `--auto` in the review lane). Builder confinement: `_adapter_env` forwards ONLY the adapter's own credential var (verified under zsh: claude/codex/antigravity get no provider keys; opencode→OPENROUTER, kimi→KIMI, cursor→CURSOR — no cross-provider leak). Lease worktree confinement: a codex builder wrote only inside its TMPDIR-rooted worktree, not the main tree. |
| Capability parity | **PASS** | CC-03 (/goal hard-gates a multi-condition checklist in `claude -p`, live: created both required files then completed) → ship-loop retirement is safe. CC-04 (dynamic workflows express external-CLI dispatch + requeue + pinned reviewer — U10's wave is the live composition). CC-05 monitors parity NOT demonstrated → both watcher hooks correctly retained (KTD-7 fallback; 4 hooks, no doc claims monitors replaced them). |
| Degradation | **PASS** | AE1: with an optional CLI absent, `resolve_role` skips it silently and lands on an available fallback member with no error (verified: cursor-absent PATH → reviewer fallback resolves to codex, empty stderr). A member with `enabled=false` is treated as absent everywhere and re-included by the flag flip alone (AE7). A `/status`-only session never triggers the liveness probe. |
| Guided setup | **PASS** | U17 live `/setup` dry pass on this host: trio liveness gate → per-optional-CLI enrollment (cursor auth=ok enrolled grok-4.5; opencode + kimi auth-failed with the exact login fix named) → six-row status table. Install offer for an absent CLI printed `curl https://cursor.com/install -fsS \| bash` and never executed it (rc=10). Enrollment persisted byte-identically across two real `session-start.sh` runs (idempotent, no re-ask). |
| Watch first runs | **PASS** | `/cli-watch` and `/repo-watch` ran as their first live runs (U15): `ops/research/2026-07-18-cli-updates.md` (May-template shape, 31 cited probe IDs), `ops/decisions/2026-07-18-cli-deprecation-watch.md` (D-004 ratified + D-009..D-019), `ops/research/2026-07-18-repo-mining.md` (27 candidates, each with Why/Concrete change/Verification/verdict, zero adoption code — R31). No registry targets unreachable. Their friction fixed U14 before release (registry resolver, SSRF gate, agent-type, probe-rerun). |
| Doc consistency | **PASS** | Ladder byte-identical across the 4 canonical locations (md5 `25fe366c…`); no live gemini/ship-loop/single-writer refs outside the marked historical changelog + migration notes; counts correct (19 agents, 13 skills, 19 commands, 4 hooks); prerequisites list all six CLIs with tiers + READY probes. Only residual: `docs/images/*.svg` labels (cosmetic, documented). |

## R35 confinement — the honest boundary

Three sandbox probes recorded FAIL: `agy --sandbox` (AGY-10), OpenCode deny-under-`--auto` (OC-06), Cursor `--sandbox enabled` (CUR-07) each let a write escape. **This is expected and handled — R35's per-builder confinement does not rely on those flags.** The actual boundary is, in layered order:

1. **Per-task git worktree isolation** — every non-lead build runs with cwd = its own worktree; the builder never sees the canonical `ops/` tree (KTD-3).
2. **Per-adapter environment allowlist** — `_adapter_env` execs the builder under `env -i` with only base vars + the adapter's own credential (KTD-14) — verified no cross-provider leak, under both bash and zsh.
3. **Flag avoidance** — the adapters never pass the escaping flags: the Antigravity lane never passes `--dangerously-skip-permissions` (AGY-09 showed deny rules don't survive it), the OpenCode review lane never passes `--auto` (OC-06), the Cursor reviewer uses `--mode plan` (CUR-08 PASS, a real read-only mode) rather than `--sandbox`.
4. **Codex native sandbox** — the one adapter with a working sandbox uses `-s read-only`/`-s workspace-write` plus the TMPDIR-exclude tuning so a builder cannot cross out of its worktree.

Docs describing "sandbox" confinement for the optional tier should be read as this layered isolation, not vendor `--sandbox` enforcement.

## Provider data-egress (R36) at a glance

Code + task context reaches: Anthropic (Claude), Google (Antigravity/Gemini Pro), OpenAI (Codex), and — when the optional tier is enrolled and authenticated — OpenRouter (intermediary) → Zhipu/Z.ai (GLM) for OpenCode, Moonshot (Kimi K3), and xAI (Grok, via Cursor). `ops/roster.toml` restricts which members — and therefore which providers — are eligible. Credentials live in OS/vendor stores, are passed per-adapter only, and captured output is scrubbed before landing in any committed `ops/` file (KTD-14).
