# Under Claude Code

- Invoke as `/at-plan <goal description>`; the goal text arrives as the skill's arguments.
- A sub-agent is the Agent tool. Name the persona (`learnings-researcher`, `plan-checker` — the plugin's agent definitions today, `personas/` from U8) and pin the model and effort on every spawn. The plan-checker is in the never-downgrade trio: `fable` at `max` when the newest probe record shows Fable PASS on the host (row CC-02), otherwise `opus` at `max`. Wait for each sub-agent before continuing; one that returns nothing is a failed sub-task, not an empty result.
- Questions to the user (the ceremony level when in doubt, the incomplete-plan ruling, the Phase 1.1 assumptions) go through the AskUserQuestion tool when it is in the tool list; otherwise ask in chat and wait.
- Run the Phase 0 block with the Bash tool; the 600 s dispatch fits a raised tool timeout or a background run that is waited on. The promoted `ops/ARCHITECTURE.md`, not the shell's exit code, is what Phase 1 reads.
