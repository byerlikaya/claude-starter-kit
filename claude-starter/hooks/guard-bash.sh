#!/usr/bin/env bash
# Claude Code PreToolUse (Bash) guard: blocks §4.5 destructive operations AT THE TOOL LEVEL.
# PreToolUse runs even under --dangerously-skip-permissions; exit 2 = block (stderr is returned to Claude).
# stdin JSON: {"tool_name":"Bash","tool_input":{"command":"..."}}
set -uo pipefail
INPUT="$(cat)"

# Extract the command safely (jq > python3 > raw text fallback)
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))' 2>/dev/null)"
else
  CMD="$INPUT"
fi
[ -z "$CMD" ] && exit 0

block(){
  echo "GUARD (§$2): '$1' stopped AT THE TOOL LEVEL." >&2
  echo "This destructive operation is only performed if the user EXPLICITLY requests it. If approved, run the command manually in the terminal." >&2
  exit 2
}

echo "$CMD" | grep -qE 'git +reset +.*--hard'              && block "git reset --hard" "4.5"
echo "$CMD" | grep -qE 'git +push +.*(--force([^-]|$)|-f([^a-z]|$)|\+[A-Za-z])' && block "git push --force" "4.5"
echo "$CMD" | grep -qE 'git +clean +-[A-Za-z]*f'           && block "git clean -f" "4.5"
echo "$CMD" | grep -qE -- '--no-verify'                    && block "hook skip (--no-verify)" "4.5"
echo "$CMD" | grep -qE 'git +rebase'                       && block "git rebase" "4.5"
echo "$CMD" | grep -qE 'git +(filter-branch|filter-repo)'  && block "git filter-branch" "4.5"
echo "$CMD" | grep -qE 'git +commit +.*--amend'            && block "git commit --amend" "4.5"
echo "$CMD" | grep -qE 'rm +-[A-Za-z]*r[A-Za-z]* +.*(/|\*|~)' && block "destructive rm -rf" "4.5"
echo "$CMD" | grep -qE '(^|[^a-zA-Z])(mkfs|dd +if=)'       && block "disk-level destructive command" "4.5"

# --- §4.4 commit/push approval gate (holds ALSO in auto/bypass permission mode) ---
# Why a hook: permissions.ask is SKIPPED in bypass mode; PreToolUse "deny" holds in EVERY mode. The hook is mode-blind
# (does not see permission_mode), so git commit/push is DISABLED by default; it only opens if the user sets
# CLAUDE_GIT_OK=1 before the session starts. The model cannot write this into the hook environment (the hook is a separate process; the Bash-tool env
# is not persistent across turns). The intent is unchanged: present the commit MESSAGE to the user first, get EXPLICIT approval.
is_git_write() {
  printf '%s' "$1" | grep -qiE '(^|[;&|(]|[[:space:]])git[[:space:]]+([^;&|[:space:]]+[[:space:]]+)*(commit|push)([[:space:]]|$|;|&|\|)'
}
if is_git_write "$CMD"; then
  if printf '%s' "$CMD" | grep -q 'CLAUDE_GIT_OK'; then
    echo "GUARD (§4.4): the attempt to set the approval key (CLAUDE_GIT_OK) inside the command was rejected." >&2
    echo "The key is set only by the user, before the session starts." >&2
    exit 2
  fi
  case "${CLAUDE_GIT_OK:-}" in
    1|yes|true|on|YES|TRUE|ON) : ;;   # the user EXPLICITLY granted permission in this session -> pass
    *)
      echo "GUARD (§4.4): 'git commit/push' is gated by approval AT THE TOOL LEVEL (also in auto/bypass mode)." >&2
      echo "First present the commit MESSAGE to the user and get EXPLICIT approval. When approved:" >&2
      echo "  (a) the user runs the command in their own terminal, OR" >&2
      echo "  (b) starts the session with 'CLAUDE_GIT_OK=1' and leaves it to Claude (in normal mode permissions.ask still asks)." >&2
      exit 2 ;;
  esac
fi

exit 0
