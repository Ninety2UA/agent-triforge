---
description: Run a sprint from a terminal with coordinate.sh, which starts one fresh lead session after another until the sprint is complete, under a Claude Code or a Codex lead.
---

This tutorial runs a sprint that nobody has to watch. You give `coordinate.sh` a goal in a terminal. It starts a fresh lead session, waits for it to end and starts another, until a session creates `ops/.sprint-complete` or the loop reaches its session cap. Each session begins with an empty context window and picks the sprint up from the notes the last one left in `ops/`.

It was written from the documentation and the scripts, with no recorded run behind it. The files and messages it names are the ones the scripts read and print. What your sessions build and find will differ.

You need:

- A project that has been through [Your first sprint](/tutorials/first-sprint/), or any project with Triforge installed and `/at-setup` run. This page keeps using the `wordcount` project from that tutorial.
- A terminal you can leave open while the loop runs.

Each session sends prompts and code to the same providers as a sprint you watch. [Data egress](/guides/data-egress/) says what goes where, and [Unattended runs](/guides/unattended-runs/) is the reference for every flag and exit code.

Claude Code leads by default, and Codex can lead too. Where the steps differ, each shows both.

## Get the project ready

In a terminal, in the project's top folder:

```bash
git status --short
ls ops/roster.toml .agents/triforge-plugin-root.local
```

### What happens

`git status --short` lists uncommitted changes and prints nothing on a clean tree. `ls` finds two files that setup left: the roster, which names the lead and the roles, and a pointer to where the plugin is installed. Session start writes that pointer, and so does setup.

### Why it matters

Every task is built in its own worktree that starts from `HEAD`, so commit whatever you want the sprint to build on. The loop reads the roster to find its lead, and the next steps read the pointer to find the script.

### Checkpoint

`git status --short` prints nothing, and `ls` lists both files. If the pointer is missing, the setup run in the next step writes it.

## Choose the lead

Skills: `at-setup`

The loop runs whichever CLI `ops/roster.toml` names as the lead, and setup's lead step is where you choose it. Quit the session when setup is done.

#### Claude Code leads

Start Claude Code in the project and run the lead step:

```bash
claude
```

```prompt
/at-setup lead
```

Choose Claude Code when it asks. If Claude Code leads already, setup says so and writes nothing.

#### Codex leads

Codex needs the plugin to lead. If you installed it only into Claude Code, add it to Codex:

```bash
codex plugin marketplace add Ninety2UA/agent-triforge
codex plugin add agent-triforge@agent-triforge
```

Add the project's trust entry to `~/.codex/config.toml` yourself, with the project's absolute path (`pwd` prints it):

```toml
[projects."/absolute/path/to/wordcount"]
trust_level = "trusted"
```

Then start Codex in the project and run the lead step:

```bash
codex
```

```prompt
$agent-triforge:at-setup lead
```

Choose Codex when it asks.

### What happens

Setup shows which CLI leads now and which ones can lead, then asks once. For your choice it checks whether the project's `AGENTS.md` reaches that lead and whether the plugin's hooks are trusted, and it prints the line that starts that lead. For Codex it adds that this lead runs with no sandbox and no approval prompts, followed by three statements of what confines it. Then it writes the `[lead]` table and ends with the status table and its verdict.

The switch is refused while leases are open, so make it between sprints. The roles keep their CLIs; only the lead changes.

The loop runs Codex headless, with `codex exec`. Since version 0.147.0, headless Codex reads the project's own `.codex/` files only when that entry marks the project trusted. Triforge never writes your user-level config. Until you trust the plugin's hooks in Codex, a Codex lead runs without them and the workflows still work; setup's `HOOKS:` lines name the trust step.

### Why it matters

A real run always uses `[lead]` from the roster, and no flag overrides it. The CLI named there plans, dispatches and merges in every session of the run.

### Checkpoint

The verdict reads `resolved` or `resolved, with warnings`. Under Codex, `ops/roster.toml` has a `[lead]` table with `cli = "codex"`, and `~/.codex/config.toml` holds the entry with your project's path.

