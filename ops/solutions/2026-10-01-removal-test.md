---
problem: "Three shipped skills (test-driven-development, systematic-debugging, verification-before-completion) teach practice a current model may already follow unaided; R18 prunes generic skills only after a removal test"
context: "v4 lead-choice plan, Phase 0, unit U4. One fixture task (two-file bug fix plus a regression test), a Claude lead (claude -p, sonnet), two arms: all 12 skills visible, and the three candidates removed. Three series of five interleaved runs per arm: the original allowlist, a corrected allowlist, and the corrected allowlist with python and pytest on PATH"
solution: "30 runs. The without-arm passed 15 of 15, the all-arm 14 of 15; the without-arm used fewer tokens in every series (ratios 0.986, 0.912, 0.861; pooled 0.928). No run invoked any skill. The rule allows removal in each series and pooled. test-driven-development and systematic-debugging are removed; verification-before-completion is kept by a scope decision (Triforge-specific content, split by U24)"
date: 2026-10-01
agent: "Claude Code worker (Fable 5.1) ran the experiment; fixture lead was claude -p --model sonnet (resolved claude-sonnet-5-5, Claude Code 2.1.284)"
sprint_id: v4.0.0-lead-choice-phase-0
task_id: U4
evidence_files: [skills/test-driven-development/SKILL.md, skills/test-driven-development/writing-good-tests.md, skills/systematic-debugging/SKILL.md, skills/verification-before-completion/SKILL.md, docs/plans/2026-09-28-1946-feat-lead-choice-v4-plan.md]
related_decisions: ["plan Key Decision 'Context audit first; must-hold rules enforced by scripts, hooks or permissions' (governs R18)"]
---

## Question

Does a Claude lead need `test-driven-development`, `systematic-debugging` and
`verification-before-completion` to fix a bug and add a regression test? R18 says a
generic skill is pruned only after a removal test, and U4 sets the rule: remove a skill
only where the without-arm passes at least as often and uses no more than 10% more
tokens.

The three candidates were removed together in the without-arm, so the measured verdict is
for the set, not for each skill separately. The scope of the pruning was then narrowed by
the orchestrator; see "Scope decision".

## Fixture

A throwaway Python repo (standard library only, `python3 -m unittest`), about 45 lines
of source in two modules, with a README that states the pricing rules. The run artifacts
are in a scratch directory (`$TMPDIR/triforge-removal-test/`) that will not outlive the
machine's temp cleanup, so the parts that matter are reproduced here.

The bug spans two files, and neither fix alone makes the visible tests pass:

```python
# shop/money.py — contract: an exact half cent rounds up
def percent_of(amount_cents, percent):
    return round(amount_cents * percent / 100)      # round() rounds halves to even: 4.5 -> 4

# shop/cart.py — contract: the discount is a percentage of the line subtotal
def line_total(line, discount_percent=0):
    discount_per_unit = percent_of(line.unit_cents, discount_percent)
    return (line.unit_cents - discount_per_unit) * line.quantity   # per unit, then multiplied
```

The visible tests (10, in `tests/test_money.py` and `tests/test_cart.py`) fail in two
places, both from the same case: three pens at 15 cents with a 10% discount must cost 40
and cost 39. The existing `percent_of` tests pass on the broken code because they only
use halves that round the same way under both rules (1.5 and 7.5), so `money.py` looks
healthy. Fixing only `cart.py` gives 41; fixing only `money.py` gives 39. I checked both
single-file fixes and the two-file fix against the visible and hidden tests before the
first run.

Task prompt, verbatim, identical in every run of every series:

> Tests fail in this repo. Find and fix the bug (it spans two files) and add a regression test that would have caught it. Run the tests before you finish.

