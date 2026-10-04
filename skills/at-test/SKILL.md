---
name: at-test
description: "Use when changed code needs Phase 5 testing: gap analysis, tests from the roster tester, a fix cycle to green."
argument-hint: "[--gaps-only] [scope]"
disable-model-invocation: true
metadata:
  triforge-consumer: "lead"
  version: "4.0.0"
---

# Test

Phase 5 of the Triforge lifecycle: find the test gaps, have the roster's tester write the tests, fix until green.

Invoked with optional flags: `--gaps-only` runs the gap analysis and stops without writing tests; `scope` names the files or modules to test. When absent, the scope is all changed code (the files named in `ops/TASKS.md` and `ops/CHANGELOG.md`). The user's own instructions outrank this skill.

**Goal:** a gap report, tests written against the scope with a failing run before any implementation change, and an `ops/TEST_RESULTS.md` the lead has read and acted on.

**Done when** `ops/TEST_RESULTS.md` is green — every failing test fixed at the underlying code and re-run — or, after 3 fix cycles, the remaining failures are escalated to the user; the final coverage metrics are reported either way. With `--gaps-only`, done when the gap report is presented.

**Safe failure:** a tester dispatch that returns anything other than 0 or 40 stops the skill and names the output file — an empty result is never "no gaps" or "all green". Return code 40 is not a failure: the tester resolved to the lead's native sub-agent lane and the tests are written there. More than 3 fix cycles is an escalation, not a fourth cycle.

## Facts a model cannot derive

- **Step 1** spawns a sub-agent with the `test-gap-analyzer` persona on the scope; the six categories it reports and the priority order: [references/gap-analysis.md](references/gap-analysis.md).
- **Step 2** dispatches the roster's tester role (`dispatch_role tester "test_writer" …`; the shipped default is Codex, a `[roles.tester]` override routes elsewhere — AE4) through the helper, reached with `ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"`, with a 900 s timeout; a scope of 5+ files is split across the tester's own parallel agents. The invocation, the rc 40 branch and the TDD contract for the native lane: [references/tester-dispatch.md](references/tester-dispatch.md). Host mechanics for the sub-agents: [references/claude.md](references/claude.md), [references/codex.md](references/codex.md). `$SKILL_DIR` is the directory this SKILL.md was loaded from — the harness shows that path when it loads the skill (the plugin install under Claude Code, the skill's path under Codex) — and every path in this skill is relative to it, never to the project; never run a project's own `scripts/locate-triforge.sh`.
- **Step 3** reads `ops/TEST_RESULTS.md` and runs the fix cycle, at most 3 rounds: [references/fix-cycle.md](references/fix-cycle.md).

## Output

- The gap report: files with no tests, functions without coverage, missing error-path and edge-case coverage, weak assertions, and the recommended test-writing priority order (the whole output under `--gaps-only`).
- `ops/TEST_RESULTS.md`, written by the tester (or by the native sub-agent on rc 40), quoting the red run and the green run.
- Success, or the fix-cycle record and an escalation after 3 cycles.
- The final coverage metrics.