## Find the loop script

The script ships with the plugin, outside your project. Read its location from the pointer:

```bash
TRIFORGE="$(tail -n 1 .agents/triforge-plugin-root.local)"
ls "$TRIFORGE/scripts/coordinate.sh"
```

### What happens

The pointer's last line is the plugin's install path. The first command keeps it in `TRIFORGE` for this terminal, and `ls` checks that the script is there.

### Why it matters

The commands below run the script by that path. Run them from the project's top folder, because the script reads and writes `ops/` there. A new terminal needs the first line again.

### Checkpoint

`ls` prints the path of `coordinate.sh`.

## Write the goal and preview the run

Skills: `at-ship`

Give the goal in one sentence, in quotes. Nobody is there to answer questions during the run, so say what to build, how it behaves and how it is tested. A dry run prints what the loop would start without starting it:

```bash
bash "$TRIFORGE/scripts/coordinate.sh" "Add an option to wordcount that prints the word count of each Markdown section under its heading, with unittest tests" --max 5 --convergence standard --dry-run
```

The flags:

- `--max` caps the sessions. Without it the cap is 5.
- `--convergence` sets when review stops: `fast` once no P1 finding is left, `standard` (the default) once no P1 or P2 is left, and `deep` once fewer than 3 P3 remain as well.
- `--team` builds in agent-team mode, meant for 5 or more tasks or interdependent ones. A goal this small leaves it out.

`--lead` composes the dry run for the other lead without changing the roster. It works only with `--dry-run`.

#### Claude Code leads

To see what a Codex lead would run:

```bash
bash "$TRIFORGE/scripts/coordinate.sh" "Add an option to wordcount that prints the word count of each Markdown section under its heading, with unittest tests" --max 5 --convergence standard --dry-run --lead codex
```

#### Codex leads

To see what a Claude Code lead would run:

```bash
bash "$TRIFORGE/scripts/coordinate.sh" "Add an option to wordcount that prints the word count of each Markdown section under its heading, with unittest tests" --max 5 --convergence standard --dry-run --lead claude
```

### What happens

The script reads the lead from the roster, composes the launch line and the prompt for the first session, prints both and exits. It starts no session and leaves `ops/` as it is.

- Under Claude Code the line is `claude --print` with `--permission-mode acceptEdits`, and the prompt opens with the `/goal` completion checklist.
- Under Codex the line starts with `codex exec -s danger-full-access` and sets the approval policy to never. Below it, the dry run notes that this line runs only with `--allow-full-access`, and that a Codex session has no goal gate and completes on `ops/.sprint-complete` alone. The prompt opens with `$agent-triforge:at-ship`, the goal in quotes and your `--convergence` and `--team` flags, and carries the checklist as text.

Under either lead the prompt gives the goal, the convergence mode and the session number (`ITERATION: 1 of 5`). It tells the session to read `ops/STATE.md` first, and to create the marker as its last action, only once the checklist holds.

### Why it matters

You see the launch line and every word of the first prompt before anything runs, and under Codex you see that the lead needs full access before you decide to allow it. Under Claude Code, `/goal` makes Claude Code hold the session to the checklist, but in a headless session that hold is best effort. The loop counts a sprint as complete only by the marker.

### Checkpoint

The output starts with `launch (Claude Code):` or `launch (Codex CLI):` and the launch line. A `---` line follows, then the prompt, with your goal after `GOAL:`.

## Start the loop

Run it in the terminal you will leave open.

#### Claude Code leads

```bash
bash "$TRIFORGE/scripts/coordinate.sh" "Add an option to wordcount that prints the word count of each Markdown section under its heading, with unittest tests" --max 5 --convergence standard
```

#### Codex leads

A Codex lead's launch line runs with no sandbox and no approval prompts. Without `--allow-full-access`, the script prints that line and the statements of what confines it, then stops with exit 77, having run nothing. When you accept that, add the flag yourself:

