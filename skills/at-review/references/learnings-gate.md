# Gated learnings-researcher (C4)

Pay for the `learnings-researcher` persona only when `ops/solutions/` plausibly knows the changed modules. Pre-search by name and path, derived from the diff, with no model call:

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
: "${REVIEW_RUN:?set REVIEW_RUN to the run directory the dispatch block printed}"
# Gated learnings-researcher (C4): derive module names from the changed paths
# (full path, basename, stem, parent directory) and grep ops/solutions/ for
# them. Dispatch the persona only on at least one match — an empty corpus, or
# one that never mentions these modules, costs nothing.
CHANGED=$( { git diff --name-only HEAD 2>/dev/null || true; git diff --name-only HEAD~1 HEAD 2>/dev/null || true; } | sort -u )
MATCH_LIST="$REVIEW_RUN/learnings-matches.txt"
: > "$MATCH_LIST"
if [ -d ops/solutions ] && [ -n "$CHANGED" ]; then
  while IFS= read -r F; do
    [ -n "$F" ] || continue
    BASE=$(basename "$F"); STEM="${BASE%.*}"; DIR=$(basename "$(dirname "$F")")
    for NEEDLE in "$F" "$BASE" "$STEM" "$DIR"; do
      # skip empty, dot-dir, and very short needles (they would match everything)
      [ -n "$NEEDLE" ] && [ "$NEEDLE" != "." ] && [ "${#NEEDLE}" -ge 4 ] || continue
      grep -rlF -- "$NEEDLE" ops/solutions/ 2>/dev/null >> "$MATCH_LIST" || true
    done
  done <<< "$CHANGED"
  sort -u -o "$MATCH_LIST" "$MATCH_LIST"
fi
if [ -s "$MATCH_LIST" ]; then
  echo "learnings-researcher: dispatch — ops/solutions/ entries mentioning the changed modules:"
  cat "$MATCH_LIST"
  # The input is data (the changed paths and the matched entries); the task is the --brief.
  { echo "Changed paths:"; printf '%s\n' "$CHANGED"; echo; echo "ops/solutions/ entries that mention them:"; cat "$MATCH_LIST"; } > "$REVIEW_RUN/learnings-input.md"
  LRC=0
  dispatch_persona learnings-researcher "$REVIEW_RUN/learnings-input.md" "$REVIEW_RUN/learnings.md" \
    --brief "Known-issue check for this review: read the ops/solutions/ entries the input lists and report which past fixes or gotchas the changed paths must not undo." || LRC=$?
  [ "$LRC" -eq 0 ] || echo "learnings-researcher failed rc=$LRC: synthesis runs without known-issue context, and the report says so" >&2
else
  echo "learnings-researcher skipped: no ops/solutions/ entry mentions the changed modules"
fi
```

The block runs the `learnings-researcher` persona only when the list is non-empty: its input is the changed paths and the matched entries (data), its task the `--brief`, and its report `$REVIEW_RUN/learnings.md`, outside `ops/REVIEW_*` because it is context, not a review lane. Synthesis hands that report to `findings-synthesizer` as **known-issue context**. When the gate prints "skipped", nothing is dispatched.
