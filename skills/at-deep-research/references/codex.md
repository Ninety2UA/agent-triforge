# Under Codex

- Invoke as `$agent-triforge:at-deep-research` in the task prompt, followed by the topic.
- The four persona lenses and the synthesizer start detached through `persona_spawn` from the shell tool, not `spawn_agent`; run the wait block in `exec_command`: `persona_wait` returns inside the registry's 900 s `wait_budget_s`, with 75 while personas still run, so you rerun it. The two fetching lenses run as Claude (their class has web tools only there), whichever CLI leads.
- The analyst dispatch runs through the shell tool. Web fetches by the research lenses need network access in the sandbox the session runs under; when it is denied, the lens lists the endpoints it could not reach rather than substituting memory for a source.
