# Under Codex

- Invoke as `$agent-triforge:at-plan` in the task prompt, with the goal text following it.
- Personas start detached through `persona_spawn` from the shell tool, not `spawn_agent`; run the wait block in `exec_command`: `persona_wait` returns inside the registry's 900 s `wait_budget_s`, with 75 while personas still run, so you rerun it. The plan-checker still runs as top-tier Claude under this lead.
- Questions to the user (the ceremony level, the incomplete-plan ruling, the assumptions) are asked in the reply. Under `codex exec` with no user answering, the unattended rules apply: archive open rows for another goal and record the ruling in `ops/CHANGELOG.md`.
- Run the Phase 0 block through the shell tool and read the promoted `ops/ARCHITECTURE.md` afterward; the shell's exit code is not the signal.
