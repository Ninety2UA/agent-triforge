# validate-skills fixtures

One scratch repo per rule for `bash scripts/validate-skills.sh --self-test` (C25). Each
directory mirrors a repo root (`skills/`, `scripts/`, `personas/`) and carries an `EXPECT` file:

```
check: C04            # the one rule the fixture violates, or `none` for a conforming fixture
under-warn: warning   # warning = a newer rule: an error in the default run, a warning under --warn; error = fails in both modes
message: double hyphen   # a substring of that rule's message
```

`--self-test` runs every fixture in both modes — the default, where every finding is an error,
and `--warn` — and asserts that exactly the named rule fires, with that message, at the named
severity. The conforming fixture also runs through the bash wrapper with `--strict`, which is
accepted and changes nothing. Run one fixture by hand with
`bash scripts/validate-skills.sh [--warn] --fixture scripts/fixtures/validate-skills/<dir>`.

The C10 set budget (14 descriptions × 290 chars), the C15 token guard (a 20,100-char body) and
the C3 block structure (frontmatter shapes with their `yaml.safe_load` verdict; most of them trip
C2 or C14 too, so no single-rule fixture can carry them) are computed inside `--self-test` rather
than committed.

These directories are outside `skills/`, so neither `validate-versions.sh`'s surface count
(`skills/*/SKILL.md`) nor the `.agents/skills/` refresh sees them.
