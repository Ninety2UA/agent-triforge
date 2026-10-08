#!/usr/bin/env bash
# validate-versions.sh — release-gate consistency checks for Agent Triforge
# (U10 of the v3.3.0 plan: R15, AS-4/AS-5; KTD6 drift check; KTD12 sweep scope;
# KTD15 — structural assertions only, no test framework; also the one-definition
# ladder check (KTD22), the AGENTS.md budget (R10) and the rule-inventory
# completeness check (R11)).
#
# Usage:
#   bash scripts/validate-versions.sh [--no-sweep] [--no-counts] [--only <check>[,<check>…]] [--root <dir>]
#   bash scripts/validate-versions.sh --self-test
#
#   --no-sweep   skip check 4 (stale-pin sweep) — useful mid-sprint while docs
#                units are still rewriting pins
#   --no-counts  skip check 5 (surface counts)
#   --only       run only the named checks: lockstep and skill-versions (1),
#                ladder (2), drift (3), sweep (4), counts (5), budget (6),
#                inventory (7), retired (8), workflows (9), manifests (10),
#                halt (11). An unknown or empty name is a usage error (exit 2),
#                so a typo never passes by running nothing.
#   --root       run the checks against <dir> instead of this checkout (the
#                self-test's fixture roots); paths print relative to <dir>.
#   --self-test  run every fixture under scripts/fixtures/validate-versions/ —
#                a minimal root plus an EXPECT file naming the checks to run,
#                the exit code, and every ok:/FAIL:/skip: line and the summary
#                in order — and the computed cases (the AGENTS.md budget
#                boundaries, --only usage errors), each through this script
#                with --root and --only. Exit 0 when every case behaves as
#                named; it takes no other flag.
#
# Checks (each prints "ok:" or "FAIL:" lines; the summary is the last line):
#   1. Version lockstep — .claude-plugin/plugin.json .version ==
#      antigravity-agents/plugin.json .version == the version in the NEWEST
#      (first in file order) README "## What's new (vX.Y.Z)" heading. The
#      README "## Recent changes" ledger must also carry that version's
#      "### <date> — vX.Y.Z: <title>" entry: scripts/release-notes.sh turns it
#      into the GitHub release title + body when the bump lands on main
#      (.github/workflows/release.yml), so a missing entry fails here, not there.
#      Every shipped skill's frontmatter metadata.version (skills/*/SKILL.md;
#      the repo-local .claude/skills are not shipped) equals that version too:
#      each skill whose metadata.version differs or is missing fails, named
#      with both versions.
#   2. Ladder one-definition (KTD22, R26) — the model ladder is defined exactly
#      once, as the TRIFORGE_MODEL_LADDER literal in scripts/lib/registry.sh
#      (triforge_ladder prints it). A definition is a line carrying the phrase
#      "Downgrade ladder for narrow runtime tasks" followed by a colon —
#      whatever comes after it, so a restatement that starts at another rung
#      counts too (matched case-insensitively; whitespace and * _ ` markup may
#      sit between the phrase and the colon). The instruction files,
#      personas/team-lead.md and skills/wave-orchestration/SKILL.md point at the
#      registry with " — " after the phrase instead. The sweep scope of check 4
#      applies (history directories, the self-test's fixtures, the README
#      ledger and this script are not shipped surfaces); any second match, or a
#      single match outside the registry literal, fails.
#   3. Registry drift (KTD7, R41) — the CLI registry is the _TRIFORGE_CLIS_PY
#      literal in scripts/lib/registry.sh (one entry per CLI; parsed with
#      ast.literal_eval, so comments and spacing do not matter) plus
#      TRIFORGE_ENV_BASE beside it. The literal must be pure, free of single
#      quotes (the shell string would end there), and every entry must carry
#      the documented fields with the right types: tier core|optional, lane
#      shell|subagent, env_keys as EXACT variable names — any wildcard other
#      than the documented KIMI_* fails — and `lead` either {} or exactly the
#      nine KTD1 fields. role_limit and opt_in_roles name DEFAULTS roles,
#      never the same role twice, opt_in_roles only beside a role_limit, and a
#      core CLI carries neither a role_limit nor consent (every chain ends at
#      one). The role table is the single DEFAULTS literal
#      (_ROLE_DEFAULTS_PY) in scripts/lib/roster.sh: each role's cli must be
#      registered, its model must equal that CLI's registry model, and its
#      chain must end at a core member; roster.sh must splice the registry and
#      carry no literal copy of CLI_DEFAULT_MODEL / BINARY / INSTALL_FIX /
#      KNOWN / CORE_TRIO. templates/ops/roster.toml [roles.*] must equal
#      DEFAULTS and every `[members.<cli>] … model = "…"` it documents must
#      name a registered CLI's registry model. The remaining readers must read,
#      not copy: hooks/handlers/session-start.sh carries no SHIPPED / ROLE_CLI
#      literal and references _TRIFORGE_CLIS_PY; _adapter_env in
#      scripts/lib/lease.sh reads TRIFORGE_ENV_BASE + cli_field and names no
#      base or credential key in code; lease.sh and lease-wait.sh code name no
#      shipped model;
#      each lane's `${<model_env>:-…}` default in scripts/lib/*.sh equals the
#      registry model; _lane_run in scripts/probe-capabilities.sh reads
#      REG_ENV_BASE and the harness's CDX_MODEL pin equals the codex model.
#      The Triforge-root test exists twice on purpose — _triforge_is_plugin_root
#      in scripts/invoke-external.sh (the loader) and is_triforge_root in
#      scripts/skill-locator/locate-triforge.sh (POSIX sh, executed, never
#      sourced) — and the two function bodies must be identical apart from the
#      function name.
#   4. Scoped stale-pin sweep (KTD12) — patterns gpt-5.6-sol, grok-4.5,
#      glm-5.2, kimi-k3, "Fable 5 →", "Opus 4.8", the pre-5.5 Sonnet rung
#      ("Opus 5.5 → Sonnet 5" not followed by ".", "Sonnet 5)", the &nbsp; form),
#      2026-07-probe-record, and
#      "Gemini 3.1 Pro (High)" ONLY on lines that also say "default" (so the
#      documented opt-in survives). Excluded: ops/research/, ops/decisions/,
#      docs/plans/, docs/brainstorms/, ops/solutions/, docs/images/,
#      scripts/fixtures/validate-versions/ (the self-test's planted stale pins
#      and second ladder), .git/,
#      the gitignored deploy copies (.agents/ .gemini/ .antigravity/),
#      node_modules/, the two validator scripts, lines marked as history
#      ("history" or "was <word>"), and README.md at or below its
#      "## Recent changes" heading (the release ledger: past entries name the
#      pins they adopted at the time).
#   5. Surface counts — personas/*.md and skills/*/SKILL.md, the skills counted
#      three ways (every skill; the portable set, whose names do not start
#      with at-; the at-* lead workflows), must match every count claim in
#      AGENTS.md, templates/AGENTS.md, README.md (above "## Recent changes"),
#      docs/index.html, docs/agent-triforge.md, .claude-plugin/plugin.json.
#      The vocabulary: "<N> skills" is every skill, "<N> portable skills" the
#      portable set, "<N> lead workflows" the at-* set, and "<N> [up to three
#      words] personas" the persona count ("agents|subagents" still counts
#      against it, so a 3.x-era claim cannot drift). A claim counts on a line
#      about the shipped inventory (ship/plugin/portable/specialized/surface/
#      focused/model-agnostic/methodology/lead workflow, or a top-level dir
#      path); subset phrasings ("+ 5 agents", "all 4 review agents", "5
#      parallel research agents") and history lines are skipped; "(was N)" is
#      stripped before matching so the current number on the same line is
#      still checked.
#   6. AGENTS.md budget (R10) — when a root AGENTS.md exists it must be at most
#      200 lines (a final unterminated line counts) and at most 16 KiB
#      (16384 bytes; Codex's combined instruction budget is 32 KiB). Prints a
#      "skip:" line while the file is absent.
#   7. Rule-inventory completeness (R11) — when docs/rule-inventory.md exists:
#      - Tables: a table is any line with a "|" followed by a separator row
#        (dashes, optional colons and pipes); outer pipes are optional on the
#        header, the separator and every row, and a table runs until the next
#        blank line, heading, blockquote or code fence — so a line without
#        pipes directly under a table is a row (one cell), as it renders.
#      - Every table must have a header cell naming the destination column
#        ("Destination", "New home" or "Now lives").
#      - Every data row must fill that cell. HTML comments, tags and entities
#        (<br>, <!-- … -->, &nbsp;) are removed first; a cell with no letter or
#        digit left is blank (dashes, "?", markup), and a cell that reads as a
#        placeholder once lowercased and stripped of punctuation and spaces —
#        tbd, tba, todo, to be determined, to be decided, unknown — fails.
#      - No cell in any table may read "TBD" (case-insensitive, whole word).
#      - Declared coverage: the file must carry exactly one line
#        "**Totals.** <N> rows: `<source>` <n> · `<source>` <n> …". The parsed
#        data-row count must equal <N>, and the rows under each
#        "## <source>" heading must equal that source's <n> (rows above the
#        first "## " heading, or under an undeclared one, fail) — a row can
#        only disappear together with an edit to the declared totals.
#      - Cited paths: every path a destination cell names must exist in the
#        tree — a backticked token, or a bare word carrying a "/" or a file
#        suffix (.md .sh .py .json .toml .yml .txt .html .js .css .local) or
#        a leading dot — after dropping a trailing "§section", "#anchor" or
#        ":line" and the surrounding punctuation; a {a,b} brace expands and a
#        * glob must match at least one file. Skipped: a quoted phrase ("…"),
#        a "§section" name, a token with $ < > = or a URL, and a destination
#        that reads "dropped: …" (model can infer / stale) — prose, not paths.
#      Prints a "skip:" line while the file is absent.
#   8. Retired commands/ and agents/ (U23, U8) — the plugin checkout ships no
#      commands/*.md (the 17 lead workflows are skills/at-*/) and no
#      agents/*.md (the personas are personas/*.md), while "commands/" and
#      "agents/" stay on FRAMEWORK_PROTECTED in scripts/lib/registry.sh: the
#      plugin host auto-loads both plugin-root directories, so a lease that
#      re-created a command or a subagent would otherwise skip the promotion
#      gate (rc 42).
#   9. Lead-workflow surfaces — the at- prefix is spelled identically at its
#      four code sites (LEAD_PREFIX in scripts/lib/skills-sync.py, the `at-*)`
#      arm in scripts/probe-capabilities.sh, startswith("at-") in
#      scripts/validate-skills.sh, the skills/at-* count in this script), and
#      the names the session-start banner (hooks/handlers/session-start.sh)
#      and skills/at-status/references/status-template.md enumerate equal the
#      set of skills/at-*/ directories (the diff is printed). No shipped
#      surface (check 4's scope, minus ops/) carries a bare $at- mention,
#      because Codex attaches a plugin skill only as
#      $agent-triforge:at-<name> (codex-cli 0.160.0, U14). The check skips
#      the validate-skills fixture c24-bare-mention/, which carries one on
#      purpose.
#  10. Other-harness skill manifests (R22) — skills/.devin-plugin/plugin.json
#      (Devin; plugin root skills/, installed as <repo>#skills) and the root
#      package.json "pi" key (Pi) each list exactly the portable skill
#      directories, one explicit path per skill, spelled exactly as the
#      directory: an at-* entry in any case, a missing portable skill, a path
#      that is not a portable skill directory (a case alias such as AT-BUILD,
#      which a case-insensitive disk resolves, included), a glob or !/+/-
#      pattern, and a duplicate all fail. Each manifest carries only
#      metadata and its skill list — no version (check 1 covers the release
#      manifests), and nothing a harness would run or obey (Devin's plugin
#      dependencies and MCP servers, npm scripts and dependencies, Pi
#      extensions, prompts or themes). Its name equals .claude-plugin's. No
#      root .devin-plugin/ may exist, and skills/ carries none of the names
#      Devin loads from a plugin root besides skills (AGENTS.md, rules/,
#      agents/, hooks.json, hooks/, .mcp.json, …): from the repo root Devin
#      would also load this AGENTS.md as an always-on rule and run hooks/.
#  11. Halt threshold — a builder halts at MORE THAN 50 changed files
#      (AGENTS.md §Delegation), so a task touching exactly 50 goes on. In
#      skills/, AGENTS.md, README.md (above its "## Recent changes" ledger),
#      docs/index.html and docs/agent-triforge.md, a 50-file threshold written
#      inclusively fails: 50+, 50 or more (or above, and up, …), 50 files or
#      more, at least 50, ≥ / >= / => 50 before file(s), changed files or file
#      changes, file changes ≥ / >= 50, and "halt … at 50 files" within one
#      clause. HTML tags, entities and * _ ` markup are dropped first, and a
#      phrase may wrap across lines. "more than 50", "over 50", "> 50" and "file changes > 50"
#      pass and are counted; a count with no comparator ("50 files", "look at
#      50 files") is prose, not a threshold.
#
# Exit codes: 0 every check passed (--self-test: every case behaved as named);
# 1 at least one check failed (--self-test: a case did not); 2 bad flag.
set -euo pipefail
ORIG_PWD="$PWD"
cd "$(dirname "$0")/.."
VV_HOME="$PWD"   # this checkout: the default --root, and where --self-test finds its fixtures

