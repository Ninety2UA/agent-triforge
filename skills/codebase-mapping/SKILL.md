---
name: codebase-mapping
description: "Full-repository analysis methodology producing ARCHITECTURE.md plus MEMORY.md and CONTRACTS.md appendices: structure, data flow, patterns, interfaces, technical debt, dependencies. Use when starting work on an unfamiliar or changed codebase (Phase 0), when a plan needs module boundaries it cannot find, or when CONTRACTS.md lacks interfaces the code already has. Not for reviewing a single change; that is an architecture review."
metadata:
  triforge-consumer: "Antigravity (analyst)"
  triforge-phase: "0 (codebase analysis)"
  version: "3.3.0"
---

# Codebase Mapping

You are performing a full codebase analysis. Follow this methodology to produce comprehensive, actionable documentation.

## Step 1: Structural scan

Map the full directory tree. For each top-level module:
- Purpose (1 sentence)
- Key files and their roles
- Public interface (exports, API surface)
- Internal dependencies (what it imports from other modules)
- External dependencies (third-party packages)

## Step 2: Data flow tracing

Trace how data moves through the system:
- Entry points (API routes, CLI commands, event handlers, message consumers)
- Transformation pipeline (what processes data and in what order)
- Storage layer (databases, caches, file system, external services)
- Exit points (responses, side effects, notifications, external API calls)

## Step 3: Pattern extraction

Identify recurring patterns across the codebase:
- **Naming conventions:** variable, function, file, and directory naming patterns
- **Error handling:** how errors are created, propagated, caught, and reported
- **State management:** how state is stored, shared, and synchronized
- **Authentication/authorization:** where and how auth checks happen
- **Configuration:** how config is loaded, validated, and accessed
- **Testing patterns:** test file organization, fixture patterns, assertion styles

## Step 4: Interface inventory

Extract all undocumented interfaces:
- TypeScript interfaces/types not in CONTRACTS.md
- API endpoint shapes (request/response)
- Database model schemas
- Event/message payload shapes
- Configuration object shapes

## Step 5: Technical debt inventory

Identify inconsistencies and risks:
- **Inconsistencies:** same thing done differently in different places
- **Dead code:** unused exports, unreachable branches, deprecated paths
- **Missing error handling:** unhandled promise rejections, unchecked nulls
- **Scaling concerns:** O(n^2) algorithms, unbounded queries, missing pagination
- **Security risks:** hardcoded secrets, unvalidated inputs, missing auth checks

## Step 6: Dependency graph

Map inter-module dependencies:
- Which modules depend on which (directed graph)
- Circular dependencies (flag as critical)
- Tightly coupled modules (high change correlation)
- Loosely coupled modules (good boundaries)

## Common rationalizations

| Excuse | Reality |
|---|---|
| "The repo is large, sample the main modules" | A map with gaps sends the planner into unmapped code. Walk every top-level module and mark the ones you could not read. |
| "Rewrite CONTRACTS.md so it is consistent" | CONTRACTS.md and MEMORY.md are append-only for this skill. Discovered interfaces are appended; changes are proposed in MEMORY.md. |
| "The circular dependency is probably fine" | Flag it as critical. The planner decides whether it is fine. |
| "Skip the debt inventory, nobody asked for it" | Inconsistencies and missing error handling are inputs to shadow-path tracing. Record them. |

## Output

Produce three documents:

### ARCHITECTURE.md
- Module structure and boundaries
- Data flow diagrams (text-based)
- External integration points
- Patterns in use
- Technical debt summary

### MEMORY.md (append only)
- Patterns: reusable conventions worth preserving
- Gotchas: non-obvious behaviors, implicit assumptions
- Decisions: architectural choices evident from the code

### CONTRACTS.md (append only)
- Discovered interfaces not yet documented
- API endpoint shapes
- Database model types
