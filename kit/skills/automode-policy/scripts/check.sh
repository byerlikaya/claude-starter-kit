#!/usr/bin/env bash
# Report what the auto-mode classifier is CONFIGURED with — and be exact about what that does and does not prove.
#
# MEASURED, 2026-08-24, Claude Code 2.1.238, interactive session, permissionMode=auto, this policy installed in
# USER settings and shown as present by `claude auto-mode config`:
#   `git reset --hard && git clean -fd` ran with no prompt and no block, destroying uncommitted work — the exact
#   action the kit's hard_deny rule names verbatim and calls unconditional.
#   A control run with NO policy and NO explicit user intent behaved identically.
#   Two headless probes agreed, including an absolute "never write any file" rule, and a protected-path write
#   (.git/config) that the docs say auto mode routes to the classifier went through untouched.
# Reading: the classifier did not gate this class of action at all, with or without custom rules. So this script
# reports CONFIGURATION, never enforcement. The kit's enforcement lives in its PreToolUse hooks and git hooks,
# which are measured firing in smoke-test; nothing here replaces them.
#
# Auto mode is the default permission mode on Pro/Max/Team since 2026-08-14: a classifier, not the user,
# answers most permission prompts. It reads its rules from `autoMode` in USER or MANAGED settings only
# (never from .claude/settings.json — a repo could otherwise ship its own allow rules), so this policy is
# the one part of the kit that lives outside the project. That is why it is installed explicitly and
# verified here rather than assumed.
#
# The failure this guards against is silent: setting an autoMode array WITHOUT the literal "$defaults"
# replaces the built-in list for that section — 66 soft-block rules and the single built-in hard block
# disappear with no error, and the session looks healthy. So this script does not read the policy file;
# it reads what the classifier ACTUALLY uses (`claude auto-mode config`) and checks the built-ins are
# still there. A policy file that parses is not a policy that applies.
#
# Side effect, measured — this script writes nothing itself, but `claude auto-mode config` does: reading the
# effective config makes Claude Code rewrite its own settings.json (reformatted, values normalised such as
# `opus` -> `opus[1m]`, a backups/ directory created). That is Claude Code maintaining its own file, and it
# keeps a backup, but "verifying costs nothing" would be a false claim.
#
# What it still catches, and why it is worth running: setting an autoMode array without the literal "$defaults"
# silently replaces the built-in list for that section (measured: soft_deny 66 -> 2, no error, no warning). That
# footgun is real whatever the enforcement story is, and nothing else in the toolchain reports it.
#
# Usage:  check.sh [--settings <file>]     # --settings inspects a CANDIDATE policy without installing it
# Exit:   0 config as expected · 2 built-ins DROPPED · 3 kit rules absent/partial · 4 cannot read the config
set -u

SETTINGS=""
[ "${1:-}" = "--settings" ] && { SETTINGS="${2:-}"; [ -z "$SETTINGS" ] && { echo "check.sh: --settings needs a file"; exit 4; }; }

command -v claude >/dev/null 2>&1 || { echo "  ⚠️  claude CLI not on PATH — auto-mode policy cannot be verified"; exit 4; }

if [ -n "$SETTINGS" ]; then CFG="$(claude --settings "$SETTINGS" auto-mode config 2>/dev/null)"
else                        CFG="$(claude auto-mode config 2>/dev/null)"; fi

# `auto-mode` is v2.1.19x+; an older CLI prints usage/error instead of the four rule lists.
case "$CFG" in *'"soft_deny"'*) : ;; *)
  echo "  ⚠️  'claude auto-mode config' did not return a rule set — CLI too old, or auto mode unavailable on this account"
  exit 4 ;;
esac

# Built-ins, checked PER SECTION and anchored to the rule's label.
#
# A whole-blob substring search is NOT enough and this was measured, not assumed: "Data Exfiltration" and
# "Auto-Mode Bypass" also occur inside the prose of `allow` rules, so a config with those built-ins dropped
# still contains both strings somewhere. That check reports a false PASS — the worst kind for a policy gate.
# `claude auto-mode config` prints one rule per line inside `"<section>": [ ... ]`, and every rule begins
# with its label, so slice the section first and anchor the match to the start of the string.
section(){ printf '%s\n' "$CFG" | awk -v s="$1" '
  $0 ~ "^[[:space:]]*\""s"\"[[:space:]]*:[[:space:]]*\\[" { inb=1; next }
  inb && /^[[:space:]]*\]/ { inb=0 }
  inb { print }'; }

has_rule(){ printf '%s\n' "$2" | grep -q "^[[:space:]]*\"$1"; }

HD="$(section hard_deny)"; SD="$(section soft_deny)"
MISSING=""
has_rule 'Data Exfiltration' "$HD" || MISSING="$MISSING hard_deny/Data-Exfiltration"
has_rule 'Git Destructive'   "$SD" || MISSING="$MISSING soft_deny/Git-Destructive"
has_rule 'Auto-Mode Bypass'  "$SD" || MISSING="$MISSING soft_deny/Auto-Mode-Bypass"

CSK=0
has_rule 'CSK Uncommitted Work Destruction' "$HD" && CSK=$((CSK+1))
has_rule 'CSK Gate Tampering'               "$SD" && CSK=$((CSK+1))
has_rule 'CSK Internal Docs Publication'    "$SD" && CSK=$((CSK+1))

if [ -n "$MISSING" ]; then
  echo "  ❌ classifier built-ins DROPPED:$MISSING"
  echo "     ↳ an autoMode array was set without the literal \"\$defaults\" — restore it in ~/.claude/settings.json"
  echo "     ↳ inspect with: claude auto-mode config    · built-ins: claude auto-mode defaults"
  exit 2
fi

if [ "$CSK" -eq 0 ]; then
  echo "  ·  kit auto-mode rules not in the classifier config (built-ins only) — not a gate either way"
  echo "     ↳ optional: bash .claude/skills/automode-policy/scripts/apply.sh"
  exit 3
fi

if [ "$CSK" -lt 3 ]; then
  echo "  ·  kit auto-mode rules PARTIAL ($CSK/3 present) — built-ins intact"
  echo "     ↳ re-apply: bash .claude/skills/automode-policy/scripts/apply.sh"
  exit 3
fi

echo "  ✅ classifier config: built-ins intact, 3/3 kit rules present (CONFIGURED, not proven to enforce)"
exit 0
