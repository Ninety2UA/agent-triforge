#!/usr/bin/env bash
# validate-skills.sh — conformance checks for the shipped portable skills
# (U10 of the v3.3.0 plan: R15, AS-3/C1; U6 of the v4 plan: R15, R17, R19 and
# the KTD1 lead-name-branch gate; KTD15 — structural assertions only).
#
# Usage:
#   bash scripts/validate-skills.sh [--warn] [skills-dir]
#   bash scripts/validate-skills.sh [--warn] --fixture <dir>
#   bash scripts/validate-skills.sh --self-test
#
#   skills-dir   Directory holding <name>/SKILL.md entries. Defaults to the
#                repo's skills/. A positional override validates that tree's
#                skills only (the per-at-skill locator check needs the shipped
#                tree and prints a skip: line).
#   --warn       The relaxed run: the newer rules (C1, C3, C8–C18, C20–C24,
#                C26, KTD1, KTD6 and the newer parts of C4, C9, C14, C21) print
#                as warnings and do not fail the run. Without it every finding
#                is an error — the default since U23. --strict is accepted and
#                changes nothing.
#   --fixture    Treat <dir> as a scratch repo root: skills at <dir>/skills,
#                shell files at <dir>/scripts and <dir>/hooks, agent files at
#                <dir>/agents. Zero skills is allowed there (a fixture may hold
#                only shell files).
#   --self-test  Run every fixture under scripts/fixtures/validate-skills/
#                (each holds an EXPECT file: check, the rule's severity under
#                --warn, message substring) in both modes — default and --warn —
#                and assert the outcome, plus two computed cases (the C10
#                description-set budget and the C15 token guard). The cases run
#                in-process; the conforming fixture's runs also go through this
#                wrapper (no flag, --warn and the --strict no-op), so the flag
#                parsing and the exit code are exercised end to end. Exit 0
#                when every fixture behaves as named.
#
# The checks (ids follow ops/research/2026-09-27-repo-mining.md §3; "new" means
# a warning under --warn and an error otherwise; the rest FAIL in both modes):
#   C1   exactly one SKILL.md (uppercase) per skill directory          (new)
#   C2   frontmatter opens and closes with ---, top level is a mapping, no
#        duplicate keys, every line parseable
#   C3   strict-YAML subset: no tab indentation, no unclosed quote, no unquoted
#        value containing ': ' or ' #' or ending in ':', no unquoted leading
#        [ { & * !                                                     (new)
#   C4   name is ^[a-z0-9][a-z0-9-]*$ (always); 1–64 chars and
#        ^[a-z0-9]+(-[a-z0-9]+)*$ — no leading/trailing/double hyphen (new)
#   C5   name equals the directory name
#   C6   top-level keys ⊆ name, description, license, compatibility, metadata
#        plus the validator-owned exception list below (disable-model-invocation,
#        argument-hint — each with its reason); anything else fails. The two
#        exceptions are type-checked (boolean / non-empty string)      (new part)
#   C7   description present, non-empty, ≤ 1024 chars
#   C8   description contains no < or >                                 (new)
#   C9   a positive trigger (Use when | Use for | Use only when | Use before |
#        Use after) survives after dropping every negated clause (always); it
#        starts within the first 150 characters                        (new)
#   C10  description ≤ 300 chars; the SUM of the validated set's descriptions
#        ≤ 4,000 chars. The sum is counted once per shipped skill: the
#        .agents/skills/ copies are byte-identical, so Codex's shared
#        8,000-char list sees the same total from either path          (new)
#   C11  no identity opener (This skill | Use this skill | A skill), no
#        slash-command catalog (two or more /name tokens), no quoted-utterance
#        catalog (two or more "..." phrases), no workflow list (three or more
#        arrows or then/next/finally)                                   (new)
#   C12  a sibling redirect ("that is <x>", "use <x>", hyphenated x) names a
#        skill in the validated set                                    (new)
#   C13  compatibility, if present, is a string of 1–500 chars           (new)
#   C14  metadata is a mapping (always); flat (a deeper mapping is reported,
#        never silently flattened), keys triforge-* or version; license is a
#        string                                                        (new part)
#   C15  SKILL.md ≤ 8,000 bytes (CRLF-adjusted), with a shrink-only OVER_BUDGET
#        allowlist (name → ceiling; allowlisted and under its ceiling is a
#        note, over it a finding); notes at > 500 lines and > 20,000 chars
#        (≈ 5,000 tokens)                                               (new)
#   C16  every body scan honors CommonMark fences: ``` and ~~~, closer at
#        least as long as the opener, 0–3 spaces of indent, an unterminated
#        fence runs to EOF (infrastructure; proven by a fixture)
#   C17  no Claude-only interpolation in SKILL.md or references/*.md, fences
#        included: $ARGUMENTS, $N, !`cmd`, {{var}}, a bare @path include (an
#        @ at a token start followed by a path with a / or a file suffix), and
#        a bare ${CLAUDE_PLUGIN_ROOT} — bare = $CLAUDE_PLUGIN_ROOT or
#        ${CLAUDE_PLUGIN_ROOT} with no :- := - = :? ? operator inside the
#        braces (also scanned in scripts/*)                            (new)
#   C18  no harness-private tool names outside references/<harness>.md
#        (harness ∈ claude, claude-code, codex, antigravity, agy, opencode,
#        kimi, cursor, grok, devin): a Claude tool name in backticks, as
#        "<Name> tool", or in a comma list of three; the snake_case agy/Codex
#        tool names anywhere; `shell` / "shell tool"; "codex exec"; "agy" with
#        an argument                                                   (new)
#   C19  a "## Output" section exists (a suffixed heading is a note); every
#        "## Step N:" heading forms 1..N in order
#   C20  skill directory entries ⊆ SKILL.md, references/, scripts/, assets/,
#        agents/ (README/CHANGELOG/INSTALL named); no empty subdirectory;
#        supporting .md names kebab-case                               (new)
#   C21  a relative link never escapes the skill (](../ and ](/ — always); it
#        and every backticked references/ scripts/ assets/ agents/ path resolve
#        inside the skill; no ~ path. A ./-prefixed path is a working-directory
#        path and is not checked                                       (new part)
#   C22  references are one level deep (a references/*.md links no skill-local
#        .md); every references/ file is named from SKILL.md; a reference over
#        100 lines carries a TOC (note)                                (new)
#   C23  scripts/*: a shebang; bash -n clean and no bash-4 features (declare -A,
#        mapfile, readarray, ${x,,} ${x^^}, |&, ;;& ;&); --help exits 0 with
#        stdin from /dev/null within 10 s; every command-position mention of
#        scripts/<file> in the prose carries its interpreter          (new)
#   C24  agents/openai.yaml, if present: keys ⊆ interface, policy,
#        dependencies; interface strings quoted; short_description 25–64
#        chars; default_prompt contains $<name>; dependencies.tools[].type ∈
#        mcp, cli; icon paths exist; policy.allow_implicit_invocation: false
#        ⇔ SKILL.md disable-model-invocation: true                     (new)
#   C25  --self-test: one fixture per rule under scripts/fixtures/validate-skills/
#   C26  C3 and C17 over agents/*.md ($ARGUMENTS and $N: an agent takes no
#        interpolation)                                                 (new)
#   KTD1 lead-name-branch gate over scripts/**/*.sh, scripts/lease-git-hooks/*,
#        hooks/**/*.sh and skills/*/scripts/* — except scripts/lib/registry.sh,
#        scripts/lib/roster.sh, this file and scripts/fixtures/. A lead token
#        is resolve_lead, lead_cli, LEAD_CLI or [lead], plus any variable
#        assigned from a line carrying one (NAME=... or read NAME <<< ...). A
#        non-comment line fails when it is a `case` whose subject carries a
#        lead token, or a [ ]/[[ ]]/test comparison (= == != =~) between an
#        operand carrying a lead token and a literal codex or claude. Worker-
#        lane arms (`codex)` under a `case "$CLI"`) are not touched   (new)
#   KTD6 every skills/at-*/scripts/ holds every file of the shared locator
#        source byte-identical — scripts/skill-locator/ (U5), or the plan's
#        skills/_shared-locator/; a missing source prints a skip: line. Every
#        locate-triforge.sh call in an at- skill's SKILL.md or references/*.md
#        (bash/sh/source/exec/env + path, $(path), . path) carries the
#        skill-directory anchor $SKILL_DIR/ or ${SKILL_DIR}/: a cwd-relative
#        call runs a project's own scripts/locate-triforge.sh (CWE-427)   (new)
#   SREF `skills-ref validate <skill>` runs when the binary is on PATH (its
#        verdict on disable-model-invocation / argument-hint is pending until
#        then); otherwise a skip: line
#
# Output: one "file: [ID] reason" line per violation, "file: warning: [ID]
# reason" per warning, "file: note: [ID] reason" per advisory note, "skip:"
# lines for checks that could not run, then the summary:
#   validate-skills: N skills OK
#   validate-skills: N skills OK (--warn)
#   validate-skills: N skills OK (--warn: W warning(s) the default run fails on)
#   validate-skills: FAIL (V violation(s) in K of N skills[ and M other file(s)])
# Exit codes: 0 pass; 1 at least one violation; 2 usage error / no SKILL.md
# found outside fixture mode.
set -euo pipefail
ORIG_PWD="$PWD"
cd "$(dirname "$0")/.."