NO_SWEEP=0
NO_COUNTS=0
ONLY=""
ROOT=""
SELF_TEST=0
# The names --only takes, in run order (the header numbers the checks).
VV_CHECKS="lockstep skill-versions ladder drift sweep counts budget inventory retired workflows manifests halt"
while [ $# -gt 0 ]; do
  case "$1" in
    --no-sweep)  NO_SWEEP=1 ;;
    --no-counts) NO_COUNTS=1 ;;
    --self-test) SELF_TEST=1 ;;
    --only)
      shift
      [ -n "${1:-}" ] || { echo "validate-versions: ERROR --only needs a check name (one of: $VV_CHECKS)" >&2; exit 2; }
      ONLY="$1"
      ;;
    --root)
      shift
      [ -n "${1:-}" ] || { echo "validate-versions: ERROR --root needs a directory" >&2; exit 2; }
      ROOT=$(cd "$ORIG_PWD" && cd "$1" 2>/dev/null && pwd -P) \
        || { echo "validate-versions: ERROR root directory not found: $1" >&2; exit 2; }
      ;;
    -h|--help)
      sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "validate-versions: unknown flag '$1' (accepted: --no-sweep --no-counts --only <check>[,<check>…] --root <dir> --self-test)" >&2
      exit 2 ;;
  esac
  shift
done
if [ "$SELF_TEST" -eq 1 ] && [ "$ONLY$ROOT$NO_SWEEP$NO_COUNTS" != "00" ]; then
  echo "validate-versions: ERROR --self-test runs alone (each case sets its own --root and --only)" >&2
  exit 2
fi
# --only: every name must be a check, and at least one must be given — an
# unknown name would otherwise select nothing and pass.
if [ -n "$ONLY" ]; then
  case "$ONLY" in
    *[!a-z,-]*)
      echo "validate-versions: ERROR --only takes check names separated by commas (one of: $VV_CHECKS), got '$ONLY'" >&2
      exit 2 ;;
  esac
  VV_ONLY_COUNT=0
  for VV_NAME in $(printf '%s' "$ONLY" | tr ',' ' '); do
    case " $VV_CHECKS " in
      *" $VV_NAME "*) VV_ONLY_COUNT=$((VV_ONLY_COUNT + 1)) ;;
      *)
        echo "validate-versions: ERROR --only names an unknown check '$VV_NAME' (one of: $VV_CHECKS)" >&2
        exit 2 ;;
    esac
  done
  if [ "$VV_ONLY_COUNT" -eq 0 ]; then
    echo "validate-versions: ERROR --only needs a check name (one of: $VV_CHECKS)" >&2
    exit 2
  fi
