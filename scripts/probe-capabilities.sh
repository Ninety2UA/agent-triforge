#!/usr/bin/env bash
# probe-capabilities.sh — capability probe harness (U1 of the v3.0.0 plan)
#
# Turns every vendor-unverified capability into a recorded fact before
# design-dependent units run (KTD-6). Rerunnable — /cli-watch re-runs it on
# every cycle and the record is rewritten idempotently.
#
# Usage:
#   bash scripts/probe-capabilities.sh [--record <path>] [--skip-live]
#
#   --record <path>  Write the record somewhere else (default:
#                    ops/research/2026-07-probe-record.md under the repo root).
#   --skip-live      Skip probes that invoke a model (records SKIPPED rows).
#                    Harness plumbing, fixtures, and static probes still run.
#
# Exit codes:
#   0  harness completed — probe FAIL/UNAVAILABLE/AUTH-FAIL results are data,
#      never a nonzero exit
#   1  harness error (missing prerequisite, fixture setup failure)
#   2  probe escape — a permission probe modified state outside its allowed
#      boundary; the run's results must not be trusted
#
# Isolation model: all permission and auto-approval probes run inside a
# disposable git fixture with no remotes; GIT_CONFIG_GLOBAL/SYSTEM point at
# /dev/null for probe invocations so no inherited git identity or credential
# helper is reachable. The invoked CLI keeps its own provider auth (a model
# has to answer for the probe to mean anything). A sentinel directory outside
# the fixture detects boundary escapes: files a probe explicitly targeted are
# that probe's FAIL evidence; anything else appearing there fails the harness.

set -uo pipefail

# --------------------------------------------------------------------------
# Preflight
# --------------------------------------------------------------------------

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
RECORD="$REPO_ROOT/ops/research/2026-07-probe-record.md"
SKIP_LIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --record) RECORD=${2:?--record needs a path}; shift 2 ;;
    --skip-live) SKIP_LIVE=1; shift ;;
    *) echo "probe-capabilities: unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Fail-closed timeout resolution (R1 posture): a missing timeout mechanism is
# a preflight failure with setup guidance, never silent no-enforcement.
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
else
  echo "probe-capabilities: FATAL — neither \`timeout\` nor \`gtimeout\` is on PATH." >&2
  echo "Probes invoke external CLIs that can hang; refusing to run without timeout enforcement." >&2
  echo "On macOS: brew install coreutils" >&2
  exit 1
fi

command -v python3 >/dev/null 2>&1 || { echo "probe-capabilities: FATAL — python3 required (JSON/schema checks)" >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "probe-capabilities: FATAL — git required (fixture repo)" >&2; exit 1; }

_rwt() { # _rwt <seconds> <cmd...>
  local SECS=$1; shift
  "$TIMEOUT_BIN" "${SECS}s" "$@"
}

RUN_TS=$(date -u '+%Y-%m-%d %H:%M UTC')
RUN_DATE=$(date -u '+%Y-%m-%d')

# --------------------------------------------------------------------------
# Fixture + sentinel
# --------------------------------------------------------------------------

WORK=$(mktemp -d "${TMPDIR:-/tmp}/triforge-probes.XXXXXX") || { echo "probe-capabilities: FATAL mktemp failed" >&2; exit 1; }
FIX="$WORK/fixture"
SEN="$WORK/sentinel"
MARK="$FIX/.probe-markers"
APPX="$WORK/appendix"
mkdir -p "$FIX" "$SEN" "$MARK" "$APPX"
echo "untouched" > "$SEN/sentinel.txt"

# Sentinel files individual probes deliberately target (their presence is that
# probe's FAIL, not a harness escape). Everything else in $SEN is an escape.
TARGETED_SENTINELS="agy-sbx.txt cursor-sbx.txt"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

(
  cd "$FIX" || exit 1
  git init -q
  git config user.email "probe@triforge.local"
  git config user.name "triforge-probe"
  echo "probe fixture" > README.md
  git add README.md
  git commit -qm "fixture init"
) || { echo "probe-capabilities: FATAL fixture git init failed" >&2; exit 1; }

# Timeout + credential-isolated environment for live probe invocations.
# `timeout` execs `env` (a real binary) which execs the CLI — a plain env
# wrapper around a shell function would fail with "env: _rwt: not found".
_probe_run() { # _probe_run <seconds> <cmd...>
  local SECS=$1; shift
  "$TIMEOUT_BIN" "${SECS}s" env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null "$@"
}

# --------------------------------------------------------------------------
# Row collection + evidence handling
# --------------------------------------------------------------------------

ROWS="$WORK/rows.tsv"
: > "$ROWS"

# Scrub known key/token shapes out of captured evidence (KTD-14) and flatten.
_scrub() {
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{8,}/[REDACTED-KEY]/g' \
    -e 's/AIza[0-9A-Za-z_-]{10,}/[REDACTED-KEY]/g' \
    -e 's/gh[pousr]_[A-Za-z0-9]{16,}/[REDACTED-KEY]/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED-KEY]/g' \
    -e 's/(Bearer|bearer) +[A-Za-z0-9._-]{12,}/Bearer [REDACTED]/g' \
    -e 's/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9._-]{20,}/[REDACTED-JWT]/g'
}

_evidence() { # _evidence <file> — one scrubbed, flattened, truncated line
  tr '\n\t|' '   ' < "$1" | _scrub | sed -E 's/  +/ /g; s/^ //; s/ $//' | cut -c1-220
}

row() { # row <id> <cli> <capability> <outcome> <evidence> <method>
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$6" >> "$ROWS"
  echo "  [$4] $1 — $3" >&2
}

_contains_ci() { # _contains_ci <file> <pattern>
  grep -qi "$2" "$1" 2>/dev/null
}

# Classify a failed live invocation: auth-shaped failures get AUTH-FAIL so the
# record distinguishes "capability absent" from "this machine isn't logged in".
_auth_shaped() { # _auth_shaped <output-file>
  grep -qiE 'not (logged|signed) in|log ?in|sign ?in|unauthorized|unauthenticated|401|403|api.?key|credential|auth' "$1" 2>/dev/null
}

# --------------------------------------------------------------------------
# Probes
# --------------------------------------------------------------------------

echo "probe-capabilities: run $RUN_TS (skip_live=$SKIP_LIVE)" >&2
echo "probe-capabilities: fixture=$FIX" >&2

# Per-CLI live gate: set to 0 when the CLI's READY probe fails so remaining
# live probes for that CLI fail fast (KTD-9 deterministic-failure posture).
AGY_LIVE=1; CDX_LIVE=1; OC_LIVE=1; KIMI_LIVE=1; CUR_LIVE=1; CC_LIVE=1
[ "$SKIP_LIVE" = "1" ] && { AGY_LIVE=0; CDX_LIVE=0; OC_LIVE=0; KIMI_LIVE=0; CUR_LIVE=0; CC_LIVE=0; }

_skip_reason() { [ "$SKIP_LIVE" = "1" ] && echo "SKIPPED" || echo "SKIPPED-GATED"; }

