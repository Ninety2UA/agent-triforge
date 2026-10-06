# Under Claude Code

- Invoke as `/at-deep-research <topic or goal>`.
- The four persona lenses and the synthesizer start detached through `persona_spawn` in the Bash tool, not the Agent tool; run the wait block with the Bash tool at `timeout: 600000`, never `run_in_background`: `persona_wait` returns inside the registry's 600 s `wait_budget_s`, with 75 while personas still run, so you rerun it. The fetching lenses get WebFetch and WebSearch from their manifest class and stay under the endpoint-hygiene rule.
- Run the swarm block with the Bash tool in the background (the analyst's 600 s timeout reaches the foreground limit) and wait for it to finish; `$RESEARCH_RUN/analyst.rc` and `analyst.md`, not the shell's exit code, are what synthesis reads.
