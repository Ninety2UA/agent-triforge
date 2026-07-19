---
description: "Run Phase 5 testing: gap analysis + Codex TDD test writing + fix cycle."
allowed-tools: Read, Grep, Glob, Bash, Agent, Edit
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

## Step 2: Write tests via the roster's tester role

The tester is resolved from `ops/roster.toml` via `dispatch_role tester` — the shipped default is Codex (`test_writer`), but a roster override (e.g. `[roles.tester] cli = "opencode"`) routes the test writing to that CLI instead (AE4). `dispatch_role` threads the resolved model/effort through to the CLI.

```bash
set -euo pipefail
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# TDD test writing via the tester role (15 min timeout for TDD cycles). If scope
# covers 5+ files, Codex spawns internal subagents for parallel test writing.
TEST_OUT="${TMPDIR:-/tmp}/test_$$_$(date +%s).txt"
DISPATCH_RC=0
dispatch_role tester "test_writer" \
  "Test scope: changed files from ops/TASKS.md and ops/CHANGELOG.md. If scope covers 5+ files, spawn a separate agent per file/module for parallel test writing. Merge all results into ops/TEST_RESULTS.md." \
  "$TEST_OUT" 900 || DISPATCH_RC=$?

if [ "$DISPATCH_RC" -eq 40 ]; then
  # tester resolved to the claude lane (codex absent -> fallback). dispatch_role
  # printed "DISPATCH_ROLE_CLAUDE <agent> <out>" instead of running a shell CLI:
  # write the tests as a native Claude subagent (the test-driven-development
  # skill on the scope, output to ops/TEST_RESULTS.md) rather than a background CLI.
  echo "test: tester role resolved to the claude lane — write tests via a native Claude subagent (TDD skill), not a shell helper" >&2
elif [ "$DISPATCH_RC" -ne 0 ]; then
  echo "test: tester dispatch failed (rc=$DISPATCH_RC) — see $TEST_OUT" >&2
  exit 1
fi
```

If `DISPATCH_RC` was 40 above, spawn a Claude subagent (Agent tool) to write the tests against the scope with the `test-driven-development` skill, writing results to `ops/TEST_RESULTS.md`.

## Step 3: Process test results

1. Read ops/TEST_RESULTS.md
2. If all tests pass → report success
3. If tests fail:
   - Read failing test details
   - Fix the underlying code
   - Re-run specific failing tests via Codex
   - Loop until green (max 3 cycles)
4. Report final coverage metrics