```bash
bash "$TRIFORGE/scripts/coordinate.sh" "Add an option to wordcount that prints the word count of each Markdown section under its heading, with unittest tests" --max 5 --convergence standard --allow-full-access
```

### What happens

The script checks that the lead's CLI is on your `PATH` and that it runs in a terminal. It prints the goal, the lead with its launch line, the session cap and the convergence mode. Under Codex it adds that the sessions have no goal gate, says full access is acknowledged, and prints the three statements:

- "Confinement under either lead is Triforge's scripts plus git-integrity detection."
- "A lease worktree limits where a worker starts, not where it writes."
- "Recorded approval is audit, not prevention, and worker output is an injection surface for a full-access lead."

It deletes any `ops/.sprint-complete` left from an earlier sprint and starts the first session. For each session it prints `--- Iteration 1/5 ---`, with the number counting up, runs the git integrity check, starts the lead with the prompt and, when the session ends, prints the last lines of its output. If the marker exists, the sprint is complete. If not, it starts the next session. A session that failed starts the next one too, unless the failure is one every new session would repeat.

Set `NOTIFY_WEBHOOK_URL` in the terminal before you start, and the loop also posts its closing message to that address.

The loop needs the terminal. Under nohup, cron or CI there is none, and it stops with exit 45 before any session starts.

### Why it matters

A full context window ends one session. The next one starts empty and reads `ops/STATE.md`, so the run goes on. Launching a full-access lead is a human-only action. The script runs one only with your `--allow-full-access`, and nothing else in Triforge starts one.

### Checkpoint

The terminal shows `--- Iteration 1/5 ---`. Under Codex, a line above it starts `Full access: acknowledged`.

## Read what each session picks up

In a second terminal in the project, during a session or between two:

```bash
cat ops/STATE.md
```

### What happens

`ops/STATE.md` is the handoff between sessions. Every prompt tells the session to read it first and to update it before it exits. A session skips Phase 0 when the file shows it done, and skips planning when `ops/TASKS.md` already holds a plan for this goal. The first session of a sprint with no `ops/STATE.md` starts from Phase 0.

When `ops/leases.toml` still holds open leases, the prompt also tells the session to rebuild the wave from that ledger: reclaim orphaned leases, keep the merged work, and requeue or finish the open ones instead of starting the wave over. For leases that failed or were escalated, it tells the session to bring them up and to resolve or abandon them before the sprint counts as done.

### Why it matters

A fresh session knows only what the files tell it. The plan, the state and the lease ledger all live in `ops/`, so a new session carries on with the sprint and keeps the work already merged.

### Checkpoint

`ops/STATE.md` names the phase the sprint is in and what comes next, and it changes as sessions end.

## Check progress

Skills: `at-status`

For a report on the whole sprint, start the lead in the second terminal and ask for the status.

#### Claude Code leads

```bash
claude
```

```prompt
/at-status
```

#### Codex leads

```bash
codex
```

```prompt
$agent-triforge:at-status
```

### What happens

The report gives the goal and the phase, then the task counts: done, in progress, pending, blocked, in review, and the open leases when there is a ledger. It lists the blockers, the recent entries in `ops/CHANGELOG.md`, the review files not yet archived and the uncommitted changes. A section with nothing to report says "none".

### Why it matters

`at-status` reads the `ops/` files and git, writes nothing and starts no other CLI, so it is safe to run beside the loop. When the loop seems stuck, its blockers section is the place to start.

### Checkpoint

The report prints with every section, from the goal to the list of workflows you can run next.

## When the loop ends

```bash
ls ops/.sprint-complete ops/archive/
cat ops/STATE.md
```

### What happens

The loop ends in one of three ways, and its closing lines say which:

- A session created `ops/.sprint-complete`. The loop prints `Sprint complete at iteration 3`, with your session number, and exits 0.
- The sessions ran out. The loop says it reached the cap without completion, points you to `ops/STATE.md` and `ops/TASKS.md`, and also exits 0.
- A session failed in a way every new session would repeat: not logged in, quota spent, or the CLI missing. It prints a `Fix:` line and exits 69.