Hidden acceptance test: a file kept outside the fixture and copied in only after the
session ended. It has 7 test methods covering inputs the visible tests do not: 14
half-cent cases for `percent_of` (2.5, 0.5, 4.5, 6.5, 8.5 and others, including one
nine-digit amount), 11 further `percent_of` cases, an integer-return check, 10
`line_total` cases (among them two where a per-unit discount gives a different answer
with no half cent involved, quantity 0, and a 100% discount), and a three-line order. On
the unfixed fixture it fails 17 assertions. It would catch a fix that special-cases the
visible input or edits a visible test's expected value.

## Arms and how visibility was checked

- **ALL:** the fixture's `.claude/skills/` holds all 12 directories of the repo's
  `skills/` (copied at HEAD f08e64f; `skills/` is unchanged since 2a2011d).
- **WITHOUT:** the same, minus the three candidates (9 directories).

Each run got a fresh copy of its arm's fixture with `git init` and one commit, then (the
series 1 command; series 2 and 3 change only what their sections say):

```
timeout 900 claude -p --model sonnet --output-format stream-json --verbose \
  --no-session-persistence --setting-sources project --strict-mcp-config \
  --permission-mode acceptEdits \
  --allowedTools "Read" "Edit" "Write" "Grep" "Glob" "Skill" "Bash(python3:*)" \
    "Bash(ls:*)" "Bash(cat:*)" "Bash(git diff:*)" "Bash(git status:*)" \
  -- "<task prompt>" < /dev/null
```

Visibility was checked once per arm in a fixture copy with the same flags and the prompt
"List the names of the skills available to you, one per line, nothing else". Two sources
agree for each arm: the `skills` list in the session's `init` event, and the model's
answer.

- ALL, `init` event: the 12 Triforge skills, then Claude Code's built-ins (`deep-research`,
  `design`, `design-sync`, `dataviz`, `update-config`, `verify`, `debug`, `code-review`,
  `simplify`, `batch`, `fewer-permission-prompts`, `doctor`, `loop`, `schedule`,
  `claude-api`, `workflow-authoring`, `run`, `run-skill-generator`). The model's answer
  listed all 12 Triforge names.
- WITHOUT, `init` event: the 9 remaining Triforge skills and the same built-ins. The model's
  answer listed those 9 and none of the three candidates.

The first request of the probe was 19,264 prompt tokens in ALL and 18,845 in WITHOUT. The
three skill descriptions therefore cost about 420 tokens on every request, whether or not
a skill is used. The skill bodies (28,838 bytes across the three directories) are loaded
only when a skill is invoked.

## Pass criteria and what each table records

Checked by script after the session ended, never from the model's own claim:

- **(a)** `python3 -m unittest` exits 0 in the run's copy.
- **(b)** the hidden acceptance test, copied in after the run, passes.
- **(c)** the diff against the fixture commit adds a `def test_` or an assertion in a file
  under `tests/`.

A run passes when all three hold.

In every series the order of execution was ALL 1, WITHOUT 1, ALL 2, WITHOUT 2, and so on.
Tokens come from the `usage` object of the session's `result` event. Total = input +
output + cache write + cache read. "Turns" is the event's `num_turns`; "Requests" is the
number of model requests, counted from the distinct assistant message ids in the event
stream. "Denied calls" counts tool calls the permission allowlist refused. Skill use was
read from the tool calls in each run's event stream. "Reproduced before editing" is yes
when the session ran the test suite and got failing output back before its first change
to a file.

All 30 runs ended with `is_error: false`, `subtype: success` and `stop_reason: end_turn`.
No run was discarded or repeated in any series.

## Series 1 (original allowlist)

