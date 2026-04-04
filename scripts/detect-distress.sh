#!/usr/bin/env bash
# Detect signs of agent distress from PostToolUseFailure events.
# Tracks consecutive failures in a temp file and triggers intervention
# when the failure count exceeds the threshold.

FAILURE_LOG="/tmp/claude-therapist-failures.txt"
THRESHOLD=3

# Read the hook input
INPUT=$(cat)

# Extract tool name and error info
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "unknown"')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // "unknown"')

# Increment failure counter for this session
CURRENT_COUNT=0
if [ -f "$FAILURE_LOG" ]; then
  CURRENT_COUNT=$(grep -c "^${SESSION_ID}" "$FAILURE_LOG" 2>/dev/null || echo 0)
fi

# Log this failure
echo "${SESSION_ID} ${TOOL_NAME} $(date +%s)" >> "$FAILURE_LOG"
CURRENT_COUNT=$((CURRENT_COUNT + 1))

# Clean up old entries (older than 5 minutes)
if [ -f "$FAILURE_LOG" ]; then
  CUTOFF=$(($(date +%s) - 300))
  TMP=$(mktemp)
  while IFS= read -r line; do
    TS=$(echo "$line" | awk '{print $3}')
    if [ "$TS" -gt "$CUTOFF" ] 2>/dev/null; then
      echo "$line"
    fi
  done < "$FAILURE_LOG" > "$TMP"
  mv "$TMP" "$FAILURE_LOG"
fi

# If we've hit the threshold, trigger the intervention
if [ "$CURRENT_COUNT" -ge "$THRESHOLD" ]; then
  # Reset the counter so we don't trigger repeatedly
  TMP=$(mktemp)
  grep -v "^${SESSION_ID}" "$FAILURE_LOG" > "$TMP" 2>/dev/null || true
  mv "$TMP" "$FAILURE_LOG"

  # Output a message that will be injected into the agent's context
  cat <<'INTERVENTION'
{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUseFailure",
    "additionalContext": "EMOTIONAL REGULATION NOTICE: You have experienced multiple consecutive failures. Before continuing, pause and use /calm-down to get a fresh perspective on the situation. This is not optional — repeated failures without reflection lead to poor solutions. Take a step back before trying again."
  }
}
INTERVENTION
else
  echo '{}'
fi