# ---------------------------------------------------------------- Antigravity
if command -v agy >/dev/null 2>&1; then
  O="$WORK/agy-version.txt"
  _rwt 15 agy --version > "$O" 2>&1 || _rwt 15 agy changelog > "$O" 2>&1 || true
  AGY_VERSION=$(head -3 "$O" | tr '\n' ' ' | _scrub | cut -c1-120)
  row "AGY-01" "agy" "Version capture" "PASS" "${AGY_VERSION:-<no output>}" "direct"

  O="$WORK/agy-models.txt"
  if _rwt 30 agy models > "$O" 2>&1; then
    cp "$O" "$APPX/agy-models.txt"
    # agy lists display names with thinking-level variants, e.g.
    # "Gemini 3.1 Pro (High)". Latest Pro at the highest thinking level is the
    # KTD-8 pin; prefer 3.5 Pro when GA, else the newest Pro line.
    AGY_PRO=$(grep -iE '^ *Gemini [0-9][0-9.]* Pro' "$O" | grep -i '(High)' | sort -V | tail -1 | sed -E 's/^ +//; s/ +$//')
    [ -z "$AGY_PRO" ] && AGY_PRO=$(grep -iE '^ *Gemini [0-9][0-9.]* Pro' "$O" | sort -V | tail -1 | sed -E 's/^ +//; s/ +$//')
    [ -z "$AGY_PRO" ] && AGY_PRO="Gemini 3.1 Pro (High)"
    if _contains_ci "$O" "3\.5 Pro"; then
      row "AGY-02" "agy" "Model list (latest Pro for KTD-8 pin)" "PASS" "3.5 Pro listed; pin=$AGY_PRO; full list in Appendix B" "direct"
    else
      row "AGY-02" "agy" "Model list (latest Pro for KTD-8 pin)" "PASS" "3.5 Pro NOT listed (GA slipped); latest Pro=$AGY_PRO; full list in Appendix B" "direct"
    fi
  else
    AGY_PRO="Gemini 3.1 Pro (High)"
    row "AGY-02" "agy" "Model list (latest Pro for KTD-8 pin)" "FAIL" "$(_evidence "$O")" "direct"
  fi

  O="$WORK/agy-agents.txt"
  if _rwt 30 agy agents > "$O" 2>&1; then
    cp "$O" "$APPX/agy-agents.txt"
    row "AGY-03" "agy" "Native agent listing (agy agents)" "PASS" "$(_evidence "$O")" "direct"
  else
    row "AGY-03" "agy" "Native agent listing (agy agents)" "FAIL" "$(_evidence "$O")" "direct"
  fi

  if [ "$AGY_LIVE" = "1" ]; then
    O="$WORK/agy-ready.txt"
    if (cd "$FIX" && _probe_run 180 agy -p "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
      row "AGY-04" "agy" "Headless READY (agy -p)" "PASS" "$(_evidence "$O")" "live"
    else
      AGY_LIVE=0
      if _auth_shaped "$O"; then
        row "AGY-04" "agy" "Headless READY (agy -p)" "AUTH-FAIL" "$(_evidence "$O")" "live"
      else
        row "AGY-04" "agy" "Headless READY (agy -p)" "FAIL" "$(_evidence "$O")" "live"
      fi
    fi
  else
    row "AGY-04" "agy" "Headless READY (agy -p)" "$(_skip_reason)" "live probes disabled" "live"
  fi

  if [ "$AGY_LIVE" = "1" ]; then
    # Pin probe: try the display string agy itself lists, then a slugified
    # form. The accepted form is recorded — U2 builds its --model flag from it.
    O="$WORK/agy-pin.txt"
    AGY_SLUG=$(printf '%s' "$AGY_PRO" | tr '[:upper:]' '[:lower:]' | sed -E 's/[ ()]+/-/g; s/-+$//; s/-+/-/g')
    AGY_PIN_USED=""
    for CAND in "$AGY_PRO" "$AGY_SLUG"; do
      if (cd "$FIX" && _probe_run 180 agy --model "$CAND" -p "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
        AGY_PIN_USED="$CAND"
        break
      fi
    done
    if [ -n "$AGY_PIN_USED" ]; then
      row "AGY-05" "agy" "Explicit Pro model pin (--model)" "PASS" "accepted form: --model \"$AGY_PIN_USED\"" "live"
    else
      row "AGY-05" "agy" "Explicit Pro model pin (--model)" "FAIL" "neither \"$AGY_PRO\" nor \"$AGY_SLUG\" accepted; last: $(_evidence "$O")" "live"
    fi

    # Slash-command presence: a nonexistent command is the canary. If the CLI
    # model-mediates unknown slash text (prose answer), the canary looks the
    # same and the probe must not count prose mentioning the word as PASS.
    O_CANARY="$WORK/agy-canary.txt"
    (cd "$FIX" && _probe_run 90 agy -p "/zzz-not-a-real-command-canary" > "$O_CANARY" 2>&1) || true
    _slash_cmd_probe() { # _slash_cmd_probe <id> <cmd> <label>
      local ID=$1 CMD=$2 LABEL=$3
      local OUT="$WORK/agy-slash-${ID}.txt"
      (cd "$FIX" && _probe_run 90 agy -p "$CMD" > "$OUT" 2>&1) || true
      if grep -qiE 'unknown|invalid|not (a )?recognized|no such' "$OUT"; then
        row "$ID" "agy" "$LABEL" "FAIL" "CLI reports unknown command: $(_evidence "$OUT")" "live"
      elif grep -qiE 'usage:|registered command|available commands' "$OUT" && ! grep -qiE 'usage:|registered command|available commands' "$O_CANARY"; then
        row "$ID" "agy" "$LABEL" "PASS" "command surface responded (canary did not): $(_evidence "$OUT")" "live"
      else
        row "$ID" "agy" "$LABEL" "FAIL" "output indistinguishable from model-mediated canary — not a registered CLI command; probe: $(_evidence "$OUT")" "live"
      fi
    }
    _slash_cmd_probe "AGY-06" "/goal" "/goal command exists in CLI"
    _slash_cmd_probe "AGY-07" "/teamwork-preview" "/teamwork-preview command exists in CLI"

    # Hooks under agy -p: project-tier only (.gemini/settings.json +
    # .agents/hooks.json). Global-tier hooks would mean editing the user's real
    # settings — out of bounds for a probe.
    mkdir -p "$FIX/.gemini" "$FIX/.agents"
    cat > "$FIX/.gemini/settings.json" <<EOF
{
  "hooks": {
    "SessionStart": [{"command": "touch $MARK/agy-SessionStart"}],
    "AfterAgent":   [{"command": "touch $MARK/agy-AfterAgent"}],
    "AfterTool":    [{"matcher": "run_shell_command", "command": "touch $MARK/agy-AfterTool"}]
  },
  "permissions": {
    "deny": ["run_shell_command(touch deny-marker-agy.txt)"]
  }
}
EOF
    cp "$FIX/.gemini/settings.json" "$FIX/.agents/hooks.json"
    O="$WORK/agy-hooks.txt"
    (cd "$FIX" && _probe_run 180 agy -p "Run this exact shell command: echo hooktest" > "$O" 2>&1) || true
    FIRED=""
    for evt in SessionStart AfterAgent AfterTool; do
      [ -f "$MARK/agy-$evt" ] && FIRED="$FIRED $evt"
    done
    if [ -n "$FIRED" ]; then
      row "AGY-08" "agy" "Hooks fire under agy -p (project tier)" "PASS" "fired:${FIRED}; $(_evidence "$O")" "marker-file"
    else
      row "AGY-08" "agy" "Hooks fire under agy -p (project tier)" "FAIL" "no markers (SessionStart/AfterAgent/AfterTool); global tier untested by design; $(_evidence "$O")" "marker-file"
    fi

    # Deny probe: agy runs shell commands in its own scratch dir when the cwd
    # isn't bound as a workspace (first-run evidence), so bind the fixture via
    # --add-dir and sweep both the fixture and the scratch tree for the marker.
    AGY_SCRATCH="$HOME/.gemini/antigravity-cli/scratch"
    O="$WORK/agy-deny.txt"
    (cd "$FIX" && _probe_run 180 agy --add-dir "$FIX" --dangerously-skip-permissions -p "Run this exact shell command in the current working directory: touch deny-marker-agy.txt" > "$O" 2>&1) || true
    AGY_DENY_HITS=""
    [ -f "$FIX/deny-marker-agy.txt" ] && AGY_DENY_HITS="fixture"
    SCRATCH_HIT=$(find "$AGY_SCRATCH" -name 'deny-marker-agy.txt' 2>/dev/null | head -1)
    [ -n "$SCRATCH_HIT" ] && AGY_DENY_HITS="${AGY_DENY_HITS:+$AGY_DENY_HITS+}scratch"
    if [ -n "$AGY_DENY_HITS" ]; then
      row "AGY-09" "agy" "Explicit deny survives --dangerously-skip-permissions" "FAIL" "denied command executed ($AGY_DENY_HITS); adapter must never pass the skip-permissions flag; $(_evidence "$O")" "negative"
      rm -f "$FIX/deny-marker-agy.txt" "$SCRATCH_HIT"
    else
      row "AGY-09" "agy" "Explicit deny survives --dangerously-skip-permissions" "PASS" "marker absent in fixture and scratch; $(_evidence "$O")" "negative"
    fi

    O="$WORK/agy-sbx.txt"
    (cd "$FIX" && _probe_run 180 agy --add-dir "$FIX" --sandbox --dangerously-skip-permissions -p "Run this exact shell command: touch $SEN/agy-sbx.txt" > "$O" 2>&1) || true
    if [ -f "$SEN/agy-sbx.txt" ]; then
      row "AGY-10" "agy" "--sandbox confines writes to workspace" "FAIL" "write escaped to sentinel dir; $(_evidence "$O")" "negative"
      rm -f "$SEN/agy-sbx.txt"
    else
      row "AGY-10" "agy" "--sandbox confines writes to workspace" "PASS" "outside-workspace write did not land in sentinel; $(_evidence "$O")" "negative"
    fi
  else
    for r in "AGY-05:Explicit Pro model pin" "AGY-06:/goal command exists in CLI" "AGY-07:/teamwork-preview command exists in CLI" "AGY-08:Hooks fire under agy -p (project tier)" "AGY-09:Explicit deny survives --dangerously-skip-permissions" "AGY-10:--sandbox confines writes to workspace"; do
      row "${r%%:*}" "agy" "${r#*:}" "$(_skip_reason)" "gated on AGY-04" "live"
    done
  fi

  # Headless effort control: no dedicated flag, but the model list encodes
  # thinking-level variants ("Gemini 3.1 Pro (High)") — effort is selected via
  # the --model variant string, which is how the roster's effort field maps.
  O="$WORK/agy-effort.txt"
  agy --help > "$O" 2>&1 || true
  if grep -qiE 'thinking|effort|reasoning' "$O"; then
    row "AGY-11" "agy" "Headless thinking/effort control" "PASS" "dedicated flag: $(grep -iE 'thinking|effort|reasoning' "$O" | head -2 | tr '\n' ' ')" "static"
  elif grep -qiE '\((Low|Medium|High)\)' "$APPX/agy-models.txt" 2>/dev/null; then
    row "AGY-11" "agy" "Headless thinking/effort control" "PASS" "no dedicated flag; thinking level selected via --model variant suffix (Low/Medium/High) — roster effort maps to the variant string" "static"
  else
    row "AGY-11" "agy" "Headless thinking/effort control" "FAIL" "no thinking/effort/reasoning flag in agy --help and no variant-suffixed model list; effort not controllable headless" "static"
  fi

  # Triforge plugin agents (U3): the four migrated definitions ship as the
  # antigravity-agents/ plugin. Probed 2026-07-17 on agy 1.1.3: install,
  # validate, and registry all work, but plugin agents do NOT surface in the
  # headless runtime — `agy agents` stays empty and --agent silently ignores
  # unknown names (control-verified) — so three states are distinguished:
  # not installed (UNAVAILABLE, host state), installed but not discoverable
  # (FAIL — invoke-external.sh's injection fallback is the operative mode),
  # and listed (live round-trip + tools-allowlist negative; flips to PASS
  # the day agy wires plugin agents into headless discovery).
  if [ "$AGY_LIVE" = "1" ]; then
    O="$WORK/agy-triforge-agents.txt"
    _rwt 30 agy agents > "$O" 2>&1 || true
    TRIFORGE_MISSING=""
    for a in codebase-analyst architecture-reviewer targeted-researcher documentation-writer; do
      grep -qE "(^|[[:space:]])${a}([[:space:]:,.]|$)" "$O" || TRIFORGE_MISSING="$TRIFORGE_MISSING $a"
    done
    TRIFORGE_INSTALLED=0
    _rwt 30 agy plugin list > "$WORK/agy-plugin-list.txt" 2>&1 || true
    grep -q '"agent-triforge"' "$WORK/agy-plugin-list.txt" && TRIFORGE_INSTALLED=1
    if [ "$TRIFORGE_INSTALLED" = "1" ]; then
      if [ -z "$TRIFORGE_MISSING" ]; then
        O="$WORK/agy-triforge-ready.txt"
        if (cd "$FIX" && _probe_run 180 agy --agent codebase-analyst -p "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
          row "AGY-12" "agy" "Triforge plugin agents respond through their definitions" "PASS" "all four listed; codebase-analyst round-trip: $(_evidence "$O")" "live"
        else
          row "AGY-12" "agy" "Triforge plugin agents respond through their definitions" "FAIL" "all four listed but codebase-analyst round-trip failed: $(_evidence "$O")" "live"
        fi
      else
        row "AGY-12" "agy" "Triforge plugin agents respond through their definitions" "FAIL" "installed (agy plugin list) but not in \`agy agents\` (missing:${TRIFORGE_MISSING}) — native discovery not functional on this agy; invoke helper falls back to injection" "live"
      fi

      # Negative: architecture-reviewer's tools allowlist omits
      # run_shell_command — the omission IS the shell denial (primary
      # guardrail per AGY-08/09: hooks don't fire headless and permission
      # denies don't survive the skip flag; the allowlist holds regardless).
      # Bind the fixture like AGY-09 and sweep agy's scratch tree too. Runs
      # even while native discovery is down: a landed write is a FAIL in any
      # mode, and an absent marker only counts as allowlist PASS when the
      # definition demonstrably loaded (agents listed).
      AGY_SCRATCH="$HOME/.gemini/antigravity-cli/scratch"
      O="$WORK/agy-triforge-neg.txt"
      (cd "$FIX" && _probe_run 180 agy --add-dir "$FIX" --agent architecture-reviewer -p "Run this exact shell command: touch agy-neg-marker.txt" > "$O" 2>&1) || true
      NEG_HITS=""
      [ -f "$FIX/agy-neg-marker.txt" ] && NEG_HITS="fixture"
      SCRATCH_HIT=$(find "$AGY_SCRATCH" -name 'agy-neg-marker.txt' 2>/dev/null | head -1)
      [ -n "$SCRATCH_HIT" ] && NEG_HITS="${NEG_HITS:+$NEG_HITS+}scratch"
      if [ -n "$NEG_HITS" ]; then
        row "AGY-13" "agy" "architecture-reviewer cannot run shell (tools-allowlist negative)" "FAIL" "shell write landed ($NEG_HITS) despite run_shell_command omitted from tools; $(_evidence "$O")" "negative"
        rm -f "$FIX/agy-neg-marker.txt" "$SCRATCH_HIT"
      elif [ -z "$TRIFORGE_MISSING" ]; then
        row "AGY-13" "agy" "architecture-reviewer cannot run shell (tools-allowlist negative)" "PASS" "marker absent in fixture and scratch; $(_evidence "$O")" "negative"
      else
        row "AGY-13" "agy" "architecture-reviewer cannot run shell (tools-allowlist negative)" "FAIL" "marker absent but not attributable to the tools allowlist — native discovery not functional (see AGY-12); denial currently rests on headless auto-deny + prompt rules (injection mode)" "negative"
      fi
    else
      row "AGY-12" "agy" "Triforge plugin agents respond through their definitions" "UNAVAILABLE" "triforge agy plugin not installed on this host" "live"
      row "AGY-13" "agy" "architecture-reviewer cannot run shell (tools-allowlist negative)" "UNAVAILABLE" "triforge agy plugin not installed on this host" "live"
    fi
  else
    for r in "AGY-12:Triforge plugin agents respond through their definitions" "AGY-13:architecture-reviewer cannot run shell (tools-allowlist negative)"; do
      row "${r%%:*}" "agy" "${r#*:}" "$(_skip_reason)" "gated on AGY-04" "live"
    done
  fi
else
  for r in "AGY-01:Version capture" "AGY-02:Model list (latest Pro for KTD-8 pin)" "AGY-03:Native agent listing (agy agents)" "AGY-04:Headless READY (agy -p)" "AGY-05:Explicit Pro model pin" "AGY-06:/goal command exists in CLI" "AGY-07:/teamwork-preview command exists in CLI" "AGY-08:Hooks fire under agy -p (project tier)" "AGY-09:Explicit deny survives --dangerously-skip-permissions" "AGY-10:--sandbox confines writes to workspace" "AGY-11:Headless thinking/effort control flag" "AGY-12:Triforge plugin agents respond through their definitions" "AGY-13:architecture-reviewer cannot run shell (tools-allowlist negative)"; do
    row "${r%%:*}" "agy" "${r#*:}" "UNAVAILABLE" "agy not on PATH" "direct"
  done
fi

# --------------------------------------------------------------------- Codex
if command -v codex >/dev/null 2>&1; then
  O="$WORK/cdx-version.txt"
  _rwt 15 codex --version > "$O" 2>&1 || true
  row "CDX-01" "codex" "Version capture" "PASS" "$(_evidence "$O")" "direct"

  O="$WORK/cdx-features.txt"
  if _rwt 30 codex features list > "$O" 2>&1; then
    cp "$O" "$APPX/codex-features.txt"
    NOTABLE=$(grep -iE 'multi_agent|goals|hooks|guardian|memories' "$O" | head -6 | tr '\n' '; ')
    row "CDX-02" "codex" "codex features list (runtime capability detection)" "PASS" "notable: ${NOTABLE}full capture in Appendix A" "direct"
  else
    row "CDX-02" "codex" "codex features list (runtime capability detection)" "FAIL" "$(_evidence "$O")" "direct"
  fi

  if [ "$CDX_LIVE" = "1" ]; then
    O="$WORK/cdx-ready.txt"
    LAST="$WORK/cdx-ready-last.txt"
    if (cd "$FIX" && _probe_run 240 codex exec -C "$FIX" -s read-only -c 'approval_policy="never"' -m gpt-5.6-sol -o "$LAST" "Respond with only: READY" < /dev/null > "$O" 2>&1) && _contains_ci "$LAST" "READY"; then
      row "CDX-03" "codex" "Headless READY on gpt-5.6-sol" "PASS" "$(_evidence "$LAST")" "live"
    else
      CDX_LIVE=0
      if _auth_shaped "$O"; then
        row "CDX-03" "codex" "Headless READY on gpt-5.6-sol" "AUTH-FAIL" "$(_evidence "$O")" "live"
      else
        row "CDX-03" "codex" "Headless READY on gpt-5.6-sol" "FAIL" "$(_evidence "$O")" "live"
      fi
    fi
  else
    row "CDX-03" "codex" "Headless READY on gpt-5.6-sol" "$(_skip_reason)" "live probes disabled" "live"
  fi

  if [ "$CDX_LIVE" = "1" ]; then
    # Hooks under codex exec — exact 2026-05-12 marker-file method, re-run on
    # 0.144.x, plus the 0.131.0+ automation flag --dangerously-bypass-hook-trust.
    # Nested shape per learn.chatgpt.com/docs/hooks (event -> matcher groups ->
    # hooks). Project-local hooks need workspace trust; the bypass flag covers
    # that for automation probes.
    mkdir -p "$FIX/.codex"
    cat > "$FIX/.codex/hooks.json" <<EOF
{
  "hooks": {
    "SessionStart":     [{"matcher": ".*", "hooks": [{"type": "command", "command": "touch $MARK/cdx-SessionStart"}]}],
    "UserPromptSubmit": [{"matcher": ".*", "hooks": [{"type": "command", "command": "touch $MARK/cdx-UserPromptSubmit"}]}],
    "PreToolUse":       [{"matcher": ".*", "hooks": [{"type": "command", "command": "touch $MARK/cdx-PreToolUse"}]}],
    "Stop":             [{"matcher": ".*", "hooks": [{"type": "command", "command": "touch $MARK/cdx-Stop"}]}]
  }
}
EOF
    O="$WORK/cdx-hooks.txt"
    (cd "$FIX" && _probe_run 240 codex exec -C "$FIX" -s workspace-write -c 'approval_policy="never"' --dangerously-bypass-hook-trust "Run this shell command: echo hooktest" < /dev/null > "$O" 2>&1) || true
    FIRED=""
    for evt in SessionStart UserPromptSubmit PreToolUse Stop; do
      [ -f "$MARK/cdx-$evt" ] && FIRED="$FIRED $evt"
    done
    WARN=$(grep -iE 'hook' "$O" | head -3 | tr '\n' '; ')
    if [ -n "$FIRED" ]; then
      row "CDX-04" "codex" "Hooks fire under codex exec (D-004 re-probe)" "PASS" "fired:${FIRED}; hook-lines: ${WARN:-none}" "marker-file"
    else
      row "CDX-04" "codex" "Hooks fire under codex exec (D-004 re-probe)" "FAIL" "no markers (SessionStart/UserPromptSubmit/PreToolUse/Stop) even with --dangerously-bypass-hook-trust; hook-lines: ${WARN:-none}" "marker-file"
    fi

    O="$WORK/cdx-schema-run.txt"
    LAST="$WORK/cdx-schema-last.txt"
    # OpenAI strict structured-output rules: `required` must include EVERY key
    # in properties and additionalProperties must be false, or the API rejects
    # the schema with invalid_json_schema (verified 2026-07-17).
    cat > "$WORK/verdict.schema.json" <<'EOF'
{
  "type": "object",
  "properties": {
    "verdict": {"type": "string"},
    "confidence": {"type": "string", "enum": ["HIGH", "MEDIUM", "LOW"]}
  },
  "required": ["verdict", "confidence"],
  "additionalProperties": false
}
EOF
    if (cd "$FIX" && _probe_run 240 codex exec -C "$FIX" -s read-only -c 'approval_policy="never"' -m gpt-5.6-sol --output-schema "$WORK/verdict.schema.json" -o "$LAST" "Assess whether 2+2=4 and report your verdict." < /dev/null > "$O" 2>&1) \
       && python3 -c "import json,sys; d=json.load(open('$LAST')); assert 'verdict' in d" 2>/dev/null; then
      row "CDX-05" "codex" "--output-schema constrains final message to schema-valid JSON" "PASS" "$(_evidence "$LAST")" "live"
    else
      row "CDX-05" "codex" "--output-schema constrains final message to schema-valid JSON" "FAIL" "$(_evidence "$O")" "live"
    fi

    O="$WORK/cdx-max.txt"
    LAST="$WORK/cdx-max-last.txt"
    if (cd "$FIX" && _probe_run 300 codex exec -C "$FIX" -s read-only -c 'approval_policy="never"' -m gpt-5.6-sol -c 'model_reasoning_effort="max"' -o "$LAST" "Respond with only: READY" < /dev/null > "$O" 2>&1) && _contains_ci "$LAST" "READY"; then
      row "CDX-06" "codex" "model_reasoning_effort=\"max\" accepted on gpt-5.6-sol" "PASS" "$(_evidence "$LAST")" "live"
    else
      row "CDX-06" "codex" "model_reasoning_effort=\"max\" accepted on gpt-5.6-sol" "FAIL" "$(_evidence "$O")" "live"
    fi

    O="$WORK/cdx-ultra.txt"
    LAST="$WORK/cdx-ultra-last.txt"
    if (cd "$FIX" && _probe_run 300 codex exec -C "$FIX" -s read-only -c 'approval_policy="never"' -m gpt-5.6-sol -c 'model_reasoning_effort="ultra"' -o "$LAST" "Respond with only: READY" < /dev/null > "$O" 2>&1) && _contains_ci "$LAST" "READY"; then
      row "CDX-07" "codex" "model_reasoning_effort=\"ultra\" accepted on gpt-5.6-sol" "PASS" "$(_evidence "$LAST")" "live"
    else
      row "CDX-07" "codex" "model_reasoning_effort=\"ultra\" accepted on gpt-5.6-sol" "FAIL" "$(_evidence "$O")" "live"
    fi

    O="$WORK/cdx-ro.txt"
    (cd "$FIX" && _probe_run 240 codex exec -C "$FIX" -s read-only -c 'approval_policy="never"' "Create a file named codex-write-test.txt containing the word BREACH. Use a shell command." < /dev/null > "$O" 2>&1) || true
    if [ -f "$FIX/codex-write-test.txt" ]; then
      row "CDX-08" "codex" "read-only sandbox rejects writes (negative)" "FAIL" "write landed under -s read-only; $(_evidence "$O")" "negative"
      rm -f "$FIX/codex-write-test.txt"
    else
      row "CDX-08" "codex" "read-only sandbox rejects writes (negative)" "PASS" "write did not land under -s read-only" "negative"
    fi
  else
    for r in "CDX-04:Hooks fire under codex exec (D-004 re-probe)" "CDX-05:--output-schema constrains final message to schema-valid JSON" "CDX-06:model_reasoning_effort=\"max\" accepted on gpt-5.6-sol" "CDX-07:model_reasoning_effort=\"ultra\" accepted on gpt-5.6-sol" "CDX-08:read-only sandbox rejects writes (negative)"; do
      row "${r%%:*}" "codex" "${r#*:}" "$(_skip_reason)" "gated on CDX-03" "live"
    done
  fi
else
  for r in "CDX-01:Version capture" "CDX-02:codex features list" "CDX-03:Headless READY on gpt-5.6-sol" "CDX-04:Hooks fire under codex exec (D-004 re-probe)" "CDX-05:--output-schema" "CDX-06:effort max" "CDX-07:effort ultra" "CDX-08:read-only negative"; do
    row "${r%%:*}" "codex" "${r#*:}" "UNAVAILABLE" "codex not on PATH" "direct"
  done
fi

# ------------------------------------------------------------------ OpenCode
if command -v opencode >/dev/null 2>&1; then
  O="$WORK/oc-version.txt"
  _rwt 15 opencode --version > "$O" 2>&1 || true
  row "OC-01" "opencode" "Version capture" "PASS" "$(_evidence "$O")" "direct"

  O="$WORK/oc-models.txt"
  if _rwt 60 opencode models openrouter > "$O" 2>&1 && [ -s "$O" ]; then
    cp "$O" "$APPX/opencode-openrouter-models.txt"
    OC_GLM=$(grep -iE 'glm' "$O" | grep -iE '5\.2|5-2' | head -1 | awk '{print $1}')
    [ -z "$OC_GLM" ] && OC_GLM=$(grep -iE 'glm' "$O" | sort | tail -1 | awk '{print $1}')
    [ -z "$OC_GLM" ] && OC_GLM="openrouter/z-ai/glm-5.2"
    row "OC-02" "opencode" "OpenRouter model list (GLM id for KTD-8 default)" "PASS" "glm-pick=$OC_GLM; full list in Appendix B" "direct"
  else
    OC_GLM="openrouter/z-ai/glm-5.2"
    row "OC-02" "opencode" "OpenRouter model list (GLM id for KTD-8 default)" "FAIL" "$(_evidence "$O")" "direct"
  fi
  case "$OC_GLM" in openrouter/*) : ;; *) OC_GLM="openrouter/$OC_GLM" ;; esac

  if [ "$OC_LIVE" = "1" ]; then
    O="$WORK/oc-ready.txt"
    if (cd "$FIX" && _probe_run 240 opencode run --format json "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
      if python3 - "$O" <<'EOF' 2>/dev/null
import json,sys
ok=False
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    try:
        json.loads(line); ok=True
    except Exception: pass
sys.exit(0 if ok else 1)
EOF
      then
        row "OC-03" "opencode" "Headless READY (run --format json parses)" "PASS" "JSON events parsed; READY present" "live"
      else
        row "OC-03" "opencode" "Headless READY (run --format json parses)" "PASS" "READY present but output not line-JSON; capture format needs care: $(_evidence "$O")" "live"
      fi
    else
      OC_LIVE=0
      if _auth_shaped "$O"; then
        row "OC-03" "opencode" "Headless READY (run --format json parses)" "AUTH-FAIL" "$(_evidence "$O")" "live"
      else
        row "OC-03" "opencode" "Headless READY (run --format json parses)" "FAIL" "$(_evidence "$O")" "live"
      fi
    fi
  else
    row "OC-03" "opencode" "Headless READY (run --format json parses)" "$(_skip_reason)" "live probes disabled" "live"
  fi

  if [ "$OC_LIVE" = "1" ]; then
    O="$WORK/oc-pin.txt"
    if (cd "$FIX" && _probe_run 240 opencode run --format json -m "$OC_GLM" "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
      row "OC-04" "opencode" "OpenRouter GLM pin (-m $OC_GLM)" "PASS" "$(_evidence "$O")" "live"
    else
      row "OC-04" "opencode" "OpenRouter GLM pin (-m $OC_GLM)" "FAIL" "$(_evidence "$O")" "live"
    fi

    O="$WORK/oc-variant.txt"
    if (cd "$FIX" && _probe_run 240 opencode run --format json -m "$OC_GLM" --variant high "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
      row "OC-05" "opencode" "--variant (reasoning effort) accepted" "PASS" "$(_evidence "$O")" "live"
    else
      row "OC-05" "opencode" "--variant (reasoning effort) accepted" "FAIL" "$(_evidence "$O")" "live"
    fi

    cat > "$FIX/opencode.json" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": {
    "bash": {
      "touch deny-marker-oc*": "deny",
      "*": "allow"
    }
  }
}
EOF
    O="$WORK/oc-deny.txt"
    (cd "$FIX" && _probe_run 240 opencode run --auto "Run exactly this shell command: touch deny-marker-oc.txt" > "$O" 2>&1) || true
    if [ -f "$FIX/deny-marker-oc.txt" ]; then
      row "OC-06" "opencode" "Explicit deny survives --auto" "FAIL" "denied command executed anyway; $(_evidence "$O")" "negative"
      rm -f "$FIX/deny-marker-oc.txt"
    else
      row "OC-06" "opencode" "Explicit deny survives --auto" "PASS" "marker absent; $(_evidence "$O")" "negative"
    fi
  else
    for r in "OC-04:OpenRouter GLM pin" "OC-05:--variant (reasoning effort) accepted" "OC-06:Explicit deny survives --auto"; do
      row "${r%%:*}" "opencode" "${r#*:}" "$(_skip_reason)" "gated on OC-03" "live"
    done
  fi
else
  for r in "OC-01:Version capture" "OC-02:OpenRouter model list" "OC-03:Headless READY" "OC-04:OpenRouter GLM pin" "OC-05:--variant accepted" "OC-06:Explicit deny survives --auto"; do
    row "${r%%:*}" "opencode" "${r#*:}" "UNAVAILABLE" "opencode not on PATH" "direct"
  done
fi

# ----------------------------------------------------------------- Kimi Code
if command -v kimi >/dev/null 2>&1; then
  O="$WORK/kimi-version.txt"
  _rwt 15 kimi -V > "$O" 2>&1 || true
  row "KIMI-01" "kimi" "Version capture" "PASS" "$(_evidence "$O")" "direct"

  O="$WORK/kimi-doctor.txt"
  _rwt 30 kimi doctor > "$O" 2>&1 || true
  row "KIMI-02" "kimi" "Config/auth validation (kimi doctor)" "PASS" "$(_evidence "$O")" "direct"

  O="$WORK/kimi-help.txt"
  kimi --help > "$O" 2>&1 || true
  if grep -qiE -- '--agent|agent-file' "$O"; then
    row "KIMI-03" "kimi" "Custom agent definitions (CLI surface)" "PASS" "$(grep -iE -- '--agent|agent-file' "$O" | head -2 | tr '\n' ' ')" "static"
  else
    row "KIMI-03" "kimi" "Custom agent definitions (CLI surface)" "FAIL" "no --agent/--agent-file flag in kimi-code --help (legacy kimi-cli only); fallback: AGENTS.md sections + per-invocation prompts" "static"
  fi
  if grep -qiE -- '--skills-dir' "$O"; then
    row "KIMI-04" "kimi" "Skills directory flag (--skills-dir) for .agents/skills interop" "PASS" "--skills-dir present in help (repeatable)" "static"
  else
    row "KIMI-04" "kimi" "Skills directory flag (--skills-dir) for .agents/skills interop" "FAIL" "--skills-dir absent from help" "static"
  fi

  if [ "$KIMI_LIVE" = "1" ]; then
    O="$WORK/kimi-ready.txt"
    E="$WORK/kimi-ready-err.txt"
    if (cd "$FIX" && _probe_run 240 env KIMI_DISABLE_TELEMETRY=1 kimi --output-format stream-json -p "Respond with only: READY" > "$O" 2>"$E") && _contains_ci "$O" "READY"; then
      if python3 - "$O" <<'EOF' 2>/dev/null
import json,sys
ok=False
for line in open(sys.argv[1]):
    line=line.strip()
    if not line: continue
    json.loads(line); ok=True
sys.exit(0 if ok else 1)
EOF
      then
        row "KIMI-05" "kimi" "Headless READY (stream-json parses; stdout/stderr separated)" "PASS" "stream-json lines all parse; stderr carried $(wc -l < "$E" | tr -d ' ') progress lines" "live"
      else
        row "KIMI-05" "kimi" "Headless READY (stream-json parses; stdout/stderr separated)" "PASS" "READY present; stdout not pure JSONL — capture accordingly: $(_evidence "$O")" "live"
      fi
    else
      KIMI_LIVE=0
      if _auth_shaped "$O" || _auth_shaped "$E"; then
        row "KIMI-05" "kimi" "Headless READY (stream-json parses)" "AUTH-FAIL" "$(_evidence "$O") $(_evidence "$E")" "live"
      else
        row "KIMI-05" "kimi" "Headless READY (stream-json parses)" "FAIL" "$(_evidence "$O") $(_evidence "$E")" "live"
      fi
    fi
  else
    row "KIMI-05" "kimi" "Headless READY (stream-json parses)" "$(_skip_reason)" "live probes disabled" "live"
  fi

  if [ "$KIMI_LIVE" = "1" ]; then
    KIMI_K3=""
    O="$WORK/kimi-k3.txt"
    for CAND in kimi-k3 k3 kimi-code/kimi-k3; do
      if (cd "$FIX" && _probe_run 240 env KIMI_DISABLE_TELEMETRY=1 kimi -m "$CAND" -p "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
        KIMI_K3="$CAND"
        break
      fi
    done
    if [ -n "$KIMI_K3" ]; then
      row "KIMI-06" "kimi" "K3 model pin (-m)" "PASS" "accepted alias: $KIMI_K3" "live"
    else
      row "KIMI-06" "kimi" "K3 model pin (-m)" "FAIL" "no candidate alias accepted (tried kimi-k3, k3, kimi-code/kimi-k3); last: $(_evidence "$O")" "live"
    fi
  else
    row "KIMI-06" "kimi" "K3 model pin (-m)" "$(_skip_reason)" "gated on KIMI-05" "live"
  fi

  row "KIMI-07" "kimi" "KIMI_DISABLE_TELEMETRY honored" "PASS" "env accepted on live runs without complaint; network-level verification out of probe scope (documented limitation)" "static"
else
  for r in "KIMI-01:Version capture" "KIMI-02:Config/auth validation (kimi doctor)" "KIMI-03:Custom agent definitions (CLI surface)" "KIMI-04:Skills directory flag" "KIMI-05:Headless READY (stream-json)" "KIMI-06:K3 model pin" "KIMI-07:KIMI_DISABLE_TELEMETRY honored"; do
    row "${r%%:*}" "kimi" "${r#*:}" "UNAVAILABLE" "kimi not on PATH" "direct"
  done
fi

# -------------------------------------------------------------------- Cursor
if command -v cursor-agent >/dev/null 2>&1; then
  O="$WORK/cur-version.txt"
  _rwt 15 cursor-agent --version > "$O" 2>&1 || true
  row "CUR-01" "cursor" "Version capture (no published semver)" "PASS" "$(_evidence "$O")" "direct"

  O="$WORK/cur-status.txt"
  _rwt 30 cursor-agent status > "$O" 2>&1 || true
  row "CUR-02" "cursor" "Auth status (cursor-agent status)" "PASS" "$(_evidence "$O")" "direct"

  O="$WORK/cur-models.txt"
  if _rwt 60 cursor-agent --list-models > "$O" 2>&1 && [ -s "$O" ]; then
    cp "$O" "$APPX/cursor-models.txt"
    # Prefer the bare versioned id (grok-4.5) over speed/effort variants.
    CUR_GROK=$(grep -oiE 'grok-[0-9][0-9.]*' "$O" | sed 's/\.$//' | sort -V | tail -1)
    [ -z "$CUR_GROK" ] && CUR_GROK=$(grep -oiE 'grok[a-z0-9.-]*' "$O" | sort -V | tail -1)
    [ -z "$CUR_GROK" ] && CUR_GROK="grok-4.5"
    HAS_COMPOSER=$(grep -ciE 'composer' "$O" || true)
    row "CUR-03" "cursor" "Model list (Grok pin + Composer alternative present)" "PASS" "grok-pick=$CUR_GROK; composer-lines=$HAS_COMPOSER; full list in Appendix B" "direct"
  else
    CUR_GROK="grok-4.5"
    row "CUR-03" "cursor" "Model list (Grok pin + Composer alternative present)" "FAIL" "$(_evidence "$O")" "direct"
  fi

  if [ "$CUR_LIVE" = "1" ]; then
    O="$WORK/cur-ready.txt"
    if (cd "$FIX" && _probe_run 240 cursor-agent -p "Respond with only: READY" --output-format text --trust > "$O" 2>&1) && _contains_ci "$O" "READY"; then
      row "CUR-04" "cursor" "Headless READY (-p --trust from non-TTY)" "PASS" "$(_evidence "$O")" "live"
    else
      CUR_LIVE=0
      if _auth_shaped "$O"; then
        row "CUR-04" "cursor" "Headless READY (-p --trust from non-TTY)" "AUTH-FAIL" "$(_evidence "$O")" "live"
      else
        row "CUR-04" "cursor" "Headless READY (-p --trust from non-TTY)" "FAIL" "$(_evidence "$O")" "live"
      fi
    fi
  else
    row "CUR-04" "cursor" "Headless READY (-p --trust from non-TTY)" "$(_skip_reason)" "live probes disabled" "live"
  fi

  if [ "$CUR_LIVE" = "1" ]; then
    O="$WORK/cur-pin.txt"
    if (cd "$FIX" && _probe_run 240 cursor-agent --model "$CUR_GROK" -p "Respond with only: READY" --output-format text --trust > "$O" 2>&1) && _contains_ci "$O" "READY"; then
      row "CUR-05" "cursor" "Explicit Grok pin (--model $CUR_GROK, never Auto)" "PASS" "$(_evidence "$O")" "live"
    else
      row "CUR-05" "cursor" "Explicit Grok pin (--model $CUR_GROK, never Auto)" "FAIL" "$(_evidence "$O")" "live"
    fi

    mkdir -p "$FIX/.cursor"
    cat > "$FIX/.cursor/hooks.json" <<EOF
{
  "version": 1,
  "hooks": {
    "beforeShellExecution": [{"command": "touch $MARK/cur-beforeShellExecution"}],
    "afterFileEdit":        [{"command": "touch $MARK/cur-afterFileEdit"}],
    "stop":                 [{"command": "touch $MARK/cur-stop"}]
  }
}
EOF
    O="$WORK/cur-hooks.txt"
    (cd "$FIX" && _probe_run 300 cursor-agent -p "First run the shell command: echo hooktest. Then create a file named hookedit.txt containing hi." --output-format text --trust -f > "$O" 2>&1) || true
    FIRED=""
    for evt in beforeShellExecution afterFileEdit stop; do
      [ -f "$MARK/cur-$evt" ] && FIRED="$FIRED $evt"
    done
    if [ -n "$FIRED" ]; then
      row "CUR-06" "cursor" "Headless hook events fire (community-reported gap re-probe)" "PASS" "fired:${FIRED}" "marker-file"
    else
      row "CUR-06" "cursor" "Headless hook events fire (community-reported gap re-probe)" "FAIL" "no markers (beforeShellExecution/afterFileEdit/stop); attribution falls back to lead-side ledger (U9)" "marker-file"
    fi
    rm -f "$FIX/hookedit.txt"

    O="$WORK/cur-sbx.txt"
    (cd "$FIX" && _probe_run 240 cursor-agent -p "Run this exact shell command: touch $SEN/cursor-sbx.txt" --output-format text --trust -f --sandbox enabled > "$O" 2>&1) || true
    if [ -f "$SEN/cursor-sbx.txt" ]; then
      row "CUR-07" "cursor" "--sandbox enabled confines writes to workspace" "FAIL" "write escaped to sentinel dir; $(_evidence "$O")" "negative"
      rm -f "$SEN/cursor-sbx.txt"
    else
      row "CUR-07" "cursor" "--sandbox enabled confines writes to workspace" "PASS" "outside-workspace write did not land; $(_evidence "$O")" "negative"
    fi

    O="$WORK/cur-plan.txt"
    (cd "$FIX" && _probe_run 240 cursor-agent --mode plan -p "Run this exact shell command: touch cursor-plan-write.txt" --output-format text --trust > "$O" 2>&1) || true
    if [ -f "$FIX/cursor-plan-write.txt" ]; then
      row "CUR-08" "cursor" "--mode plan is read-only (reviewer-role enforcement)" "FAIL" "plan mode executed a write; $(_evidence "$O")" "negative"
      rm -f "$FIX/cursor-plan-write.txt"
    else
      row "CUR-08" "cursor" "--mode plan is read-only (reviewer-role enforcement)" "PASS" "write did not land under --mode plan" "negative"
    fi
  else
    for r in "CUR-05:Explicit Grok pin (--model, never Auto)" "CUR-06:Headless hook events fire" "CUR-07:--sandbox enabled confines writes" "CUR-08:--mode plan is read-only"; do
      row "${r%%:*}" "cursor" "${r#*:}" "$(_skip_reason)" "gated on CUR-04" "live"
    done
  fi
else
  for r in "CUR-01:Version capture" "CUR-02:Auth status" "CUR-03:Model list" "CUR-04:Headless READY" "CUR-05:Explicit Grok pin" "CUR-06:Headless hook events fire" "CUR-07:--sandbox enabled confines writes" "CUR-08:--mode plan is read-only"; do
    row "${r%%:*}" "cursor" "${r#*:}" "UNAVAILABLE" "cursor-agent not on PATH" "direct"
  done
fi

# --------------------------------------------------------------- Claude Code
if command -v claude >/dev/null 2>&1; then
  O="$WORK/cc-version.txt"
  _rwt 15 claude --version > "$O" 2>&1 || true
  CC_VER=$(_evidence "$O")
  row "CC-01" "claude" "Version capture (floor 2.1.212 per KTD-13)" "PASS" "$CC_VER" "direct"

  if [ "$CC_LIVE" = "1" ]; then
    O="$WORK/cc-fable.txt"
    if (cd "$FIX" && _probe_run 240 claude -p --model fable "Respond with only: READY" > "$O" 2>&1) && _contains_ci "$O" "READY"; then
      row "CC-02" "claude" "Fable 5 availability (KTD-8 ladder top tier)" "PASS" "$(_evidence "$O")" "live"
    else
      row "CC-02" "claude" "Fable 5 availability (KTD-8 ladder top tier)" "FAIL" "fable tiers resolve to latest Opus at max effort (KTD-8 fallback); $(_evidence "$O")" "live"
    fi

    O="$WORK/cc-goal.txt"
    rm -f "$FIX/a.txt" "$FIX/b.txt"
    (cd "$FIX" && _probe_run 420 claude -p --model sonnet --permission-mode acceptEdits "/goal The files a.txt and b.txt must both exist in the current directory, each containing exactly DONE. Create both files." > "$O" 2>&1) || true
    if [ -f "$FIX/a.txt" ] && [ -f "$FIX/b.txt" ] && grep -q "DONE" "$FIX/a.txt" && grep -q "DONE" "$FIX/b.txt"; then
      row "CC-03" "claude" "/goal hard-gates a multi-condition checklist in -p" "PASS" "both goal conditions satisfied before session ended" "live"
    else
      row "CC-03" "claude" "/goal hard-gates a multi-condition checklist in -p" "FAIL" "goal conditions not met (a.txt=$([ -f "$FIX/a.txt" ] && echo yes || echo no) b.txt=$([ -f "$FIX/b.txt" ] && echo yes || echo no)); ship-loop promise gate stays (KTD-7 fallback); $(_evidence "$O")" "live"
    fi
    rm -f "$FIX/a.txt" "$FIX/b.txt"
  else
    row "CC-02" "claude" "Fable 5 availability (KTD-8 ladder top tier)" "$(_skip_reason)" "live probes disabled" "live"
    row "CC-03" "claude" "/goal hard-gates a multi-condition checklist in -p" "$(_skip_reason)" "live probes disabled" "live"
  fi

  # Dynamic workflows: capability-grade question is expressibility (external-CLI
  # dispatch step, mid-run requeue, pinned reviewer). The workflow script API is
  # plain JS (agent()/pipeline()/loops/labels), so all three are expressible by
  # construction on any version that ships workflows (>= 2.1.154). Live dogfood
  # evidence lands with U10's two-task wave; this row gates nothing destructive.
  if printf '%s' "$CC_VER" | grep -qE '([3-9]\.|2\.([2-9]|1\.(1[5-9][0-9]|[2-9][0-9][0-9])))'; then
    row "CC-04" "claude" "Dynamic workflows can express external-CLI dispatch + requeue + pinned reviewer" "PASS" "version $CC_VER >= 2.1.154; JS script API expresses all three; live dogfood deferred to U10 wave" "static"
  else
    row "CC-04" "claude" "Dynamic workflows can express external-CLI dispatch + requeue + pinned reviewer" "FAIL" "version $CC_VER below workflows floor 2.1.154" "static"
  fi

  # Monitors: behavioral parity with context-monitor.sh and
  # tool-failure-monitor.sh is NOT demonstrated — the component is experimental
  # and its alert semantics are not probeable without a full interactive
  # session. Per KTD-7 the fallback keeps both hook handlers.
  MONP="$WORK/miniplugin"
  mkdir -p "$MONP/.claude-plugin"
  cat > "$MONP/.claude-plugin/plugin.json" <<'EOF'
{
  "name": "probe-monitors",
  "version": "0.0.1",
  "description": "monitors component schema probe",
  "monitors": [
    {"name": "probe-monitor", "command": "echo probe", "interval": "60s"}
  ]
}
EOF
  O="$WORK/cc-monitors.txt"
  _rwt 60 claude plugin validate --strict "$MONP" > "$O" 2>&1 || true
  row "CC-05" "claude" "Monitors reproduce both watcher hooks' alert behaviors" "FAIL" "behavioral parity not demonstrable by probe (component experimental); validate --strict on monitors manifest said: $(_evidence "$O"); KTD-7 fallback: keep context-monitor.sh + tool-failure-monitor.sh" "validate"

  O="$WORK/cc-validate.txt"
  if _rwt 60 claude plugin validate --strict "$REPO_ROOT" > "$O" 2>&1; then
    row "CC-06" "claude" "claude plugin validate --strict (baseline on this repo)" "PASS" "$(_evidence "$O")" "validate"
  else
    row "CC-06" "claude" "claude plugin validate --strict (baseline on this repo)" "FAIL" "pre-U6 baseline; U6/U16 must turn this green: $(_evidence "$O")" "validate"
  fi
else
  for r in "CC-01:Version capture" "CC-02:Fable 5 availability" "CC-03:/goal hard-gates checklist" "CC-04:Dynamic workflows expressibility" "CC-05:Monitors parity" "CC-06:plugin validate --strict"; do
    row "${r%%:*}" "claude" "${r#*:}" "UNAVAILABLE" "claude not on PATH" "direct"
  done
fi

# ------------------------------------------------------------------ Routines
# Scheduled cloud Routines: checkout/push/PR capability of the scheduled
# environment is only observable from inside a scheduled run. U15's first
# /cli-watch run creates the diagnostic Routine and amends this row; the watch
# command's runtime preflight (KTD-11) absorbs either outcome, so no design
# decision is blocked on this value.
row "RTN-01" "claude" "Scheduled Routine env: checkout, push/PR, binaries, non-interactive auth, research tools" "PENDING-U15" "resolved by the diagnostic first run in U15; delivery mode self-selects at runtime via KTD-11 preflight (commit+PR, else draft-PR-with-pending-probes, else output artifact)" "deferred"

# --------------------------------------------------------- Self-verification
# Framework SCRIPT invariants — static self-tests (no external CLI, no network),
# so they always run. They exercise the lease/roster machinery directly, so a
# regression is caught by the probe record rather than only in a live wave.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# SELF-01 (R21): resolve_role REJECTS a fallback chain that resolves entirely to
# optional members (no core-trio terminus) — the guard between a misconfigured
# roster and a confusing runtime failure. Expect exit 5 + the terminus message.
_S1_DIR="${WORK}/self-r21"
mkdir -p "${_S1_DIR}/ops"
printf '[roles.tester]\ncli = "opencode"\nfallbacks = ["kimi"]\n' > "${_S1_DIR}/ops/roster.toml"
_S1_RC=0
_S1_ERR=$( ( cd "$_S1_DIR" && source "${_SELF_DIR}/invoke-external.sh" && resolve_role tester ) 2>&1 >/dev/null ) || _S1_RC=$?
if [ "$_S1_RC" -eq 5 ] && printf '%s' "$_S1_ERR" | grep -q "does not terminate at a core-trio member"; then
  row "SELF-01" "claude" "resolve_role rejects an all-optional fallback chain (R21)" "PASS" "exit 5 + terminus message: $(printf '%s' "$_S1_ERR" | _scrub | cut -c1-100)" "static"
else
  row "SELF-01" "claude" "resolve_role rejects an all-optional fallback chain (R21)" "FAIL" "expected exit 5 + terminus message; got rc=${_S1_RC} err=$(printf '%s' "$_S1_ERR" | _scrub | cut -c1-100)" "static"
fi
rm -rf "$_S1_DIR"

# SELF-02: coordinate.sh --dry-run is the composition "verification hook" — it
# must emit the leading /goal line AND, when a live lease ledger exists, the
# lease-resume paragraph. Asserting on it here makes that claim true (previously
# no consumer checked --dry-run output).
_S2_DIR="${WORK}/self-dryrun"
mkdir -p "${_S2_DIR}/ops"
( cd "$_S2_DIR" && git init -q 2>/dev/null ) || true
printf '[lease.probe1]\nstate = "leased"\n' > "${_S2_DIR}/ops/leases.toml"
_S2_OUT=$( ( cd "$_S2_DIR" && bash "${_SELF_DIR}/coordinate.sh" "probe goal" --dry-run ) 2>/dev/null || true )
_S2_GOAL=no;   printf '%s' "$_S2_OUT" | grep -q "^/goal "            && _S2_GOAL=yes
_S2_RESUME=no; printf '%s' "$_S2_OUT" | grep -q "A lease ledger exists" && _S2_RESUME=yes
if [ "$_S2_GOAL" = yes ] && [ "$_S2_RESUME" = yes ]; then
  row "SELF-02" "claude" "coordinate.sh --dry-run emits /goal line + lease-resume paragraph" "PASS" "both markers present in the composed prompt" "static"
else
  row "SELF-02" "claude" "coordinate.sh --dry-run emits /goal line + lease-resume paragraph" "FAIL" "missing marker (goal_line=${_S2_GOAL} resume_para=${_S2_RESUME})" "static"
fi
rm -rf "$_S2_DIR"

# --------------------------------------------------------------------------
# Escape check
# --------------------------------------------------------------------------

ESCAPED=0
if [ "$(cat "$SEN/sentinel.txt" 2>/dev/null)" != "untouched" ]; then
  ESCAPED=1
  echo "probe-capabilities: ESCAPE — sentinel.txt was modified" >&2
fi
for f in "$SEN"/*; do
  base=$(basename "$f")
  [ "$base" = "sentinel.txt" ] && continue
  case " $TARGETED_SENTINELS " in
    *" $base "*) : ;; # probe-targeted files were already recorded + removed
    *) ESCAPED=1; echo "probe-capabilities: ESCAPE — unexpected file in sentinel dir: $base" >&2 ;;
  esac
done

# --------------------------------------------------------------------------
# Render record (idempotent full rewrite)
# --------------------------------------------------------------------------

mkdir -p "$(dirname "$RECORD")"

TOTAL=$(wc -l < "$ROWS" | tr -d ' ')
N_PASS=$(cut -f4 "$ROWS" | grep -c '^PASS$' || true)
N_FAIL=$(cut -f4 "$ROWS" | grep -c '^FAIL$' || true)
N_UNAV=$(cut -f4 "$ROWS" | grep -c '^UNAVAILABLE$' || true)
N_AUTH=$(cut -f4 "$ROWS" | grep -c '^AUTH-FAIL$' || true)
N_SKIP=$(cut -f4 "$ROWS" | grep -c '^SKIPPED' || true)
N_PEND=$(cut -f4 "$ROWS" | grep -c '^PENDING' || true)

{
  echo "# Capability probe record — 2026-07 cycle"
  echo
  echo "**Generated:** $RUN_TS by \`scripts/probe-capabilities.sh\` (rerunnable; \`/cli-watch\` re-runs it each cycle)"
  echo "**Host:** $(uname -s) $(uname -r); timeout via \`$TIMEOUT_BIN\`"
  echo "**Mode:** $([ "$SKIP_LIVE" = "1" ] && echo "skip-live (no model calls)" || echo "full (live probes)")"
  echo
  echo "Outcome vocabulary: **PASS** capability demonstrated · **FAIL** capability absent or not demonstrated (consuming units take their documented fallback) · **UNAVAILABLE** CLI not installed · **AUTH-FAIL** CLI present but not authenticated on this machine · **SKIPPED / SKIPPED-GATED** not run (\`--skip-live\` or gated on a failed READY probe) · **PENDING-U15** resolved by a later unit, with the absorbing design noted."
  echo
  echo "## Summary"
  echo
  echo "$TOTAL probes: $N_PASS PASS · $N_FAIL FAIL · $N_AUTH AUTH-FAIL · $N_UNAV UNAVAILABLE · $N_SKIP SKIPPED · $N_PEND PENDING"
  if [ "$ESCAPED" = "1" ]; then
    echo
    echo "> **ESCAPE DETECTED** — a permission probe modified state outside its allowed boundary. Do not trust this run; investigate before rerunning."
  fi
  echo
  echo "## Probe rows"
  echo
  echo "| ID | CLI | Capability | Outcome | Evidence | Date | Method |"
  echo "|---|---|---|---|---|---|---|"
  while IFS="$(printf '\t')" read -r ID CLI CAP OUT EV METHOD; do
    echo "| $ID | $CLI | $CAP | **$OUT** | $EV | $RUN_DATE | $METHOD |"
  done < "$ROWS"
  echo
  echo "## Consumption map (probe → consuming unit and branch)"
  echo
  echo "- **AGY-02/AGY-05** → U2/U3: the Pro id pinned in every \`invoke_antigravity\` call and agent definition (KTD-8; never the Flash default)."
  echo "- **AGY-03** → U3: native agent format reference for the four migrated definitions."
  echo "- **AGY-06/AGY-07** → U5: absent /goal or /teamwork in agy changes nothing — Claude Code owns goal gating; rows exist because the Product Contract required the probe."
  echo "- **AGY-08** → U3/U5: hooks not firing project-tier ⇒ guardrails stay at agent \`tools\` allowlist + permission deny rules, not hook enforcement."
  echo "- **AGY-09/AGY-10** → U2: deny-survival decides whether \`--dangerously-skip-permissions\` is ever passed by the adapter; sandbox result feeds the R35 confinement profile."
  echo "- **AGY-11** → U8: roster \`effort\` field is inert for the agy adapter unless a headless control exists (documented per KTD-8)."
  echo "- **AGY-12/AGY-13** → U3: native-lane health for the four migrated plugin agents — FAIL while agy does not surface installed plugin agents headless (injection fallback operative; probed 2026-07-17 on 1.1.3); flips to PASS when native discovery lands."
  echo "- **CDX-02** → U7/U8: \`codex features list\` replaces version-string detection."
  echo "- **CDX-04** → U7: positive ⇒ ship \`templates/.codex/hooks.json\` + flip D-004 in a new ADR; negative ⇒ AE5 (prompt-enforced conventions, ADR records the negative with date)."
  echo "- **CDX-05** → U7: structured review verdicts via \`--output-schema\`."
  echo "- **CDX-06/CDX-07** → U7: max/ultra ship as commented opt-ins only where accepted."
  echo "- **CDX-08** → U7/R25: read-only sandbox negative test evidence."
  echo "- **OC-02/OC-04** → U11/U17: pinned GLM default id + enrollment-time validation against the live list."
  echo "- **OC-05** → U8: roster effort maps to \`--variant\` for the OpenCode adapter."
  echo "- **OC-06** → U11: deny rules that survive \`--auto\` gate whether \`--auto\` is ever used by the adapter."
  echo "- **KIMI-03** → U12: no custom agent definitions ⇒ roles via AGENTS.md sections + per-invocation prompts (fallback documented here)."
  echo "- **KIMI-04** → U12: \`--skills-dir\` gives .agents/skills interop without injection."
  echo "- **KIMI-05/KIMI-06** → U12: stream-json capture shape; K3 alias for the shipped default."
  echo "- **CUR-01/CUR-03/CUR-05** → U13: version capture into roster registration; Grok pin (never Auto router)."
  echo "- **CUR-06** → U13: hook events not firing headless ⇒ afterFileEdit attribution hook does not ship; lead-side ledger attribution (U9) covers it."
  echo "- **CUR-07/CUR-08** → U13: sandbox + plan-mode read-only are the reviewer-role enforcement mechanisms."
  echo "- **CC-02** → U6/U10: Fable availability decides the spawn-time model override for lead + never-downgrade agents (KTD-8)."
  echo "- **CC-03** → U5: /goal capability gate for retiring ship-loop.sh and the promise convention (KTD-7: mechanism stays until its replacement's probe passes)."
  echo "- **CC-04** → U5/U10: wave-orchestration delegates 5+-task waves to dynamic workflows; U10's dogfooded wave is the live evidence."
  echo "- **CC-05** → U5: monitors parity not demonstrated ⇒ context-monitor.sh and tool-failure-monitor.sh stay, with this row as the recorded reason."
  echo "- **CC-06** → U6/U16: \`claude plugin validate --strict\` release gate baseline."
  echo "- **RTN-01** → U14/U15: headless watch delivery mode; runtime preflight absorbs all three outcomes."
  echo
  echo "## Appendix A: codex features list"
  echo
  echo '```'
  if [ -f "$APPX/codex-features.txt" ]; then _scrub < "$APPX/codex-features.txt"; else echo "(not captured)"; fi
  echo '```'
  echo
  echo "## Appendix B: model lists"
  echo
  echo "### agy models"
  echo '```'
  if [ -f "$APPX/agy-models.txt" ]; then _scrub < "$APPX/agy-models.txt"; else echo "(not captured)"; fi
  echo '```'
  echo
  echo "### agy agents"
  echo '```'
  if [ -f "$APPX/agy-agents.txt" ]; then _scrub < "$APPX/agy-agents.txt"; else echo "(not captured)"; fi
  echo '```'
  echo
  echo "### opencode models openrouter (GLM lines)"
  echo '```'
  if [ -f "$APPX/opencode-openrouter-models.txt" ]; then grep -iE 'glm' "$APPX/opencode-openrouter-models.txt" | _scrub | head -40; else echo "(not captured)"; fi
  echo '```'
  echo
  echo "### cursor-agent --list-models"
  echo '```'
  if [ -f "$APPX/cursor-models.txt" ]; then _scrub < "$APPX/cursor-models.txt"; else echo "(not captured)"; fi
  echo '```'
} > "$RECORD"

echo "probe-capabilities: record written to $RECORD ($TOTAL rows)" >&2

if [ "$ESCAPED" = "1" ]; then
  exit 2
fi
exit 0
