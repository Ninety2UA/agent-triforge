#!/usr/bin/env bash
# KTD1 fixture: a comparison of the lead's CLI value with a literal must fail.
if [ "$(resolve_lead | cut -f1)" = codex ]; then
  echo "codex lead"
fi
