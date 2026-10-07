# Output shapes

What the watch reports and the ADR hold, stage by stage. Match the May-cycle report (`ops/research/cli-updates-2026-05.md`) and ADR (`ops/decisions/2026-05-12-cli-deprecation-watch.md`).

## Stage 3 — per-target changelog

- **CLIs:** a `Date | Version | Feature | Category | Source` table. Categories: `command | flag | config | agent-primitive | mcp | context | hook | fs-convention | breaking | perf`. Omit UI, voice and telemetry-only noise. Tag pre-release rows. Every row cites a primary-source URL.
- **Repos:** the commits, releases and docs since the window start, distilled to *patterns a plugin like Triforge could adopt*, not a raw diff. Cite the file, commit or PR.

## Stage 4 — gap table vs current Triforge

- **CLIs** (`ops/research/cli-updates-2026-05.md` §3 shape): `Feature | CLI | Used in Triforge? | Action | Reasoning`, where Action ∈ {Adopt, Evaluate, Keep, Verify, Skip}.
- **Repos** (May "top-N candidates" shape): a prioritized list of candidates, each with **Why** (the gap it closes), **Concrete change** (the exact files and edit Triforge would make) and **Verification** (how you'd prove it works).

## Stage 5 — adopt/defer verdicts

**`/cli-watch`** writes the ADR matching `2026-05-12-cli-deprecation-watch.md`:

- One `D-xxx` decision per candidate with an explicit **ADOPT / DEFER / DOCUMENT** verdict and its reasoning (cite the affected Triforge file). When a new probe reverses a prior verdict, supersede it explicitly (as `ops/decisions/2026-07-18-codex-hooks-under-exec.md` supersedes D-004); never contradict it silently.
- A **Verification record** probe table: `Probe | Outcome | Date | Method`.
- An **Open watches** table: `Risk | Source | Trigger to revisit`, so the next cycle knows what to re-check.

**`/repo-watch`** keeps its verdicts in the report itself: each candidate carries an explicit **ADOPT-in-follow-up / DEFER** verdict. These are recommendations for a later, user-approved sprint; `/repo-watch` never edits source to adopt a pattern and never opens an ADR.

## Stage 6 — closing the report

The report ends with a **Sources appendix** (every endpoint the workers and the lead read) and a **cross-checks performed** list: random source re-verification, window coverage, gap-table grounding, pre-release flagging.

## Flagged targets

Every target that is dead, renamed, unreachable or fails validation, and every worker that failed or returned nothing, gets a row:

```markdown
### Flagged targets (continue-and-flag)
| Target | Registry URL | Problem | Evidence | Suggested registry fix |
|---|---|---|---|---|
| repo.example | https://github.com/org/example | 404 (repo deleted/renamed) | gh api 404 at <date> | update url or remove entry |
```
