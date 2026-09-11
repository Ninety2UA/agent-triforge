#!/usr/bin/env bash
# validate-versions.sh — release-gate consistency checks for Agent Triforge
# (U10 of the v3.3.0 plan: R15, AS-4/AS-5; KTD6 drift check; KTD12 sweep scope;
# KTD15 — structural assertions only, no test framework).
#
# Usage:
#   bash scripts/validate-versions.sh [--no-sweep] [--no-counts]
#
#   --no-sweep   skip check 4 (stale-pin sweep) — useful mid-sprint while docs
#                units are still rewriting pins
#   --no-counts  skip check 5 (surface counts)
#
# Checks (each prints "ok:" or "FAIL:" lines; the summary is the last line):
#   1. Version lockstep — .claude-plugin/plugin.json .version ==
#      antigravity-agents/plugin.json .version == the version in the NEWEST
#      (first in file order) README "## What's new (vX.Y.Z)" heading.
#   2. Ladder byte-identity — the single "Downgrade ladder for narrow runtime
#      tasks:" line in .claude/CLAUDE.md, templates/CLAUDE.md,
#      agents/team-lead.md, skills/wave-orchestration/SKILL.md is md5-hashed
#      (md5 on macOS, md5sum fallback); one hash printed per file; every file
#      must carry exactly one such line and all four hashes must match.
#   3. DEFAULTS drift (KTD6) — the DEFAULTS and CLI_DEFAULT_MODEL python
#      literals are duplicated inside resolve_role and roster_role_entry in
#      scripts/invoke-external.sh; the two copies must be equal (parsed with
#      ast.literal_eval, so comments and spacing do not matter). The
#      roster_member_default case arms must equal CLI_DEFAULT_MODEL, and the
#      templates/ops/roster.toml [roles.*] cli/model/effort/fallbacks must
#      equal DEFAULTS; the template must also document each optional member's
#      shipped default (model = "<CLI_DEFAULT_MODEL>").
#   4. Scoped stale-pin sweep (KTD12) — patterns gpt-5.6-sol, grok-4.5,
#      glm-5.2, kimi-k3, "Fable 5 →", "Opus 4.8", 2026-07-probe-record, and
#      "Gemini 3.1 Pro (High)" ONLY on lines that also say "default" (so the
#      documented opt-in survives). Excluded: ops/research/, ops/decisions/,
#      docs/plans/, ops/solutions/, docs/images/, .git/, the gitignored
#      deploy copies (.agents/ .gemini/ .antigravity/), node_modules/, the two
#      validator scripts, lines marked as history ("history" or "was <word>"),
#      and README.md at or below its "## Recent changes" heading (the release
#      ledger: past entries name the pins they adopted at the time).
#   5. Surface counts — agents/*.md, skills/*/SKILL.md, commands/*.md counts
#      must match every count claim in .claude/CLAUDE.md, templates/CLAUDE.md,
#      README.md (above "## Recent changes"), docs/index.html,
#      docs/agent-triforge.md, .claude-plugin/plugin.json. A claim is
#      "<N> [up to three words] agents|subagents|skills|commands" on a line
#      about the shipped inventory (ship/plugin/portable/specialized/slash/
#      surface/focused/model-agnostic/methodology, or a top-level dir path);
#      subset phrasings ("+ 5 agents", "all 4 review agents", "5 parallel
#      research agents") and history lines are skipped; "(was N)" is stripped
#      before matching so the current number on the same line is still checked.
#
# Exit codes: 0 every check passed; 1 at least one check failed; 2 bad flag.
set -euo pipefail
cd "$(dirname "$0")/.."

NO_SWEEP=0
NO_COUNTS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-sweep)  NO_SWEEP=1 ;;
    --no-counts) NO_COUNTS=1 ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "validate-versions: unknown flag '$1' (accepted: --no-sweep --no-counts)" >&2
      exit 2 ;;
  esac
  shift
done

