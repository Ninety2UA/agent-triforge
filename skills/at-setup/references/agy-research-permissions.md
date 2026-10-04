# Closing guidance: agy research lanes (`read_url`)

The deep-research and analyze skills (`at-deep-research`, `at-analyze`) fetch URLs through agy, which since 1.1.28 asks before `read_url` and soft-denies it headless; a research run then returns an empty response and `invoke_antigravity` fails it with reason `denied`. The only tier agy enforces headless is the user tier, `~/.gemini/antigravity-cli/settings.json`, and Triforge never writes that file (R18). Print this block for the user to merge by hand: the allow rule the research lanes need, paired with the three deny rules that `templates/.antigravity/settings.json` (under the plugin root) records as intent at the project tier:

```json
{
  "permissions": {
    "allow": ["read_url(*)"],
    "deny": ["command(rm -rf)", "command(git push)", "command(sudo)"]
  }
}
```

Say plainly that `read_url(*)` is a broad grant (every URL the agent chooses) and should be narrowed to the hosts the project actually researches as soon as agy accepts a pattern in that position. Without the allow rule the research lanes still run, but every URL fetch is denied and the run fails closed rather than silently returning less.
