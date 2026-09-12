---
name: verification-before-completion
description: "Evidence-gated completion checklist with an Iron Law, a gate function, and a claim-to-evidence table. Use when about to claim a task, wave, or sprint is done, before moving a task to Done in ops/TASKS.md, before writing the ops/.sprint-complete marker, or before reporting Status: DONE from a lease. Also use for documenter, analyst, and research work that has no test command. Not for planning the work; that is writing-plans."
metadata:
  triforge-consumer: "All"
  triforge-phase: "every task completion; 6 (wrap-up)"
  version: "3.3.0"
---

# Verification Before Completion

## The Iron Law

> No completion claim without fresh verification evidence.

"Fresh" means produced by a command or observation you ran after the last change, in this session, and read in full. A claim is any statement that work is done, tests pass, a bug is fixed, a migration applied, or a document matches the code. Memory of an earlier run, a builder's self-report, and a diff that looks right are not evidence.

## The gate function

Run this before every claim, in order. Do not skip a step because the answer feels obvious.

1. **Identify the claim.** Write the exact sentence you are about to state ("the full suite passes", "the migration is applied", "the docs match the flags").
2. **Name the proof.** Name the command or observation whose result would prove that sentence, and what a failing result would look like.
3. **Run it.** Execute the command now, after the last change, against the tree you are about to hand over.
4. **Read the result.** Read the whole output: exit code, totals, skipped items, warnings. A green summary line above a red section is a failure.
5. **State the claim with the evidence quoted.** Only now state the claim, and quote the command and the output lines that prove it. If the result does not prove the claim, say what it does show and stop there.

If any step cannot be completed, the claim is not made. Report the gap instead ("not verified: no command reproduces the bug on this host").

## Claim, evidence, and what is not enough

| Claim | Requires | Not sufficient |
|---|---|---|
| Tests pass | The full suite run after the last change, with the exit code and totals quoted | Running only the new tests; a run from before the last edit; a builder's "all green" line |
| Bug fixed | Red-green-revert: the reproduction fails on the old code, passes on the fix, and fails again when the fix is reverted | The symptom not appearing once; a fix that should cover it |
| Regression test works | Red-green-revert, with the test's failure message naming the behavior it guards | A test that passed the first time it ran |
| Feature works | The feature exercised end to end through its real entry point, with the observed output quoted | Unit tests alone; reading the code; a screenshot from an earlier build |
| Migration applied | The schema or data queried after the migration and the result quoted; the rollback tried on a scratch copy | The migration file existing; the migration command exiting 0 |
| Docs match code | Every documented command or flag executed as written, and every documented name grepped in the source, with hits quoted | Rereading the docs for style; the docs and code changing in the same commit |
| Refactor preserves behavior | The pre-refactor tests (or characterization tests) unchanged and green, and the VCS diff shows only intended changes | "The logic is equivalent"; new tests written alongside the refactor |
| Builder completed | The VCS diff read by the lead shows the change, and the builder's final Status line parsed | The builder's prose report; a clean exit code |
| Lint clean | The linter run on the changed files with zero findings quoted | The editor showing no warnings |

## When there is no test command

Documentation, analysis, configuration, and research tasks have no suite to run. The gate still applies; only the shape of the proof changes. Pick the strongest available and record the exact command and its output:

- **Smoke run.** Execute the artifact the way its consumer will: run the documented command, load the config with its real parser (`bash -n`, `python3 -c 'import tomllib; ...'`, `python3 -c 'import json; ...'`), render the page.
- **Grep.** For every name, path, flag, or version the artifact asserts, grep the source for it and quote the hit or the miss.
- **Parser.** Feed the artifact to whatever reads it downstream (the skills validator, the plugin validator, a schema check) and quote the result.
- **Manual reproduction.** Follow the artifact's steps yourself on a clean checkout or a scratch directory and record what happened at each step.
- **Re-open the artifact.** Open the finished file, name each section the task required, confirm each is present, and check that its totals reconcile with the sources. "Complete" and "right" are separate claims; verify both.

Record the evidence in the same form as a test run: the command, the output lines that prove the claim, and the commit or file state it ran against.

