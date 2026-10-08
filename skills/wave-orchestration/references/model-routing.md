# Model routing

Which model and effort each sub-agent runs at. `ROOT` is the Triforge plugin root: `${CLAUDE_PLUGIN_ROOT:-$ROOT}` under Claude Code, and from any other lead the path the `at-` skill's locator printed.

## Personas

A persona (a reviewer, checker or researcher from the persona home) runs through `dispatch_persona <persona> <input> <out> [--at task:<id>|ref:<git-ref>] [--brief <text>]`. A skill starts it detached, `persona_spawn <run-dir> <name> <persona> <input> <out> [flags]`, and collects it with `persona_wait <run-dir> [<name>…]`, rerun while it returns 75: a top-tier persona can outlast one host tool call (Claude Code stops one at 600 s, a Codex lead at 900 s). `<input>` is data under review: a file (the collect-snapshot diff, a scope, a bug report), or `task:<id>`, the lease's recorded snapshot diff as `persona_snapshot_diff` writes it; for an `exec` persona a bare `<id>` or `task:<id>` input also stands for `--at task:<id>`. The skill's task text goes in `--brief`, never in the input. `<out>` is the report file the call writes, and `--at` picks the disposable worktree an `exec` persona runs in (default `ref:HEAD`, committed work only). `ref:` takes a branch, `HEAD` or a commit id; a name that another ref of the same name, or a second object, makes ambiguous is refused with rc 64, and the refusal names what to pass instead. Its manifest entry carries its tool class, its starting tier on the ladder and its turn budget, so the dispatching skill pins nothing and cannot step it down. The never-downgrade trio (security-sentinel, plan-checker, findings-synthesizer) is pinned to the top tier there and runs as top-tier Claude whichever CLI leads; when Claude is unavailable the call blocks and names the fix.

## Model routing discretion

When you pick the model yourself (a builder task, the `team-lead` persona's agent-team spawn), you MAY step down the runtime ladder one tier at a time for narrow, rubric-following tasks:

The ladder is defined once — `TRIFORGE_MODEL_LADDER` in `$ROOT/scripts/lib/registry.sh`; `triforge_ladder` prints it after sourcing `$ROOT/scripts/invoke-external.sh`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.

- Pick the smallest downgrade that fits the task — don't skip to Sonnet when Opus/xhigh would do.
- Only downgrade for tasks with clear rubrics and limited scope.

## Spawn-time Fable override

When the newest `ops/research/*-probe-record.md` (`latest_probe_record` in `$ROOT/scripts/invoke-external.sh`), row CC-02, shows Fable PASS on the host, the top tier is `fable`: `dispatch_persona` applies it to the top-tier personas (the never-downgrade trio among them), and the lead applies it when it spawns the `team-lead` persona. The Claude Code spawn parameter that carries the override for team-lead is named in the claude reference.
