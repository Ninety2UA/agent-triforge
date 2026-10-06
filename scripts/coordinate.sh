#!/usr/bin/env bash
# Coordinate — Outer loop script for context exhaustion recovery
# Spawns fresh lead sessions when context is exhausted.
# Each iteration gets a clean context window.
# Progress tracked in ops/STATE.md.
#
# The lead is [lead] in ops/roster.toml (resolve_lead; no table = Claude Code).
# What runs and how a session is gated are the lead's registry fields (KTD1,
# KTD14 — scripts/lib/registry.sh), never its name:
#   lead.launch_argv  one headless session; the composed prompt is appended
#                     as its last word.
#   lead.model_argv / lead.effort_argv
#                     the flags that carry [lead] model and effort ("{}" =
#                     the value), placed after launch_argv and before the
#                     prompt; an empty value adds nothing (a Codex lead's
#                     defaults are gpt-6-astra at xhigh, Claude Code's empty).
#   lead.goal_gate    non-empty (Claude Code: /goal): the prompt LEADS with
#                     "<goal_gate> <completion checklist>", so the host
#                     hard-gates the session natively (probe CC-03; a slash
#                     command works only as the first line of a headless
#                     prompt). Empty (Codex): no gate; the prompt leads with
#                     the at-ship skill in its $<skill> mention form, carries
#                     the checklist as text, and the session completes on the
#                     sentinel alone (R27).
#
# Completion contract:
#   - The session creates the runtime marker ops/.sprint-complete ONLY after
#     the verification checklist passes (Phase 6 wrap).
#   - This loop clears the marker at start and detects completion solely by
#     the file's existence — headless-observable, no output parsing.
#
# Full access (R50): a launch line that asks for it (`-s danger-full-access`,
# the D-047 Codex profile, or another host's bypass-everything flag) runs only
# when the human passed --allow-full-access on this command line. Without it
# the script prints the launch line and the three confinement statements (R4)
# and exits 77, having run nothing. --dry-run never runs a lead either way.
#
# Before each session the lead-side integrity check runs (KTD18,
# _lead_integrity_check): a change to .git/config, .git/hooks, refs, worktree
# pointers or the ledger that the lead did not make is restored where
# possible, the open leases are escalated, and the loop stops before the
# session starts (rc 44), so no unattended session accepts it.
#
# Usage:
#   ./scripts/coordinate.sh "Build the authentication module"
#   ./scripts/coordinate.sh "Build auth" --max 5
#   ./scripts/coordinate.sh "Build auth" --convergence deep
#   ./scripts/coordinate.sh "Build auth" --dry-run [--lead claude|codex]
#   ./scripts/coordinate.sh "Build auth" --allow-full-access
#
# Flags:
#   --max N              Maximum iterations (default: 5)
#   --convergence        Convergence mode: fast|standard|deep (default: standard)
#   --team               Use agent team mode for Phase 2
#   --dry-run            Print the launch line and the composed session prompt
#                        and exit without running the lead (asserted by probe
#                        SELF-02)
#   --lead <cli>         With --dry-run only: compose for this lead instead of
#                        the roster's [lead]
#   --allow-full-access  The human's acknowledgement that the lead's launch
#                        line runs with full access (R50); needed only when it
#                        asks for it
#
# Exit codes:
#   0   sprint complete (the sentinel exists), the dry run printed, or the
#       iterations ran out without completion (the closing lines say so)
#   1   usage error, the lead can't be resolved, its CLI is not on PATH, or
#       the helper library is missing
#   44  the integrity check found a change before a session (restored,
#       escalated; inspect, then lease_rebaseline) or could not run
#   45  this shell may not run the lead's loop (R38: another CLI's host
#       markers, or no terminal and no markers, as under nohup, cron or CI),
#       checked before any session or ledger read
#   69  the lead's run failed deterministically (not logged in, quota spent,
#       binary missing): stopped after that iteration, class and fix printed
#   77  the launch line asks for full access and --allow-full-access was not
#       given: the line was printed, nothing ran

set -euo pipefail

