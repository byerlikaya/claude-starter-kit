#!/usr/bin/env bash
# Kit smoke-test: structural validation (without running Claude Code).
# Usage: bash .claude/eval/smoke-test.sh   (from the repo root or from inside .claude/eval)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"       # .claude/
AGENTS="$ROOT/agents"; SKILLS="$ROOT/skills"; HOOKS="$ROOT/hooks"
FAIL=0
pass(){ echo "  ✅ $1"; }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "== 1) Agent frontmatter & trigger =="
AC=0
for f in "$AGENTS"/*.md; do
  AC=$((AC+1)); n=$(basename "$f")
  grep -q '^name:' "$f"        || fail "$n: no name"
  grep -q '^tools:' "$f"       || fail "$n: no tools"
  grep -qE '^model:' "$f" || true   # no model means inherit (valid)
  grep -q 'Trigger phrases:' "$f" || fail "$n: no Trigger phrases"
done
# Core agents must be present regardless of profile; stack-specific agents (backend/database/
# frontend-expert-csk) vary by install profile, so no fixed count is expected.
for c in planner-csk security-expert-csk privacy-agent-csk test-expert-csk review-agent-csk commit-agent-csk session-manager-csk; do
  [ -f "$AGENTS/$c.md" ] || fail "missing core agent: $c"
done
[ "$AC" -ge 7 ] && pass "$AC agents found (7 core complete)" || fail "agent count below the 7 core: $AC"

echo "== 2) Skill frontmatter & trigger =="
for d in "$SKILLS"/*/; do
  n=$(basename "$d"); f="$d/SKILL.md"
  [ -f "$f" ] || { fail "$n: no SKILL.md"; continue; }
  grep -q '^name:' "$f"           || fail "$n: no name"
  grep -q 'Trigger phrases:' "$f" || fail "$n: no Trigger phrases"
done
pass "$(ls -d "$SKILLS"/*/ | wc -l | tr -d ' ') skills scanned"

echo "== 3) Orphan skill reference (agent -> nonexistent skill) =="
# (a) Do the X's in "applies the \`X\` skill" in an agent body exist?
for f in "$AGENTS"/*.md; do
  for ref in $(grep -oE 'applies the `[a-z0-9-]+` skill' "$f" | grep -oE '`[a-z0-9-]+`' | tr -d '`'); do
    [ -f "$SKILLS/$ref/SKILL.md" ] || fail "$(basename $f): skill '$ref' does not exist"
  done
done
# (b) Do the backticked skill names on "Also apply: \`x\` · \`y\` ..." lines also exist?
for f in "$AGENTS"/*.md; do
  al="$(grep -F 'Also apply' "$f" || true)"
  for ref in $(printf '%s' "$al" | grep -oE '`[a-z0-9-]+`' | tr -d '`'); do
    [ -f "$SKILLS/$ref/SKILL.md" ] || fail "$(basename $f): 'Also apply' skill does not exist: $ref"
  done
done
pass "agent->skill references (applies + Also apply) checked"

echo "== 4) Stub / unfilled skill leftover =="
if grep -rlq "to be filled\|generated from source" "$SKILLS" 2>/dev/null; then
  fail "stub marker still present"; else pass "no stub"
fi

echo "== 5) Trace scanner ready? =="
[ -x "$HOOKS/pre-commit" ] && pass "pre-commit hook +x" || fail "pre-commit missing/not executable"
[ -f "$HOOKS/trace-blocklist.txt" ] && pass "blocklist present" || fail "trace-blocklist.txt missing"


echo "== 6) Context-usage threshold logic (fixture) + hook integrity =="
FX="$(mktemp)"
printf '%s\n' '{"isSidechain":false,"message":{"usage":{"input_tokens":1000,"cache_read_input_tokens":800000,"cache_creation_input_tokens":0}}}' > "$FX"
o1="$(CONTEXT_WINDOW=1000000 bash "$HOOKS/context-usage.sh" "$FX" 2>/dev/null)"
case "$o1" in *"handoff+clear"*) pass "threshold: ~80% → handoff+clear" ;; *) fail "threshold(high) not 'handoff+clear': $o1" ;; esac
o2="$(CONTEXT_WINDOW=2000000 bash "$HOOKS/context-usage.sh" "$FX" 2>/dev/null)"
case "$o2" in *"continue"*) pass "threshold: CONTEXT_WINDOW=2M → continue" ;; *) fail "threshold(window) not 'continue': $o2" ;; esac
if bash "$HOOKS/context-usage.sh" "/no/such.jsonl" >/dev/null 2>&1; then fail "malformed transcript returned exit 0"; else pass "malformed transcript exit!=0"; fi
rm -f "$FX"
[ -x "$HOOKS/commit-msg" ]       && pass "commit-msg hook +x"           || fail "commit-msg missing/not executable"
[ -x "$HOOKS/context-usage.sh" ] && pass "context-usage.sh +x"          || fail "context-usage.sh missing/not executable"
[ -x "$HOOKS/session-guard.sh" ] && pass "session-guard.sh +x (Stop)"   || fail "session-guard.sh missing/not executable"

echo "== 7) settings.json & guard (§4.4/§4.5) =="
if [ -f "$ROOT/settings.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq empty "$ROOT/settings.json" 2>/dev/null && pass "settings.json valid JSON" || fail "settings.json invalid JSON"
  else pass "settings.json present (no jq, JSON validation skipped)"; fi
else fail "settings.json missing"; fi
[ -x "$HOOKS/guard-bash.sh" ] && pass "guard-bash.sh +x" || fail "guard-bash.sh missing/not executable"
# §4.4 git approval gate (behavioral): keyless commit/push BLOCKED, PASSES with CLAUDE_GIT_OK=1, destructive always BLOCKED
GJC='{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
printf '%s' "$GJC" | bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "keyless git commit PASSED (§4.4 gate missing)" || pass "keyless git commit BLOCKED (§4.4)"
printf '%s' "$GJC" | CLAUDE_GIT_OK=1 bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && pass "git commit PASSES with CLAUDE_GIT_OK=1" || fail "keyed commit blocked (gate too strict)"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | CLAUDE_GIT_OK=1 bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "push --force PASSED with key (§4.5 hole)" || pass "push --force BLOCKED even with key (§4.5)"

echo "== 8) Slash commands =="
for c in simplify plan review ship handoff; do
  [ -f "$ROOT/commands/$c.md" ] && pass "/$c present" || fail "/$c command missing"
done

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "SMOKE-TEST: PASSED ✅"; exit 0
else echo "SMOKE-TEST: $FAIL errors ❌"; exit 1; fi
