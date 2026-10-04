# Optional reviewer lanes (roster-driven)

The core-trio swarm (Antigravity + Codex) is the shipped default and always runs. In addition, dispatch a reviewer lane for every **enrolled optional member** (`[members.<cli>] enabled = true` in `ops/roster.toml`) AND for any optional CLI named as the **primary `reviewer`** via `[roles.reviewer] cli = "<optional>"`. Each writes `ops/REVIEW_<CLI>.md`; `findings-synthesizer` globs `ops/REVIEW_*.md`, so these lanes are merged automatically when present. Members that are absent or declined are skipped silently (AE1). The locator path is relative to this skill's directory.

```bash
set -euo pipefail
ROOT=$(bash scripts/locate-triforge.sh) || exit $?; source "$ROOT/scripts/invoke-external.sh"

# Read the reviewer-role primary so a [roles.reviewer] cli="<optional>" override
# runs that optional CLI as the primary reviewer even if it is not in the
# enrolled-members list (roles do not require enrollment; members do).
REVIEWER_PRIMARY=""
if RESOLVED_REVIEWER=$(resolve_role reviewer 2>/dev/null); then
  REVIEWER_PRIMARY=$(printf '%s\n' "$RESOLVED_REVIEWER" | cut -f1)
fi

REVIEW_PROMPT="Review scope: tasks marked [R] in ops/TASKS.md. Report findings as [SEVERITY] file:line — issue → fix. Write them to ops/REVIEW_<YOUR_CLI>.md if you can; otherwise return them as your response."

for OCLI in opencode kimi cursor; do
  ENABLED=$(_roster_member_field "$OCLI" enabled 2>/dev/null || true)
  # Run when enrolled-enabled OR named as the reviewer-role primary; else skip.
  if [ "$ENABLED" != "true" ] && [ "$OCLI" != "$REVIEWER_PRIMARY" ]; then
    continue
  fi
  OMODEL=$(_roster_member_field "$OCLI" model 2>/dev/null || true)   # empty -> helper's shipped default
  UP=$(printf '%s' "$OCLI" | tr '[:lower:]' '[:upper:]')
  OOUT="${TMPDIR:-/tmp}/${OCLI}_review_$$_$(date +%s).txt"
  ORC=0
  case "$OCLI" in
    opencode) OPENCODE_MODEL="${OMODEL:-}" invoke_opencode "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
    kimi)     KIMI_MODEL="${OMODEL:-}"     invoke_kimi     "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
    cursor)   CURSOR_MODEL="${OMODEL:-}"   invoke_cursor   "reviewer" "$REVIEW_PROMPT" "$OOUT" 600 || ORC=$? ;;
  esac
  [ "$ORC" -ne 0 ] && echo "review: ${OCLI} reviewer lane exited $ORC (see $OOUT) — optional lane, continuing" >&2
  # Typed completion signal (KTD11): the optional-tier reviewer briefs promise
  # that the lead parses their final `Status:` line and treats a run without
  # it as "report missing", never as review-ready — so promote captured output
  # into ops/REVIEW_<CLI>.md ONLY on DONE / DONE_WITH_CONCERNS. BLOCKED,
  # NEEDS_CONTEXT, and a missing report leave no REVIEW file (an absent lane is
  # visible to findings-synthesizer; a truncated review promoted as complete is not).
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
done
```
