#!/usr/bin/env bash
# release-notes.sh — GitHub release title / body / tag target for a plugin version.
#
# README.md is the release ledger: every shipped version has a "## Recent changes"
# entry headed "### <YYYY-MM-DD> — v<X.Y.Z>: <title>" (the "## What's new (vX.Y.Z)"
# summary block is the fallback source). This script is the one place that turns
# that entry into the GitHub release, so the notes on the Releases page are the
# README entry verbatim plus an install/compare footer. Consumed by
# .github/workflows/release.yml on every version bump that lands on main;
# runnable by hand for a preview.
#
# Usage:
#   bash scripts/release-notes.sh [--title | --body | --target] [version]
#
#   version    defaults to .claude-plugin/plugin.json's "version"
#   --title    "v<version> — <Recent changes title>"  ("v<version>" when the entry has no title)
#   --body     the ledger entry's markdown + the install / compare footer  (default)
#   --target   the commit that first set .claude-plugin/plugin.json to <version> — the tag target
#
# Exit codes: 0 ok · 1 no README entry (a release never ships with empty notes —
# add the "### <date> — v<version>: <title>" entry first) or no bump commit found ·
# 2 usage. Bash 3.2-compatible (macOS /bin/bash); BSD and GNU awk/sed/grep/sort.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO_URL="https://github.com/Ninety2UA/agent-triforge"
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
  VERSION=$(python3 -c 'import json; print(json.load(open(".claude-plugin/plugin.json"))["version"])')
fi
case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "release-notes: version must be X.Y.Z (got '$VERSION')" >&2; exit 2 ;;
esac
TAG="v$VERSION"

# The ledger entry's heading title, or empty. Literal substring match on
# "v<version>:" — the colon keeps v3.3.1 from matching v3.3.10.
ledger_title() {
  awk -v v="$VERSION" '
    /^## Recent changes/ { led = 1; next }
    led && /^### / && index($0, "v" v ":") > 0 {
      sub(/^### [^:]*: */, ""); print; exit
    }
  ' README.md
}

# The ledger entry's body: the lines after its heading up to the next heading
# or "---" separator. Empty when the version has no entry.
ledger_body() {
  awk -v v="$VERSION" '
    /^## Recent changes/ { led = 1; next }
    led && /^### / {
      if (inentry) exit
      if (index($0, "v" v ":") > 0) inentry = 1
      next
    }
    led && inentry {
      if ($0 ~ /^---[ \t]*$/ || $0 ~ /^## /) exit
      print
    }
  ' README.md
}

# Fallback: the "## What's new (v<version>)" summary block.
whats_new_body() {
  awk -v hdr="## What's new (v$VERSION)" '
    index($0, hdr) == 1 { inb = 1; next }
    inb && (/^## / || /^### /) { exit }
    inb { print }
  ' README.md
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
    t=$(ledger_title)
    if [ -n "$t" ]; then
      first=$(printf '%s' "${t:0:1}" | tr '[:lower:]' '[:upper:]')
      printf '%s — %s%s\n' "$TAG" "$first" "${t:1}"
    else
      printf '%s\n' "$TAG"
    fi
    ;;
  body)
    body=$(ledger_body | trim_blank_lines)
    if [ -z "$body" ]; then
      body=$(whats_new_body | trim_blank_lines)
    fi
    if [ -z "$body" ]; then
      echo "release-notes: README.md has no '## Recent changes' entry '### <date> — $TAG: <title>' (nor a '## What's new ($TAG)' block) — add it before releasing" >&2
      exit 1
    fi
    prev=$(previous_tag)
    printf '%s\n\n---\n\n' "$body"
    printf '**Install / update:** `claude plugin marketplace add %s` · `claude plugin install agent-triforge@agent-triforge` · `claude plugin update agent-triforge`\n\n' "$REPO_URL"
    if [ -n "$prev" ]; then
      printf '**Full changelog:** [%s...%s](%s/compare/%s...%s) · ' "$prev" "$TAG" "$REPO_URL" "$prev" "$TAG"
    else
      printf '**Full changelog:** '
    fi
    printf '[README › Recent changes](%s/blob/%s/README.md#recent-changes)\n' "$REPO_URL" "$TAG"
    ;;
  target)
    # Oldest commit on the current history that introduced this exact version
    # string — the bump commit, whether a direct push or a squash merge.
    target=$(git log --format=%H -S"\"version\": \"$VERSION\"" -- .claude-plugin/plugin.json | tail -1)
    if [ -z "$target" ]; then
      echo "release-notes: no commit sets .claude-plugin/plugin.json to $VERSION on this history" >&2
      exit 1
    fi
    printf '%s\n' "$target"
    ;;
esac
