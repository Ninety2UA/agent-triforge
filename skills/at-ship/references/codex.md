# Under a Codex lead

- Invoke as `$at-ship <goal> [--convergence …] [--team]`. No plugin-root variable is exported, so the locator resolves this skill's own location inside the plugin tree, else the plugin-root pointer that the setup skill's bootstrap writes under `.agents/`.
- A sub-agent is `spawn_agent` (the collaboration tools): the named reviewers and checkers run as spawned agents carrying their briefs. Pin model and effort on every spawn, run one spawn round (no spawn-of-spawn), wait for each one, and record a spawn that returns nothing as a failed sub-task. The never-downgrade trio (`plan-checker`, `security-sentinel`, `findings-synthesizer`) still runs as top-tier Claude, through the claude worker lane, so security review stays on a different model family from the lead.
- Agent-team mode has no separate runtime: the lead itself takes the team-lead role (wave grouping, context injection, every merge on the main tree).
- There is no `/goal` gate. Print the completion checklist for the record and complete on the sentinel alone: `ops/.sprint-complete`, created last, is the only completion signal (KTD14), and the coordinator reads nothing else.
