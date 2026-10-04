# Under Codex

- Invoke as `$at-analyze` in the task prompt, followed by the GitHub URL or local path.
- Run at the highest reasoning effort (`xhigh` on `gpt-6-astra`); the 3.3 command's `ultrathink` has no Codex equivalent beyond the effort setting.
- A URL is fetched through the shell tool (`curl`, or a read-only `git clone` into a scratch directory) — network access depends on the sandbox the session runs under, and a resource the sandbox cannot reach is reported, not reconstructed from memory; a local path is read with the shell. No `apply_patch` in this skill: it writes nothing.