# Parse arguments
GOAL=""
MAX_ITERATIONS=5
CONVERGENCE="standard"
USE_TEAM=""
DRY_RUN=false
LEAD_OVERRIDE=""
ALLOW_FULL_ACCESS=false

USAGE='Usage: ./scripts/coordinate.sh "goal description" [--max N] [--convergence fast|standard|deep] [--team] [--dry-run [--lead <cli>]] [--allow-full-access]'

while [[ $# -gt 0 ]]; do
  case $1 in
    --max)
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --convergence)
      CONVERGENCE="$2"
      shift 2
      ;;
    --team)
      USE_TEAM="--team"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --lead)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "coordinate.sh: --lead needs a CLI name" >&2
        exit 1
      fi
      LEAD_OVERRIDE="$2"
      shift 2
      ;;
    --allow-full-access)
      ALLOW_FULL_ACCESS=true
      shift
      ;;
    *)
      if [ -z "$GOAL" ]; then
        GOAL="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$GOAL" ]; then
  echo "$USAGE"
  exit 1
fi
if [ -n "$LEAD_OVERRIDE" ] && [ "$DRY_RUN" != "true" ]; then
  echo "coordinate.sh: --lead composes a dry run for another lead; it needs --dry-run (a real run always uses [lead] in ops/roster.toml)" >&2
  echo "$USAGE" >&2
  exit 1
fi

SENTINEL="ops/.sprint-complete"

# The helper library: lead resolution and the registry (roster.sh,
# registry.sh), the integrity check (lease.sh), the failure classifier
# (common.sh). The loader finds the plugin root itself (KTD6).
_COORD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
if ! source "${_COORD_DIR}/invoke-external.sh"; then
  echo "coordinate.sh: ERROR could not load ${_COORD_DIR}/invoke-external.sh (the helper library)" >&2
  exit 1
fi

# The lead and its model and effort: [lead] in the roster (resolve_lead), or
# for a dry run the --lead CLI (lead_resolve_as: the roster's values when it is
# this checkout's lead, else that CLI's lead defaults).
TAB=$(printf '\t')
# Only stdout is the row; stderr is read (by a second call) only on failure,
# so a warning printed on success never becomes part of the lead's name.
if [ -n "$LEAD_OVERRIDE" ]; then
  if ! LEAD_ROW=$(lead_resolve_as "$LEAD_OVERRIDE" 2>/dev/null); then
    echo "coordinate.sh: ERROR $(lead_resolve_as "$LEAD_OVERRIDE" 2>&1 >/dev/null | tail -1)" >&2
    exit 1
  fi
else
  if ! LEAD_ROW=$(resolve_lead 2>/dev/null); then
    echo "coordinate.sh: ERROR the lead could not be resolved from ops/roster.toml: $(resolve_lead 2>&1 >/dev/null | tail -1)" >&2
    exit 1
  fi
