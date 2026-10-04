# Gated learnings-researcher (C4)

Pay for the `learnings-researcher` persona only when `ops/solutions/` plausibly knows the changed modules. Pre-search by name and path, derived from the diff, with no model call:

```bash
set -euo pipefail
# Gated learnings-researcher (C4): derive module names from the changed paths
# (full path, basename, stem, parent directory) and grep ops/solutions/ for
# them. Dispatch the persona only on at least one match — an empty corpus, or
# one that never mentions these modules, costs nothing.
CHANGED=$( { git diff --name-only HEAD 2>/dev/null || true; git diff --name-only HEAD~1 HEAD 2>/dev/null || true; } | sort -u )
MATCH_LIST="${TMPDIR:-/tmp}/learnings_gate_$$_$(date +%s).txt"
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
else
  echo "learnings-researcher skipped: no ops/solutions/ entry mentions the changed modules"
fi
```

**Run the `learnings-researcher` persona only when the list is non-empty.** Write its brief to a file ("Known-issue check for the review of <changed paths>: read these ops/solutions/ entries — <list> — and report which past fixes or gotchas the diff must not undo"), then run `dispatch_persona learnings-researcher <brief file> <out>` with `<out>` outside `ops/REVIEW_*` (it is context, not a review lane). That file goes to `findings-synthesizer` as **known-issue context** alongside the `ops/REVIEW_*.md` lanes. When the gate prints "skipped", do not dispatch it.
