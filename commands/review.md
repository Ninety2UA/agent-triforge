---
description: "Trigger parallel review: Antigravity + Codex + Claude specialized agents. Synthesize findings."
allowed-tools: Read, Grep, Glob, Bash, Agent, Edit
argument-hint: "[--full] [--security] [--perf] [--simple] [--conventions]"
---

You are executing Phase 3 + Phase 4 of the multi-agent framework (parallel review + synthesis).

## Preflight

Core-trio liveness is gated lazily here — never at session start, so a /status-only session never pays for it. Fast non-model checks (`--version`, cached per session); on failure it names the failing member and its install/login fix:

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh
ensure_core_trio_live || exit 1
```

## Arguments
$ARGUMENTS

Flags:
- `--full` — Run ALL review agents (Antigravity + Codex + security-sentinel + performance-oracle + code-simplicity-reviewer + convention-enforcer + architecture-strategist)
- `--security` — Add security-sentinel to default reviewers
- `--perf` — Add performance-oracle to default reviewers
- `--simple` — Add code-simplicity-reviewer to default reviewers
- `--conventions` — Add convention-enforcer to default reviewers
- No flags — Default: Antigravity + Codex only

> **Note:** For small changes (< 3 files, obvious fix), consider `/quick` instead — it uses self-review only, skipping the full review swarm.

## Phase 3: Launch parallel reviews

Read ops/TASKS.md to determine review scope (tasks marked [R]).

### Always launch (background bash):

```bash
set -euo pipefail
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Fresh-cycle guard (prevents stale findings surviving a fix cycle). A reviewer
# that returns findings as stdout (headless permission auto-deny) is promoted
# into ops/REVIEW_*.md ONLY when that file is ABSENT (the `[ ! -f ... ]` guards
# below). Without clearing prior-cycle files first, cycle N-1's REVIEW_*.md
# would survive and findings-synthesizer would read it as cycle N's result —
# a green-while-red review that hides newly-introduced findings. Archive (not
# delete) so each prior cycle stays auditable under ops/archive/reviews/.
if ls ops/REVIEW_*.md >/dev/null 2>&1; then
  _REV_ARCH="ops/archive/reviews/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$_REV_ARCH" && mv ops/REVIEW_*.md "$_REV_ARCH"/ 2>/dev/null || true
fi

AGY_OUT="${TMPDIR:-/tmp}/antigravity_review_$$_$(date +%s).txt"
CODEX_OUT="${TMPDIR:-/tmp}/codex_review_$$_$(date +%s).txt"

# Core review swarm, ROSTER-DRIVEN (R19/AE4): the analyst role (shipped default
# Antigravity, architecture-reviewer) and the reviewer role (shipped default
# Codex, logic_reviewer). Routing through dispatch_role — instead of hardcoding
# invoke_antigravity/invoke_codex — means a roster override such as
# `[roles.reviewer] cli = "opencode"` actually takes effect here (it was
# previously ignored for the core lane). dispatch_role returns 40 when a role
# resolves to the CLAUDE lane (run that reviewer as a native subagent, below);
# any other nonzero is a real reviewer failure.
dispatch_role analyst "architecture-reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. Write findings to ops/REVIEW_ANTIGRAVITY.md if you can; otherwise return them as your response." \
  "$AGY_OUT" 600 &
AGY_PID=$!

# If scope covers 5+ files, the reviewer CLI may spawn internal subagents.
dispatch_role reviewer "logic_reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. If scope covers 5+ files, spawn separate agents for logic review, security audit, and test coverage analysis — merge all findings into ops/REVIEW_CODEX.md. Otherwise review sequentially and write to ops/REVIEW_CODEX.md." \
  "$CODEX_OUT" 600 &
CODEX_PID=$!

# Wait per-PID so a silent failure (which would leave REVIEW_*.md empty and look
# like "no findings") fails fast. rc 40 = resolved to the claude lane, handled
# by a native subagent below — NOT a failure.
AGY_RC=0; CODEX_RC=0
wait $AGY_PID || AGY_RC=$?
wait $CODEX_PID  || CODEX_RC=$?
if [ "$AGY_RC" -eq 40 ]; then
  echo "review: analyst role resolved to the claude lane — run the architecture review as a native Claude subagent (below), not a shell helper" >&2
elif [ "$AGY_RC" -ne 0 ]; then
  echo "review: analyst (architecture) reviewer failed rc=$AGY_RC — see $AGY_OUT" >&2; exit 1
fi
if [ "$CODEX_RC" -eq 40 ]; then
  echo "review: reviewer role resolved to the claude lane — run the logic/security review as a native Claude subagent (below), not a shell helper" >&2
elif [ "$CODEX_RC" -ne 0 ]; then
  echo "review: reviewer (logic) reviewer failed rc=$CODEX_RC — see $CODEX_OUT" >&2; exit 1
fi

# Headless resilience: agy (and any optional-CLI primary) auto-denies file
# writes in -p mode, so a reviewer may return findings as stdout instead of
# writing ops/. Promote captured output (scrubbed) so the pipeline stays alive
# either way — symmetric for BOTH core lanes now that the reviewer lane can be
# any roster CLI, not just Codex-writes-directly.
if [ ! -f "ops/REVIEW_ANTIGRAVITY.md" ] && [ -s "$AGY_OUT" ]; then
  { echo "<!-- captured from analyst-role output; agent could not write ops/ directly (headless permission auto-deny) -->"; _scrub < "$AGY_OUT"; } > ops/REVIEW_ANTIGRAVITY.md
fi
if [ ! -f "ops/REVIEW_CODEX.md" ] && [ -s "$CODEX_OUT" ]; then
  { echo "<!-- captured from reviewer-role output; agent could not write ops/ directly (headless permission auto-deny) -->"; _scrub < "$CODEX_OUT"; } > ops/REVIEW_CODEX.md