fi
# _selected <check>: true when this run includes <check> — every check unless
# --only names a set.
_selected() {
  case ",${ONLY:-$1}," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# --- self-test: the planted fixtures and the computed cases ------------------
if [ "$SELF_TEST" -eq 1 ]; then
  VV_SCRIPT="$VV_HOME/scripts/validate-versions.sh" VV_FIXTURES="$VV_HOME/scripts/fixtures/validate-versions" \
  VV_BASH="$BASH" python3 - <<'PYEOF'
import os
import shutil
import subprocess
import sys
import tempfile

SCRIPT = os.environ["VV_SCRIPT"]
BASH = os.environ["VV_BASH"]
FX_ROOT = os.environ["VV_FIXTURES"]
# The lines a case asserts, in order: every check's verdict lines and the
# summary. The file:line:text hits a check prints above its FAIL line are left
# out (GNU grep prefixes ./, BSD grep does not).
STATUS = ("ok:", "FAIL:", "skip:", "validate-versions:")
SUMMARY_FAIL = "validate-versions: FAIL — 1 check(s) failed (see FAIL: lines above)"


def run(root, only):
    """One case through this script: (rc, stdout, stderr)."""
    p = subprocess.run([BASH, SCRIPT, "--root", root, "--only", only], capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def assess(rc_want, lines_want, rc, out, err):
    """Problems with one run: the exit code, the status lines in order, and a
    silent stderr (a check that crashes still exits 1)."""
    problems = []
    got = [ln for ln in out.split("\n") if ln.startswith(STATUS)]
    if rc != rc_want:
        problems.append("expected rc " + str(rc_want) + ", got " + str(rc))
    if got != lines_want:
        problems.append("status lines differ")
    if err.strip():
        problems.append("stderr is not empty")
    return problems


def report(name, outcome, problems, lines_want, out, err):
    if not problems:
        print("self-test: ok   " + name + ": " + outcome)
        return 0
    print("self-test: FAIL " + name + ": " + "; ".join(problems))
    for ln in lines_want:
        print("    expected> " + ln)
    for ln in (out + err).strip().split("\n"):
        print("    got> " + ln)
    return 1


def scratch_run(name, files, only, rc_want, lines_want):
    """A computed case: write files into a scratch root, run, assess."""
    tmp = tempfile.mkdtemp(prefix="vv-selftest-")
    try:
        for rel, content in files.items():
            with open(os.path.join(tmp, rel), "w", encoding="utf-8", newline="") as fh:
                fh.write(content)
        rc, out, err = run(tmp, only)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    outcome = "[" + only + "] rc " + str(rc) + ", " + str(len(lines_want)) + " status line(s) as named"
    return report(name, outcome, assess(rc_want, lines_want, rc, out, err), lines_want, out, err)


count = 0
failures = 0
for entry in sorted(os.listdir(FX_ROOT)):
    src = os.path.join(FX_ROOT, entry)
    expect_path = os.path.join(src, "EXPECT")
    if not os.path.isfile(expect_path):
        continue
    count += 1
    check, rc_want, lines_want, bad = "", None, [], []
    with open(expect_path, encoding="utf-8") as fh:
        for raw in fh.read().split("\n"):
            if not raw.strip() or raw.startswith("#"):
                continue
            key, _, value = raw.partition(":")
            key, value = key.strip(), value.strip()
            if key == "check":
                check = value
            elif key == "rc" and value.isdigit():
                rc_want = int(value)
            elif key == "line":
                lines_want.append(value)
            else:
                bad.append(raw)
    if not check or rc_want is None or not lines_want or bad:
        failures += report(entry, "", ["EXPECT needs check:, rc: and line: entries" + (" (unreadable: " + "; ".join(bad) + ")" if bad else "")], [], "", "")
        continue
    # The case runs on a copy without its EXPECT, so the expected lines are
    # never part of the tree the checks scan.
    tmp = tempfile.mkdtemp(prefix="vv-selftest-")
    try:
        root = os.path.join(tmp, "root")
        shutil.copytree(src, root, ignore=shutil.ignore_patterns("EXPECT"))
        rc, out, err = run(root, check)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    outcome = "[" + check + "] rc " + str(rc) + ", " + str(len(lines_want)) + " status line(s) as named"
    failures += report(entry, outcome, assess(rc_want, lines_want, rc, out, err), lines_want, out, err)

# Computed cases — the AGENTS.md budget (check 6) at and past its two limits.
# Generated rather than committed: a fixture AGENTS.md would be an instruction
# file at depth that agents load when they work in its directory.
edge = "x" * 81 + "\n"                      # 199 × 82 bytes + a 66-byte line = 16,384
boundary = edge * 199 + "y" * 65 + "\n"
assert len(boundary.encode("utf-8")) == 16384 and boundary.count("\n") == 200
budget = (
    ("computed-budget-at-limits", boundary, 0,
     ["ok:   AGENTS.md budget: 200 lines (max 200), 16384 bytes (max 16384)",
      "validate-versions: PASS (--only budget)"]),
    ("computed-budget-201-lines", "x\n" * 201, 1,
     ["FAIL: AGENTS.md budget: 201 lines (max 200), 402 bytes (max 16384) — over budget (R10)", SUMMARY_FAIL]),
    ("computed-budget-16385-bytes", boundary[:-1] + "y\n", 1,
     ["FAIL: AGENTS.md budget: 200 lines (max 200), 16385 bytes (max 16384) — over budget (R10)", SUMMARY_FAIL]),
    # wc -l would count 200: the final line has no newline, and it still counts
    ("computed-budget-unterminated-201st-line", "x\n" * 200 + "x", 1,
     ["FAIL: AGENTS.md budget: 201 lines (max 200), 401 bytes (max 16384) — over budget (R10)", SUMMARY_FAIL]),
)
for name, content, rc_want, lines_want in budget:
    count += 1
    failures += scratch_run(name, {"AGENTS.md": content}, "budget", rc_want, lines_want)

# Computed cases — --only refuses what would select nothing (exit 2, no check runs).
for name, only, needle in (
    ("computed-only-unknown-check", "budget,nosuch", "unknown check 'nosuch'"),
    ("computed-only-no-name", ",", "--only needs a check name"),
    ("computed-only-empty", "", "--only needs a check name"),
):
    count += 1
    tmp = tempfile.mkdtemp(prefix="vv-selftest-")
    try:
        rc, out, err = run(tmp, only)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    problems = []
    if rc != 2:
        problems.append("expected rc 2, got " + str(rc))
    if out.strip():
        problems.append("expected no check to run, stdout is not empty")
    if needle not in err:
        problems.append("stderr does not name " + repr(needle))
    failures += report(name, "--only " + repr(only) + " → rc " + str(rc) + ", " + needle, problems, [], out, err)

if failures:
    print("validate-versions --self-test: FAIL (" + str(failures) + " of " + str(count) + " cases)")
    sys.exit(1)
print("validate-versions --self-test: " + str(count) + " cases OK")
PYEOF
  exit 0
fi
if [ -n "$ROOT" ]; then
  cd "$ROOT"
fi

FAILED_CHECKS=0
fail() { printf 'FAIL: %s\n' "$1"; FAILED_CHECKS=$((FAILED_CHECKS + 1)); }
ok()   { printf 'ok:   %s\n' "$1"; }

# Shipped-surface scope, shared by checks 2 and 4 (and the README ledger
# boundary by checks 5 and 11). GNU grep prints ./path, BSD grep prints path —
# the RE accepts both prefixes. The self-test's fixtures plant a second ladder
# and stale pins on purpose, so the checkout's own run skips them.
SWEEP_EXCLUDE_RE='^(\./)?(ops/research|ops/decisions|docs/plans|docs/brainstorms|ops/solutions|docs/images|scripts/fixtures/validate-versions|\.git|\.agents|\.gemini|\.antigravity|node_modules)/'
# Whole directories are pruned at walk time (grep never descends into .git's
# object store or a node_modules tree); the path-scoped exclusions above are
# applied on the output, where the RE also re-covers the pruned names.
SWEEP_EXCLUDE_DIRS=(--exclude-dir=.git --exclude-dir=.agents --exclude-dir=.gemini --exclude-dir=.antigravity --exclude-dir=node_modules)
SWEEP_SELF_RE='^(\./)?scripts/validate-(versions|skills)\.sh:'
README_HISTORY_START=$(grep -n '^## Recent changes' README.md 2>/dev/null | head -1 | cut -d: -f1 || true)
README_HISTORY_START="${README_HISTORY_START:-0}"
# _shipped_surfaces: filter grep -rn output (file:line:text) down to the
# shipped surfaces — drops the excluded paths, this script, and README.md at
# or below its release ledger.
_shipped_surfaces() {
  grep -vE "$SWEEP_EXCLUDE_RE" \
    | grep -vE "$SWEEP_SELF_RE" \
    | awk -F: -v start="$README_HISTORY_START" \
        '!( (($1 == "README.md") || ($1 == "./README.md")) && start > 0 && ($2 + 0) >= start )' \
    || true
}

# --- 1. version lockstep -----------------------------------------------------
json_version() {
  VV_FILE="$1" python3 -c 'import json, os; print(json.load(open(os.environ["VV_FILE"]))["version"])'
}
PLUGIN_V=""
if _selected lockstep || _selected skill-versions; then
  PLUGIN_V=$(json_version .claude-plugin/plugin.json)
fi
if _selected lockstep; then
  AGY_V=$(json_version antigravity-agents/plugin.json)
  # The marketplace manifest carries the version twice (metadata + the one
  # plugin entry); both must move with plugin.json.
  MKT_V=$(VV_FILE=.claude-plugin/marketplace.json python3 -c 'import json, os; d = json.load(open(os.environ["VV_FILE"])); m = d.get("metadata", {}).get("version", ""); p = [x.get("version", "") for x in d.get("plugins", []) if x.get("name") == "agent-triforge"]; print(m if p == [m] else "mismatch(metadata=" + m + ",plugin=" + ",".join(p) + ")")' 2>/dev/null || echo "unreadable")
  README_V=$(grep -m1 -E "^## What's new \(v[0-9]+\.[0-9]+\.[0-9]+\)" README.md \
    | sed -E "s/^## What's new \(v([0-9]+\.[0-9]+\.[0-9]+)\).*/\1/" || true)
  if [ -z "$README_V" ]; then
    fail "version lockstep: README.md has no '## What's new (vX.Y.Z)' heading"
  elif [ "$PLUGIN_V" = "$AGY_V" ] && [ "$PLUGIN_V" = "$README_V" ] && [ "$PLUGIN_V" = "$MKT_V" ]; then
    ok "version lockstep: $PLUGIN_V (.claude-plugin/plugin.json, .claude-plugin/marketplace.json, antigravity-agents/plugin.json, README What's new)"
  else
    fail "version lockstep: .claude-plugin/plugin.json=$PLUGIN_V .claude-plugin/marketplace.json=$MKT_V antigravity-agents/plugin.json=$AGY_V README What's new=$README_V"
  fi
  # Release-notes source: literal "v<version>:" on a "### " heading below
  # "## Recent changes" (the colon keeps v3.3.1 from matching v3.3.10).
  if awk -v v="$PLUGIN_V" '
        /^## Recent changes/ { led = 1; next }
        led && /^### / && index($0, "v" v ":") > 0 { found = 1; exit }
        END { exit !found }
      ' README.md; then
    ok "release notes: README Recent changes carries the v$PLUGIN_V entry (GitHub release body source)"
  else
    fail "release notes: README.md '## Recent changes' has no '### <date> — v$PLUGIN_V: <title>' entry — scripts/release-notes.sh needs it for the GitHub release"
  fi
fi
# Skill versions: each shipped skill's frontmatter metadata.version moves with
# the plugin. The frontmatter is read as validate-skills.sh reads it: metadata
# is one level of indented key: value lines, a quoted value is unquoted, and an
# unquoted one loses a trailing " # comment".
if _selected skill-versions; then
  SKILLV_RC=0
  VV_PLUGIN_V="$PLUGIN_V" python3 - <<'PYEOF' || SKILLV_RC=$?
import glob
import os
import re
import sys

want = os.environ["VV_PLUGIN_V"]


def unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return re.sub(r"\s+#.*$", "", value)


def meta_version(path):
    """metadata.version in the frontmatter of path; None without one."""
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    if lines[0].strip() != "---":
        return None
    found, in_meta, base = None, False, None
    for line in lines[1:]:
        if line.strip() == "---":
            return found
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        indent = len(line) - len(line.lstrip())
        if indent == 0:
            in_meta, base = re.match(r"^metadata:\s*$", line) is not None, None
        elif in_meta:
            base = indent if base is None else base
            m = re.match(r"^version:(.*)$", line.strip())
            if m and indent == base:
                found = unquote(m.group(1))
    return None    # no closing ---, so no frontmatter


skills = sorted(glob.glob("skills/*/SKILL.md"))
fails = [] if skills else ["no skills/*/SKILL.md found"]
for path in skills:
    try:
        have = meta_version(path)
    except (OSError, UnicodeDecodeError) as exc:
        fails.append(path + " unreadable (" + str(exc) + ")")
        continue
    if have is None:
        fails.append(path + " has no metadata.version; .claude-plugin/plugin.json is \"" + want + "\"")
    elif have != want:
        fails.append(path + " metadata.version is \"" + have + "\"; .claude-plugin/plugin.json is \"" + want + "\"")
for line in fails:
    print("FAIL: skill versions: " + line)
if fails:
    sys.exit(1)
print("ok:   skill versions: all " + str(len(skills)) + " skills/*/SKILL.md carry metadata.version " + want + " (= .claude-plugin/plugin.json)")
PYEOF
  if [ "$SKILLV_RC" -ne 0 ]; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
fi

# --- 2. ladder one-definition (KTD22) ----------------------------------------
LADDER_SOURCE='scripts/lib/registry.sh'
LADDER_VAR='TRIFORGE_MODEL_LADDER'
if _selected ladder; then
  # A definition is the phrase followed by a colon, whatever rungs come after it
  # (a restatement that starts at `opus` is still a second definition); pointer
  # lines put " — " after the phrase, so only the registry literal matches.
  # Case-insensitive, and markup or spaces between the phrase and the colon do
  # not hide a definition. (This script is filtered out by _shipped_surfaces.)
  LADDER_DEF_RE='Downgrade ladder for narrow runtime tasks[[:space:]*_`]*:'
  LADDER_DEFS=$(
    grep -rnIiE "${SWEEP_EXCLUDE_DIRS[@]}" -e "$LADDER_DEF_RE" . \
      | _shipped_surfaces \
      | sort -t: -k1,1 -k2,2n -u || true
  )
  LADDER_DEF_COUNT=$(printf '%s\n' "$LADDER_DEFS" | grep -c . || true)
  LADDER_DEF_FILE=$(printf '%s\n' "$LADDER_DEFS" | head -1 | cut -d: -f1 | sed 's#^\./##')
  LADDER_DEF_LINE=$(printf '%s\n' "$LADDER_DEFS" | head -1 | cut -d: -f2)
  LADDER_DEF_TEXT=$(printf '%s\n' "$LADDER_DEFS" | head -1 | cut -d: -f3-)
  # The one match must be the registry assignment itself, not a comment there.
  LADDER_IS_LITERAL=0
  case "$LADDER_DEF_TEXT" in
    "${LADDER_VAR}='"*) LADDER_IS_LITERAL=1 ;;
  esac
  if [ "$LADDER_DEF_COUNT" -eq 1 ] && [ "$LADDER_DEF_FILE" = "$LADDER_SOURCE" ] && [ "$LADDER_IS_LITERAL" -eq 1 ]; then
    ok "ladder: one definition ($LADDER_SOURCE:$LADDER_DEF_LINE $LADDER_VAR)"
  elif [ "$LADDER_DEF_COUNT" -eq 0 ]; then
    fail "ladder: no definition — $LADDER_SOURCE must set $LADDER_VAR to the ladder text (the phrase 'Downgrade ladder for narrow runtime tasks', a colon, the rungs)"
  elif [ "$LADDER_DEF_COUNT" -eq 1 ] && [ "$LADDER_DEF_FILE" = "$LADDER_SOURCE" ]; then
    printf '%s\n' "$LADDER_DEFS"
    fail "ladder: $LADDER_SOURCE:$LADDER_DEF_LINE carries the ladder text but is not the $LADDER_VAR='...' assignment (a comment or another variable)"
  elif [ "$LADDER_DEF_COUNT" -eq 1 ]; then
    printf '%s\n' "$LADDER_DEFS"
    fail "ladder: the single definition is in $LADDER_DEF_FILE:$LADDER_DEF_LINE, not the $LADDER_VAR literal in $LADDER_SOURCE"
  else
    printf '%s\n' "$LADDER_DEFS"
    fail "ladder: $LADDER_DEF_COUNT definitions (expected exactly 1: $LADDER_VAR in $LADDER_SOURCE) — every line with the phrase followed by a colon counts, whichever rung it starts at; replace the others with pointers (see file:line:text above)"
  fi
fi

# --- 3. registry drift (KTD7) ------------------------------------------------
if _selected drift; then
  DRIFT_RC=0
  VV_REGISTRY="scripts/lib/registry.sh" VV_SRC="scripts/lib/roster.sh" VV_ROSTER="templates/ops/roster.toml" \
  VV_HOOK="hooks/handlers/session-start.sh" VV_LEASE="scripts/lib/lease.sh" VV_LEASE_WAIT="scripts/lib/lease-wait.sh" VV_PROBE="scripts/probe-capabilities.sh" \
  VV_LOADER="scripts/invoke-external.sh" VV_LOCATOR="scripts/skill-locator/locate-triforge.sh" \
  VV_LIBDIR="scripts/lib" python3 - <<'PYEOF' || DRIFT_RC=$?
import ast
import glob
import os
import re
import shlex
import sys

try:
    import tomllib
except ImportError:
    try:
        import tomli as tomllib
    except ImportError:
        print("FAIL: drift: no TOML parser (Python 3.11+ tomllib or pip install tomli)")
        sys.exit(1)

fails = []
oks = []


def read(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        fails.append(path + " unreadable: " + str(exc))
        return None


def code_lines(text):
    """(lineno, line) for every line that is not a comment."""
    return [(n, ln) for n, ln in enumerate(text.split("\n"), 1) if not ln.lstrip().startswith("#")]


def func_body(text, name, path):
    """The body of a top-level shell function '<name>() {' ... '}' (first column brace)."""
    m = re.search(r"^" + re.escape(name) + r"\(\) \{[^\n]*\n(.*?)^\}", text, re.M | re.S)
    if not m:
        fails.append(path + ": " + name + "() not found")
        return None
    return m.group(1)


NAME_RE = re.compile(r"^[A-Z_][A-Z0-9_]*$")
WILDCARDS_OK = ("KIMI_*",)
FIELDS = {
    "name": str, "tier": str, "binary": str, "binary_env": str, "resolver": str, "version_re": str,
    "model": str, "model_env": str, "install": str, "login": str, "env_keys": list, "lane": str,
    "egress": str, "role_limit": list, "opt_in_roles": list, "consent": bool, "instructions": str, "lead": dict,
}
LEAD_FIELDS = {
    "launch_argv": str, "model_argv": str, "effort_argv": str, "full_access": bool, "wait_budget_s": int, "tool_vocab_read": str, "tool_vocab_action": str,
    "goal_gate": str, "ask_user": str, "native_subagents_enforced_tools": bool, "agent_teams": bool,
    "plugin_root_env": str,
}

# --- the registry literal ----------------------------------------------------
reg_path = os.environ["VV_REGISTRY"]
reg = read(reg_path)
clis = None
env_base = []
launch_full_access = launch_extra_words = None
if reg is not None:
    m = re.search(r"^_LAUNCH_ACCESS_PY='\n(.*?)\n'$", reg, re.M | re.S)
    if not m:
        fails.append(reg_path + ": _LAUNCH_ACCESS_PY='...' not found — the full-access detector lead.full_access is checked against")
    elif "'" in m.group(1):
        fails.append(reg_path + ": _LAUNCH_ACCESS_PY contains a single quote — the shell literal ends there")
    else:
        try:
            ns = {}
            exec(m.group(1), ns)  # noqa: S102 — this checkout's own registry
            launch_full_access, launch_extra_words = ns["launch_full_access"], ns["launch_extra_words"]
        except Exception as exc:  # noqa: BLE001 — report, do not crash
            fails.append(reg_path + ": _LAUNCH_ACCESS_PY does not define launch_full_access and launch_extra_words: " + str(exc))
    m = re.search(r"^_TRIFORGE_CLIS_PY='\n(.*?)\n'$", reg, re.M | re.S)
    if not m:
        fails.append(reg_path + ": _TRIFORGE_CLIS_PY='...' literal not found")
    else:
        body = m.group(1)
        if "'" in body:
            fails.append(reg_path + ": _TRIFORGE_CLIS_PY contains a single quote — the shell literal ends there (use double quotes inside)")
        if not body.startswith("CLIS = {"):
            fails.append(reg_path + ": _TRIFORGE_CLIS_PY must start with 'CLIS = {'")
        else:
            try:
                clis = ast.literal_eval(body[len("CLIS = "):])
            except Exception as exc:  # noqa: BLE001 — report, do not crash
                fails.append(reg_path + ": _TRIFORGE_CLIS_PY is not a pure literal (ast.literal_eval): " + str(exc))
            if clis is not None and not isinstance(clis, dict):
                fails.append(reg_path + ": CLIS must be a dict of cli -> entry")
                clis = None
    m = re.search(r'^TRIFORGE_ENV_BASE="([^"]*)"[ \t]*$', reg, re.M)
    if not m:
        fails.append(reg_path + ': TRIFORGE_ENV_BASE="..." not found')
    else:
        env_base = m.group(1).split()
        if not env_base:
            fails.append(reg_path + ": TRIFORGE_ENV_BASE is empty")
        for k in env_base:
            if not NAME_RE.match(k):
                fails.append(reg_path + ": TRIFORGE_ENV_BASE key " + repr(k) + " is not an exact variable name")

core = []
if clis is not None:
    shape_ok = True
    for cli, e in clis.items():
        where = reg_path + ": registry entry " + repr(cli)
        if not re.match(r"^[a-z][a-z0-9_-]*$", str(cli)):
            fails.append(where + ": name must be lowercase [a-z0-9_-]")
            shape_ok = False
        if not isinstance(e, dict):
            fails.append(where + ": entry must be a dict")
            shape_ok = False
            continue
        missing = [f for f in FIELDS if f not in e]
        extra = [f for f in e if f not in FIELDS]
        if missing:
            fails.append(where + ": missing field(s) " + ", ".join(missing))
            shape_ok = False
        if extra:
            fails.append(where + ": unknown field(s) " + ", ".join(extra))
            shape_ok = False
        for f, t in FIELDS.items():
            if f in e and (type(e[f]) is not t):
                fails.append(where + ": field " + f + " must be " + t.__name__ + ", got " + type(e[f]).__name__)
                shape_ok = False
        if e.get("tier") not in ("core", "optional"):
            fails.append(where + ": tier must be core|optional, got " + repr(e.get("tier")))
            shape_ok = False
        if e.get("lane") not in ("shell", "subagent"):
            fails.append(where + ": lane must be shell|subagent, got " + repr(e.get("lane")))
            shape_ok = False
        if not e.get("binary"):
            fails.append(where + ": binary is empty")
            shape_ok = False
        for f in ("binary_env", "model_env"):
            if e.get(f) and not NAME_RE.match(e[f]):
                fails.append(where + ": " + f + " " + repr(e[f]) + " is not an exact variable name")
                shape_ok = False
        for k in e.get("env_keys", []) if isinstance(e.get("env_keys"), list) else []:
            if not isinstance(k, str):
                fails.append(where + ": env_keys entries must be strings")
                shape_ok = False
            elif "*" in k:
                if k not in WILDCARDS_OK:
                    fails.append(where + ": env_keys " + repr(k) + " carries a wildcard — allowlist keys are exact variable names; the one documented exception is KIMI_*")
                    shape_ok = False
            elif not NAME_RE.match(k):
                fails.append(where + ": env_keys " + repr(k) + " is not an exact variable name")
                shape_ok = False
        lead = e.get("lead")
        if isinstance(lead, dict) and lead:
            lmissing = [f for f in LEAD_FIELDS if f not in lead]
            lextra = [f for f in lead if f not in LEAD_FIELDS]
            if lmissing or lextra:
                fails.append(where + ": lead must carry exactly the KTD1 fields" + (" — missing " + ", ".join(lmissing) if lmissing else "") + (" — unknown " + ", ".join(lextra) if lextra else ""))
                shape_ok = False
            for f, t in LEAD_FIELDS.items():
                if f in lead and type(lead[f]) is not t:
                    fails.append(where + ": lead." + f + " must be " + t.__name__ + ", got " + type(lead[f]).__name__)
                    shape_ok = False
            if not lead.get("launch_argv"):
                fails.append(where + ": lead.launch_argv is empty")
                shape_ok = False
            for f in ("model_argv", "effort_argv"):
                if isinstance(lead.get(f), str) and lead[f] and "{}" not in lead[f]:
                    fails.append(where + ": lead." + f + " has no {} where the value goes")
                    shape_ok = False
            # The declaration and what the shipped launch line does must agree
            # (coordinate.sh asks for --allow-full-access when either says so).
            if launch_full_access is not None and isinstance(lead.get("launch_argv"), str) and isinstance(lead.get("full_access"), bool):
                try:
                    words = shlex.split(lead["launch_argv"])
                    for f in ("model_argv", "effort_argv"):
                        if isinstance(lead.get(f), str) and lead[f]:
                            words += launch_extra_words(lead[f], "x")
                    why = launch_full_access(words)
                except ValueError as exc:
                    why = None
                    fails.append(where + ": lead.launch_argv does not split into shell words: " + str(exc))
                if why is not None and bool(why) != lead["full_access"]:
                    fails.append(where + ": lead.full_access = " + str(lead["full_access"]) + " but its launch line reads as "
                                 + ("full access (" + "; ".join(why) + ")" if why else "no full access") + " — declare what the line does")
                    shape_ok = False
        if e.get("tier") == "core":
            core.append(cli)
    if not core:
        fails.append(reg_path + ": no core-tier CLI — every fallback chain must end at one")
        shape_ok = False
    if shape_ok:
        leads = [c for c, e in clis.items() if isinstance(e.get("lead"), dict) and e["lead"]]
        oks.append(reg_path + " registry: " + str(len(clis)) + " CLIs (" + ", ".join(clis) + "), core: " + ", ".join(core)
                   + ", lead-capable: " + ", ".join(leads) + "; env_keys exact (KIMI_* the one wildcard); TRIFORGE_ENV_BASE " + " ".join(env_base))

models = {c: e.get("model", "") for c, e in clis.items()} if clis is not None else {}

# --- scripts/lib/roster.sh: the one role table, no per-CLI copies -------------
src_path = os.environ["VV_SRC"]
src = read(src_path)
role_defaults = None
if src is not None:
    pat = re.compile(r"^([ \t]*)DEFAULTS = \{\n(.*?)^\1\}[ \t]*$", re.M | re.S)
    blocks = list(pat.finditer(src))
    if len(blocks) != 1:
        fails.append(src_path + ": expected exactly 1 DEFAULTS literal (_ROLE_DEFAULTS_PY), found " + str(len(blocks)))
    else:
        b = blocks[0]
        try:
            role_defaults = ast.literal_eval("{\n" + b.group(2) + "}")
        except Exception as exc:  # noqa: BLE001
            fails.append(src_path + ": DEFAULTS at line " + str(src.count("\n", 0, b.start()) + 1) + " is not a pure literal: " + str(exc))
        decl = re.search(r"^_ROLE_DEFAULTS_PY='", src, re.M)
        if not decl or not (decl.start() < b.start()):
            fails.append(src_path + ": the DEFAULTS literal must live in _ROLE_DEFAULTS_PY (spliced into resolve_role and roster_role_entry)")
    if "${_TRIFORGE_CLIS_PY}" not in src:
        fails.append(src_path + ": does not splice ${_TRIFORGE_CLIS_PY} — per-CLI data must come from the registry")
    copy_re = re.compile(r"^[ \t]*(CLI_DEFAULT_MODEL|BINARY|INSTALL_FIX|KNOWN|CORE_TRIO|CORE)[ \t]*=[ \t]*[\{\(\[][ \t]*($|['\"])")
    for n, ln in code_lines(src):
        if copy_re.match(ln):
            fails.append(src_path + ":" + str(n) + ": literal copy of registry data (" + ln.strip()[:60] + ") — derive it from CLIS")
    if role_defaults is not None and clis is not None:
        # role limits and opt-ins (R24): DEFAULTS roles only, opt-ins only
        # outside a limit, and no limit or consent on a core CLI
        lim_fail = False
        for cli, e in clis.items():
            lim = e.get("role_limit", []) if isinstance(e.get("role_limit"), list) else []
            opt = e.get("opt_in_roles", []) if isinstance(e.get("opt_in_roles"), list) else []
            where = reg_path + ": registry entry " + repr(cli)
            for r in lim + opt:
                if r not in role_defaults:
                    fails.append(where + ": role " + repr(r) + " in role_limit/opt_in_roles is not a DEFAULTS role (" + ", ".join(role_defaults) + ")")
                    lim_fail = True
            if len(set(lim + opt)) != len(lim + opt):
                fails.append(where + ": role_limit and opt_in_roles name a role twice")
                lim_fail = True
            if opt and not lim:
                fails.append(where + ": opt_in_roles without a role_limit — an unlimited CLI takes every role already")
                lim_fail = True
            if e.get("tier") == "core" and (lim or e.get("consent") is True):
                fails.append(where + ": a core CLI carries no role_limit or consent — every fallback chain ends at one")
                lim_fail = True
        if not lim_fail:
            limited = [c + "(" + "+".join(e["role_limit"]) + ")" for c, e in clis.items() if e.get("role_limit")]
            oks.append(reg_path + " role limits: " + (", ".join(limited) or "none") + "; consent: " + (", ".join(c for c, e in clis.items() if e.get("consent") is True) or "none"))
        role_fail = False
        for role, d in role_defaults.items():
            if not isinstance(d, dict):
                fails.append(src_path + ": DEFAULTS[" + repr(role) + "] is not a table")
                role_fail = True
                continue
            cli = d.get("cli")
            chain = [cli] + list(d.get("fallbacks", []))
            for c in chain:
                if c not in clis:
                    fails.append(src_path + ": DEFAULTS[" + repr(role) + "] names unregistered CLI " + repr(c))
                    role_fail = True
            if cli in clis and d.get("model") != models.get(cli):
                fails.append(src_path + ": DEFAULTS[" + repr(role) + "].model = " + repr(d.get("model")) + " but the registry model for " + str(cli) + " is " + repr(models.get(cli)))
                role_fail = True
            if chain and chain[-1] in clis and chain[-1] not in core:
                fails.append(src_path + ": DEFAULTS[" + repr(role) + "] chain " + repr(chain) + " does not end at a core CLI")
                role_fail = True
        if not role_fail:
            oks.append(src_path + " DEFAULTS: one literal, " + str(len(role_defaults)) + " roles, each model equal to its CLI's registry model, chains end at a core CLI")

# --- templates/ops/roster.toml vs DEFAULTS / the registry ---------------------
roster_path = os.environ["VV_ROSTER"]
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
roster_text = read(roster_path)
if roster_text is not None and clis is not None:
    doc_fail = False
    documented = re.findall(r"\[members\.([a-z0-9_-]+)\][^\[]*?model = \"([^\"]*)\"", roster_text, re.S)
    for cli, model in documented:
        if cli not in clis:
            fails.append(roster_path + " documents [members." + cli + "], which the registry does not know")
            doc_fail = True
        elif model != models[cli]:
            fails.append(roster_path + " documents [members." + cli + "] model = " + repr(model) + " but the registry model is " + repr(models[cli]))
            doc_fail = True
    if not doc_fail:
        oks.append(roster_path + " documented member pins match the registry (" + str(len(documented)) + " members)")

# --- hooks/handlers/session-start.sh: reads, never copies ---------------------
hook_path = os.environ["VV_HOOK"]
hook = read(hook_path)
if hook is not None:
    hook_fail = False
    # A literal copy opens with a newline or a quoted key; the hook's own
    # derivations (SHIPPED = {cli: e["model"] for ...}) open with a name.
    for n, ln in code_lines(hook):
        if re.match(r"^[ \t]*(SHIPPED|ROLE_CLI)[ \t]*=[ \t]*\{[ \t]*($|['\"])", ln):
            fails.append(hook_path + ":" + str(n) + ": literal copy of registry data (" + ln.strip()[:40] + ") — the hook reads _TRIFORGE_CLIS_PY / _ROLE_DEFAULTS_PY")
            hook_fail = True
    if "_TRIFORGE_CLIS_PY" not in hook:
        fails.append(hook_path + ": does not read the registry (_TRIFORGE_CLIS_PY)")
        hook_fail = True
    if "_ss_resolve_cursor_bin" in hook:
        fails.append(hook_path + ": still carries _ss_resolve_cursor_bin — the registry names _cursor_bin as cursor's resolver")
        hook_fail = True
    if not hook_fail:
        oks.append(hook_path + " reads the registry (no SHIPPED / ROLE_CLI / cursor-resolver copy)")

# --- scripts/lib/lease.sh: _adapter_env reads the registry ---------------------
lease_path = os.environ["VV_LEASE"]
lease = read(lease_path)
if lease is not None and clis is not None:
    lease_fail = False
    body = func_body(lease, "_adapter_env", lease_path)
    if body is not None:
        if "TRIFORGE_ENV_BASE" not in body or "cli_field" not in body:
            fails.append(lease_path + ": _adapter_env must read TRIFORGE_ENV_BASE and cli_field (the registry), not a hand-written list")
            lease_fail = True
        keys = set()
        for e in clis.values():
            for k in e.get("env_keys", []):
                keys.add(k[:-1] if k.endswith("*") else k)
        start = lease.find(body)
        base_line = lease.count("\n", 0, start) + 1
        for i, ln in enumerate(body.split("\n")):
            if ln.lstrip().startswith("#"):
                continue
            for k in env_base:
                if re.search(r"\b" + k + r"=\$\{" + k + r"\b", ln):
                    fails.append(lease_path + ":" + str(base_line + i) + ": _adapter_env hand-copies base key " + k + " — it is read from TRIFORGE_ENV_BASE")
                    lease_fail = True
            for k in sorted(keys):
                if re.search(r"\b" + re.escape(k), ln):
                    fails.append(lease_path + ":" + str(base_line + i) + ": _adapter_env names credential key " + k + " in code — keys come from the registry env_keys")
                    lease_fail = True
    # the lease subsystem spans lease.sh and lease-wait.sh (the lane composer
    # _lease_lane_argv lives in the second): neither spells a shipped model
    wait_path = os.environ["VV_LEASE_WAIT"]
    for scan_path, scan in ((lease_path, lease), (wait_path, read(wait_path))):
        if scan is None:
            lease_fail = True
            continue
        for n, ln in code_lines(scan):
            for cli, model in models.items():
                if model and model in ln:
                    fails.append(scan_path + ":" + str(n) + ": shipped " + cli + " model " + repr(model) + " spelled out in code — read it with cli_field " + cli + " model")
                    lease_fail = True
    if not lease_fail:
        oks.append(lease_path + " _adapter_env reads TRIFORGE_ENV_BASE + env_keys; no model literal in " + lease_path + " or " + wait_path + " code")

# --- the lanes: ${<model_env>:-default} equals the registry model -------------
if clis is not None:
    lane_fail = False
    seen = 0
    for path in sorted(glob.glob(os.path.join(os.environ["VV_LIBDIR"], "*.sh"))):
        text = read(path)
        if text is None:
            continue
        for cli, e in clis.items():
            if not e.get("model_env"):
                continue
            for n, ln in code_lines(text):
                for dflt in re.findall(r"\$\{" + re.escape(e["model_env"]) + r":-([^}]*)\}", ln):
                    if dflt == "":
                        continue    # ${X_MODEL:-} is a set-test, not a default
                    seen += 1
                    if dflt != e["model"]:
                        fails.append(path + ":" + str(n) + ": ${" + e["model_env"] + ":-" + dflt + "} but the registry model for " + cli + " is " + repr(e["model"]))
                        lane_fail = True
    if not lane_fail:
        oks.append("lane defaults: " + str(seen) + " ${<model_env>:-…} default(s) in scripts/lib/*.sh equal the registry model")

# --- scripts/probe-capabilities.sh: _lane_run mirror + the codex pin ----------
probe_path = os.environ["VV_PROBE"]
probe = read(probe_path)
if probe is not None and clis is not None:
    probe_fail = False
    body = func_body(probe, "_lane_run", probe_path)
    if body is not None and "REG_ENV_BASE" not in body:
        fails.append(probe_path + ": _lane_run must iterate REG_ENV_BASE (TRIFORGE_ENV_BASE read through the loader), not a hand-written list")
        probe_fail = True
    if "codex" in clis:
        m = re.search(r'^CDX_MODEL="([^"]*)"', probe, re.M)
        if not m:
            fails.append(probe_path + ': CDX_MODEL="..." not found')
            probe_fail = True
        elif m.group(1) != models["codex"]:
            fails.append(probe_path + ": CDX_MODEL = " + repr(m.group(1)) + " but the registry codex model is " + repr(models["codex"]))
            probe_fail = True
    if not probe_fail:
        oks.append(probe_path + " _lane_run reads REG_ENV_BASE; CDX_MODEL equals the registry codex model")

# --- the Triforge-root test: the loader and the skill locator carry one copy each
loader_path = os.environ["VV_LOADER"]
locator_path = os.environ["VV_LOCATOR"]
loader = read(loader_path)
locator = read(locator_path)
if loader is not None and locator is not None:
    root_a = func_body(loader, "_triforge_is_plugin_root", loader_path)
    root_b = func_body(locator, "is_triforge_root", locator_path)
    if root_a is not None and root_b is not None:
        if root_a.replace("_triforge_is_plugin_root", "@") == root_b.replace("is_triforge_root", "@"):
            oks.append("Triforge-root test: _triforge_is_plugin_root (" + loader_path + ") and is_triforge_root (" + locator_path + ") have the same body")
        else:
            fails.append(loader_path + " _triforge_is_plugin_root() and " + locator_path + " is_triforge_root() differ — the two copies of the Triforge-root test must stay identical apart from the function name (edit both)")

for line in oks:
    print("ok:   drift: " + line)
for line in fails:
    print("FAIL: drift: " + line)
sys.exit(1 if fails else 0)
PYEOF
  if [ "$DRIFT_RC" -ne 0 ]; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
fi

# --- 4. scoped stale-pin sweep (KTD12) ---------------------------------------
if _selected sweep; then
  if [ "$NO_SWEEP" -eq 1 ]; then
    echo "skip: stale-pin sweep (--no-sweep)"
  else
    SWEEP_HITS=$(
      {
        grep -rnI "${SWEEP_EXCLUDE_DIRS[@]}" \
          -e 'gpt-5\.6-sol' \
          -e 'grok-4\.5' \
          -e 'glm-5\.2' \
          -e 'kimi-k3' \
          -e 'Fable 5 →' \
          -e 'Opus 4\.8' \
          -e 'Opus 5\.5 → Sonnet 5[^.]' \
          -e 'Opus 5\.5 → Sonnet 5$' \
          -e 'Sonnet 5)' \
          -e 'Sonnet&nbsp;5[^.]' \
          -e '2026-07-probe-record' \
          . || true
        grep -rnI "${SWEEP_EXCLUDE_DIRS[@]}" 'Gemini 3\.1 Pro (High)' . | grep -i 'default' || true
      } \
        | grep -v 'history\|was [a-z]' \
        | _shipped_surfaces \
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
fi

# --- 5. surface counts -------------------------------------------------------
PERSONA_COUNT=$(ls personas/*.md 2>/dev/null | grep -c . || true)
SKILL_COUNT=$(ls skills/*/SKILL.md 2>/dev/null | grep -c . || true)
WORKFLOW_COUNT=$(ls skills/at-*/SKILL.md 2>/dev/null | grep -c . || true)
PORTABLE_COUNT=$((SKILL_COUNT - WORKFLOW_COUNT))
if _selected counts; then
  if [ "$NO_COUNTS" -eq 1 ]; then
    echo "skip: surface counts (--no-counts; shipped: $PERSONA_COUNT personas, $SKILL_COUNT skills: $PORTABLE_COUNT portable, $WORKFLOW_COUNT lead workflows)"
  else
    COUNTS_RC=0
    VV_PERSONAS="$PERSONA_COUNT" VV_SKILLS="$SKILL_COUNT" VV_PORTABLE="$PORTABLE_COUNT" VV_WORKFLOWS="$WORKFLOW_COUNT" \
    VV_README_HISTORY_START="$README_HISTORY_START" python3 - <<'PYEOF' || COUNTS_RC=$?
import os
import re
import sys

# "N skills" is every skill, "N portable skills" the non-at- set, "N lead
# workflows" the at-* set (U23 vocabulary); "N personas" the persona files
# (U8), and "N agents" still counts against them.
actual = {
    "persona": int(os.environ["VV_PERSONAS"]),
    "skill": int(os.environ["VV_SKILLS"]),
    "portable skill": int(os.environ["VV_PORTABLE"]),
    "lead workflow": int(os.environ["VV_WORKFLOWS"]),
}
# A claim's surface word, lowercased and singular, to the count it checks.
KIND = {"agent": "persona"}
readme_history_start = int(os.environ["VV_README_HISTORY_START"] or "0")
files = [
    "AGENTS.md",
    "templates/AGENTS.md",
    "README.md",
    "docs/index.html",
    "docs/agent-triforge.md",
    ".claude-plugin/plugin.json",
]
CLAIM = re.compile(
    r"(?P<pre>(?:\+|\ball|of the|the other|\bother)\s+)?"
    r"\b(?P<n>\d+)\s+(?P<mods>(?:[A-Za-z-]+\s+){0,3}?)(?P<sub>sub)?(?P<kind>agent|persona|skill|lead workflow)s?\b",
    re.I,
)
SUBSET_WORDS = {
    "parallel", "review", "research", "external", "reviewer", "reviewers",
    "background", "concurrent", "additional", "new", "more", "remaining", "other",
}
SURFACE_MODS = {"specialized", "portable", "shipped", "focused", "model-agnostic", "methodology"}
SURFACE_LINE = re.compile(
    r"\bship|plugin|portable|specialized|surface|focused|model-agnostic|methodology"
    r"|lead workflows?|agents/|personas/|skills/|restricted tools",
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
                kind = KIND.get(m.group("kind").lower(), m.group("kind").lower())
                if kind == "skill" and "portable" in mods:
                    kind = "portable skill"
                n = int(m.group("n"))
                claims += 1
                if n != actual[kind]:
                    mismatches.append(
                        path + ":" + str(lineno) + ": says " + str(n) + " " + kind + "s, shipped "
                        + str(actual[kind]) + " — " + m.group(0).strip()
                    )

# Landing-page hero counters carry the number in a data-target attribute and
# the surface name in the next span, so the prose CLAIM regex never sees them.
HERO = re.compile(
    r'data-target="(?P<n>\d+)">0</span>\s*<span class="hero__stat-label">(?P<kind>Personas|Agents|Skills|Portable skills|Lead workflows)</span>'
)
if os.path.exists("docs/index.html"):
    with open("docs/index.html", encoding="utf-8") as fh:
        html = fh.read()
    for m in HERO.finditer(html):
        kind = m.group("kind").lower().rstrip("s")
        kind = KIND.get(kind, kind)
        n = int(m.group("n"))
        claims += 1
        if n != actual[kind]:
            lineno = html.count("\n", 0, m.start()) + 1
            mismatches.append(
                "docs/index.html:" + str(lineno) + ": hero counter says " + str(n) + " " + kind + "s, shipped "
                + str(actual[kind]) + " — data-target=\"" + str(n) + "\" " + m.group("kind")
            )

for line in mismatches:
    print("FAIL: counts: " + line)
if mismatches:
    sys.exit(1)
print(
    "ok:   surface counts: " + str(claims) + " claims match shipped "
    + str(actual["persona"]) + " personas / " + str(actual["skill"]) + " skills ("
    + str(actual["portable skill"]) + " portable, " + str(actual["lead workflow"]) + " lead workflows)"
)
PYEOF
    if [ "$COUNTS_RC" -ne 0 ]; then
      FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
  fi
fi

# --- 6. AGENTS.md budget (R10) -----------------------------------------------
AGENTS_MD='AGENTS.md'
AGENTS_MD_MAX_LINES=200
AGENTS_MD_MAX_BYTES=16384
if _selected budget; then
  if [ -f "$AGENTS_MD" ]; then
    # awk counts a final line without a trailing newline; wc -l would not.
    AGENTS_MD_LINES=$(awk 'END { print NR }' "$AGENTS_MD")
    AGENTS_MD_BYTES=$(wc -c < "$AGENTS_MD" | tr -d ' ')
    if [ "$AGENTS_MD_LINES" -le "$AGENTS_MD_MAX_LINES" ] && [ "$AGENTS_MD_BYTES" -le "$AGENTS_MD_MAX_BYTES" ]; then
      ok "AGENTS.md budget: $AGENTS_MD_LINES lines (max $AGENTS_MD_MAX_LINES), $AGENTS_MD_BYTES bytes (max $AGENTS_MD_MAX_BYTES)"
    else
      fail "AGENTS.md budget: $AGENTS_MD_LINES lines (max $AGENTS_MD_MAX_LINES), $AGENTS_MD_BYTES bytes (max $AGENTS_MD_MAX_BYTES) — over budget (R10)"
    fi
  else
    echo "skip: AGENTS.md budget (no root $AGENTS_MD yet)"
  fi
fi

# --- 7. rule-inventory completeness (R11) ------------------------------------
INVENTORY_MD='docs/rule-inventory.md'
if _selected inventory; then
  if [ -f "$INVENTORY_MD" ]; then
    INVENTORY_RC=0
    VV_INVENTORY="$INVENTORY_MD" python3 - <<'PYEOF' || INVENTORY_RC=$?
import glob
import html
import os
import re
import sys

path = os.environ["VV_INVENTORY"]
with open(path, encoding="utf-8") as fh:
    lines = fh.read().split("\n")

CELL_SPLIT = re.compile(r"(?<!\\)\|")          # an escaped \| stays inside its cell
SEPARATOR = re.compile(r"^\|?(\s*:?-+:?\s*\|)*\s*:?-+:?\s*\|?$")
TABLE_END = re.compile(r"^(#{1,6}(\s|$)|>|```|~~~)")   # a blank line ends a table too
SOURCE_HEADING = re.compile(r"^##\s+(.*?)\s*#*$")
DEST_HEADER = re.compile(r"destination|new home|now lives", re.I)
TBD = re.compile(r"\btbd\b", re.I)
# HTML that renders as nothing: a comment (closed or not) or a tag. An autolink
# (<https://…>, <a@b.c>) is not a tag: a tag name ends at a space, "/" or ">".
HTML = re.compile(r"<!--.*?(-->|$)|</?[A-Za-z][A-Za-z0-9-]*(\s[^>]*)?/?>")
PLACEHOLDERS = {"tbd", "tba", "todo", "tobedetermined", "tobedecided", "unknown"}
TOTALS = re.compile(r"^\*\*Totals\.\*\*")
TOTALS_COUNT = re.compile(r"^\*\*Totals\.\*\*\s+(\d+)\s+rows:")
TOTALS_SOURCE = re.compile(r"\s*`([^`]+)`\s+(\d+)\s*")
# Cited paths (see the header): what a destination cell names must exist.
QUOTED = re.compile(r'"[^"]*"')               # a quoted phrase is prose
BACKTICKED = re.compile(r"`([^`]+)`")
SECTION = re.compile(r"§[^;,]*")               # "§Invocation via invoke-external.sh" is a heading, not a file
PATH_SUFFIX = re.compile(r"\.(?:md|sh|py|json|toml|ya?ml|txt|html|js|css|local)$")
BRACE = re.compile(r"^(.*)\{([^}]*)\}(.*)$")


def cited_paths(cell):
    """Path tokens a destination cell names: backticked, or bare with a '/', a
    file suffix or a leading dot. Quoted phrases, §section names and tokens
    with shell or markup characters are not paths."""
    text = QUOTED.sub(" ", cell)
    toks = BACKTICKED.findall(text)
    toks.extend(re.split(r"[\s;,()]+", SECTION.sub(" ", BACKTICKED.sub(" ", text))))
    out = []
    for t in toks:
        t = re.sub(r"[§#:].*$", "", t.strip().strip("()[]").rstrip(".,;:"))
        if not t or re.search(r"\s", t) or any(ch in t for ch in "$<>=") or "://" in t:
            continue
        if "/" in t or PATH_SUFFIX.search(t) or (t.startswith(".") and len(t) > 1 and t[1].isalpha()):
            out.append(t)
    return out


def path_exists(p):
    m = BRACE.match(p)
    for cand in ([m.group(1) + x + m.group(3) for x in m.group(2).split(",")] if m else [p]):
        if any(ch in cand for ch in "*?["):
            if not glob.glob(cand):
                return False
        elif not os.path.exists(cand):
            return False
    return True


def cells(row):
    # Outer pipes are optional: drop at most one leading and one trailing
    # (unescaped) pipe, so an empty first cell written "||" stays a cell.
    row = row.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|") and not row.endswith("\\|"):
        row = row[:-1]
    return [c.strip() for c in CELL_SPLIT.split(row)]


def normalized(cell):
    # What is left to read: HTML and entities gone, lowercase, letters and
    # digits only ("T.B.D." -> "tbd", "<br>&nbsp;" -> "").
    return re.sub(r"[\W_]+", "", html.unescape(HTML.sub("", cell))).lower()


def source_name(name):
    return "above the first '## <source>' heading" if name is None else "under '## " + name + "'"


fails = []
tables = 0
rows = 0
cited = set()       # distinct destination paths checked for existence
source = None       # text of the nearest "## " heading above
by_source = {}      # heading text -> data rows under it
i = 0
while i < len(lines):
    line = lines[i].strip()
    if not (CELL_SPLIT.search(line) and i + 1 < len(lines) and SEPARATOR.match(lines[i + 1].strip())):
        heading = SOURCE_HEADING.match(line)
        if heading:
            source = heading.group(1).strip("` ")
        i += 1
        continue
    tables += 1
    header_line = i + 1
    header = cells(line)
    dest = next((k for k, h in enumerate(header) if DEST_HEADER.search(h)), None)
    if dest is None:
        fails.append(path + ":" + str(header_line) + ": table has no Destination column (header: " + " | ".join(header) + ")")
    i += 2
    while i < len(lines) and lines[i].strip() and not TABLE_END.match(lines[i].strip()):
        row = cells(lines[i])
        rows += 1
        by_source[source] = by_source.get(source, 0) + 1
        for k, cell in enumerate(row):
            if TBD.search(cell):
                fails.append(path + ":" + str(i + 1) + ": cell " + str(k + 1) + " reads TBD — " + cell)
        if dest is not None:
            shown = row[dest] if dest < len(row) else ""
            if dest >= len(row):
                fails.append(path + ":" + str(i + 1) + ": row has no destination (" + str(len(row)) + " cell(s), Destination is cell " + str(dest + 1) + "; a table runs until the next blank line) — " + lines[i].strip())
            elif not normalized(shown):
                fails.append(path + ":" + str(i + 1) + ": row has no destination — " + lines[i].strip())
            elif normalized(shown) in PLACEHOLDERS and not TBD.search(shown):
                fails.append(path + ":" + str(i + 1) + ": destination is a placeholder (" + shown + ") — " + lines[i].strip())
            elif not normalized(shown).startswith("dropped"):
                for tok in cited_paths(shown):
                    cited.add(tok)
                    if not path_exists(tok):
                        fails.append(path + ":" + str(i + 1) + ": destination cites a path that does not exist in the tree: "
                                     + tok + " — " + shown[:120])
        i += 1

if tables == 0:
    fails.append(path + ": no markdown table found (the inventory is a table with a Destination column)")

# Declared coverage: the parsed rows must equal the Totals line, in total and
# per "## <source>" heading.
TOTALS_SHAPE = "'**Totals.** <N> rows: `<source>` <n> · `<source>` <n> …'"
totals_at = [n for n, text in enumerate(lines, 1) if TOTALS.match(text)]
declared = {}
if len(totals_at) != 1:
    found = "none" if not totals_at else str(len(totals_at)) + " (lines " + ", ".join(str(n) for n in totals_at) + ")"
    fails.append(path + ": expected exactly one " + TOTALS_SHAPE + " line, found " + found + " — the parsed rows are compared with it")
else:
    where = path + ":" + str(totals_at[0])
    text = lines[totals_at[0] - 1]
    count = TOTALS_COUNT.match(text)
    if not count:
        fails.append(where + ": the Totals line does not read " + TOTALS_SHAPE)
    else:
        pos = count.end()
        while True:
            pair = TOTALS_SOURCE.match(text, pos)
            if not pair:
                break
            name = pair.group(1).strip()
            declared[name] = declared.get(name, 0) + int(pair.group(2))
            pos = pair.end()
            if not text.startswith("·", pos):
                break
            pos += 1
        if rows != int(count.group(1)):
            fails.append(where + ": " + str(rows) + " data rows parsed, the Totals line declares " + count.group(1) + " — a row was added or removed without the totals")
        if not declared:
            fails.append(where + ": the Totals line declares no per-source counts (" + TOTALS_SHAPE + ")")
        else:
            for name, want in declared.items():
                if by_source.get(name, 0) != want:
                    fails.append(where + ": " + str(by_source.get(name, 0)) + " data row(s) under '## " + name + "', the Totals line declares " + str(want))
            for name, got in by_source.items():
                if name not in declared:
                    fails.append(where + ": " + str(got) + " data row(s) " + source_name(name) + ", a source the Totals line does not declare")

for line in fails:
    print("FAIL: rule inventory: " + line)
if fails:
    sys.exit(1)
print("ok:   rule inventory: " + path + " — " + str(rows) + " rows in " + str(tables) + " table(s), matching the declared Totals for each of " + str(len(declared))
      + " sources; every row has a destination, no TBD cell, every cited destination path exists (" + str(len(cited)) + " distinct)")
PYEOF
    if [ "$INVENTORY_RC" -ne 0 ]; then
      FAILED_CHECKS=$((FAILED_CHECKS + 1))
    fi
  else
    echo "skip: rule-inventory completeness (no $INVENTORY_MD yet)"
  fi
fi

# --- 8. retired commands/ and agents/ (U23, U8) ------------------------------
# The 17 lead workflows are skills/at-*/ and the personas personas/*.md; nothing
# ships under commands/ or agents/. Both stay on FRAMEWORK_PROTECTED because the
# plugin host auto-loads them from the plugin root, so a lease re-creating
# commands/*.md (a live command) or agents/*.md (a live subagent with its own
# tools) must hit the gate.
if _selected retired; then
  for RETIRED in commands agents; do
    case "$RETIRED" in
      commands) RETIRED_KIND="command"; RETIRED_NOW="the lead workflows are skills/at-*/" ;;
      *)        RETIRED_KIND="subagent"; RETIRED_NOW="the personas are personas/*.md" ;;
    esac
    RETIRED_MD=$(ls "$RETIRED"/*.md 2>/dev/null | grep -c . || true)
    if [ "$RETIRED_MD" -ne 0 ]; then
      ls "$RETIRED"/*.md
      fail "$RETIRED/: $RETIRED_MD $RETIRED/*.md in the plugin checkout — 4.0 ships none ($RETIRED_NOW); the plugin host auto-loads $RETIRED/, so each stray file is a live $RETIRED_KIND (see the paths above)"
    elif ! grep -qE "^[[:space:]]*\"[^\"]*\",?[[:space:]]*.*\"$RETIRED/\"," scripts/lib/registry.sh && ! grep -qE "^[[:space:]]*\"$RETIRED/\"," scripts/lib/registry.sh; then
      fail "$RETIRED/: \"$RETIRED/\" is not on FRAMEWORK_PROTECTED in scripts/lib/registry.sh — the directory ships empty but the plugin host auto-loads it, so a lease that re-creates $RETIRED/*.md must hit the promotion gate (rc 42)"
    else
      ok "$RETIRED/: no $RETIRED/*.md in the plugin checkout (4.0 ships none); \"$RETIRED/\" stays on FRAMEWORK_PROTECTED (the plugin host auto-loads the directory)"
    fi
  done
fi

# --- 9. lead-workflow surfaces (the at- prefix and the enumerated names) ------
if _selected workflows; then
  LEADWF_RC=0
  VV_SYNC="scripts/lib/skills-sync.py" VV_PROBE="scripts/probe-capabilities.sh" VV_VSKILLS="scripts/validate-skills.sh" \
  VV_SELF="scripts/validate-versions.sh" VV_HOOK="hooks/handlers/session-start.sh" \
  VV_STATUS="skills/at-status/references/status-template.md" python3 - <<'PYEOF' || LEADWF_RC=$?
import os
import re
import sys

fails = []
oks = []


def read(p):
    try:
        with open(p, encoding="utf-8") as fh:
            return fh.read()
    except OSError as exc:
        fails.append(p + " unreadable: " + str(exc))
        return ""


# (a) the prefix literal, one per site; every site must be present and agree.
SITES = (
    ("VV_SYNC", re.compile(r'^LEAD_PREFIX = "([a-z0-9-]+)"', re.M), 'LEAD_PREFIX = "at-"'),
    ("VV_PROBE", re.compile(r"^\s*([a-z0-9-]+)\*\)\s+SHIPPED_LEAD_WORKFLOWS=", re.M), "the `at-*) SHIPPED_LEAD_WORKFLOWS=…` case arm"),
    ("VV_VSKILLS", re.compile(r'startswith\("([a-z0-9-]+)"\)\]', re.M), 'startswith("at-")'),
    ("VV_SELF", re.compile(r"ls skills/([a-z0-9-]+)\*/SKILL\.md", re.M), "ls skills/at-*/SKILL.md"),
)
found = []
for var, rx, what in SITES:
    p = os.environ[var]
    m = rx.search(read(p))
    if m:
        found.append((p, m.group(1)))
    else:
        fails.append(p + ": lead-workflow prefix site missing (" + what + ")")
prefixes = set(v for _, v in found)
if len(prefixes) > 1:
    fails.append("lead-workflow prefix differs across sites: " + ", ".join(p + "=" + repr(v) for p, v in found))
elif found and prefixes != {"at-"}:
    fails.append("lead-workflow prefix is " + repr(found[0][1]) + " at every site, expected 'at-' (skills/at-*/)")
elif len(found) == len(SITES):
    oks.append("lead-workflow prefix 'at-' spelled identically at " + str(len(SITES)) + " sites (skills-sync.py LEAD_PREFIX, probe case arm, validate-skills startswith, validate-versions count)")

# (b) the hand-listed names equal the skills/at-*/ directories.
shipped = sorted(d for d in os.listdir("skills") if d.startswith("at-") and os.path.isfile(os.path.join("skills", d, "SKILL.md")))
NAME = re.compile(r"(?<![\w-])at-[a-z0-9]+(?:-[a-z0-9]+)*(?![\w-])")


def compare(where, label, names):
    missing = sorted(set(shipped) - set(names))
    extra = sorted(set(names) - set(shipped))
    if missing or extra:
        fails.append(where + ": " + label + " differ from skills/at-*/" + (" — missing " + ", ".join(missing) if missing else "")
                     + (" — extra " + ", ".join(extra) if extra else ""))
    else:
        oks.append(where + " " + label + " enumerate exactly the " + str(len(shipped)) + " skills/at-*/ names")


hook_path = os.environ["VV_HOOK"]
banner = [ln for ln in read(hook_path).split("\n") if ln.lstrip().startswith("echo 'Lead workflows")]
if len(banner) != 1:
    fails.append(hook_path + ": expected exactly one \"echo 'Lead workflows …'\" banner line, found " + str(len(banner)))
else:
    compare(hook_path, "banner names", NAME.findall(banner[0].split("):", 1)[-1]))
status_path = os.environ["VV_STATUS"]
listed = re.findall(r"^- /(at-[a-z0-9]+(?:-[a-z0-9]+)*)\b", read(status_path), re.M)
if not listed:
    fails.append(status_path + ": no '- /at-<name>' lines (the Available commands block)")
else:
    compare(status_path, "Available commands", listed)

for line in oks:
    print("ok:   lead workflows: " + line)
for line in fails:
    print("FAIL: lead workflows: " + line)
sys.exit(1 if fails else 0)
PYEOF
  if [ "$LEADWF_RC" -ne 0 ]; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
  BARE_MENTIONS=$(
    grep -rnI "${SWEEP_EXCLUDE_DIRS[@]}" -e '\$at-' . 2>/dev/null \
      | grep -vE '^(\./)?(ops/|scripts/fixtures/validate-skills/c24-bare-mention/)' \
      | _shipped_surfaces \
      | sort -t: -k1,1 -k2,2n || true
  )
  if [ -n "$BARE_MENTIONS" ]; then
    printf '%s\n' "$BARE_MENTIONS"
    BARE_COUNT=$(printf '%s\n' "$BARE_MENTIONS" | grep -c . || true)
    fail "lead workflows: $BARE_COUNT bare \$at- mention(s) on shipped surfaces (listed above as file:line:text). Codex attaches a plugin skill only as \$agent-triforge:at-<name>; a bare \$at-<name> attaches nothing."
  else
    ok "lead workflows: no bare \$at- mention on shipped surfaces (Codex form: \$agent-triforge:at-<name>)"
  fi
fi

# --- 10. other-harness skill manifests (R22) ---------------------------------
if _selected manifests; then
  MANIFESTS_RC=0
  python3 - <<'PYEOF' || MANIFESTS_RC=$?
import json
import os
import re
import sys

DEVIN = "skills/.devin-plugin/plugin.json"
PI = "package.json"
fails = []

portable = sorted(d for d in os.listdir("skills")
                  if not d.casefold().startswith(("at-", ".", "_")) and os.path.isfile(os.path.join("skills", d, "SKILL.md")))


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        fails.append(path + ": unreadable (" + str(exc) + ")")
        return None
    if not isinstance(data, dict):
        fails.append(path + ": not a JSON object")
        return None
    return data


def only_keys(where, data, allowed):
    extra = sorted(set(data) - set(allowed))
    if extra:
        fails.append(where + ": carries " + ", ".join(extra) + " — only " + ", ".join(allowed) + " belong here")


def check_list(where, entries, prefix):
    """entries must name each portable skill directory exactly once, as <prefix><name>, and nothing else.

    Names compare exactly with the directory listing, never through the disk: on
    a case-insensitive volume skills/AT-BUILD/SKILL.md opens skills/at-build/."""
    if not isinstance(entries, list) or not all(isinstance(e, str) for e in entries):
        fails.append(where + ": must be a list of paths, one per portable skill directory")
        return
    names = []
    for e in entries:
        if re.search(r"[*?\[\]{}]", e) or e[:1] in ("!", "+", "-"):
            fails.append(where + ": '" + e + "' is a pattern — list each portable skill directory explicitly, so no glob can reach an at-* workflow")
            continue
        norm = e[2:] if e.startswith("./") else e
        norm = norm.rstrip("/")
        name = norm[len(prefix):] if norm.startswith(prefix) else ""
        if not name or "/" in name:
            fails.append(where + ": '" + e + "' is not " + prefix + "<skill> (one skill directory directly under skills/)")
        elif name.casefold().startswith("at-"):
            fails.append(where + ": '" + e + "' is a lead workflow — at-* workflows reach a lead only from its plugin install (KTD12)")
        elif name not in portable:
            alias = [p for p in portable if p.casefold() == name.casefold()]
            if alias:
                fails.append(where + ": '" + e + "' is not spelled as the skill directory " + alias[0] + " — list the exact name")
            else:
                fails.append(where + ": '" + e + "' is not a portable skill directory (one of: " + ", ".join(portable) + ")")
        else:
            names.append(name)
    dup = sorted(set(n for n in names if names.count(n) > 1))
    missing = sorted(set(portable) - set(names))
    if dup:
        fails.append(where + ": lists " + ", ".join(dup) + " more than once")
    if missing:
        fails.append(where + ": misses the portable skill(s) " + ", ".join(missing))


meta = ("name", "description", "author", "homepage", "repository", "license", "keywords")
claude = load(".claude-plugin/plugin.json") or {}

devin = load(DEVIN)
if devin is not None:
    only_keys(DEVIN, devin, meta + ("skills",))
    check_list(DEVIN + " skills", devin.get("skills"), "")
    if devin.get("name") != claude.get("name"):
        fails.append(DEVIN + ": name " + repr(devin.get("name")) + " differs from .claude-plugin/plugin.json's " + repr(claude.get("name")))

pi = load(PI)
if pi is not None:
    only_keys(PI, pi, meta + ("private", "pi"))
    pi_key = pi.get("pi")
    if not isinstance(pi_key, dict):
        fails.append(PI + ": no \"pi\" object (Pi's package manifest key)")
    else:
        only_keys(PI + " pi", pi_key, ("skills",))
        check_list(PI + " pi.skills", pi_key.get("skills"), "skills/")
    if pi.get("name") != claude.get("name"):
        fails.append(PI + ": name " + repr(pi.get("name")) + " differs from .claude-plugin/plugin.json's " + repr(claude.get("name")))

if os.path.lexists(".devin-plugin"):
    fails.append(".devin-plugin/ exists at the repo root — it outranks .claude-plugin/ for a Devin install of the root, which also loads this AGENTS.md as an always-on rule and runs hooks/; the Devin manifest is " + DEVIN)
ROOT_LOADED = ("agents.md", "agents.local.md", "agent.md", ".windsurfrules", "rules", "agents",
               "hooks.json", "hooks", ".mcp.json", "mcp.json")
stray = sorted(e for e in os.listdir("skills") if e.casefold() in ROOT_LOADED)
if stray:
    fails.append("skills/ (the Devin plugin root) carries " + ", ".join(stray) + " — Devin loads that name from a plugin root as rules, subagents, hooks or MCP servers")

for line in fails:
    print("FAIL: skill manifests: " + line)
if fails:
    sys.exit(1)
print("ok:   skill manifests: " + DEVIN + " (Devin) and " + PI + " pi.skills (Pi) list exactly the " + str(len(portable))
      + " portable skill directories, no at-* workflow, metadata and skills only; no root .devin-plugin/, nothing else Devin loads under skills/")
PYEOF
  if [ "$MANIFESTS_RC" -ne 0 ]; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
fi

# --- 11. halt threshold ------------------------------------------------------
if _selected halt; then
  HALT_RC=0
  VV_README_HISTORY_START="$README_HISTORY_START" python3 - <<'PYEOF' || HALT_RC=$?
import html
import os
import re
import sys

# A builder halts at MORE THAN 50 changed files (AGENTS.md §Delegation). Each
# INCLUSIVE alternative is a phrasing under which 50 itself halts; EXCLUSIVE
# lists the phrasings of the rule, counted for the ok line. Both need a
# comparator, so a bare count ("50 files") never matches.
FILES = r"(?:changed\s+|modified\s+)?files?(?:\s+changes?)?\b"
EDGE = r"(?<![\w.,])"           # 50 itself: not 150, 2.50 or 1,50
END = r"(?!\w|[.,]\d)"          # 50 itself: not 500 or 50.5; a full stop may follow
INCLUSIVE = re.compile(
    EDGE + r"50\s*\+\s*" + FILES                                                    # 50+ file changes
    + r"|" + EDGE + r"50\s+(?:or|and)\s+(?:more|above|over|greater|up)\s+" + FILES  # 50 or more files
    + r"|" + EDGE + r"50\s+" + FILES + r"\s+or\s+(?:more|above|over|greater)\b"     # 50 files or more
    + r"|\b(?:at\s+least|no\s+fewer\s+than|not\s+fewer\s+than)\s+50\s+" + FILES      # at least 50 files
    + r"|\bhalt\w*\s+(?:[^\s.;:!?]+\s+){0,12}?at\s+50\s+" + FILES                   # halt … at 50 files, in one clause
    + r"|(?:≥|>=|=>)\s*50\s+" + FILES                                                # >= 50 changed files
    + r"|\bfiles?(?:\s+changes?)?\s*(?:≥|>=|=>)\s*50" + END,                         # file changes >= 50
    re.I,
)
EXCLUSIVE = re.compile(
    r"\b(?:more\s+than|over|above)\s+50\s+" + FILES                                  # more than 50 changed files
    + r"|(?<![=>≥])>\s*50\s+" + FILES                                                # > 50 files
    + r"|\bfiles?(?:\s+changes?)?\s*>(?!=)\s*50" + END,                              # file changes > 50
    re.I,
)
# Markup that renders as nothing is dropped first; a removed tag keeps its
# newlines, so line numbers hold.
TAG = re.compile(r"<!--.*?(?:-->|$)|</?[A-Za-z][A-Za-z0-9-]*(?:\s[^>]*)?/?>", re.S)
EMPHASIS = re.compile(r"[*_`]")
SCOPE = "skills/, AGENTS.md, README.md, docs/index.html, docs/agent-triforge.md"

readme_history_start = int(os.environ["VV_README_HISTORY_START"] or "0")
paths = [p for p in ("AGENTS.md", "README.md", "docs/index.html", "docs/agent-triforge.md") if os.path.isfile(p)]
for top, dirs, names in os.walk("skills"):
    dirs.sort()
    paths.extend(os.path.join(top, n) for n in sorted(names))

fails = []
stated = 0
for path in paths:
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError):
        continue    # not text: states no threshold (grep -I skips it too)
    if path == "README.md" and readme_history_start:
        # the release ledger names what each past release did
        text = "\n".join(text.split("\n")[:readme_history_start - 1])
    text = TAG.sub(lambda m: "\n" * m.group(0).count("\n"), text)
    text = EMPHASIS.sub("", html.unescape(text))
    for m in INCLUSIVE.finditer(text):
        fails.append(path + ":" + str(text.count("\n", 0, m.start()) + 1) + ": \"" + " ".join(m.group(0).split())
                     + "\" halts at 50 itself — the threshold is more than 50 changed files (AGENTS.md §Delegation)")
    stated += len(EXCLUSIVE.findall(text))

for line in fails:
    print("FAIL: halt threshold: " + line)
if fails:
    sys.exit(1)
print("ok:   halt threshold: " + str(stated) + " statement(s) of more than 50 changed files and none that halts at 50 itself (50+, 50 or more, at least 50, >= 50) in " + SCOPE)
PYEOF
  if [ "$HALT_RC" -ne 0 ]; then
    FAILED_CHECKS=$((FAILED_CHECKS + 1))
  fi
fi

# --- summary -----------------------------------------------------------------
if [ "$FAILED_CHECKS" -eq 0 ] && [ -n "$ONLY" ]; then
  echo "validate-versions: PASS (--only $ONLY)"
  exit 0
elif [ "$FAILED_CHECKS" -eq 0 ]; then
  echo "validate-versions: PASS — plugin $PLUGIN_V, ladder: one definition ($LADDER_SOURCE), $PERSONA_COUNT personas / $SKILL_COUNT skills ($PORTABLE_COUNT portable, $WORKFLOW_COUNT lead workflows)"
  exit 0
fi
echo "validate-versions: FAIL — $FAILED_CHECKS check(s) failed (see FAIL: lines above)"
exit 1
