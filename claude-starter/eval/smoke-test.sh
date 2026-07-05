#!/usr/bin/env bash
# Kit smoke-test: yapisal dogrulama (Claude Code calistirmadan).
# Kullanim: bash .claude/eval/smoke-test.sh   (repo kokunden veya .claude/eval icinden)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"       # .claude/
AGENTS="$ROOT/agents"; SKILLS="$ROOT/skills"; HOOKS="$ROOT/hooks"
FAIL=0
pass(){ echo "  ✅ $1"; }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }

echo "== 1) Ajan frontmatter & trigger =="
AC=0
for f in "$AGENTS"/*.md; do
  AC=$((AC+1)); n=$(basename "$f")
  grep -q '^name:' "$f"        || fail "$n: name yok"
  grep -q '^tools:' "$f"       || fail "$n: tools yok"
  grep -qE '^model:' "$f" || true   # model yoksa inherit (gecerli)
  grep -q 'Trigger phrases:' "$f" || fail "$n: Trigger phrases yok"
done
# Core ajanlar profil ne olursa olsun bulunmali; stack-ozel ajanlar (backend/database/
# frontend-expert) kurulum profiline gore degisir, o yuzden sabit sayi beklenmez.
for c in planner security-expert privacy-agent test-expert review-agent commit-agent session-manager; do
  [ -f "$AGENTS/$c.md" ] || fail "core ajan eksik: $c"
done
[ "$AC" -ge 7 ] && pass "$AC ajan bulundu (core 7 tam)" || fail "ajan sayisi 7 core'un altinda: $AC"

echo "== 2) Skill frontmatter & trigger =="
for d in "$SKILLS"/*/; do
  n=$(basename "$d"); f="$d/SKILL.md"
  [ -f "$f" ] || { fail "$n: SKILL.md yok"; continue; }
  grep -q '^name:' "$f"           || fail "$n: name yok"
  grep -q 'Trigger phrases:' "$f" || fail "$n: Trigger phrases yok"
done
pass "$(ls -d "$SKILLS"/*/ | wc -l | tr -d ' ') skill tarandi"

echo "== 3) Sahipsiz skill referansi (agent -> var olmayan skill) =="
# (a) Agent govdesinde "X skill'ini izle" gecen X'ler mevcut mu?
for f in "$AGENTS"/*.md; do
  for ref in $(grep -oE "[a-z0-9-]+ skill'ini izle" "$f" | awk '{print $1}'); do
    [ -f "$SKILLS/$ref/SKILL.md" ] || fail "$(basename $f): '$ref' skill'i yok"
  done
done
# (b) "Ayrica uygula: `x` · `y` ..." satirlarindaki backtickli skill adlari da mevcut mu?
for f in "$AGENTS"/*.md; do
  al="$(grep -F 'Ayrıca uygula' "$f" || true)"
  for ref in $(printf '%s' "$al" | grep -oE '`[a-z0-9-]+`' | tr -d '`'); do
    [ -f "$SKILLS/$ref/SKILL.md" ] || fail "$(basename $f): 'Ayrıca uygula' skill'i yok: $ref"
  done
done
pass "agent->skill referanslari (izle + Ayrıca uygula) kontrol edildi"

echo "== 4) Stub / doldurulmamis skill kalinti =="
if grep -rlq "doldurulacak\|kaynaktan üretilir/uyarlanır" "$SKILLS" 2>/dev/null; then
  fail "hala stub ibaresi var"; else pass "stub yok"
fi

echo "== 5) Iz-denetcisi (trace) hazir mi =="
[ -x "$HOOKS/pre-commit" ] && pass "pre-commit hook +x" || fail "pre-commit yok/executable degil"
[ -f "$HOOKS/trace-blocklist.txt" ] && pass "blocklist var" || fail "trace-blocklist.txt yok"


echo "== 6) Context-usage esik mantigi (fixture) + hook butunlugu =="
FX="$(mktemp)"
printf '%s\n' '{"isSidechain":false,"message":{"usage":{"input_tokens":1000,"cache_read_input_tokens":800000,"cache_creation_input_tokens":0}}}' > "$FX"
o1="$(CONTEXT_WINDOW=1000000 bash "$HOOKS/context-usage.sh" "$FX" 2>/dev/null)"
case "$o1" in *"handoff+clear"*) pass "esik: ~%80 → handoff+clear" ;; *) fail "esik(yuksek) 'handoff+clear' degil: $o1" ;; esac
o2="$(CONTEXT_WINDOW=2000000 bash "$HOOKS/context-usage.sh" "$FX" 2>/dev/null)"
case "$o2" in *"devam"*) pass "esik: CONTEXT_WINDOW=2M → devam" ;; *) fail "esik(pencere) 'devam' degil: $o2" ;; esac
if bash "$HOOKS/context-usage.sh" "/yok/olmayan.jsonl" >/dev/null 2>&1; then fail "hatali transcript exit 0 dondu"; else pass "hatali transcript exit!=0"; fi
rm -f "$FX"
[ -x "$HOOKS/commit-msg" ]       && pass "commit-msg hook +x"           || fail "commit-msg yok/executable degil"
[ -x "$HOOKS/context-usage.sh" ] && pass "context-usage.sh +x"          || fail "context-usage.sh yok/executable degil"
[ -x "$HOOKS/session-guard.sh" ] && pass "session-guard.sh +x (Stop)"   || fail "session-guard.sh yok/executable degil"

echo "== 7) settings.json & guard (§4.4/§4.5) =="
if [ -f "$ROOT/settings.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq empty "$ROOT/settings.json" 2>/dev/null && pass "settings.json geçerli JSON" || fail "settings.json bozuk JSON"
  else pass "settings.json var (jq yok, JSON doğrulaması atlandı)"; fi
else fail "settings.json yok"; fi
[ -x "$HOOKS/guard-bash.sh" ] && pass "guard-bash.sh +x" || fail "guard-bash.sh yok/executable degil"
# §4.4 git onay kapisi (davranissal): anahtarsiz commit/push BLOK, CLAUDE_GIT_OK=1 ile GEC, destruktif hep BLOK
GJC='{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}'
printf '%s' "$GJC" | bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "git commit anahtarsiz GECTI (§4.4 kapi yok)" || pass "git commit anahtarsiz BLOK (§4.4)"
printf '%s' "$GJC" | CLAUDE_GIT_OK=1 bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && pass "git commit CLAUDE_GIT_OK=1 ile GEC" || fail "anahtarli commit bloklandi (kapi fazla siki)"
printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' | CLAUDE_GIT_OK=1 bash "$HOOKS/guard-bash.sh" >/dev/null 2>&1 && fail "push --force anahtarla GECTI (§4.5 delik)" || pass "push --force anahtarla bile BLOK (§4.5)"

echo "== 8) Slash komutları =="
for c in simplify plan review ship handoff; do
  [ -f "$ROOT/commands/$c.md" ] && pass "/$c var" || fail "/$c komutu yok"
done

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "SMOKE-TEST: GEÇTI ✅"; exit 0
else echo "SMOKE-TEST: $FAIL hata ❌"; exit 1; fi
