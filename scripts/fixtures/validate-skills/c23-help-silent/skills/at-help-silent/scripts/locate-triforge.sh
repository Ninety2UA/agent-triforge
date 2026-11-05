#!/usr/bin/env bash
# locate-triforge.sh: fixture stand-in for the shared locator whose --help exits 0 silently.
set -euo pipefail
case "${1:-}" in
  -h|--help)
    exit 0 ;;
esac
echo "fixture-root"
