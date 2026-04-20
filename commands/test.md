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
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# TDD test writing (uses test_writer agent definition, 15 min timeout for TDD cycles)
# If scope covers 5+ files, Codex will spawn internal subagents for parallel test writing
invoke_codex "test_writer" \
  "Test scope: changed files from ops/TASKS.md and ops/CHANGELOG.md. If scope covers 5+ files, spawn a separate agent per file/module for parallel test writing. Merge all results into ops/TEST_RESULTS.md." \
  "${TMPDIR:-/tmp}/codex_test_$$_$(date +%s).txt" 900
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
