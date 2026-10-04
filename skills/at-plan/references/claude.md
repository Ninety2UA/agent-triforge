# Under Claude Code

- Invoke as `/at-plan <goal description>`; the goal text arrives as the skill's arguments.
- Personas run through `dispatch_persona`, not the Agent tool; run each call with the Bash tool and wait for it before continuing.
- Questions to the user (the ceremony level when in doubt, the incomplete-plan ruling, the Phase 1.1 assumptions) go through the AskUserQuestion tool when it is in the tool list; otherwise ask in chat and wait.
- Run the Phase 0 block with the Bash tool; the 600 s dispatch fits a raised tool timeout or a background run that is waited on. The promoted `ops/ARCHITECTURE.md`, not the shell's exit code, is what Phase 1 reads.
