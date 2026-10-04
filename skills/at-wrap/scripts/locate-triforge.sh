#!/bin/sh
# locate-triforge.sh — print the Agent Triforge plugin root (KTD6 / R16 / R42).
#
# SOURCE: scripts/skill-locator/locate-triforge.sh in the Triforge plugin. Every
# at- skill carries a byte-identical copy at <skill>/scripts/locate-triforge.sh
# (scripts/validate-skills.sh checks each copy against this source). Edit the
# source, never a copy. Execute it; do not source it (it exits).
#
# Usage, from a skill script:
#   ROOT=$("$(dirname "$0")/locate-triforge.sh") || exit $?
#   . "$ROOT/scripts/invoke-external.sh"
# Usage, from skill text (SKILL.md or a reference) — anchored to the skill's
# own directory, so a project's scripts/locate-triforge.sh is never the one run
# (validate-skills.sh KTD6 rejects a cwd-relative call):
#   ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"
# stdout: the plugin root (physical path), one line, rc 0.
# stderr: one line saying what was tried and naming the setup skill;
#   rc 1  no root found (no candidate passed the test, no pointer file)
#   rc 3  a pointer file exists but was refused (tracked, inside the project,
#         relative, not a directory, not a Triforge root, a symlinked .agents,
#         or git could not say whether it is tracked)
#
# Resolution order (KTD6). <project> is the git toplevel of the working
# directory (else the working directory itself); in a linked worktree the main
# checkout counts as the project too.
#   1. CLAUDE_PLUGIN_ROOT, when it passes the Triforge-root test — a Claude
#      Code lead exports it for plugin skills; any other lead does not.
#   2. This copy's own location: <skill>/scripts/locate-triforge.sh, so the
#      directory two levels above <skill> — the plugin root when the skill lives
#      at <plugin>/skills/<skill>/. The step is skipped when that directory lies
#      strictly inside <project> or is a CLI configuration directory (.agents,
#      .claude, .codex, ...): a copy under <project>/.agents/skills/ would
#      otherwise let the project plant a passing root at <project>/.agents, so
#      a project-tier copy resolves only through the pointer (step 3). The
#      Triforge checkout itself (that directory == <project>) still resolves.
#      (The reason KTD6 chose the root test over a bare ../.. fallback.)
#   3. The plugin-root pointer <project>/.agents/triforge-plugin-root.local;
#      in a linked worktree the main checkout's pointer is tried after the
#      worktree's own. The file holds one absolute path (blank and # lines
#      ignored). It is REFUSED — rc 3, no fallback — when the project's git
#      tracks it under any letter case (it must stay untracked: a user project
#      gitignores `.agents/*.local`; this repository ignores `/.agents/` whole),
#      when git cannot say whether it is tracked, when <project>/.agents is a
#      symlink, when its target resolves inside the project's toplevel, or when
#      the target fails the Triforge-root test. Writer: `triforge_bootstrap`,
#      run by the setup skill, is the only writer of this file (U14); nothing
#      here writes it.
#   4. Otherwise fail closed, naming the setup skill.
#
# Triforge-root test: <dir>/.claude-plugin/plugin.json names "agent-triforge"
# AND <dir>/scripts/invoke-external.sh exists — the same test the loader's
# _triforge_is_plugin_root applies.
#
# POSIX sh on purpose: it runs the same under /bin/sh, macOS /bin/bash 3.2 and
# zsh (`sh file`, `bash file`, `zsh file`, or by its shebang) — no arrays, no
# [[ ]], no local, no bash-only expansions.
set -eu

POINTER_NAME=".agents/triforge-plugin-root.local"
SETUP_HINT='run the Triforge setup skill at-setup (`/at-setup` under Claude Code, `$at-setup` in a Codex prompt)'

is_triforge_root() { # is_triforge_root <dir>
  if [ -n "${1:-}" ] && [ -f "$1/scripts/invoke-external.sh" ] && [ -f "$1/.claude-plugin/plugin.json" ] \
     && grep -Eq '"name"[[:space:]]*:[[:space:]]*"agent-triforge"' "$1/.claude-plugin/plugin.json" 2>/dev/null; then
    return 0
  fi
  return 1
}
phys() { # phys <dir> — physical (symlink-free) path of an existing directory
  # The external pwd, not the builtin: sh and bash keep the letter case the
  # caller typed, so on a case-insensitive filesystem a path spelled
  # differently would miss the string comparisons below; getcwd returns the
  # on-disk spelling, the same one git prints for the toplevel.
  (cd "$1" 2>/dev/null && env pwd -P)
}
refuse() { # refuse <pointer-file> <reason>
  echo "locate-triforge: ERROR plugin-root pointer $1 refused: $2 — remove or fix it, then $SETUP_HINT" >&2
  exit 3
}

# 1. CLAUDE_PLUGIN_ROOT
CPR_NOTE="unset"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  if is_triforge_root "${CLAUDE_PLUGIN_ROOT:-}"; then
    phys "${CLAUDE_PLUGIN_ROOT:-}"
    exit 0
  fi
  CPR_NOTE="'${CLAUDE_PLUGIN_ROOT:-}' is not a Triforge root"
fi

# The working directory's project: its git toplevel (else the directory itself)
# and, in a linked worktree, the main checkout. Steps 2 and 3 both need them.
TOP=""
if command -v git >/dev/null 2>&1; then
  TOP=$(git rev-parse --show-toplevel 2>/dev/null) || TOP=""
