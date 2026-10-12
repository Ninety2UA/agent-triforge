#!/usr/bin/env bash
# locate-triforge.sh — fixture stand-in for the shared locator (scripts/skill-locator/).
set -euo pipefail
case "${1:-}" in
  -h|--help)
    echo "usage: bash scripts/locate-triforge.sh [--help]  — prints the Triforge root or fails closed naming at-setup"
    exit 0 ;;
esac
echo "fixture-root"
# drifted copy: one extra line
