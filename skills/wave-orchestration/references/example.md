# Example

A four-wave plan for one goal, with the integration verification between waves.

## A four-wave plan

```
Goal: Build user authentication system

Wave 1 (parallel, no dependencies):
  T1: Define auth interfaces in CONTRACTS.md (Claude)
  T3: Set up JWT library configuration (Claude)

  → Integration verify: interfaces compile, config loads

Wave 2 (parallel, depends on Wave 1):
  T2a: Implement registration endpoint
  T2b: Implement login endpoint
  T2c: Implement token refresh endpoint

  → Integration verify: all endpoints compile, unit tests pass

Wave 3 (depends on Wave 2):
  T4: Integration tests (Codex)
  T5: Auth middleware (Claude)

  → Integration verify: full test suite, build clean

Wave 4 (depends on Wave 3):
  T6: Documentation (Antigravity)
  T7: Security review (Antigravity + Codex parallel)
```
