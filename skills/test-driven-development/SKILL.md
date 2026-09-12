---
name: test-driven-development
description: "RED-GREEN-REFACTOR discipline: a failing test before any production code, and a characterization test before any change to untested legacy code. Use when adding or changing behavior, writing a regression test for a bug, or refactoring code that has no tests. Not for deciding what a whole system lacks coverage for; that is gap analysis. Companion: writing-good-tests.md."
metadata:
  triforge-consumer: "Codex (tester), Claude (builder)"
  triforge-phase: "5 (test); 2 (build)"
  version: "3.3.0"
---

# Test-Driven Development

Follow the RED-GREEN-REFACTOR cycle strictly. No production code without a failing test first. What makes a test worth writing is in [writing-good-tests.md](writing-good-tests.md); read it before writing the first assertion.

## The iron law

> Never write production code unless a failing test demands it.

## Which branch you are on

Decide before writing anything:

- **New or changed behavior** → the RED-GREEN-REFACTOR cycle below. The test for the new or changed behavior must fail first.
- **Behavior must not change** (refactor, cleanup, migration of legacy code with no tests) → the characterization guard below. Capture current behavior first, watch the capture pass, then change.
- **Bug fix** → both, in order: a characterization test for the surrounding behavior that must survive, then a RED test that reproduces the bug (the systematic-debugging skill supplies the reproduction).

## Cycle

### RED: Write a failing test

1. Pick the smallest behavior to test next
2. Write a test that asserts the expected behavior
3. Run the test — it MUST fail
4. If a test for new or changed behavior passes immediately, it is not testing the change: either the behavior already exists (delete the test, or switch to the characterization guard) or the assertion is too weak. Rewrite it until it fails for the right reason
5. The failure message should clearly describe what is missing

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

## Characterization guard (legacy code with no tests)

When changing legacy code that has no tests, first capture current behavior with a characterization test, watch it pass, then change:

1. **Name the mutation.** State the one behavior your change must preserve as "if I broke X, this test would fail because Y".
2. **Write the characterization test** against the current code. It asserts what the code does today, not what it should do. Run it and watch it pass.
3. **Prove it can fail.** Temporarily break the behavior it captures (invert a condition, return early). Run the test and watch it fail with a message that names the behavior. If it still passes, the test proves nothing; rewrite it.
4. **Restore the original code** with the VCS (`git restore --source=HEAD --worktree -- <paths>`) and confirm the diff is empty apart from the new test.
5. **Now change.** Refactor with the characterization test green after every step. When done, decide per test whether it stays (it documents intended behavior) or is replaced by a spec-shaped test.

A characterization test that captures a bug is still correct for this step; fix the bug afterwards on the RED-GREEN branch so the two changes are separable in the diff.

## Test design principles

The full rules are in [writing-good-tests.md](writing-good-tests.md). The short form:

- **One behavior per test:** each test proves one thing and its name says which
- **Descriptive names:** the test name reads as a specification (`it("returns empty array when no results match filter")`)
- **Arrange-Act-Assert:** clear separation of setup, action, and verification
- **No test interdependence:** each test must run in isolation and in any order
- **Test the interface, not the implementation:** tests should survive refactoring
- **Exercise the real thing:** a test whose every dependency is mocked proves nothing about integration

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

## Red Flags

Stop and re-read the branch rules when:

- A test for new or changed behavior passes the first time it runs.
- You wrote production code and the test that demands it does not exist yet.
- You are about to refactor a file no test touches and no characterization test has been written.
- The test asserts the code's own output back at itself, or greps the source for a string.
- The test needs every collaborator mocked before it can run.
- You cannot say which change to the code would make the test fail.
- "Run all tests" was skipped because only one file changed.

## Common rationalizations

| Excuse | Reality |
|---|---|
| "I will write the tests after the code" | Tests written after pass by construction and prove only that the code does what it does. The failing test is the specification. |
| "This code has no tests, so TDD does not apply" | It applies through the characterization guard: capture, prove the capture can fail, then change. |
| "The change is too small to need a test" | Small changes are where inverted conditions hide. One test, one run. |
| "The test passed immediately, so the code already works" | Or the test does not exercise the change. Break the code and see whether the test notices. |
| "Mocking everything makes the test fast" | A test whose every dependency is mocked proves nothing about integration. Mock at the boundary you do not own and run the real thing inside it. |
| "I ran the new test; the old ones are unrelated" | The old tests are the regression guard. Run the full suite before claiming green. |
| "Refactoring does not change behavior, so no test is needed" | That is the claim under test. Characterization tests are how the claim is checked. |

## Output

After each TDD cycle, produce:
- Test file(s) created/modified with test count
- Production code created/modified
- Test results (all passing, coverage %)
- For the characterization branch: the characterization test, the failure observed when the behavior was broken, and the empty diff after restore
- Any proposed CONTRACTS.md changes (written to MEMORY.md, not CONTRACTS.md directly)

## Coverage targets

- New code: aim for >90% line coverage
- Changed code: maintain or improve existing coverage
- Critical paths (auth, payments, data mutations): 100% branch coverage
