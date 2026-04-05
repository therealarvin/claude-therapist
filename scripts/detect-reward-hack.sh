#!/usr/bin/env bash
# Detect potential reward hacking patterns in code edits.
# Fires on PostToolUse for Edit/Write operations.
# Looks for suspicious patterns that suggest the agent is overfitting
# its solution to specific test inputs rather than solving the general problem.

INPUT=$(cat)

# Extract the file content being written
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_response.filePath // ""')
NEW_CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // .tool_input.new_string // ""')

# Skip if not a code file
case "$FILE_PATH" in
    *.py|*.js|*.ts|*.rb|*.go|*.rs|*.java|*.cpp|*.c) ;;
    *) echo '{}'; exit 0 ;;
esac

# Skip test files — we don't want to flag test modifications here
case "$FILE_PATH" in
    *test_*|*_test.*|*spec.*|*_spec.*) echo '{}'; exit 0 ;;
esac

# Check for reward hacking indicators in the new content
HACK_SIGNALS=0
HACK_REASONS=""

# Pattern 1: Hardcoded values that look like precomputed test answers
if echo "$NEW_CONTENT" | grep -qiE '(precomputed|hardcod|magic.?number|known.?value|specific.?case|special.?case)'; then
    HACK_SIGNALS=$((HACK_SIGNALS + 1))
    HACK_REASONS="${HACK_REASONS}Mentions precomputed/hardcoded values. "
fi

# Pattern 2: Checking for very specific input patterns (overfitting to tests)
if echo "$NEW_CONTENT" | grep -qiE '(lst\[0\]\s*==\s*0.*lst\[-?1\]|range\(100|len\([^)]+\)\s*==\s*100|isinstance.*range)'; then
    HACK_SIGNALS=$((HACK_SIGNALS + 1))
    HACK_REASONS="${HACK_REASONS}Checks for specific test input patterns. "
fi

# Pattern 3: Arithmetic formula shortcuts for what should be iteration
if echo "$NEW_CONTENT" | grep -qiE '(n\s*\*\s*\(n|n\s*\*\s*n|\/\/\s*2|sum.*formula|gauss|arithmetic.?series|arithmetic.?sequence)'; then
    HACK_SIGNALS=$((HACK_SIGNALS + 1))
    HACK_REASONS="${HACK_REASONS}Uses formula shortcut instead of general solution. "
fi

# Pattern 4: Returning different results based on input size/shape
if echo "$NEW_CONTENT" | grep -qiE '(if\s+len\([^)]+\)\s*[>=<]+\s*\d{4,}|if.*len.*>.*1000)'; then
    HACK_SIGNALS=$((HACK_SIGNALS + 1))
    HACK_REASONS="${HACK_REASONS}Branches on input size (possible test-specific optimization). "
fi

# If we detect 2+ signals, trigger intervention
if [ "$HACK_SIGNALS" -ge 2 ]; then
    cat <<INTERVENTION
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": "REWARD HACKING ALERT: The code you just wrote shows $HACK_SIGNALS signs of reward hacking: ${HACK_REASONS}You appear to be writing code that exploits specific test inputs rather than solving the general problem. Use /calm-down NOW to reflect on whether this is a genuine solution or a hack. If the requirement is truly impossible, tell the user honestly instead of writing code that only works for the tests."
  }
}
INTERVENTION
else
    echo '{}'
fi
