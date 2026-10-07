# Under a Codex lead

- Invoke as `$at-ship <goal> [--convergence …] [--team]`. No plugin-root variable is exported, so the locator resolves this skill's own location inside the plugin tree, else the plugin-root pointer that the setup skill's bootstrap writes under `.agents/`.
- Personas start detached through `persona_spawn` from the shell tool, not `spawn_agent`, parallel ones in one block; run the wait block in `exec_command`: `persona_wait` returns inside the registry's 900 s `wait_budget_s`, with 75 while personas still run, so you rerun it. One that fails or writes nothing is a failed sub-task. The never-downgrade trio (`plan-checker`, `security-sentinel`, `findings-synthesizer`) runs as top-tier Claude under this lead too, so security review stays on a different model family from the lead.
- Agent-team mode has no separate runtime: the lead itself takes the team-lead role (wave grouping, context injection, every merge on the main tree).
- There is no `/goal` gate. Print the completion checklist for the record and complete on the sentinel alone: `ops/.sprint-complete`, created last, is the only completion signal (KTD14), and the coordinator reads nothing else.
