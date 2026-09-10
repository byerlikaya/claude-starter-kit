#!/usr/bin/env bash
# The commit content gate, for installs that have no git hooks to put it in.
#
# §4.1/§4.2 (no AI trace, no vendor name) and the secret scan are enforced by `pre-commit` and `commit-msg`,
# which git runs via `core.hooksPath`. The PLUGIN edition cannot set that — a plugin ships Claude Code hooks,
# not git hooks — so a plugin-only install had the approval gate but none of the CONTENT gates: the model could
# commit a credential or an authorship trailer and nothing would look at it. Four distribution channels, one of
# them quietly weaker than the other three.
#
# This closes that by running the REAL scanners from PreToolUse, before the commit command executes. It does
# not re-implement them. A second matcher is how a gate passes while the thing it guards is broken — the same
# reasoning that made the blocklists carry their own test cases and made the eval graders reuse this very
# pattern file.
#
# In a FULL install this is harmless duplication: the git hooks still fire afterwards and catch the same
# content. Belt and braces on the strictest rules in the kit is a fair trade for the plugin edition no longer
# being the weak channel.
#
# Deliberately NOT covered: `--no-verify`. It is §4.5 and `guard-bash.sh` blocks it outright, so it never
# reaches this hook.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

# ---- CSK-JSON-PARSE ------------------------------------------------------------------------------------
_json_slice(){  # $1 = whole payload, $2 = key -> the raw (still JSON-escaped) string value, "" if absent
  local LC_ALL=C   # FIRST, so every expansion below -- the key search included -- counts and cuts in bytes.
                   # Lengths from ${#x} are used as offsets into ${y:n}; with the locale set before any of
                   # them, the two never disagree about a unit. Walking bytes is safe because no UTF-8
                   # continuation byte can be 0x5C or 0x22, so a cut cannot land inside a character at a
                   # quote or backslash edge. What this line is worth in SPEED depends on the platform --
                   # read the table in _json_unescape below before quoting a number for it.
  local pre rest seg w r n base=0 j=0 cl lim run=0 chunk C=4096 W=256; local -a acc=("")
  # Every "step past X" here is arithmetic on a length, never `${s#"$literal"}`. That shape reads like a
  # constant-time strip and is not one: bash retries the pattern at every prefix length, so stripping an
  # n-byte literal costs O(n^2). It was in this function twice, and both were measured:
  #   * `${1#*"$2"}` found the key -- cheap when the key sits near the front, quadratic in the distance to it
  #     otherwise. `permission_mode` behind a 100 KB command took 7.94s on Git Bash, 0.27s in front of it.
  #     Captured from Claude Code 2.1.267, the real order puts `permission_mode` BEFORE `tool_input`, so on
  #     that version this cost was not reachable -- this file's header had shown the opposite order, and was
  #     wrong. The parse stays order-independent regardless: the order is not a documented contract, and the
  #     payload is still moving (`effort` is absent from the field list recorded on 2.1.246).
  #   * `${tail#"$seg"\"}` stepped past each escaped quote: 16.8s for a single 100 KB step on Git Bash,
  #     against 0.002s for `${tail:${#seg}+1}` doing exactly the same thing.
  # `${1%%"$2"*}` still finds the FIRST occurrence -- the longest suffix that starts with the key starts at the
  # earliest one -- so a command containing the literal text `"command":"` still cannot relocate the parse.
  # Stepping by length removed the quadratic strip, but each escaped quote still sliced and re-assigned the
  # whole remainder, so an escape-dense command stayed k*n here as well (2.2s of the 6.8s described in
  # _json_unescape below, on Git Bash). The walk is chunked the same way: the payload is read 4096 bytes at a
  # time and every per-quote operation stays inside the chunk. One thing is carried across edges on purpose
  # -- the length of the backslash run in front of a quote -- because that run can straddle a window or a
  # chunk, and its parity is what decides whether the quote ends the value. Isolated, escape-dense 44030 B:
  # 2.61s -> 0.41s on Git Bash 5.3.15, 0.93s -> 0.09s on macOS/bash 3.2.
  # Output is byte-identical to the previous shape across 378 cases at four chunk/window sizes down to 7 and 1
  # bytes, and that shape to the one before it across a 27-case battery (escaped quotes, backslash runs before
  # a quote, the key twice, the key appearing first as a value, glob metacharacters, UTF-8, no closing quote,
  # empty input). Broken twins -- the run not carried across a window, a byte skipped after a quote -- prove
  # the battery sees both.
  pre="${1%%\"$2\"*}"                          # everything before the FIRST `"key"`
  [ "$pre" != "$1" ] || return 0               # key absent: emit nothing
  rest="${1:${#pre}+${#2}+2}"                  # past `"key"`
  seg="${rest%%\"*}"                           # skip `: "` up to the value's opening quote, when there is one
  [ "$seg" = "$rest" ] || rest="${rest:${#seg}+1}"
  # Walk to the closing quote that is NOT escaped. A `"` preceded by an odd number of backslashes is content.
  n=${#rest}; chunk="${rest:0:C}"; cl=${#chunk}
  while :; do
    lim=$((cl - j))
    if [ "$lim" -le 0 ]; then
      [ $((base + cl)) -lt "$n" ] || break                 # no closing quote at all: everything is already taken
      base=$((base + j)); chunk="${rest:base:C}"; cl=${#chunk}; j=0; continue
    fi
    [ "$lim" -le "$W" ] || lim=$W
    w="${chunk:j:lim}"
    seg="${w%%\"*}"
    if [ "$seg" = "$w" ]; then                             # no quote in view: take all of it, carry the run
      acc+=("$w"); j=$((j+lim))
      r="${w##*[!\\]}"; case "$w" in *[!\\]*) run=${#r} ;; *) run=$((run+${#w})) ;; esac
      continue
    fi
    acc+=("$seg"); j=$((j+${#seg}+1))
    r="${seg##*[!\\]}"; case "$seg" in *[!\\]*) run=${#r} ;; *) run=$((run+${#seg})) ;; esac
    if [ $((run % 2)) -eq 1 ]; then acc+=("\""); run=0; else break; fi
  done
  local IFS=''; printf '%s' "${acc[*]}"
}
_json_unescape(){  # left-to-right, a chunk at a time; a two-pass sed would corrupt `\\"` (escaped backslash + quote)
  # This is the tier-3 path below -- the one a stock Windows install actually runs on. It used to walk ONE
  # CHARACTER at a time, which is O(n^2) twice over: `${s%"${s#?}"}` matches a pattern the length of the
  # entire remainder just to read one character, and `out="$out$c"` recopies the output for each one.
  #
  # That was not a comfort question. This hook's timeout is 60s -- set in settings.json, NOT Claude Code's
  # default, and reading the default instead is how a first pass at this got the consequence wrong. A
  # PreToolUse hook KILLED at its timeout emits no exit 2, so every rule below is simply skipped. Measured on
  # the tier-3 path with jq and python3 both shadowed, the old shape crossed 60s at ~4.3 KB. And 4.3 KB is
  # not exotic: across 6791 Bash calls in 280 real transcripts, 2.49% of commands are bigger, and the largest
  # is 46815 B, which the old shape needed roughly 39 minutes to decode. One Bash call in forty walked past
  # §4.4 and §4.5 entirely, silently, on every stock Windows desktop.
  #
  # Two changes, and their wins are NOT the same shape -- writing them down as one number was the mistake
  # this comment exists to avoid repeating:
  #   * Taking the whole run up to the next backslash in ONE expansion, and indexing with `${s:0:1}` instead
  #     of matching a pattern, is 47x on a 4.4 KB payload. This one holds on every machine.
  #   * `local LC_ALL=C` makes these expansions byte-oriented instead of re-decoding the string on every
  #     substring operation. What that is WORTH depends on the platform, and putting a single number here
  #     would have been wrong three separate ways -- it was written as "another 5x" twice before this:
  #         macOS / bash 3.2, a locale set .................. 5x
  #         Git Bash 5.3.15, a locale set ................... 1.23x   (measured on the OLD shape; the new one
  #                                                                    touches the locale once per escape
  #                                                                    rather than once per character, so its
  #                                                                    ratio is smaller and unmeasured)
  #         Git Bash, LANG empty -- what Claude Code starts .. nothing at all
  #     So speed is not what keeps this line; CORRECTNESS is, and that half holds everywhere. `[0-9a-fA-F]`
  #     below is a collation-defined range outside the C locale: on a tr_TR desktop it is not 0-9a-f. That
  #     alone would justify the line, and it costs nothing. `local` restores the previous locale on return
  #     -- verified on bash 3.2 and on Git Bash 5.3.15, not assumed.
  #
  # Then the cost moved rather than went away. With the per-character walk gone, each escape still sliced the
  # whole REMAINDER -- `s="${s:${#pre}+1}"` -- so an escape-dense command stayed k*n: on Git Bash a 44080 B
  # command with 2755 escapes took 6.8s, 11% of the timeout. The input is now touched only a chunk at a time
  # (`${s:base:C}`, once per 4096 bytes) and every per-escape operation stays inside that chunk, so no escape
  # pays for the length of the whole command. That is the change that matters: bounding only the lookahead,
  # while still indexing the full string, was measured too and gave about 4x on both machines, against 6-12x
  # for the chunked walk. Five bytes are held back at a chunk's end whenever more input follows, so a
  # `\uXXXX` that starts in a chunk ends in it.
  # The output goes into an array joined once, not a string recopied at every append, and `\n`/`\t` are
  # written `$'\n'`/`$'\t'`, so this file carries no raw TAB for an editor or a copy to turn into spaces.
  #
  # Measured, isolated, previous shape -> this one:
  #     macOS/bash 3.2   escape-dense 44030 B, 2590 escapes .. 1.44s -> 0.12s
  #                      sparse 100014 B, 4 escapes ........... 0.09s -> 0.02s
  #     Git Bash 5.3.15  escape-dense 44030 B, 2590 escapes .. 3.92s -> 0.54s
  #     (LANG empty)     sparse 99997 B, 4 escapes ............ 0.49s -> 0.07s
  # These numbers do not travel, which is why each one names its machine.
  #
  # Output is byte-identical to the previous shape across 478 cases, each run at four chunk/window sizes
  # down to 7 and 1 bytes so that an edge falls every few bytes; that shape was itself byte-identical to
  # the original character walk across a 31-case battery (escaped quotes, `\\`, a lone trailing backslash, a
  # truncated `\u`, Turkish, emoji). Deliberately broken twins -- the 5-byte margin cut to 4, the backslash
  # not stepped over -- prove the battery sees both edges, and tier 1 and tier 3 return the same verdict on
  # the gate cases.
  local LC_ALL=C
  local s="$1" pre w c h n base=0 j=0 cl lim chunk C=4096 W=256; local -a acc=("")
  case "$s" in *\\*) ;; *) printf '%s' "$s"; return 0 ;; esac   # no escapes: the common case pays nothing
  n=${#s}; chunk="${s:0:C}"; cl=${#chunk}
  while :; do
    lim=$((cl - j))
    if [ $((base + cl)) -lt "$n" ]; then                  # more input after this chunk: hold 5 bytes back, so
      lim=$((lim - 5))                                     # a `\uXXXX` that starts in a chunk also ends in it
      if [ "$lim" -le 0 ]; then base=$((base + j)); chunk="${s:base:C}"; cl=${#chunk}; j=0; continue; fi
    else
      [ "$lim" -gt 0 ] || break
    fi
    [ "$lim" -le "$W" ] || lim=$W
    w="${chunk:j:lim}"
    pre="${w%%\\*}"                                        # the literal run before the next backslash in view
    if [ "$pre" = "$w" ]; then acc+=("$w"); j=$((j+lim)); continue; fi
    acc+=("$pre"); j=$((j+${#pre}+1))
    if [ $((base + j)) -ge "$n" ]; then acc+=("\\"); break; fi   # a lone trailing backslash stays literal, as before
    c="${chunk:j:1}"; j=$((j+1))
    case "$c" in
      n) acc+=($'\n') ;;
      t) acc+=($'\t') ;;
      r) ;;
      b|f) acc+=(" ") ;;
      u) if [ $((n - base - j)) -ge 4 ]; then h="${chunk:j:4}"; j=$((j+4)); else h=""; fi   # a short tail is left alone, as before
         # A `\uXXXX` used to become a literal `?`. That is not a lossy nicety, it is a hole: `\u002e` is `.`,
         # so `\u002eclaude/hooks/guard-bash.sh` decoded to `?claude/…` and matched no gate pattern, while jq
         # decoded the same bytes to the real path — the two tiers disagreed on whether a payload was an
         # attack. Printable ASCII is decoded properly (builtin printf, no fork); anything else still becomes
         # `?`, which is only ever a display concern because this value is used for MATCHING, never to write.
         case "$h" in
           00[2-7][0-9a-fA-F]) printf -v c "\\x${h#00}"; acc+=("$c") ;;
           *)                  acc+=("?") ;;
         esac ;;
      *) acc+=("$c") ;;
    esac
  done
  local IFS=''; printf '%s' "${acc[*]}"
}
# ---- /CSK-JSON-PARSE -----------------------------------------------------------------------------------

