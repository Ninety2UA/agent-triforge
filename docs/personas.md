[← Agent Triforge](../README.md#documentation)

# Personas reference

19 personas in [`personas/`](../personas/). A persona is a prompt with no frontmatter. Its entry in [`personas/manifest.toml`](../personas/manifest.toml) sets a tool class (`read`, `read-web` or `exec`), a starting model tier and a turn budget, and `dispatch_persona` enforces all three. Each persona runs in its own context. The never-downgrade trio (`plan-checker`, `security-sentinel`, `findings-synthesizer`) always runs as top-tier Claude, whichever CLI leads.

## Core workflow (7)

| Persona | Phase | What it does |
|---|---|---|
| [`plan-checker`](../personas/plan-checker.md) | 1.5 | Validates task plans for completeness, assignments, dependencies. `persona_verdict` passes only an explicit APPROVED with no blocking issue |
| [`findings-synthesizer`](../personas/findings-synthesizer.md) | 4 | Merges review outputs with deduplication and confidence tiering. The lanes it is handed are authoritative; one that is missing, empty or short of complete coverage is a gap |
| [`integration-verifier`](../personas/integration-verifier.md) | 2 | Runs build, tests, lint between waves. `persona_verdict` passes only an explicit PASS with a matching recommendation |
| [`learnings-researcher`](../personas/learnings-researcher.md) | Pre-1 | Searches `ops/solutions/` and `ops/decisions/` for relevant patterns. Skipped while the knowledge store holds only its skeleton |
| [`team-lead`](../personas/team-lead.md) | 2 | Orchestrates agent team workers with file ownership and quality gates |
| [`research-synthesizer`](../personas/research-synthesizer.md) | 0 | Merges parallel research outputs into unified analysis |
| [`continuous-reviewer`](../personas/continuous-reviewer.md) | 2 | Per-task quality gate during team builds; reviews every completed task |

## Review specialists (6)

| Persona | Lens | What it catches |
|---|---|---|
| [`security-sentinel`](../personas/security-sentinel.md) | Security | SQL injection, XSS, auth bypass, data exposure, OWASP |
| [`performance-oracle`](../personas/performance-oracle.md) | Performance | O(n²) loops, N+1 queries, memory leaks, scalability |
| [`code-simplicity-reviewer`](../personas/code-simplicity-reviewer.md) | Complexity | Over-engineering, YAGNI violations, unnecessary abstraction |
| [`convention-enforcer`](../personas/convention-enforcer.md) | Conventions | Naming, file organization, code style consistency |
| [`architecture-strategist`](../personas/architecture-strategist.md) | Structure | SOLID principles, coupling/cohesion, module boundaries |
| [`test-gap-analyzer`](../personas/test-gap-analyzer.md) | Coverage | Untested code paths, missing edge cases, weak assertions |

## Research and verification (6)

| Persona | What it does |
|---|---|
| [`best-practices-researcher`](../personas/best-practices-researcher.md) | Industry-wide patterns, anti-patterns, tradeoff analysis |
| [`framework-docs-researcher`](../personas/framework-docs-researcher.md) | Current documentation for specific frameworks and libraries |
| [`git-history-analyzer`](../personas/git-history-analyzer.md) | Code evolution and architectural decisions via git history |
| [`bug-reproduction-validator`](../personas/bug-reproduction-validator.md) | Validates bugs are reproducible before fixes begin |
| [`deployment-verifier`](../personas/deployment-verifier.md) | Post-deployment health checks, smoke tests, error monitoring |
| [`pr-comment-resolver`](../personas/pr-comment-resolver.md) | Reads GitHub PR review comments and implements changes, as a lease builder |