FAILED_CHECKS=0
fail() { printf 'FAIL: %s\n' "$1"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); }
ok()   { printf 'ok:   %s\n' "$1"; }

# md5 on macOS, md5sum fallback; reads stdin, prints the bare hash.
_md5() {
  if command -v md5 >/dev/null 2>&1; then
    md5 -q
  else
    md5sum | awk '{print $1}'
  fi
}

# --- 1. version lockstep -----------------------------------------------------
json_version() {
  VV_FILE="$1" python3 -c 'import json, os; print(json.load(open(os.environ["VV_FILE"]))["version"])'
}
PLUGIN_V=$(json_version .claude-plugin/plugin.json)
AGY_V=$(json_version antigravity-agents/plugin.json)
README_V=$(grep -m1 -E "^## What's new \(v[0-9]+\.[0-9]+\.[0-9]+\)" README.md \
  | sed -E "s/^## What's new \(v([0-9]+\.[0-9]+\.[0-9]+)\).*/\1/" || true)
if [ -z "$README_V" ]; then
  fail "version lockstep: README.md has no '## What's new (vX.Y.Z)' heading"
elif [ "$PLUGIN_V" = "$AGY_V" ] && [ "$PLUGIN_V" = "$README_V" ]; then
  ok "version lockstep: $PLUGIN_V (.claude-plugin/plugin.json, antigravity-agents/plugin.json, README What's new)"
else
  fail "version lockstep: .claude-plugin/plugin.json=$PLUGIN_V antigravity-agents/plugin.json=$AGY_V README What's new=$README_V"
fi

# --- 2. ladder byte-identity -------------------------------------------------
LADDER_RE='Downgrade ladder for narrow runtime tasks:'
LADDER_FILES="
.claude/CLAUDE.md
templates/CLAUDE.md
agents/team-lead.md
skills/wave-orchestration/SKILL.md
"
LADDER_HASHES=""
LADDER_FILE_COUNT=0
LADDER_BAD=0
for f in $LADDER_FILES; do
  LADDER_FILE_COUNT=$((LADDER_FILE_COUNT + 1))
  if [ ! -f "$f" ]; then
    fail "ladder: $f missing"; LADDER_BAD=1; continue
  fi
  n=$(grep -c "$LADDER_RE" "$f" || true)
  if [ "$n" -ne 1 ]; then
    fail "ladder: $f has $n ladder lines (expected exactly 1)"; LADDER_BAD=1; continue
  fi
  h=$(grep "$LADDER_RE" "$f" | _md5)
  printf 'ladder %s  %s\n' "$h" "$f"
  LADDER_HASHES="${LADDER_HASHES}${h}
"
done
LADDER_DISTINCT=$(printf '%s' "$LADDER_HASHES" | sort -u | grep -c . || true)
if [ "$LADDER_BAD" -eq 0 ] && [ "$LADDER_DISTINCT" -eq 1 ]; then
  LADDER_HASH=$(printf '%s' "$LADDER_HASHES" | head -1)
  ok "ladder byte-identity: $LADDER_HASH across $LADDER_FILE_COUNT files"
else
  LADDER_HASH="(none)"
  [ "$LADDER_BAD" -ne 0 ] || fail "ladder byte-identity: $LADDER_DISTINCT distinct hashes across $LADDER_FILE_COUNT files"
fi

# --- 3. DEFAULTS drift (KTD6) ------------------------------------------------
DRIFT_RC=0
VV_SRC="scripts/invoke-external.sh" VV_ROSTER="templates/ops/roster.toml" python3 - <<'PYEOF' || DRIFT_RC=$?
import ast
import os
import re
import sys

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("FAIL: drift: no TOML parser (Python 3.11+ tomllib or pip install tomli)")
        sys.exit(1)

src_path = os.environ["VV_SRC"]
roster_path = os.environ["VV_ROSTER"]
with open(src_path, encoding="utf-8") as fh:
    src = fh.read()

fails = []
oks = []


