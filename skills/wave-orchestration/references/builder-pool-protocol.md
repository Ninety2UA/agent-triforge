# Builder-pool wave protocol

The per-task mechanics the core skill points at. Every command below comes from `$ROOT/scripts/invoke-external.sh`; `ROOT` is the Triforge plugin root: `${CLAUDE_PLUGIN_ROOT:-$ROOT}` under Claude Code, and from any other lead the path the `at-` skill's locator printed.

Every implementation task in a wave — INCLUDING lead-authored ones — is built under a per-task lease and merges only after cross-review by a pinned non-author reviewer. The single-writer rule is retired: any roster member (claude, codex, antigravity, and any enrolled optional member) is an eligible builder. Safety comes from three mechanisms, not from write-restriction: per-task leases in their own git worktrees, a lead-owned ledger (`ops/leases.toml`), and mandatory cross-review before merge (AE3, KTD-10). A worktree is where a builder starts, not a sandbox: the dispatch contract keeps it inside its worktree and out of the canonical `ops/` tree (KTD-3), and nothing enforces that. The lead merges only the snapshot it took at collect (KTD19) and detects changes to git state and the ledger (see the integrity-escalations reference); a builder's write to any other file in the main checkout, including the rest of `ops/`, goes undetected. This protocol layers onto every execution mode: the default sub-agent mode and the Claude Code forms in the claude reference.

Assignment reads `ops/roster.toml` per task's role via `resolve_role` (the roster maps builder | reviewer | tester | analyst | documenter → CLI + model + effort, with validated fallback chains). The lead injects context and performs all `ops/` mutations and merges on the main tree; builders run in their own worktrees under the dispatch contract.

## Contents

