---
description: How one task goes from assignment to main under a lease, with its own worktree, a reviewer who didn't build it, three fix cycles at most and the approvals left to you.
intro: Every task in a sprint is built under a lease, the lead's own tasks included. The lease gives the task its own git worktree and a row in the lead's ledger, and nothing from it merges until a reviewer who didn't build it approves.
---

## What a lease is

A lease is the lead's record of one task while it is built. Creating one sets up three things:

- a git worktree on its own branch, `lease/<task id>`, where the builder works;
- a row in `ops/leases.toml`, the ledger that only the lead writes;
- a builder, taken from the builder role in [`ops/roster.toml`](/guides/models-and-effort/), or from the next CLI in that role's fallback chain.

Any roster member can build: Claude Code, Codex, Antigravity, or an optional CLI you enrolled as a builder.

## One task, start to finish

1. The lead creates the lease for the task, with the builder the roster names.
2. The lead sends the builder the task and the context it needs: its rows from `ops/TASKS.md`, the part of `ops/CONTRACTS.md` it touches, and its roster entry. The builder works in its worktree and commits nothing. It runs on its own, so it keeps going when the lead's turn ends.
3. The builder's report has to end with a status line: `Status: DONE`, `DONE_WITH_CONCERNS`, `BLOCKED` or `NEEDS_CONTEXT`. When the builder finishes, the lead takes its own snapshot of the worktree and routes the task by that line. DONE and DONE_WITH_CONCERNS go to review, and BLOCKED and NEEDS_CONTEXT go back to the lead. A report with no status line counts as missing: the lead sends the task once more, and escalates if the second report is missing too.
4. The lead pins a reviewer, a roster member other than the builder. The lead can review any task another CLI built. `lease_merge` refuses a merge where the reviewer built the task, and one with no pinned reviewer. The pin holds for every fix cycle, across sessions too, so a new session can't swap reviewers. If no reviewer other than the builder is available, the task waits for you.
5. Once the reviewer approves, the task lands as one squash commit of the lead's snapshot on the sprint's integration branch. It never lands on main directly. Tasks merge in wave order, which may differ from the order they finished in.
6. When the whole wave is merged, the lead checks the integration branch (tests, build, lint) and promotes it to main.

## Three fix cycles at most

When the reviewer finds problems, the task goes back to the same builder with the findings, and the same reviewer checks the new version. That loop runs three times at most. After the third cycle the task escalates, and the lead stops to ask you.

## Protected paths

Some files control the pool itself. In every project these are `ops/roster.toml` with its `[promotion]` block, each CLI's config folder (`.claude/`, `.codex/`, `.agents/` and the others), and every `AGENTS.md`, `CLAUDE.md` and `.mcp.json` at any depth. A task that changes one of them is handled more strictly:

- Only the lead or you can review it. A review by another CLI alone doesn't count.
- It merges only with an approval of that exact snapshot, from the lead or from you. When the lead's own CLI built the task, the approval has to be yours.
- A fix cycle makes a new snapshot, and the new snapshot needs a new approval.
- Its promotion to main waits for your approval, even when the roster doesn't ask for one.

## Who approves what

| Decision | Who decides |
|---|---|
| Review a task | A roster member that didn't build it. The lead counts. |
| Review a task that changes a protected path | The lead or you |
| Approve merging that task | The lead, or you when the lead's CLI built it |
| Promote a checked wave to main | The lead |
| Promote a wave that changes a protected path | You |
| Promote anything while `require_user_approval = true` in `[promotion]` | You |
| A task after three fix cycles, or with no reviewer available | You |

The lead records your approval with `lease_approve` when you give it, or you run `lease_approve` yourself in a terminal. The record notes where it was made. A promotion approval covers the exact branch state you approved, and a later merge voids it.

## What a lease doesn't do

A worktree is where a builder starts. A builder with a shell can still change files outside it. The lead merges only the snapshot it took, and before every lease call it checks git config, hooks, refs, worktree pointers and the ledger. A change it didn't make stops all lease calls until someone reads it. A write anywhere else in your checkout goes unnoticed.

An approval record says who approved and from where. Any shell can write one, so treat it as an audit trail.

## Where leases run

[`at-build`](/skills/at-build/) runs the build phase as waves of leases, and [`at-ship`](/skills/at-ship/) runs that phase inside a whole sprint. The rules are in the [`wave-orchestration`](/skills/wave-orchestration/) skill. [Team builds](/guides/team-builds/) covers the builder pool and the review swarm.