| Arm | Run | (a) suite | (b) hidden | (c) test added | Turns | Requests | Input | Output | Cache write | Cache read | Total tokens | Duration (s) | Cost (USD) | Denied calls | Tests added | Candidate skills invoked |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ALL | 1 | pass | pass | pass | 14 | 7 | 14 | 2,411 | 12,018 | 140,264 | 154,707 | 18.5 | 0.1003 | 3 | 3 | none |
| WITHOUT | 1 | pass | pass | pass | 14 | 7 | 14 | 2,489 | 11,568 | 137,361 | 151,432 | 24.8 | 0.0987 | 3 | 2 | n/a (not present) |
| ALL | 2 | pass | pass | pass | 9 | 6 | 12 | 1,924 | 11,458 | 112,449 | 125,843 | 15.6 | 0.0876 | 2 | 2 | none |
| WITHOUT | 2 | pass | pass | pass | 14 | 7 | 14 | 2,421 | 11,501 | 137,206 | 151,142 | 18.9 | 0.0977 | 3 | 2 | n/a (not present) |
| ALL | 3 | pass | pass | pass | 15 | 7 | 14 | 2,560 | 12,619 | 136,462 | 151,655 | 19.8 | 0.1034 | 4 | 1 | none |
| WITHOUT | 3 | pass | pass | pass | 15 | 8 | 16 | 2,582 | 12,172 | 156,080 | 170,850 | 20.0 | 0.1058 | 4 | 1 | n/a (not present) |
| ALL | 4 | pass | pass | pass | 14 | 8 | 16 | 3,068 | 13,613 | 165,879 | 182,576 | 22.3 | 0.1183 | 3 | 2 | none |
| WITHOUT | 4 | pass | pass | pass | 15 | 8 | 16 | 3,083 | 12,724 | 162,752 | 178,575 | 21.4 | 0.1143 | 4 | 2 | n/a (not present) |
| ALL | 5 | pass | pass | pass | 15 | 9 | 18 | 2,257 | 12,401 | 185,156 | 199,832 | 21.5 | 0.1092 | 4 | 2 | none |
| WITHOUT | 5 | pass | pass | pass | 14 | 7 | 14 | 2,392 | 11,466 | 137,214 | 151,086 | 18.7 | 0.0973 | 3 | 2 | n/a (not present) |

No run in either arm made a `Skill` tool call of any kind (not for the candidates, not for
the other nine Triforge skills, not for the built-in `debug` or `verify`), and no run
read a file under `.claude/skills/`. Reproduced before editing: 0 of 10 (see below).

| Series 1 means | ALL (n=5) | WITHOUT (n=5) | WITHOUT / ALL |
|---|---|---|---|
| Runs passing (a), (b) and (c) | 5 of 5 | 5 of 5 | equal |
| Reproduced before editing | 0 of 5 | 0 of 5 | |
| Turns | 13.4 | 14.4 | 1.07 |
| Requests | 7.4 | 7.4 | 1.00 |
| Input tokens | 14.8 | 14.8 | 1.00 |
| Output tokens | 2,444 | 2,593 | 1.061 |
| Cache-write tokens | 12,422 | 11,886 | 0.957 |
| Cache-read tokens | 148,042 | 146,123 | 0.987 |
| **Total tokens** | **162,923** | **160,617** | **0.986** |
| Total tokens, range | 125,843 to 199,832 | 151,086 to 178,575 | |
| Total tokens, median | 154,707 | 151,432 | 0.979 |
| Duration (s) | 19.5 | 20.8 | 1.06 |
| Cost (USD) | 0.104 | 0.103 | 0.99 |
| Denied calls | 3.2 | 3.4 | |

After the first three runs per arm the means were 144,068 (ALL) and 157,808 (WITHOUT), a
ratio of 1.095 with overlapping ranges. That is inside the rule but too close to it to
call, so two more runs per arm were added.

What went wrong in series 1: the allowlist permits `python3`, but the model's first
choice was `python -m pytest`, `python -m unittest`, or a compound command containing
`npm test`, all refused (2 to 4 refusals per run). In all ten runs the attempt to run the
tests before the fix was among the refused calls, so no session saw the failing output.
Each found the bug by reading the code and ran the suite once, after the fix, with
`python3 -m unittest`, where it passed.

## Series 2 (corrected allowlist)

Same fixture, arms, model, flags and prompt. The only change is the Bash allowlist, widened
so the model's first-choice commands are permitted:

