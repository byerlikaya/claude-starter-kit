#!/usr/bin/env bash
# Claude Code PreToolUse guard for the FILE tools (Write / Edit / MultiEdit / NotebookEdit).
# Companion to guard-bash.sh: that one covers shell tampering, this one covers the model editing the gate
# scripts directly with its file tools. A gate you can silently rewrite is not a gate.
#
# stdin JSON: {"tool_name":"Write|Edit|...","tool_input":{"file_path":"...", ...}}
#
# HARD BLOCK (exit 2, every permission mode) when the target is a gate SCRIPT:
#   - .claude/hooks/*   (guard-bash.sh, guard-write.sh, pre-commit, commit-msg, session-guard.sh, blocklists)
#   - .git/hooks/*      (the armed git hooks themselves)
# settings.json is deliberately NOT blocked: the update-config skill legitimately edits it, and a hook/permission
# change there is reviewable — the irreversible, silent move is rewriting the scripts, so that is what we gate.
set -uo pipefail
INPUT="$(cat)"

if command -v jq >/dev/null 2>&1; then
  FP="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)"
elif command -v python3 >/dev/null 2>&1; then
  FP="$(printf '%s' "$INPUT" | python3 -c 'import sys,json;d=json.load(sys.stdin).get("tool_input",{});print(d.get("file_path") or d.get("notebook_path") or "")' 2>/dev/null)"
else
  FP="$(printf '%s' "$INPUT" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi
[ -z "$FP" ] && exit 0

block(){
  # Same write-only observability channel as guard-bash.sh, and absent for the same reason unless the operator
  # exports CSK_GATE_LOG. Logged after the verdict; it cannot change it.
  [ -n "${CSK_GATE_LOG:-}" ] && printf 'BLOCK\t§4.5\t%s\t%s\n' "gate-file edit (Write/Edit tools)" \
    "$(printf '%s' "$FP" | tr -d '\000-\037' | cut -c1-200)" >> "$CSK_GATE_LOG" 2>/dev/null
  echo "GUARD (§4.5): editing '$FP' is blocked AT THE TOOL LEVEL." >&2
  echo "This file is a gate script — rewriting it would disarm the trace/secret/approval gates. Kit updates go through the installer/update script, not the assistant's file tools. If the user explicitly wants it changed, they edit it in their own editor." >&2
  exit 2
}

case "$FP" in
  */.claude/hooks/*|.claude/hooks/*) block ;;
  */.git/hooks/*|.git/hooks/*)       block ;;
esac

# ---- team board: you may not start work nobody knows you started -----------------------------------------------
# The claim lock already makes it impossible for two people to HOLD the same item — a losing claim is refused in
# under a second, before any code exists. The hole this closes is the other one: somebody who never claims at all.
# Caught only at commit time, that is hours of work discovered as duplicated at the end, which is exactly the
# wasted effort the board exists to prevent. So the first file edit is where it is caught instead.
#
# Cost: this runs before EVERY Write/Edit, so it must not shell out. board.sh maintains a one-bit flag file
# (present == a board exists, it requires a claim, and this user holds none); everything here is a file test.
[ -n "${CSK_NO_BOARD:-}" ] && exit 0
GD=".git"
[ -d "$GD" ] || GD="$(git rev-parse --git-common-dir 2>/dev/null)"   # worktree/submodule: .git is a file
if [ -n "$GD" ] && [ -f "$GD/csk-board-guard" ]; then
  case "$FP" in
    */docs/*|docs/*|*/.claude/*|.claude/*) ;;   # planning notes and kit config are not the work being claimed
    *)
      echo "BOARD GATE: you hold no work item, so nobody else can see what you are starting." >&2
      echo "Claim one first: /board-csk  (lists what is free, what is blocked, and who holds the rest)." >&2
      echo "Work that belongs to no item: set CSK_NO_BOARD=1 for this session, and commit it with [chore]." >&2
      echo "Just claimed one elsewhere? The board view is cached — /board-csk sync refreshes it." >&2
      exit 2 ;;
  esac
fi
exit 0