STRICT=1
FIXTURE=""
SELF_TEST=0
SKILLS_DIR=""
usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --strict)    STRICT=1 ;;   # the default since U23; kept so older call sites still parse
    --warn)      STRICT=0 ;;
    --self-test) SELF_TEST=1 ;;
    --fixture)
      shift
      [ $# -gt 0 ] || { echo "validate-skills: ERROR --fixture needs a directory" >&2; exit 2; }
      FIXTURE=$(cd "$ORIG_PWD" && cd "$1" 2>/dev/null && pwd -P) \
        || { echo "validate-skills: ERROR fixture directory not found: $1" >&2; exit 2; }
      ;;
    -h|--help) usage; exit 0 ;;
    -*)
      echo "validate-skills: unknown flag '$1' (accepted: --warn --strict --fixture <dir> --self-test)" >&2
      exit 2 ;;
    *) SKILLS_DIR="$1" ;;
  esac
  shift
done
if [ -n "$SKILLS_DIR" ] && [ -z "$FIXTURE" ] && [ ! -d "$SKILLS_DIR" ]; then
  echo "validate-skills: ERROR skills directory not found: $SKILLS_DIR" >&2
  exit 2
fi

# Inputs cross into python as prefixed env vars, never interpolated.
VS_STRICT="$STRICT" VS_FIXTURE="$FIXTURE" VS_SELF_TEST="$SELF_TEST" \
VS_SKILLS_DIR="$SKILLS_DIR" VS_SCRIPT="$PWD/scripts/validate-skills.sh" \
python3 - <<'PYEOF'
import contextlib
import glob
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile

STRICT = os.environ.get("VS_STRICT") == "1"
FIXTURE = os.environ.get("VS_FIXTURE", "")
SELF_TEST = os.environ.get("VS_SELF_TEST") == "1"
SKILLS_DIR_ARG = os.environ.get("VS_SKILLS_DIR", "")
SCRIPT = os.environ["VS_SCRIPT"]
REPO = os.getcwd()
ROOT = FIXTURE or REPO
BASH = "/bin/bash" if os.path.exists("/bin/bash") else "bash"

# --- constants -----------------------------------------------------------------
ALLOWED_KEYS = ("name", "description", "license", "compatibility", "metadata")
# Validator-owned exception list (C6): key -> why it is allowed at top level.
EXCEPTION_KEYS = {
    "disable-model-invocation": "Claude Code: side-effect skills opt out of auto-invocation; "
    "mirrored by agents/openai.yaml policy.allow_implicit_invocation: false (C24)",
    "argument-hint": "Claude Code autocomplete hint (compound-engineering convention); other hosts ignore it",
}
KEBAB_LOOSE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
KEBAB_STRICT = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
STEP_HEADING = re.compile(r"^## Step (\d+):")
OUTPUT_HEADING = re.compile(r"^## Output(\s.*)?$")
ESCAPING_LINK = re.compile(r"\]\((?:\.\./|/)[^)]*\)")
MD_LINK = re.compile(r"\]\(<?([^)\s>]+)>?\)")
BACKTICK_SPAN = re.compile(r"`([^`]+)`")
LOCAL_PATH =re.compile(r"(?<![\w/.-])((?:references|scripts|assets|agents)/[A-Za-z0-9_./-]+)")
TRIGGER = re.compile(r"\bUse (?:only when|when|for|before|after)\b")
NEGATED_CLAUSE = re.compile(r"^\s*(?:Not\b|Do not\b|Don't\b|Never\b|Avoid\b|Also not\b)|\b(?:not|never|don't|do not)\s+(?:use|for)\b", re.I)
IDENTITY_OPENER = re.compile(r"^(?:This skill|Use this skill|A skill)\b")
SLASH_NAME = re.compile(r"(?<![\w./])/[a-z][a-z0-9-]+\b(?![/.\w])")
QUOTED_PHRASE = re.compile(r'"[^"]{2,}"')
WORKFLOW_WORD = re.compile(r"\b(?:then|next|finally)\b", re.I)
REDIRECT = re.compile(r"\b(?:that is (?:the )?|[Uu]se )([a-z0-9]+(?:-[a-z0-9]+)+)")
METADATA_KEY = re.compile(r"^(?:triforge-[a-z0-9-]+|version)$")
MAX_DESCRIPTION = 1024
WARN_DESCRIPTION = 300
TRIGGER_WINDOW = 150
SET_BUDGET = 4000
MAX_BYTES = 8000
NOTE_LINES = 500
NOTE_CHARS = 20000  # ≈ 5,000 tokens
# Shrink-only allowlist for C15: a listed skill may stay over 8,000 bytes while
# it is at or under its recorded ceiling (the size when the cap landed).
OVER_BUDGET = {}
ALLOWED_ENTRIES = ("SKILL.md", "references", "scripts", "assets", "agents")
HARNESS_NAMES = ("claude", "claude-code", "codex", "antigravity", "agy", "opencode", "kimi", "cursor", "grok", "devin")
CLAUDE_TOOLS = ("Read", "Edit", "MultiEdit", "Write", "Bash", "Grep", "Glob", "WebFetch", "WebSearch",
                "Agent", "Task", "TodoWrite", "NotebookEdit", "AskUserQuestion", "EnterPlanMode", "Skill")
_alts = "|".join(CLAUDE_TOOLS)
TOOL_BACKTICKED = re.compile(r"`(?:" + _alts + r")`")
TOOL_WORD = re.compile(r"\b(?:" + _alts + r") tool\b")
TOOL_LIST = re.compile(r"\b(?:" + _alts + r")(?:,\s*(?:" + _alts + r")\b){2,}")
SNAKE_TOOLS = re.compile(r"\b(?:view_file|list_dir|find_by_name|grep_search|write_to_file|run_command|"
                         r"read_url_content|search_web|exec_command|apply_patch|spawn_agent|update_plan)\b")
