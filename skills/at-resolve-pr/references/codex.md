# Under Codex

- Invocation: `$agent-triforge:at-resolve-pr 123` in the prompt. Codex never invokes this skill implicitly (`agents/openai.yaml` sets `policy.allow_implicit_invocation: false`).
- Network: `gh api` needs network access. The lead runs with the launch profile the human typed, so it fetches; a builder in `sandbox_mode = "workspace-write"` has no network by default, which is why the comments travel in the lease prompt.
- `lease_wait` runs in `exec_command`; its budget stays inside the registry's `wait_budget_s` (900 s), which the shipped launch line's `background_terminal_max_timeout=900000` matches. Builders run detached and survive the end of the tool call.
