#!/usr/bin/env bash
# locate-triforge.sh: fixture stand-in for the shared locator whose --help names itself but not the plugin root.
set -euo pipefail
case "${1:-}" in
  -h|--help)
    echo "usage: locate-triforge.sh [--help]"
    exit 0 ;;
esac
echo "fixture-root"