- [The per-task loop](#the-per-task-loop)
- [Integration branch and promotion gate](#integration-branch-and-promotion-gate)
- [Attribution](#attribution)
- [Merge in wave order](#merge-in-wave-order)
- [Common rationalizations](#common-rationalizations)

### The per-task loop

Source `$ROOT/scripts/invoke-external.sh`, then for each task:

1. `lease_create <task_id> <role>` — resolves the builder from the roster, carves an isolated worktree + `lease/<task_id>` branch, provisions `.agents/skills/`, writes the `leased` row with the provisioned paths (`provisioned`), which `lease_collect`'s snapshot leaves out. Every lease_* writer and the roster writers are lead-only: run by a worker (`_adapter_env` sets `TRIFORGE_LEASE_WORKER=builder`, or `persona`) or from a directory under the lease root they refuse with rc 45, and the plugin's hooks exit at once under the marker, so a worker never runs lead machinery or leaves bootstrap residue (KTD9).
2. `lease_dispatch <task_id> <prompt> [timeout]` — the lead injects context (the task's TASKS.md rows, the relevant CONTRACTS.md slice, the roster entry) into the prompt; the builder runs in the BACKGROUND in its worktree under a per-adapter env allowlist. The builder commits nothing.
3. `lease_heartbeat_check [task_id]` — sweep until the builder exits. Orphan / timeout / silent-death handling reclaims the lease and requeues it ONCE to a DIFFERENT builder via `lease_requeue <task_id>` (KTD-9), or escalates; a deterministic failure (auth, absent CLI) fails fast with guidance and does NOT requeue.
4. `lease_collect <task_id>` — lead-side harvest. A clean exit is routed by the builder's final typed report (KTD11): `Status: DONE` / `DONE_WITH_CONCERNS` → state `review`, output path printed, the builder's "Discoveries for later tasks" copied into `ops/MEMORY.md`; `Status: BLOCKED` / `NEEDS_CONTEXT` → state `escalated`, never review (the lead reads the report, supplies the missing context or rules on the blocker, and re-dispatches through the requeue path); no `Status:` line → rc 80, report-missing (the failure-handling reference). A clean exit is never review-ready on its own.
5. **Pin the reviewer** — `lease_pin_reviewer <task_id> <reviewer>`. Choose a reviewer that is a DIFFERENT roster member than the lease's `builder_cli`. The lead is a valid reviewer for any task built by a *different* CLI — but a task built by the lead's own CLI needs a reviewer from another roster member (under a Claude lead the `reviewer` role default, Codex, provides this), because the AE3 guard correctly refuses `reviewer == builder_cli`. `lease_pin_reviewer` records the choice in the ledger so it stays this task's reviewer for ALL ≤3 fix cycles **even across a session boundary** (KTD-10): a fresh session cannot silently re-pin, and `lease_merge` refuses any reviewer that does not match the pin. Self-review is never allowed; **if no non-author agent is live, the merge blocks and escalates to the user.**
6. **Review the collected output**, then:
   - **Approved →** `lease_merge <task_id> <reviewer>` — squashes the snapshot `lease_collect` took (the lead's own commit of the worktree on the recorded base) as ONE commit on the sprint integration branch, records reviewer + merge_commit in the ledger, and reclaims the worktree. It refuses a lease branch that moved after collect or carries commits the builder made itself (naming the commit), a worktree changed after collect, and a diff touching `ops/` (naming the file) — KTD19. Review against the snapshot: anything that writes files in the lease worktree after collect (a reviewer running tests or a formatter there) makes the merge refuse. `lease_merge` REFUSES unless (a) `<reviewer>` is a known adapter identity (a fabricated label like `codex-reviewer` is rejected), (b) it differs from `builder_cli` (AE3 — self-review never merges), and (c) that reviewer was already pinned in step 5 — **the pin is the record that a review happened, so a merge with no pin is refused.** Pin, review, then merge.
   - **Findings, cycle < 3 →** `lease_redispatch <task_id> <prompt-with-findings> [timeout]` re-dispatches the SAME lease's task to the SAME builder with the reviewer's findings appended, keeping the SAME pinned reviewer; it increments `review_cycle` and returns the lease to `building` (state transition `review → building`). This is the ONLY path from `review` back to `building` — `lease_dispatch` requires `leased`, `lease_requeue` requires `requeued`.
   - **Cycle 3 reached →** `lease_redispatch` escalates instead of re-dispatching: it sets state `escalated` and returns a distinct code so the lead pauses for the user (KTD-10 / max 3 review cycles per task).

### Integration branch and promotion gate

Approved merges land as one commit per task on a **sprint integration branch**, never directly on the main branch (`lease_merge` REFUSES to run when the main tree is checked out on the default branch — cut an integration branch first). At wave end, the integration-verifier gate (Step 3 Verify) runs against the integration branch — combined verification across the wave's merged tasks — BEFORE the lead promotes to the main branch via **`lease_promote`** (the actual promotion mechanism).

Promotion honors the KTD-5 `[promotion]` gate in `ops/roster.toml`: `lease_promote` reads `require_user_approval` (default `false`) — when true, it BLOCKS and the lead pauses for explicit user approval before promoting. `lease_promote` has no approve flag: once the user approves, promote by hand (`git checkout <default> && git merge <integration>`) and run `lease_rebaseline` straight after, or the next lease call returns 44 because the default branch moved.

**Protected-path override.** Any task whose diff touches a protected path forces the promotion gate ON regardless of the knob, AND requires the lead or the user as the cross-reviewer — never an external-CLI-only review. The lists live in `$ROOT/scripts/lib/registry.sh`. In every project they cover `ops/roster.toml` (including its `[promotion]` block); each CLI's config and permission tree (`.claude/`, `.codex/`, `.agents/`, `.antigravity/`, `.gemini/`, `.opencode/`, `.kimi-code/`, `.cursor/`, plus `opencode.json`, `opencode.jsonc` and `.cursorrules` at the root); and every `AGENTS.md`, `AGENTS.override.md`, `CLAUDE.md`, `CLAUDE.local.md` and `.mcp.json` at any depth. In the Triforge checkout they also cover the framework's own control plane. This keeps a builder from self-promoting a change to the very controls that govern the pool. `lease_promote` enforces the gate: it scans the integration diff against those lists and BLOCKS (rc 42, no merge) on any match, even when `require_user_approval = false`. The scan is case-folded, sees both sides of a rename, and matches a protected directory's bare name (a symlink in its place); it fails closed: if the scan itself errors, promotion is blocked too. The reviewer rule is yours to keep, because `lease_merge` does not check it: review such a task yourself; if you built it (the pin cannot be your own CLI), pin a non-author CLI so it can merge, and leave the protected-path review to the user at the rc 42 block.

### Attribution

Every merged task's `ops/CHANGELOG.md` row carries **builder + reviewer + merge commit**, read from the ledger (`lease_status`, or the row's `builder_cli` / `reviewer` / `merge_commit` fields). Attribution is mandatory — the ledger is the source of truth for who built and who reviewed each commit. The ≤3-cycle review escalation and the same-error kill criteria (the failure-handling reference) both still apply.

### Merge in wave order

Merge in wave order, never completion order. Within a wave, merge approved tasks in their TASKS.md order; a task that finishes and passes review early waits for its predecessors in the wave, so the integration branch history reads as the plan and a dependency violation cannot hide behind a fast builder. A later wave never merges before the earlier wave has fully merged and passed integration verification. If a predecessor is still in a fix cycle, the approved task waits; if the predecessor escalates or is cut, the lead rules on whether the wave proceeds without it and ledgers the ruling.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "I built it, I know it is right, I can merge it" | Self-merge is refused by `lease_merge` (AE3). Pin a non-author reviewer. |
| "No reviewer is live, so I will skip the pin this once" | A merge without a pin has no record that a review happened. Block and escalate. |
| "T3 finished first, merge it now" | Merge in wave order. Completion order makes the integration history unreadable and hides dependency violations. |
| "The builder's output looks complete, send it to review" | No `Status:` line is report-missing, not done. Re-dispatch with the contract restated. |
| "This decision needs the user, park the sprint" | Unless it is one of the four hard stops, rule, ledger the `Ruling:` line, and continue. |
| "The verify step is slow, start the next wave in parallel" | A next wave on an unverified branch builds on unknown state. Verify, then dispatch. |
| "The retry will work if I just run it again" | Answer the reflection questions first. The same approach three times is a kill criterion. |
