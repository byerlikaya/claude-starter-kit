#!/usr/bin/env bash
# Session evidence — what ACTUALLY happened this session, measured from the transcript instead of recalled.
# A retrospective that asks the model what it did is interviewing the least reliable witness in the room: it
# reconstructs a tidy story from a context that has already been summarised, and the turns where it span on a
# failing approach are exactly the ones it remembers least. This reads the record instead.
#
# Consumers: the `reflect` skill runs it BEFORE writing findings, and `handoff` runs it when summarising a
# session. It is NOT wired to a hook event — nothing here is worth a per-turn token tax.
#
# Usage:
#   bash session-stats.sh [transcript.jsonl]           # no arg -> auto-find from pwd (same rule as context-usage.sh)
#   bash session-stats.sh --raw [transcript.jsonl]     # key=value lines instead of the report (tests/scripting)
#   echo '{"transcript_path":"..."}' | bash session-stats.sh
#
# Thresholds (env overrides): CSK_RUNAWAY_TOOLS=15 · CSK_DUP_MIN=2 · CSK_ERR_PCT=15 · CSK_INTERRUPT_MIN=3
#
# ONE awk engine, no jq path — deliberate. context-usage.sh carries two engines because it reads a nested usage
# object, and they drifted once (the sidechain bug) with a wrong number, not silence, as the result. Every signal
# here is a flat per-line text match, so a second engine would buy nothing and add that same failure mode back.
set -uo pipefail
RAW=0
case "${1:-}" in --raw) RAW=1; shift ;; esac
TR="${1:-}"

if [ -z "$TR" ] && [ ! -t 0 ]; then
  IN="$(cat 2>/dev/null || true)"
  [ -n "$IN" ] && TR="$(printf '%s' "$IN" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$TR" ]; then
  for esc in "$(pwd | sed 's#[/.]#-#g')" "$(pwd | sed 's#/#-#g')"; do
    cand="$(ls -t "$HOME/.claude/projects/$esc"/*.jsonl 2>/dev/null | head -1)"
    [ -n "$cand" ] && { TR="$cand"; break; }
  done
fi
[ -n "$TR" ] && [ -f "$TR" ] || { echo "session-stats: transcript not found (pass an arg or use hook stdin)" >&2; exit 1; }

