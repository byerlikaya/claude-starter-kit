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
  CMD="$(printf '%s' "$INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1 \
        | sed 's/\\n/\n/g; s/\\"/"/g; s/\\\\/\\/g')"
fi
[ -z "$CMD" ] && exit 0

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