## Red Flags

Stop and run the gate function when you notice any of these:

- You are about to write "should work", "should pass", or "looks correct".
- The last test run happened before your most recent edit.
- You are relying on a builder's or reviewer's summary instead of the file or the diff.
- You are quoting a count you did not read from output.
- The command you ran is not the one the task named in its `Accept:` field.
- You feel pressure to close the task before the suite finishes.
- You are marking a task Done because the diff is small.
- The evidence lives in your memory of an earlier session.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "It worked before the refactor" | The refactor is the change under test. Only a run after it proves anything. |
| "Tests are slow" | A slow run is shorter than the fix cycle a false Done triggers. Run the suite, or state that it was not run. |
| "The diff is obvious" | Obvious diffs ship typos, wrong paths, and inverted conditions. The gate takes one command. |
| "The builder said all tests pass" | A self-report is a claim, not evidence. Read the diff and quote a run you performed. |
| "I ran it a minute ago" | If an edit happened since, the run is stale. Run it again. |
| "There is no test command for this" | There is always a smoke run, a grep, a parser, or a manual reproduction. Pick one and record it. |
| "CI will catch it" | CI is a second gate, not a replacement for the first. A red CI after a Done still costs a full cycle. |
| "It is only documentation" | Documentation that names a wrong flag breaks the next agent that follows it. Execute what it documents. |
| "The linter passed, so the code is right" | Lint proves style, not behavior. Each claim needs its own proof. |
| "I will verify after I mark it Done" | Done is the claim. Verification comes before the claim by definition. |

## Requirements met

Before marking ANY task as done, verify:

### Code quality
- [ ] Code compiles/transpiles without errors
- [ ] No new linter warnings introduced
- [ ] No commented-out code left behind
- [ ] No debug logging (console.log, print, debugger) left in production code
- [ ] No hardcoded secrets, API keys, or credentials

### Tests
- [ ] All existing tests pass (run full suite, not just new tests)
- [ ] New code has corresponding tests
- [ ] Tests actually test behavior (not just line coverage)
- [ ] Edge cases covered (empty inputs, boundaries, error conditions)

### Contracts
- [ ] Output conforms to interfaces defined in CONTRACTS.md
- [ ] If new interfaces were introduced, they are documented
- [ ] If existing interfaces were modified, change was proposed in MEMORY.md first

### Integration
- [ ] Changes work with the rest of the system (not just in isolation)
- [ ] No N+1 queries or obvious performance regressions
- [ ] Error handling covers failure modes (timeouts, missing data, auth failures)

### Documentation
- [ ] CHANGELOG.md updated with changes and attribution
- [ ] MEMORY.md updated with any new decisions, patterns, or gotchas
- [ ] TASKS.md updated (task moved to "Done" with result summary)

## Output

Produce, in this order:
- The gate record for each claim: the claim, the command or observation, its quoted result, and the commit or file state it ran against
- The "Requirements met" checklist with pass/fail status for each item
- The completion signal for your scope (below) when every claim is proven and every item passes
- Otherwise, the blocker documented in TASKS.md and the task left open

Skills are invoked in each CLI's own form (`/name` in Claude Code, Antigravity, and Cursor; `$name` in Codex; the skill tool in OpenCode; `/skill:name` in Kimi). The evidence rules are the same in every harness.

## Completion signal

Only after ALL checks pass:

- **Task scope:** mark the task Done in TASKS.md with a result summary.
- **Sprint scope (Phase 6 wrap):** create the runtime marker as the LAST action:

  ```bash
  touch ops/.sprint-complete
  ```

  Outer tooling (`scripts/coordinate.sh`) detects sprint completion solely by this gitignored file's existence.

The signal means: "I have verified that all work is complete and all checks pass." It is not a summary; it is a commitment.

## What to do when checks fail

- If tests fail: fix the code, re-run, do not mark done
- If linter fails: fix the warnings, re-run
- If integration fails: investigate, fix root cause, re-verify
- If you cannot fix an issue: do NOT mark done. Instead:
  1. Document the blocker in TASKS.md
  2. Create a new task for the unresolved issue
  3. Mark current task as BLOCKED (not done)
