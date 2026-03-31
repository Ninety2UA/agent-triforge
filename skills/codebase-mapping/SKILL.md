---
name: codebase-mapping
description: "Systematic methodology for analyzing an entire codebase and producing structured architecture documentation. Primary consumer: Gemini CLI (Phase 0)."
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

## Output format

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
