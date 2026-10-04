# validate-skills fixtures

One scratch repo per rule for `bash scripts/validate-skills.sh --self-test` (C25). Each
directory mirrors a repo root (`skills/`, `scripts/`, `commands/`, `agents/`) and carries
an `EXPECT` file:

```
check: C04          # the one rule the fixture violates, or `none` for a conforming fixture
default: warn       # warn = new rule (warning by default, error under --strict); fail = existing rule (error in both modes)
message: double hyphen   # a substring of that rule's message
```

`--self-test` runs every fixture in both modes and asserts that exactly the named rule fires,
with that message, at the named severity. Run one fixture by hand with
`bash scripts/validate-skills.sh [--strict] --fixture scripts/fixtures/validate-skills/<dir>`.

The C10 set budget (14 descriptions × 290 chars) and the C15 token guard (a 20,100-char body)
are computed inside `--self-test` rather than committed.

These directories are outside `skills/`, so neither `validate-versions.sh`'s surface count
(`skills/*/SKILL.md`) nor the `.agents/skills/` refresh sees them.
