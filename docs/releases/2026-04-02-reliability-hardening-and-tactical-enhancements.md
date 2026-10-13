# 2026-04-02 — Reliability hardening and tactical enhancements

Informed by a deep comparative analysis against the [official Codex plugin](https://github.com/openai/codex-plugin-cc) and [oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode), this update addresses operational reliability gaps and adds targeted capabilities identified through triaged review (P1/P2 findings only, no architectural changes).

**Subprocess timeouts** — All 7 `wait $PID` calls for Gemini/Codex now use a watchdog pattern: a background timer sends SIGTERM after timeout (600s for review/build/plan, 900s for TDD test writing), with SIGKILL fallback after 5s grace. Normal runs are completely undisturbed — the watchdog is silently killed when the process finishes. Previously, a hung `codex exec` or `gemini -p` call would block the entire pipeline indefinitely.

**Circuit breaker for debugging** — The [`systematic-debugging`](https://github.com/Ninety2UA/agent-triforge/blob/41be77d4ff56419a7e24aa639e5ea2a850208c76/skills/systematic-debugging/SKILL.md) skill now enforces a 3-attempt ceiling per issue. If the same failing test or error recurs after 3 consecutive fix attempts, the agent stops and produces a structured escalation report (error signature, attempts summary, assumption ledger, hypothesis, suggested next step) instead of looping. The ship-loop has a session-level ceiling, but this catches per-issue repetition within a session.

**Git trailer conventions** — [`/wrap`](https://github.com/Ninety2UA/agent-triforge/blob/41be77d4ff56419a7e24aa639e5ea2a850208c76/commands/wrap.md) and the [`CLAUDE.md` template](https://github.com/Ninety2UA/agent-triforge/blob/41be77d4ff56419a7e24aa639e5ea2a850208c76/templates/CLAUDE.md) now define structured commit trailers (`Constraint`, `Rejected`, `Confidence`, `Scope-risk`, `Not-tested`) to embed decision context directly in git history. Previously, decision rationale lived only in `ops/decisions/` files, separated from the code.

**Pre-plan ambiguity resolution (Phase 1.1)** — [`/plan`](https://github.com/Ninety2UA/agent-triforge/blob/41be77d4ff56419a7e24aa639e5ea2a850208c76/commands/plan.md) and [`/ship`](https://github.com/Ninety2UA/agent-triforge/blob/41be77d4ff56419a7e24aa639e5ea2a850208c76/commands/ship.md) now surface the 3 most critical unverified assumptions about the goal before building, asking the user to confirm or correct. Skipped for unambiguous goals. Previously, ambiguous specs were caught by the plan-checker after a full planning pass — this catches them earlier.

**PreCompact hook** — New [`pre-compact.sh`](../../hooks/handlers/pre-compact.sh) handler auto-checkpoints `ops/STATE.md` with task status counts and current phase before Claude Code compacts the context window. Previously, if compaction hit mid-sprint without a `/wrap`, the outer loop could restart from stale state.

**PostToolUse failure tracker** — New [`tool-failure-monitor.sh`](../../hooks/handlers/tool-failure-monitor.sh) handler tracks tool failures in `.claude/tool-failures.local.md` and warns at 5 consecutive or 10 total failures per session. Registered under `PostToolUse` and filters on `tool_response.is_error`. Previously, tool failures during autonomous runs were silent.

**Completion notifications** — [`scripts/coordinate.sh`](../../scripts/coordinate.sh) now sends macOS (`osascript`), Linux (`notify-send`), or webhook notifications on sprint completion and max-iteration exit. Gated on `NOTIFY_WEBHOOK_URL` env var for webhook delivery. Previously, long autonomous runs required manual polling.

<details>
<summary><strong>Files changed (14 files, 250 insertions)</strong></summary>

| File | Change |
|---|---|
| `commands/review.md` | Watchdog timeout (600s) on Gemini + Codex wait |
| `commands/test.md` | Watchdog timeout (900s) on Codex wait |
| `commands/build.md` | Watchdog timeout (600s) on Gemini + Codex wait |
| `commands/coordinate.md` | Watchdog timeout (600s) on Gemini wait |
| `commands/ship.md` | Watchdog timeout (600s) on Gemini wait + Phase 1.1 ambiguity check |
| `commands/plan.md` | Watchdog timeout (600s) on Gemini wait + Phase 1.1 ambiguity check |
| `commands/deep-research.md` | Watchdog timeout (600s) on Gemini wait |
| `commands/wrap.md` | Step 7: git trailer conventions |
| `skills/systematic-debugging/SKILL.md` | Circuit breaker (3-attempt ceiling) |
| `templates/CLAUDE.md` | Git trailer conventions section |
| `hooks/hooks.json` | PostToolUse failure-tracker + PreCompact hook entries |
| `hooks/handlers/tool-failure-monitor.sh` | **New** — failure tracking handler |
| `hooks/handlers/pre-compact.sh` | **New** — STATE.md auto-checkpoint handler |
| `scripts/coordinate.sh` | notify() function + completion/failure notification calls |
</details>
