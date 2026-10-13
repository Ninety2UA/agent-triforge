#!/usr/bin/env bash
# release-notes.sh — GitHub release title / body / tag target for a plugin version.
#
# docs/releases/ is the release ledger: every shipped version has a notes file
# docs/releases/v<X.Y.Z>.md whose first line is "# <YYYY-MM-DD> — v<X.Y.Z>: <title>"
# and whose body (every line after it) starts with that version's "## What's new".
# This script is the one place that turns that file into the GitHub release, so
# the notes on the Releases page are the file's body plus an install/compare
# footer. Each repo-relative link "](../../<path>)" becomes
# "](https://github.com/Ninety2UA/agent-triforge/blob/v<X.Y.Z>/<path>)", so it
# resolves on the release page. Consumed by .github/workflows/release.yml on
# every version bump that lands on main; runnable by hand for a preview.
#
# Usage:
#   bash scripts/release-notes.sh [--title | --body | --target] [version]
#
#   version    defaults to .claude-plugin/plugin.json's "version"
#   --title    "v<version> — <title>": the heading's text after its first ": ",
#              first letter capitalized ("v<version>" when the title is empty)
#   --body     the notes file's body + the install / compare footer  (default);
#              the footer links the notes file at the tag when the tag holds
#              it (or, before the tag exists, the --target commit does), else
#              at main
#   --target   the commit that first set .claude-plugin/plugin.json to <version> — the tag target
#
# Exit codes: 0 ok · 1 no notes file, a first line that is not its
# "# <date> — v<version>: <title>" heading, or an empty body (a release never
# ships without notes; write docs/releases/v<version>.md first), or no bump
# commit found · 2 usage. Bash 3.2-compatible (macOS /bin/bash); BSD and GNU
# awk/sed/grep/sort.
set -euo pipefail
cd "$(dirname "$0")/.."

# RN_PY_PRELUDE — python: the first lines of every program this script runs.
# python3 -c puts the working directory first on sys.path, so a json.py left in
# this checkout would be imported in place of the module; these lines drop it
# and every relative entry before anything else is imported. The same lines as
# _PY_PRELUDE in scripts/lib/common.sh, inline because this script runs
# without that library; SELF-27 compares the copies.
RN_PY_PRELUDE='
import os, sys
try:
    _tf_here = os.path.realpath(os.getcwd())
except OSError:
    _tf_here = None
sys.path[:] = [_p for _p in sys.path if os.path.isabs(_p) and os.path.realpath(_p) != _tf_here]
del _tf_here
'

REPO_URL="https://github.com/Ninety2UA/agent-triforge"
REPO_SLUG="${REPO_URL#https://github.com/}"   # owner/repo: the form `codex plugin marketplace add` takes
MODE="body"
VERSION=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title|--body|--target) MODE="${1#--}" ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*)
      echo "release-notes: unknown flag '$1' (accepted: --title --body --target)" >&2
      exit 2 ;;
    *) VERSION="$1" ;;
  esac
  shift
done
if [ -z "$VERSION" ]; then
  VERSION=$(python3 -c "${RN_PY_PRELUDE}"'import json; print(json.load(open(".claude-plugin/plugin.json"))["version"])')
fi
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "release-notes: version must be X.Y.Z (got '$VERSION')" >&2; exit 2 ;;
esac
TAG="v$VERSION"
NOTES="docs/releases/$TAG.md"

# Exits 1 unless the notes file exists and its first line is the heading
# "# <date> — v<version>: <title>". Literal substring match on "v<version>:" —
# the colon keeps v3.3.1 from matching v3.3.10.
require_notes() {
  if [ ! -f "$NOTES" ]; then
    echo "release-notes: no notes file $NOTES — write it before releasing: first line '# <YYYY-MM-DD> — $TAG: <title>', then the notes, starting with '## What's new'" >&2
    exit 1
  fi
  if ! awk -v v="$VERSION" 'NR == 1 { if (/^# / && index($0, "v" v ":") > 0) found = 1; exit } END { exit !found }' "$NOTES"; then
    echo "release-notes: $NOTES does not start with its heading '# <YYYY-MM-DD> — $TAG: <title>'" >&2
    exit 1
  fi
}

