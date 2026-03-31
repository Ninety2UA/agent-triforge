---
name: test-driven-development
description: "RED-GREEN-REFACTOR test-driven development methodology. Primary consumer: Codex CLI (Phase 5), also used by Claude for feature builds."
---

# Test-Driven Development

Follow the RED-GREEN-REFACTOR cycle strictly. No production code without a failing test first.

## The iron law

> Never write production code unless a failing test demands it.

## Cycle

### RED: Write a failing test

1. Pick the smallest behavior to test next
2. Write a test that asserts the expected behavior
3. Run the test — it MUST fail
4. If it passes, the test is wrong (testing something already implemented) — rewrite it
5. The failure message should clearly describe what's missing

### GREEN: Make it pass

1. Write the MINIMUM code to make the test pass
2. Do not generalize, optimize, or clean up — just make it green
3. Run all tests — the new test must pass and no existing tests may break
4. If existing tests break, you changed too much — revert and try smaller

### REFACTOR: Clean up

1. Now improve the code: remove duplication, improve naming, simplify logic
2. Run all tests after every change — they must stay green
3. Never change behavior during refactor (tests prove this)
4. Refactoring is not optional — this is where code quality comes from

## Test design principles

- **One assertion per test** (conceptual, not literal): each test verifies one behavior
- **Descriptive names:** test name should read as a specification (`it("returns empty array when no results match filter")`)
- **Arrange-Act-Assert:** clear separation of setup, action, and verification
- **No test interdependence:** each test must run in isolation
- **Test the interface, not the implementation:** tests should survive refactoring

## Priority order for what to test

1. Happy path (normal expected behavior)
2. Edge cases (empty inputs, boundary values, single element)
3. Error cases (invalid inputs, missing data, network failures)
4. Type conformance (does the output match the contract interface?)
5. Security cases (injection, auth bypass, data exposure)

## When working with CONTRACTS.md

- All test fixtures MUST conform to types defined in CONTRACTS.md
- If a test requires a type change, do not modify CONTRACTS.md — propose the change in MEMORY.md
- Import types from CONTRACTS.md (or the source they define) in test files

## Output

After each TDD cycle, produce:
- Test file(s) created/modified with test count
- Production code created/modified
- Test results (all passing, coverage %)
- Any proposed CONTRACTS.md changes (written to MEMORY.md, not CONTRACTS.md directly)

## Coverage targets

- New code: aim for >90% line coverage
- Changed code: maintain or improve existing coverage
- Critical paths (auth, payments, data mutations): 100% branch coverage