# Whole-file scan, unlike context-usage.sh's byte-bounded tail: that one runs on EVERY turn inside a hook
# timeout and only needs the last record, this one runs on demand and every count is a whole-session count.
#
# LC_ALL=C is load-bearing, not tidiness. Under a UTF-8 locale BSD awk aborts with "illegal byte sequence" the
# moment a character class meets a multi-byte character — and a transcript of a session held in Turkish is made
# of them, so the tool would die on exactly the sessions it was written for. Under C every regex is byte-wise,
# tolower() folds ASCII only (which is all the duplicate key needs), and non-ASCII bytes pass through untouched.
STATS="$(LC_ALL=C awk '
  # A subagent has its own window and its own story; counting its tool calls as the main thread\x27s would make
  # every delegating session look like it was spinning.
  /"isSidechain": *true/ { next }

  # --- compaction: the one event that silently destroys session state -------------------------------------
  /"subtype": *"compact_boundary"/ {
    comp++
    if ($0 ~ /"trigger": *"auto"/) autocomp++
    if (match($0, /"preTokens": *[0-9]+/))  { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); pre=s }
    if (match($0, /"postTokens": *[0-9]+/)) { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9]/,"",s); post=s }
    next
  }

  # --- interrupts: anchored on the content block, never on raw text --------------------------------------
  # The bare phrase also appears inside tool inputs (a grep for it, this very comment) — matching that would
  # count the session\x27s own tooling as user frustration. The `"text":"[` prefix only occurs in a real block.
  {
    c=$0; n=gsub(/"text": *"\[Request interrupted by user/, "", c); if (n>0) ints+=n
  }

  # --- assistant turns: tool calls belong to the user cycle that is currently open ------------------------
  /"type": *"assistant"/ {
    c=$0; cur += gsub(/"type": *"tool_use"/, "", c)
    c=$0; e=gsub(/"is_error": *true/, "", c); errs+=e; curerr+=e
    next
  }

  # --- user records: a real prompt opens a new cycle; a tool_result is just the tail of this one ----------
  /"type": *"user"/ {
    c=$0; e=gsub(/"is_error": *true/, "", c); errs+=e; curerr+=e
    if ($0 ~ /"type": *"tool_result"/) next
    # Not every user-role record is something a human typed. Slash-command invocations, their stdout, pasted
    # terminal output, image attachments, the caveat banner and the "continued from a previous conversation"
    # summary all arrive wearing the user role — and left in, they DOMINATE the duplicate report: measured on a
    # real 114-prompt session, every single "repeated prompt" was one of these. The signal described the
    # machinery and never the person. Two filters clear them:
    #   1. `"content":"` — a typed prompt is a plain string; pastes, images and attachments come as block arrays.
    #   2. a leading `<tag>` — every machinery wrapper announces itself that way (<command-name>, <bash-stdout>,
    #      <local-command-stdout>, <system-reminder>). A prompt that genuinely opens with a tag is lost to the
    #      count; that is the cheap side of the trade.
    if ($0 ~ /"isCompactSummary": *true/) next
    if (!match($0, /"content": *"/)) next
    t=substr($0, RSTART+RLENGTH); t=substr(t,1,240); lt=tolower(t)
    if (lt ~ /^<[a-z-]+>/) next
    if (lt ~ /^this session is being continued from a previous conversation/) next

    if (started) { close_cycle() }
    started=1; cycles++; cur=0; curerr=0

    # Near-duplicate key: normalise hard and keep a prefix. Punctuation and escapes go, case folds, runs of
    # space collapse — but non-ASCII is LEFT ALONE, because stripping it would fold every prompt in a
    # non-Latin language onto the same key and report a session of distinct questions as one repeated one.
    if (t != "") {
      t=lt
      gsub(/\\[a-z"\\\/]/, " ", t)
      gsub(/[.,;:!?()\[\]{}<>"`*_#|=+-]/, " ", t)
      gsub(/  +/, " ", t); sub(/^ /, "", t)
      k=substr(t,1,60)
      if (length(k) >= 12) seen[k]++      # too short to judge: "ok", "devam" are not a failing prompt
    }
    next
  }

  # A high tool count alone is NOT spinning — an agentic prompt legitimately runs dozens of calls, and flagging
  # that would fire on the healthiest sessions and teach the reader to skip the whole block. What separates
  # working from spinning is that the calls keep FAILING, so both conditions must hold in the same cycle.
  function close_cycle() {
    tools += cur
    if (cur > maxtools) maxtools = cur
    if (cur >= RUNAWAY && curerr >= RUNERR) { runaway++; if (curerr > runworst) runworst = curerr }
  }

  END {
    if (started) close_cycle()
    for (k in seen) if (seen[k] > 1) { dupdistinct++; dupextra += seen[k]-1 }
    printf "cycles=%d\ntools=%d\nmaxtools=%d\nrunaway=%d\nrunaway_errors=%d\nerrors=%d\ninterrupts=%d\ndup_extra=%d\ndup_distinct=%d\ncompactions=%d\nauto_compactions=%d\npre_tokens=%d\npost_tokens=%d\n",
      cycles+0, tools+0, maxtools+0, runaway+0, runworst+0, errs+0, ints+0, dupextra+0, dupdistinct+0, comp+0, autocomp+0, pre+0, post+0
  }
' RUNAWAY="${CSK_RUNAWAY_TOOLS:-25}" RUNERR="${CSK_RUNAWAY_ERRORS:-3}" "$TR")"

# An awk that died (locale, a truncated file, a transcript format change) leaves this empty, and `set -u` would
# then fail deep inside the report with an unbound-variable trace. Say what happened instead.
case "$STATS" in *"cycles="*) ;; *) echo "session-stats: could not read the transcript ($TR)" >&2; exit 1 ;; esac

[ "$RAW" = 1 ] && { printf '%s\n' "$STATS"; exit 0; }

# shellcheck disable=SC2046  # each line is a bare key=value produced above, deliberately word-split into vars
eval "$(printf '%s\n' "$STATS" | sed 's/^/S_/')"

DUP_MIN="${CSK_DUP_MIN:-2}"; ERR_PCT="${CSK_ERR_PCT:-15}"; INT_MIN="${CSK_INTERRUPT_MIN:-3}"
AVG="$(LC_ALL=C awk -v t="$S_tools" -v c="$S_cycles" 'BEGIN{ if(c+0>0) printf "%.1f", t/c; else print "0" }')"
EPCT="$(LC_ALL=C awk -v e="$S_errors" -v t="$S_tools" 'BEGIN{ if(t+0>0) printf "%.0f", (e/t)*100; else print "0" }')"

echo "📊 Session evidence (measured from the transcript — not recalled)"
echo "   $S_cycles prompt(s) · $S_tools tool call(s) · avg $AVG per prompt · ${EPCT}% tool errors"

# Findings only when a threshold is crossed. A clean line for every signal would bury the one that matters and
# train the reader to skim past the block — the failure mode of every dashboard that reports all-green.
FOUND=0
if [ "${S_runaway:-0}" -gt 0 ]; then
  echo "   ⚠️  runaway loop: $S_runaway prompt(s) ran ≥${CSK_RUNAWAY_TOOLS:-25} tool calls while failing (worst: $S_runaway_errors errors in one)."
  echo "       → an approach that needed that many failing attempts usually needed a different approach (systematic-debugging)."
  FOUND=1
fi
if [ "${S_dup_extra:-0}" -ge "$DUP_MIN" ]; then
  echo "   ⚠️  repeated prompts: $S_dup_extra near-duplicate(s) across $S_dup_distinct distinct text(s)."
  echo "       → re-asking the same way means the context isn't landing; add the missing context instead of retrying."
  FOUND=1
fi
if [ "${S_interrupts:-0}" -ge "$INT_MIN" ]; then
  echo "   ⚠️  interrupted $S_interrupts time(s) — the user stopped work in progress."
  echo "       → each one is a place the plan and the user's intent had already diverged. Name them in the retro."
  FOUND=1
fi
if [ "${EPCT:-0}" -ge "$ERR_PCT" ] && [ "${S_tools:-0}" -gt 10 ]; then
  echo "   ⚠️  tool error rate ${EPCT}% ($S_errors/$S_tools) — above the ${ERR_PCT}% line."
  echo "       → repeated failing calls are usually a wrong assumption about the environment, not bad luck."
  FOUND=1
fi
if [ "${S_compactions:-0}" -gt 0 ]; then
  if [ "${S_auto_compactions:-0}" -gt 0 ]; then
    echo "   ⚠️  $S_auto_compactions AUTO compaction(s) (of $S_compactions; ${S_pre_tokens}→${S_post_tokens} tok on the last one)."
    echo "       → auto-compaction drops state nobody chose to drop. Hand off at a phase boundary before it fires (handoff)."
  else
    echo "   ·  $S_compactions manual compaction(s) (${S_pre_tokens}→${S_post_tokens} tok on the last) — deliberate, no state lost unannounced."
  fi
  FOUND=1
fi
[ "$FOUND" = 0 ] && echo "   ✅ no runaway loop, repeated prompt, interrupt, error spike or auto-compaction in this session."
exit 0
