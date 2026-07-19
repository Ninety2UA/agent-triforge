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

AGY_OUT="${TMPDIR:-/tmp}/antigravity_review_$$_$(date +%s).txt"
CODEX_OUT="${TMPDIR:-/tmp}/codex_review_$$_$(date +%s).txt"

# Antigravity architecture review (uses architecture-reviewer agent definition)
invoke_antigravity "architecture-reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. Write findings to ops/REVIEW_ANTIGRAVITY.md if you can; otherwise return them as your response." \
  "$AGY_OUT" 600 &
AGY_PID=$!

# Codex logic + security review (uses logic_reviewer agent definition)
# If scope covers 5+ files, Codex will spawn internal subagents for parallel review
invoke_codex "logic_reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. If scope covers 5+ files, spawn separate agents for logic review, security audit, and test coverage analysis — merge all findings into ops/REVIEW_CODEX.md. Otherwise review sequentially and write to ops/REVIEW_CODEX.md." \
  "$CODEX_OUT" 600 &
CODEX_PID=$!

# Wait for each PID individually so we can fail-fast if either reviewer died;
# a silent failure would leave REVIEW_*.md empty and look like "no findings".
AGY_RC=0; CODEX_RC=0
wait $AGY_PID || AGY_RC=$?
wait $CODEX_PID  || CODEX_RC=$?
if [ $AGY_RC -ne 0 ] || [ $CODEX_RC -ne 0 ]; then
  echo "review: reviewer failed — antigravity=$AGY_RC codex=$CODEX_RC" >&2
  echo "review: last stderr in $AGY_OUT / $CODEX_OUT" >&2
  exit 1
fi

# Headless resilience: agy auto-denies permission-requiring tools in -p mode,
# so the reviewer may have returned findings instead of writing ops/ directly.
# Promote the captured output so the pipeline stays alive either way.
if [ ! -f "ops/REVIEW_ANTIGRAVITY.md" ] && [ -s "$AGY_OUT" ]; then
  {
    echo "<!-- captured from invoke_antigravity output; agent could not write ops/ directly (headless permission auto-deny) -->"
    cat "$AGY_OUT"
  } > ops/REVIEW_ANTIGRAVITY.md
fi
```

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
    { echo "<!-- captured from invoke_${OCLI} reviewer output; headless permission auto-deny -->"; cat "$OOUT"; } > "ops/REVIEW_${UP}.md"
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
