---
description: "Trigger parallel review: Gemini + Codex + Claude specialized agents. Synthesize findings."
argument-hint: "[--full] [--security] [--perf] [--simple] [--conventions]"
---

You are executing Phase 3 + Phase 4 of the multi-agent framework (parallel review + synthesis).

## Arguments
$ARGUMENTS

Flags:
- `--full` — Run ALL review agents (Gemini + Codex + security-sentinel + performance-oracle + code-simplicity-reviewer + convention-enforcer + architecture-strategist)
- `--security` — Add security-sentinel to default reviewers
- `--perf` — Add performance-oracle to default reviewers
- `--simple` — Add code-simplicity-reviewer to default reviewers
- `--conventions` — Add convention-enforcer to default reviewers
- No flags — Default: Gemini + Codex only

> **Note:** For small changes (< 3 files, obvious fix), consider `/quick` instead — it uses self-review only, skipping the full review swarm.

## Phase 3: Launch parallel reviews

Read ops/TASKS.md to determine review scope (tasks marked [R]).

### Always launch (background bash):

```bash
source ${CLAUDE_PLUGIN_ROOT}/scripts/invoke-external.sh

GEMINI_OUT="${TMPDIR:-/tmp}/gemini_review_$$_$(date +%s).txt"
CODEX_OUT="${TMPDIR:-/tmp}/codex_review_$$_$(date +%s).txt"

# Gemini architecture review (uses architecture-reviewer agent definition)
invoke_gemini "architecture-reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. Write findings to ops/REVIEW_GEMINI.md." \
  "$GEMINI_OUT" 600 &
GEMINI_PID=$!

# Codex logic + security review (uses logic_reviewer agent definition)
# If scope covers 5+ files, Codex will spawn internal subagents for parallel review
invoke_codex "logic_reviewer" \
  "Review scope: tasks marked [R] in ops/TASKS.md. If scope covers 5+ files, spawn separate agents for logic review, security audit, and test coverage analysis — merge all findings into ops/REVIEW_CODEX.md. Otherwise review sequentially and write to ops/REVIEW_CODEX.md." \
  "$CODEX_OUT" 600 &
CODEX_PID=$!

# Wait for each PID individually so we can fail-fast if either reviewer died;
# a silent failure would leave REVIEW_*.md empty and look like "no findings".
GEMINI_RC=0; CODEX_RC=0
wait $GEMINI_PID || GEMINI_RC=$?
wait $CODEX_PID  || CODEX_RC=$?
if [ $GEMINI_RC -ne 0 ] || [ $CODEX_RC -ne 0 ]; then
  echo "review: reviewer failed — gemini=$GEMINI_RC codex=$CODEX_RC" >&2
  echo "review: last stderr in $GEMINI_OUT / $CODEX_OUT" >&2
  exit 1
fi
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
2. It reads ops/REVIEW_GEMINI.md, ops/REVIEW_CODEX.md, and subagent outputs
3. Produces synthesized report with confidence tiering (HIGH/MEDIUM/LOW) and priority (P1/P2/P3)
4. Apply `iterative-refinement` skill:
   - Fix P1 (critical) immediately
   - Fix P2 (important) this cycle
   - Log P3 (suggestion) for later
5. Convergence check: P1=0 AND P2=0 → proceed (standard mode)
6. If not converged → re-trigger review on changed files only (max 3 cycles)
7. After 3 cycles without convergence → escalate to user
