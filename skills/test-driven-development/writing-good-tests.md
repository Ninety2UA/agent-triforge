# Writing good tests

Companion to the test-driven-development skill ([SKILL.md](SKILL.md)). A test earns its place when it proves something that would otherwise be a guess. This file says what that proof looks like and when a test is the wrong instrument.

## What a good test proves

A good test has a name for the break: you can state which change to the production code would make it fail, and why. "If the discount were applied twice, this fails because the total is 90 instead of 95." If you cannot name the break, the test is a change detector (it fails whenever anything changes) or a mirror (it restates the code's output back at the code), and neither proves behavior.

Three properties follow:

1. **It fails for one reason.** When it goes red, the message points at the behavior that broke, not at a fixture or a mock setup.
2. **It survives refactoring.** It exercises the interface a caller sees, so renaming a private helper does not touch it.
3. **It can be run first.** It was red before the code existed (new behavior) or was proven able to go red by breaking the code (characterization).

## One behavior per test

Each test proves one thing. "One assertion" is the conceptual rule, not a literal count: several `expect` lines that together describe one outcome (status, body, and header of one response) are one behavior. Two behaviors in one test hide which one broke and let the first failure mask the second.

Split when the setup diverges, when the name needs "and", or when a failure message would not say which behavior failed.

## The name reads as a spec

The test name is the sentence a reader would put in the documentation: `returns 409 when the email already exists`, `retries once on connection timeout then returns 503`. A name like `test_create_user_2` or `works correctly` cannot be read as a specification and cannot be checked against the plan's `Accept:` line.

Name from the caller's point of view, in the present tense, with the condition in the name.

## Arrange, act, assert

Keep the three sections visibly separate: build the inputs, perform one action, check the outcome. Assertions inside the arrange step (checking that a fixture loaded) belong in a fixture test, not here. An act step that performs two actions is two tests.

## No interdependence

Every test runs alone and in any order. It creates what it needs and leaves nothing behind: no shared mutable module state, no reliance on a test that ran earlier, no files outside a per-test temporary directory. A suite that passes only in one order has a polluter; find it by bisecting the order, not by pinning it.

## Exercise the real thing

A test whose every dependency is mocked proves nothing about integration: it proves the code calls the mocks the way the test author expected, which is the same assumption the code was written under. Mock at the boundary you do not own (the network, a third-party service, the clock) and run the real thing inside that boundary: the real parser, the real query builder, the real filesystem in a temporary directory.

Warning signs of over-mocking:

- The mock setup is longer than the test body.
- The test asserts that a function was called, not what happened as a result.
- Changing an internal call signature breaks tests but no behavior changed.
- The mocked return value is the value the assertion checks.

For a shell helper, the real thing is a process: run the helper, assert its exit code and output. A grep of the helper's source for a string is a mirror, not a test.

## Characterization tests

When code has no tests and you must change it, write a test that asserts what the code does today, bugs included. Its purpose is to make the change observable, not to specify correct behavior. Follow the guard in [SKILL.md](SKILL.md): capture, prove the capture can fail, restore to an empty diff, then change.

After the change, either keep the characterization test (renamed to read as a spec, once you have confirmed the behavior is intended) or replace it with a spec-shaped test. Do not leave a test named after the capture ("current behavior of X") in the suite; the next reader cannot tell whether it documents a feature or a bug.

## The mutation check

Before trusting any test, break the code it guards and run it. If it still passes, it proves nothing about that behavior. The check takes one edit and one run and catches mirrors, change detectors, over-mocked tests, and tests that assert on the wrong object. Do it for every characterization test and for any test that passed on the first run.

## Warning signs

- The test passed the first time it ran and nobody broke the code to see it fail.
- The expected value in the assertion was copied from the code's output.
- The test checks that a string appears in a source file.
- The test's failure message would be "expected true, got false".
- Deleting the production code under test leaves the suite green.
- The test reads a fixture and asserts the fixture.

## When a test is not the right proof

Some claims are not proven by a unit test, and writing one anyway gives false confidence:

| Claim | Right proof |
|---|---|
| A documented command works | Run the command as written and quote its output (smoke run) |
| A config file loads | Feed it to its real parser and quote the result |
| A migration is applied | Query the schema afterwards; try the rollback on a scratch copy |
| A name or flag exists in the source | Grep it and quote the hit |
| Something is faster | A measurement under the same conditions, before and after |
| A refactor preserves behavior | The pre-refactor tests unchanged and green, plus a VCS diff that shows only intended changes |

The verification-before-completion skill defines how each of these is recorded. A test that cannot name its break, or that would need to mock the thing being proven, is a signal to switch to one of these instead.
