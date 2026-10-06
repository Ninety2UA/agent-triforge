# Step 1: identify test gaps

The persona runs with Bash in a disposable worktree at the default `--at ref:HEAD`, which holds committed work only. When the scope has uncommitted changes (`git status --porcelain -- <scope paths>` prints anything), stop before the start and tell the user the persona sees committed HEAD only; ask them to commit the changes or name a ref for `--at`, and never commit for them. It runs detached, because a persona can outlast one tool call: the first block starts it, and you rerun the second while it returns 75. Both run the same under bash and zsh.

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
GAP_RUN=$(mktemp -d "${TMPDIR:-/tmp}/triforge-test.XXXXXX")
printf '%s\n' "<scope paths, one per line>" > "$GAP_RUN/scope.txt"
persona_spawn "$GAP_RUN" test-gap-analyzer test-gap-analyzer "$GAP_RUN/scope.txt" "$GAP_RUN/gaps.md" \
  --brief "Find the untested paths in the scope the input names."
echo "test: test-gap-analyzer started; run the wait block next (GAP_RUN=$GAP_RUN)"
```

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
: "${GAP_RUN:?set GAP_RUN to the run directory the start block printed}"
persona_wait "$GAP_RUN" || { rc=$?; [ "$rc" -eq 75 ] && echo "test: test-gap-analyzer still running; rerun this block"; exit "$rc"; }
R=$(cat "$GAP_RUN/test-gap-analyzer.rc" 2>/dev/null || echo missing)
[ "$R" = 0 ] && [ -s "$GAP_RUN/gaps.md" ] || { echo "test: test-gap-analyzer failed rc=$R or wrote nothing — see $GAP_RUN" >&2; exit 1; }
cat "$GAP_RUN/gaps.md"
```

A persona that fails or writes nothing is a failed step, never "no gaps". Its report identifies:

- Files with no tests
- Functions without test coverage
- Missing error path coverage
- Missing edge case coverage
- Weak assertions
- Recommended test writing priority order

With the `--gaps-only` flag: report the gaps and stop.
