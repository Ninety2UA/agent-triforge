---
name: review-synthesis
description: "Merge, deduplicate, and prioritize findings from multiple reviewers with confidence tiering. Primary consumer: Claude Code (Phase 4)."
---

# Review Synthesis

When processing findings from multiple reviewers (Gemini, Codex, Claude subagent reviewers), follow this protocol to produce a single, actionable, deduplicated report.

## Step 1: Collect all findings

Read all review outputs:
- `ops/REVIEW_GEMINI.md` (architecture, design, documentation)
- `ops/REVIEW_CODEX.md` (logic, security, tests)
- Any subagent review outputs (security-sentinel, performance-oracle, etc.)

## Step 2: Normalize format

Convert every finding to:

```
[CONFIDENCE] [PRIORITY] [file:line] — [description]
Source: [reviewer name(s)]
Recommendation: [what to do]
```

## Step 3: Assign confidence tiers

| Tier | Criteria | Example |
|---|---|---|
| **HIGH** | Verified in codebase via grep/read; deterministic detection | Missing null check at line 45 (confirmed: no guard exists) |
| **MEDIUM** | Detected via pattern matching; some false positive risk | Possible N+1 query in user loop (likely but depends on ORM behavior) |
| **LOW** | Requires intent verification; heuristic-only detection | "This function seems too complex" (subjective, needs context) |

**Rule:** LOW confidence findings can NEVER be Priority 1. Maximum P2.

## Step 4: Assign priority

| Priority | Definition | Action |
|---|---|---|
| **P1 Critical** | Security vulnerability, data loss risk, crash, broken core functionality | Fix immediately, block ship |
| **P2 Important** | Performance at scale, missing error handling, test gaps, logic errors | Fix this cycle |
| **P3 Suggestion** | Style, naming, documentation, minor optimization | Log or fix if trivial |

## Step 5: Deduplicate

When multiple reviewers flag the same issue:

| Scenario | Action |
|---|---|
| Same problem + same recommendation | Merge into single entry, note all sources, bump confidence |
| Same problem + different recommendations | Merge, list both recommendations, decide based on ARCHITECTURE.md |
| Different problems at same location | Keep as separate entries |
| One reviewer approves, another flags | The flag wins — address the concern |
| Contradictory findings | Flag explicitly as CONTRADICTION, do not resolve silently |

## Step 6: Apply suppressions

Do NOT include findings that match these patterns:
- Redundancy that aids readability (explicit types where inference works)
- Documented threshold values with clear context comments
- Sufficient test coverage (don't flag "too few tests" when behavior is covered)
- Consistency-only style changes (project convention already applied)
- Issues already addressed in the current diff
- Harmless no-ops (return undefined at end of void function)

## Output

Produce a single markdown document with:
- All findings grouped by file, ordered by priority (P1→P2→P3)
- Each finding annotated with confidence tier and source reviewer(s)
- Contradictions section (if any)
- Summary counts by priority

## Step 7: Produce synthesized report

Group findings by file, ordered by priority:

```markdown
## Synthesized review findings
<!-- Cycle [N] | Sources: Gemini, Codex, [subagents] -->

### Critical (P1) — fix before proceeding
- [HIGH] src/auth/login.ts:45 — SQL injection via unsanitized email input
  Sources: Codex (security), security-sentinel
  Fix: Use parameterized query

### Important (P2) — fix this cycle
- [HIGH] src/api/users.ts:120 — Missing error handling for DB timeout
  Sources: Codex (logic), Gemini (architecture)
  Fix: Add try/catch with 503 response
- [MEDIUM] src/api/users.ts:89 — Possible N+1 query in user list
  Sources: performance-oracle
  Fix: Add eager loading for user.roles

### Suggestions (P3) — log for later
- [LOW] src/utils/format.ts:12 — Function could be simplified
  Sources: code-simplicity-reviewer
  Note: Works correctly, style preference only

### Contradictions
- src/auth/middleware.ts:30 — Gemini recommends extracting to utility, Codex recommends keeping inline for clarity
  Decision needed: [resolve based on ARCHITECTURE.md patterns]

### Summary
- P1: [count] (must fix)
- P2: [count] (should fix)
- P3: [count] (optional)
- Contradictions: [count] (needs decision)
```
