# Under Claude Code

- Invoke as `/at-debug <bug description or error message>`.
- Step 1's validator is a sub-agent spawned with the Agent tool, the `bug-reproduction-validator` persona and a pinned model and effort; wait for it, and treat an empty return as a failed sub-task, not as NOT_REPRODUCIBLE.
- The anti-pattern sweep in Step 3 is a Grep over the repository; a question to the user (more details on a non-reproducible report) goes through the AskUserQuestion tool when it is listed, otherwise in chat.
