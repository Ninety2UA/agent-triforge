---
name: verification-before-completion
description: "Use before claiming a task, wave or sprint done, or reporting Status: DONE — fresh evidence for every claim."
metadata:
  triforge-consumer: "every role"
  triforge-phase: "every task completion; 6 (wrap-up)"
  version: "4.0.0"
---

# Verification Before Completion

## The Iron Law

> No completion claim without fresh verification evidence.

"Fresh" means produced by a command or observation you ran after the last change, in this session, and read in full. A claim is any statement that work is done, tests pass, a bug is fixed, a migration applied, or a document matches the code. Memory of an earlier run, a builder's self-report, and a diff that looks right are not evidence.

**Done when** every claim you are about to make has a gate record (the claim, the command or observation, its quoted result, the commit or file state it ran against) and the completion signal for your scope has been given — or the gap is reported and the task left open.

**Safe failure direction:** when a step of the gate cannot be completed, the claim is not made. Report what the evidence does show ("not verified: no command reproduces the bug on this host") and stop there; a task stays open rather than closing on a guess.

## The gate function

Run this before every claim, in order. Do not skip a step because the answer feels obvious.

1. **Identify the claim.** Write the exact sentence you are about to state ("the full suite passes", "the migration is applied", "the docs match the flags").
2. **Name the proof.** Name the command or observation whose result would prove that sentence, and what a failing result would look like. [references/claim-evidence.md](references/claim-evidence.md) lists, per kind of claim, what counts and what is commonly offered instead.
3. **Run it.** Execute the command now, after the last change, against the tree you are about to hand over.
4. **Read the result.** Read the whole output: exit code, totals, skipped items, warnings. A green summary line above a red section is a failure.
5. **State the claim with the evidence quoted.** Only now state the claim, and quote the command and the output lines that prove it. If the result does not prove the claim, say what it does show and stop there.

If any step cannot be completed, the claim is not made. Report the gap instead.

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

When one of these is accompanied by a reason why the gate does not apply this time, [references/rationalizations.md](references/rationalizations.md) has the answer to it.

## Output

Produce, in this order:
- The gate record for each claim: the claim, the command or observation, its quoted result, and the commit or file state it ran against
- The "Requirements met" checklist ([references/requirements-checklist.md](references/requirements-checklist.md)) with pass/fail status for each item
- The completion signal for your scope (below) when every claim is proven and every item passes
- Otherwise, the blocker documented in TASKS.md and the task left open

## Completion signal

Only after ALL checks pass:

- **Task scope:** mark the task Done in TASKS.md with a result summary.
- **Sprint scope (Phase 6 wrap):** create the runtime marker as the LAST action:

  ```bash
  touch ops/.sprint-complete
  ```

  Outer tooling (`$ROOT/scripts/coordinate.sh`, where `ROOT` is the Triforge plugin root) detects sprint completion solely by this gitignored file's existence.

The signal means: "I have verified that all work is complete and all checks pass." It is not a summary; it is a commitment.

## What to do when checks fail

- If tests fail: fix the code, re-run, do not mark done
- If linter fails: fix the warnings, re-run
- If integration fails: investigate, fix root cause, re-verify
- If you cannot fix an issue: do NOT mark done. Instead:
  1. Document the blocker in TASKS.md
  2. Create a new task for the unresolved issue
  3. Mark current task as BLOCKED (not done)
