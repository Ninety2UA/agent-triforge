# Under a Codex lead

- Invoke as `$at-build`. No plugin-root variable is exported, so the locator resolves this skill's own location inside the plugin tree, else the plugin-root pointer that the setup skill's bootstrap writes under `.agents/`.
- Personas (`integration-verifier`, `continuous-reviewer`) run through `dispatch_persona` from the shell tool, not `spawn_agent`; one that fails or writes nothing is a failed sub-task.
- Agent-team mode has no separate runtime (this lead's `agent_teams` capability is unset): the lead itself takes the role of the `team-lead` persona, whose text `persona_prompt team-lead` prints (wave grouping, context injection, every merge on the main tree, KTD-3), and runs the builders as leases with `continuous-reviewer` dispatches for review.
- `lease_wait` runs in `exec_command`; its budget stays inside the registry's `wait_budget_s` (900 s), which the shipped launch line's `background_terminal_max_timeout=900000` matches. Builders run detached, so they survive the end of the tool call and of the `codex exec` run.
- The lead's completion signals are the ledger (`lease_status`) and, for a sprint, the `ops/.sprint-complete` sentinel; there is no `/goal` gate under Codex (KTD14).
