---
name: at-skill-work
description: "Use when writing or changing a Triforge skill (SKILL.md, references, scripts) so it passes validate-skills under --strict."
---

# Skill Work

**Goal:** a skill that every enrolled CLI can load and act on — Claude Code, Codex, Antigravity, OpenCode, Kimi or Cursor — from the plugin tree or from an `.agents/skills/` copy. **Done when** `bash ./scripts/validate-skills.sh --strict` passes for the shipped skills (its default scope is `./skills/`; a skill under `./.claude/skills/` is validated only when you name that directory: `bash ./scripts/validate-skills.sh --strict ./.claude/skills`) and `bash ./scripts/validate-skills.sh --self-test` still reports every fixture OK. **Safe failure:** a rule you cannot meet stays a warning in the default mode; never silence it by widening the validator — change the skill, or raise the rule in review.

## What a skill says (R17)

Prose carries what a model cannot infer: the goal, the done condition, the safe failure direction, and the non-derivable facts (paths, return codes, limits, who owns what). Not procedures: a capable model derives the steps, and a step list rots and hides the intent. State constraints as outcomes ("merges only after a pinned non-author review"), not as click paths.

## Shape (R15, R16)

- One router `SKILL.md` per skill, at most 8,000 bytes and about 5,000 tokens; detail goes under `references/`, one level deep (a reference never links another skill-local file), and every reference is named from `SKILL.md`. Allowed entries: `SKILL.md`, `references/`, `scripts/`, `assets/`, `agents/`. No README inside a skill.
- The skill is self-contained: links and backticked `references/`, `scripts/`, `assets/` paths resolve inside it; nothing climbs out with `../`, `/` or `~`. A working-directory path is written with a `./` prefix. `CLAUDE_PLUGIN_ROOT` is read only with a fallback (`${CLAUDE_PLUGIN_ROOT:-<fallback>}`), and only inside `scripts/`.
- Every `at-` skill carries the shared locator in its `scripts/`, byte-identical to the source in `./scripts/skill-locator/`; the locator finds the helper scripts from either lead and fails closed naming `at-setup`.
- Scripts have a shebang, run under `/bin/bash` 3.2, answer `--help` with exit 0 and stdin closed, and are invoked through their interpreter in the prose (`bash scripts/<name>`).

## Frontmatter

- `name` equals the directory and matches `^[a-z0-9]+(-[a-z0-9]+)*$`, 1–64 chars; Triforge workflows carry the `at-` prefix.
- `description`: a positive trigger (`Use when`, `Use for`, `Use only when`, `Use before`, `Use after`) within the first 150 characters, at most 300 characters, no `<` or `>`, no identity opener ("This skill…"), no slash-command or quoted-utterance catalog, no step list. A negative redirect names a sibling skill that exists. All shipped descriptions together stay under 4,000 characters: Codex lists every skill in one shared 8,000-character budget, and the `.agents/skills/` copies are the same text.
- Keys: `name`, `description`, `license`, `compatibility`, `metadata` (flat, keys `triforge-*` or `version`), plus `disable-model-invocation` and `argument-hint`. Anything else fails. Quote a value that contains `: ` or ` #`; spaces, never tabs.
- A skill with side effects (writes, dispatches, promotes) sets `disable-model-invocation: true` and ships `openai.yaml` under `agents/` with `policy.allow_implicit_invocation: false`; the two always agree.

## Portability

- No Claude-only interpolation anywhere in a skill or its references, fenced code included: a dollar-prefixed `ARGUMENTS` or numbered placeholder, a bang-backtick command, mustache braces, a bare `@path` include.
- No harness tool names outside `references/<harness>.md` — the capitalized Claude Code tool names, agy's and Codex's snake_case tool names, a bare shell-tool reference, a harness command line — where `<harness>` is `claude`, `codex`, `antigravity`, `agy`, `opencode`, `kimi`, `cursor`, `grok` or `devin`.
- Never branch on the lead's CLI name in shell: read a registry field or a capability (KTD1). The registry and roster lanes (`registry.sh`, `roster.sh`) are the only files that may.

## Validate

`bash ./scripts/validate-skills.sh` warns on the new rules and fails on the old ones; `--strict` fails on both and becomes the default in U23. `--self-test` runs the fixtures under `./scripts/fixtures/validate-skills/`, one scratch repo per rule with an `EXPECT` file: add or adjust a fixture whenever a rule changes. `skills-ref validate` runs when the binary is installed; until then its verdict on `disable-model-invocation` and `argument-hint` is pending.

## Output

- The changed skill, the `bash ./scripts/validate-skills.sh --strict` lines it produces (none, when done — with `./.claude/skills` named when the skill lives there), and a `--self-test` run that still reports every case OK.