def func_pos(name):
    m = re.search(r"^" + re.escape(name) + r"\(\) \{", src, re.M)
    return m.start() if m else None


def literal_blocks(name):
    """Every '<name> = {' ... '}' block in the shell file, parsed as a python literal."""
    pat = re.compile(
        r"^([ \t]*)" + re.escape(name) + r" = \{\n(.*?)^\1\}[ \t]*$", re.M | re.S
    )
    found = []
    for m in pat.finditer(src):
        text = "{\n" + m.group(2) + "}"
        try:
            value = ast.literal_eval(text)
        except Exception as exc:  # noqa: BLE001 — report, do not crash
            fails.append(name + " block at line " + str(src.count("\n", 0, m.start()) + 1)
                         + " is not a pure literal: " + str(exc))
            value = None
        found.append((m.start(), value))
    return found


pos_resolve = func_pos("resolve_role")
pos_entry = func_pos("roster_role_entry")
if pos_resolve is None:
    fails.append("resolve_role() not found in " + src_path)
if pos_entry is None:
    fails.append("roster_role_entry() not found in " + src_path)

canonical = {}
for name in ("DEFAULTS", "CLI_DEFAULT_MODEL"):
    blocks = literal_blocks(name)
    if len(blocks) != 2:
        fails.append(name + ": expected 2 copies (resolve_role + roster_role_entry), found " + str(len(blocks)))
        if blocks and blocks[0][1] is not None:
            canonical[name] = blocks[0][1]
        continue
    (p0, v0), (p1, v1) = blocks
    if pos_resolve is not None and pos_entry is not None and not (pos_resolve < p0 < pos_entry < p1):
        fails.append(name + ": the two copies are not one inside resolve_role and one inside roster_role_entry")
    if v0 is None or v1 is None:
        continue
    canonical[name] = v0
    if v0 == v1:
        oks.append(name + ": resolve_role and roster_role_entry copies identical (" + str(len(v0)) + " entries)")
    else:
        for key in sorted(set(v0) | set(v1)):
            if v0.get(key) != v1.get(key):
                fails.append(name + "[" + repr(key) + "] differs: resolve_role=" + repr(v0.get(key))
                             + " roster_role_entry=" + repr(v1.get(key)))

cli_defaults = canonical.get("CLI_DEFAULT_MODEL")
role_defaults = canonical.get("DEFAULTS")

# roster_member_default case arms vs CLI_DEFAULT_MODEL
m = re.search(r"^roster_member_default\(\) \{\n(.*?)^\}", src, re.M | re.S)
if not m:
    fails.append("roster_member_default() not found in " + src_path)
elif cli_defaults is not None:
    arms = dict(re.findall(r'^\s*([a-z]+)\)\s+echo "([^"]*)"\s*;;', m.group(1), re.M))
    arm_fail = False
    for cli, model in sorted(cli_defaults.items()):
        if cli not in arms:
            fails.append("roster_member_default has no arm for " + cli)
            arm_fail = True
        elif arms[cli] != model:
            fails.append("roster_member_default " + cli + " = " + repr(arms[cli])
                         + " but CLI_DEFAULT_MODEL = " + repr(model))
            arm_fail = True
    if not arm_fail:
        oks.append("roster_member_default arms match CLI_DEFAULT_MODEL (" + str(len(cli_defaults)) + " members)")

# templates/ops/roster.toml vs DEFAULTS / CLI_DEFAULT_MODEL
try:
    with open(roster_path, "rb") as fh:
        roster = tomllib.load(fh)
except Exception as exc:  # noqa: BLE001
    fails.append(roster_path + " does not parse: " + str(exc))
    roster = None
