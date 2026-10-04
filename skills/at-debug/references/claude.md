# Under Claude Code

- Invoke as `/at-debug <bug description or error message>`.
- Step 1's validator runs through `dispatch_persona` with the Bash tool, not the Agent tool; nothing is pinned on the call.
- The anti-pattern sweep in Step 3 is a Grep over the repository; a question to the user (more details on a non-reproducible report) goes through the AskUserQuestion tool when it is listed, otherwise in chat.
