# Model routing

Which model and effort each sub-agent runs at. `ROOT` is the Triforge plugin root: `${CLAUDE_PLUGIN_ROOT:-$ROOT}` under Claude Code, and from any other lead the path the `at-` skill's locator printed.

## Model routing discretion

Shipped frontmatter floors at `opus` — no shipped file names a model a host may lack. team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) ship at `effort: max`; the other 15 agents ship at `effort: xhigh`. When spawning sub-agents for narrow, rubric-following tasks (e.g., learnings-researcher, convention-enforcer), you MAY step down the runtime ladder one tier at a time:

The ladder is defined once — `TRIFORGE_MODEL_LADDER` in `$ROOT/scripts/lib/registry.sh`; `triforge_ladder` prints it after sourcing `$ROOT/scripts/invoke-external.sh`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.

- Pick the smallest downgrade that fits the task — don't skip to Sonnet when Opus/xhigh would do.
- Only downgrade for tasks with clear rubrics and limited scope.

## Spawn-time Fable override

When the newest `ops/research/*-probe-record.md` (`latest_probe_record` in `$ROOT/scripts/invoke-external.sh`), row CC-02, shows Fable PASS on the host, team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) run with a model override to `fable`. The Claude Code spawn parameter that carries the override is named in the claude reference.
