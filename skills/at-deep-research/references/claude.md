# Under Claude Code

- Invoke as `/at-deep-research <topic or goal>`.
- The four persona lenses and the synthesizer are Agent tool sub-agents: `learnings-researcher`, `framework-docs-researcher`, `git-history-analyzer`, `best-practices-researcher`, then `research-synthesizer`. Launch the four and the analyst dispatch in one message, pin model and effort on each, and wait for every one before spawning the synthesizer. The fetching lenses use WebFetch and WebSearch under the endpoint-hygiene rule.
- Run the analyst's dispatch block with the Bash tool in the background (its 600 s timeout approaches the foreground limit) and wait on it; `ops/RESEARCH_ANTIGRAVITY.md` and `$AGY_OUT`, not the shell's exit code, are what the synthesizer reads.
