# Under Claude Code

- Invoke as `/at-plan <goal description>`; the goal text arrives as the skill's arguments.
- Personas start detached through `persona_spawn` in the Bash tool, not the Agent tool; run the wait block with the Bash tool at `timeout: 600000`, never `run_in_background`: `persona_wait` returns inside the registry's 600 s `wait_budget_s`, with 75 while personas still run, so you rerun it before continuing.
- Questions to the user (the ceremony level when in doubt, the incomplete-plan ruling, the Phase 1.1 assumptions) go through the AskUserQuestion tool when it is in the tool list; otherwise ask in chat and wait.
- Run the Phase 0 block with the Bash tool; the 600 s dispatch fits a raised tool timeout or a background run that is waited on. The promoted `ops/ARCHITECTURE.md`, not the shell's exit code, is what Phase 1 reads.
