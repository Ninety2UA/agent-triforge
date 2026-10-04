# Under Claude Code

- Invocation: `/at-resolve-pr 123` or `/at-resolve-pr https://github.com/OWNER/REPO/pull/123`.
- The spawn: the Agent tool with the `pr-comment-resolver` persona (in 3.3 a plugin agent of that name: `Read, Grep, Glob, Bash, Edit, Write`; `model: opus`, `effort: xhigh`, `maxTurns: 20`). Pass the brief and the PR reference in the prompt and pin `model` on the spawn; the persona is not in the never-downgrade trio, so the ladder may step it down one tier at a time for a narrow PR.
- `gh` runs in the sub-agent's own shell with the user's `gh` login; nothing in Triforge writes or forwards GitHub credentials.
- Wait for the sub-agent to return before verifying tests or touching `ops/CHANGELOG.md`; a sub-agent that returns nothing is a failed sub-task, not an empty result.
