---
description: "Deep compatibility analysis of an external repo/resource against our system."
argument-hint: "<github-url or local-path>"
---

You are a senior systems architect performing a deep compatibility analysis. Use ultrathink.

## Task
Analyze this repo/resource in depth and evaluate whether its prompts, patterns, mechanisms, or architecture would be useful to incorporate into OUR system (the current project).

## Input
$ARGUMENTS

## Analysis Framework

### 1. Repo Overview
- Purpose, architecture, and core mechanism
- Tech stack and dependencies
- Maturity and maintenance status

### 2. Extractable Patterns
For each notable prompt, pattern, or mechanism found:
- **What it is**: precise description
- **How it works**: implementation detail
- **Relevance to our system**: direct mapping to our existing architecture
- **Adoption effort**: trivial / moderate / significant refactor
- **Risk/tradeoff**: what we gain vs. what could break or add complexity

### 3. Prompt Engineering Insights
- System prompt structures, role definitions, guardrails
- Chain-of-thought or orchestration strategies
- Tool use patterns, context management techniques
- Anything that outperforms or differs from our current approach

### 4. Verdict Matrix
Summarize as a table:
| Pattern/Mechanism | Usefulness (1-5) | Effort (1-5) | Priority | Notes |
Each row = one concrete extractable element.

### 5. Recommended Actions
- Ranked list of what to adopt, adapt, or ignore
- For each "adopt/adapt" item: sketch the integration path into our system

## Constraints
- DO NOT edit, modify, or write to any files
- Read-only analysis only
- Be exhaustive — scan all key files (AGENTS.md, prompts, configs, orchestration logic, README, src/)
- Compare against our current conventions (check AGENTS.md, CONVENTIONS.md, docs/) to avoid redundant suggestions
- If the input is a URL, fetch and analyze it; if a local path, read it directly