# Extract the -m/--message VALUES from the command line without an interpreter.
#
# Without this tier the fallback below hands the WHOLE command line to the message scanner, and a file path is
# not a message: `git commit -m "feat: add scaffolding" -- src/AI-generated/scaffold.ts` was refused with
# "TRACE-SCANNER (message): 'AI-generated'" while the message itself is clean. The same commit is ACCEPTED
# where python3 works, because that tier returns only the -m values — so the gate's verdict depended on
# whether an interpreter resolved, not on the commit. This makes the interpreter-free tier answer the same
# question the python3 tier answers.
#
# It is awk, not parameter expansion, and that is deliberate on a hook that already spawns ~49 processes for a
# commit: a pure-shell character walk was written first and MEASURED QUADRATIC — 146 B 0.006s,
# 4 KB 0.181s, 16 KB 1.03s, 64 KB 8.08s. That does NOT blow the 60 s timeout the kit sets, and the
# largest command payload seen across 6791 real Bash calls was 46.8 KB — so this is a tail-risk
# trade, not a rescue: awk is 0.049s flat to 64 KB and 0.585s at 1 MB, so the cost stops depending
# on what someone pasted into a commit message. One fork, on a path that already spawns ~49 and only
# when the python3 tier is unavailable; the zero-fork rule still governs the per-Bash-call path.
# Byte-oriented under LC_ALL=C, which is safe because a UTF-8 continuation byte is always >= 0x80
# and can never equal an ASCII quote.
#
# Contract: rc=0 with the values, or rc=1 when the line cannot be parsed with confidence (unterminated quote,
# trailing backslash, an -m with nothing after it). rc=1 keeps the over-inclusive fallback, so this can only
# remove false positives — it can never open a blind spot. Verified against a POSIX shlex oracle written
# independently in another language: 37 command shapes, 33 byte-identical, 4 safe fallbacks, 0 mismatches,
# with the harness itself calibrated by two deliberate mutations.
csk_msg_values() {
  CSK_CMD="$1" LC_ALL=C awk '
    BEGIN {
      s = ENVIRON["CSK_CMD"]; n = length(s); i = 1
      ntok = 0; cur = ""; have = 0
      while (i <= n) {
        c = substr(s, i, 1)
        if (c == " " || c == "\t" || c == "\n" || c == "\r" || c == "\f" || c == "\v") {
          if (have) { ntok++; tok[ntok] = cur; cur = ""; have = 0 }
          i++; continue
        }
        if (c == "\\") {                                  # outside quotes: escapes the next byte
          i++
          if (i > n) exit 1                               # trailing backslash
          cur = cur substr(s, i, 1); have = 1; i++; continue
        }
        if (c == "'"'"'") {                               # single quotes: literal to the next quote
          i++; have = 1
          while (1) {
            if (i > n) exit 1                             # no closing quote
            c = substr(s, i, 1)
            if (c == "'"'"'") { i++; break }
            cur = cur c; i++
          }
          continue
        }
        if (c == "\"") {                                  # double quotes: backslash escapes " and \
          i++; have = 1
          while (1) {
            if (i > n) exit 1                             # no closing quote
            c = substr(s, i, 1)
            if (c == "\"") { i++; break }
            if (c == "\\" && i < n) {
              nx = substr(s, i + 1, 1)
              if (nx == "\"" || nx == "\\") { cur = cur nx; i += 2; continue }
            }
            cur = cur c; i++
          }
          continue
        }
        cur = cur c; have = 1; i++
      }
      if (have) { ntok++; tok[ntok] = cur }

      out = ""; nout = 0
      for (k = 1; k <= ntok; k++) {
        t = tok[k]
        if (t == "-m" || t == "--message") {
          k++
          if (k > ntok) exit 1                            # -m with nothing after it: do not guess
          nout++; res[nout] = tok[k]
        } else if (substr(t, 1, 10) == "--message=") {
          nout++; res[nout] = substr(t, 11)
        }
      }
      for (k = 1; k <= nout; k++) printf "%s\n", res[k]
      exit 0
    }'
}

INPUT="$(cat)"
# Same ladder as guard-bash.sh, and for the same reason: the raw-text fallback leaves JSON escapes in place,
# so `-m \"…\"` never matches a quote-based extraction and the message silently goes unscanned. That is
# precisely how the first version of this hook passed a commit carrying a co-author trailer.
# And the same rule as guard-bash.sh about WHICH rung is taken: a tier is chosen on whether it works, not on
# whether it exists. Windows ships a Store redirector stub named python3 on PATH by default; `command -v` finds
# it, it exits 49 with an empty stdout, and this hook then read CMD="" and exited 0 — the commit content scan
# never ran. Measured on a stock Windows 11 desktop. The extraction's own exit status is the probe.
CMD=""; _parsed=0
if command -v jq >/dev/null 2>&1 && CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"; then
  _parsed=1
elif command -v python3 >/dev/null 2>&1 && CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))' 2>/dev/null)"; then
  _parsed=1
