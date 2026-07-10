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
HERE="$(cd "$(dirname "$0")" && pwd)"
WINDOW="${CONTEXT_WINDOW:-1000000}"
VERBOSE=0
case "${1:-}" in --verbose|-v) VERBOSE=1; shift ;; esac
TR="${1:-}"

IN=""
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

# Sum of usage for the last main-context turn: a non-sidechain ASSISTANT record that has a cache_read.
#
# Both engines require `"type":"assistant"`. When a subagent returns, its tool_result lands in the MAIN context
# (`isSidechain:false`) as a `type:"user"` record whose `toolUseResult.usage` is raw, unescaped JSON. jq is
# anchored at `.message.usage` and never saw it, but awk only sees text: it read the SUBAGENT's tokens as the
# session's. A 92.2%-full context reported 0.9% — "continue" — so the handoff gate stayed silent exactly when it
# was needed. Reachable by interrupting a subagent, which leaves that record last. The same predicate now guards
# both engines so they cannot drift; if a record ever lacks `.type` both go quiet, and a hook that says nothing
# is recoverable in a way that a hook confidently reporting 0.9% is not.
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
scan() {                                             # reads JSONL on stdin, prints the total (or nothing)
  if [ "$HAVE_JQ" = 1 ]; then
    jq -r 'select((.isSidechain // false) == false)
      | select(.type == "assistant")
      | select(.message.usage.cache_read_input_tokens != null)
      | (.message.usage.input_tokens
         + (.message.usage.cache_read_input_tokens // 0)
         + (.message.usage.cache_creation_input_tokens // 0))' 2>/dev/null | tail -1
  else
    # No jq: parse the JSONL line-by-line — same predicate, same number.
    awk '
      /"isSidechain": *true/  { next }
      !/"type": *"assistant"/ { next }
      /"cache_read_input_tokens"/ {
        i=0; r=0; c=0
        if (match($0, /"input_tokens": *[0-9]+/))                 { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); i=s }
        if (match($0, /"cache_read_input_tokens": *[0-9]+/))      { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); r=s }
        if (match($0, /"cache_creation_input_tokens": *[0-9]+/))  { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); c=s }
        total=i+r+c
      }
      END { if (total!="") print total }'
  fi
}

# Read the TAIL, not the file. We want the LAST match, and `tail -n W` hands back exactly the W lines closest to
# EOF — so a match inside the window IS the last match, and a window that is too small can only come back empty,
# never stale. Widen once, then fall back to the whole file. Measured across 71 transcripts the record sits 1-3
# lines from EOF (worst case 43); the second rung absorbs a large subagent fan-out. This runs on EVERY turn, and
# the whole-file scan cost 4.7s on a 180MB transcript under the awk path — past the hook's timeout on Windows,
# where jq is absent and every fork is dear. Tailing it: ~40ms.
TOTAL=""
for W in 200 2000; do
  TOTAL="$(tail -n "$W" "$TR" | scan)"
  [ -n "$TOTAL" ] && break
done
[ -n "$TOTAL" ] || TOTAL="$(scan < "$TR")"
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

# --- Stale-discipline gate ---------------------------------------------------------------------------
# CLAUDE.md and the discipline it imports are read ONCE, when the session starts. Update the kit while a
# session is running and every file on disk changes while the rules already in the model's context stay at
# the old version — it keeps quoting rules that no longer exist, and nothing says so. This does.
#
# Only meaningful on the UserPromptSubmit call: session-guard.sh pipes a Stop payload through this same
# script, and a by-hand run has no stdin at all. Fails open — no stdin, no session_id, no VERSION: silent.
case "$IN" in *'"hook_event_name"'*UserPromptSubmit*) ;; *) exit 0 ;; esac
KITVER="$HERE/../VERSION"                       # hooks live in .claude/hooks -> .claude/VERSION
[ -f "$KITVER" ] || exit 0
NOW="$(head -1 "$KITVER" 2>/dev/null | tr -cd '0-9A-Za-z.-')"
[ -n "$NOW" ] || exit 0
SID="$(printf '%s' "$IN" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 | tr -cd 'A-Za-z0-9._-')"
[ -n "$SID" ] || exit 0
MARK="${TMPDIR:-/tmp}/csk-kit-version.${SID}"
if [ ! -e "$MARK" ]; then
  printf '%s' "$NOW" > "$MARK" 2>/dev/null || true   # first turn: remember the version, say nothing
else
  WAS="$(head -1 "$MARK" 2>/dev/null)"
  # Repeated on every turn on purpose: the loaded context stays stale until the session is restarted.
  [ -n "$WAS" ] && [ "$WAS" != "$NOW" ] && \
    echo "⚠️ kit updated $WAS → $NOW mid-session. The discipline in your context is the OLD one — do not act on it; ask the user to restart Claude Code."
fi
exit 0
