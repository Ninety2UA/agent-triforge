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

## Phase 3: Launch parallel reviews

Read ops/TASKS.md to determine review scope (tasks marked [R]).

### Always launch (background bash):

```bash
# Gemini architecture review
gemini -p "You are reviewing code in a multi-agent repository.
YOUR ROLE: Architecture reviewer + documentation specialist.
READ: ops/CHANGELOG.md, ops/CONTRACTS.md, ops/ARCHITECTURE.md, ops/MEMORY.md, ops/TASKS.md
USE CONFIDENCE TIERING: [HIGH] verified, [MEDIUM] pattern match, [LOW] heuristic
RULE: [LOW] confidence can NEVER be P1.
DO NOT FLAG: readability redundancy, documented thresholds, sufficient assertions, consistency-only style, already-addressed issues.
Write findings to ops/REVIEW_GEMINI.md." > /tmp/gemini_review.txt 2>&1 &
GEMINI_PID=$!

# Codex logic + security review
codex exec "You are reviewing code in a multi-agent repository.
YOUR ROLE: Logic reviewer + security auditor + test coverage analyst.
READ: ops/CHANGELOG.md, ops/CONTRACTS.md, ops/MEMORY.md, ops/TASKS.md
USE CONFIDENCE TIERING: [HIGH] verified, [MEDIUM] pattern match, [LOW] heuristic
RULE: [LOW] confidence can NEVER be P1.
DO NOT FLAG: test fixture hardcoded values, readability redundancy, dev-only config, sufficient assertions, already-addressed issues.
Write findings to ops/REVIEW_CODEX.md." > /tmp/codex_review.txt 2>&1 &
CODEX_PID=$!

# Wait for external reviewers with timeout (10 min per agent)
AGENT_TIMEOUT=600
for PID in $GEMINI_PID $CODEX_PID; do
  ( sleep $AGENT_TIMEOUT && kill -TERM $PID 2>/dev/null && sleep 5 && kill -9 $PID 2>/dev/null ) &
  WD=$!
  wait $PID 2>/dev/null
  kill $WD 2>/dev/null; wait $WD 2>/dev/null
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
2. It reads ops/REVIEW_GEMINI.md, ops/REVIEW_CODEX.md, and subagent outputs
3. Produces synthesized report with confidence tiering (HIGH/MEDIUM/LOW) and priority (P1/P2/P3)
4. Apply `iterative-refinement` skill:
   - Fix P1 (critical) immediately
   - Fix P2 (important) this cycle
   - Log P3 (suggestion) for later
5. Convergence check: P1=0 AND P2=0 → proceed (standard mode)
6. If not converged → re-trigger review on changed files only (max 3 cycles)
7. After 3 cycles without convergence → escalate to user
