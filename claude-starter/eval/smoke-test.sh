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
# Agent govdesinde "X skill'ini izle" gecen X'ler mevcut mu?
for f in "$AGENTS"/*.md; do
  for ref in $(grep -oE "[a-z0-9-]+ skill'ini izle" "$f" | awk '{print $1}'); do
    [ -f "$SKILLS/$ref/SKILL.md" ] || fail "$(basename $f): '$ref' skill'i yok"
  done
done
pass "agent->skill referanslari kontrol edildi"

echo "== 4) Stub / doldurulmamis skill kalinti =="
if grep -rlq "doldurulacak\|kaynaktan üretilir/uyarlanır" "$SKILLS" 2>/dev/null; then
  fail "hala stub ibaresi var"; else pass "stub yok"
fi

echo "== 5) Iz-denetcisi (trace) hazir mi =="
[ -x "$HOOKS/pre-commit" ] && pass "pre-commit hook +x" || fail "pre-commit yok/executable degil"
[ -f "$HOOKS/trace-blocklist.txt" ] && pass "blocklist var" || fail "trace-blocklist.txt yok"


echo "== 7) settings.json & guard (§4.4/§4.5) =="
if [ -f "$ROOT/settings.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq empty "$ROOT/settings.json" 2>/dev/null && pass "settings.json geçerli JSON" || fail "settings.json bozuk JSON"
  else pass "settings.json var (jq yok, JSON doğrulaması atlandı)"; fi
else fail "settings.json yok"; fi
[ -x "$HOOKS/guard-bash.sh" ] && pass "guard-bash.sh +x" || fail "guard-bash.sh yok/executable degil"

echo "== 8) Slash komutları =="
for c in simplify plan review ship handoff; do
  [ -f "$ROOT/commands/$c.md" ] && pass "/$c var" || fail "/$c komutu yok"
done

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "SMOKE-TEST: GEÇTI ✅"; exit 0
else echo "SMOKE-TEST: $FAIL hata ❌"; exit 1; fi
