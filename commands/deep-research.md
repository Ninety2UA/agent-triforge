---
description: "Launch a research swarm: 5 parallel research agents + synthesizer. Use before planning complex features."
argument-hint: "<topic or goal to research>"
---

You are launching a research swarm — multiple research agents analyzing the same topic in parallel, each through a different lens.

## Topic
$ARGUMENTS

## Research swarm

Launch ALL of these agents in a SINGLE message for maximum parallelism:

### Agent 1: learnings-researcher
"Search ops/solutions/ and ops/decisions/ for patterns relevant to: $ARGUMENTS"

### Agent 2: framework-docs-researcher
"Research current documentation, best practices, and known issues for technologies relevant to: $ARGUMENTS"

### Agent 3: git-history-analyzer
"Analyze git history for code evolution, contributors, and architectural decisions related to: $ARGUMENTS"

### Agent 4: Gemini codebase analysis (targeted)
```bash
gemini -p "$(cat ${CLAUDE_PLUGIN_ROOT}/skills/codebase-mapping/SKILL.md)

Analyze the codebase specifically for patterns, modules, and architecture related to: $ARGUMENTS

Focus on:
- Existing code that touches this area
- Dependencies and integration points
- Patterns that must be followed for consistency
- Technical debt or risks in this area

Write a targeted analysis (not full ARCHITECTURE.md — just this topic)." > /tmp/gemini_research.txt 2>&1 &
GEMINI_PID=$!

# Wait with timeout (10 min)
AGENT_TIMEOUT=600
( sleep $AGENT_TIMEOUT && kill -TERM $GEMINI_PID 2>/dev/null && sleep 5 && kill -9 $GEMINI_PID 2>/dev/null ) &
WD=$!
wait $GEMINI_PID 2>/dev/null
kill $WD 2>/dev/null; wait $WD 2>/dev/null
```

### Agent 5: best-practices-researcher
"Research industry-wide best practices, design patterns, and anti-patterns relevant to: $ARGUMENTS"

## Wait for all 5 to complete

## Synthesize

Spawn the `research-synthesizer` agent with ALL outputs:
"Merge these research findings into a unified analysis for: $ARGUMENTS"

The synthesizer produces:
- Must-know findings (changes how we plan)
- Architectural context
- Known risks and gotchas
- Conventions to follow
- Open questions
- Contradictions between sources

## Output

Present the synthesized research to the user. This output should inform `/plan` — run `/plan` next to turn research into actionable tasks.
