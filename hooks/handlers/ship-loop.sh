#!/usr/bin/env bash
# ship-loop.sh — Stop hook for /ship premature-exit prevention (inner guard)
#
# Prevents Claude from giving up before the pipeline is done.
# This is the INNER guard — it blocks premature exit within a single session.
#
# For true context-exhaustion recovery with fresh context per iteration,
# use the OUTER loop: scripts/coordinate.sh (external bash loop).
#
# State file: .claude/ship-loop.local.md (YAML frontmatter + prompt body)
# Activation: /ship or /coordinate creates the state file
# Termination: <promise>DONE</promise> in last assistant output, or max iterations (default 5)
#
# Presence of the state file (with active: true) indicates an active loop.
# Users who need to share a project directory across concurrent ship loops
# should run them from separate checkouts; per-session isolation via the
# hook-input session_id was removed because the slash commands can't know
# the runtime UUID at the time they create the state file.

set -euo pipefail

SHIP_STATE_FILE=".claude/ship-loop.local.md"

# Ensure .claude/ directory exists for project-local state files
mkdir -p .claude

# --------------------------------------------------
# 1. Read hook input from stdin (JSON from Claude Code)
# --------------------------------------------------
HOOK_INPUT=$(cat)

# --------------------------------------------------
# 2. Check if a ship loop is active
# --------------------------------------------------
if [[ ! -f "$SHIP_STATE_FILE" ]]; then
  exit 0  # No active loop — allow exit
fi

# --------------------------------------------------
# 3. Parse state file frontmatter
# --------------------------------------------------
FRONTMATTER=$(awk '/^---$/{i++; next} i==1{print} i>=2{exit}' "$SHIP_STATE_FILE")

ACTIVE=$(echo "$FRONTMATTER" | grep '^active:' | sed 's/active: *//')
if [[ "$ACTIVE" != "true" ]]; then
  exit 0  # Loop not active — allow exit
fi

# --------------------------------------------------
# 4. Parse iteration state
# --------------------------------------------------
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | tr -d '"')

# Defaults
COMPLETION_PROMISE="${COMPLETION_PROMISE:-DONE}"

# Validate numeric fields
if ! [[ "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Ship loop: Invalid iteration count. Cleaning up." >&2
  rm -f "$SHIP_STATE_FILE"
  exit 0
fi

if ! [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Ship loop: Invalid max_iterations. Cleaning up." >&2
  rm -f "$SHIP_STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# 5. Check max iterations
# --------------------------------------------------
if [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "Ship loop: Max iterations ($MAX_ITERATIONS) reached." >&2
  rm -f "$SHIP_STATE_FILE"
  exit 0  # Allow exit
fi

# --------------------------------------------------
# 6. Check for completion promise in last assistant output
# --------------------------------------------------
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transcript_path',''))" 2>/dev/null || echo "")

if [[ -n "$TRANSCRIPT_PATH" ]] && [[ -f "$TRANSCRIPT_PATH" ]]; then
  # Extract last assistant text from JSONL transcript
  LAST_OUTPUT=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null | tail -n 50 | python3 -c "
import sys, json
lines = sys.stdin.readlines()
for line in reversed(lines):
    try:
        msg = json.loads(line)
        contents = msg.get('message', {}).get('content', [])
        for c in contents:
            if c.get('type') == 'text':
                print(c.get('text', ''))
                sys.exit(0)
    except:
        continue
print('')
" 2>/dev/null || echo "")

  # Check for completion promise using exact match
  if [[ -n "$COMPLETION_PROMISE" ]] && [[ -n "$LAST_OUTPUT" ]]; then
    # Only attempt extraction if <promise> tags are actually present
    if echo "$LAST_OUTPUT" | grep -q '<promise>' 2>/dev/null; then
      PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
    else
      PROMISE_TEXT=""
    fi

    if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
      echo "Ship loop: Completion promise fulfilled. Pipeline done." >&2
      rm -f "$SHIP_STATE_FILE"
      exit 0  # Allow exit — work is done
    fi
  fi
fi

# --------------------------------------------------
# 7. Increment iteration and re-feed prompt
# --------------------------------------------------
NEXT_ITERATION=$((ITERATION + 1))

# Atomically update iteration counter (python avoids sed-injection risk)
TEMP_FILE="${SHIP_STATE_FILE}.tmp.$$"
NEXT_ITERATION="$NEXT_ITERATION" python3 -c "
import os, sys, re
n = os.environ['NEXT_ITERATION']
with open('$SHIP_STATE_FILE') as f:
    src = f.read()
sys.stdout.write(re.sub(r'^iteration: .*$', f'iteration: {n}', src, count=1, flags=re.MULTILINE))
" > "$TEMP_FILE"
mv "$TEMP_FILE" "$SHIP_STATE_FILE"

# Extract prompt text (everything after second ---)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$SHIP_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "Ship loop: No prompt text in state file. Cleaning up." >&2
  rm -f "$SHIP_STATE_FILE"
  exit 0
fi

# --------------------------------------------------
# 8. Block exit and re-feed the prompt (JSON-safe encoding)
# --------------------------------------------------
REASON_JSON=$(printf '%s' "$PROMPT_TEXT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")
SYS_MSG="Ship loop iteration $NEXT_ITERATION/$MAX_ITERATIONS | REFLECT BEFORE CONTINUING: What specifically failed? What concrete change will fix it? Am I repeating the same broken approach? If yes, try a fundamentally different strategy. | To complete: output <promise>$COMPLETION_PROMISE</promise> (ONLY when ALL work is done and verified)"
SYS_MSG_JSON=$(printf '%s' "$SYS_MSG" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))")

printf '{\n  "decision": "block",\n  "reason": %s,\n  "systemMessage": %s\n}\n' "$REASON_JSON" "$SYS_MSG_JSON"

exit 2
