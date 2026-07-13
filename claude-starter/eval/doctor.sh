#!/usr/bin/env bash
# Install doctor — verify a LIVE kit install in a CONSUMER repo is actually active. This is the counterpart to
# smoke-test.sh: smoke-test checks the kit's SOURCE (dev-side, in this repo); doctor checks a real install on a
# user's machine — the things that silently make the gates inert: a hook left non-executable, core.hooksPath not
# set (so the commit trace/secret scan never runs), settings.json missing (so the tool-level gates never fire).
# Zero-dep, bash-only, Git-Bash safe. Run from the project root (or pass the path):  bash .claude/eval/doctor.sh
set -uo pipefail
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "doctor: cannot enter '$ROOT'"; exit 2; }

FAIL=0
ok(){  echo "  ✅ $1"; }
bad(){ echo "  ❌ $1"; echo "     ↳ fix: $2"; FAIL=$((FAIL+1)); }
warn(){ echo "  ⚠️  $1"; }

echo "== Claude Starter Kit — install doctor =="

# 0) Is the kit even here?
[ -d .claude ] || { echo "  ❌ no .claude/ in '$PWD' — is the kit installed here?"; echo "     ↳ fix: npx @byerlikaya/claude-starter-kit adopt"; exit 1; }

# 1) VERSION (marks a full install; also what /update-csk compares)
if [ -f .claude/VERSION ]; then ok "VERSION present ($(head -1 .claude/VERSION | tr -cd '0-9A-Za-z.-'))"
else bad "VERSION missing" "reinstall or update the kit (npx @byerlikaya/claude-starter-kit update)"; fi

# 2) Hooks executable — a non-executable hook is silently skipped by Claude Code / git
NX=""
for h in .claude/hooks/*.sh .claude/hooks/pre-commit .claude/hooks/commit-msg; do
  [ -e "$h" ] || continue                       # unmatched glob / absent optional hook
  [ -x "$h" ] || NX="$NX $(basename "$h")"
done
[ -z "$NX" ] && ok "all shipped hooks are executable" \
             || bad "not executable:$NX" "chmod +x .claude/hooks/*.sh .claude/hooks/pre-commit .claude/hooks/commit-msg"

# 3) core.hooksPath — without it the §4.1/§4.2 commit trace + secret/bloat scan never runs
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HP="$(git config --get core.hooksPath 2>/dev/null || true)"
  case "$HP" in
    */.claude/hooks|.claude/hooks) ok "core.hooksPath -> $HP (commit-time gates active)" ;;
    "") bad "core.hooksPath is unset — commit trace/secret/bloat gates are INACTIVE" "git config core.hooksPath .claude/hooks" ;;
    *)  bad "core.hooksPath -> $HP (not the kit's hooks)" "git config core.hooksPath .claude/hooks" ;;
  esac
else
  warn "not a git repo — commit gates need: git init && git config core.hooksPath .claude/hooks"
fi

# 4) settings.json wires the tool-level gates (PreToolUse / UserPromptSubmit / Stop)
S=.claude/settings.json
if [ -f "$S" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq empty "$S" 2>/dev/null && ok "settings.json is valid JSON" || bad "settings.json is invalid JSON" "restore settings.json from the kit"
  fi
  MISS=""
  for ev in PreToolUse UserPromptSubmit Stop; do grep -q "\"$ev\"" "$S" || MISS="$MISS $ev"; done
  [ -z "$MISS" ] && ok "settings.json wires PreToolUse / UserPromptSubmit / Stop" \
                 || bad "settings.json is missing hook events:$MISS — those gates won't fire" "restore settings.json from the kit"
else
  bad "settings.json missing — the tool-level gates (commit approval, guards, context) are INACTIVE" "reinstall the kit"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "DOCTOR: healthy ✅"; exit 0
else echo "DOCTOR: $FAIL issue(s) ❌ — apply the fixes above"; exit 1; fi