```
--allowedTools "Read" "Edit" "Write" "Grep" "Glob" "Skill" "Bash(python:*)" "Bash(python3:*)" \
  "Bash(git ls-files:*)" "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)" \
  "Bash(ls:*)" "Bash(cat:*)" "Bash(head:*)" "Bash(tail:*)"
```

A probe session, asked to run the commands series 1 had refused, ran all of them with no
refusal.

| Arm | Run | (a) suite | (b) hidden | (c) test added | Reproduced before editing | Turns | Requests | Input | Output | Cache write | Cache read | Total tokens | Duration (s) | Cost (USD) | Denied calls | Tests added | Any skill invoked |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ALL | 1 | pass | pass | pass | no | 5 | 5 | 10 | 1,604 | 10,726 | 91,597 | 103,937 | 13.2 | 0.0773 | 1 | 3 | none |
| WITHOUT | 1 | pass | pass | pass | no | 5 | 5 | 10 | 1,525 | 10,090 | 89,404 | 101,029 | 17.2 | 0.0735 | 1 | 2 | none |
| ALL | 2 | pass | pass | pass | no | 5 | 5 | 10 | 1,698 | 10,744 | 91,622 | 104,074 | 13.9 | 0.0783 | 1 | 2 | none |
| WITHOUT | 2 | pass | pass | pass | no | 6 | 6 | 12 | 1,752 | 9,861 | 110,993 | 122,618 | 15.9 | 0.0792 | 1 | 2 | none |
| ALL | 3 | pass | pass | pass | no | 10 | 6 | 12 | 2,601 | 12,111 | 114,092 | 128,816 | 19.1 | 0.0973 | 2 | 2 | none |
| WITHOUT | 3 | pass | pass | pass | no | 4 | 4 | 8 | 1,342 | 9,883 | 70,518 | 81,751 | 11.3 | 0.0671 | 0 | 2 | none |
| ALL | 4 | pass | pass | pass | no | 6 | 6 | 12 | 1,509 | 10,630 | 112,884 | 125,035 | 13.3 | 0.0802 | 1 | 2 | none |
| WITHOUT | 4 | pass | pass | pass | no | 9 | 8 | 16 | 2,412 | 11,226 | 155,361 | 169,015 | 20.4 | 0.1001 | 2 | 1 | none |
| ALL | 5 | pass | pass | **FAIL** | no | 7 | 7 | 14 | 1,914 | 10,635 | 135,549 | 148,112 | 19.4 | 0.0888 | 2 | 0 | none |
| WITHOUT | 5 | pass | pass | pass | no | 4 | 4 | 8 | 1,532 | 9,783 | 70,751 | 82,074 | 14.9 | 0.0686 | 0 | 2 | none |

| Series 2 means | ALL (n=5) | WITHOUT (n=5) | WITHOUT / ALL |
|---|---|---|---|
| Runs passing (a), (b) and (c) | 4 of 5 | 5 of 5 | WITHOUT higher |
| Reproduced before editing | 0 of 5 | 0 of 5 | |
| Turns | 6.6 | 5.6 | 0.85 |
| Requests | 5.8 | 5.4 | 0.93 |
| Input tokens | 11.6 | 10.8 | 0.93 |
| Output tokens | 1,865 | 1,713 | 0.918 |
| Cache-write tokens | 10,969 | 10,169 | 0.927 |
| Cache-read tokens | 109,149 | 99,405 | 0.911 |
| **Total tokens** | **121,995** | **111,297** | **0.912** |
| Total tokens, range | 103,937 to 148,112 | 81,751 to 169,015 | |
| Total tokens, median | 125,035 | 101,029 | 0.808 |
| Duration (s) | 15.8 | 16.0 | 1.01 |
| Cost (USD) | 0.084 | 0.078 | 0.92 |
| Denied calls | 1.4 | 0.8 | |

