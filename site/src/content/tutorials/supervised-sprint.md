---
description: Add Agent Triforge to a codebase you already have, then run one sprint a phase at a time and read what each workflow wrote before you start the next.
---

[Your first sprint](/tutorials/first-sprint/) gave one goal to `/at-ship` and let a single session run every phase. This tutorial starts in a codebase you already have, a git repository with its own history, and runs the same sprint one phase at a time. You start each phase's workflow yourself and read what it wrote before you go on. Between phases you can change the plan, or stop and pick up in a new session.

It was written from the documentation and the workflows, with no recorded run behind it. The files and checks it names are the ones the workflows produce; your plan, your tasks and your review findings will differ.

You need:

- Claude Code, Antigravity (`agy`) and Codex, each installed and logged in, plus git, Python 3 and, on macOS, GNU coreutils. [Getting started](/docs/getting-started/#prerequisites) lists the versions and the checks.
- A project of your own in a git repository, with at least one commit.

Each phase sends prompts and code from your repository to the providers behind the CLIs it calls, and in Phase 0 the analyst reads the whole repository. [Data egress](/guides/data-egress/) says what goes where.

Claude Code leads by default, and Codex can lead too. Where the steps differ, each shows both.

## Start from a clean checkout

In your project:

```bash
cd path/to/your-project
git status
```

Commit or set aside your own changes first, so the sprint starts from a clean working tree. Triforge sets the project up in the repository's top folder, the nearest one above that holds `.git`, even when you start in a subfolder.

### What happens

git names the branch you are on and lists any changes that are not committed yet.

### Why it matters

Each task's worker starts from the commit its lease is cut from, so it sees only committed work. The review reads the diff up to your working tree, uncommitted edits included, and lists untracked files by name. The test step stops when the files it tests have uncommitted changes. Unfinished changes of your own would be reviewed as part of the sprint.

### Checkpoint

`git status` reports a clean working tree.

## Install the plugin and start the lead

If Triforge is already installed in your lead, only start the lead in the project.

#### Claude Code leads

```bash
claude plugin marketplace add https://github.com/Ninety2UA/agent-triforge
claude plugin install agent-triforge@agent-triforge
```

Then start Claude Code in the project:

```bash
claude
```

#### Codex leads

```bash
codex plugin marketplace add Ninety2UA/agent-triforge
codex plugin add agent-triforge@agent-triforge
```

Add the project's trust entry to `~/.codex/config.toml` yourself, with the project's absolute path. Triforge never writes your user-level config.

```toml
[projects."/absolute/path/to/your-project"]
trust_level = "trusted"
```

Then start Codex in the project:

```bash
codex
```

### What happens

The lead's first session in the project sets it up. It creates `ops/` with the skeleton files and `ops/roster.toml`, copies the portable skills into `.agents/skills/`, and adds the project files Codex reads in `.codex/`. Each run fills in only what is missing. Session start never writes into an existing `AGENTS.md`; when the project has no root `AGENTS.md`, it prints a `cp` command for Triforge's pointer block.

Under Codex the session-start banner appears once you have trusted the plugin's hooks. Each lead workflow also runs that setup itself, so the next step sets the project up either way.

### Why it matters

Triforge adds its own folders beside your code and leaves your existing code as it is. The plan, the roster, the review files and the notes later sprints read all live in `ops/`.

### Checkpoint

`git status --short` lists `ops/` and the other folders Triforge added as untracked, and none of your own files as modified. Under Codex, `ops/` may appear only during the next step.

## Run setup

Skills: `at-setup`

Answer setup's questions as they come. Keep the default roles unless you have a reason to change them; setup is safe to run again later.

#### Claude Code leads

```prompt
/at-setup
```

#### Codex leads

```prompt
$agent-triforge:at-setup
```

For a Codex lead, setup also shows the hook trust step and the launch line that starts Codex with full access. You type that line yourself.

### What happens

Setup checks that the core trio answers, asks which CLI leads, shows the roles and offers each optional CLI, as in [Your first sprint](/tutorials/first-sprint/#run-setup). In a project with history, the instruction-file step is the one that can change your own files. Setup lists the instruction files in the project, in each folder above it and at the user level, and says for each CLI that can lead whether Triforge's pointer block reaches it. Then it offers a change where one is needed:

- An `AGENTS.md` without the pointer block, or no `AGENTS.md` at all: it offers to add the block, a short marked section that points agents to `ops/` and to Triforge's rules.
- A `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in the project: while one exists, Claude Code reads `AGENTS.md` only if that file imports it, so setup offers the import line.
- A `CLAUDE.md` in a folder above the project: an import there would reach every project under that folder. Setup first suggests a `CLAUDE.md` in your project whose only line is `@AGENTS.md`, and prints it for you to create.
- An `AGENTS.override.md`: Codex reads it in place of `AGENTS.md` in that folder. Setup names it and leaves the decision to you.

For each change it shows the plan first and writes nothing until you say yes. It never writes a user-level file. If adding the block would push the files Codex combines past its instruction budget, it writes nothing and shows you the sizes.

Setup also lists which providers receive your code. It ends with a status table and a verdict, then offers to commit what it wrote. That commit holds only `ops/roster.toml` and the instruction files setup changed, whatever else you have staged.

### Why it matters

The pointer block sits beside your own instructions and says that they outrank a skill's defaults. Setup changes a file of yours only after your yes. The commit matters because workers start from `HEAD`: a roster or instruction-file change reaches them only once it is committed.

### Checkpoint

The verdict reads `resolved` or `resolved, with warnings`, and `git log -1 --stat` shows setup's commit with `ops/roster.toml` and each instruction file you said yes to.

## Hold promotion for your approval

Once a wave of the build passes its check, the lead promotes the sprint's integration branch to your main branch. Unless the change touches a protected path, it does that without asking. To approve every promotion yourself, set this in `ops/roster.toml`:

```toml
[promotion]
require_user_approval = true
```

Then commit it:

```bash
git add ops/roster.toml
git commit -m "Wait for my approval before promoting"
```

Skip this step to keep the default.

### What happens

The roster ships with `require_user_approval = false`. With `true`, the lead pauses at the end of each wave and promotes only after you approve.

### Why it matters

On a main branch other people build on, you decide when the sprint's work lands there. The lead records your approval bound to the exact tree you approved, so a later merge or a move of your main branch voids it.

### Checkpoint

`ops/roster.toml` holds `require_user_approval = true` under `[promotion]`, and `git log -1 --stat` shows your commit with it.

## Plan the goal

Skills: `at-plan`

Give the goal in one sentence, and pick a change you can test. Put your own goal in place of this one.

#### Claude Code leads

```prompt
/at-plan Validate the configuration at startup and stop with an error that names each invalid setting
```

#### Codex leads

If you have not yet, quit Codex and start it again with the launch line setup printed. Triforge never runs that line for you. Then type:

```prompt
$agent-triforge:at-plan Validate the configuration at startup and stop with an error that names each invalid setting
```

Answer the planning questions in this session. Under `codex exec`, with no one to answer them, the plan follows its unattended rules instead.

### What happens

Before any phase runs, the lead says how much ceremony the goal needs, `trivial`, `standard` or `high-ceremony`, and why. Then:

- The `learnings-researcher` persona searches `ops/solutions/` and `ops/decisions/` for notes from earlier sprints. A project new to Triforge has none yet.
- In Phase 0 the roster's analyst, Antigravity by default, reads the whole repository and maps it into `ops/ARCHITECTURE.md`. It can add what it finds to `ops/MEMORY.md` and `ops/CONTRACTS.md` too. An analysis that fails or returns nothing is reported and skipped. The lead also skips Phase 0 when the codebase has not changed since the last sprint, when the session continues earlier work, or for a small bug fix.
- In Phase 1 the lead writes the plan to `ops/TASKS.md`: tasks of one to two hours, each assigned a role from the roster and grouped in waves. The larger tasks list the ways they can fail.

If `ops/TASKS.md` still holds open tasks for another goal, the lead first asks whether to archive them, merge them into the new plan or abandon them.

### Why it matters

Phase 1 reads `ops/ARCHITECTURE.md`, `ops/MEMORY.md` and `ops/CONTRACTS.md` before it splits the goal into tasks, so the plan starts from how your code is built. Each task carries the contract types it touches.

### Checkpoint

`ops/ARCHITECTURE.md` describes your codebase, unless the lead said why it skipped Phase 0. The lead then asks you about the plan's assumptions.

## Answer the riskiest assumptions

The lead names the three assumptions about your goal that would cost the most if they were wrong. Each comes with the other way to read your goal and the tasks that change if that reading is the right one. Reply with what is right, for example:

```prompt
1 and 3 are right. For 2: warn about an unknown setting and keep going.
```

### What happens

The lead revises `ops/TASKS.md` where you corrected it. It skips the questions only for a goal with no room for another reading, and never at `high-ceremony`.

Then the `plan-checker` persona checks the plan: each task's fields and assignment, dependencies without cycles, the scope, the failure paths, and whether the plan fits the architecture. Every `Accept:` command needs a concrete `Fails when:`, and every one-way task names a checkpoint. `plan-checker` sends the plan back until it approves, three rounds at most; after the third, the lead stops and shows you what is still open. `plan-checker` runs on top-tier Claude whichever CLI leads. A `trivial` goal skips it.

### Why it matters

Every task in the plan rests on these readings of your goal. A correction here changes the plan before any task is built from it.

### Checkpoint

The lead reports the plan as approved, and planning stops there, before anything is built.

## Read the plan before you build

Skills: `at-status`

In a second terminal:

```bash
grep -n '^Ceremony:' ops/TASKS.md
less ops/TASKS.md
```

#### Claude Code leads

Ask the lead where the sprint stands:

```prompt
/at-status
```

To change the plan, say what to change before you build, and ask for another `plan-checker` pass. For example:

```prompt
Keep the existing setting names and drop the task that renames them. Then have plan-checker check the changed plan.
```

#### Codex leads

Ask the lead where the sprint stands:

```prompt
$agent-triforge:at-status
```

To change the plan, say what to change before you build, and ask for another `plan-checker` pass. For example:

```prompt
Keep the existing setting names and drop the task that renames them. Then have plan-checker check the changed plan.
```

### What happens

`at-status` reads `ops/`, git and the review files and prints one report: the goal, the phase, the task counts, blockers, recent activity, pending reviews, uncommitted changes and the workflows you can run next. It writes nothing, so you can run it between any two phases.

In `ops/TASKS.md`, look at:

- The `Ceremony:` line. `high-ceremony` means the goal touches a shared interface, a protected path, a migration or something security-sensitive. It forces `plan-checker`, the full review swarm and the check between waves. The level can be raised later in the sprint and is never lowered.
- The waves. A task sits in the first wave after everything it depends on, and tasks in the same wave never change the same files.
- Each task's role and files, and its `Accept:` and `Fails when:` lines. The reviewers check the code against them later.

### Why it matters

Each builder's prompt holds its task's rows from this file. A task you did not want is easier to drop here than to undo after it merges. The build needs a plan that passed `plan-checker`, so a changed plan goes back to it first.

### Checkpoint

The status report names your goal and counts its tasks as pending, and `ops/TASKS.md` holds a plan you are ready to build.

## Build in waves

Skills: `at-build`, `wave-orchestration`

While the build runs, don't commit, switch branches or change git config in the project yourself. Every lease call first compares the git state with the lead's record of it, and a change the lead did not make stops the open leases until the lead has read what changed.

#### Claude Code leads

```prompt
/at-build
```

#### Codex leads

```prompt
$agent-triforge:at-build
```

### What happens

After a quick check that the core trio answers, the lead takes the plan one wave at a time:

- It leases each task to the roster's builder, Claude Code by default, in its own git worktree, with the task's rows and the contracts it touches in the prompt. The builder commits nothing and ends with a typed report; a report without its status line counts as missing.
- The roster's reviewer, Codex by default, is pinned to the task and checks the work. It is never the member that built the task. Findings go back to the same builder with the same reviewer, three fix cycles at most. After that the lead asks you.
- An approved task lands as one squash commit on the sprint's integration branch, made from the lead's own snapshot of the work, in wave order. Nothing merges onto your main branch directly.
- Between waves, the `integration-verifier` persona judges the build, test and lint output of the merged work. A failure blocks the next wave.

With five or more tasks, or tasks that depend on each other, the build runs in agent-team mode under the `team-lead` persona; `--team` forces that mode. `--wave N` resumes the build from wave N.

Protected paths get a stricter review. They include every `AGENTS.md`, `CLAUDE.md` and `.mcp.json` at any depth, `ops/roster.toml`, and each CLI's config folder, such as `.claude/` or `.codex/`. A task that changes one needs the lead or you as its reviewer, and it merges only with an approval, which has to be yours when the lead's own CLI built the task. Its promotion to your main branch waits for your approval too, as every promotion does when you set `require_user_approval`.

### Why it matters

No agent merges its own work, and the lead merges only the snapshot the reviewer approved, so a builder cannot slip in a change the reviewer never saw. Every task the sprint merges into your codebase has a row in `ops/CHANGELOG.md` naming its builder and a different reviewer.

### Checkpoint

While the build runs, `git worktree list` shows a worktree for each task in progress. When it ends, the lead reports whether it promoted the work, or why the promotion is blocked and which approval it needs from you. `ops/CHANGELOG.md` has a row for each merged task.

## Stop and pick up later

Skills: `at-pause`, `at-resume`

You can stop between any two phases, or in the middle of one. Save a checkpoint first.

#### Claude Code leads

```prompt
/at-pause
```

Later, start Claude Code in the project again:

```bash
claude
```

Then resume:

```prompt
/at-resume
```

#### Codex leads

```prompt
$agent-triforge:at-pause
```

Later, start Codex in the project again with the launch line setup printed, then resume:

```prompt
$agent-triforge:at-resume
```

### What happens

`at-pause` writes `ops/STATE.md` and nothing else. It records the phase and wave, the task counts, the work in progress and its branch, decisions and open questions, the review cycle, what to do first on resume, and the last command that proved the tree green, with its result and commit. When nothing was proven green in the session, it says so and copies no older result. It archives nothing and marks no task done; that happens at wrap-up.

`at-resume` reads `ops/STATE.md`, `ops/TASKS.md`, `ops/MEMORY.md`, `ops/CHANGELOG.md` and `ops/CONTRACTS.md`. If `HEAD` moved since the pause, it runs the recorded check again before anything else. Builders run detached, so they outlive the session that started them: the lead adopts the ones still running, collects the ones that finished, and never redoes a merged task. Then it summarizes the goal, the phase, the tasks done and left and the next action, and asks whether to go on or let you look first.

Under Claude Code, the session-start banner mentions a saved state, and a hook also saves a smaller checkpoint before the context is compacted. Under Codex the checkpoint is the last one `at-pause` wrote.

### Why it matters

A resumed session checks the saved state against the repository before it acts on it. A test result from another commit proves nothing about this one, so the lead runs the check again.

### Checkpoint

The lead says the state is saved and tells you to resume with `/at-resume` (`$agent-triforge:at-resume` under Codex). After you resume, its summary matches where you stopped.

## Review the change

Skills: `at-review`, `iterative-refinement`

With no flags the review runs the two core lanes. Add the specialists your change calls for: `--security`, `--perf`, `--simple`, `--conventions`, or `--full` for all of them. The example goal reads input from a file, so this run adds the security reviewer:

#### Claude Code leads

```prompt
/at-review --security
```

#### Codex leads

```prompt
$agent-triforge:at-review --security
```

### What happens

The reviewers read the same package at the same time: each task under review with its `Accept:` and `Fails when:` lines, the changed files and the diff. Each one writes its own `ops/REVIEW_*.md`:

- The roster's analyst and reviewer always run, Antigravity on architecture and Codex on logic under the shipped roster.
- Each optional CLI you enrolled adds a lane.
- `--security` adds the `security-sentinel` persona, `--perf` adds `performance-oracle`, `--simple` adds `code-simplicity-reviewer` and `--conventions` adds `convention-enforcer`. `--full` runs all of them plus `architecture-strategist`. A `high-ceremony` plan gets the full swarm whatever you pass.
- When a note in `ops/solutions/` names a module the change touches, the `learnings-researcher` persona adds what earlier sprints learned about it.

The `findings-synthesizer` persona then merges the findings into one list, each ranked P1, P2 or P3 with a confidence tier, and a low-confidence finding is never P1. The lead fixes the P1 and P2 findings, logs the P3s, and appends a review dispositions block for the cycle to `ops/TASKS.md`: every finding fixed, dismissed with a reason, or deferred with where it went.

The review converges when no P1 or P2 is left and every lane delivered its file. A lane that returned nothing counts as a gap, and the cycle cannot converge until that lane runs again. Otherwise the reviewers go again on the changed files only, three cycles at most. After the third, the lead hands you the remaining issues, each reviewer's view, the dispositions and its recommendation, including whether to ship with known issues.

### Why it matters

Reviewers start from a folder the lead controls, with the diff as their input, so a builder's edits to instruction or config files cannot steer its own review. The lead rules on each finding after the review, in dispositions you can read, and tells no reviewer beforehand which findings to accept.

### Checkpoint

`ls ops/REVIEW_*.md` lists a file for each lane, and `ops/TASKS.md` has a review dispositions block for each cycle.

## Find the test gaps, then test

Skills: `at-test`

With `--gaps-only` the workflow stops after its gap report, so you can read the gaps before any test is written. To test only part of the change, add the files or modules after the command.

#### Claude Code leads

```prompt
/at-test --gaps-only
```

When the report looks right, run the whole phase:

```prompt
/at-test
```

#### Codex leads

```prompt
$agent-triforge:at-test --gaps-only
```

When the report looks right, run the whole phase:

```prompt
$agent-triforge:at-test
```

### What happens

The `test-gap-analyzer` persona reads the changed code, by default the files named in `ops/TASKS.md` and `ops/CHANGELOG.md`. Its report lists the files with no tests, functions without coverage, missing error-path and edge-case tests, weak assertions, and the order to write the tests in. It reads committed work only, so when those files have uncommitted changes, the lead stops and asks you to commit them or to name a branch or commit to test. It never commits for you.

The full run starts with the same analysis. Then the roster's tester, Codex by default, writes each test so that it fails first, and the lead fixes the code and reruns the failing tests until the suite passes, three fix cycles at most. What still fails after that, the lead hands to you. `ops/TEST_RESULTS.md` quotes the failing run and the passing run, and the lead reports the final coverage.

### Why it matters

A new test for behavior your code already has passes on its first run, which says nothing about whether it checks that behavior. The tester shows each such test failing when the behavior is broken.

### Checkpoint

`ops/TEST_RESULTS.md` shows the suite passing, or the lead has handed you the failures left after three cycles.

## Wrap up

Skills: `at-wrap`, `knowledge-compounding`, `verification-before-completion`

#### Claude Code leads

```prompt
/at-wrap
```

#### Codex leads

```prompt
$agent-triforge:at-wrap
```

### What happens

The wrap runs in a fixed order:

1. Anything a future agent would otherwise get wrong again, or have to work out again, goes into a note in `ops/solutions/` or `ops/decisions/`. When nothing clears that bar, the lead writes no note and says so.
2. `ops/CHANGELOG.md`, `ops/MEMORY.md` and `ops/TASKS.md` are brought up to date.
3. The lead lists every ruling it made during the sprint and exports the deferred review findings, into `ops/MEMORY.md` or, when there are ten or more, a file under `ops/archive/`.
4. The review and test files move to `ops/archive/<today's date>/`.
5. Every claim of done is checked against fresh evidence, and `ops/STATE.md` is written.
6. The sprint summary prints, and `ops/.sprint-complete` is created as the last action.

If a check fails, the lead creates no marker and writes down the blocker instead.

### Why it matters

The summary's "Rulings I made" list holds every decision the lead made on its own during the sprint, so you can overturn any of them. The list prints before the marker exists, so you see every ruling before the sprint counts as finished. The next sprint's planning searches the notes in `ops/solutions/` before it plans anything.

### Checkpoint

`ops/.sprint-complete` exists, `ops/archive/` holds the review files, and `ops/STATE.md` says where the sprint ended. git ignores the marker, so it is never committed.

## Recap

| Workflow or skill | What it produced |
|---|---|
| `at-setup` | `ops/roster.toml`, and the pointer block in your instruction files where you said yes |
| `at-plan` | `ops/ARCHITECTURE.md` and the approved plan in `ops/TASKS.md` |
| `at-status` | A report of where the sprint stood, between any two phases |
| `at-build` | One reviewed squash commit per task, and the promotion to your main branch |
| `wave-orchestration` | The leases and pinned reviews behind each merge, each with its row in `ops/CHANGELOG.md` |
| `at-pause` | The checkpoint in `ops/STATE.md` |
| `at-resume` | A new session that picked up where the last one stopped |
| `at-review` | The `ops/REVIEW_*.md` files from each lane |
| `iterative-refinement` | The review dispositions in `ops/TASKS.md` |
| `at-test` | The gap report and `ops/TEST_RESULTS.md` |
| `at-wrap` | The archive, `ops/STATE.md` and `ops/.sprint-complete` |
| `knowledge-compounding` | The notes in `ops/solutions/` and `ops/decisions/` |
| `verification-before-completion` | Fresh evidence behind each claim of done |

[Workflows](/docs/workflows/) lists every workflow with its arguments, and [Project layout](/docs/project-layout/#customization) shows what else you can change in the roster. To run a sprint with nobody watching, follow [An unattended run](/tutorials/unattended-run/).
