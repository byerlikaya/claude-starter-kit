#!/usr/bin/env bash
# Davranissal eval: golden prompt -> beklenen hedefe trigger ile yonleniyor mu (deterministik).
# Claude Code CALISTIRMAZ; trigger tasariminin routing dogrulugunu statik proxy'ler:
#   1) Golden routing  — her ornek prompt, beklenen hedefin bir trigger'ini (substring) icermeli.
#   2) Ajan cakismasi  — iki FARKLI ajan ayni trigger phrase'ini paylasmamali (routing belirsizligi).
# Turkce diyakritik iki tarafta da normalize edilir (guvenlik == güvenlik); diyakritiksiz yazan
# kullaniciya da dayaniklidir. Budanmis kurulumda kurulu-olmayan hedefin satiri ATLANIR.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
AGENTS="$ROOT/agents"; SKILLS="$ROOT/skills"
GOLD="$HERE/golden-routing.txt"
FAIL=0; SKIP=0
pass(){ echo "  ✅ $1"; }
fail(){ echo "  ❌ $1"; FAIL=$((FAIL+1)); }
skip(){ echo "  ⏭  $1"; SKIP=$((SKIP+1)); }

norm() {  # Turkce diyakritik -> ascii, sonra kucult
  printf '%s' "$1" | sed \
    -e 's/Ç/c/g' -e 's/ç/c/g' -e 's/Ğ/g/g' -e 's/ğ/g/g' -e 's/İ/i/g' -e 's/ı/i/g' \
    -e 's/Ö/o/g' -e 's/ö/o/g' -e 's/Ş/s/g' -e 's/ş/s/g' -e 's/Ü/u/g' -e 's/ü/u/g' \
    | tr '[:upper:]' '[:lower:]'
}

triggers_of() {  # $1 = hedef adi; trigger phrase'lerini satir satir yazar (yoksa exit 1)
  local n="$1" f=""
  if   [ -f "$AGENTS/$n.md" ];      then f="$AGENTS/$n.md"
  elif [ -f "$SKILLS/$n/SKILL.md" ]; then f="$SKILLS/$n/SKILL.md"
  else return 1; fi
  grep -i "Trigger phrases:" "$f" | head -1 | grep -oE '"[^"]+"' | sed 's/"//g'
}

echo "== 1) Golden routing (prompt -> beklenen hedef) =="
[ -f "$GOLD" ] || { fail "golden-routing.txt yok"; }
while IFS='|' read -r prompt expected; do
  case "$prompt" in ''|\#*) continue ;; esac
  expected="$(printf '%s' "$expected" | tr -d '[:space:]')"
  [ -n "$expected" ] || continue
  trs="$(triggers_of "$expected")" || { skip "\"$prompt\" -> $expected (hedef bu profilde yok)"; continue; }
  np="$(norm "$prompt")"
  hit=0
  while IFS= read -r ph; do
    [ -n "$ph" ] || continue
    nph="$(norm "$ph")"
    case "$np" in *"$nph"*) hit=1; break ;; esac
  done <<EOF
$trs
EOF
  if [ "$hit" = 1 ]; then pass "\"$prompt\" -> $expected"
  else fail "\"$prompt\" -> $expected (hicbir trigger eslesmedi — routing boslugu)"; fi
done < "$GOLD"

echo "== 2) Ajan-ajan trigger cakismasi =="
# NOT: Yalniz AJAN-AJAN cakismasina bakilir (routing belirsizligi buradadir). Ajan ile KENDI
# sahiplendigi skill'in trigger paylasmasi (backend-expert-cck<->devarch-module, security-expert-cck<->
# security-scan, devops-expert-cck<->incident-runbook ...) BEKLENENDIR: skill, ajanin ic "nasil"
# kaynagidir, ayri bir dispatch degil — router ajani secer, ajan skill'i tek subagent icinde okur.
# Bu yuzden ajan<->kendi-skill'i ortusmesi kasitlidir ve burada FAIL degildir.
# Her ajanin benzersiz (normalize) trigger'larini topla; iki+ ajanda gecen = cakisma.
dupe="$(
  for f in "$AGENTS"/*.md; do
    grep -i "Trigger phrases:" "$f" | head -1 | grep -oE '"[^"]+"' | sed 's/"//g' | while IFS= read -r p; do
      [ -n "$p" ] && norm "$p"
    done | sort -u
  done | sort | uniq -d
)"
if [ -n "$dupe" ]; then
  while IFS= read -r d; do [ -n "$d" ] && fail "ayni trigger birden cok ajanda: \"$d\""; done <<EOF
$dupe
EOF
else
  pass "ajan trigger'lari benzersiz (cakisma yok)"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "ROUTING-EVAL: GEÇTI ✅  (atlanan: $SKIP)"; exit 0
else echo "ROUTING-EVAL: $FAIL hata ❌  (atlanan: $SKIP)"; exit 1; fi
