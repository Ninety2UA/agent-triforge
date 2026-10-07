# Optional reviewer lanes (roster-driven)

The core-trio swarm (Antigravity + Codex) is the shipped default and always runs. In addition, dispatch a reviewer lane for every **enrolled optional member** (`[members.<cli>] enabled = true` in `ops/roster.toml`) AND for any optional CLI named as the **primary `reviewer`** via `[roles.reviewer] cli = "<optional>"`. Each writes `ops/REVIEW_<CLI>.md`; `findings-synthesizer` globs `ops/REVIEW_*.md`, so these lanes are merged automatically when present. Members that are absent or declined are skipped silently (AE1). The lanes run in parallel, as the core lanes do. Each runs in a background subshell with its own output file and REVIEW file, and the block waits for each one. A lane's output becomes its REVIEW file only when the helper exited 0 and the report's `Status:` line says DONE or DONE_WITH_CONCERNS; a lane that exits nonzero is reported as failed with its exit code and reason, and the other lanes still finish. Every lane's prompt carries the review package: the `[R]` rows of the lead's `ops/TASKS.md` and the diff from where HEAD left the default branch (or from `REVIEW_BASE`, when set) to the working tree, because the read-class reviewers cannot run git and Grok reviews from a copy of HEAD. If the roster does not load, the block stops before any lane starts, as the core dispatch does. `$SKILL_DIR` is the directory this skill was loaded from (SKILL.md explains it).

