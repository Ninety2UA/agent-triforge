# Common rationalizations

Read it when you notice a Red Flag and are about to argue your way past the gate.

## Excuse and reality

| Excuse | Reality |
|---|---|
| "It worked before the refactor" | The refactor is the change under test. Only a run after it proves anything. |
| "Tests are slow" | A slow run is shorter than the fix cycle a false Done triggers. Run the suite, or state that it was not run. |
| "The diff is obvious" | Obvious diffs ship typos, wrong paths, and inverted conditions. The gate takes one command. |
| "The builder said all tests pass" | A self-report is a claim, not evidence. Read the diff and quote a run you performed. |
| "I ran it a minute ago" | If an edit happened since, the run is stale. Run it again. |
| "There is no test command for this" | There is always a smoke run, a grep, a parser, or a manual reproduction. Pick one and record it. |
| "CI will catch it" | CI is a second gate, not a replacement for the first. A red CI after a Done still costs a full cycle. |
| "It is only documentation" | Documentation that names a wrong flag breaks the next agent that follows it. Execute what it documents. |
| "The linter passed, so the code is right" | Lint proves style, not behavior. Each claim needs its own proof. |
| "I will verify after I mark it Done" | Done is the claim. Verification comes before the claim by definition. |
