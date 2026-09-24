#!/usr/bin/env bash
# SessionStart hook — put the TEAM's state into a session that would otherwise only know its own.
#
# The problem it closes: every teammate runs the kit locally, so "Ali took item #1 two hours ago" exists
# nowhere this session can see. This hook injects the board summary at the start of every session, which is the
# one moment the answer changes what happens next: which item to pick up, which one is blocked, which claim has
# gone quiet.
#
# Deliberate scope:
#   - Same event and channel as session-rehydrate.sh: SessionStart + hookSpecificOutput.additionalContext is the
#     documented way to put text into the model's context.
#   - Matched on startup|resume|clear|compact. Unlike the handover hook this DOES include `startup`: a stale
#     handover nags, but "who holds what right now" is exactly what a fresh session is missing.
#   - NO NETWORK IN THE FOREGROUND. The visible half reads one cache file and exits. When that cache is older
#     than CREW_BOARD_MAX_AGE the hook starts a DETACHED refresher (fetch + heartbeat) whose result is used by the
#     NEXT session. On an unreachable remote the session-start cost stays at zero.
#   - Fails OPEN and SILENT: no repo, no board, no cache -> no output, exit 0. It never blocks a session.
set -uo pipefail
# The 2.x names of the variables a user can set still work (one helper: eval/lib/crew-env.sh).
_crew_d="${BASH_SOURCE%/*}"; [ "$_crew_d" = "${BASH_SOURCE}" ] && _crew_d=.
[ -f "$_crew_d/../eval/lib/crew-env.sh" ] && . "$_crew_d/../eval/lib/crew-env.sh"; unset _crew_d

# Two intervals, because two very different repos run this hook. Where a board exists, 15 minutes keeps the view
# worth acting on. Where none does — every solo project, and every install that upgraded into this feature — the
# only thing a refresh can do is ask the remote for a ref nobody has created, so it backs off to once a day.
# Without that split, a repo that will never have a board opened a background fetch at every session start.
MAX_AGE="${CREW_BOARD_MAX_AGE:-900}"
MAX_AGE_NOBOARD="${CREW_BOARD_MAX_AGE_NOBOARD:-86400}"

HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$HERE/$(basename "$0")"

# ---- detached half: the only place this hook is allowed to touch the network -----------------------------------
if [ "${1:-}" = "--refresh" ]; then
  cd "${2:-.}" 2>/dev/null || exit 0
  bash "$HERE/board.sh" sync >/dev/null 2>&1 || exit 0
  bash "$HERE/board.sh" beat >/dev/null 2>&1 || true
  exit 0
fi

# ---- foreground half: one file read, then a decision -----------------------------------------------------------
[ -n "${CREW_NO_BOARD:-}" ] && exit 0

IN=""
[ ! -t 0 ] && IN="$(cat 2>/dev/null || true)"
ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ROOT" ] || ROOT="$(printf '%s' "$IN" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$ROOT" ] || ROOT="$PWD"
# Windows hands this over as a native path and the stdin copy arrives JSON-encoded on top (`C:\\Repos\\app`).
# Undo the escaping, then fold the separators; both are no-ops on POSIX.
ROOT="${ROOT//\\\\//}"; ROOT="${ROOT//\\//}"

cd "$ROOT" 2>/dev/null || exit 0
GITDIR="$(git rev-parse --git-common-dir 2>/dev/null)" || exit 0
[ -n "$GITDIR" ] || exit 0

CACHE="$GITDIR/crew-board-cache"
STAMP=0
[ -f "$CACHE.at" ] && STAMP="$(tr -cd '0-9' < "$CACHE.at" 2>/dev/null)"
[ -n "$STAMP" ] || STAMP=0

# A non-empty cache means a board was found here; an absent or empty one means there is nothing to keep fresh.
# Costs no extra process: the same test decides, below, whether there is anything to say.
[ -s "$CACHE" ] || MAX_AGE="$MAX_AGE_NOBOARD"

NOW="$(date -u +%s 2>/dev/null || echo 0)"
if [ "$NOW" -gt 0 ] && [ "$((NOW - STAMP))" -gt "$MAX_AGE" ]; then
  # stdin/stdout/stderr all detached: an inherited stdout keeps the hook's pipe open after it exits, and the
  # caller then waits to EOF on a fetch that has nothing to do with it.
  bash "$SELF" --refresh "$ROOT" </dev/null >/dev/null 2>&1 &
fi

# Never invent a board state. No cache (no board here, or every refresh so far failed) -> stay silent.
[ -s "$CACHE" ] || exit 0

MSG="$(cat "$CACHE")
Board state above is a cached snapshot; /crew-board sync refreshes it."

# ONE PATH, no jq. The JSON is built here on every machine, so a Mac with jq and a Windows box without it emit the
# same bytes. The escaper is jq-identical, measured on 15 inputs (quote, backslash, tab, CR, C0 controls, DEL,
# UTF-8, leading/trailing newlines, 5000 chars): 15/15 equal to `jq -cn --arg m`. The one it replaced escaped only
# the quote, the backslash and the newline, so a tab in an item title produced JSON the CLI cannot parse
# (measured: jq rc=5) and the board silently vanished from the session — on exactly the no-jq machine this
# branch existed for. The trailing newline on the printf closes the last record, so a value ending in a newline
# keeps it. One awk, no subshell per character. A CR that ENDS a line is dropped on purpose: it is a CRLF line
# ending, not content, and MSYS gawk already drops it on read (text mode) while BSD awk keeps it — measured on
# Windows. Stripping it here makes every OS emit the same bytes; a CR inside a line is still escaped as \r.
ESC="$(printf '%s\n' "$MSG" | LC_ALL=C awk 'BEGIN { ORS = ""
    for (i = 1; i < 32; i++) ctl[i] = sprintf("%c", i)
    nm[8] = "\\b"; nm[9] = "\\t"; nm[12] = "\\f"; nm[13] = "\\r" }
  NR > 1 { print "\\n" }
  { s = $0; sub(/\r$/, "", s)
    gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
    for (i = 1; i < 32; i++) {
      if (i == 10 || !index(s, ctl[i])) continue
      r = (i in nm) ? nm[i] : sprintf("\\u%04x", i)
      out = ""; while ((p = index(s, ctl[i])) > 0) { out = out substr(s, 1, p - 1) r; s = substr(s, p + 1) }
      s = out s
    }
    d = sprintf("%c", 127)
    if (index(s, d)) { out = ""; while ((p = index(s, d)) > 0) { out = out substr(s, 1, p - 1) "\\u007f"; s = substr(s, p + 1) }; s = out s }
    print s }')"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$ESC"
exit 0
