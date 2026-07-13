#!/usr/bin/env bash
# Claude Code PreToolUse (Bash) guard. PreToolUse runs in EVERY permission mode, including bypass.
# stdin JSON: {"tool_name":"Bash","tool_input":{"command":"..."},"permission_mode":"default|acceptEdits|auto|dontAsk|plan|bypassPermissions"}
#
# §4.5 destructive operations -> HARD BLOCK (exit 2). No key, no mode, no escape.
#
# §4.4 git commit / git push -> ASK THE USER, IN SESSION. The hook answers with
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask", ...}}
# and Claude Code escalates to a permission prompt that ONLY the human can answer. Approve once and Claude
# runs the commit itself — you never have to paste commands into your own terminal. The model cannot
# self-approve (it never sees the keypress) and cannot forge the decision (this hook is a separate process).
#
# Verified on Claude Code 2.1.205: a hook "ask" is honoured — the tool does not run until the user says yes —
# in permission_mode default, acceptEdits, auto and dontAsk. It is NOT verified under bypassPermissions, so
# there (and for any mode this hook does not recognise, i.e. anything added in a future release) we FAIL
# CLOSED and hard-block instead of trusting a prompt that may never reach the user.
#
# CLAUDE_GIT_OK=1, exported by the user before the session starts, pre-authorises the session. It exists for
# headless/CI runs where no one is at the keyboard. It does NOT replace approval: present the message first.
set -uo pipefail
INPUT="$(cat)"

# Extract the command + the permission mode (jq > python3 > raw text fallback).
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  PERM_MODE="$(printf '%s' "$INPUT" | jq -r '.permission_mode // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("tool_input",{}).get("command",""))' 2>/dev/null)"
  PERM_MODE="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d.get("permission_mode",""))' 2>/dev/null)"
else
  CMD="$INPUT"
  PERM_MODE="$(printf '%s' "$INPUT" | sed -n 's/.*"permission_mode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
PERM_MODE="${PERM_MODE:-}"
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

# §4.5 remote-code-execution & permission-nuke -> HARD BLOCK. A downloaded script piped straight into a shell
# runs code no one has read; a world-writable chmod or a disk-overwriting dd is irreversible.
echo "$CMD" | grep -qE '(curl|wget|fetch)([^|]|\|\|)*\|[[:space:]]*(sudo[[:space:]]+)?(bash|sh|zsh|python[0-9.]*|node|perl|ruby)([[:space:]]|$)' && block "pipe-to-shell (curl|bash RCE)" "4.5"
echo "$CMD" | grep -qE '(^|[^a-zA-Z])dd[[:space:]]+([^|]*[[:space:]])?of='  && block "dd of= (disk overwrite)" "4.5"
echo "$CMD" | grep -qE '(^|[^a-zA-Z])chmod[[:space:]]+(-[A-Za-z]*[[:space:]]+)*(0?777|a=?\+?rwx|\+rwx)([[:space:]]|$)' && block "chmod 777 (world-writable)" "4.5"

# §4.5 gate-tampering -> HARD BLOCK. A gate you can silently remove is not a gate: redirecting core.hooksPath,
# or deleting/overwriting/patching the hook scripts, would disarm the trace/secret/approval gates in one line.
echo "$CMD" | grep -qE 'git[[:space:]]+config\b[^|]*core\.hooksPath'                       && block "git config core.hooksPath (disarms the git hooks)" "4.5"
echo "$CMD" | grep -qE '(rm|mv|cp|truncate|tee|install|ln)\b[^|]*\.claude/(hooks|settings\.json)' && block "tampering with a .claude gate file" "4.5"
echo "$CMD" | grep -qE 'sed[[:space:]]+-i[^|]*\.claude/(hooks|settings\.json)'             && block "in-place edit of a .claude gate file" "4.5"
echo "$CMD" | grep -qE '(rm|mv|cp|truncate|tee|chmod|sed[[:space:]]+-i)\b[^|]*\.git/hooks/' && block "tampering with .git/hooks" "4.5"
echo "$CMD" | grep -qE '>[[:space:]]*[^|]*\.claude/(hooks|settings\.json)'                 && block "redirect over a .claude gate file" "4.5"

