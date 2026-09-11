#!/usr/bin/env bash
# validate-skills.sh — structural checks for the shipped portable skills
# (U10 of the v3.3.0 plan: R15, AS-3/C1; KTD15 — structural assertions only).
#
# Usage:
#   bash scripts/validate-skills.sh [skills-dir]
#
#   skills-dir  Directory holding <name>/SKILL.md entries. Defaults to the
#               repo's skills/. Pass a scratch directory to validate fixtures.
#
# Per <dir>/<name>/SKILL.md the checks are:
#   - YAML frontmatter between the first two --- lines, parsed by a tiny
#     scanner (flat key: value pairs plus ONE level of nesting, block scalars
#     with > or |, and single- or multi-line quoted strings). No PyYAML.
#   - name equals the directory name and is kebab-case ^[a-z0-9][a-z0-9-]*$.
#   - description present, <= 1024 chars, and contains a NON-negated
#     "Use when" (case-sensitive; "Do not Use when" alone does not count).
#   - only name, description, license, compatibility, metadata at top level
#     (the agentskills.io portable shape; vendor fields live under metadata).
#     metadata is optional — today's skills carry name+description only; after
#     U11 they carry metadata.triforge-consumer / triforge-phase / version.
#   - every "## Step N:" heading forms the sequence 1..N in order (no gaps,
#     no repeats). Headings inside fenced code blocks are ignored.
#   - no relative markdown link that escapes the skill directory: ](../ or ](/
#   - a "## Output" section exists (a "## Output <suffix>" heading satisfies
#     the check but is reported as a warning — the convention is "## Output").
#   - WARN (never fail) when the file exceeds 500 lines.
#
# Output: one "file: reason" line per violation, "file: warning: reason" for
# warnings, then "validate-skills: N skills OK" on success.
# Exit codes: 0 all skills pass; 1 at least one violation; 2 usage error /
# no SKILL.md found.
set -euo pipefail
cd "$(dirname "$0")/.."

SKILLS_DIR="${1:-skills}"
if [ ! -d "$SKILLS_DIR" ]; then
  echo "validate-skills: ERROR skills directory not found: $SKILLS_DIR" >&2
  exit 2
fi

# Inputs cross into python as a prefixed env var, never interpolated.
VS_SKILLS_DIR="$SKILLS_DIR" python3 - <<'PYEOF'
import glob
import os
import re
import sys

skills_dir = os.environ["VS_SKILLS_DIR"]
ALLOWED_KEYS = ("name", "description", "license", "compatibility", "metadata")
KEBAB = re.compile(r"^[a-z0-9][a-z0-9-]*$")
STEP_HEADING = re.compile(r"^## Step (\d+):")
OUTPUT_HEADING = re.compile(r"^## Output(\s.*)?$")
ESCAPING_LINK = re.compile(r"\]\((?:\.\./|/)[^)]*\)")
# A "Use when" that is not immediately preceded by a negation word.
POSITIVE_USE_WHEN = re.compile(
    r"(?<!not )(?<!Not )(?<!NOT )(?<!never )(?<!Never )(?<!n't )Use when"
)
MAX_DESCRIPTION = 1024
WARN_LINES = 500
FENCE = chr(96) * 3  # three backticks


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ('"', "'"):
        inner = value[1:-1]
        if value[0] == '"':
            inner = inner.replace('\\"', '"').replace("\\\\", "\\")
        else:
            inner = inner.replace("''", "'")
        return inner
    # Unquoted scalar: drop a trailing YAML comment.
    return re.sub(r"\s+#.*$", "", value)


def quoted_is_closed(text):
    """True when a scalar that starts with a quote also ends with an unescaped one."""
    quote = text[0]
    if len(text) < 2 or not text.endswith(quote):
        return False
    if quote == '"' and text.endswith('\\"'):
        return False
    return True


