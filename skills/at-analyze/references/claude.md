# Under Claude Code

- Invoke as `/at-analyze <github-url or local-path>`.
- The 3.3 command asked for `ultrathink`: run this skill at the highest reasoning effort available (`max` on the lead's model) and say so.
- Fetch a URL with the WebFetch tool (a GitHub repository can also be cloned read-only into a scratch directory and read from there); read a local path with the Read tool and search it with Grep and Glob. No Edit or Write calls in this skill.