# §4.5 force-add bypasses .gitignore (sneaks build output / secrets past the bloat & ignore rules); deleting a
# lockfile is a §4.5 op the discipline already names. Both are only done on an explicit request.
echo "$CMD" | grep -qE 'git[[:space:]]+add[[:space:]]+([^;&|]*[[:space:]])?(-[A-Za-z]*f[A-Za-z]*|--force)([[:space:]]|$)' && block "git add -f (bypasses .gitignore)" "4.5"
echo "$CMD" | grep -qE '(rm|git[[:space:]]+rm)\b[^|]*(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|npm-shrinkwrap\.json|Gemfile\.lock|poetry\.lock|Pipfile\.lock|Cargo\.lock|composer\.lock|go\.sum|packages\.lock\.json)' && block "lockfile deletion" "4.5"

# --- §4.4 commit/push approval gate ---
# Escape a shell string into a JSON string body. A raw control character inside a JSON string is a parse
# error, and the reason text is attacker-adjacent (it is the model's own command line), so:
#   - delete every control char except tab and newline (this also removes CR, which a CRLF here-doc leaks);
#   - fold a surviving tab to a space (display-only text; the command Claude runs is untouched);
#   - escape backslash and double quote;
#   - fold newlines to the two-character \n escape.
json_escape(){
  printf '%s' "$1" \
    | tr -d '\000-\010\013-\037\177' \
    | tr '\011' ' ' \
    | sed 's/\\/\\\\/g; s/"/\\"/g' \
    | awk 'NR>1{printf "\\n"} {printf "%s", $0}'
}
# Escalate to a permission prompt only the user can answer, then let Claude run the command itself.
ask_user(){
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$(json_escape "$1")"
  exit 0
}
is_git_write() {
  printf '%s' "$1" | grep -qiE '(^|[;&|(]|[[:space:]])git[[:space:]]+([^;&|[:space:]]+[[:space:]]+)*(commit|push)([[:space:]]|$|;|&|\|)'
}
if is_git_write "$CMD"; then
  # The key is granted by the user's environment, never by the command line the model composes.
  if printf '%s' "$CMD" | grep -q 'CLAUDE_GIT_OK'; then
    echo "GUARD (§4.4): the attempt to set the approval key (CLAUDE_GIT_OK) inside the command was rejected." >&2
    echo "The key is set only by the user, before the session starts." >&2
    exit 2
  fi
  case "${CLAUDE_GIT_OK:-}" in
    1|yes|true|on|YES|TRUE|ON) exit 0 ;;   # pre-authorised session (headless/CI) -> pass
  esac
  case "$PERM_MODE" in
    default|acceptEdits|auto|dontAsk)
      # A prompt provably reaches the user in these modes: ask, and let them approve in one keypress.
      SHORT="$CMD"
      [ "${#SHORT}" -gt 300 ] && SHORT="$(printf '%s' "$SHORT" | cut -c1-300)…"
      # §4.4 branch guard: committing straight onto main/master is not blocked (a fresh project legitimately
      # lives on main), but it is surfaced in the approval prompt so the user can send it to a branch instead.
      BRANCH_WARN=""
      case "$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" in
        main|master) BRANCH_WARN="⚠️  This commits DIRECTLY to the default branch. Prefer a feature branch unless you meant to.

" ;;
      esac
      ask_user "§4.4 commit/push approval gate. Claude wants to run:

$SHORT

${BRANCH_WARN}Approve only if the commit message above was shown to you and you agree with it. Approving lets Claude run the command itself."
      ;;
    *)
      # bypassPermissions, plan, or an unrecognised/absent mode: we cannot prove the prompt would reach a
      # human, so we fail closed rather than let the gate silently evaporate.
      echo "GUARD (§4.4): 'git commit/push' is gated by approval AT THE TOOL LEVEL, and this session's permission mode ('${PERM_MODE:-unknown}') cannot show you an approval prompt." >&2
      echo "Present the commit MESSAGE to the user and get EXPLICIT approval. Then either:" >&2
      echo "  (a) the user re-runs Claude in a normal permission mode, where this gate asks them directly and Claude commits, OR" >&2
      echo "  (b) the user starts the session with 'CLAUDE_GIT_OK=1' (headless/CI), OR" >&2
      echo "  (c) the user runs the command in their own terminal." >&2
      exit 2 ;;
  esac
fi

exit 0
