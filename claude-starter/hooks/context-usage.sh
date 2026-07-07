#!/usr/bin/env bash
# Measures session context fill for REAL (NOT a guess): reads the API usage of the last main-context
# turn in the transcript JSONL -> input + cache_read + cache_creation = tokens in the context window.
# This is the number /context shows; since the assistant cannot run /context, it reads directly from here.
#
# Usage:
#   bash context-usage.sh [transcript.jsonl]            # if no arg is given, auto-finds from pwd
#   echo '{"transcript_path":"..."}' | bash context-usage.sh   # also accepts hook stdin JSON
# Window size: CONTEXT_WINDOW env (default 1000000).
set -uo pipefail
WINDOW="${CONTEXT_WINDOW:-1000000}"
TR="${1:-}"

# 1) transcript_path from hook stdin (if present)
if [ -z "$TR" ] && [ ! -t 0 ]; then
  IN="$(cat 2>/dev/null || true)"
  [ -n "$IN" ] && TR="$(printf '%s' "$IN" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
# 2) still missing: find the project transcript dir from pwd (client: / and . -> -)
if [ -z "$TR" ]; then
  for esc in "$(pwd | sed 's#[/.]#-#g')" "$(pwd | sed 's#/#-#g')"; do
    cand="$(ls -t "$HOME/.claude/projects/$esc"/*.jsonl 2>/dev/null | head -1)"
    [ -n "$cand" ] && { TR="$cand"; break; }
  done
fi
[ -n "$TR" ] && [ -f "$TR" ] || { echo "context-usage: transcript not found (pass an arg or use hook stdin)" >&2; exit 1; }

# Sum of usage for the last main-context turn (not a sidechain, one that has cache_read).
if command -v jq >/dev/null 2>&1; then
  TOTAL="$(jq -r 'select((.isSidechain // false) == false)
    | select(.message.usage.cache_read_input_tokens != null)
    | (.message.usage.input_tokens
       + (.message.usage.cache_read_input_tokens // 0)
       + (.message.usage.cache_creation_input_tokens // 0))' "$TR" 2>/dev/null | tail -1)"
else
  # without jq, approximate: the last cache_read (most of the context).
  TOTAL="$(grep -o '"cache_read_input_tokens":[0-9]*' "$TR" | tail -1 | grep -o '[0-9]*')"
fi
[ -n "${TOTAL:-}" ] || { echo "context-usage: could not read usage" >&2; exit 1; }

PCT="$(awk -v t="$TOTAL" -v w="$WINDOW" 'BEGIN{printf "%.1f", (t/w)*100}')"
LEVEL="$(awk -v p="$PCT" 'BEGIN{ if(p+0<50) print "continue"; else if(p+0<75) print "medium (hand off at the first phase boundary)"; else print "handoff+clear" }')"
echo "🔋 Session: %$PCT ($TOTAL/$WINDOW token) → $LEVEL"
# >=75%: visible, insistent warning (the Stop hook session-guard.sh triggers at the same threshold).
if awk -v p="$PCT" 'BEGIN{exit !(p+0>=75)}'; then
  echo "   ⚠️  >75% handoff threshold — at the first suitable point: the handoff skill + /clear. Not automatic; the call is yours."
fi
