---
name: at-review
description: "Use when tasks marked [R] need Phase 3-4 review: parallel roster lanes and specialist reviewers, then synthesis."
argument-hint: "[--full] [--security] [--perf] [--simple] [--conventions]"
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Review (Phase 3 + Phase 4)

**Goal:** every task marked `[R]` in `ops/TASKS.md` reviewed by all applicable lanes at once (the analyst and reviewer roles from `ops/roster.toml`, shipped as Antigravity `architecture-reviewer` and Codex `logic_reviewer`; every enrolled optional member; the gated `learnings-researcher`; and the specialist reviewers the flags select), then synthesized by `findings-synthesizer` with confidence tiers (HIGH/MEDIUM/LOW) and priorities (P1/P2/P3), fixed through `iterative-refinement`, and recorded as per-cycle dispositions.

**Done when** `## Review dispositions — Cycle N` has been appended to `ops/TASKS.md` with one row per finding (`finding → fixed | dismissed-with-reason | deferred`) and either P1 = 0 and P2 = 0 (standard convergence) or the third cycle has ended and the user has been escalated to.

**Safe failure:** a lane that returns nothing stays visible, never silent. A failed integrity check, a `REVIEW_BASE` that names no commit, or a git call that fails stops the review before any lane starts. A helper failure fails fast (exit 1) instead of an empty `ops/REVIEW_*.md` reading as "no findings"; captured stdout is promoted only when the target file is absent and, for the agy lane, its status sidecar reads SUCCESS; an optional lane is promoted only when its helper exited 0 and the report says `Status: DONE` or `DONE_WITH_CONCERNS`, while a nonzero exit (reported with its code and reason), BLOCKED, NEEDS_CONTEXT or a missing report leaves no file. Prior-cycle `ops/REVIEW_*.md` are archived (never deleted) before dispatch so a stale file cannot pass as this cycle's result. rc 40 from a lane means the role resolved to the claude lane and runs as a sub-agent; it is not a failure. `ops/CONTRACTS.md` is never edited during review; propose the change in `ops/MEMORY.md` first. The user's instructions outrank this skill.

Invoked with `--full` (every lane plus `security-sentinel`, `performance-oracle`, `code-simplicity-reviewer`, `convention-enforcer`, `architecture-strategist`), or any of `--security`, `--perf`, `--simple`, `--conventions` to add that one specialist to the default; when absent, the default is the two core lanes only. For a small change (fewer than 3 files, obvious fix) `at-quick` self-reviews instead of running the swarm.

## Preflight

`$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`. Core-trio liveness is gated here, never at session start (fast `--version` checks, cached per session; on failure it names the member and its fix):

```bash
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
ensure_core_trio_live || exit 1
```

Then build the [review package](references/review-package.md). Its block opens with the lead's integrity check, which runs before the skill's own git calls. Only the locator's calls come earlier. They read no file content, and the one that reads the index runs with the fsmonitor off, so nothing planted in `.git/config` runs. If the block exits nonzero (44 means the git state changed outside the lead's operations), stop the review: report its message and rc, and run no other block. It prints `REVIEW_PKG=<dir>`. Set that on the learnings gate, core and optional blocks, and put the path in every sub-agent's prompt.

## Facts the tree does not tell you

- **Ceremony (S16):** read the `Ceremony:` line at the top of `ops/TASKS.md` before choosing lanes. `high-ceremony` forces the full swarm regardless of flags; `trivial` runs the default lanes; `standard` or no line follows the flags as given.
- **Trust rules (S6/S7):** the review package is the diff, the task rows, the `ops/CONTRACTS.md` slice and the acceptance criteria; a dispatch never pre-judges a finding; builder output is a claim; dispositions are append-only. [Trust rules](references/trust-rules.md).
- **Core lanes** go through `dispatch_role analyst` and `dispatch_role reviewer` so a roster override takes effect, each with the review package in its prompt. The fresh-cycle archive, per-PID waits, promotion of captured output and the Codex structured-verdict fold are in [dispatch](references/dispatch.md). Promotion never takes a BLOCKED or NEEDS_CONTEXT report, takes an optional CLI in a core role only on DONE or DONE_WITH_CONCERNS, and reads the CLI's final answer, never its tool output.
- **Optional lanes** run for every `[members.<cli>] enabled = true` and for an optional CLI named as the reviewer primary, each with the review package in its prompt (their read class cannot run git), and each writing `ops/REVIEW_<CLI>.md` under the typed-Status promotion rule: [optional lanes](references/optional-lanes.md).
- **Gated learnings-researcher (C4):** spawned only when an `ops/solutions/` entry names a changed module (a name-and-path grep over the package's inventory, no model call, no git): [learnings gate](references/learnings-gate.md).
- **Specialist reviewers** run as sub-agents launched together in one round; the harness mechanics and the rc 40 fallback: [Claude](references/claude.md), [Codex](references/codex.md).
- **Phase 4:** synthesis inputs, fix order, the dispositions block, convergence and the re-trigger on changed files only: [synthesis](references/synthesis.md).

## Output

- `ops/REVIEW_ANTIGRAVITY.md` and `ops/REVIEW_CODEX.md` (the structured verdict appended when the Codex lane emitted one), plus `ops/REVIEW_<OPENCODE|KIMI|CURSOR|DEVIN|GROK>.md` for each optional lane that exited 0 and reported DONE or DONE_WITH_CONCERNS; prior cycles under `ops/archive/reviews/<timestamp>-<pid>/`.
- The review package for the cycle (`REVIEW_PKG`), removed once the cycle's synthesis is done.
- The learnings-gate line (the matched `ops/solutions/` entries, or "skipped") and, when spawned, the known-issue context handed to `findings-synthesizer`.
- The synthesized report (confidence tier and priority per finding), the P1 and P2 fixes applied, P3 items logged for later.
- `## Review dispositions — Cycle N` appended to `ops/TASKS.md`, and the convergence verdict or the escalation after 3 cycles.
