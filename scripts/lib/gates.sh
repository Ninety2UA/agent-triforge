#!/usr/bin/env bash
# scripts/lib/gates.sh: no-model gates, at-review's Coverage line (R24, KTD5), the
# plan and verify verdicts (R28, KTD11) and the planning learnings gate (R29, KTD10)
#
# Not standalone: sourced by scripts/invoke-external.sh (the loader), inside the
# same shell, ahead of scripts/lib/lease.sh. Runs under bash 3.2 and zsh: the
# skill blocks that call it run under both, and it starts no python.
if [ -z "${_TRIFORGE_SCRIPTS_DIR:-}" ]; then
  echo "scripts/lib/gates.sh: not standalone; source scripts/invoke-external.sh" >&2
  return 2 2>/dev/null || exit 2
fi

# What every at-review prompt and brief carries. A reviewer's agent file says
# the same, but the prompt has to say it too: invoke_codex and
# invoke_antigravity retry on the raw prompt with no agent instructions, and a
# deployed agent file is copy-if-absent (_bootstrap_copy), so a project set up
# before this rule keeps its old format section.
REVIEW_COVERAGE_RULE='End your report with a Coverage line as its last non-empty line, plain text outside any code fence, after any `Status:` report and with nothing after it: `Coverage: complete`, `Coverage: partial: <reason>` or `Coverage: none: <reason>`. Complete means every changed file and every `Accept:` was judged from the package and readable code; a command-shaped `Accept:` you cannot run is judged by reading and listed `not run`, without lowering coverage. Partial and none are for unread files or an unreadable package. A report without this line is a gap, never a review.'

# What every at-review prompt and brief says about judging (R22, R23, R26), for
# the same two reasons. A command-shaped `Accept:` a lane cannot run has its
# clause once, in the Coverage rule that follows this one in every prompt.
REVIEW_JUDGE_RULE='Judge every `Accept:`; an unmet one is at least P2. Read the callers, the contracts and the surrounding code before you report or clear a finding. Never quote a secret value: name the file, line and shape.'

# The fold dispatch.md appends after a lane's text, and the one thing that
# marks a lane as a Codex lane with a structured verdict.
_REVIEW_VERDICT_MARK='<!-- structured verdict (codex --output-schema, review-verdict.schema.json) -->'

# The code fence reader review_coverage and persona_verdict share, in awk.
# fenced(s) feeds it one line with its line ending gone and answers 1 for an
# opening or closing fence or a line between them. Fences as CommonMark has
# them: up to three spaces, three or more backticks or tildes, and a backtick
# fence's info string holds no backtick; only the opening character, at least
# as many of it and nothing else closes one. fc is non-empty while one is open.
_GATES_FENCE_AWK='
    function fenced(s,   t, c, n) {
      t = s; sub(/^ ? ? ?/, "", t); c = substr(t, 1, 1); n = 0
      if (c == "`" || c == "~") while (substr(t, n + 1, 1) == c) n++
      if (fc != "") {
        if (c == fc && n >= fn && substr(t, n + 1) !~ /[^ \t]/) fc = ""
        return 1
      }
      if (n >= 3 && (c == "~" || index(substr(t, n + 1), "`") == 0)) { fc = c; fn = n; return 1 }
      return 0
    }'

# review_coverage <file>: one word on stdout, rc 0: complete, partial, none,
# missing or contradictory. Only the file's LAST non-empty line counts, from
# its first column, so a Coverage line quoted in a diff, a finding or tool
# output never does: `Coverage: complete` exactly, or `Coverage: partial` /
# `Coverage: none` with or without `: <reason>` (the fold writes them bare; the
# JSON has no reason). Anything else is missing, an absent or unreadable file
# too, and so is a last line inside a code fence, which a closed fence cannot
# hold (its closing line comes last) and an unterminated one always does.
# contradictory is a Codex lane only: below the last fold marker, the verdict
# JSON's top-level coverage (invoke_codex pretty-prints it, so that key alone
# sits at two spaces, and a finding's text cannot put a bare quote on a line) or,
# above it, the last line of the lane's text, when that line is a Coverage line
# outside any fence, disagrees with the file's last line. The marker is
# dispatch.md's own line, so it ends a fence the lane's text left open.
review_coverage() {
  local F=${1:-} V=""
  if [ -n "$F" ] && [ -f "$F" ]; then
    V=$(LC_ALL=C awk -v M="$_REVIEW_VERDICT_MARK" "$_GATES_FENCE_AWK"'
      function cov(s) {
        if (s == "Coverage: complete") return "complete"
        if (s ~ /^Coverage: partial(: .*)?$/) return "partial"
        if (s ~ /^Coverage: none(: .*)?$/) return "none"
        return ""
      }
      {
        sub(/\r$/, ""); sub(/[ \t]+$/, "")
        if ($0 == M) { mark = 1; text = (fc == "") ? last : ""; fc = ""; js = "" }
        else {
          fenced($0)
          if (mark && $0 ~ /^  "coverage": "(complete|partial|none)",?$/) { split($0, a, "\""); js = a[4] }
        }
        if ($0 != "") last = $0
      }
      END {
        v = (fc == "") ? cov(last) : ""
        if (v == "") { print "missing"; exit }
        if (mark) {
          t = cov(text)
          if ((t != "" && t != v) || (js != "" && js != v)) { print "contradictory"; exit }
        }
        print v
      }' "$F" 2>/dev/null) || V=""
  fi
  case "$V" in
    complete|partial|none|contradictory) printf '%s\n' "$V" ;;
    *) printf 'missing\n' ;;
  esac
  return 0
}

