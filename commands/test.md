---
description: "Run Phase 5 testing: gap analysis + Codex TDD test writing + fix cycle."
argument-hint: "[--gaps-only] [scope]"
---

You are executing Phase 5 (Test) of the multi-agent framework.

## Arguments
$ARGUMENTS

Flags:
- `--gaps-only` — Only run test-gap-analyzer, don't invoke Codex to write tests
- `scope` — Specific files or modules to test (default: all changed code)

## Step 1: Identify test gaps

Spawn the `test-gap-analyzer` agent on the scope.

It identifies:
- Files with no tests
- Functions without test coverage
- Missing error path coverage
- Missing edge case coverage
- Weak assertions
- Recommended test writing priority order

If `--gaps-only` flag: report gaps and stop.

## Step 2: Invoke Codex for test writing

```bash
codex exec "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/test-driven-development/SKILL.md)

You are the testing agent in a multi-agent repository.

READ THESE FILES FIRST:
- ops/CONTRACTS.md (your tests MUST use these types)
- ops/CHANGELOG.md (focus on changed code)
- ops/REVIEW_GEMINI.md (test edge cases flagged here)
- ops/REVIEW_CODEX.md (test security concerns flagged here)
- ops/TASKS.md (your assigned test tasks)

APPLY the RED-GREEN-REFACTOR cycle.

FOR EACH TEST TASK:
1. Write a failing test first (RED)
2. Verify it fails for the right reason
3. Write minimal code to pass (GREEN) — or verify existing code passes
4. Refactor if needed

AFTER TESTING:
- Write results to ops/TEST_RESULTS.md
- Update ops/CHANGELOG.md
- If tests fail on existing code, log as tasks assigned to Claude in ops/TASKS.md" > /tmp/codex_test.txt 2>&1 &
CODEX_PID=$!

# Wait with timeout (15 min — TDD cycles take longer)
AGENT_TIMEOUT=900
( sleep $AGENT_TIMEOUT && kill -TERM $CODEX_PID 2>/dev/null && sleep 5 && kill -9 $CODEX_PID 2>/dev/null ) &
WD=$!
wait $CODEX_PID 2>/dev/null
kill $WD 2>/dev/null; wait $WD 2>/dev/null
```

## Step 3: Process test results

1. Read ops/TEST_RESULTS.md
2. If all tests pass → report success
3. If tests fail:
   - Read failing test details
   - Fix the underlying code
   - Re-run specific failing tests via Codex
   - Loop until green (max 3 cycles)
4. Report final coverage metrics