fi
[ -n "$TOP" ] || TOP=$(pwd -P)
TOP=$(phys "$TOP") || TOP=$(pwd -P)
MAIN=""
if [ -n "$TOP" ] && command -v git >/dev/null 2>&1; then
  COMMON=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || COMMON=""
  if [ -n "$COMMON" ] && [ "$(basename "$COMMON")" = ".git" ]; then
    MAIN=$(phys "$(dirname "$COMMON")") || MAIN=""
    [ "$MAIN" = "$TOP" ] && MAIN=""
  fi
fi
inside_project() { # inside_project <dir> — strictly below TOP or MAIN (never equal)
  case "$1/" in
    "$TOP"/?*) return 0 ;;
  esac
  if [ -n "$MAIN" ]; then
    case "$1/" in
      "$MAIN"/?*) return 0 ;;
    esac
  fi
  return 1
}

# 2. this copy's own location: <plugin>/skills/<skill>/scripts/locate-triforge.sh
#    — skipped for a copy inside the project and for a copy whose would-be root
#    is a CLI configuration directory, where project-tier skill copies live
#    (<anything>/.agents, .claude, .codex, .cursor, .opencode, .kimi-code,
#    .gemini, .antigravity): such a copy must not let the project plant its own
#    root, whatever the working directory is. Other dot-named directories (a
#    plugin cloned into ~/.triforge, say) still resolve.
SELF_DIR=$(phys "$(dirname "$0")") || SELF_DIR=""
if [ -n "$SELF_DIR" ]; then
  OWN_ROOT=$(dirname "$(dirname "$(dirname "$SELF_DIR")")")
  # compared in lower case: a case-insensitive filesystem serves .Agents as .agents
  case "$(printf '%s' "${OWN_ROOT##*/}" | tr '[:upper:]' '[:lower:]')" in
    .agents|.claude|.codex|.cursor|.opencode|.kimi-code|.gemini|.antigravity) ;;
    *)
      if ! inside_project "$OWN_ROOT" && is_triforge_root "$OWN_ROOT"; then
        phys "$OWN_ROOT"
        exit 0
      fi
      ;;
  esac
fi

# 3. the pointer file of the project (then, in a linked worktree, of the main
#    checkout)
TRIED=""
for PROJECT in "$TOP" "$MAIN"; do
  [ -n "$PROJECT" ] || continue
  PFILE="$PROJECT/$POINTER_NAME"
  TRIED="${TRIED}${TRIED:+ or }${PFILE}"
  [ -e "$PFILE" ] || [ -L "$PFILE" ] || continue
  PDIR="$PROJECT/.agents"
  if [ -L "$PDIR" ] || [ "$(phys "$PDIR" || echo "$PDIR")" != "$PDIR" ]; then
    refuse "$PFILE" "$PDIR is a symlink (the pointer must live in a real .agents directory of the project)"
  fi
  [ -f "$PFILE" ] && ! [ -L "$PFILE" ] || refuse "$PFILE" "not a regular file"
  if command -v git >/dev/null 2>&1 && git -C "$PROJECT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # tracked under any letter case (a case-insensitive filesystem serves the
    # pointer under a name git tracks differently); a git error is a refusal
    if git -C "$PROJECT" ls-files --error-unmatch -- ":(icase)$POINTER_NAME" >/dev/null 2>&1; then
      refuse "$PFILE" "the file is tracked by the project's git (it must stay untracked: gitignore .agents/*.local)"
    else
      LS_RC=$?
      [ "$LS_RC" -eq 1 ] || refuse "$PFILE" "git could not say whether the file is tracked (git ls-files rc $LS_RC)"
    fi
  fi
  TARGET=$(grep -v '^[[:space:]]*#' "$PFILE" | grep -v '^[[:space:]]*$' | head -1 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//') || TARGET=""
  [ -n "$TARGET" ] || refuse "$PFILE" "the file names no path"
  case "$TARGET" in
    /*) ;;
    *) refuse "$PFILE" "'$TARGET' is not an absolute path" ;;
  esac
  TREAL=$(phys "$TARGET") || refuse "$PFILE" "'$TARGET' is not a directory"
  case "$TREAL/" in
    "$TOP"/*) refuse "$PFILE" "'$TARGET' resolves inside the project ($TOP); the plugin root must live outside the project tree" ;;
  esac
  if [ -n "$MAIN" ]; then
    case "$TREAL/" in
      "$MAIN"/*) refuse "$PFILE" "'$TARGET' resolves inside the project's main checkout ($MAIN); the plugin root must live outside the project tree" ;;
    esac
  fi
  is_triforge_root "$TREAL" || refuse "$PFILE" "'$TARGET' is not a Triforge plugin root (.claude-plugin/plugin.json named agent-triforge plus scripts/invoke-external.sh)"
  printf '%s\n' "$TREAL"
  exit 0
done

# 4. fail closed
echo "locate-triforge: ERROR no Triforge plugin root — CLAUDE_PLUGIN_ROOT $CPR_NOTE; this copy (${SELF_DIR:-$(dirname "$0")}) is not inside a Triforge plugin tree; no pointer at ${TRIED:-$POINTER_NAME} — $SETUP_HINT, which writes the pointer." >&2
exit 1
