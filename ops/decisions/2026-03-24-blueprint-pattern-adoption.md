---
title: Adopt Claude Code Blueprint patterns into heterogeneous multi-model framework
date: 2026-03-24
status: accepted
---

## Context
Analyzed the Claude Code Blueprint (github.com/Ninety2UA/claude-code-blueprint) — a homogeneous Claude-only framework with 34 skills, 26 agents, 24 commands, 6 hooks. Evaluated which patterns complement our heterogeneous Claude + Gemini + Codex architecture.

## Decision
Selectively adopt 18 of 26 Blueprint agents, adapt their quality mechanisms, and extend them with portable skill injection across all three CLIs. Key adoptions:

- **Confidence tiering** (HIGH/MEDIUM/LOW) on all review findings — LOW can never be P1
- **Suppressions lists** in reviewer prompts to reduce false positives
- **Review synthesis** via findings-synthesizer agent for automated deduplication
- **Wave orchestration** with integration-verifier between waves
- **Dual-loop context management** (inner Stop hook + outer bash loop)
- **Quality gates** (5 non-negotiable checkpoints enforced via agents and skills)
- **Knowledge compounding** (ops/solutions/ and ops/decisions/ directories)
- **Portable skills** — model-agnostic markdown injected into Gemini/Codex via $(cat)

## Alternatives considered
- **Full Blueprint adoption**: Rejected — requires homogeneous Claude-only model, loses Gemini 1M context and Codex sandbox
- **No adoption**: Rejected — Blueprint has battle-tested patterns we lacked (confidence tiering, suppressions, synthesis)
- **Minimal adoption** (just suppressions + confidence): Rejected — wave orchestration, quality gates, and knowledge compounding add too much value

## Consequences
- Framework now has 18 agents, 12 skills, 16 commands, 3 hooks (up from 0/0/1/0)
- Skills are portable across all CLIs via prompt injection — a novel extension the Blueprint doesn't have
- Agent teams add a 4th coordination mode for complex builds
- Review phase now supports up to 8 parallel reviewers (2 external + 6 Claude subagents)
- Institutional knowledge compounds across sessions via learnings-researcher
