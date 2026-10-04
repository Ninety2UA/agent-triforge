# Under Claude Code

- Invocation: `/at-resolve-pr 123` or `/at-resolve-pr https://github.com/OWNER/REPO/pull/123`.
- `gh` runs in the lead's shell, the Bash tool, with the user's `gh` login; nothing in Triforge writes or forwards GitHub credentials.
- Run each `lease_wait` as one Bash tool call with `timeout: 600000` (the registry's `wait_budget_s`, 600 s × 1000), never `run_in_background`; its own budget defaults to 585 s, so it returns inside that limit.
- A builder the roster resolves to claude runs as a `claude -p` lease worker, not as an Agent-tool sub-agent: the lease protocol is the same whichever CLI builds.