Each of the three shows a desktop notification (`osascript` on macOS, `notify-send` on Linux) and posts to `NOTIFY_WEBHOOK_URL` when you set it. A stop before a session starts, such as the integrity check's exit 44, sends no notification.

### Why it matters

Exit 0 alone does not mean the sprint is done, since running out of sessions exits 0 too. Look for the marker. The lead creates it as its last action, only after the completion checklist holds, and the loop reads nothing else.

### Checkpoint

After a completed sprint, `ops/.sprint-complete` exists, `ops/archive/` holds the review files, and `ops/STATE.md` says where the sprint ended.

## If it stops early

Skills: `at-resume`, `at-pause`

The closing lines name the cause. The common ones:

- Exit 77, under Codex: The command had no `--allow-full-access`. Nothing ran.
- Exit 69: Log in, wait for the quota to reset, or install the CLI, as the `Fix:` line says.
- Exit 44: The integrity check found a change to `.git/config`, the git hooks, the refs, a worktree pointer or the lease ledger that the lead did not make. It restored what it could and escalated the open leases. Look at the change, and if you made it, accept it with `lease_rebaseline` before you go on.
- Exit 45: The script ran without a terminal. Start it from one.
- Exit 1: A usage error, a lead it could not resolve, the lead's CLI not on `PATH`, the helper library missing, or a `TMPDIR` other users could change.
- The sessions ran out: The progress is in `ops/STATE.md` and `ops/TASKS.md`.

[When a run stops](/guides/unattended-runs/#when-a-run-stops) has the full table. Once the cause is fixed, run the loop again or carry on by hand.

#### Claude Code leads

Run the loop again:

```bash
bash "$TRIFORGE/scripts/coordinate.sh" "Add an option to wordcount that prints the word count of each Markdown section under its heading, with unittest tests" --max 5 --convergence standard
```

Or take the sprint over in a session you watch:

```bash
claude
```

```prompt
/at-resume
```

To stop partway and hand the sprint back to the loop, run `/at-pause` first.

#### Codex leads

Run the loop again:

```bash
bash "$TRIFORGE/scripts/coordinate.sh" "Add an option to wordcount that prints the word count of each Markdown section under its heading, with unittest tests" --max 5 --convergence standard --allow-full-access
```

Or take the sprint over in a session you watch. Start Codex yourself with the launch line setup printed in the lead step, then type:

```prompt
$agent-triforge:at-resume
```

To stop partway and hand the sprint back to the loop, run `$agent-triforge:at-pause` first.

### What happens

A rerun gets a fresh session cap, and its first session reads `ops/STATE.md`, so the sprint continues where it stopped. `at-resume` loads the same files, reruns the last verification when `HEAD` has moved, and sums up the goal, the phase, the tasks done and left, and the blockers. Then it asks whether to continue on its own or let you review the state first. `at-pause` writes the `ops/STATE.md` checkpoint that the next session starts from, yours or the loop's.

### Why it matters

The sprint's state lives in `ops/` and git, so either the loop or you can carry it on from where it stopped.

### Checkpoint

The rerun shows `--- Iteration 1/5 ---` again, or `at-resume` has printed its summary and asked how to continue.

## Recap

| What you ran | What it produced |
|---|---|
| `at-setup` | The `[lead]` table in `ops/roster.toml`, which every run of the loop reads |
| `coordinate.sh --dry-run` | The launch line and the first session's prompt, with nothing run |
| `coordinate.sh` | One fresh lead session after another, until `ops/.sprint-complete` exists or the cap is reached |
| `at-ship` | The sprint and its completion checklist, which every session works toward |
| `at-status` | A read-only report on the sprint while the loop runs |
| `at-resume` | The sprint carried on by hand from `ops/STATE.md` |
| `at-pause` | A checkpoint in `ops/STATE.md` for the next session |

[Unattended runs](/guides/unattended-runs/) covers every flag and exit code, and [Your first sprint](/tutorials/first-sprint/) walks through the phases each session runs.