# review_coverage_gaps <lanes> <gaps>: append "<lane>: coverage <value>" to
# <gaps> for each lane on the <lanes> list whose file is there and not complete.
# A lane with no file, or an empty one, is the caller's to name: synthesis.md's
# lanes loop already wrote it to the same gaps file. Lane paths are relative to
# the working directory, as the loop reads them.
review_coverage_gaps() {
  local LANES=${1:-} GAPS=${2:-} LANE V
  if [ -z "$LANES" ] || [ -z "$GAPS" ]; then
    echo "usage: review_coverage_gaps <lanes> <gaps>" >&2
    return 64
  fi
  while IFS= read -r LANE || [ -n "$LANE" ]; do
    if [ -n "$LANE" ] && [ -s "$LANE" ]; then
      V=$(review_coverage "$LANE")
      if [ "$V" != complete ]; then printf '%s: coverage %s\n' "$LANE" "$V" >> "$GAPS"; fi
    fi
  done < "$LANES"
  return 0
}

# review_verdict_coverage <verdict.json>: the coverage value of the JSON
# invoke_codex pretty-printed, or nothing when it has none: dispatch.md's fold
# then writes no Coverage line, and the lane reads as missing.
review_verdict_coverage() {
  LC_ALL=C awk '/^  "coverage": "(complete|partial|none)",?$/ { split($0, a, "\""); print a[4]; exit }' "${1:-/dev/null}" 2>/dev/null || true
  return 0
}

