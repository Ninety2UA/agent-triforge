# Under Codex

- Invoke as `$at-plan` in the task prompt, with the goal text following it.
- A sub-agent is `spawn_agent` with the persona's prompt text inlined (Codex loads no plugin agents; the `learnings-researcher` and `plan-checker` prompts live in the Triforge tree). The plan-checker stays on top-tier Claude under a Codex lead — the never-downgrade trio runs as Claude whichever CLI leads; if that lane is unreachable, report it and ask the user before Phase 1.5 rather than validating with another model.
- Questions to the user (the ceremony level, the incomplete-plan ruling, the assumptions) are asked in the reply. Under `codex exec` with no user answering, the unattended rules apply: archive open rows for another goal and record the ruling in `ops/CHANGELOG.md`.
- Run the Phase 0 block through the shell tool and read the promoted `ops/ARCHITECTURE.md` afterward; the shell's exit code is not the signal.
