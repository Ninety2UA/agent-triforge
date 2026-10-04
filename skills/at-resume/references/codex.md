# Under Codex

- Invocation: `$at-resume` in the prompt. Codex lists skills by description and never invokes this one implicitly (`agents/openai.yaml` sets `policy.allow_implicit_invocation: false`).
- Sub-agents for a resumed phase: `spawn_agent`, with the persona's prompt in the spawn and model + effort pinned. One spawn round, no spawn-of-spawn — the `[agents]` caps in the Triforge Codex declarations (`max_depth = 2`, `max_threads = 4`) state the intended fan-out; `gpt-6-astra` runs `multi_agent_v2` and ignores `max_depth`, so the one-round rule is the skill's, not the runtime's. The never-downgrade trio still runs as top-tier Claude, through the claude worker lane, never as a Codex sub-agent.
- Completion: a Codex lead has no `/goal` gate — it completes on the `ops/.sprint-complete` sentinel (KTD14), created only after the verification checklist passes.
- Pre-compaction checkpoints are a Claude Code hook; under Codex the last checkpoint in `ops/STATE.md` is the one the lead wrote with the pause skill. A missing baseline is still "not verified".
