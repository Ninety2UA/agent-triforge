#!/usr/bin/env bash
# KTD1 fixture: a case over the lead's CLI value must fail.
case "$LEAD_CLI" in
  codex)  echo "codex lead" ;;
  claude) echo "claude lead" ;;
esac