if roster is not None and role_defaults is not None:
    roles = roster.get("roles", {})
    role_fail = False
    for role, want in sorted(role_defaults.items()):
        have = roles.get(role)
        if have is None:
            fails.append(roster_path + " missing [roles." + role + "]")
            role_fail = True
            continue
        for field in ("cli", "model", "effort", "fallbacks"):
            if have.get(field) != want.get(field):
                fails.append(roster_path + " [roles." + role + "]." + field + " = " + repr(have.get(field))
                             + " but DEFAULTS = " + repr(want.get(field)))
                role_fail = True
    for role in sorted(roles):
        if role not in role_defaults:
            fails.append(roster_path + " has [roles." + role + "] with no DEFAULTS entry")
            role_fail = True
    if not role_fail:
        oks.append(roster_path + " [roles.*] match DEFAULTS (" + str(len(role_defaults)) + " roles)")
if roster is not None and cli_defaults is not None:
    with open(roster_path, encoding="utf-8") as fh:
        roster_text = fh.read()
    doc_fail = False
    for cli in ("opencode", "kimi", "cursor"):
        needle = 'model = "' + cli_defaults.get(cli, "") + '"'
        if needle not in roster_text:
            fails.append(roster_path + " does not document the shipped " + cli + " default: " + needle)
            doc_fail = True
    if not doc_fail:
        oks.append(roster_path + " documents the optional-member defaults from CLI_DEFAULT_MODEL")

for line in oks:
    print("ok:   drift: " + line)
for line in fails:
    print("FAIL: drift: " + line)
sys.exit(1 if fails else 0)
PYEOF
if [ "$DRIFT_RC" -ne 0 ]; then
  FAILED_CHECKS=$((FAILED_CHECKS + 1))
fi

# README release ledger boundary (shared by checks 4 and 5).
README_HISTORY_START=$(grep -n '^## Recent changes' README.md | head -1 | cut -d: -f1 || true)
README_HISTORY_START="${README_HISTORY_START:-0}"

# --- 4. scoped stale-pin sweep (KTD12) ---------------------------------------
if [ "$NO_SWEEP" -eq 1 ]; then
  echo "skip: stale-pin sweep (--no-sweep)"
else
  # GNU grep prints ./path, BSD grep prints path — accept both prefixes.
  SWEEP_EXCLUDE_RE='^(\./)?(ops/research|ops/decisions|docs/plans|ops/solutions|docs/images|\.git|\.agents|\.gemini|\.antigravity|node_modules)/'
  SWEEP_SELF_RE='^(\./)?scripts/validate-(versions|skills)\.sh:'
  SWEEP_HITS=$(
    {
      grep -rnI \
        -e 'gpt-5\.6-sol' \
        -e 'grok-4\.5' \
        -e 'glm-5\.2' \
        -e 'kimi-k3' \
        -e 'Fable 5 →' \
        -e 'Opus 4\.8' \
        -e '2026-07-probe-record' \
        . || true
      grep -rnI 'Gemini 3\.1 Pro (High)' . | grep -i 'default' || true
    } \
      | grep -vE "$SWEEP_EXCLUDE_RE" \
      | grep -vE "$SWEEP_SELF_RE" \
      | grep -v 'history\|was [a-z]' \
      | awk -F: -v start="$README_HISTORY_START" \
          '!( (($1 == "README.md") || ($1 == "./README.md")) && start > 0 && ($2 + 0) >= start )' \
      | sort -t: -k1,1 -k2,2n -u || true
  )
  if [ -n "$SWEEP_HITS" ]; then
    printf '%s\n' "$SWEEP_HITS"
    SWEEP_COUNT=$(printf '%s\n' "$SWEEP_HITS" | grep -c . || true)
    fail "stale-pin sweep: $SWEEP_COUNT hit(s) on shipped surfaces (see file:line:text above)"
  else
    ok "stale-pin sweep: no stale pins outside the excluded paths"
  fi
fi

