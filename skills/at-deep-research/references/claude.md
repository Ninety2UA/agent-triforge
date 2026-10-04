# Under Claude Code

- Invoke as `/at-deep-research <topic or goal>`.
- The four persona lenses and the synthesizer run through `dispatch_persona` in the Bash tool, not the Agent tool. The fetching lenses get WebFetch and WebSearch from their manifest class and stay under the endpoint-hygiene rule.
- Run the analyst's dispatch block with the Bash tool in the background (its 600 s timeout approaches the foreground limit) and wait on it; `ops/RESEARCH_ANTIGRAVITY.md` and `$AGY_OUT`, not the shell's exit code, are what the synthesizer reads.