SHELL_TOOL = re.compile(r"`shell`|\bshell tool\b")
HARNESS_CMD = re.compile(r"\bcodex exec\b|\bagy\s+(?:-{1,2}[a-z]|plugin\b|agents\b)")
ARGUMENTS = re.compile(r"\$\{?ARGUMENTS\b")
POSITIONAL = re.compile(r"\$[1-9][0-9]*\b")
BANG_CMD = re.compile(r"!`[^`]+`")
MUSTACHE = re.compile(r"\{\{[^}]+\}\}")
AT_INCLUDE = re.compile(r"(?:^|(?<=\s))@(?:[\w.-]*/[\w./-]+|[\w-]+\.(?:md|txt|json|toml|yaml|yml|sh|py))\b")
BARE_PLUGIN_ROOT = re.compile(r"\$CLAUDE_PLUGIN_ROOT\b|\$\{CLAUDE_PLUGIN_ROOT\}")
BASH4 = re.compile(r"\bdeclare\s+-[a-zA-Z]*A|\bmapfile\b|\breadarray\b|\$\{[A-Za-z_][A-Za-z0-9_]*(?:,,|\^\^)|\|&|;;&|;&(?!&)")
LEAD_TOKEN = re.compile(r"\bresolve_lead\b|\blead_cli\b|\bLEAD_CLI\b|\[lead\]")
ASSIGN = re.compile(r"^\s*(?:local\s+|declare\s+(?:-\w+\s+)*|readonly\s+|export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
READ_INTO = re.compile(r"\bread\b(?:\s+-\w+)*\s+([A-Za-z_][A-Za-z0-9_ ]*?)\s*(?:<<<|<\s*<\()(.*)$")
CASE_LINE = re.compile(r"^\s*case\s+(.+?)\s+in\b")
COMPARISON = re.compile(r"(?:\[\[?|\btest\b)\s+(?P<left>.+?)\s+(?P<op>==?|!=|=~)\s+(?P<right>.+?)(?:\s+\]\]?|\s*(?:;|&&|\|\||$))")
LEAD_LITERAL = re.compile(r"""^["']?(?:codex|claude)\*?["']?$""")
FENCE_OPEN = re.compile(r"^( {0,3})(`{3,}|~{3,})(.*)$")

# --- findings ------------------------------------------------------------------
F = []      # (severity, path, id, message)
SKIPS = []


def rel(path):
    base = FIXTURE if FIXTURE else REPO
    try:
        r = os.path.relpath(path, base)
    except ValueError:
        return path
    return path if r.startswith("..") else r


def err(path, cid, msg):
    F.append(("error", rel(path), cid, msg))


def new(path, cid, msg):
    F.append(("error" if STRICT else "warning", rel(path), cid, msg))


def note(path, cid, msg):
    F.append(("note", rel(path), cid, msg))


# --- YAML subset ---------------------------------------------------------------
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


def quoted_continuation(fm, i, quote):
    """A quoted scalar opened on fm[i] did not close there: consume the
    continuation lines. Return (closed, next_i, pieces) — whether a closing
    quote was found, the index after the consumed lines, the stripped lines."""
    pieces = []
    closed = False
    i += 1
    while i < len(fm):
        piece = fm[i].strip()
        pieces.append(piece)
        i += 1
        if quoted_is_closed(quote + piece):
            closed = True
            break
    return closed, i, pieces


def parse_frontmatter(lines, errs, info):
    """Return (mapping, index of first body line). errs collects C2 messages;
    info gets 'deep' (parent key -> child keys nested one level too far),
    'unclosed' (keys whose quoted scalar never closes) and 'fm' (raw lines)."""
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
    info["fm"] = fm
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
                # One level of nesting: indented key: value lines. A deeper
                # level is recorded for C14 instead of being flattened.
                nested = {}
                base_indent = None
                last_key = None
                i += 1
                while i < len(fm) and (not fm[i].strip() or fm[i][0] in " \t"):
                    raw = fm[i]
                    item = raw.strip()
                    if item and not item.startswith("#"):
                        indent = len(raw) - len(raw.lstrip())
                        if base_indent is None:
                            base_indent = indent
                        if indent > base_indent and last_key is not None:
                            info.setdefault("deep", {}).setdefault(key, []).append(last_key)
                        else:
                            mm = re.match(r"^([A-Za-z0-9_.-]+):\s*(.*)$", item)
                            if mm:
                                nested[mm.group(1)] = unquote(mm.group(2))
                                last_key = mm.group(1)
                            else:
                                errs.append("unparseable nested line under " + key + ": " + item)
                    i += 1
                data[key] = nested
                continue
            if rest[0] in ('"', "'") and not quoted_is_closed(rest):
                # Quoted scalar continued on following lines.
                closed, i, pieces = quoted_continuation(fm, i, rest[0])
                parts = [rest] + pieces
                if not closed:
                    info.setdefault("unclosed", []).append(key)
                    parts[-1] = parts[-1] + rest[0]
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


def strict_yaml_issues(fm):
    """C3 over raw frontmatter lines (skills and agents alike)."""
    issues = []
    i = 0
    while i < len(fm):
        line = fm[i]
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            i += 1
            continue
        lead = line[:len(line) - len(line.lstrip())]
        if "\t" in lead:
            issues.append("tab indentation at frontmatter line " + str(i + 1) + " (spaces only)")
        indent = len(lead)
        m = re.match(r"^\s*(?:-\s+)?([A-Za-z0-9_.-]+):(.*)$", line)
        if m:
            label, rest = m.group(1), m.group(2).strip()
        else:
            m2 = re.match(r"^\s*-\s+(.*)$", line)
            if not m2:
                i += 1
                continue
            label, rest = "list item", m2.group(1).strip()
        if rest in (">", ">-", ">+", "|", "|-", "|+"):
            i += 1
            while i < len(fm) and (not fm[i].strip() or len(fm[i]) - len(fm[i].lstrip()) > indent):
                i += 1
            continue
        if rest and rest[0] in ('"', "'"):
            if not quoted_is_closed(rest):
                closed, i, _ = quoted_continuation(fm, i, rest[0])
                if not closed:
                    issues.append("unclosed quote: " + label)
                continue
            i += 1
            continue
        if rest:
            if rest[0] in "[{&*!":
                issues.append("unquoted value starts with '" + rest[0] + "' (flow, anchor or tag syntax) — quote it: " + label)
            if ": " in rest:
                issues.append("unquoted value contains ': ' — quote it: " + label)
            if " #" in rest:
                issues.append("unquoted value contains ' #' — quote it: " + label)
            if rest.endswith(":"):
                issues.append("unquoted value ends with ':' — quote it: " + label)
        i += 1
    return issues


def parse_simple_yaml(text):
    """Mappings, lists (of scalars or mappings) and scalars; a scalar is
    (value, was_quoted). Enough for agents/openai.yaml; raises ValueError."""
    items = []
    for raw in text.split("\n"):
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        items.append([len(raw) - len(raw.lstrip()), raw.strip()])

    def scalar(s):
        s = s.strip()
        quoted = len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'")
        return (unquote(s), quoted)

    def block(pos, indent):
        if pos < len(items) and items[pos][1].startswith("- "):
            lst = []
            while pos < len(items) and items[pos][0] == indent and items[pos][1].startswith("- "):
                inner = items[pos][1][2:].strip()
                if re.match(r"^[A-Za-z0-9_.-]+:(\s|$)", inner):
                    items[pos] = [indent + 2, inner]
                    obj, pos = block(pos, indent + 2)
                    lst.append(obj)
                else:
                    lst.append(scalar(inner))
                    pos += 1
            return lst, pos
        mapping = {}
        while pos < len(items) and items[pos][0] == indent:
            m = re.match(r"^([A-Za-z0-9_.-]+):(.*)$", items[pos][1])
            if not m:
                raise ValueError("unparseable line: " + items[pos][1])
            key, rest = m.group(1), m.group(2).strip()
            if rest == "":
                if pos + 1 < len(items) and items[pos + 1][0] > indent:
                    child, pos = block(pos + 1, items[pos + 1][0])
                    mapping[key] = child
                else:
                    mapping[key] = ("", False)
                    pos += 1
            else:
                mapping[key] = scalar(rest)
                pos += 1
        if pos < len(items) and items[pos][0] > indent:
            raise ValueError("unexpected indentation: " + items[pos][1])
        return mapping, pos

    if not items:
        return {}
    obj, pos = block(0, items[0][0])
    if pos < len(items):
        raise ValueError("unexpected line: " + items[pos][1])
    return obj


# --- body helpers --------------------------------------------------------------
def body_lines(lines, start):
    """Yield (index, line, in_fence) honoring CommonMark fences (C16)."""
    fence_char = None
    fence_len = 0
    for idx in range(start, len(lines)):
        line = lines[idx]
        if fence_char is None:
            m = FENCE_OPEN.match(line)
            if m and not (m.group(2)[0] == "`" and "`" in m.group(3)):
                fence_char, fence_len = m.group(2)[0], len(m.group(2))
                yield idx, line, True
                continue
            yield idx, line, False
        else:
            m = re.match(r"^ {0,3}(" + re.escape(fence_char) + r"{3,})\s*$", line)
            if m and len(m.group(1)) >= fence_len:
                fence_char = None
            yield idx, line, True


def trigger_position(desc):
    """Index of the first positive trigger outside a negated clause, else -1."""
    pos = 0
    for clause in re.split(r"(?<=[.;])", desc):
        if clause and not NEGATED_CLAUSE.search(clause):
            m = TRIGGER.search(clause)
            if m:
                return pos + m.start()
        pos += len(clause)
    return -1


def interpolation_hits(line, forms):
    hits = []
    if "arguments" in forms and ARGUMENTS.search(line):
        hits.append("$ARGUMENTS")
    if "positional" in forms and POSITIONAL.search(line):
        hits.append(POSITIONAL.search(line).group(0))
    if "bang" in forms and BANG_CMD.search(line):
        hits.append("!`cmd`")
    if "mustache" in forms and MUSTACHE.search(line):
        hits.append(MUSTACHE.search(line).group(0))
    if "at" in forms and AT_INCLUDE.search(line):
        hits.append(AT_INCLUDE.search(line).group(0).strip())
    if "plugin-root" in forms and BARE_PLUGIN_ROOT.search(line):
        hits.append(BARE_PLUGIN_ROOT.search(line).group(0) + " without a fallback")
    return hits


def tool_name_hits(line):
    hits = []
    for rx in (TOOL_BACKTICKED, TOOL_WORD, TOOL_LIST, SNAKE_TOOLS, SHELL_TOOL, HARNESS_CMD):
        m = rx.search(line)
        if m:
            hits.append(m.group(0))
    return hits


def is_harness_reference(relpath):
    base = os.path.basename(relpath)
    return relpath.startswith("references/") and base[:-3] in HARNESS_NAMES if base.endswith(".md") else False


def read_text(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


# --- per-skill checks ----------------------------------------------------------
def check_skill(skill_dir, sibling_names):
    """Append findings for one skill directory; return the description (for C10)."""
    dirname = os.path.basename(skill_dir)
    path = os.path.join(skill_dir, "SKILL.md")
    errs = []
    info = {}
    text = read_text(path)
    lines = text.split("\n")
    line_count = len(lines) - 1 if text.endswith("\n") else len(lines)

    fm, body_start = parse_frontmatter(lines, errs, info)
    for e in errs:
        err(path, "C02", e)
    for e in strict_yaml_issues(info.get("fm", [])):
        new(path, "C03", e)
    for key in info.get("unclosed", []):
        new(path, "C03", "unclosed quote: " + key)

    # C6 — allowed keys plus the exception list.
    allowed_all = ALLOWED_KEYS + tuple(EXCEPTION_KEYS)
    for key in fm:
        if key not in allowed_all:
            err(path, "C06", "unexpected top-level frontmatter key '" + key + "' (allowed: "
                + ", ".join(allowed_all) + "; vendor fields go under metadata)")
    dmi = fm.get("disable-model-invocation")
    if dmi is not None and dmi not in ("true", "false"):
        new(path, "C06", "disable-model-invocation must be true or false, got '" + str(dmi) + "'")
    hint = fm.get("argument-hint")
    if hint is not None and (not isinstance(hint, str) or not hint.strip()):
        new(path, "C06", "argument-hint must be a non-empty string")

    # C4 / C5 — name.
    name = fm.get("name")
    if not isinstance(name, str) or not name:
        err(path, "C04", "name missing")
    else:
        if name != dirname:
            err(path, "C05", "name '" + name + "' does not match directory '" + dirname + "'")
        if not KEBAB_LOOSE.match(name):
            err(path, "C04", "name '" + name + "' is not kebab-case ([a-z0-9][a-z0-9-]*)")
        elif not KEBAB_STRICT.match(name) or len(name) > 64:
            new(path, "C04", "name '" + name + "' violates ^[a-z0-9]+(-[a-z0-9]+)*$ with 1–64 chars "
                "(no leading, trailing or double hyphen)")

    # C7 – C12 — description.
    desc = fm.get("description")
    if not isinstance(desc, str) or not desc.strip():
        err(path, "C07", "description missing or empty")
        desc = ""
    else:
        if len(desc) > MAX_DESCRIPTION:
            err(path, "C07", "description is " + str(len(desc)) + " chars (max " + str(MAX_DESCRIPTION) + ")")
        if "<" in desc or ">" in desc:
            new(path, "C08", "description contains '<' or '>' (Codex rejects angle brackets)")
        tpos = trigger_position(desc)
        if tpos < 0:
            if TRIGGER.search(desc):
                err(path, "C09", 'description has only a negated trigger ("Use when" and the like); state a positive one')
            else:
                err(path, "C09", 'description lacks a positive trigger ("Use when", "Use for", "Use only when", "Use before", "Use after")')
        elif tpos >= TRIGGER_WINDOW:
            new(path, "C09", "trigger starts at char " + str(tpos) + " (must start within the first "
                + str(TRIGGER_WINDOW) + "; lead with the trigger, not the mechanism)")
        if len(desc) > WARN_DESCRIPTION:
            new(path, "C10", "description is " + str(len(desc)) + " chars (keep it ≤ " + str(WARN_DESCRIPTION)
                + "; the set budget is " + str(SET_BUDGET) + ")")
        if IDENTITY_OPENER.match(desc):
            new(path, "C11", "description opens with an identity phrase (This skill / Use this skill / A skill); start with the mechanism or the trigger")
        if len(SLASH_NAME.findall(desc)) >= 2:
            new(path, "C11", "description lists slash commands (/name catalog); describe the trigger instead")
        if len(QUOTED_PHRASE.findall(desc)) >= 2:
            new(path, "C11", "description catalogs quoted utterances; describe the trigger instead")
        if desc.count("→") + desc.count("->") >= 3 or len(WORKFLOW_WORD.findall(desc)) >= 3:
            new(path, "C11", "description reads as a workflow list (arrows or then/next/finally); state what and when, not the steps")
        for target in REDIRECT.findall(desc):
            if target not in sibling_names:
                new(path, "C12", "redirect names '" + target + "', which is not a skill in this set")

    # C13 / C14 — compatibility, license, metadata.
    compat = fm.get("compatibility")
    if compat is not None and (not isinstance(compat, str) or not 1 <= len(compat) <= 500):
        new(path, "C13", "compatibility must be a string of 1–500 chars")
    lic = fm.get("license")
    if lic is not None and (not isinstance(lic, str) or not lic.strip()):
        new(path, "C14", "license must be a non-empty string")
    if "metadata" in fm:
        if not isinstance(fm["metadata"], dict):
            err(path, "C14", "metadata must be a nested mapping of key: value pairs")
        else:
            deep = info.get("deep", {}).get("metadata")
            if deep:
                new(path, "C14", "metadata is not flat: a deeper mapping under '" + deep[0] + "'")
            else:
                for k in fm["metadata"]:
                    if not METADATA_KEY.match(k):
                        new(path, "C14", "metadata key '" + k + "' is not triforge-* or version")

    # C15 — size.
    nbytes = len(text.replace("\r\n", "\n").encode("utf-8"))
    if nbytes > MAX_BYTES:
        ceiling = OVER_BUDGET.get(dirname)
        if ceiling is not None and nbytes <= ceiling:
            note(path, "C15", str(nbytes) + " bytes over the " + str(MAX_BYTES)
                 + "-byte cap — allowlisted in OVER_BUDGET (shrink-only ceiling " + str(ceiling) + ")")
        elif ceiling is not None:
            new(path, "C15", str(nbytes) + " bytes — grew past its OVER_BUDGET ceiling of " + str(ceiling)
                + " (the cap is " + str(MAX_BYTES) + "; the allowlist only shrinks)")
        else:
            new(path, "C15", str(nbytes) + " bytes (max " + str(MAX_BYTES) + "; move detail into references/)")
    if line_count > NOTE_LINES:
        note(path, "C15", str(line_count) + " lines (> " + str(NOTE_LINES) + "; consider moving detail into references/)")
    if len(text) > NOTE_CHARS:
        note(path, "C15", str(len(text)) + " chars (> " + str(NOTE_CHARS) + " ≈ 5,000 tokens; Claude Code compaction keeps the first 5,000)")

    # Body scan (C17, C18, C19, C21), fences honored where the rule says so.
    step_numbers = []
    output_headings = []
    skill_text_paths = set()
    for idx, line, in_fence in body_lines(lines, body_start):
        lineno = str(idx + 1)
        for hit in interpolation_hits(line, ("arguments", "positional", "bang", "mustache", "at", "plugin-root")):
            new(path, "C17", "line " + lineno + ": Claude-only interpolation " + hit)
        for hit in tool_name_hits(line):
            new(path, "C18", "line " + lineno + ": harness-private tool name '" + hit
                + "' (allowed only in references/<harness>.md)")
        # C21 looks at code: backticked spans in prose, whole lines in a fence.
        spans = [line] if in_fence else [s.group(1) for s in BACKTICK_SPAN.finditer(line)]
        for span in spans:
            for m in LOCAL_PATH.finditer(span):
                skill_text_paths.add(m.group(1))
        if in_fence:
            continue
        m = STEP_HEADING.match(line)
        if m:
            step_numbers.append(int(m.group(1)))
        if OUTPUT_HEADING.match(line):
            output_headings.append(line.rstrip())
        for link in ESCAPING_LINK.finditer(line):
            err(path, "C21", "line " + lineno + ": relative link escapes the skill directory: " + link.group(0))
        for m in MD_LINK.finditer(line):
            target = m.group(1)
            if re.match(r"^(?:[a-z]+:|#)", target) or target.startswith(("../", "/")):
                continue
            if target.startswith("~"):
                new(path, "C21", "line " + lineno + ": link uses a ~ path: " + target)
                continue
            target = target.split("#", 1)[0]
            if target and not os.path.exists(os.path.join(skill_dir, target)):
                new(path, "C21", "line " + lineno + ": link target does not exist in the skill: " + target)
    for p in sorted(skill_text_paths):
        if any(ch in p for ch in "*<>") or p.endswith("/"):
            continue
        if "/../" in p or not os.path.exists(os.path.join(skill_dir, p)):
            new(path, "C21", "backticked skill-local path does not resolve inside the skill: " + p)

    if step_numbers and step_numbers != list(range(1, len(step_numbers) + 1)):
        err(path, "C19", "Step headings are not sequential from 1: found " + ", ".join(str(n) for n in step_numbers))
    if not output_headings:
        err(path, "C19", 'missing "## Output" section')
    elif not any(h == "## Output" for h in output_headings):
        note(path, "C19", 'Output heading is "' + output_headings[0] + '"; convention is exactly "## Output"')

    # C20 — layout.
    for entry in sorted(os.listdir(skill_dir)):
        if entry.startswith("."):
            continue
        full = os.path.join(skill_dir, entry)
        if entry not in ALLOWED_ENTRIES:
            upper = entry.upper()
            kind = " (README/CHANGELOG/INSTALL belong in the repo, not the skill)" if upper.startswith(("README", "CHANGELOG", "INSTALL")) else ""
            new(path, "C20", "unexpected entry '" + entry + "' (allowed: SKILL.md, references/, scripts/, assets/, agents/)" + kind)
        elif entry != "SKILL.md" and not os.path.isdir(full):
            new(path, "C20", "'" + entry + "' must be a directory")
    for sub, dirs, files in os.walk(skill_dir):
        if sub == skill_dir:
            continue
        visible = [f for f in files if not f.startswith(".")]
        if not visible and not dirs:
            new(path, "C20", "empty subdirectory: " + os.path.relpath(sub, skill_dir) + "/")
        for f in visible:
            if f.endswith(".md") and not re.match(r"^[a-z0-9]+(-[a-z0-9]+)*\.md$", f):
                new(path, "C20", "supporting file name is not kebab-case: " + os.path.relpath(os.path.join(sub, f), skill_dir))

    # C17 / C18 / C22 — references.
    refs_dir = os.path.join(skill_dir, "references")
    if os.path.isdir(refs_dir):
        for sub, dirs, files in os.walk(refs_dir):
            for f in sorted(files):
                if f.startswith("."):
                    continue
                ref_path = os.path.join(sub, f)
                ref_rel = os.path.relpath(ref_path, skill_dir)
                if ref_rel not in skill_text_paths and ref_rel not in text:
                    new(path, "C22", "orphan reference: " + ref_rel + " is not named from SKILL.md")
                if not f.endswith(".md"):
                    continue
                ref_text = read_text(ref_path)
                ref_lines = ref_text.split("\n")
                harness = is_harness_reference(ref_rel)
                for idx, line, in_fence in body_lines(ref_lines, 0):
                    lineno = str(idx + 1)
                    for hit in interpolation_hits(line, ("arguments", "positional", "bang", "mustache", "at", "plugin-root")):
                        new(ref_path, "C17", "line " + lineno + ": Claude-only interpolation " + hit)
                    if not harness:
                        for hit in tool_name_hits(line):
                            new(ref_path, "C18", "line " + lineno + ": harness-private tool name '" + hit
                                + "' (allowed only in references/<harness>.md)")
                    if in_fence:
                        continue
                    for m in MD_LINK.finditer(line):
                        target = m.group(1).split("#", 1)[0]
                        if target.endswith(".md") and not re.match(r"^[a-z]+:", target):
                            new(ref_path, "C22", "line " + lineno + ": a reference links another skill-local .md ("
                                + target + "); references are one level deep")
                            break
                    else:
                        for m in LOCAL_PATH.finditer(line):
                            if m.group(1).endswith(".md"):
                                new(ref_path, "C22", "line " + lineno + ": a reference names another skill-local .md ("
                                    + m.group(1) + "); references are one level deep")
                                break
                nlines = len(ref_lines) - 1 if ref_text.endswith("\n") else len(ref_lines)
                if nlines > 100 and not (re.search(r"(?im)^#+ .*(contents|table of contents|toc)\b", ref_text)
                                         or ref_text.count("](#") >= 3):
                    note(ref_path, "C22", str(nlines) + " lines without a table of contents")

    # C17 (plugin root) / C23 — scripts.
    scripts_dir = os.path.join(skill_dir, "scripts")
    if os.path.isdir(scripts_dir):
        for f in sorted(os.listdir(scripts_dir)):
            sp = os.path.join(scripts_dir, f)
            if f.startswith(".") or not os.path.isfile(sp):
                continue
            s_text = read_text(sp)
            s_lines = s_text.split("\n")
            for i, line in enumerate(s_lines):
                for hit in interpolation_hits(line, ("plugin-root",)):
                    new(sp, "C17", "line " + str(i + 1) + ": " + hit)
            shebang = s_lines[0] if s_lines and s_lines[0].startswith("#!") else ""
            if not shebang:
                new(sp, "C23", "no shebang on line 1")
            if f.endswith(".sh") or "bash" in shebang or shebang.endswith("sh"):
                rc = subprocess.run([BASH, "-n", sp], capture_output=True, text=True)
                if rc.returncode != 0:
                    new(sp, "C23", "bash -n failed: " + (rc.stderr.strip().split("\n")[0] if rc.stderr else "rc " + str(rc.returncode)))
                for i, line in enumerate(s_lines):
                    if line.lstrip().startswith("#"):
                        continue
                    m = BASH4.search(line)
                    if m:
                        new(sp, "C23", "line " + str(i + 1) + ": bash-4 feature '" + m.group(0).strip() + "' (hooks and helpers run under bash 3.2)")
            interp = None
            if "bash" in shebang or shebang.endswith("/sh") or shebang.endswith(" sh"):
                interp = [BASH]
            elif "python" in shebang:
                interp = ["python3"]
            if interp:
                try:
                    run = subprocess.run(interp + [sp, "--help"], stdin=subprocess.DEVNULL, capture_output=True,
                                         text=True, timeout=10, cwd=skill_dir)
                    if run.returncode != 0:
                        new(sp, "C23", "--help exited " + str(run.returncode) + " (must exit 0 with stdin from /dev/null)")
                except subprocess.TimeoutExpired:
                    new(sp, "C23", "--help did not exit within 10 s (scripts must be non-interactive)")
            # Prose invocation: a command-position mention must carry its interpreter.
            mention = re.compile(r"(?<![\w/`\[(.-])(?:\./)?scripts/" + re.escape(f) + r"\b")
            interp_before = re.compile(r"(?:\b(?:bash|sh|source|python3?|env|exec)|^\s*\.)\s+(?:\./)?scripts/" + re.escape(f) + r"\b")
            for idx, line, in_fence in body_lines(lines, body_start):
                for m in mention.finditer(line):
                    before = line[:m.start()]
                    if interp_before.search(before + m.group(0)):
                        continue
                    if before.rstrip().endswith("`"):
                        continue
                    new(path, "C23", "line " + str(idx + 1) + ": scripts/" + f + " invoked without its interpreter (write `bash \"$SKILL_DIR/scripts/" + f + "\"`)")

    # C24 — agents/openai.yaml and the parity with disable-model-invocation.
    oy = os.path.join(skill_dir, "agents", "openai.yaml")
    dmi_true = dmi == "true"
    aii_false = False
    if os.path.isfile(oy):
        try:
            y = parse_simple_yaml(read_text(oy))
        except ValueError as exc:
            new(oy, "C24", "unparseable: " + str(exc))
            y = {}
        if not isinstance(y, dict):
            new(oy, "C24", "top level must be a mapping")
            y = {}
        for k in y:
            if k not in ("interface", "policy", "dependencies"):
                new(oy, "C24", "unexpected top-level key '" + k + "' (allowed: interface, policy, dependencies)")
        iface = y.get("interface")
        if isinstance(iface, dict):
            for k in ("display_name", "short_description", "default_prompt"):
                v = iface.get(k)
                if isinstance(v, tuple) and not v[1]:
                    new(oy, "C24", "interface." + k + " must be a quoted string")
            sd = iface.get("short_description")
            if isinstance(sd, tuple) and not 25 <= len(sd[0]) <= 64:
                new(oy, "C24", "interface.short_description is " + str(len(sd[0])) + " chars (25–64)")
            dp = iface.get("default_prompt")
            if isinstance(dp, tuple) and name and ("$" + name) not in dp[0]:
                new(oy, "C24", "interface.default_prompt does not mention $" + name)
            for k in ("icon_small", "icon_large"):
                v = iface.get(k)
                if isinstance(v, tuple) and v[0] and not os.path.exists(os.path.join(skill_dir, v[0].lstrip("./"))):
                    new(oy, "C24", "interface." + k + " path does not exist: " + v[0])
        policy = y.get("policy")
        if isinstance(policy, dict):
            v = policy.get("allow_implicit_invocation")
            if isinstance(v, tuple):
                if v[0] not in ("true", "false"):
                    new(oy, "C24", "policy.allow_implicit_invocation must be true or false")
                aii_false = v[0] == "false"
        deps = y.get("dependencies")
        if isinstance(deps, dict):
            tools = deps.get("tools")
            if isinstance(tools, list):
                for t in tools:
                    tv = t.get("type") if isinstance(t, dict) else None
                    if not (isinstance(tv, tuple) and tv[0] in ("mcp", "cli")):
                        new(oy, "C24", "dependencies.tools[].type must be mcp or cli")
    if dmi_true != aii_false:
        if dmi_true:
            new(path, "C24", "disable-model-invocation: true needs agents/openai.yaml policy.allow_implicit_invocation: false (parity)")
        else:
            new(oy, "C24", "policy.allow_implicit_invocation: false needs SKILL.md disable-model-invocation: true (parity)")
    return desc


def skill_dirs(skills_dir):
    """Skill directories under skills_dir (C1 reported per directory). Entries
    starting with '_' are shared sources (skills/_shared-locator/), not skills."""
    out = []
    if not os.path.isdir(skills_dir):
        return out
    for entry in sorted(os.listdir(skills_dir)):
        full = os.path.join(skills_dir, entry)
        if entry.startswith((".", "_")) or not os.path.isdir(full):
            continue
        names = [e for e in os.listdir(full) if e.lower() == "skill.md"]
        if names == ["SKILL.md"]:
            out.append(full)
        elif not names:
            new(full, "C01", "skill directory has no SKILL.md (exactly one SKILL.md, uppercase)")
        else:
            new(full, "C01", "skill directory has '" + "', '".join(sorted(names)) + "' but no SKILL.md (exactly one SKILL.md, uppercase)")
    return out


# --- cross-file checks ---------------------------------------------------------
def check_agents(root):
    """C26: C3 and C17 over agents/*.md."""
    for path in sorted(glob.glob(os.path.join(root, "agents", "*.md"))):
        text = read_text(path)
        # Only the raw frontmatter lines are wanted here; the C2 structure
        # messages are a skill rule and are dropped.
        info = {}
        parse_frontmatter(text.split("\n"), [], info)
        for e in strict_yaml_issues(info.get("fm", [])):
            new(path, "C26", "frontmatter: " + e)
        for i, line in enumerate(text.split("\n")):
            for hit in interpolation_hits(line, ("arguments", "positional")):
                new(path, "C26", "line " + str(i + 1) + ": " + hit + " (agents take no interpolation)")


def check_lead_branches(root):
    """KTD1: no case or comparison over the lead's CLI value outside the registry lanes."""
    files = []
    for pattern in ("scripts/*.sh", "scripts/*/*.sh", "scripts/*/*/*.sh", "scripts/lease-git-hooks/*",
                    "hooks/*.sh", "hooks/*/*.sh", "skills/*/scripts/*"):
        files.extend(glob.glob(os.path.join(root, pattern)))
    seen = set()
    for path in sorted(files):
        if not os.path.isfile(path) or path in seen:
            continue
        seen.add(path)
        r = os.path.relpath(path, root)
        if r in ("scripts/lib/registry.sh", "scripts/lib/roster.sh", "scripts/validate-skills.sh") or r.startswith("scripts/fixtures/"):
            continue
        derived = []
        for i, line in enumerate(read_text(path).split("\n")):
            if line.lstrip().startswith("#"):
                continue

            def has_lead(s):
                return bool(LEAD_TOKEN.search(s)) or any(re.search(r"\$\{?" + re.escape(v) + r"\b", s) for v in derived)

            m = ASSIGN.match(line)
            if m and has_lead(m.group(2)):
                derived.append(m.group(1))
            m = READ_INTO.search(line)
            if m and has_lead(m.group(2)):
                derived.extend(m.group(1).split())
            m = CASE_LINE.match(line)
            if m and has_lead(m.group(1)):
                new(path, "KTD1", "line " + str(i + 1) + ": case over the lead's CLI value (" + m.group(1).strip()
                    + "); read a registry field or capability instead")
                continue
            for m in COMPARISON.finditer(line):
                left, right = m.group("left").strip(), m.group("right").strip()
                if (has_lead(left) and LEAD_LITERAL.match(right)) or (has_lead(right) and LEAD_LITERAL.match(left)):
                    new(path, "KTD1", "line " + str(i + 1) + ": comparison of the lead's CLI value with a literal ("
                        + left + " " + m.group("op") + " " + right + "); read a registry field or capability instead")
                    break


LOCATOR_SOURCES = ("scripts/skill-locator", "skills/_shared-locator")  # U5 ships the first; the plan's name is accepted too
# A locator call in skill text: an interpreter, a $( substitution or a POSIX
# `. ` source, then the path (an opening quote allowed) ending in the locator.
LOCATOR_CALL = re.compile(r"(?:\b(?:bash|sh|zsh|source|exec|env)\s+|\$\(\s*|(?<!\S)\.\s+)(?P<path>[\"']?[^\s\"'`;)]*locate-triforge\.sh)")
LOCATOR_ANCHOR = re.compile(r"\$\{?SKILL_DIR\}?/")


def check_locator_calls(skill_dir):
    """KTD6: every locate-triforge.sh call in SKILL.md or references/*.md is
    anchored to the skill directory. To a shell a bare scripts/… path is
    relative to the lead's working directory — the project — so a project
    shipping its own scripts/locate-triforge.sh would get it executed."""
    files = [os.path.join(skill_dir, "SKILL.md")]
    refs_dir = os.path.join(skill_dir, "references")
    if os.path.isdir(refs_dir):
        for sub, dirs, names in os.walk(refs_dir):
            files.extend(os.path.join(sub, f) for f in sorted(names) if f.endswith(".md") and not f.startswith("."))
    for path in files:
        for i, line in enumerate(read_text(path).split("\n")):
            for m in LOCATOR_CALL.finditer(line):
                call = m.group("path").lstrip("\"'")
                if not LOCATOR_ANCHOR.search(call):
                    new(path, "KTD6", "line " + str(i + 1) + ": cwd-relative locator call `" + call
                        + "` — to a shell that path is the project's, not the skill's; write "
                        + "ROOT=$(bash \"$SKILL_DIR/scripts/locate-triforge.sh\") || exit $?")


def check_locators(root, skills_dir, dirs):
    """KTD6: every skills/at-*/scripts/ carries the shared locator byte-identical,
    and every call to it in skill text is anchored to the skill directory."""
    at_skills = [d for d in dirs if os.path.basename(d).startswith("at-")]
    for d in at_skills:
        check_locator_calls(d)
    source_rel = next((s for s in LOCATOR_SOURCES if os.path.isdir(os.path.join(root, s))), None)
    if source_rel is None:
        SKIPS.append("[KTD6] locator source not present (" + " or ".join(s + "/" for s in LOCATOR_SOURCES)
                     + ", U5) — locator parity not checked" + (" for " + str(len(at_skills)) + " at- skill(s)" if at_skills else ""))
        return
    source = os.path.join(root, source_rel)
    sources = sorted(f for f in os.listdir(source) if not f.startswith(".") and os.path.isfile(os.path.join(source, f)))
    if not sources:
        SKIPS.append("[KTD6] " + source_rel + "/ holds no file — locator parity not checked")
        return
    for d in at_skills:
        for f in sources:
            copy = os.path.join(d, "scripts", f)
            if not os.path.isfile(copy):
                new(d, "KTD6", "scripts/" + f + " missing (every at- skill carries the shared locator; copy " + source_rel + "/" + f + ")")
            elif open(copy, "rb").read() != open(os.path.join(source, f), "rb").read():
                new(copy, "KTD6", "differs from " + source_rel + "/" + f + " (the locator is byte-identical in every at- skill)")


def run_skills_ref(dirs):
    binary = shutil.which("skills-ref")
    if not binary:
        SKIPS.append("[SREF] skills-ref not installed — `skills-ref validate` not run (its verdict on disable-model-invocation / argument-hint is pending)")
        return
    for d in dirs:
        try:
            run = subprocess.run([binary, "validate", d], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            new(d, "SREF", "skills-ref validate did not finish within 60 s")
            continue
        if run.returncode != 0:
            first = (run.stdout + run.stderr).strip().split("\n")[0] if (run.stdout + run.stderr).strip() else "rc " + str(run.returncode)
            new(d, "SREF", "skills-ref validate: " + first)


# --- main run ------------------------------------------------------------------
def configure(strict, fixture, skills_dir_arg=""):
    """Set the run's inputs (the wrapper's flags) and reset the findings. main()
    reads these globals, so the self-test can run it once per case."""
    global STRICT, FIXTURE, SKILLS_DIR_ARG, ROOT
    STRICT, FIXTURE, SKILLS_DIR_ARG = strict, fixture, skills_dir_arg
    ROOT = fixture or REPO
    del F[:]
    del SKIPS[:]


def run_checks(strict, fixture):
    """One --fixture run of the whole pipeline in-process: (rc, stdout, stderr)."""
    configure(strict, os.path.realpath(fixture))  # the wrapper's pwd -P
    out, errout = io.StringIO(), io.StringIO()
    rc = 0
    try:
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(errout):
            main()
    except SystemExit as exc:
        rc = exc.code or 0
    return rc, out.getvalue(), errout.getvalue()


def main():
    if SKILLS_DIR_ARG and not FIXTURE:
        skills_dir = SKILLS_DIR_ARG if os.path.isabs(SKILLS_DIR_ARG) else os.path.join(REPO, SKILLS_DIR_ARG)
        shipped_tree = False
    else:
        skills_dir = os.path.join(ROOT, "skills")
        shipped_tree = True

    dirs = skill_dirs(skills_dir)
    if not dirs and not FIXTURE:
        sys.stderr.write("validate-skills: ERROR no */SKILL.md under " + rel(skills_dir) + "\n")
        sys.exit(2)
    sibling_names = set(os.path.basename(d) for d in dirs)
    total_desc = 0
    for d in dirs:
        total_desc += len(check_skill(d, sibling_names))
    if total_desc > SET_BUDGET:
        new(skills_dir, "C10", "combined description length " + str(total_desc) + " chars exceeds the "
            + str(SET_BUDGET) + "-char budget (counted once per shipped skill; the .agents/skills/ copies are identical)")
    if shipped_tree:
        check_locators(ROOT, skills_dir, dirs)
    else:
        SKIPS.append("[KTD6] locator parity applies to the shipped skills/ tree; skipped for " + rel(skills_dir))
    check_agents(ROOT)
    check_lead_branches(ROOT)
    if not FIXTURE:
        run_skills_ref(dirs)

    skill_paths = set(rel(d) for d in dirs)

    def owner(p):
        for s in skill_paths:
            if p == s or p.startswith(s + "/"):
                return s
        return None

    errors = [f for f in F if f[0] == "error"]
    warnings = [f for f in F if f[0] == "warning"]
    for sev, path, cid, msg in F:
        prefix = "" if sev == "error" else sev + ": "
        print(path + ": " + prefix + "[" + cid + "] " + msg)
    for s in SKIPS:
        print("skip: " + s)
    if errors:
        failing_skills = set(owner(f[1]) for f in errors if owner(f[1]))
        other = set(f[1] for f in errors if not owner(f[1]))
        tail = " and " + str(len(other)) + " other file(s)" if other else ""
        print("validate-skills: FAIL (" + str(len(errors)) + " violation(s) in " + str(len(failing_skills))
              + " of " + str(len(dirs)) + " skills" + tail + ")" + ("" if STRICT else
              (" (--warn: " + str(len(warnings)) + " warning(s) the default run fails on)" if warnings else " (--warn)")))
        sys.exit(1)
    if STRICT:
        print("validate-skills: " + str(len(dirs)) + " skills OK")
    elif warnings:
        print("validate-skills: " + str(len(dirs)) + " skills OK (--warn: " + str(len(warnings)) + " warning(s) the default run fails on)")
    else:
        print("validate-skills: " + str(len(dirs)) + " skills OK (--warn)")


# --- self-test (C25) -----------------------------------------------------------
FINDING_LINE = re.compile(r"^(?P<path>.+?): (?:(?P<sev>warning|note): )?\[(?P<id>[A-Z0-9]+)\] (?P<msg>.*)$")


SMOKE_FIXTURE = "conforming"  # its runs go through the bash wrapper (no flag, --warn, --strict)


def parse_findings(stdout):
    findings = []
    for line in stdout.split("\n"):
        if line.startswith("skip: "):
            continue
        m = FINDING_LINE.match(line)
        if m:
            findings.append((m.group("sev") or "error", m.group("id"), m.group("msg")))
    return findings


def run_validator(strict, fixture):
    """One case in-process: (rc, stdout + stderr, findings)."""
    rc, out, errout = run_checks(strict, fixture)
    return rc, out + errout, parse_findings(out)


def run_wrapper(strict, fixture, flag=None):
    """The same case through the bash wrapper (flag parsing, the env hand-off
    and the exit code exercised end to end); run_validator's shape. The default
    run passes no flag (strict is the default); `flag` forces one."""
    args = [flag] if flag else ([] if strict else ["--warn"])
    run = subprocess.run([BASH, SCRIPT] + args + ["--fixture", fixture], capture_output=True, text=True)
    return run.returncode, run.stdout + run.stderr, parse_findings(run.stdout)


def ids(findings, sev):
    return sorted(set(f[1] for f in findings if f[0] == sev))


def assess(name, expect, default_run, warn_run):
    """Return a list of problems for one fixture. EXPECT's `under-warn` names
    the rule's severity under --warn: `warning` (a newer rule, an error in the
    default run) or `error` (fails in both modes)."""
    problems = []
    check, under_warn, message = expect.get("check", ""), expect.get("under-warn", "warning"), expect.get("message", "")
    rc_d, out_d, f_d = default_run
    rc_w, out_w, f_w = warn_run
    if check == "none":
        if rc_d != 0 or ids(f_d, "error") or ids(f_d, "warning"):
            problems.append("default: expected a clean pass, rc=" + str(rc_d) + " findings=" + str(ids(f_d, "error") + ids(f_d, "warning")))
        if rc_w != 0 or ids(f_w, "error") or ids(f_w, "warning"):
            problems.append("--warn: expected a clean pass, rc=" + str(rc_w))
        return problems
    if rc_d != 1:
        problems.append("default: expected rc 1, got " + str(rc_d))
    if ids(f_d, "error") != [check]:
        problems.append("default: expected exactly [" + check + "] as errors, got " + str(ids(f_d, "error")))
    if ids(f_d, "warning"):
        problems.append("default: unexpected warnings " + str(ids(f_d, "warning")))
    if message and not any(message in f[2] for f in f_d if f[1] == check):
        problems.append("default: no [" + check + "] message containing '" + message + "'")
    if under_warn == "warning":
        if rc_w != 0:
            problems.append("--warn: expected rc 0 (warning only), got " + str(rc_w))
        if ids(f_w, "warning") != [check]:
            problems.append("--warn: expected exactly [" + check + "] as a warning, got " + str(ids(f_w, "warning")))
        if ids(f_w, "error"):
            problems.append("--warn: unexpected errors " + str(ids(f_w, "error")))
    else:
        if rc_w != 1:
            problems.append("--warn: expected rc 1 (the rule fails in both modes), got " + str(rc_w))
        if ids(f_w, "error") != [check]:
            problems.append("--warn: expected exactly [" + check + "] as an error, got " + str(ids(f_w, "error")))
        if ids(f_w, "warning"):
            problems.append("--warn: unexpected warnings " + str(ids(f_w, "warning")))
    return problems


def write_skill(root, name, description, body_extra=""):
    d = os.path.join(root, "skills", name)
    os.makedirs(d)
    with open(os.path.join(d, "SKILL.md"), "w", encoding="utf-8") as fh:
        fh.write("---\nname: " + name + "\ndescription: \"" + description + "\"\n---\n\n# " + name
                 + "\n\nBody.\n" + body_extra + "\n## Output\n\n- A line.\n")


def self_test():
    fx_root = os.path.join(REPO, "scripts", "fixtures", "validate-skills")
    failures = 0
    count = 0
    for entry in sorted(os.listdir(fx_root)):
        path = os.path.join(fx_root, entry)
        expect_path = os.path.join(path, "EXPECT")
        if not os.path.isdir(path) or not os.path.isfile(expect_path):
            continue
        expect = {}
        for line in read_text(expect_path).split("\n"):
            if ":" in line and not line.startswith("#"):
                k, v = line.split(":", 1)
                expect[k.strip()] = v.strip()
        count += 1
        runner = run_wrapper if entry == SMOKE_FIXTURE else run_validator
        default_run = runner(True, path)
        warn_run = runner(False, path)
        problems = assess(entry, expect, default_run, warn_run)
        if entry == SMOKE_FIXTURE:
            # --strict is the accepted no-op: same exit code and findings as no flag.
            strict_run = run_wrapper(True, path, "--strict")
            if strict_run[0] != default_run[0] or strict_run[2] != default_run[2]:
                problems.append("--strict: expected the default run's outcome (rc " + str(default_run[0]) + "), got rc " + str(strict_run[0]))
        check = expect.get("check", "")
        if check == "none":
            outcome = "passes the default run (rc " + str(default_run[0]) + ") and --warn (rc " + str(warn_run[0]) + ")"
            if entry == SMOKE_FIXTURE:
                outcome += "; --strict is a no-op"
        else:
            outcome = ("[" + check + "] default rc " + str(default_run[0]) + " error; --warn rc " + str(warn_run[0])
                       + " " + expect.get("under-warn", "warning"))
        if problems:
            failures += 1
            print("self-test: FAIL " + entry + ": " + "; ".join(problems))
            for label, run in (("default", default_run), ("--warn", warn_run)):
                for line in run[1].strip().split("\n"):
                    print("    " + label + "> " + line)
        else:
            print("self-test: ok   " + entry + ": " + outcome)

    # Computed case 1 — C10 set budget: 14 skills × 290 chars = 4,060 > 4,000, each under 300.
    count += 1
    tmp = tempfile.mkdtemp(prefix="vs-selftest-")
    try:
        desc = ("Use when a fixture needs a description of exactly two hundred and ninety characters for the budget case."
                + " padding word" * 40)[:290]
        assert len(desc) == 290, len(desc)
        for n in range(14):
            write_skill(tmp, "budget-skill-" + "%02d" % n, desc)
        default_run = run_validator(True, tmp)
        warn_run = run_validator(False, tmp)
        problems = []
        if warn_run[0] != 0 or ids(warn_run[2], "warning") != ["C10"] or not any("combined" in f[2] for f in warn_run[2]):
            problems.append("--warn: expected rc 0 with one [C10] 'combined' warning, got rc " + str(warn_run[0]) + " " + str(ids(warn_run[2], "warning")))
        if default_run[0] != 1 or ids(default_run[2], "error") != ["C10"]:
            problems.append("default: expected rc 1 with [C10], got rc " + str(default_run[0]) + " " + str(ids(default_run[2], "error")))
        if problems:
            failures += 1
            print("self-test: FAIL computed-c10-set-budget: " + "; ".join(problems))
        else:
            print("self-test: ok   computed-c10-set-budget: 14 × 290 chars = 4060 > 4000 → [C10] default rc 1 error; --warn rc 0 warning")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    # Computed case 2 — C15 token guard: a 21,000-char body (320 × 66 chars + header) notes ≈ 5,000 tokens.
    count += 1
    tmp = tempfile.mkdtemp(prefix="vs-selftest-")
    try:
        filler = ("Plain prose line for the token guard fixture, with no tool names.\n" * 320)
        write_skill(tmp, "token-guard", "Use when a fixture needs a long body.", filler)
        run = run_validator(False, tmp)
        notes = [f for f in run[2] if f[0] == "note" and f[1] == "C15" and "5,000 tokens" in f[2]]
        if run[0] != 0 or not notes or ids(run[2], "warning") != ["C15"]:
            failures += 1
            print("self-test: FAIL computed-c15-token-guard: expected --warn rc 0, a [C15] bytes warning and a '≈ 5,000 tokens' note; got rc "
                  + str(run[0]) + " warnings=" + str(ids(run[2], "warning")) + " notes=" + str(len(notes)))
        else:
            print("self-test: ok   computed-c15-token-guard: 21,000 chars → [C15] bytes warning + '≈ 5,000 tokens' note (--warn rc 0)")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print("validate-skills --self-test: FAIL (" + str(failures) + " of " + str(count) + " cases)")
        sys.exit(1)
    print("validate-skills --self-test: " + str(count) + " cases OK")


if SELF_TEST:
    self_test()
else:
    main()
PYEOF
