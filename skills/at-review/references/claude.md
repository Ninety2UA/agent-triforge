# Under a Claude Code lead

- Invoke as `/at-review [flags]`. Claude Code exports `CLAUDE_PLUGIN_ROOT`, which the locator accepts first when it passes the Triforge-root test.
- The specialist reviewers, `learnings-researcher` and `findings-synthesizer` are personas: they run through `dispatch_persona` inside the dispatch block (the Bash tool), not the Agent tool, so nothing is pinned on a spawn.
- rc 40 from `dispatch_role`: that role resolved to the Claude lane (its default CLI is absent, or the roster pins `cli = "claude"`). The analyst lane runs the `architecture-strategist` persona through `dispatch_persona` (the dispatch reference). The reviewer lane is a native Claude sub-agent (the Agent tool) with a logic + security brief against the `[R]` scope, `model` and `effort` pinned, writing `ops/REVIEW_CODEX.md` so `findings-synthesizer` sees it alongside the other lanes.
