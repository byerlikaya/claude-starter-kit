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
  echo "GUARD (§4.5): editing '$FP' is blocked AT THE TOOL LEVEL." >&2
  echo "This file is a gate script — rewriting it would disarm the trace/secret/approval gates. Kit updates go through the installer/update script, not the assistant's file tools. If the user explicitly wants it changed, they edit it in their own editor." >&2
  exit 2
}

case "$FP" in
  */.claude/hooks/*|.claude/hooks/*) block ;;
  */.git/hooks/*|.git/hooks/*)       block ;;
esac
exit 0