# --- 5. surface counts -------------------------------------------------------
AGENT_COUNT=$(ls agents/*.md 2>/dev/null | grep -c . || true)
SKILL_COUNT=$(ls skills/*/SKILL.md 2>/dev/null | grep -c . || true)
COMMAND_COUNT=$(ls commands/*.md 2>/dev/null | grep -c . || true)
if [ "$NO_COUNTS" -eq 1 ]; then
  echo "skip: surface counts (--no-counts; shipped: $AGENT_COUNT agents, $SKILL_COUNT skills, $COMMAND_COUNT commands)"
else
  COUNTS_RC=0
  VV_AGENTS="$AGENT_COUNT" VV_SKILLS="$SKILL_COUNT" VV_COMMANDS="$COMMAND_COUNT" \
  VV_README_HISTORY_START="$README_HISTORY_START" python3 - <<'PYEOF' || COUNTS_RC=$?
import os
import re
import sys

actual = {
    "agent": int(os.environ["VV_AGENTS"]),
    "skill": int(os.environ["VV_SKILLS"]),
    "command": int(os.environ["VV_COMMANDS"]),
}
readme_history_start = int(os.environ["VV_README_HISTORY_START"] or "0")
files = [
    ".claude/CLAUDE.md",
    "templates/CLAUDE.md",
    "README.md",
    "docs/index.html",
    "docs/agent-triforge.md",
    ".claude-plugin/plugin.json",
]
CLAIM = re.compile(
    r"(?P<pre>(?:\+|\ball|of the|the other|\bother)\s+)?"
    r"\b(?P<n>\d+)\s+(?P<mods>(?:[A-Za-z-]+\s+){0,3}?)(?P<sub>sub)?(?P<kind>agent|skill|command)s?\b",
    re.I,
)
SUBSET_WORDS = {
    "parallel", "review", "research", "external", "reviewer", "reviewers",
    "background", "concurrent", "additional", "new", "more", "remaining", "other",
}
SURFACE_MODS = {"specialized", "portable", "slash", "shipped", "focused", "model-agnostic", "methodology"}
SURFACE_LINE = re.compile(
    r"\bship|plugin|portable|specialized|slash|surface|focused|model-agnostic|methodology"
    r"|agents/|skills/|commands/|restricted tools",
    re.I,
)
HISTORY = re.compile(r"history|\bwas\b|previously", re.I)

mismatches = []
claims = 0
for path in files:
    if not os.path.exists(path):
        mismatches.append(path + ": file missing")
        continue
    with open(path, encoding="utf-8") as fh:
        for lineno, raw in enumerate(fh, 1):
            if path == "README.md" and readme_history_start and lineno >= readme_history_start:
                break
            line = re.sub(r"\(was \d+\)", "", raw)
            if HISTORY.search(line):
                continue
            for m in CLAIM.finditer(line):
                if m.group("pre"):
                    continue
                mods = {w.lower() for w in m.group("mods").split()}
                if mods & SUBSET_WORDS:
                    continue
                if not (mods & SURFACE_MODS) and not SURFACE_LINE.search(line):
                    continue
                kind = m.group("kind").lower()
                n = int(m.group("n"))
                claims += 1
                if n != actual[kind]:
                    mismatches.append(
                        path + ":" + str(lineno) + ": says " + str(n) + " " + kind + "s, shipped "
                        + str(actual[kind]) + " — " + m.group(0).strip()
                    )

for line in mismatches:
    print("FAIL: counts: " + line)
if mismatches:
    sys.exit(1)
print(
    "ok:   surface counts: " + str(claims) + " claims match shipped "
    + str(actual["agent"]) + " agents / " + str(actual["skill"]) + " skills / "
    + str(actual["command"]) + " commands"
)
PYEOF
  if [ "$COUNTS_RC" -ne 0 ]; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
fi

# --- summary -----------------------------------------------------------------
if [ "$FAILED_CHECKS" -eq 0 ]; then
  echo "validate-versions: PASS — plugin $PLUGIN_V, ladder $LADDER_HASH, $AGENT_COUNT agents / $SKILL_COUNT skills / $COMMAND_COUNT commands"
  exit 0
fi
echo "validate-versions: FAIL — $FAILED_CHECKS check(s) failed (see FAIL: lines above)"
exit 1
