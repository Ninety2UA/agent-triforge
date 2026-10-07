# Claude Code forms

The Claude Code-specific ways of running the wave. The lease and cross-review contract in the builder-pool-protocol reference is the same in every form; only the spawning mechanism differs.

## Personas and the Fable override

Personas start detached through `persona_spawn` (it runs `dispatch_persona`) in the Bash tool, not the Agent tool, and are collected with `persona_wait`, rerun while it returns 75; and the persona lane applies the spawn-time Fable override (model-routing reference) to top-tier personas itself. The one Agent-tool spawn left is the `team-lead` persona in team mode: its `model` parameter is `fable` when the newest `ops/research/*-probe-record.md` (`latest_probe_record` in `$ROOT/scripts/invoke-external.sh`), row CC-02, shows Fable PASS on the host, otherwise `opus`, at `max` effort.

## Waiting on builders

Run each `lease_wait` as one Bash tool call with `timeout: 600000` (the registry's `wait_budget_s`, 600 s × 1000), never `run_in_background`: its own budget defaults to 585 s, so it returns inside that limit. Where the timeout cannot be raised, pass `--budget <s>` below the tool's limit. rc 75 means the budget ran out with builders still running: call it again. rc 80 means a building row could not be verified: stop the loop and read the message. rc 44 is an integrity escalation (the integrity-escalations reference). A `claude -p` lead that ends its turn leaves its builders running; the next session's `lease_heartbeat_check` picks them up.

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
