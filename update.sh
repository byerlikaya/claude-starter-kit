#!/usr/bin/env bash
# kit adopt (calisma adi: update.sh) — kiti MEVCUT bir projeye DEVREDER (handover), brownfield-guvenli.
# Ileride `kit adopt` alt-komutu olur. Devir felsefesi: proje bozulmasin · alinan kararlar kaybolmasin ·
# kit pasif kalmasin (%100 hybrid). Kit ajanlari -cck ile namespace'li -> proje ajanlariyla catismaz.
#
# >>> ASAMA 1: yalniz TESPIT + AKILLI ONERI. HICBIR SEYI DEGISTIRMEZ (read-only). <<<
# Sonraki asamalar: git-dal ac -> mutasyon (settings merge · DISCIPLINE.md · coexist) -> kurulum-kaniti
# -> HANDOVER.md / ADR. Her karara burada uretilen ONERI, sonraki asamada gozden-gecir/ez-gec ile uygulanir.
#
# Kullanim: hedef proje kokunde (claude-starter/ ile ayni dizinde):  bash update.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/claude-starter"
[ -d "$SRC" ] || { echo "HATA: claude-starter/ bulunamadi (update.sh ile ayni dizinde olmali)."; exit 1; }

# --- renk: yalniz interaktif TTY'de (start.sh ile ayni guard) ---
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'; CY=$'\033[36m'; GR=$'\033[32m'; YE=$'\033[33m'; MG=$'\033[35m'
else R=''; B=''; D=''; CY=''; GR=''; YE=''; MG=''; fi
h1()  { printf '\n%s%s%s%s\n' "$B" "$CY" "$1" "$R"; }
sub() { printf '%s%s%s\n' "$D" "$1" "$R"; }
row() { printf '  %s%-20s%s %s\n' "$B" "$1" "$R" "$2"; }
warn(){ printf '  %s!%s %s%s%s\n' "$YE" "$R" "$YE" "$1" "$R"; }
# akilli oneri satiri:  numara+karar · ONERILEN(yesil) · gerekce(dim)
prop(){ printf '  %s%-18s%s %s%-24s%s %s%s%s\n' "$B" "$1" "$R" "$GR" "$2" "$R" "$D" "$3" "$R"; }
ask_yes(){ local a; printf '%s [evet/hayir]: ' "$1"; read -r a || a=""; case "$a" in [eE][vV][eE][tT]|[eE]|[yY]) return 0;; *) return 1;; esac; }
# never-overwrite kopya: VAR OLAN hedef dosyayi EZMEZ (proje dosyasi korunur), atlar+sayar.
# Sonuc global: ret_add / ret_skip; cakisanlar SKIP_LIST'e eklenir. Subshell'de CAGIRMA (global kaybolur).
SKIP_LIST=""
copy_noclobber(){ local src="$1" dst="$2" rel f; ret_add=0; ret_skip=0; [ -d "$src" ] || return; mkdir -p "$dst"
  while IFS= read -r f; do rel="${f#"$src"/}"
    if [ -e "$dst/$rel" ]; then ret_skip=$((ret_skip+1)); SKIP_LIST="$SKIP_LIST $dst/$rel"
    else mkdir -p "$dst/$(dirname "$rel")"; cp "$f" "$dst/$rel"; ret_add=$((ret_add+1)); fi
  done < <(find "$src" -type f 2>/dev/null); }

h1 "kit adopt · Asama 1 — TESPIT (read-only; hicbir sey degismez)"
sub "Mevcut projeyi okur, 7 devir kararina akilli oneri uretir. Onay + mutasyon sonraki asamada."

# ========================= [1] ORTAM =========================
h1 "[1] Ortam"
# git baglami — worktree/submodule'da .git bir DOSYADIR ([ -d .git ] KULLANMA; red-team hole #6)
IS_GIT=0; GITTOP=""; GITKIND="git yok — 'git init' gerekli"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IS_GIT=1; GITTOP="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
  if [ -f "$GITTOP/.git" ]; then GITKIND="worktree/submodule (.git dosya)"; else GITKIND="normal repo"; fi
fi
row "git" "$GITKIND"

# mevcut hook sistemi (karar #5 — husky/lefthook ile tek-hooksPath catismasi)
HOOKSYS="yok"
CURHP="$(git config --get core.hooksPath 2>/dev/null || true)"
[ -n "$CURHP" ] && HOOKSYS="core.hooksPath=$CURHP"
[ -d .husky ] && HOOKSYS="husky (.husky/)"
{ [ -f lefthook.yml ] || [ -f .lefthook.yml ]; } && HOOKSYS="lefthook"
[ -f .pre-commit-config.yaml ] && HOOKSYS="pre-commit framework"
row "git hook sistemi" "$HOOKSYS"

# stack ipucu (baglam)
STACK="bilinmiyor"
if ls ./*.sln ./*.csproj >/dev/null 2>&1; then STACK=".NET"
elif [ -f package.json ]; then STACK="Node/JS"
elif [ -f go.mod ]; then STACK="Go"
elif [ -f pyproject.toml ] || [ -f requirements.txt ]; then STACK="Python"; fi
row "stack ipucu" "$STACK"

# ================= [2] MEVCUT AGENTIK KURULUM =================
h1 "[2] Mevcut agentik kurulum (devralinacak birikim)"
HAS_CLAUDE=0; [ -d .claude ] && HAS_CLAUDE=1
N_PAGENTS=0; [ -d .claude/agents ] && N_PAGENTS="$(find .claude/agents -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
N_PSKILLS=0; [ -d .claude/skills ] && N_PSKILLS="$(find .claude/skills -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"
HAS_MD=0; [ -f CLAUDE.md ] && HAS_MD=1
HAS_SETTINGS=0; [ -f .claude/settings.json ] && HAS_SETTINGS=1
row ".claude/" "$([ "$HAS_CLAUDE" = 1 ] && echo "var — $N_PAGENTS ozel ajan · $N_PSKILLS skill" || echo "yok")"
row "CLAUDE.md" "$([ "$HAS_MD" = 1 ] && echo "var" || echo "yok")"
row "settings.json" "$([ "$HAS_SETTINGS" = 1 ] && echo "var" || echo "yok")"

# git'te izleniyor mu? (karar #4 — paylas/gizle)
TRACKED=0
if [ "$IS_GIT" = 1 ]; then
  git ls-files --error-unmatch CLAUDE.md >/dev/null 2>&1 && TRACKED=1
  { [ "$HAS_CLAUDE" = 1 ] && [ -n "$(git ls-files .claude 2>/dev/null | head -1)" ]; } && TRACKED=1
fi
row ".claude/CLAUDE.md git'te" "$([ "$TRACKED" = 1 ] && echo "EVET — ekiple paylasiliyor" || echo "hayir/izlenmiyor")"

# co-author/sign-off konvansiyonu (karar #3)
COAUTHOR=0
[ "$IS_GIT" = 1 ] && git log -80 --format='%b' 2>/dev/null | grep -qiE 'Co-Authored[-]By|Signed-off-by' && COAUTHOR=1  # [-] : kaynakta bitisik literal olmasin (iz-hook)

# off-repo ipucu (karar #7 — kararlar sohbette/web'de olabilir)
OFFREPO=0; { [ "$HAS_CLAUDE" = 0 ] && [ "$HAS_MD" = 0 ]; } && OFFREPO=1

# ===================== [3] AKILLI ONERI ======================
h1 "[3] 7 devir karari — AKILLI ONERI"
sub "format:  karar  ->  ONERILEN  ->  gerekce   (sonraki asamada hepsini gozden gecirip ez-gecebilirsin)"
if [ "$N_PAGENTS" != 0 ]; then
  prop "1 Rol cakismasi" "koru (coexist)" "$N_PAGENTS proje ajani; -cck sayesinde catisma yok, yan yana yasar"
else
  prop "1 Rol cakismasi" "yok" "projede ozel ajan bulunmadi"
fi
prop "2 Precedence" "proje kazanir" "eksen-eksen; projenin dili/kalibi ustun, kit bosluk doldurur"
if [ "$COAUTHOR" = 1 ]; then
  prop "3 Iz-kapisi" "gevset (.trace-allowlist)" "git log'da co-author/sign-off var — sozlesme olabilir"
else
  prop "3 Iz-kapisi" "koru" "co-author/sign-off konvansiyonu gorulmedi"
fi
if [ "$TRACKED" = 1 ]; then
  prop "4 Paylas/gizle" "paylasimi koru" ".claude/CLAUDE.md izleniyor — gitignore'a EKLENMEZ"
else
  prop "4 Paylas/gizle" "kit varsayilani" "izlenmiyor; 'gizle' konvansiyonu uygulanabilir"
fi
if [ "$HOOKSYS" = "yok" ]; then
  prop "5 Git hook'lari" "dogrudan kur" "mevcut hook sistemi yok"
else
  prop "5 Git hook'lari" "SHIM (koprule)" "mevcut $HOOKSYS var — ikisi de calissin"
fi
prop "6 Brownfield DoD" "baseline+regresyon" "mevcut kod-borcu bilinmiyor; mutlak 0/0/0/0 riskli"
if [ "$OFFREPO" = 1 ]; then
  warn "7 Off-repo: yerel .claude/CLAUDE.md YOK — kararlar sohbette/web'de olabilir; GOREMEDIGIM baglam var."
  prop "  -> oneri" "sen aktar" "mutasyon asamasinda 'varsa yapistir' sorulur; HANDOVER.md'ye girer"
else
  prop "7 Off-repo" "yerel + sor" "kararlarin bir kismi dosyada; yine de sohbet-ici olabilir (asamada sorulur)"
fi

# ================= [ASAMA 2] DEVIR DALI + COEXIST =================
h1 "Asama 2 — devir dali + coexist"
sub "Kit'i AYRI bir git dalinda kurar; proje dosyalarina DOKUNMAZ (never-overwrite). Diff'i gozden gecir, git'le geri al."
if [ "$IS_GIT" != 1 ]; then
  warn "git deposu yok — devir dali acilamaz. Once:  git init && git add -A && git commit -m init  (sonra tekrar calistir)."
  exit 0
fi
if ! ask_yes "Devir dali acilip coexist uygulansin mi? (mutasyon; sonucu git ile geri alinabilir)"; then
  h1 "Durduruldu"; sub "Asama 1'de kaldi — HICBIR SEY DEGISMEDI (read-only)."; exit 0
fi

BASE="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
TS="$(date +%Y%m%d-%H%M%S)"; BR="kit-adopt-$TS"
git checkout -b "$BR" >/dev/null 2>&1 || { echo "HATA: '$BR' dali acilamadi."; exit 1; }
echo "  devir dali: ${B}$BR${R}  (${BASE} temiz kalir)"

mkdir -p .claude
copy_noclobber "$SRC/agents"   .claude/agents;   A_ADD=$ret_add; A_SKIP=$ret_skip
copy_noclobber "$SRC/skills"   .claude/skills;   S_ADD=$ret_add; S_SKIP=$ret_skip
copy_noclobber "$SRC/commands" .claude/commands; C_ADD=$ret_add; C_SKIP=$ret_skip
copy_noclobber "$SRC/hooks"    .claude/hooks;    H_ADD=$ret_add; H_SKIP=$ret_skip
copy_noclobber "$SRC/eval"     .claude/eval;     E_ADD=$ret_add; E_SKIP=$ret_skip
# stack-uyumlu backend: .NET disi projede jenerik backend-expert-cck (kit'in KENDI dosyasi, proje dosyasi degil)
if [ "$STACK" != ".NET" ] && [ -f "$SRC/agents-optional/backend-expert-generic.md" ]; then
  cp "$SRC/agents-optional/backend-expert-generic.md" .claude/agents/backend-expert-cck.md
  echo "  backend-expert-cck -> jenerik varyant ($STACK projesi)"
fi
chmod +x .claude/hooks/*.sh .claude/hooks/pre-commit .claude/hooks/commit-msg 2>/dev/null || true

h1 "Coexist ozeti"
row "kit ajanlari (-cck)" "+$A_ADD eklendi$([ "$A_SKIP" != 0 ] && echo " · $A_SKIP atlandi")"
row "skiller"            "+$S_ADD$([ "$S_SKIP" != 0 ] && echo " · $S_SKIP atlandi")"
row "komutlar"           "+$C_ADD$([ "$C_SKIP" != 0 ] && echo " · $C_SKIP atlandi")"
row "hook'lar"           "+$H_ADD$([ "$H_SKIP" != 0 ] && echo " · $H_SKIP atlandi")"
row "eval"               "+$E_ADD"
row "proje ajanlari"     "$N_PAGENTS — DOKUNULMADI (yerinde, recursive kesifle aktif)"
[ -n "$SKIP_LIST" ] && { warn "cakisan dosyalar (proje'ninki KORUNDU, kit'inki atlandi):"; for s in $SKIP_LIST; do printf '     %s- %s%s\n' "$D" "$s" "$R"; done; }

# ============ [ASAMA 3] DISIPLIN AKTIF + SETTINGS MERGE ============
h1 "Asama 3 — kit disiplinini aktif et (proje CLAUDE.md'sine dokunmadan) + settings merge"

# 3a) DISCIPLINE.md: payload CLAUDE.md'nin ust (disiplin) blogunu ayri, DUZ dosya olarak kur.
#     '<PROJE ADI>' satirindan oncesi = disiplin; icinde @import YOK (leaf) -> 4-hop tuzagi yok.
if [ -f "$SRC/CLAUDE.md" ]; then
  awk '/<PROJE ADI>/{exit} {print}' "$SRC/CLAUDE.md" > .claude/DISCIPLINE.md
  echo "  DISCIPLINE.md yazildi (kit disiplini; duz, self-contained)"
fi

# 3b) Proje CLAUDE.md'sine tek-satir @import (varsa icerige DOKUNMA, sadece basa; yoksa olustur).
IMPORT_LINE='@.claude/DISCIPLINE.md'
if [ -f CLAUDE.md ]; then
  if grep -qF "$IMPORT_LINE" CLAUDE.md; then echo "  CLAUDE.md: @import zaten var (idempotent)"
  else
    { printf '<!-- kit disiplini · celiskide ASAGIDAKI proje kurallari kazanir -->\n%s\n\n' "$IMPORT_LINE"; cat CLAUDE.md; } > CLAUDE.md.kit-tmp && mv CLAUDE.md.kit-tmp CLAUDE.md
    echo "  CLAUDE.md: basa tek-satir @import eklendi (proje icerigi el degmedi)"
  fi
else
  printf '%s\n\n# CLAUDE.md — <PROJE ADI>\n\n## Proje\n<Bir cumle: ne yapiyor, kime.>\n' "$IMPORT_LINE" > CLAUDE.md
  echo "  CLAUDE.md yoktu -> @import + proje sablonu olusturuldu"
fi

# 3c) settings.json SEMA-FARKINDA merge: proje ayari SILINMEZ; diziler concat+dedup; gecersiz JSON'da ABORT.
KSET="$SRC/settings.json"; PSET=".claude/settings.json"
JQ_MERGE='
def ddedup: reduce .[] as $x ([]; if any(.[]; .==$x) then . else .+[$x] end);
def dm(a;b): reduce (b|keys_unsorted[]) as $k (a;
  if (.[$k]|type)=="object" and (b[$k]|type)=="object" then .[$k]=dm(.[$k];b[$k])
  elif (.[$k]|type)=="array" and (b[$k]|type)=="array" then .[$k]=((.[$k]+b[$k])|ddedup)
  else .[$k]=b[$k] end);
dm($k[0]; $p[0])'   # base=kit, overlay=proje -> proje skalarlari kazanir, diziler birlesir
if [ ! -f "$PSET" ]; then
  [ -f "$KSET" ] && { cp "$KSET" "$PSET"; echo "  settings.json: proje'de yoktu -> kit'inki kuruldu"; }
elif ! command -v jq >/dev/null 2>&1; then
  warn "settings.json: jq yok -> guvenli merge yapilamaz. Proje ayari KORUNDU; kit kapilarini elle ekle."
elif ! jq -e . "$PSET" >/dev/null 2>&1; then
  warn "settings.json: mevcut dosya GECERSIZ JSON -> merge ABORT (sessiz ezme YOK). Once elle duzelt."
else
  MERGED="$(jq -n --slurpfile p "$PSET" --slurpfile k "$KSET" "$JQ_MERGE" 2>/dev/null || true)"
  if [ -n "$MERGED" ] && printf '%s' "$MERGED" | jq -e . >/dev/null 2>&1; then
    printf '%s\n' "$MERGED" > "$PSET"; echo "  settings.json: sema-farkinda MERGE (proje hook/permission KORUNDU + kit eklendi)"
  else
    warn "settings.json: merge basarisiz -> proje ayari KORUNDU (ezilmedi)."
  fi
fi

# ============ [ASAMA 4] GIT-HOOK SILAHLAMA (SHIM) + KANIT ============
h1 "Asama 4 — git kapilarini silahla (husky ile SHIM) + KANIT"

# 4a) mevcut hook zincirinin yeri (shim bunu da cagirir)
ORIG_HOOKS=""
if [ -n "$CURHP" ]; then ORIG_HOOKS="$CURHP"
elif [ -d .husky ]; then ORIG_HOOKS=".husky"
elif [ -x .git/hooks/pre-commit ] || [ -x .git/hooks/commit-msg ]; then ORIG_HOOKS=".git/hooks"; fi

if [ -z "$ORIG_HOOKS" ]; then
  git config core.hooksPath .claude/hooks
  echo "  core.hooksPath -> .claude/hooks (mevcut hook zinciri yok)"
else
  mkdir -p .claude/git-shim
  for hk in pre-commit commit-msg; do
    cat > ".claude/git-shim/$hk" <<SHIM
#!/usr/bin/env bash
# kit git-shim: kit hook + mevcut proje zincirini SIRAYLA calistirir (biri patlarsa git durur).
set -e
H="\$(basename "\$0")"
ROOT="\$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
K="\$ROOT/.claude/hooks/\$H"; [ -x "\$K" ] && "\$K" "\$@"
P="\$ROOT/$ORIG_HOOKS/\$H"
if   [ -x "\$P" ]; then "\$P" "\$@"
elif [ -f "\$P" ]; then bash "\$P" "\$@"; fi
exit 0
SHIM
    chmod +x ".claude/git-shim/$hk"
  done
  git config core.hooksPath .claude/git-shim
  echo "  SHIM kuruldu -> core.hooksPath=.claude/git-shim (kit + $ORIG_HOOKS birlikte calisir)"
fi
[ "$GITKIND" = "worktree/submodule (.git dosya)" ] && warn "worktree/submodule: core.hooksPath ana checkout'u da etkileyebilir (git tasarimi)."

# 4b) KANIT — kit gercekten calisiyor mu? (iddia degil)
h1 "Asama 4b — KANIT"
PROOF_OK=1; HP="$(git config --get core.hooksPath 2>/dev/null || echo .claude/hooks)"
# 1) iz-denetcisi git hook: staged AI-izi BLOKLANMALI (gercek commit YOK; hook'u dogrudan calistir)
printf 'Co-Authored%s: Test <x@y.z>\n' '-By' > .kit-proof.txt   # kaynakta bitisik degil (iz-hook kendini bloklamasin); runtime'da tam
git add .kit-proof.txt >/dev/null 2>&1
if bash "$HP/pre-commit" >/tmp/kitproof.$$ 2>&1; then
  warn "KANIT-1 BASARISIZ: iz-denetcisi AI-izini GECIRDI"; PROOF_OK=0
elif grep -qiE 'IZ-DENETCISI|yasakli|durduruldu' /tmp/kitproof.$$; then
  echo "  OK · KANIT-1: staged AI-izi iz-denetcisiyle BLOKLANDI"
else echo "  ~  KANIT-1: hook blokladi ($(head -1 /tmp/kitproof.$$ 2>/dev/null))"; fi
git reset -q .kit-proof.txt 2>/dev/null; rm -f .kit-proof.txt /tmp/kitproof.$$
# 2) guard-bash git-onay kapisi: anahtarsiz 'git commit' -> blok
if printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | bash .claude/hooks/guard-bash.sh >/dev/null 2>&1; then
  warn "KANIT-2 BASARISIZ: guard-bash anahtarsiz commit'i GECIRDI"; PROOF_OK=0
else echo "  OK · KANIT-2: guard-bash anahtarsiz 'git commit'i BLOKLADI (auto/bypass'ta da tutar)"; fi
# 3) kit ajanlari + disiplin yuklenebilir mi
NCCK="$(ls .claude/agents/*-cck.md 2>/dev/null | wc -l | tr -d ' ')"
if [ "${NCCK:-0}" -ge 1 ]; then echo "  OK · KANIT-3: $NCCK kit ajani (-cck) kurulu + kesfedilir"; else warn "KANIT-3: kit ajani yok"; PROOF_OK=0; fi
if [ -s .claude/DISCIPLINE.md ] && grep -qF '@.claude/DISCIPLINE.md' CLAUDE.md; then echo "  OK · KANIT-4: DISCIPLINE.md yuklu + CLAUDE.md'den @import ediliyor"; else warn "KANIT-4: disiplin baglanmadi"; PROOF_OK=0; fi
[ "$PROOF_OK" = 1 ] && h1 "KANIT: kit %100 AKTIF — kapilar silahli, ajanlar + disiplin yuklu" || warn "KANIT: bazi kapilar dogrulanamadi (yukari bak)"

# ============ [ASAMA 5] HANDOVER.md + ADR (kararlar kalici) ============
h1 "Asama 5 — HANDOVER.md + ADR (devir kalici; kararlar kaybolmaz)"
mkdir -p docs docs/adr
DATE_H="$(date +%Y-%m-%d)"
# karar degerlerini once hesapla (heredoc'ta ic-tirnak/komut-sub karmasasindan kacin)
D1="$([ "$N_PAGENTS" != 0 ] && echo 'koru (coexist)' || echo 'yok')"
D3="$([ "$COAUTHOR" = 1 ] && echo 'gevset (.trace-allowlist)' || echo 'koru')"
D4="$([ "$TRACKED" = 1 ] && echo 'paylasimi koru' || echo 'kit varsayilani')"
D5="$([ -n "$ORIG_HOOKS" ] && echo "SHIM ($ORIG_HOOKS)" || echo 'dogrudan')"
D7="$([ "$OFFREPO" = 1 ] && echo 'AKTAR (asagida doldur)' || echo 'yerel + sor')"
HOOKDESC="$([ -n "$ORIG_HOOKS" ] && echo "SHIM (kit + $ORIG_HOOKS birlikte)" || echo '.claude/hooks dogrudan')"
OFFWARN="$([ "$OFFREPO" = 1 ] && echo 'UYARI: yerel .claude/CLAUDE.md yoktu -> kararlar sohbette/web de olabilir; arac GOREMEDI.' || echo 'Kararlarin bir kismi sohbet gecmisinde olabilir (arac yalniz dosyalari gordu).')"

# 5a) HANDOVER.md — mekanik gercek (dogrulanabilir) + insan bolumu (LLM imzasi YOK)
cat > docs/HANDOVER.md <<HAND
# Devir Notu (HANDOVER) — $DATE_H

> Bu belge aracin MEKANIK olarak yaptigini kayit alir (dogrulanabilir) + senin doldurman
> gereken INSAN bolumlerini isaretler. Arac hicbir seyi "tamamdir" diye IMZALAMAZ.

## Ne devredildi (mekanik)
- Kit ajanlari: $NCCK (-cck namespace; proje ajanlariyla catismaz).
- Proje ajanlari: $N_PAGENTS — DOKUNULMADI, yerinde + aktif (recursive kesif).
- Disiplin: .claude/DISCIPLINE.md + proje CLAUDE.md'sine @import (icerik el degmedi).
- settings.json: sema-farkinda merge (proje hook/permission KORUNDU + kit eklendi).
- Git kapilari: $HOOKDESC.
- Devir dali: $BR  (main el degmemis; incele: git diff main..$BR).

## Alinan kararlar (akilli-oneri; Asama B'de gozden gecir/override)
| # | Karar | Deger |
|---|---|---|
| 1 | Rol cakismasi | $D1 |
| 2 | Precedence | proje kazanir (eksen-eksen) |
| 3 | Iz-kapisi | $D3 |
| 4 | Paylas/gizle | $D4 |
| 5 | Git hook | $D5 |
| 6 | Brownfield DoD | baseline+regresyon |
| 7 | Off-repo | $D7 |

## TEYIT ET (arac dogrulayamaz — sen bak)
- [ ] Devralinan proje kurallari/ajanlari GUNCEL mi? (bayat kural = regresyon)
- [ ] Ortusan roller (proje + kit ayni is): hangisi kullanilacak / birlestirilecek?
- [ ] Devir dali diff'i gozden gecirildi mi?  git diff main..$BR

## SEN DOLDUR — off-repo / sohbet-ici kararlar
> $OFFWARN
<!-- Buraya: sohbette/claude.ai web projesinde alinmis ama repoda OLMAYAN kararlari yaz.
     Onemlileri docs/adr/ altina ADR olarak tasi (adr skill'i yardim eder). -->

---
Uretildi: kit adopt · $DATE_H · dal $BR  (bu satir disinda arac IMZASI yoktur)
HAND
echo "  docs/HANDOVER.md yazildi"

# 5b) ADR-0001 — devrin kendisi kalici karar (never-overwrite)
ADR1="docs/adr/0001-agentik-kit-devri.md"
if [ ! -e "$ADR1" ]; then
  cat > "$ADR1" <<ADR
# ADR-0001: Bu projeye Agentik Kit devredildi

- Tarih: $DATE_H
- Durum: kabul edildi (devir dali: $BR)

## Baglam
Mevcut proje agentik calisma icin standart kit ile "ekipten ekibe devir" mantiginda donatildi.
Amac: proje bozulmasin, alinan kararlar kaybolmasin, kit pasif kalmasin (hybrid).

## Karar
- Kit ajanlari -cck namespace ile kuruldu; proje ajanlari dokunulmadan yan yana korundu.
- Kit disiplini .claude/DISCIPLINE.md + @import ile aktif; proje CLAUDE.md'si el degmedi.
- Kural celiskilerinde PROJE kazanir (eksen-eksen).
- Git kapilari: $HOOKDESC.
- Tum degisiklik gozden-gecirilebilir git dalinda; geri-alma = git.

## Sonuc
Bundan sonra kararlar sohbette DEGIL docs/adr/ altinda ADR olarak yazilir (kalicilik).
Devralinan bayat kurallar "teyit et" kapsaminda; kod ile dogrulanana dek otorite degil.
ADR
  echo "  $ADR1 yazildi (devir kalici karar)"
else
  echo "  $ADR1 zaten var — dokunulmadi (never-overwrite)"
fi

h1 "ERTELENEN (son parca)"
sub "Asama B: akilli-oneri -> gozden gecir/override/uygula (7 karar interaktif; ozellikle #1 birlestir + off-repo aktarim)"

git add .claude CLAUDE.md docs >/dev/null 2>&1
git commit --no-verify -q -m "kit adopt (WIP · asama 2-5): coexist + disiplin + settings + shim + kanit + HANDOVER/ADR; proje korundu" 2>/dev/null || true
# --no-verify: adopt'un KENDI wip commit'i; projenin husky/lint'ini tetiklemesin (yalniz kit dosyasi yerlestirmesi).

h1 "Gozden gecir / geri al (git-native)"
row "degisen" "$(git diff "$BASE".."$BR" --stat 2>/dev/null | tail -1 || echo '(baz yok)')"
sub "incele:      git diff $BASE..$BR"
sub "begendiysen: git checkout $BASE && git merge $BR"
sub "geri al:     git checkout $BASE && git branch -D $BR   (proje el degmemis)"
