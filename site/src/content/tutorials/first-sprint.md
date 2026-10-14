---
description: Install Agent Triforge, set up a new project with at-setup and take one small goal through every phase with at-ship, under a Claude Code or a Codex lead.
---

This tutorial starts in an empty folder and ends with a finished sprint. You install Agent Triforge, set the project up with `/at-setup`, and give `/at-ship` one small goal. From there one session does the rest: it plans the work, builds each task in its own worktree, has another agent review it, tests it and writes down what it learned.

It was written from the documentation and the workflows, with no recorded run behind it. The files and checks it names are the ones the workflows produce; your plan, your tasks and your review findings will differ.

You need:

- Claude Code, Antigravity (`agy`) and Codex, each installed and logged in. [Getting started](/docs/getting-started/#prerequisites) lists the versions and the checks.
- git, and Python 3, which the hooks use.
- On macOS, GNU coreutils (`brew install coreutils`). Without a `timeout` command the helper refuses to call another CLI.

The sprint sends prompts and code to Anthropic, Google and OpenAI, the providers behind those CLIs. [Data egress](/guides/data-egress/) says what goes where.

Claude Code leads by default, and Codex can lead too. Where the steps differ, each shows both. Pick your lead once and every step, on every page, follows it.

## Create the project

```bash
mkdir wordcount && cd wordcount
git init
echo "# wordcount" > README.md
git add README.md && git commit -m "Start the project"
```

### What happens

git creates the repository and its first commit. The sprint writes all of the code.

### Why it matters

Every task is built in its own git worktree, and the workers start from `HEAD`, so the repository needs a commit to start from.

### Checkpoint

`git log --oneline` shows one commit.

## Install the plugin

Only the CLI that leads gets the plugin.

#### Claude Code leads

```bash
claude plugin marketplace add https://github.com/Ninety2UA/agent-triforge
claude plugin install agent-triforge@agent-triforge
```

That installs it for your user, in every project. To share it with your team through `.claude/settings.json`, add `--scope project` to the second line.

#### Codex leads

```bash
codex plugin marketplace add Ninety2UA/agent-triforge
codex plugin add agent-triforge@agent-triforge
```

Then trust the project. Add this entry to `~/.codex/config.toml` yourself, with the project's absolute path (`pwd` prints it):

```toml
[projects."/absolute/path/to/wordcount"]
trust_level = "trusted"
```

### What happens

Claude Code registers the plugin's skills, hooks and settings by itself. Codex registers the skills and the hooks, and runs the hooks only after you trust them; setup checks that later and tells you what to do.

Since version 0.147.0, Codex reads a project's own `.codex/` files only in a trusted project. Triforge never writes your user-level config, so that entry is yours to add.

### Why it matters

The lead runs the workflows and calls the other agents through its helper, so they need no plugin of their own. They only need to be installed and logged in.

### Checkpoint

Under Claude Code, both commands finish without an error. Under Codex, `~/.codex/config.toml` holds the entry with your project's path.

## Start the lead

In the project folder:

#### Claude Code leads

```bash
claude
```

#### Codex leads

```bash
codex
```

### What happens

The first Claude Code session in the project runs the plugin's session-start hook, which sets the project up. It creates `ops/` with the skeleton files and `ops/roster.toml`, copies the portable skills into `.agents/skills/`, and adds the project files Codex reads in `.codex/`. The banner reads "Multi-agent framework ready." and lists the lead workflows.

Under Codex the banner appears once you have trusted the plugin's hooks. Each lead workflow also runs that setup itself, so the next step sets the project up either way.

### Why it matters

`ops/` is where the agents share their work: the plan, the roster, the review files and the notes later sprints read all live there.

### Checkpoint

The project has an `ops/` folder holding `roster.toml`, `MEMORY.md` and `CHANGELOG.md`. Under Codex it can appear only during the next step.

## Run setup

Skills: `at-setup`

Run setup and answer its questions. For a first sprint, keep the default roles. You can enroll the optional CLIs now or later, because setup is safe to run again.

#### Claude Code leads

```prompt
/at-setup
```

#### Codex leads

```prompt
$agent-triforge:at-setup
```

### What happens

Setup goes through the project in this order:

1. It checks that Claude Code, Antigravity and Codex answer. For one that does not, it names the install or login fix, and the verdict stays unresolved until you run it.
2. It asks which CLI leads, Claude Code or Codex. For a Codex lead it shows the trust entry, the hook trust and the launch line that starts Codex with full access. You type that line yourself.
3. It shows each role with its CLI, model and effort. Keep the defaults, or change any of them. [The roster](/roster/) lists the defaults.
4. It offers each optional CLI. You pick a model for it or decline it, and a decline is remembered. Devin joins only with your consent on record.
5. It lists the instruction files and offers to add Triforge's pointer block to the project's root `AGENTS.md`. It changes a file only after you say yes.
6. It lists which providers receive your code.

It ends with a status table, one row per CLI, and a verdict: `resolved`, `resolved, with warnings`, or `UNRESOLVED` with the exact fix. Then it offers to commit what it wrote.

### Why it matters

Setup is the one guided path from a fresh install to a working roster. It never runs an installer or a login and never writes your user-level config; it prints those steps for you instead. Each roster change is checked before it is written, so a wrong answer leaves the roster as it was.

### Checkpoint

The verdict reads `resolved` or `resolved, with warnings`. Say yes to the commit offer, so the tasks start from a `HEAD` that holds what setup wrote.

## Start the sprint

Skills: `at-ship`

Give the goal in one sentence. Put your own goal in place of this one: a small goal you can test makes a good first sprint.

#### Claude Code leads

```prompt
/at-ship Build a Python command-line tool that counts the words in a Markdown file, skipping fenced code blocks, with unittest tests
```

Before any work starts it prints a completion line. Paste that line back as your next message:

```prompt
/goal Sprint complete ONLY when ALL of: every phase is done or explicitly skipped with a stated reason; the verification-before-completion checklist passes with evidence; ops/STATE.md is written; review files are archived to ops/archive/; ops/.sprint-complete is created last.
```

#### Codex leads

Quit Codex and start it again with the launch line setup printed. That line runs Codex with full access and no approval prompts, and Triforge never runs it for you. Then type:

```prompt
$agent-triforge:at-ship Build a Python command-line tool that counts the words in a Markdown file, skipping fenced code blocks, with unittest tests
```

### What happens

The sprint starts with the completion checklist. Then the phases run in order, and the lead says why whenever it skips one:

- Before planning, the `learnings-researcher` persona searches `ops/solutions/` and `ops/decisions/` for notes from earlier sprints. A new project has none yet.
- In Phase 0, Antigravity maps the codebase into `ops/ARCHITECTURE.md`. The lead skips this when the codebase has not changed or the change is small.
- In Phase 1 the lead writes the plan to `ops/TASKS.md`: tasks in waves, each assigned a role from the roster, and for the larger ones the ways they can fail.

Under Claude Code, the `/goal` line makes Claude Code hold the session to that checklist. A Codex lead has no such gate. It prints the checklist for the record, and the sprint ends when `ops/.sprint-complete` exists.

### Why it matters

The checklist is the sprint's definition of done, fixed before any work starts. Under either lead, `ops/.sprint-complete` is created only after every item holds, and it is the one completion signal the tools read.

### Checkpoint

`ops/TASKS.md` holds the plan, its tasks grouped in waves.

## Answer the riskiest assumptions

Before anything is built, the lead names the three assumptions about your goal that would cost the most if they were wrong. Each comes with the other way to read your goal and what changes if that reading is the right one. Reply with what is right, for example:

```prompt
1 and 2 are right. For 3: count the words in headings too, but not in inline code.
```

### What happens

The lead corrects `ops/TASKS.md` where you corrected it. For a goal with nothing open to question it skips this step.

Then the `plan-checker` persona reviews the plan: assignments, dependencies, scope and the failure paths. It sends the plan back until it approves, three rounds at most. `plan-checker` runs on top-tier Claude whichever CLI leads.

### Why it matters

Every task in the plan rests on these readings of your goal. A correction here changes the plan before any task is built from it.

### Checkpoint

`ops/TASKS.md` reflects your answers, and the build starts. The lead builds only from a plan that `plan-checker` approved.

## Watch the build

Skills: `wave-orchestration`

The build runs without you. To watch it, open a second terminal in the project:

```bash
git worktree list
```

### What happens

The lead leases each task to the roster's builder, Claude Code by default, in its own git worktree. When the task is built, a pinned reviewer checks it. The reviewer is a different roster member from the builder, Codex by default. A task gets at most three fix cycles with the same reviewer; after that the lead asks you.

An approved task lands as one squash commit on the sprint's integration branch, made from the lead's own snapshot of the work. Between waves the `integration-verifier` persona checks what has been merged. At the end the lead promotes the integration branch to your main branch. A change to a protected path, such as `AGENTS.md` or anything under `.claude/`, waits for your approval first.

### Why it matters

No agent merges its own work, and the lead merges only its own snapshot of what the reviewer approved, so a builder cannot slip in a change the reviewer never saw.

### Checkpoint

`git worktree list` shows a worktree for each task in progress. When the build ends, `ops/CHANGELOG.md` has a row for each merged task, naming its builder and its reviewer.

## Review until it converges

Skills: `iterative-refinement`

During the review, in the second terminal:

```bash
ls ops/REVIEW_*.md
```

### What happens

Five reviewers read the change at once, each writing its own `ops/REVIEW_*.md`: Antigravity on architecture and design, Codex on logic, security and tests, and the `security-sentinel`, `performance-oracle` and `code-simplicity-reviewer` personas. The `findings-synthesizer` persona merges their findings into one list ranked P1, P2 or P3, each with a confidence tier.

The lead fixes the P1 and P2 findings and checks whether the review has converged. In the default `standard` mode that means no P1 or P2 is left. If some are, the reviewers go again, three cycles at most, and then the lead hands you what is left with a recommendation. `--convergence fast` on the goal line stops once no P1 is left; `--convergence deep` also waits for fewer than 3 P3.

### Why it matters

Each reviewer looks for a different kind of problem. The synthesis removes duplicates and gives each finding a confidence tier, and a low-confidence finding is never P1, so a guess cannot hold up the sprint.

### Checkpoint

`ops/TASKS.md` has a review dispositions block for each cycle: every finding fixed, dismissed with a reason, or deferred with where it went.

## Test, failing test first

In the second terminal, once the tests have run:

```bash
cat ops/TEST_RESULTS.md
```

### What happens

The `test-gap-analyzer` persona finds the code paths no test covers. It reads committed work only, so when the changed files have uncommitted changes, the lead stops and asks you to commit them or name a branch. It never commits for you. The tester, Codex by default, then writes each test so that it fails first, and the lead fixes and reruns until the suite passes. The results go to `ops/TEST_RESULTS.md`.

### Why it matters

A test that passes before the code exists may not check anything. Watching it fail first shows that it checks the behavior your goal asked for.

### Checkpoint

`ops/TEST_RESULTS.md` shows the suite passing.

## Wrap up

Skills: `knowledge-compounding`, `verification-before-completion`

When the lead reports the sprint done:

```bash
ls ops/.sprint-complete ops/archive/
cat ops/STATE.md
```

### What happens

The lead writes a note to `ops/solutions/` for anything a future agent would otherwise get wrong again, and no note when there is no such lesson. It updates `ops/CHANGELOG.md`, `ops/MEMORY.md` and `ops/TASKS.md`, moves the review files to `ops/archive/<today's date>/`, checks every claim of done against fresh evidence, and writes `ops/STATE.md` for the next session.

Only when every checklist item holds does it create `ops/.sprint-complete`, as its last action. If an item fails, it creates no marker and writes the blocker into `ops/TASKS.md` and `ops/STATE.md` instead.

### Why it matters

`coordinate.sh` counts a sprint as finished only when the marker exists, so a sprint that failed a checklist item is never counted as done. Before the next sprint plans anything, it searches `ops/solutions/` for these notes.

### Checkpoint

`ops/.sprint-complete` exists, `ops/archive/` holds the review files, and `ops/STATE.md` says where the sprint ended.

## Recap

| Workflow or skill | What it produced |
|---|---|
| `at-setup` | `ops/roster.toml`: your lead, the roles and the optional CLIs you enrolled |
| `at-ship` | The whole sprint, from `ops/TASKS.md` to `ops/.sprint-complete` |
| `wave-orchestration` | One reviewed squash commit per task, each with its row in `ops/CHANGELOG.md` |
| `iterative-refinement` | The review dispositions in `ops/TASKS.md` |
| `knowledge-compounding` | The notes in `ops/solutions/` |
| `verification-before-completion` | Fresh evidence behind each claim of done |

[The sprint](/sprint/) takes each phase in more depth, and [the roster](/roster/) shows how to change who does what.