fi

# Codex structured verdict (R16): invoke_codex writes <out>.verdict.json when the
# reviewer agent declares an output_schema (logic_reviewer does, via
# review-verdict.schema.json). Fold it (scrubbed) into REVIEW_CODEX.md so
# findings-synthesizer actually CONSUMES the structured verdict instead of it
# being produced-but-ignored. Guarded on existence: only the Codex lane emits it,
# so a roster override to a non-Codex reviewer simply skips this.
if [ -f "${CODEX_OUT}.verdict.json" ]; then
  {
    echo ""
    echo "<!-- structured verdict (codex --output-schema, review-verdict.schema.json) -->"
    echo '```json'
    _scrub < "${CODEX_OUT}.verdict.json"
    echo '```'
  } >> ops/REVIEW_CODEX.md 2>/dev/null || true
fi
```

**If `AGY_RC` or `CODEX_RC` was 40 above**, that role resolved to the Claude lane (its default CLI is absent, or the roster pins `cli = "claude"`). Spawn a native Claude subagent (Agent tool) for that reviewer against the `[R]` scope — architecture-strategist for the analyst lane, a logic + security review for the reviewer lane — writing findings to `ops/REVIEW_ANTIGRAVITY.md` / `ops/REVIEW_CODEX.md` respectively, so `findings-synthesizer` sees them alongside the other lanes.

### Optional reviewer lanes (roster-driven):

The core-trio swarm above (Antigravity + Codex) is the shipped default and always runs. In addition, dispatch a reviewer lane for every **enrolled optional member** (`[members.<cli>] enabled = true` in `ops/roster.toml`) AND for any optional CLI named as the **primary `reviewer`** via `[roles.reviewer] cli = "<optional>"`. Each writes `ops/REVIEW_<CLI>.md`; `findings-synthesizer` globs `ops/REVIEW_*.md`, so these lanes are merged automatically when present. Members that are absent or declined are skipped silently (AE1).

```bash
set -euo pipefail
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

# Read the reviewer-role primary so a [roles.reviewer] cli="<optional>" override
# runs that optional CLI as the primary reviewer even if it is not in the
# enrolled-members list (roles do not require enrollment; members do).
REVIEWER_PRIMARY=""
if RESOLVED_REVIEWER=$(resolve_role reviewer 2>/dev/null); then
  REVIEWER_PRIMARY=$(printf '%s\n' "$RESOLVED_REVIEWER" | cut -f1)
fi

REVIEW_PROMPT="Review scope: tasks marked [R] in ops/TASKS.md. Report findings as [SEVERITY] file:line — issue → fix. Write them to ops/REVIEW_<YOUR_CLI>.md if you can; otherwise return them as your response."

for OCLI in opencode kimi cursor; do
  ENABLED=$(_roster_member_field "$OCLI" enabled 2>/dev/null || true)
  # Run when enrolled-enabled OR named as the reviewer-role primary; else skip.
  if [ "$ENABLED" != "true" ] && [ "$OCLI" != "$REVIEWER_PRIMARY" ]; then
    continue
  fi
  OMODEL=$(_roster_member_field "$OCLI" model 2>/dev/null || true)   # empty -> helper's shipped default
  UP=$(printf '%s' "$OCLI" | tr '[:lower:]' '[:upper:]')
  OOUT="${TMPDIR:-/tmp}/${OCLI}_review_$$_$(date +%s).txt"
  ORC=0
  case "$OCLI" in
    opencode) OPENCODE_MODEL="${OMODEL:-}" invoke_opencode "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
    kimi)     KIMI_MODEL="${OMODEL:-}"     invoke_kimi     "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
    cursor)   CURSOR_MODEL="${OMODEL:-}"   invoke_cursor   "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
  esac
  [ "$ORC" -ne 0 ] && echo "review: ${OCLI} reviewer lane exited $ORC (see $OOUT) — optional lane, continuing" >&2
  # Headless resilience: promote captured output into ops/REVIEW_<CLI>.md when the
  # reviewer returned findings instead of writing ops/ directly.
  if [ ! -f "ops/REVIEW_${UP}.md" ] && [ -s "$OOUT" ]; then
    { echo "<!-- captured from invoke_${OCLI} reviewer output; headless permission auto-deny -->"; _scrub < "$OOUT"; } > "ops/REVIEW_${UP}.md"
  fi
done
```

### Conditionally launch Claude subagent reviewers:
- If `--full` or `--security` → spawn `security-sentinel` agent
- If `--full` or `--perf` → spawn `performance-oracle` agent
- If `--full` or `--simple` → spawn `code-simplicity-reviewer` agent
- If `--full` → also spawn `convention-enforcer` and `architecture-strategist` agents

Launch all applicable subagents in a SINGLE message for maximum parallelism.

Wait for all reviewers to complete.

## Phase 4: Synthesize findings

1. Spawn the `findings-synthesizer` agent
2. It reads ALL `ops/REVIEW_*.md` lanes (Antigravity + Codex + any optional-tier REVIEW_OPENCODE/KIMI/CURSOR.md) plus subagent outputs
3. Produces synthesized report with confidence tiering (HIGH/MEDIUM/LOW) and priority (P1/P2/P3)
4. Apply `iterative-refinement` skill:
   - Fix P1 (critical) immediately
   - Fix P2 (important) this cycle
   - Log P3 (suggestion) for later
5. Convergence check: P1=0 AND P2=0 → proceed (standard mode)
6. If not converged → re-trigger review on changed files only (max 3 cycles)
7. After 3 cycles without convergence → escalate to user
