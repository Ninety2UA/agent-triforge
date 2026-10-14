[← Agent Triforge](../README.md#documentation)

# Team work and swarms

Work fans out in two shapes. In team work each task goes to one builder in its own lease and worktree, and the lead merges the results one task at a time. In a swarm several read-only lanes look at the same input through different lenses, and a synthesizer merges what they report.

## The builder pool

A wave reads [`ops/roster.toml`](../templates/ops/roster.toml), leases each task to a builder CLI in its own git worktree, and merges a task only after a pinned reviewer who did not build it approves. The lead then promotes the sprint integration branch to `main` through a protected-path gate.

<p align="center">
  <img src="images/builder-pool.png" alt="The builder pool: the lead leases each task to a roster builder in its own worktree, then cross-review, the integration branch, a wave check and promotion to main." width="90%">
</p>

The roster decides who does what. Five roles (builder, reviewer, tester, analyst, documenter) each map to a CLI, a model and an effort, with an ordered fallback chain that must end at a core-trio member. The shipped posture has Claude building, Codex reviewing and testing, and Antigravity analyzing and documenting; the roster can override any of it. Optional members carry an `enabled` flag and are absent everywhere when it is off. The shipped pins put the newest Gemini at its highest thinking level on `agy` (`"Gemini 3.8 Flash (High)"` today, Pro or Flash, whichever is newest; D-022) and `cursor-grok-4.6-xhigh` on Cursor. [Model and effort](models.md) has every pin and how to change it, and `at-setup`'s role step walks keep current, customize or restore the shipped defaults with validated writes.

Every builder runs under a lease. The lead-owned ledger `ops/leases.toml` (runtime state) tracks each task through its lifecycle, with heartbeat-based orphan detection, a single requeue to a different builder, and escalation when a task can't converge. The pinned reviewer gets at most 3 fix cycles with the builder before the task escalates to you, and an approved task lands as one squash commit of the lead's own snapshot on the sprint integration branch.

<p align="center">
  <img src="images/lease-lifecycle.png" alt="One task's lease from lease_create to lease_promote: dispatch, wait, collect, a pinned review and the squash merge, with the points where it escalates." width="90%">
</p>

Three mechanisms keep this safe, and none of them restricts who may write code:

- Per-task worktrees with lead-side checks. A builder starts in its own worktree and is contracted to stay out of the canonical `ops/` tree. The worktree limits where it starts, not where it writes, so the lead detects changes to git state and the ledger and merges only its own collect snapshot. It detects those changes without preventing them, and it does not see a write elsewhere in the main checkout.
- A per-adapter environment allowlist. No builder receives another provider's credential environment variables; credential files under `$HOME` are shared.
- Mandatory cross-review before any merge. No agent merges its own build.

## Four coordination modes

| Mode | Mechanism | When to use |
|---|---|---|
| File-based | Shared markdown in [`ops/`](../ops/) | Persistent state across sessions, audit trails |
| Direct invocation | `agy -p` / `codex exec` via bash | Real-time external agent delegation |
| Personas | `dispatch_persona` runs a [`personas/`](../personas/) prompt with the tools, model and turn budget its manifest entry sets | Reviews, research, verification |
| Agent teams | Multi-Claude with shared task lists ([`team-lead`](../personas/team-lead.md)) | Complex builds with 5+ interdependent tasks |

## Wave Orchestration (`at-build`)

[`at-build`](../skills/at-build/SKILL.md) groups the plan's tasks by dependency into waves. Independent tasks within a wave run in parallel, each in its own lease and worktree, and tasks that modify the same files never share a wave. An [`integration-verifier`](../personas/integration-verifier.md) runs the tests, build and lint between waves. Each task merges after its pinned review as one squash commit, in wave order, and after the check `lease_promote` takes the result to the main branch through the promotion gate.

<p align="center">
  <img src="images/wave-orchestration.png" alt="Three dependency-ordered waves of leased tasks, with an integration-verifier check between waves and promotion to main after the last one." width="90%">
</p>

## Review Swarm (`at-review`)

[`at-review`](../skills/at-review/SKILL.md) starts every lane at once. The two core lanes always run: Antigravity's `architecture-reviewer` (architecture, design) and Codex's `logic_reviewer` (logic, security, tests). Every optional member you have enrolled reviews too. The flags add specialist personas: `--security`, `--perf`, `--simple` and `--conventions` add one each, and `--full` runs all five, with [`architecture-strategist`](../personas/architecture-strategist.md) as the fifth. [`learnings-researcher`](../personas/learnings-researcher.md) joins when an `ops/solutions/` entry names a changed module. A [`findings-synthesizer`](../personas/findings-synthesizer.md) then merges and deduplicates every `ops/REVIEW_*.md`, giving each finding a confidence tier and a priority (P1, P2, P3). The lead fixes P1 and P2, logs P3, and escalates to you after 3 cycles without convergence.

<p align="center">
  <img src="images/review-swarm.png" alt="The review swarm: core lanes, enrolled optional members and flagged specialists review at once, then findings-synthesizer merges and ranks what they found." width="90%">
</p>

### Confidence tiering

Every finding gets a confidence score, so nobody spends time on phantom issues:

| Tier | Criteria | Rule |
|---|---|---|
| HIGH | Verified in codebase via grep/read. Deterministic. | Can be any priority |
| MEDIUM | Pattern-aggregated detection. Some false positive risk. | Can be any priority |
| LOW | Requires intent verification. Heuristic-only. | Can never be P1 |

### Suppressions

Each reviewer has a "Do Not Flag" list to reduce noise: readability-aiding redundancy, documented thresholds, sufficient test assertions, consistency-only style changes, and issues already addressed in the current diff. Each persona file in [`personas/`](../personas/) lists its own suppressions.

## Deep Research (`at-deep-research`)

[`at-deep-research`](../skills/at-deep-research/SKILL.md) runs five research lenses in parallel before planning: past solutions and decisions, current framework docs for the stack, git history, Antigravity's targeted codebase analysis, and industry practice. [`research-synthesizer`](../personas/research-synthesizer.md) merges them into one research brief that lists contradictions without resolving them, and hands off to `at-plan`.

<p align="center">
  <img src="images/research-swarm.png" alt="The research swarm: five lenses research in parallel, and research-synthesizer merges them into one brief for at-plan." width="90%">
</p>

## The knowledge loop (`at-compound`)

After a non-trivial problem is solved, [`at-compound`](../skills/at-compound/SKILL.md) records it in [`ops/solutions/`](../ops/solutions/), or a decision in [`ops/decisions/`](../ops/decisions/), when it clears the counterfactual bar: a future agent without the note would repeat the mistake or work the decision out again. Otherwise it says in one line why it wrote nothing. Before new work is planned, [`learnings-researcher`](../personas/learnings-researcher.md) searches both directories.

<p align="center">
  <img src="images/knowledge-loop.png" alt="The knowledge loop: solve a problem, record it with at-compound, store it in ops/, and search it before the next plan." width="90%">
</p>
