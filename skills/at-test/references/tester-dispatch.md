# Step 2: write tests via the roster's tester role

The tester is resolved from `ops/roster.toml` via `dispatch_role tester` — the shipped default is Codex (`test_writer`), but a roster override (for example `[roles.tester] cli = "opencode"`) routes the test writing to that CLI instead (AE4). `dispatch_role` threads the resolved model and effort through to the CLI.

```bash
set -euo pipefail
ROOT=$(bash scripts/locate-triforge.sh) || exit $?
source "$ROOT/scripts/invoke-external.sh"

# TDD test writing via the tester role (15 min timeout for TDD cycles). If scope
# covers 5+ files, the tester spawns internal subagents for parallel test writing.
TEST_OUT="${TMPDIR:-/tmp}/test_$$_$(date +%s).txt"
DISPATCH_RC=0
dispatch_role tester "test_writer" \
  "Test scope: changed files from ops/TASKS.md and ops/CHANGELOG.md. If scope covers 5+ files, spawn a separate agent per file/module for parallel test writing. Merge all results into ops/TEST_RESULTS.md." \
  "$TEST_OUT" 900 || DISPATCH_RC=$?

if [ "$DISPATCH_RC" -eq 40 ]; then
  # tester resolved to the lead's native sub-agent lane (codex absent -> fallback).
  # dispatch_role printed "DISPATCH_ROLE_CLAUDE <agent> <out>" instead of running
  # a shell CLI: write the tests as a native sub-agent (failing test first on the
  # scope, output to ops/TEST_RESULTS.md) rather than a background CLI.
  echo "test: tester role resolved to the native sub-agent lane — write tests via a sub-agent (failing test first), not a shell helper" >&2
elif [ "$DISPATCH_RC" -ne 0 ]; then
  echo "test: tester dispatch failed (rc=$DISPATCH_RC) — see $TEST_OUT" >&2
  exit 1
fi
```

When `DISPATCH_RC` was 40, spawn a sub-agent to write the tests against the scope, writing results to `ops/TEST_RESULTS.md`. A failing test that names the behavior comes before any implementation change, and the report quotes the red run and the green run; a test for existing behavior is shown to fail when that behavior is broken.