# The heading's title: its text after the first ": " (empty when there is none).
notes_title() {
  awk 'NR == 1 { i = index($0, ": "); if (i > 0) { t = substr($0, i + 2); sub(/^ */, "", t); print t } exit }' "$NOTES"
}

# The notes file's body: every line after its heading, each repo-relative link
# "](../../<path>)" rewritten to the file in the repository at the tag. index()
# and substr() only, so mawk, gawk and BSD awk agree.
notes_body() {
  awk -v base="$REPO_URL/blob/$TAG/" '
    NR == 1 { next }
    {
      out = ""; rest = $0
      while ((i = index(rest, "](../../")) > 0) {
        out = out substr(rest, 1, i + 1) base
        rest = substr(rest, i + 8)
      }
      print out rest
    }
  ' "$NOTES"
}

# Oldest commit on the current history that introduced this exact version
# string — the bump commit, whether a direct push or a squash merge.
bump_commit() {
  git log --format=%H -S"\"version\": \"$VERSION\"" -- .claude-plugin/plugin.json | tail -1
}

# Drop leading and trailing blank lines, keep interior ones.
trim_blank_lines() {
  awk '
    NF { printf "%s", pending; pending = ""; print; started = 1; next }
    started { pending = pending "\n" }
  '
}

# The tag that precedes this version in version order (empty for the first).
previous_tag() {
  { git tag --list 'v*'; printf '%s\n' "$TAG"; } | sort -u | sort -V \
    | awk -v cur="$TAG" '$0 == cur { exit } { prev = $0 } END { print prev }'
}

case "$MODE" in
  title)
    require_notes
    t=$(notes_title)
    if [ -n "$t" ]; then
      first=$(printf '%s' "${t:0:1}" | tr '[:lower:]' '[:upper:]')
      printf '%s — %s%s\n' "$TAG" "$first" "${t:1}"
    else
      printf '%s\n' "$TAG"
    fi
    ;;
  body)
    require_notes
    body=$(notes_body | trim_blank_lines)
    if [ -z "$body" ]; then
      echo "release-notes: $NOTES has nothing after its heading — write the notes before releasing" >&2
      exit 1
    fi
    prev=$(previous_tag)
    # The notes file at the tag once the tag holds it (or, before the tag
    # exists, the commit it will be created at); tags older than docs/releases/
    # link it on main.
    ref=main
    if git rev-parse -q --verify "refs/tags/$TAG^{commit}" >/dev/null; then
      if git cat-file -e "$TAG:$NOTES" 2>/dev/null; then
        ref="$TAG"
      fi
    else
      target=$(bump_commit)
      if [ -n "$target" ] && git cat-file -e "$target:$NOTES" 2>/dev/null; then
        ref="$TAG"
      fi
    fi
    printf '%s\n\n---\n\n' "$body"
    printf '**Install / update (Claude Code):** `claude plugin marketplace add %s` · `claude plugin install agent-triforge@agent-triforge` · `claude plugin update agent-triforge`\n\n' "$REPO_URL"
    printf '**Install (Codex):** `codex plugin marketplace add %s` · `codex plugin add agent-triforge@agent-triforge`\n\n' "$REPO_SLUG"
    if [ -n "$prev" ]; then
      printf '**Full changelog:** [%s...%s](%s/compare/%s...%s) · ' "$prev" "$TAG" "$REPO_URL" "$prev" "$TAG"
    else
      printf '**Full changelog:** '
    fi
    printf '[%s](%s/blob/%s/%s)\n' "$NOTES" "$REPO_URL" "$ref" "$NOTES"
    ;;
  target)
    target=$(bump_commit)
    if [ -z "$target" ]; then
      echo "release-notes: no commit sets .claude-plugin/plugin.json to $VERSION on this history" >&2
      exit 1
    fi
    printf '%s\n' "$target"
    ;;
esac
