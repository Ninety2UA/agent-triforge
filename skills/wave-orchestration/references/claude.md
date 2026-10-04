# Claude Code forms

The Claude Code-specific ways of running the wave. The lease and cross-review contract in the builder-pool-protocol reference is the same in every form; only the spawning mechanism differs.

## Sub-agents and the Fable override

Under Claude Code a sub-agent is spawned with the Agent tool. The spawn-time Fable override (model-routing reference) is the Agent tool's `model` parameter set to `fable` for team-lead and the never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) when the newest `ops/research/*-probe-record.md` (`latest_probe_record` in `$ROOT/scripts/invoke-external.sh`), row CC-02, shows Fable PASS on the host.

## Wave execution modes beyond the default

The default sub-agent mode (< 5 tasks per wave) is in the core skill. The two forms below are Claude Code-only.

### Dynamic workflow mode (5+ tasks or cross-dependent)

For 5+-task waves, author the wave as a native Claude Code dynamic workflow (`ultracode:` prefix) instead of hand-dispatching each subagent. The dependency-grouping process above (Steps 1–2) IS the workflow-authoring method — the wave plan translates directly:

- **Stages:** each wave becomes a workflow stage — tasks within a wave run as a `parallel` group; waves chain as a `pipeline` in dependency order
- **Integration verification:** the between-wave verify (Step 3.3) runs as its own stage between parallel groups; external-CLI steps (Antigravity/Codex via `invoke_antigravity`/`invoke_codex`) dispatch as workflow steps like any other
- **Mid-run requeue:** a failed task re-enters its stage via a workflow loop with the reflection questions (Step 3.5) prepended, instead of aborting the run
- **Pinned reviewer:** give the continuous reviewer a fixed label so review work routes to the same instance across stages (1:3–4 ratio with builders)

Capability basis: probe CC-04 in the newest `ops/research/*-probe-record.md` (PASS, expressibility) — dynamic workflows can express external-CLI dispatch + requeue + pinned review. The "Builder-pool wave protocol" above is the lease/cross-review contract those stages carry; it is dogfooded end-to-end (two-task wave, cross-review, single-commit merges, AE3 refusal) in the unit that introduced it.

### Team mode (experimental alternative for cross-dependent builds)

> **Note:** Team mode requires Claude Code's experimental Agent Teams feature (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS: "1"`). This mode is Claude-specific and not available when this skill is injected into Antigravity or Codex.

Each task assigned to a coordinated team worker:
- Workers coordinate via shared task list
- Direct messaging for cross-task questions
- Quality gates enforced between waves
- Orchestrator monitors and resolves conflicts
