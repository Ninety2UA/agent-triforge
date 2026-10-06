# Under Codex

- Invoke as `$agent-triforge:at-deep-research` in the task prompt, followed by the topic.
- The four persona lenses and the synthesizer are `spawn_agent` calls with each persona's prompt inlined (Codex loads no plugin agents). Spawn the four alongside the analyst dispatch, wait for all, then spawn the synthesizer — one spawn round, no spawn-of-spawn.
- The analyst dispatch runs through the shell tool. Web fetches by the research lenses need network access in the sandbox the session runs under; when it is denied, the lens lists the endpoints it could not reach rather than substituting memory for a source.
