---
name: at-conforming
description: "Use when a fixture must pass every validate-skills rule under --strict. Checks nothing itself; the body exists to exercise the layout rules."
disable-model-invocation: true
argument-hint: "[optional: a note]"
metadata:
  triforge-consumer: "lead"
  triforge-phase: "fixture"
  version: "4.0.0"
---

# Conforming Fixture

The smallest skill that passes every rule. Details live in [the reference](references/details.md); the locator runs as `bash "$SKILL_DIR/scripts/locate-triforge.sh"`.

## Step 1: Locate

Run `bash "$SKILL_DIR/scripts/locate-triforge.sh"` and read the printed root.

## Step 2: Report

State what was verified and what was not.

## Output

- One line naming the root, or the failure direction (`at-setup`).
