# Gated learnings-researcher (C4)

Pay for the `learnings-researcher` sub-agent only when `ops/solutions/` plausibly knows the changed modules. Pre-search by name and path, with no model call. The changed paths come from the review package's inventory (`REVIEW_PKG`, the directory the review-package block printed), so this block runs no git:

```bash
set -euo pipefail
# Gated learnings-researcher (C4): derive module names from the changed paths
# (full path, basename, stem, parent directory) and grep ops/solutions/ for
# them. Spawn the sub-agent only on at least one match — an empty corpus, or
# one that never mentions these modules, costs nothing. The paths are the
# package inventory's (rename sources included, untracked files too).
REVIEW_PKG=${REVIEW_PKG:-}
if [ -z "$REVIEW_PKG" ] || [ ! -O "$REVIEW_PKG" ] || [ ! -f "$REVIEW_PKG/inventory.txt" ]; then
  echo "learnings gate: no review package (REVIEW_PKG='${REVIEW_PKG}') — run the review-package block first and set REVIEW_PKG to the directory it printed" >&2; exit 1
fi
CHANGED=$(cut -f2- "$REVIEW_PKG/inventory.txt" | tr '\t' '\n' | sed '/^$/d' | sort -u)
MATCH_LIST="$REVIEW_PKG/learnings.txt"
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
  echo "learnings-researcher: spawn — ops/solutions/ entries mentioning the changed modules:"
  cat "$MATCH_LIST"
else
  echo "learnings-researcher skipped: no ops/solutions/ entry mentions the changed modules"
fi
```

**Spawn `learnings-researcher` only when the list is non-empty**, with the matched entries and the changed paths in its prompt ("Known-issue check for the review of <changed paths>: read these ops/solutions/ entries — <list> — and report which past fixes or gotchas the diff must not undo"; the diff is `$REVIEW_PKG/full.diff`). Its output goes to `findings-synthesizer` as **known-issue context** alongside the `ops/REVIEW_*.md` lanes. When the gate prints "skipped", do not spawn it.