fi
LEAD=${LEAD_ROW%%"$TAB"*}
LEAD_ROW_REST=${LEAD_ROW#*"$TAB"}
LEAD_MODEL=${LEAD_ROW_REST%%"$TAB"*}
LEAD_EFFORT=${LEAD_ROW_REST#*"$TAB"}
LEAD_FIELDS=$(cli_field "$LEAD" name lead.launch_argv lead.goal_gate 2>/dev/null) || LEAD_FIELDS=""
LEAD_NAME=${LEAD_FIELDS%%"$TAB"*}
LEAD_REST=${LEAD_FIELDS#*"$TAB"}
LAUNCH_ARGV=${LEAD_REST%%"$TAB"*}
GOAL_GATE=${LEAD_REST#*"$TAB"}
if [ -z "$LEAD_FIELDS" ] || [ -z "$LAUNCH_ARGV" ]; then
  echo "coordinate.sh: ERROR '${LEAD}' cannot lead (no lead.launch_argv in scripts/lib/registry.sh); the lead is one of the CLIs whose registry entry carries the lead fields" >&2
  exit 1
fi

# The [lead] model and effort ride the lead's lead.model_argv and
# lead.effort_argv ("{}" = the value), appended to launch_argv before the
# prompt. An empty value adds nothing; a non-empty one with no such field adds
# nothing and is named once in a note (LAUNCH_NOTES).
MODEL_ARGV=$(cli_field "$LEAD" lead.model_argv 2>/dev/null) || MODEL_ARGV=""
EFFORT_ARGV=$(cli_field "$LEAD" lead.effort_argv 2>/dev/null) || EFFORT_ARGV=""
# What the registry declares about full access (true|false); unreadable counts
# as full access below (fail closed).
FULL_DECL=$(cli_field "$LEAD" lead.full_access 2>/dev/null) || FULL_DECL=""

# The launch argv as words (shell quoting, as the human would type it), the
# model and effort words after them, and whether the line runs the lead with
# full access: the registry's lead.full_access, or any word the registry's
# launch_full_access reads as full access (_LAUNCH_ACCESS_PY: sandbox modes,
# permission modes, bypass flags, profiles, in every spelling the two lead
# CLIs take). Either one asks for the human's --allow-full-access. One line
# per word, then the verdict, its reasons, the extra words as typed, notes.
LAUNCH_WORDS=()
FULL_ACCESS=0
FULL_WHY=""
LAUNCH_EXTRA=""
LAUNCH_NOTES=""
while IFS= read -r _w; do
  case "$_w" in
    "__full_access__="*) FULL_ACCESS=${_w#__full_access__=} ;;
    "__why__="*) FULL_WHY="${FULL_WHY}${FULL_WHY:+; }${_w#__why__=}" ;;
    "__extra__="*) LAUNCH_EXTRA=${_w#__extra__=} ;;
    "__note__="*) LAUNCH_NOTES="${LAUNCH_NOTES}${LAUNCH_NOTES:+
}${_w#__note__=}" ;;
    *) LAUNCH_WORDS+=("$_w") ;;
  esac
done <<COORD_ARGV_EOF
$(CA_ARGV="$LAUNCH_ARGV" CA_NAME="$LEAD_NAME" CA_MODEL="$LEAD_MODEL" CA_EFFORT="$LEAD_EFFORT" CA_FULL="$FULL_DECL" \
  CA_MODEL_ARGV="$MODEL_ARGV" CA_EFFORT_ARGV="$EFFORT_ARGV" python3 -c "${_LAUNCH_ACCESS_PY}"'
import os, shlex
e = os.environ
words = shlex.split(e["CA_ARGV"])
extra, notes = [], []
for field in ("model", "effort"):
    value, tmpl = e["CA_" + field.upper()], e["CA_" + field.upper() + "_ARGV"]
    if not value:
        continue
    if "{}" not in tmpl or "\n" in value:
        notes.append("the " + e["CA_NAME"] + " registry entry has no lead." + field + "_argv, so the [lead] " + field + " " + " ".join(value.split()) + " is not passed (the host default runs)")
        continue
    extra += [w.replace("{}", value) for w in shlex.split(tmpl)]
why = launch_full_access(words + extra)
if e["CA_FULL"] == "true":
    why.append("the registry declares lead.full_access = true")
elif e["CA_FULL"] != "false":
    why.append("no lead.full_access declaration could be read (fail closed)")
for w in words + extra:
    print(w)
print("__full_access__=" + ("1" if why else "0"))
for r in why:
    print("__why__=" + " ".join(r.split()))
print("__extra__=" + " ".join(shlex.quote(w) for w in extra))
for n in notes:
    print("__note__=" + n)
')
COORD_ARGV_EOF
unset _w
LAUNCH_SHOWN="${LAUNCH_ARGV}${LAUNCH_EXTRA:+ ${LAUNCH_EXTRA}}"
if [ "${#LAUNCH_WORDS[@]}" -eq 0 ]; then
  echo "coordinate.sh: ERROR the ${LEAD_NAME} launch line '${LAUNCH_ARGV}' could not be split into words" >&2
  exit 1
fi

# The three statements R4 has setup and AGENTS.md make; printed beside every
# full-access launch line.
confinement_statements() {
  echo "  - Confinement under either lead is Triforge's scripts plus git-integrity detection."
  echo "  - A lease worktree limits where a worker starts, not where it writes."
  echo "  - Recorded approval is audit, not prevention, and worker output is an injection surface for a full-access lead."
}

# Lease-ledger resume (KTD-4/U9): when ops/leases.toml still holds
# non-terminal leases, the fresh session must reconstruct the wave from the
# ledger instead of restarting it. Prints the extra prompt paragraph, or
# nothing. (probe-capabilities.sh SELF-02 asserts the /goal line + this resume
# paragraph appear in --dry-run output — that probe is the verification hook.)
lease_resume_paragraph() {
  [ -f "ops/leases.toml" ] || return 0
  local COUNTS ACTIVE ATTENTION
  # Two counts: live (mid-flight work to reconstruct) and attention (terminal
  # failed/escalated rows a fresh session must still resolve, not silently drop
  # — they are NOT "live" reclaimable work, so they get their own surface).
  COUNTS=$(python3 -c "
import sys
try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print('0 0')
        sys.exit(0)
try:
    with open('ops/leases.toml', 'rb') as f:
        data = tomllib.load(f)
    leases = data.get('lease', {})
    rows = [v for v in (leases.values() if isinstance(leases, dict) else []) if isinstance(v, dict)]
    live = ('leased', 'building', 'review', 'orphaned', 'requeued')
    attention = ('failed', 'escalated')
    print(sum(1 for v in rows if v.get('state') in live),
          sum(1 for v in rows if v.get('state') in attention))
except Exception:
    print('0 0')
" 2>/dev/null || echo '0 0')
  ACTIVE=$(printf '%s' "$COUNTS" | awk '{print $1+0}')
  ATTENTION=$(printf '%s' "$COUNTS" | awk '{print $2+0}')
  if [ "${ACTIVE:-0}" -gt 0 ] 2>/dev/null; then
    printf '%s' "A lease ledger exists (ops/leases.toml). FIRST reconstruct wave state from it — reclaim orphans (lease_heartbeat_check), keep merged work, requeue or finish open leases — instead of restarting the wave from scratch."
  fi
  if [ "${ATTENTION:-0}" -gt 0 ] 2>/dev/null; then
    [ "${ACTIVE:-0}" -gt 0 ] && printf ' '
    printf '%s' "${ATTENTION} lease(s) are in a failed/escalated state needing a decision — surface them (lease_status) and resolve or abandon them before the sprint is considered done; do NOT silently drop them."
  fi
  return 0
}

# The goal as at-ship reads it. at-ship has no argument parser of its own: the
# lead model reads its argument-hint, "<goal description> [--convergence ...]
# [--team]". So the goal goes first as one double-quoted string (JSON escaping,
# lines joined) and this script's own flags follow the closing quote: a
# "--team" or "--convergence" inside the goal stays inside the quotes.
GOAL_QUOTED=$(CA_GOAL="$GOAL" python3 -c 'import json, os; print(json.dumps(" ".join(os.environ["CA_GOAL"].splitlines()), ensure_ascii=False))')

CHECKLIST="Sprint complete ONLY when ALL of: (1) every framework phase for the goal is done or explicitly skipped with a stated reason; (2) the verification-before-completion checklist passes with evidence; (3) ops/STATE.md is written for session handoff; (4) temporary review files are archived to ops/archive/; (5) the runtime marker ops/.sprint-complete exists — created LAST, only after conditions 1-4 hold."

# Compose the per-iteration session prompt. Sets $PROMPT.
# $1 = iteration number.
# Under a lead with a goal gate the first line is "<goal_gate> <checklist>":
# a slash command can only be user-typed or the first line of a headless
# prompt, which is exactly what this is. Under a lead without one the first
# line invokes the at-ship skill ($<skill> mention form) and the checklist is
# the standing completion condition, met on the sentinel alone (KTD14).
compose_prompt() {
  local LEASE_RESUME LEAD_LINE GATE_RULE
  LEASE_RESUME=$(lease_resume_paragraph)
  if [ -n "$GOAL_GATE" ]; then
    LEAD_LINE="${GOAL_GATE} ${CHECKLIST}"
    GATE_RULE="Completion signal: ONLY when the ${GOAL_GATE} checklist above is fully satisfied, create the empty runtime marker ops/.sprint-complete (touch ops/.sprint-complete) as your LAST action."
  else
    LEAD_LINE="\$at-ship ${GOAL_QUOTED} --convergence ${CONVERGENCE}${USE_TEAM:+ ${USE_TEAM}}"
    GATE_RULE="Completion checklist (this lead has no goal gate; the sentinel alone completes the sprint): ${CHECKLIST}
Completion signal: ONLY when that checklist is fully satisfied, create the empty runtime marker ops/.sprint-complete (touch ops/.sprint-complete) as your LAST action."
  fi
  PROMPT="${LEAD_LINE}

You are continuing a multi-agent sprint.

GOAL: $GOAL
CONVERGENCE MODE: $CONVERGENCE
ITERATION: $1 of $MAX_ITERATIONS
$USE_TEAM

FIRST: Read ops/STATE.md to understand where the previous session left off.
If this is iteration 1 and no STATE.md exists, start from Phase 0.${LEASE_RESUME:+

$LEASE_RESUME}

Follow the Agent Triforge framework (docs/agent-triforge.md):
- Phase 0: Codebase analysis (Antigravity) — skip if STATE.md shows Phase 0 complete
- Phase 1: Planning — skip if TASKS.md already exists for this goal
- Phase 1.5: Plan validation — run plan-checker agent
- Phase 2: Build — use wave orchestration for complex builds
- Phase 3: Parallel review — Antigravity + Codex + Claude subagent reviewers
- Phase 4: Process reviews — use findings-synthesizer agent
- Phase 5: Test — Codex writes and runs tests
- Phase 6: Wrap up — compound knowledge, update STATE.md

Before exiting, ALWAYS update ops/STATE.md with current progress.
${GATE_RULE} NEVER create it early — the outer loop detects completion solely by this file's existence."
}

# launch_line — the launch line as typed: the registry's launch_argv, the
# model and effort words, then the prompt quoted for a POSIX shell.
launch_line() {
  printf '%s %s\n' "$LAUNCH_SHOWN" "$(CA_PROMPT="$PROMPT" python3 -c 'import os, shlex; print(shlex.quote(os.environ["CA_PROMPT"]))')"
}

# launch_notes [prefix] — each note on the model and effort flags, once.
launch_notes() {
  if [ -n "$LAUNCH_NOTES" ]; then printf '%s\n' "$LAUNCH_NOTES" | sed "s/^/${1:-note: }/"; fi
}

# Dry run: print the launch line and the composed prompt (iteration 1) and
# exit. No lead run, no sentinel mutation, no integrity check (nothing runs).
if [ "$DRY_RUN" = "true" ]; then
  compose_prompt 1
  echo "launch (${LEAD_NAME}): ${LAUNCH_SHOWN} <the prompt below, as one argument>"
  launch_notes
  if [ "$FULL_ACCESS" = 1 ]; then
    echo "full access: this launch line runs only with --allow-full-access (R50): ${FULL_WHY}"
  fi
  if [ -z "$GOAL_GATE" ]; then
    echo "goal gate: none for ${LEAD_NAME}; the session completes on ${SENTINEL} alone (KTD14)"
  fi
  echo "---"
  printf '%s\n' "$PROMPT"
  exit 0
fi

# Full access is the human's call (R50): without the acknowledgement, print
# what to type and run nothing.
if [ "$FULL_ACCESS" = 1 ] && [ "$ALLOW_FULL_ACCESS" != "true" ]; then
  compose_prompt 1
  echo "coordinate.sh: the ${LEAD_NAME} lead's launch line runs with full access (no sandbox, no approval prompts; ${FULL_WHY}):" >&2
  echo "" >&2
  echo "  ${LAUNCH_SHOWN}" >&2
  echo "" >&2
  launch_notes >&2
  confinement_statements >&2
  echo "" >&2
  echo "Nothing ran. Launching a full-access lead is the human's step: rerun this command with --allow-full-access to let the loop launch it each iteration, or type one session yourself:" >&2
  launch_line
  exit 77
fi

# Preflight: the lead's binary must be on PATH, or every iteration below
# would be a silent no-op.
if ! command -v "${LAUNCH_WORDS[0]}" >/dev/null 2>&1; then
  echo "coordinate.sh: ERROR \`${LAUNCH_WORDS[0]}\` (the ${LEAD_NAME} lead) not found on PATH." >&2
  echo "  Fix: $(cli_install_fix "$LEAD" 2>/dev/null || echo "install ${LEAD_NAME}")" >&2
  exit 1
fi

# The loop is a lead-owned helper (R38): it runs under the lead's own host
# markers, from a terminal, or under the SELF seam, and refuses anywhere else
# (nohup, cron, CI: no terminal and no markers) before it reads or writes the
# ledger, with the helper's own message and rc 45.
if ! _lead_only coordinate.sh; then
  echo "coordinate.sh: STOPPED before starting a session — run the loop from a terminal or from the ${LEAD_NAME} lead's own shell (rc ${_RC_LEAD_ONLY}, above)." >&2
  exit "$_RC_LEAD_ONLY"
fi

# --- Notification (optional, env-var-gated) ---
notify() {
  local title="$1" body="$2"
  if [ -n "${NOTIFY_WEBHOOK_URL:-}" ]; then
    curl -s --connect-timeout 5 --max-time 10 -X POST "$NOTIFY_WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "{\"text\": \"$title: $body\"}" > /dev/null 2>&1 || true
  fi
  if command -v osascript &>/dev/null; then
    osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "$title" "$body" 2>/dev/null || true
  fi
}

# stop_fix <reason> — the fix line for a deterministic stop, by the KTD-9
# reason: a login for auth (the registry's login hint), a wait for quota (no
# reinstall helps), the install line for anything else (binary missing).
stop_fix() {
  local LOGIN=""
  case "${1:-}" in
    auth)
      LOGIN=$(cli_field "$LEAD" login 2>/dev/null) || LOGIN=""
      printf 'not logged in: %s\n' "${LOGIN:-log in to ${LEAD_NAME}}"
      ;;
    quota)
      printf 'the %s quota or rate limit is reached; wait for it to reset or switch plans, then rerun\n' "$LEAD_NAME"
      ;;
    *)
      cli_install_fix "$LEAD" 2>/dev/null || printf 'install %s\n' "$LEAD_NAME"
      ;;
  esac
}

# integrity_gate — the lead-side integrity check before a session (KTD18).
# Outside a git repository (no .git above: _lead_roster_path stays relative)
# there are no leases and nothing to compare; inside one, a check that can't
# run is a stop, like any change. The check runs against the lease root the
# ledger was last written under (_lease_at_ledger_root, as lease_approve):
# a shell whose TMPDIR derives another root would otherwise compare the ledger
# with no anchors at all and adopt whatever it holds. A recorded root that is
# gone refuses, naming TRIFORGE_LEASE_ROOT.
integrity_gate() {
  local RC=0
  local TRIFORGE_LEASE_ROOT="${TRIFORGE_LEASE_ROOT:-}"   # _lease_at_ledger_root may set it
  case "$(_lead_roster_path)" in
    /*) ;;
    *) return 0 ;;
  esac
  if ! _lease_ctx || ! _lease_at_ledger_root coordinate.sh; then
    echo "coordinate.sh: STOPPED before starting a session — the lease root the ledger was last written under can't be used from this shell (above). Point TRIFORGE_LEASE_ROOT at the lead's lease root and rerun; an unattended session never starts on a ledger it can't check." >&2
    exit 44
  fi
  _lead_integrity_check coordinate.sh || RC=$?
  if [ "$RC" -eq 0 ]; then
    return 0
  fi
  if [ "$RC" -eq "$_RC_LEAD_ONLY" ]; then
    echo "coordinate.sh: the integrity check is lead-owned and this shell may not run it (rc ${RC}, above); no session started. Run coordinate.sh from a terminal, or from the ${LEAD_NAME} lead's own shell." >&2
    exit "$RC"
  fi
  echo "coordinate.sh: STOPPED before starting a session — the integrity check returned rc ${RC} (above). Inspect the change; if you or the lead made it, accept it with lease_rebaseline <task...>, then rerun. An unattended session never accepts it." >&2
  exit 44
}

PROGRESS_FILE="ops/STATE.md"
ITERATION=0
DONE=false
RUN_LOG=$(mktemp "${TMPDIR:-/tmp}/triforge-coordinate.XXXXXX")
trap 'rm -f "$RUN_LOG"' EXIT

echo "=== Multi-Agent Coordinate Loop ==="
echo "Goal: $GOAL"
echo "Lead: ${LEAD_NAME} (${LAUNCH_SHOWN})"
launch_notes
echo "Max iterations: $MAX_ITERATIONS"
echo "Convergence: $CONVERGENCE"
if [ -z "$GOAL_GATE" ]; then
  # R44: the missing capability, said once for the run.
  echo "Goal gate: none for ${LEAD_NAME}; each session completes on ${SENTINEL} alone (KTD14)"
fi
if [ "$FULL_ACCESS" = 1 ]; then
  echo "Full access: acknowledged (--allow-full-access). Stated plainly:"
  confinement_statements
fi
echo ""

# Fresh run: clear any stale completion marker (runtime file, gitignored)
rm -f "$SENTINEL"

while [ "$ITERATION" -lt "$MAX_ITERATIONS" ] && [ "$DONE" = "false" ]; do
  ITERATION=$((ITERATION + 1))
  echo "--- Iteration $ITERATION/$MAX_ITERATIONS ---"

  integrity_gate
  compose_prompt "$ITERATION"

  # Run the lead with the composed prompt (tail shown for observability)
  RUN_RC=0
  "${LAUNCH_WORDS[@]}" "$PROMPT" < /dev/null > "$RUN_LOG" 2>&1 || RUN_RC=$?
  tail -n 20 "$RUN_LOG"

  # Completion check: headless-observable sentinel created by the session
  # only after the verification checklist passes
  if [ -f "$SENTINEL" ]; then
    DONE=true
    notify "Agent Triforge" "Sprint complete — converged in $ITERATION iterations"
    echo ""
    echo "=== Sprint complete at iteration $ITERATION ($SENTINEL present) ==="
  elif [ "$RUN_RC" -ne 0 ]; then
    # A failed run is classified (KTD-9) on its last lines: a deterministic
    # class (not logged in, quota spent, binary missing) repeats on every
    # fresh session, so the loop stops here instead of spending the rest.
    tail -n 50 "$RUN_LOG" > "${RUN_LOG}.tail" 2>/dev/null || true
    _classify_invoke_failure "$RUN_RC" "${RUN_LOG}.tail"
    rm -f "${RUN_LOG}.tail"
    if [ "$INVOKE_FAILURE_CLASS" = "deterministic" ]; then
      echo ""
      echo "=== Stopped at iteration $ITERATION: the ${LEAD_NAME} lead failed (exit ${RUN_RC}, class=${INVOKE_FAILURE_CLASS} reason=${_INVOKE_FAILURE_REASON:-unknown}) ===" >&2
      echo "Fix: $(stop_fix "${_INVOKE_FAILURE_REASON:-}")" >&2
      notify "Agent Triforge" "Sprint stopped — the lead failed (${_INVOKE_FAILURE_REASON:-deterministic})"
      exit 69
    fi
    echo "Session exited ${RUN_RC} (class=${INVOKE_FAILURE_CLASS}) without creating $SENTINEL. Spawning fresh session..."
    echo ""
  else
    echo "Session ended without creating $SENTINEL. Spawning fresh session..."
    echo ""
  fi
done

if [ "$DONE" = "false" ]; then
  echo ""
  echo "=== Max iterations ($MAX_ITERATIONS) reached without completion ==="
  notify "Agent Triforge" "Sprint did NOT converge after $MAX_ITERATIONS iterations"
  echo "Check ${PROGRESS_FILE} for current progress."
  echo "Check ops/TASKS.md for remaining tasks."
  echo "Run again to continue, or review manually."
fi
