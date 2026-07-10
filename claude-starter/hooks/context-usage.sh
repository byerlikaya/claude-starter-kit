#!/usr/bin/env bash
# Measures session context fill for REAL (NOT a guess): reads the API usage of the last main-context
# turn in the transcript JSONL -> input + cache_read + cache_creation = tokens in the context window.
# This is the number /context shows; since the assistant cannot run /context, it reads directly from here.
#
# Usage:
#   bash context-usage.sh [transcript.jsonl]            # if no arg is given, auto-finds from pwd
#   bash context-usage.sh --verbose [transcript.jsonl]  # long form, with the raw token counts
#   echo '{"transcript_path":"..."}' | bash context-usage.sh   # also accepts hook stdin JSON
# Window size: CONTEXT_WINDOW env (default 1000000).
#
# The default output is COMPACT on purpose. The UserPromptSubmit hook injects this line into the model's
# context on EVERY turn, and it stays there for the rest of the session — a long line is a per-turn tax that
# compounds through cache reads. The percentage carries all the signal; the raw counts are for humans, so they
# live behind --verbose (which is what session-guard.sh uses for its once-per-threshold user warning).
set -uo pipefail
WINDOW="${CONTEXT_WINDOW:-1000000}"
VERBOSE=0
case "${1:-}" in --verbose|-v) VERBOSE=1; shift ;; esac
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
  # No jq: parse the JSONL line-by-line. Skip sidechains; for the LAST main-context record that has a
  # cache_read, sum input + cache_read + cache_creation (mirrors the jq path above — same number).
  TOTAL="$(awk '
    /"isSidechain": *true/ { next }
    /"cache_read_input_tokens"/ {
      i=0; r=0; c=0
      if (match($0, /"input_tokens": *[0-9]+/))                 { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); i=s }
      if (match($0, /"cache_read_input_tokens": *[0-9]+/))      { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); r=s }
      if (match($0, /"cache_creation_input_tokens": *[0-9]+/))  { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); c=s }
      total=i+r+c
    }
    END { if (total!="") print total }
  ' "$TR")"
fi
[ -n "${TOTAL:-}" ] || { echo "context-usage: could not read usage" >&2; exit 1; }

# LC_ALL=C: force a '.' decimal separator regardless of locale (tr_TR etc. would emit '77,2' and could
# mis-parse the percentage). Generation AND every comparison below run under C so they stay consistent.
PCT="$(LC_ALL=C awk -v t="$TOTAL" -v w="$WINDOW" 'BEGIN{printf "%.1f", (t/w)*100}')"
LEVEL="$(LC_ALL=C awk -v p="$PCT" 'BEGIN{ if(p+0<50) print "continue"; else if(p+0<75) print "medium"; else print "handoff+clear" }')"
# The '%<number>' shape is a contract: session-guard.sh reads the percentage back out of this line.
if [ "$VERBOSE" = 1 ]; then
  echo "🔋 Session: %$PCT ($TOTAL/$WINDOW token) → $LEVEL"
else
  echo "🔋 Session %$PCT → $LEVEL"
fi
# >=75%: a short nudge for the model. The USER already gets the full, once-per-threshold warning from the
# Stop hook (session-guard.sh), so repeating the whole sentence here every turn would be pure duplication.
if LC_ALL=C awk -v p="$PCT" 'BEGIN{exit !(p+0>=75)}'; then
  echo "⚠️ >75% — hand off (handoff skill) then /clear; not automatic."
fi
