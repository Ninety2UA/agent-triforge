# Under a Claude Code lead

- Invoke as `/at-build`. Claude Code exports `CLAUDE_PLUGIN_ROOT`, which the locator accepts first when it passes the Triforge-root test.
- A sub-agent is the Agent tool. Pin `model` and `effort` on every spawn, run one spawn round (no spawn-of-spawn), wait for each one before merging, and record a sub-agent that returns nothing as a failed sub-task rather than dropping its scope. `integration-verifier` and `team-lead` are the shipped agent definitions of those names.
- Agent-team mode is Claude agent teams: the `team-lead` agent coordinates teammates with a shared task list and messaging (it requires the agent-teams environment flag that `settings.json` ships).
- The never-downgrade rule holds for every spawn the build makes: `plan-checker`, `security-sentinel` and `findings-synthesizer` always run at the top Claude tier; narrow builder tasks may step down the ladder that `triforge_ladder` prints.
