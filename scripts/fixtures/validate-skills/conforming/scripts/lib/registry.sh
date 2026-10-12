#!/usr/bin/env bash
# The registry lane may branch on the lead's CLI: KTD1 excludes registry.sh and roster.sh by name.
resolve_lead() { printf 'codex\t\t\n'; }
LEAD_CLI="$(resolve_lead | cut -f1)"
case "$LEAD_CLI" in
  codex)  echo "codex lead" ;;
  claude) echo "claude lead" ;;
esac
