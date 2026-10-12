# Under Claude Code

- Invoke as `/at-debug <bug description or error message>`.
- Step 1's validator starts detached through `persona_spawn` in the Bash tool, not the Agent tool, with nothing pinned on the call; run the wait block with the Bash tool at `timeout: 600000`, never `run_in_background`: `persona_wait` returns inside the registry's 600 s `wait_budget_s`, with 75 while personas still run, so you rerun it.
- The anti-pattern sweep in Step 3 is a Grep over the repository; a question to the user (more details on a non-reproducible report) goes through the AskUserQuestion tool when it is listed, otherwise in chat.