def parse_frontmatter(lines, errs):
    """Return (mapping, index of first body line)."""
    if not lines or lines[0].strip() != "---":
        errs.append("missing YAML frontmatter (file must start with ---)")
        return {}, 0
    end = None
    for i in range(1, len(lines)):
        if lines[i].strip() == "---":
            end = i
            break
    if end is None:
        errs.append("unterminated YAML frontmatter (no closing ---)")
        return {}, len(lines)
    fm = lines[1:end]
    data = {}
    i = 0
    while i < len(fm):
        line = fm[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        m = re.match(r"^([A-Za-z0-9_-]+):(.*)$", line)
        if m:
            key, rest = m.group(1), m.group(2).strip()
            if key in data:
                errs.append("duplicate frontmatter key: " + key)
            if rest in (">", ">-", ">+", "|", "|-", "|+"):
                # Block scalar: consume the indented continuation lines.
                block = []
                i += 1
                while i < len(fm) and (not fm[i].strip() or fm[i][0] in " \t"):
                    block.append(fm[i].strip())
                    i += 1
                joiner = " " if rest[0] == ">" else "\n"
                data[key] = joiner.join(b for b in block if b)
                continue
            if rest == "":
                # One level of nesting: indented key: value lines.
                nested = {}
                i += 1
                while i < len(fm) and (not fm[i].strip() or fm[i][0] in " \t"):
                    item = fm[i].strip()
                    if item and not item.startswith("#"):
                        mm = re.match(r"^([A-Za-z0-9_.-]+):\s*(.*)$", item)
                        if mm:
                            nested[mm.group(1)] = unquote(mm.group(2))
                        else:
                            errs.append("unparseable nested line under " + key + ": " + item)
                    i += 1
                data[key] = nested
                continue
            if rest[0] in ('"', "'") and not quoted_is_closed(rest):
                # Quoted scalar continued on following lines.
                parts = [rest]
                i += 1
                while i < len(fm):
                    piece = fm[i].strip()
                    parts.append(piece)
                    i += 1
                    if piece.endswith(rest[0]) and quoted_is_closed(rest[0] + piece):
                        break
                data[key] = unquote(" ".join(parts))
                continue
            data[key] = unquote(rest)
            i += 1
            continue
        if line[0] in " \t":
            errs.append("indented frontmatter line outside a nested block: " + line.strip())
        else:
            errs.append("unparseable frontmatter line: " + line.strip())
        i += 1
    return data, end + 1


def check_skill(path):
    errs = []
    warns = []
    dirname = os.path.basename(os.path.dirname(path))
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.split("\n")
    line_count = len(lines) - 1 if text.endswith("\n") else len(lines)

    fm, body_start = parse_frontmatter(lines, errs)

    for key in fm:
        if key not in ALLOWED_KEYS:
            errs.append(
                "unexpected top-level frontmatter key '" + key
                + "' (allowed: " + ", ".join(ALLOWED_KEYS) + "; vendor fields go under metadata)"
            )

    name = fm.get("name")
    if not isinstance(name, str) or not name:
        errs.append("name missing")
    else:
        if name != dirname:
            errs.append("name '" + name + "' does not match directory '" + dirname + "'")
        if not KEBAB.match(name):
            errs.append("name '" + name + "' is not kebab-case ([a-z0-9][a-z0-9-]*)")

    desc = fm.get("description")
    if not isinstance(desc, str) or not desc.strip():
        errs.append("description missing or empty")
    else:
        if len(desc) > MAX_DESCRIPTION:
            errs.append("description is " + str(len(desc)) + " chars (max " + str(MAX_DESCRIPTION) + ")")
        if "Use when" not in desc:
            errs.append('description lacks the phrase "Use when"')
        elif not POSITIVE_USE_WHEN.search(desc):
            errs.append('description has only a negated "Use when"; state a positive trigger')

    if "metadata" in fm and not isinstance(fm["metadata"], dict):
        errs.append("metadata must be a nested mapping of key: value pairs")

    # Body scan: skip fenced code blocks for headings and links.
    step_numbers = []
    output_headings = []
    in_fence = False
    for idx in range(body_start, len(lines)):
        line = lines[idx]
        if line.lstrip().startswith(FENCE):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        m = STEP_HEADING.match(line)
        if m:
            step_numbers.append(int(m.group(1)))
        if OUTPUT_HEADING.match(line):
            output_headings.append(line.rstrip())
        for link in ESCAPING_LINK.finditer(line):
            errs.append(
                "line " + str(idx + 1) + ": relative link escapes the skill directory: " + link.group(0)
            )

    if step_numbers and step_numbers != list(range(1, len(step_numbers) + 1)):
        errs.append(
            "Step headings are not sequential from 1: found "
            + ", ".join(str(n) for n in step_numbers)
        )

    if not output_headings:
        errs.append('missing "## Output" section')
    elif not any(h == "## Output" for h in output_headings):
        warns.append('Output heading is "' + output_headings[0] + '"; convention is exactly "## Output"')

    if line_count > WARN_LINES:
        warns.append(str(line_count) + " lines (> " + str(WARN_LINES) + "; consider moving detail into references/)")

    return errs, warns


paths = sorted(glob.glob(os.path.join(skills_dir, "*", "SKILL.md")))
if not paths:
    sys.stderr.write("validate-skills: ERROR no */SKILL.md under " + skills_dir + "\n")
    sys.exit(2)

total_violations = 0
failing_skills = 0
for path in paths:
    errs, warns = check_skill(path)
    for w in warns:
        print(path + ": warning: " + w)
    for e in errs:
        print(path + ": " + e)
    if errs:
        failing_skills += 1
        total_violations += len(errs)

if total_violations:
    print(
        "validate-skills: FAIL (" + str(total_violations) + " violation(s) in "
        + str(failing_skills) + " of " + str(len(paths)) + " skills)"
    )
    sys.exit(1)
print("validate-skills: " + str(len(paths)) + " skills OK")
PYEOF
