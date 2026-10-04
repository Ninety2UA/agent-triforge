# Under Codex

- Invoke as `$at-plan` in the task prompt, with the goal text following it.
- Personas run through `dispatch_persona` from the shell tool, not `spawn_agent`; the plan-checker still runs as top-tier Claude under this lead.
- Questions to the user (the ceremony level, the incomplete-plan ruling, the assumptions) are asked in the reply. Under `codex exec` with no user answering, the unattended rules apply: archive open rows for another goal and record the ruling in `ops/CHANGELOG.md`.
- Run the Phase 0 block through the shell tool and read the promoted `ops/ARCHITECTURE.md` afterward; the shell's exit code is not the signal.
