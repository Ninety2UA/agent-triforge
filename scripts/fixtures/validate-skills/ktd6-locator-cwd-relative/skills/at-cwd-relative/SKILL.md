---
name: at-cwd-relative
description: "Use when a fixture calls the locator by a working-directory path instead of its skill-directory anchor."
---

# at-cwd-relative

Run `ROOT=$(bash scripts/locate-triforge.sh) || exit $?` — the path is the project's, not the skill's.

## Output

- A line.
