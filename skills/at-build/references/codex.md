# Under a Codex lead

- Invoke as `$at-build`. No plugin-root variable is exported, so the locator resolves this skill's own location inside the plugin tree, else the plugin-root pointer that the setup skill's bootstrap writes under `.agents/`.
- A sub-agent is `spawn_agent` (the collaboration tools). Pin model and effort on every spawn, run one spawn round (no spawn-of-spawn), wait for each one before merging, and record a sub-agent that returns nothing as a failed sub-task.
- Agent-team mode has no separate runtime: the lead itself takes the team-lead role (wave grouping, context injection, every merge on the main tree, KTD-3) and runs the builders as leases plus a spawn round of reviewers.
- The lead's completion signals are the ledger (`lease_status`) and, for a sprint, the `ops/.sprint-complete` sentinel; there is no `/goal` gate under Codex (KTD14).
