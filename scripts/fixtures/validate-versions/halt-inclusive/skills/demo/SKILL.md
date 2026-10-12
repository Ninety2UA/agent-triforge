# Demo (validate-versions fixture)

Every line in this list fails: under each phrasing a builder halts at exactly fifty.

- Halt at risk above 20 % or 50+ file changes.
- Halt at 50 or more changed files.
- Halt a builder that has at least 50 changed files.
- Halt when file changes >= 50.
- Halt at ≥ 50 files.
- Halt a builder at 50 changed files.
- Stop after 50 changed files or more.
- Halt at risk above 20 % or at 50 changed files.
- Halt at risk above 20 % or 50+
  file changes (the phrase wraps).

Every line in this list passes: the threshold as the rule states it, or a count with no comparator.

- Halt a builder at risk above 20 % or more than 50 changed files.
- Halt when file changes > 50.
- The repository holds 50 files.
- Look at 50 files before you plan.
- Halt the run. Look at 50 files after it stops.
- A 150+ file diff is large.
