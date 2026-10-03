#!/usr/bin/env bash
# scripts/lib/registry.sh — data the other lanes read from one place (KTD7). In 3.3.3: the two protected-path lists and their match rule (KTD8), and the model ladder (KTD22)
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, after scripts/lib/common.sh and before scripts/lib/lease.sh.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/registry.sh: not standalone — source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# ---------------------------------------------------------------------------
# Protected paths (KTD8, R30)
# ---------------------------------------------------------------------------
#
# A diff touching a protected path forces the promotion gate on and needs the
# lead or the user as cross-reviewer, never an external-CLI-only review.
# Two lists:
#   FRAMEWORK_PROTECTED  Triforge's own control plane. Applies only in the
#                        Triforge checkout (.claude-plugin/plugin.json named
#                        agent-triforge), so a user project's own scripts/,
#                        skills/ or hooks/ are not force-gated.
#   PROJECT_PROTECTED    what governs the pool in ANY project: the roster, each
#                        CLI's permission/config tree, and every instruction
#                        file at any depth.
# Entries ending in "/" match everything under that directory AND the bare
# name itself (".claude/" also hits a changed path ".claude"), so a symlink or
# file committed in the directory's place cannot redirect a CLI config tree
# past the gate; ".clauder" or "claudeish" still do not match. Any other entry
# matches that exact path (or a directory of that name). *_ANY_DEPTH entries match a
# basename anywhere in the tree. Matching is case-folded, because the default
# macOS filesystem treats Hooks/handlers/x.sh and hooks/handlers/x.sh as one
# file. Callers feed BOTH sides of a rename (git diff --no-renames) and read
# any error as a hit — the scan fails closed (lease_promote: rc 42).
#
# _PROTECTED_PY is spliced into the python that classifies paths (the
# _CURSOR_ID_PY pattern in cursor.sh); SELF-10 checks the protected-path list
# in the root AGENTS.md against it. A new control-plane file joins the right
# list in the commit that creates it.
_PROTECTED_PY='
FRAMEWORK_PROTECTED = (
    # enforcement code: the helper, its lanes, the no-push hook, the outer loop
    "scripts/lib/", "scripts/lease-git-hooks/", "scripts/invoke-external.sh", "scripts/coordinate.sh",
    # the probe harness and the release gates
    "scripts/probe-capabilities.sh", "scripts/probe-self-tests.sh",
    "scripts/validate-skills.sh", "scripts/validate-versions.sh", "scripts/release-notes.sh",
    # lifecycle hooks, the lead-facing workflows and the persona home
    "hooks/", "skills/", "commands/", "personas/",
    # shipped agent configs, one directory per CLI
    "agents/", "antigravity-agents/", "codex-agents/", "opencode-agents/", "kimi-agents/", "cursor-agents/",
    # manifests, plugin settings, and the templates copied into user projects
    ".claude-plugin/", "settings.json", "templates/",
    # CI plumbing (.gitmodules is on PROJECT_PROTECTED: every project)
    ".github/",
)
FRAMEWORK_PROTECTED_ANY_DEPTH = (".gitattributes",)
PROJECT_PROTECTED = (
    "ops/roster.toml",
    # each CLI project-tier config / permission tree (agy reads .agents/hooks.json
    # and .agents/agents/, so .agents/ is protected whole, skills included)
    ".claude/", ".codex/", ".agents/", ".antigravity/", ".gemini/", ".opencode/", ".kimi-code/", ".cursor/",
    # project-root config files outside those trees: OpenCode reads its permission
    # config from opencode.json / opencode.jsonc, and Cursor still reads the
    # legacy root instruction file .cursorrules
    "opencode.json", "opencode.jsonc", ".cursorrules",
    # .gitmodules names the URL `git submodule update` pulls into any path a
    # nested repo was recorded at (a builder can record one at .claude/)
    ".gitmodules",
)
PROJECT_PROTECTED_ANY_DEPTH = ("agents.md", "agents.override.md", "claude.md", "claude.local.md", ".mcp.json")

def _protected_hit(folded, base, entries, any_depth):
    if base in any_depth:
        return True
    for e in entries:
        e = e.casefold()
        if e.endswith("/"):
            if folded.startswith(e) or folded == e[:-1]:
                return True
        elif folded == e or folded.startswith(e + "/"):
            return True
    return False

def protected_match(path, framework):
    """The list a changed path hits ("project" / "framework"), or None."""
    p = path
    while p.startswith("./"):
        p = p[2:]
    p = p.lstrip("/")
    folded = p.casefold()
    base = folded.rsplit("/", 1)[-1]
    if _protected_hit(folded, base, PROJECT_PROTECTED, PROJECT_PROTECTED_ANY_DEPTH):
        return "project"
    if framework and _protected_hit(folded, base, FRAMEWORK_PROTECTED, FRAMEWORK_PROTECTED_ANY_DEPTH):
        return "framework"
    return None
'

# _protected_classify <framework:0|1> < NUL-separated paths — print
# "<list><TAB><path>" for every protected path on stdin (git diff -z output).
# Nonzero, with the python error on stderr, when the classifier itself fails:
# callers treat that as a hit (fail closed), never as "nothing protected".
_protected_classify() {
  PC_FRAMEWORK="${1:-0}" python3 -c "
import os, sys
${_PROTECTED_PY}
framework = os.environ['PC_FRAMEWORK'] == '1'
raw = sys.stdin.buffer.read()
for item in raw.split(b'\0'):
    if not item:
        continue
    path = item.decode('utf-8', 'surrogateescape')
    hit = protected_match(path, framework)
    if hit:
        sys.stdout.write(hit + '\t' + path.encode('utf-8', 'surrogateescape').decode('utf-8', 'replace') + '\n')
"
}

# ---------------------------------------------------------------------------
# Model ladder (KTD22, R26)
# ---------------------------------------------------------------------------
#
# The one definition of the downgrade ladder for narrow runtime tasks. The
# instruction file (the root AGENTS.md), agents/team-lead.md and
# skills/wave-orchestration/SKILL.md point here with a one-line summary
# instead of restating the rungs; scripts/validate-versions.sh (check 2) fails
# when any other shipped file carries the phrase, a colon, and the rung list
# again. The `opus` rung names Opus 5.5 with its Claude Code floor (D-037).
# Callers print the text with triforge_ladder.
TRIFORGE_MODEL_LADDER='Downgrade ladder for narrow runtime tasks: `fable`+`max` (lead + never-downgrade tier when available; otherwise latest `opus` at `max` — the model steps down, the effort does not) → `opus` (Opus 5.5, Claude Code ≥ 2.1.280) + `xhigh` → `opus`+`high` → `sonnet` (Sonnet 5) + `high`. Never downgrade security-sentinel, plan-checker, or findings-synthesizer.'

# triforge_ladder — print the ladder text (one line, newline-terminated).
triforge_ladder() {
  printf '%s\n' "$TRIFORGE_MODEL_LADDER"
}
