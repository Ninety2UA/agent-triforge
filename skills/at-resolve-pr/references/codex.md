# Under Codex

- Invocation: `$at-resolve-pr 123` in the prompt. Codex never invokes this skill implicitly (`agents/openai.yaml` sets `policy.allow_implicit_invocation: false`).
- The spawn: `spawn_agent` with the brief and the PR reference as the prompt, model and effort pinned (the Codex pin is `gpt-6-astra` at `xhigh`). One spawn round; the `[agents]` caps in the Triforge Codex declarations are the intended fan-out, not enforced config.
- Network: `gh api` needs network access. A sandboxed sub-agent (`sandbox_mode = "workspace-write"` has no network by default) may report the fetch as denied; in that case the lead — which runs with the launch profile the human typed — fetches the comments itself and passes them to the sub-agent as data.
- The sub-agent's `Status:` line is read the same way as a lease report: `DONE` / `DONE_WITH_CONCERNS` proceed to verification, `BLOCKED` / `NEEDS_CONTEXT` go to the user, and no line at all is "report missing", re-dispatched once.