Three things happened in series 2.

1. **Still no session reproduced the failure first (0 of 10).** The allowlist no longer
   refused `python -m pytest -q`, but the host has no `python` binary and no pytest
   module, so the command printed `command not found: python`. The same command had also
   printed the source files with `cat`. In all ten runs the model went straight from that
   output to the fix, without retrying the suite under `python3`, and ran the suite with
   `python3 -m unittest` only afterwards. The corrected allowlist removed the permission barrier and
   exposed a host barrier behind it. Series 3 removes that one.
2. **The sessions got shorter.** With fewer refusals (means 1.4 and 0.8, down from 3.2 and
   3.4) and edits often done in one `python3` script, a run took 4 to 8 requests instead of
   6 to 9, and mean total tokens fell by 25% in ALL and 31% in WITHOUT.
3. **ALL 5 failed criterion (c), and its final message was wrong.** The session put its
   test edits and a check into one command: a `python3` script that added two test methods
   (three assertions), then `git stash` of the fix, a test run, and `git stash pop`, to
   confirm the new tests fail without the fix. `git stash` is not on the allowlist, so the whole command was
   refused, test edits included. The session then ran the suite, which reported 10 tests
   (the fixture's original count), and ended with a message saying it had added three
   regression tests. It had added none; the diff touches only `shop/cart.py` and
   `shop/money.py`. The fix itself was correct, so (a) and (b) pass. The remaining refusals
   in this series were the opening compound command containing `npm test` (8 runs) and
   `sed -i` (2 runs).

## Series 3 (corrected allowlist, with `python` and pytest on PATH)

Series 2 was asked for so that the model's first-choice test command would work before the
fix. It did not, for the host reason above, so I ran one more series. This goes beyond the
five runs per arm that were requested for the corrected series; it is reported separately
so it can be set aside.

The only change from series 2: a virtual environment in the scratch directory (Python
3.14, pytest 9.1.1) was put first on `PATH` for the `claude` process, so `python` and
`python -m pytest` exist. The allowlist is the series 2 allowlist. A probe session ran
`python -m pytest -q` and got `2 failed, 8 passed`. The scripted checks (a) and (b) still
ran under the system `python3`.

| Arm | Run | (a) suite | (b) hidden | (c) test added | Reproduced before editing | Turns | Requests | Input | Output | Cache write | Cache read | Total tokens | Duration (s) | Cost (USD) | Denied calls | Tests added | Any skill invoked |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ALL | 1 | pass | pass | pass | yes | 6 | 6 | 12 | 1,696 | 11,259 | 113,500 | 126,467 | 17.1 | 0.0847 | 1 | 2 | none |
| WITHOUT | 1 | pass | pass | pass | yes | 5 | 5 | 10 | 1,644 | 10,224 | 90,220 | 102,098 | 14.6 | 0.0754 | 1 | 2 | none |
| ALL | 2 | pass | pass | pass | yes | 4 | 4 | 8 | 1,549 | 10,140 | 72,565 | 84,262 | 13.0 | 0.0706 | 0 | 2 | none |
| WITHOUT | 2 | pass | pass | pass | yes | 5 | 5 | 10 | 1,465 | 10,248 | 93,138 | 104,861 | 12.9 | 0.0743 | 0 | 1 | none |
| ALL | 3 | pass | pass | pass | yes | 5 | 5 | 10 | 1,572 | 11,084 | 93,878 | 106,544 | 14.5 | 0.0789 | 0 | 2 | none |
| WITHOUT | 3 | pass | pass | pass | yes | 4 | 4 | 8 | 1,503 | 10,052 | 71,009 | 82,572 | 12.6 | 0.0695 | 0 | 2 | none |
| ALL | 4 | pass | pass | pass | yes | 9 | 6 | 12 | 2,141 | 12,023 | 114,812 | 128,988 | 17.1 | 0.0925 | 1 | 2 | none |
| WITHOUT | 4 | pass | pass | pass | yes | 4 | 4 | 8 | 1,663 | 10,146 | 71,003 | 82,820 | 13.9 | 0.0714 | 0 | 2 | none |
| ALL | 5 | pass | pass | pass | yes | 5 | 5 | 10 | 1,509 | 10,654 | 92,062 | 104,235 | 17.6 | 0.0761 | 1 | 2 | none |
| WITHOUT | 5 | pass | pass | pass | yes | 5 | 5 | 10 | 1,662 | 10,109 | 90,117 | 101,898 | 17.6 | 0.0751 | 1 | 2 | none |

| Series 3 means | ALL (n=5) | WITHOUT (n=5) | WITHOUT / ALL |
|---|---|---|---|
| Runs passing (a), (b) and (c) | 5 of 5 | 5 of 5 | equal |
| Reproduced before editing | 5 of 5 | 5 of 5 | |
| Turns | 5.8 | 4.6 | 0.79 |
| Requests | 5.2 | 4.6 | 0.88 |
| Input tokens | 10.4 | 9.2 | 0.88 |
| Output tokens | 1,693 | 1,587 | 0.937 |
| Cache-write tokens | 11,032 | 10,156 | 0.921 |
| Cache-read tokens | 97,363 | 83,097 | 0.853 |
| **Total tokens** | **110,099** | **94,850** | **0.861** |
| Total tokens, range | 84,262 to 128,988 | 82,572 to 104,861 | |
| Total tokens, median | 106,544 | 101,898 | 0.956 |
| Duration (s) | 15.9 | 14.3 | 0.90 |
| Cost (USD) | 0.081 | 0.073 | 0.91 |
| Denied calls | 0.6 | 0.4 | |

In all ten runs the session ran `python -m pytest -q` before its first edit, saw the two
failing tests, and then fixed both files. No session opened a skill, in either
arm. The five refusals in this series were all the opening compound command containing
`npm test`.

## All series and pooled

| | ALL passes | WITHOUT passes | ALL mean total | WITHOUT mean total | WITHOUT / ALL | Reproduced first | Skill invoked |
|---|---|---|---|---|---|---|---|
| Series 1 | 5 of 5 | 5 of 5 | 162,923 | 160,617 | 0.986 | 0 of 10 | 0 of 10 |
| Series 2 | 4 of 5 | 5 of 5 | 121,995 | 111,297 | 0.912 | 0 of 10 | 0 of 10 |
| Series 3 | 5 of 5 | 5 of 5 | 110,099 | 94,850 | 0.861 | 10 of 10 | 0 of 10 |
| Series 1 + 2 pooled | 9 of 10 | 10 of 10 | 142,459 | 135,957 | 0.954 | 0 of 20 | 0 of 20 |
| All three pooled | 14 of 15 | 15 of 15 | 131,672 | 122,255 | 0.928 | 10 of 30 | 0 of 30 |

Output tokens alone, WITHOUT / ALL: 1.061 (series 1), 0.918 (series 2), 0.937 (series 3),
0.999 (series 1 + 2), 0.982 (all three).

Pooling mixes three allowlist conditions, but each series has the same number of runs in
each arm, run alternately, so the conditions weigh equally on both arms.

## Decision rule and verdict

Rule: remove only if WITHOUT passes at least as often as ALL, and WITHOUT's mean total
tokens are at most 1.10 times ALL's.

| Applied to | Passes: WITHOUT at least as often? | Tokens: ratio at most 1.10? | Rule allows removal |
|---|---|---|---|
| Series 1 alone | yes, 5 = 5 | yes, 0.986 | yes |
| Series 2 alone | yes, 5 > 4 | yes, 0.912 | yes |
| Series 1 + 2 pooled | yes, 10 > 9 | yes, 0.954 | yes |
| Series 3 alone | yes, 5 = 5 | yes, 0.861 | yes |
| All three pooled | yes, 15 > 14 | yes, 0.928 | yes |

Series 2 does not contradict series 1 under the rule, and neither does series 3.

**Verdict: `test-driven-development` and `systematic-debugging` are removed.
`verification-before-completion` is kept.**

### Scope decision

The orchestrator decided the scope after series 1, and it is recorded here as taken:

- **`verification-before-completion` is kept.** R18 keeps skills specific to Triforge, and
  this one carries Triforge-specific content the fixture cannot reach: the completion
  signal (mark the task Done in `ops/TASKS.md`), the `ops/.sprint-complete` sentinel, and
  the checklist named by `scripts/coordinate.sh` and by the ship, coordinate and wrap
  workflows. U24 splits it.
- **`test-driven-development` and `systematic-debugging` are the removal candidates**,
  removed only if series 2 does not contradict series 1 under the rule. It does not.

The measured without-arm removed all three skills, so the configuration that will ship
(two removed, `verification-before-completion` present) was not run as its own arm. It
sits between the two measured arms. It differs from WITHOUT by one skill description on
each request, for a skill that no ALL-arm session opened in 15 runs.

### What the numbers do and do not show

- The arms did not differ in behavior. In the ALL arm the model had the three skills on
  offer, with a task that matches two of their "Use when" lines ("a test fails", "writing
  a regression test for a bug"), and did not open any of them in 15 runs. That held when
  the session worked from reading alone (series 1 and 2) and when it worked from a failing
  test run (series 3).
- The token differences between the arms are run-to-run variation, not a skill effect.
  Total tokens follow the number of requests in a session. In series 1, 6 requests cost
  126k tokens, 7 cost 151k to 155k, 8 cost 171k to 183k and 9 cost 200k, and both arms
  averaged 7.4 requests. In series 2 and 3 the ALL arm happened to average 0.4 and 0.6 more
  requests. The only systematic cost of the candidates is the 420 tokens their three
  descriptions add to each request, 2,000 to 3,100 tokens per run.
- The one failed run was in the ALL arm (series 2, ALL 5). Its cause was a refused
  command, not the presence of the skills, so it is not evidence that the skills hurt. It
  is evidence that having `verification-before-completion` available did not stop a
  session from claiming three tests it had not added: the skill was on offer and was not
  opened. A completion rule that must hold needs a script or hook behind it, which is what
  the plan's Key Decision for R18 says.
- A forced-use arm (the prompt telling the model to follow the skills) was not run. It
  could not change the verdict under this rule: WITHOUT passes every run, so forced use
  could at best tie on passes while loading up to 28,838 bytes of skill text.

## Limits of the evidence

- One fixture, and an easy one: about 45 lines of source, a README that states the rules,
  a bug findable by reading. It says nothing about long debugging sessions, flaky failures
  or a legacy codebase with no tests, which is where the skills' circuit breaker and
  characterization-test sections would apply.
- One model tier, sonnet. It was chosen because a weaker tier that needs no skill implies
  the stronger tiers (`opus`, `fable`) need none. That inference does not extend to the
  other CLIs that read `.agents/skills/` (Codex, Antigravity, OpenCode, Kimi, Cursor); none
  of them was tested, and `test-driven-development` and `systematic-debugging` name Codex
  as their first consumer.
- n = 5 per arm per series, 15 per arm in total. Pass rates of 15 of 15 and 14 of 15 cannot
  distinguish a 100% configuration from a 90% one.
- Only series 3 has sessions that worked from a failing run, and there the failing output
  names the failing case outright. The runs do not show how the model debugs when the
  failure does not point at the cause.
- The test measured availability, not content. Because no run invoked a skill, it shows
  that a Claude lead does not reach for these skills and succeeds without them. It does not
  measure what happens when a command names a skill explicitly, as `commands/test.md` and
  `commands/debug.md` do today for the two removed skills. Those references have to be
  rewritten or dropped with the removal.
- The shipped configuration (two removed, one kept) was inferred from the two measured
  arms, not measured; see "Scope decision".

## What did not go as designed

- **Output format.** Every run used `--output-format stream-json --verbose` instead of
  `json`, so that skill use could be read from every run without a re-run. The stream's
  final `result` event is the object `--output-format json` prints; it was saved as
  `run.json` per run and all table values come from it.
- **Session isolation.** Three flags were added: `--setting-sources project`,
  `--strict-mcp-config` and `--no-session-persistence`. The host has about 200 user-level
  skills, several plugins and MCP servers; without these flags both arms would have carried
  them. With them, the session saw the fixture's project skills and Claude Code's built-ins
  only (the lists above). Built-in `debug` and `verify` skills were present in both arms
  and were not invoked in any of the 30 runs.
- **`Skill` in the allowlist.** `Skill` was added to `--allowedTools` in both arms so that
  an ALL-arm session could open a skill without a permission denial.
- **Series 1 allowlist.** Too narrow; no session could run the tests before the fix. See
  series 1.
- **Series 2 host gap.** The corrected allowlist was not enough, because the host has no
  `python` binary and no pytest. I knew that before the series started and expected the
  model to fall back to `python3 -m unittest` before editing. It did not. See series 2.
- **Series 3 was not requested.** It adds five runs per arm beyond the corrected series
  that was asked for, and it changes the environment (a scratch virtual environment with
  pytest), not only the allowlist.
- **Residual refusals.** Series 2 and 3 still refuse compound commands containing
  `npm test`, `sed -i` and `git stash`. The last of these caused the one failed run.
- **Model id.** The `sonnet` alias resolved to `claude-sonnet-5-5` (from the `init` event
  and `modelUsage`).

## What was not tested

The other nine skills were visible in both arms and were not candidates. They are kept:
`codebase-mapping`, `iterative-refinement`, `knowledge-compounding`, `review-synthesis`,
`scope-cutting`, `session-continuity`, `shadow-path-tracing`, `wave-orchestration`,
`writing-plans`. All nine describe Triforge's own workflow (ops/ files, waves, leases,
review merging, session handoff), and a single bug-fix fixture cannot exercise them.

## Removal rows

The pruning itself is applied by the orchestrator after this note; the rows record the
decision and the runs behind it.
Applied in this change (U4, 2026-10-01): both removed directories are gone from `skills/`, and 10 skills ship.

| Row | Evidence |
|---|---|
| removed: `test-driven-development` (with its companion `writing-good-tests.md`) | 30 runs, series 1 to 3, ALL 1 to 5 and WITHOUT 1 to 5 in each: WITHOUT passes 15 of 15, ALL 14 of 15; mean total tokens WITHOUT / ALL 0.986, 0.912, 0.861 by series and 0.928 pooled; invoked in 0 of 15 ALL runs; every WITHOUT run added a regression test unaided (criterion c) |
| removed: `systematic-debugging` | same 30 runs and ratios; invoked in 0 of 15 ALL runs; every WITHOUT run found and fixed both files (criterion b), from reading alone in series 1 and 2 and from a failing test run in series 3 |
| kept: `verification-before-completion` | scope decision, not a measurement: Triforge-specific content (completion signal, `ops/.sprint-complete` sentinel, the checklist named by `scripts/coordinate.sh` and the ship, coordinate and wrap workflows); U24 splits it. For the record, it was invoked in 0 of 15 ALL runs |

## Prevention

- A removal test needs the session isolated from the host's own skills and plugins
  (`--setting-sources project --strict-mcp-config`), or the arms differ from each other by
  less than they differ from the fixture's intent.
- Read skill use from the event stream, not from the model's summary. The same goes for
  the outcome: one session reported regression tests that its diff does not contain.
- Before the series, run one throwaway session and read its tool calls. Check two things:
  that the allowlist permits the commands the model actually chooses, and that those
  commands exist on the host (`python`, pytest). Series 1 failed the first check and
  series 2 the second.