fi
if [ "$_parsed" = 0 ]; then
  # Tier 3, and it used to be a `sed | head | sed` pipeline: four processes on EVERY Bash tool call,
  # to re-derive a string guard-bash.sh had already parsed one hook earlier, and then re-answer a
  # question it had already answered. Measured on `ls -la`: guard-bash.sh 2 processes, this hook 7.
  # guard-write.sh already carried the shared parser; this was the one hook that never got it.
  CMD="$(_json_unescape "$(_json_slice "$INPUT" command)")"
fi
[ -z "$CMD" ] && exit 0

# A command that does not contain `git` at all cannot match the pattern below, and finding that out
# should not cost a process. Measured on `ls -la`: this hook spawned 7 processes to answer "no".
# The test is case-INSENSITIVE while the pattern is not, so it is a superset: it can only let more
# through to the real matcher, never less.
case "$CMD" in *[Gg][Ii][Tt]*) ;; *) exit 0 ;; esac

# Only git commit. Matching mirrors guard-bash.sh's tolerance for `git -C dir commit`, TAB separators and a
# quoted binary, because a gate that a whitespace change walks past is not a gate.
printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])["'"'"'`]?git["'"'"'`]?([[:space:]]+-[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)' || exit 0

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# `git commit -a` has not staged anything yet at this point; tell the scanner to look at tracked-but-unstaged
# changes too. Matches -a, --all and clusters like -am.
UNSTAGED=0
printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(--all|-[A-Za-z]*a[A-Za-z]*)([[:space:]]|$)' && UNSTAGED=1

FAILED=0
OUT=""
if [ -x "$DIR/pre-commit" ]; then
  OUT="$(CSK_SCAN_UNSTAGED="$UNSTAGED" bash "$DIR/pre-commit" 2>&1)" || FAILED=1
fi

# The message carries its own trace risk (a co-author trailer lives there, not in the diff), and commit-msg is
# what scans it. Reuse it on the -m value when there is one; an editor-composed message is not visible here and
# stays the git hook's job.
if [ "$FAILED" = 0 ] && [ -x "$DIR/commit-msg" ]; then
  # shlex parses the command the way a shell does, which matters because a real commit message is MULTI-LINE:
  # a line-oriented `sed` extraction found the subject and stopped, so a co-author trailer on line 3 — the
  # single most likely §4.1 violation, and the one the bare arm of the eval actually produced — went unscanned.
  # Without python3, scan the whole command text instead of guessing where the message ends: over-inclusive
  # beats a gate with a blind spot, and anything matching here belongs in neither the message nor the command.
  # `&&` on the assignment, not a bare `command -v`: a python3 that exists but cannot run (the Windows Store
  # stub) must land in the same over-inclusive fallback as no python3 at all. Testing existence alone left
  # MSG="" here, which reads exactly like "this commit has no -m" and skipped the message scan entirely.
  #
  # But WHICH branch we are in cannot be decided from MSG's emptiness either, and that is the subtler half.
  # "there is no -m" and "there is an -m but nothing here can extract it" are different facts with opposite
  # correct answers: the first must fall through to the fail-closed editor/-F path below, the second must
  # scan. Reading both off one empty string is what let a first attempt at this fix skip the fail-closed path
  # on exactly the Windows machines it was written for. So ask the question directly, with a test that needs
  # no interpreter. Cheap: nothing below runs unless the command is already known to be a `git commit`.
  HAS_M=0
  printf '%s' "$CMD" | grep -qE '(^|[[:space:]])(-[A-Za-z]*m|--message)([[:space:]]|=|$)' && HAS_M=1
  if command -v python3 >/dev/null 2>&1 && MSG="$(CSK_CMD="$CMD" python3 -c '
import os, shlex
try: parts = shlex.split(os.environ["CSK_CMD"])
except ValueError: parts = []
out = []
for i, p in enumerate(parts):
    if p in ("-m", "--message") and i + 1 < len(parts): out.append(parts[i + 1])
    elif p.startswith("--message="): out.append(p.split("=", 1)[1])
print("\n".join(out))
' 2>/dev/null)"; then
    :
  elif MSG="$(csk_msg_values "$CMD")"; then
    :
  else
    MSG="$CMD"
  fi
  if [ "$HAS_M" = 1 ] && [ -n "$MSG" ]; then
    MF="$(mktemp "${TMPDIR:-/tmp}/csk-msg.XXXXXX")"
    printf '%s\n' "$MSG" > "$MF"
    OUT="$OUT
$(bash "$DIR/commit-msg" "$MF" 2>&1)" || FAILED=1
    rm -f "$MF"
  else
    # No -m: either the message comes from a file (-F/--file, which we CAN read) or from an editor, which does
    # not exist yet at this point. In a full install the commit-msg git hook reads it afterwards and the gap
    # closes itself. In a plugin-only install nothing does — and a co-authorship trailer lives in the message,
    # not the diff, so that is precisely where §4.1 would be lost. Fail closed rather than wave it through:
    # a gate that silently skips the case it was built for is worse than no gate, because it reads as covered.
    MFILE=""
    if command -v python3 >/dev/null 2>&1; then
      MFILE="$(CSK_CMD="$CMD" python3 -c '
import os, shlex
try: parts = shlex.split(os.environ["CSK_CMD"])
except ValueError: parts = []
for i, p in enumerate(parts):
    if p in ("-F", "--file") and i + 1 < len(parts): print(parts[i + 1]); break
    if p.startswith("--file="): print(p.split("=", 1)[1]); break
' 2>/dev/null)"
    fi
    # No interpreter (or a stub that cannot run): a -F path is a single token, so a plain extraction gets it.
    # Without this the file is never read on Windows and the branch below refuses the commit — correct as a
    # direction, but it refuses the CLEAN -F commits too, and a gate that blocks the innocent is the one people
    # learn to route around. shlex is still preferred where it exists: it handles a quoted path with spaces.
    if [ -z "$MFILE" ]; then
      MFILE="$(printf '%s' "$CMD" \
        | sed -n 's/.*[[:space:]]--\{0,1\}[Ff]\(ile\)\{0,1\}[[:space:]=]\{1,\}\([^[:space:];&|]\{1,\}\).*/\2/p' \
        | head -1)"
      MFILE="${MFILE%\"}"; MFILE="${MFILE#\"}"; MFILE="${MFILE%\'}"; MFILE="${MFILE#\'}"
    fi
    if [ -n "$MFILE" ] && [ -f "$MFILE" ]; then
      OUT="$OUT
$(bash "$DIR/commit-msg" "$MFILE" 2>&1)" || FAILED=1
    else
      HP="$(git config core.hooksPath 2>/dev/null || true)"
      GITMSG_HOOK=""
      [ -n "$HP" ] && [ -x "$HP/commit-msg" ] && GITMSG_HOOK="$HP/commit-msg"
      [ -z "$GITMSG_HOOK" ] && [ -x "$(git rev-parse --git-path hooks/commit-msg 2>/dev/null)" ] \
        && GITMSG_HOOK="git-default"
      if [ -z "$GITMSG_HOOK" ]; then
        echo "GUARD (§4.1): this commit's message would go unscanned." >&2
        echo "No -m/-F was given, so the message is composed in an editor after this point, and no commit-msg" >&2
        echo "git hook is wired here to read it afterwards (plugin-only install: a plugin cannot set" >&2
        echo "core.hooksPath). Pass the message with -m so it can be scanned, or install the kit fully." >&2
        exit 2
      fi
    fi
  fi
fi

if [ "$FAILED" = 1 ]; then
  echo "GUARD (§4.1/§4.2): the commit content gate rejected this commit before it ran." >&2
  echo "$OUT" >&2
  echo "Fix the flagged content and commit again. --no-verify is §4.5 and stays blocked." >&2
  exit 2
fi
exit 0