```bash
set -euo pipefail
ROOT=$(bash "$SKILL_DIR/scripts/locate-triforge.sh") || exit $?; source "$ROOT/scripts/invoke-external.sh"

# Read the reviewer-role primary so a [roles.reviewer] cli="<optional>" override
# runs that optional CLI as the primary reviewer even if it is not in the
# enrolled-members list (roles do not require enrollment; members do). A
# resolve_role failure stops here (rc 5: the roster breaks a load rule, such as
# devin enabled without a recorded consent; its error names the fix), as the
# core dispatch stops on dispatch_role's.
RR_RC=0
RESOLVED_REVIEWER=$(resolve_role reviewer) || RR_RC=$?
if [ "$RR_RC" -ne 0 ]; then
  echo "review: resolve_role reviewer failed rc=${RR_RC} — fix ops/roster.toml (see the error above); no optional lane started" >&2; exit 1
fi
REVIEWER_PRIMARY=$(printf '%s\n' "$RESOLVED_REVIEWER" | cut -f1)

# The review package rides in the prompt (trust rules: the diff and the task
# rows). The read-class lanes (Devin, a Grok reviewer) have no shell to run
# git, and Grok reviews from a scratch copy of HEAD, where ops/TASKS.md is the
# committed one. The base is REVIEW_BASE when the lead sets it (a commit), else
# where HEAD left the default branch, else HEAD; the diff runs from the base to
# the working tree, so the branch's commits and uncommitted edits both show
# (untracked files do not). On the default branch with nothing uncommitted it
# is the last commit. Lead-side hardened git (_lgr) with no external diff or
# textconv driver; capped at 200000 bytes.
RBASE=${REVIEW_BASE:-}; RRANGE="none: not a git checkout"; REVIEW_DIFF=""
if _lease_ctx 2>/dev/null; then
  RRANGE="${RBASE:-HEAD} to the working tree"
  if [ -z "$RBASE" ]; then
    RDEF=$(_lease_default_branch 2>/dev/null || true)
    if [ -n "$RDEF" ]; then RBASE=$(_lgr merge-base "refs/heads/${RDEF}" HEAD 2>/dev/null || true); fi
    if [ -n "$RBASE" ]; then RRANGE="${RBASE:0:12} (where HEAD left ${RDEF}) to the working tree"; fi
  fi
  RBASE=${RBASE:-HEAD}
  REVIEW_DIFF=$(_lgr diff --no-ext-diff --no-textconv --no-color "$RBASE" -- 2>/dev/null || true)
  if [ -z "$REVIEW_DIFF" ] && _lgr rev-parse --verify --quiet "HEAD~1^{commit}" >/dev/null 2>&1; then
    RRANGE="HEAD~1 HEAD (the last commit)"
    REVIEW_DIFF=$(_lgr diff --no-ext-diff --no-textconv --no-color HEAD~1 HEAD -- 2>/dev/null || true)
  fi
fi
RBYTES=$(printf '%s' "$REVIEW_DIFF" | wc -c | tr -d ' ')
RNOTE=""
if [ "$RBYTES" -gt 200000 ]; then
  REVIEW_DIFF=$(printf '%s' "$REVIEW_DIFF" | head -c 200000 || true)
  RNOTE=" — cut at 200000 of ${RBYTES} bytes; read the remaining files at their paths"
fi
RROWS=$(grep -F '[R]' ops/TASKS.md 2>/dev/null | head -100 || true)

REVIEW_PROMPT="Review scope: tasks marked [R] in ops/TASKS.md. Report findings as [SEVERITY] file:line — issue → fix. Write them to ops/REVIEW_<YOUR_CLI>.md if you can; otherwise return them as your response.

## Task rows under review (the [R] rows of the lead's ops/TASKS.md)
${RROWS:-(none found)}

## The diff under review (git diff from ${RRANGE}${RNOTE})
----- BEGIN DIFF -----
${REVIEW_DIFF:-(empty: no change against the base)}
----- END DIFF -----"

# One background subshell per lane; the PIDs in a space-separated string, not
# an array (an empty array breaks bash 3.2 under set -u).
OPIDS=""
for OCLI in $(cli_list optional); do
  ENABLED=$(_roster_member_field "$OCLI" enabled 2>/dev/null || true)
  # Run when enrolled-enabled OR named as the reviewer-role primary; else skip.
  if [ "$ENABLED" != "true" ] && [ "$OCLI" != "$REVIEWER_PRIMARY" ]; then
    continue
  fi
  (
    OMODEL=$(_roster_member_field "$OCLI" model 2>/dev/null || true)   # empty -> helper's shipped default
    UP=$(printf '%s' "$OCLI" | tr '[:lower:]' '[:upper:]')
    OOUT="${TMPDIR:-/tmp}/${OCLI}_review_$$_$(date +%s).txt"
    ORC=0
    case "$OCLI" in
      opencode) OPENCODE_MODEL="${OMODEL:-}" invoke_opencode "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
      kimi)     KIMI_MODEL="${OMODEL:-}"     invoke_kimi     "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
      cursor)   CURSOR_MODEL="${OMODEL:-}"   invoke_cursor   "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
      devin)    DEVIN_MODEL="${OMODEL:-}" DEVIN_ROLE=reviewer invoke_devin "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;   # read-only class; refuses without a recorded consent; rc 80 = no Status line
      grok)     GROK_MODEL="${OMODEL:-}" GROK_ROLE=reviewer invoke_grok "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
      *)        echo "review: no reviewer arm here for ${OCLI} — optional lane skipped" >&2; exit 0 ;;
    esac
    # A failed run is never a review, whatever its output says: invoke_grok
    # keeps the prose of a run cut off at max_tokens, which can already hold a
    # Status: DONE line. The lane is reported failed with its rc and reason,
    # and writes no REVIEW file; the other lanes run on.
    if [ "$ORC" -ne 0 ]; then
      echo "review: ${OCLI} reviewer lane FAILED rc=${ORC} (${INVOKE_FAILURE_CLASS:-unknown}${_INVOKE_FAILURE_REASON:+, ${_INVOKE_FAILURE_REASON}}) — nothing promoted to ops/REVIEW_${UP}.md; output at ${OOUT}" >&2
      exit "$ORC"
    fi
    # Typed completion signal (KTD11): the optional-tier reviewer briefs promise
    # that the lead parses their final `Status:` line and treats a run without
    # it as "report missing", never as review-ready — so promote captured output
    # of a run that exited 0 into ops/REVIEW_<CLI>.md ONLY on DONE /
    # DONE_WITH_CONCERNS. BLOCKED, NEEDS_CONTEXT, and a missing report leave no
    # REVIEW file (an absent lane is visible to findings-synthesizer; a
    # truncated review promoted as complete is not).
    OSTATUS=$(_lease_parse_status "$OOUT" 2>/dev/null || echo MISSING)
    case "$OSTATUS" in
      DONE|DONE_WITH_CONCERNS)
        if [ ! -f "ops/REVIEW_${UP}.md" ] && [ -s "$OOUT" ]; then
          { echo "<!-- captured from invoke_${OCLI} reviewer output; headless permission auto-deny; report_status=${OSTATUS} -->"; _scrub < "$OOUT"; } > "ops/REVIEW_${UP}.md"
        fi ;;
      BLOCKED|NEEDS_CONTEXT)
        echo "review: ${OCLI} reviewer reported Status: ${OSTATUS} — not promoted to ops/REVIEW_${UP}.md; read ${OOUT}, supply the missing context, and re-run the lane" >&2 ;;
      *)
        echo "review: ${OCLI} reviewer output has no final 'Status:' line — report missing, NOT review-ready; nothing promoted (captured at ${OOUT}; re-run the lane with the contract restated)" >&2 ;;
    esac
  ) &
  OPIDS="$OPIDS $!"
done
# One wait per lane. The list goes through printf so zsh, which does not split
# an unquoted $OPIDS, splits it too.
for P in $(printf '%s\n' "$OPIDS"); do wait "$P" || true; done
```
