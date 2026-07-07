#!/usr/bin/env bash
# Stop hook — above 75% session fill it GUARANTEES the handoff recommendation surfaces; it does not
# leave it to the model to "remember" (session management = a gate at the threshold, not a wish).
# context-usage.sh does the measurement. This hook only continues the model once before it stops,
# at the handoff+clear threshold and with the LOOP-GUARD. No automatic /clear — approval is the user's (§4.4).
# If the measurement fails it fails open (exit 0): it never blocks by mistake.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
IN="$(cat 2>/dev/null || true)"

# Loop guard: if this Stop is already a Stop-hook continuation, do not block again (infinite-loop guard).
case "$IN" in
  *'"stop_hook_active":true'*|*'"stop_hook_active": true'*) exit 0 ;;
esac

# Real context% — context-usage.sh reads transcript_path from the stdin JSON (first line = summary).
LINE="$(printf '%s' "$IN" | bash "$HERE/context-usage.sh" 2>/dev/null | head -1 || true)"

case "$LINE" in
  *"handoff+clear"*)
    # exit 2: stderr returns to the model; before stopping, the model presents the handoff recommendation to the user.
    echo "SESSION >75% ($LINE). Before closing your reply: EXPLICITLY present the session-health line + the handoff/clear recommendation to the user. If asked, write the handover to docs/SESSION_STATE.md applying the \`handoff\` skill. No automatic /clear (approval is the user's)." >&2
    exit 2 ;;
  *) exit 0 ;;
esac
