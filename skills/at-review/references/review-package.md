# The review package (built once per cycle, before any lane)

## Contents

- What the package holds, and its base.
- The integrity check that opens the block.
- Where the package lives and who reads it.
- The package block.

The core lanes, the optional lanes and the specialist sub-agents all review the same package, and the learnings gate reads its list of changed files. The read-class reviewers have no shell to run git, the Antigravity reviewer runs no command, and Grok reviews from a scratch copy of HEAD, so the package carries what changed. `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it).

The package holds three things:

1. The `[R]` rows of the lead's `ops/TASKS.md`.
2. A complete inventory of changed files: every tracked change from the base to the working tree with its `git diff --name-status` letter, then every untracked file (`git ls-files --others --exclude-standard`) marked `?`. Untracked files are listed by name only. They are not in the diff, and the prompt says so.
3. The diff from the base to the working tree, so the branch's commits and the uncommitted edits both show. The inline diff is cut so the whole package stays within 116,000 bytes. A lane's prompt then stays under 120,000 bytes, and under Linux's 131,072-byte limit on one argument even with a role brief added. When the diff is cut, the prompt says so and names `full.diff`, which holds every file.

The base is `REVIEW_BASE` when the lead sets it. It must name a commit, or the review stops and names it. Without it, the base is where HEAD left the default branch, else HEAD. With no explicit base and nothing differing from it, the package falls back to the last commit. A git call that fails stops the review. It never turns into an empty diff or another scope.

The block starts with the lead's integrity check (KTD18). That check comes before at-review's first git call, so a filter or fsmonitor a worker planted in `.git/config` never runs in the lead's shell. `_lead_git` turns off hooks and fsmonitor but not filters. In a project that was never leased there is no ledger, and the check returns 0 and writes nothing. A nonzero exit stops the review: report the message and the rc, and run no other block. No package exists then, so no lane can start.

The package is a private directory (mode 700, from `mktemp -d`) under the lead's `TMPDIR`. Lanes read it by absolute path. Grok's read-only sandbox reads everywhere, and Devin auto-approves read tools at any path. The block prints `REVIEW_PKG=<dir>` as its last line. Set it on every later block, and give the path to every sub-agent. Each cycle builds its own package, and synthesis removes it when the cycle ends.

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"

# The lead's integrity check before the first git call at-review makes
# (KTD18): git diff runs a clean filter planted in .git/config, and the lead's
# hardened git switches off hooks and fsmonitor, not filters. A git checkout is
# found the way git finds one (the nearest ancestor holding .git); outside one
# at-review runs no git at all. Any failure of the check, a context it could
# not resolve included, stops the review here, before the package exists.
RGIT=0; RD=$(pwd -P)
while :; do
  if [ -e "$RD/.git" ]; then RGIT=1; break; fi
  if [ "$RD" = / ]; then break; fi
  RD=$(dirname "$RD")
done
if [ "$RGIT" -eq 1 ]; then
  _lead_integrity_check at-review || { RIC=$?; echo "review: STOPPED — the lead's integrity check failed (rc ${RIC}; its message is above). No package was built and no lane started." >&2; exit "$RIC"; }
fi

# The base: an explicit REVIEW_BASE must name a commit; else where HEAD left
# the default branch (merge-base rc 1, no common history, means HEAD); else HEAD.
RBASE=""; RTO=""; RRANGE="none: not a git checkout"
if [ "$RGIT" -eq 1 ]; then
  _lease_ctx || exit 1
  if ! _lgr rev-parse --verify --quiet 'HEAD^{commit}' >/dev/null 2>&1; then
    echo "review: STOPPED — HEAD names no commit (an empty repository?); nothing to review against" >&2; exit 1
  fi
  if [ -n "${REVIEW_BASE:-}" ]; then
    case "$REVIEW_BASE" in
      -*) ;;
      *)  RBASE=$(_lgr rev-parse --verify --quiet "${REVIEW_BASE}^{commit}" 2>/dev/null || true) ;;
    esac
    if [ -z "$RBASE" ]; then
      echo "review: STOPPED — REVIEW_BASE='${REVIEW_BASE}' names no commit in this repository. Set it to a commit, or unset it to review from where HEAD left the default branch." >&2; exit 1
    fi
    RRANGE="REVIEW_BASE ${REVIEW_BASE} (${RBASE:0:12}) to the working tree"
  else
    RDEF=$(_lease_default_branch 2>/dev/null || true)
    if [ -n "$RDEF" ]; then
      RMB=0; RBASE=$(_lgr merge-base "refs/heads/${RDEF}" HEAD 2>/dev/null) || RMB=$?
      if [ "$RMB" -gt 1 ]; then echo "review: STOPPED — git merge-base ${RDEF} HEAD failed (rc ${RMB})" >&2; exit 1; fi
    fi
    if [ -n "$RBASE" ]; then RRANGE="${RBASE:0:12} (where HEAD left ${RDEF}) to the working tree"; else RBASE=HEAD; RRANGE="HEAD to the working tree"; fi
  fi
fi

# The package directory; removed again unless the package is complete.
RTMP=${TMPDIR:-/tmp}
REVIEW_PKG=$(mktemp -d "${RTMP%/}/triforge-review.XXXXXX") || exit 1
trap 'rm -rf "$REVIEW_PKG"' EXIT
: > "$REVIEW_PKG/tracked.txt"; : > "$REVIEW_PKG/untracked.txt"; : > "$REVIEW_PKG/full.diff"

# The diff and the inventory, through the lead's hardened git with no external
# diff or textconv driver. Every call's rc is checked.
if [ "$RGIT" -eq 1 ]; then
  RERR="$REVIEW_PKG/git.err"; RGRC=0
  _lgr diff --no-ext-diff --no-textconv --no-color "$RBASE" -- > "$REVIEW_PKG/full.diff" 2> "$RERR" || RGRC=$?
  if [ "$RGRC" -eq 0 ] && [ ! -s "$REVIEW_PKG/full.diff" ] && [ -z "${REVIEW_BASE:-}" ] \
     && _lgr rev-parse --verify --quiet 'HEAD~1^{commit}' >/dev/null 2>&1; then
    RBASE=HEAD~1; RTO=HEAD; RRANGE="HEAD~1 to HEAD (the last commit; nothing else differs from the base)"
    _lgr diff --no-ext-diff --no-textconv --no-color HEAD~1 HEAD -- > "$REVIEW_PKG/full.diff" 2> "$RERR" || RGRC=$?
  fi
  if [ "$RGRC" -eq 0 ]; then
    _lgr -c core.quotePath=false diff --no-ext-diff --no-color --name-status "$RBASE" ${RTO:+"$RTO"} -- > "$REVIEW_PKG/tracked.txt" 2> "$RERR" || RGRC=$?
  fi
  if [ "$RGRC" -eq 0 ]; then
    _lgr -c core.quotePath=false ls-files --others --exclude-standard > "$REVIEW_PKG/untracked.txt" 2> "$RERR" || RGRC=$?
  fi
  if [ "$RGRC" -ne 0 ]; then
    echo "review: STOPPED — collecting the diff from ${RRANGE} failed (git rc ${RGRC}): $(tail -3 "$RERR" | tr '\n' ' ' | cut -c1-300)" >&2; exit 1
  fi
fi
grep -F '[R]' ops/TASKS.md 2>/dev/null | head -100 > "$REVIEW_PKG/rows.txt" || true

# package.md: the rows, the inventory (inventory.txt holds all of it) and the
# inline diff, cut at a file boundary when possible, within 116000 bytes.
RP_DIR="$REVIEW_PKG" RP_CAP=116000 RP_RANGE="$RRANGE" RP_GIT="$RGIT" python3 -c '
import os
d, cap, rng = os.environ["RP_DIR"], int(os.environ["RP_CAP"]), os.environ["RP_RANGE"]
def rd(n):
    with open(os.path.join(d, n), "rb") as f:
        return f.read()
def lines(b):
    return [x for x in b.split(b"\n") if x.strip()]
def fit(ls, room):
    out, n = [], 0
    for x in ls:
        if n + len(x) + 1 > room:
            break
        out.append(x)
        n += len(x) + 1
    return out
E = lambda s: s.encode("utf-8")
inv = lines(rd("tracked.txt")) + [b"?\t" + p for p in lines(rd("untracked.txt"))]
with open(os.path.join(d, "inventory.txt"), "wb") as f:
    f.write(b"".join(x + b"\n" for x in inv))
nu = sum(1 for x in inv if x.startswith(b"?\t"))
rows = fit(lines(rd("rows.txt")), 16000)
head = E("## Task rows under review (the [R] rows of ops/TASKS.md in the lead checkout)\n")
head += (b"\n".join(rows) if rows else b"(none found)") + b"\n\n"
head += E("## Changed files (%d, %d untracked; git diff --name-status from %s, then untracked files marked ?). Untracked files are listed by name only and are not in the diff: read them at their paths.\n" % (len(inv), nu, rng))
shown = fit(inv, 40000)
head += (b"\n".join(shown) if shown else b"(none)") + b"\n"
if len(shown) < len(inv):
    head += E("(%d more: the complete list is in %s)\n" % (len(inv) - len(shown), os.path.join(d, "inventory.txt")))
full, fpath = rd("full.diff"), os.path.join(d, "full.diff")
nf = full.count(b"\ndiff --git ") + (1 if full.startswith(b"diff --git ") else 0)
dhead = E("\n## The diff under review (git diff from %s)\n" % rng)
begin, end = b"----- BEGIN DIFF -----\n", b"\n----- END DIFF -----\n"
room = cap - len(head) - len(dhead) - len(begin) - len(end) - 200 - len(E(fpath))
note, body = b"", full.rstrip(b"\n")
if not full:
    body = b"(empty: not a git checkout)" if os.environ["RP_GIT"] != "1" else b"(empty: no change against the base)"
elif len(body) > room:
    room = max(room, 0)
    cut = full.rfind(b"\ndiff --git ", 0, room + 1)
    if cut <= 0:
        cut = full.rfind(b"\n", 0, room + 1)
    body = full[:max(cut, 0)]
    kept = body.count(b"\ndiff --git ") + (1 if body.startswith(b"diff --git ") else 0)
    note = E("Cut: below are the first %d of %d bytes, %d of %d files. The full diff, every file, is in %s: read it there.\n" % (len(body), len(full), kept, nf, fpath))
pkg = head + dhead + note + begin + body + end
with open(os.path.join(d, "package.md"), "wb") as f:
    f.write(pkg)
print("review package: %d changed files (%d untracked) from %s; diff %d bytes, %s; package %d bytes" % (len(inv), nu, rng, len(full), "cut, full diff in full.diff" if note else "all inline", len(pkg)))
' || exit 1
trap - EXIT
echo "REVIEW_PKG=${REVIEW_PKG}"
```
