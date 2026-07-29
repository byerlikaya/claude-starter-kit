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
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))' 2>/dev/null)"
else
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
  if command -v python3 >/dev/null 2>&1; then
    MSG="$(CSK_CMD="$CMD" python3 -c '
import os, shlex
try: parts = shlex.split(os.environ["CSK_CMD"])
except ValueError: parts = []
out = []
for i, p in enumerate(parts):
    if p in ("-m", "--message") and i + 1 < len(parts): out.append(parts[i + 1])
    elif p.startswith("--message="): out.append(p.split("=", 1)[1])
print("\n".join(out))
' 2>/dev/null)"
  else
    MSG="$CMD"
  fi
  if [ -n "$MSG" ]; then
    MF="$(mktemp "${TMPDIR:-/tmp}/csk-msg.XXXXXX")"
    printf '%s\n' "$MSG" > "$MF"
    OUT="$OUT
$(bash "$DIR/commit-msg" "$MF" 2>&1)" || FAILED=1
    rm -f "$MF"
  fi
fi

if [ "$FAILED" = 1 ]; then
  echo "GUARD (§4.1/§4.2): the commit content gate rejected this commit before it ran." >&2
  echo "$OUT" >&2
  echo "Fix the flagged content and commit again. --no-verify is §4.5 and stays blocked." >&2
  exit 2
fi
exit 0