# persona_verdict <file> plan|verify: read a plan-checker or integration-verifier
# report fail-closed (R28, KTD11). rc 0 pass. rc 1: NEEDS_REVISION, FAIL,
# NEEDS_CONTEXT, or a contradiction (APPROVED over blocking content, PASS over a
# recommendation that is not PROCEED_TO_NEXT_WAVE or a check that reads FAIL).
# rc 2: malformed or missing.
# Every rc but 0 writes one stderr line quoting what it read; rc 64 is a bad call.
#
# A line counts from its first column, so an indented quote never does, and a
# heading inside a code fence is a quoted example, never the verdict, so a report
# whose only Status sits in one, a report wrapped whole in one too, is malformed,
# and so is a fence left unterminated, which could hide anything below it. A fenced
# line inside an open section is still that section's content. plan wants one
# `### Status:` line holding APPROVED or NEEDS_REVISION, and APPROVED one section
# whose heading starts `### Blocking issues`, empty or holding only a None
# spelling: None or None identified, with or without a list marker, bold or a
# closing period. A heading's own text after that start is read as the section's
# first line, a bare `(...)` qualifier aside, so `### Blocking issues: <a real
# issue>` is content. verify wants one `### Status:` line holding PASS, FAIL or
# NEEDS_CONTEXT, and PASS one `### Recommendation` section whose first line is
# PROCEED_TO_NEXT_WAVE, under no `### Build`, `### Tests`, `### Lint` or
# `### Contract conformance` line reading FAIL. A section ends at the next heading
# of level 1 to 3, so `#### x` inside one is content. As
# in _lease_parse_status, bold and a closing period are tolerated around a value;
# unlike it, no other text is, so `APPROVED with caveats` is malformed.
persona_verdict() {
  local F=${1:-} K=${2:-} O="" C=""
  case "$K" in
    plan|verify) ;;
    *) echo "usage: persona_verdict <file> plan|verify" >&2; return 64 ;;
  esac
  if [ -z "$F" ] || [ ! -s "$F" ]; then
    printf 'persona_verdict: %s verdict %s: missing or empty\n' "$K" "${F:-(no file named)}" >&2
    return 2
  fi
  O=$(LC_ALL=C awk -v K="$K" "$_GATES_FENCE_AWK"'
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function value(s) { gsub(/\*/, "", s); s = trim(s); sub(/[.,;]$/, "", s); return s }
    function quote(s) { return (length(s) > 160) ? substr(s, 1, 160) "..." : s }
    function say(rc, s) { print rc " " K " verdict: " s; exit }
    # the section is open from its heading to the next heading of level 1 to 3
    function section(want, line, s) {
      count[want]++; sec = want
      s = trim(substr(line, RLENGTH + 1))
      sub(/^\([^)]*\)/, "", s); s = trim(s); sub(/^:/, "", s); s = trim(s)
      if (s != "") add(s)
    }
    function add(s) { if (body[sec] == "") head[sec] = s; body[sec] = body[sec] s }
    {
      sub(/\r$/, ""); line = $0
      if (fenced(line)) { if (sec != "" && line ~ /[^ \t]/) add(line); next }
      plain = $0; gsub(/\*/, "", plain); low = tolower(plain)
      if (match(low, /^###[ \t]*status/)) {
        ns++; v = trim(substr(plain, RLENGTH + 1)); sub(/^:/, "", v)
        st[ns] = value(v); raw[ns] = trim(line); sec = ""
      }
      else if (match(low, /^###[ \t]*blocking issues/)) section("blocking", plain)
      else if (match(low, /^###[ \t]*recommendation/)) section("recommendation", plain)
      else if (K == "verify" && match(low, /^###[ \t]*(build|tests|lint|contract conformance)[ \t]*:/)) {
        sec = ""
        if (bad == "" && value(substr(plain, RLENGTH + 1)) ~ /^FAIL([^A-Za-z_]|$)/) bad = trim(line)
      }
      else if (line ~ /^(#|##|###)[ \t]/) sec = ""
      else if (sec != "" && line ~ /[^ \t]/) add(line)
    }
    END {
      if (fc != "") say(2, "a code fence is left unterminated")
      if (ns == 0) say(2, "no ### Status: line outside a code fence")
      if (ns > 1) say(2, ns " ### Status: lines: " quote(raw[1]) " / " quote(raw[2]))
      s = st[1]
      if (K == "plan") {
        if (s == "NEEDS_REVISION") say(1, "NEEDS_REVISION: " quote(head["blocking"]))
        if (s != "APPROVED") say(2, "malformed status: " quote(raw[1]))
        if (count["blocking"] == 0) say(2, "APPROVED with no ### Blocking issues section")
        if (count["blocking"] > 1) say(2, count["blocking"] " ### Blocking issues sections")
        b = tolower(body["blocking"]); gsub(/[ \t]/, "", b)
        if (b == "" || b ~ /^[-*+]?\*?\*?none(identified)?\*?\*?\.?\*?\*?$/ || b == "<list,ornone>" || b == "<listornone>") say(0, "")
        say(1, "APPROVED contradicts ### Blocking issues: " quote(head["blocking"]))
      }
      if (s == "FAIL") say(1, "FAIL: " quote(head["recommendation"]))
      if (s == "NEEDS_CONTEXT") say(1, "NEEDS_CONTEXT, the lead fixes the environment and runs it again: " quote(head["recommendation"]))
      if (s != "PASS") say(2, "malformed status: " quote(raw[1]))
      if (bad != "") say(1, "PASS contradicts " quote(bad))
      if (count["recommendation"] == 0) say(2, "PASS with no ### Recommendation section")
      if (count["recommendation"] > 1) say(2, count["recommendation"] " ### Recommendation sections")
      r = value(head["recommendation"])
      if (r == "PROCEED_TO_NEXT_WAVE") say(0, "")
      if (r == "FIX_REQUIRED" || r == "ESCALATE") say(1, "PASS contradicts ### Recommendation: " r)
      say(2, "malformed ### Recommendation: " quote(head["recommendation"]))
    }' "$F" 2>/dev/null) || O=""
  C=${O%% *}
  case "$C" in
    0) return 0 ;;
    1|2) printf 'persona_verdict: %s\n' "${O#* }" >&2; return "$C" ;;
    *) printf 'persona_verdict: %s verdict %s: could not be read\n' "$K" "$F" >&2; return 2 ;;
  esac
}

# learnings_store_empty: rc 0 only when the planning spawn of learnings-researcher
# has nothing to search (R29, KTD10): every source the persona reads, relative to
# the working directory as a skill block's ops/ is, holds only the skeleton.
# ops/solutions/ and ops/decisions/ hold nothing but folders, and ops/MEMORY.md and
# ops/CHANGELOG.md are absent or byte-identical to the shipped templates. Anything
# it cannot prove empty is not empty: a symlink, an unreadable folder, a template
# this install lacks, and a directory with no ops/ at all, which is a run from the
# wrong folder and says nothing about the store. The review gate is dispatch.md's.
learnings_store_empty() {
  local D F L T="${_TRIFORGE_SCRIPTS_DIR}/../templates/ops"
  # Without read and search on ops/ every test below would read "absent".
  [ -d ops ] && [ -r ops ] && [ -x ops ] || return 1
  for D in ops/solutions ops/decisions; do
    if [ -e "$D" ] || [ -L "$D" ]; then
      L=$(find "$D" ! -type d -print 2>/dev/null) || return 1
      if [ -n "$L" ]; then return 1; fi
    fi
  done
  for F in MEMORY.md CHANGELOG.md; do
    if [ -e "ops/$F" ] || [ -L "ops/$F" ]; then
      cmp -s "ops/$F" "$T/$F" || return 1
    fi
  done
  return 0
}
