#!/usr/bin/env bash
# Worker lane: a case over the WORKER's CLI stays legal (KTD1 bans it only for the lead's value).
_adapter_env() {
  local CLI="$1"
  case "$CLI" in
    claude) echo "claude lane" ;;
    codex)  echo "codex lane" ;;
    *)      echo "other lane" ;;
  esac
  if [ "$CLI" = codex ]; then echo "codex worker"; fi
}
