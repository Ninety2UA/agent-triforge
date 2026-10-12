# Step 7: commit with decision context (git trailers)

When creating commits for this sprint's work, append structured trailers to capture decision context that would otherwise be lost:

```
Constraint: <what forced this approach — e.g., "API rate limit requires batch processing">
Rejected: <alternative considered and why — e.g., "WebSocket: too complex for current infra">
Confidence: <high|medium|low — how certain are you this is the right approach>
Scope-risk: <what could break outside the changed files>
Not-tested: <what wasn't covered — e.g., "edge case: concurrent writes">
```

Rules:

- Include at least `Constraint` and `Confidence` on every non-trivial commit.
- `Rejected` only when a meaningful alternative was considered.
- `Not-tested` only when known gaps exist.
- Trailers go after the commit body, separated by a blank line.
