#!/usr/bin/env bash
# Vercel's ignored build step, run from site/ (the project's root directory).
# Exit 0 skips the build; exit 1 builds. It skips only when no input of the site changed since the
# last deployment, and it fails open: with no previous commit to compare against, or one missing from
# Vercel's shallow clone, it builds. test/ignore-build.test.mjs keeps the inputs equal to what the
# build reads.
set -u

prev="${VERCEL_GIT_PREVIOUS_SHA:-}"
if [ -z "$prev" ]; then
  echo "No previous deployment to compare with: building."
  exit 1
fi
if ! git cat-file -e "${prev}^{commit}" 2>/dev/null; then
  echo "Previous deployment commit ${prev} is not in this clone: building."
  exit 1
fi

# Everything the build reads (':/' anchors each path at the repository root): the site itself, the
# skills, personas and docs pages it renders, the README (FAQ, install block, release table), the
# plugin version, the shipped roster, and the CLI registry and DOC_PAGES list it parses.
inputs=(
  ':/site'
  ':/skills'
  ':/personas'
  ':/docs'
  ':/README.md'
  ':/.claude-plugin/plugin.json'
  ':/templates/ops/roster.toml'
  ':/scripts/lib/registry.sh'
  ':/scripts/validate-versions.sh'
)
if git diff --quiet "$prev" HEAD -- "${inputs[@]}"; then
  echo "No site input changed since ${prev}: skipping the build."
  exit 0
fi
echo "Site inputs changed since ${prev}: building."
exit 1
