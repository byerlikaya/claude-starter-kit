#!/usr/bin/env bash
# Kurulum sihirbazi: adimlarla profil + backend yigini secer, ozet gosterip onaylatir;
# backend .NET secilirse DevArchitecture temelini onay kapisiyla dahil eder; sonra kiti
# (./.claude + ./CLAUDE.md) profile gore budayarak kurar; en son claude-starter/'i ve kendini siler.
# start.sh + claude-starter/ AYNI dizinde olmali. Proje kokunde:  bash start.sh [bayraklar]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/claude-starter"
DEVARCH_URL="https://github.com/DevArchitecture/DevArchitecture"

if [ ! -d "$SRC" ]; then
  echo "HATA: 'claude-starter/' klasoru bulunamadi."
  echo "start.sh ile claude-starter/ AYNI dizinde olmali (zip'i acinca ikisi birlikte gelir)."
  exit 1
fi

usage() {
  cat <<'USAGE'
Kullanim: bash start.sh [PROFIL] [BACKEND-YIGINI]
  Profil:   --backend | --frontend | --mobile | --fullstack   (varsayilan: fullstack)
  Yigin:    --dotnet  | --generic   (yalniz backend/fullstack; varsayilan: dotnet)
Bayrak verilmezse betik ilgili adimi interaktif sorar (sihirbaz).
  --dotnet   .NET/DevArchitecture tam destek (devarch-module + sonarqube-check + DevArch kapisi)
  --generic  jenerik backend (backend/database-expert-cck + db-migration; devarch/sonarqube YOK)
USAGE
}

ask_yes() {  # $1 = soru; kullanici 'evet' derse 0 doner
  local a
  printf '%s [evet/hayir]: ' "$1"
  read -r a || a=""
  case "$a" in [eE][vV][eE][tT]|[eE]|[yY]) return 0 ;; *) return 1 ;; esac
}
has_devarch() {  # projede DevArchitecture kanonik yapisi var mi
  [ -d ./Business ] && [ -d ./Core ] && { [ -d ./DataAccess ] || [ -d ./Entities ] || [ -d ./WebAPI ]; }
}
project_has_source() {  # kit disinda gercek kaynak/proje dosyasi var mi
  ls ./*.sln ./*.csproj >/dev/null 2>&1 && return 0
  for m in package.json go.mod pom.xml build.gradle Cargo.toml requirements.txt pyproject.toml src; do
    [ -e "./$m" ] && return 0
  done
  return 1
}
clone_devarch() {  # birebir dahil et: klonla, nested .git'i sil, koke kopyala
  command -v git >/dev/null 2>&1 || { echo "  HATA: git yok; DevArchitecture dahil edilemiyor."; return 1; }
  local tmp; tmp="$(mktemp -d)"
  echo "  Indiriliyor: $DEVARCH_URL"
  if ! git clone --depth 1 "$DEVARCH_URL" "$tmp/da" >/dev/null 2>&1; then
    echo "  HATA: klonlama basarisiz (ag/erisim?). Elle: git clone $DEVARCH_URL"
    rm -rf "$tmp"; return 1
  fi
  rm -rf "$tmp/da/.git"     # ayri repo/submodule degil, birebir dosya olarak dahil
  cp -R "$tmp/da/." ./
  rm -rf "$tmp"
  echo "  DevArchitecture projeye birebir dahil edildi."
  echo "  NOT (§4.2): kalip adi namespace / dosya / csproj / appsettings'te KALMAMALI —"
  echo "  sonraki adimda proje adina gore yeniden adlandirin (kurulum sonrasi ajanlara yaptirin)."
}

# --- Bayrak ayristirma (sessiz/CI modu) ---
PROFILE=""; STACK=""
for a in "$@"; do
  case "$a" in
    --backend) PROFILE="backend" ;;
    --frontend) PROFILE="frontend" ;;
    --mobile) PROFILE="mobile" ;;
    --fullstack) PROFILE="fullstack" ;;
    --dotnet) STACK="dotnet" ;;
    --generic) STACK="generic" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Bilinmeyen parametre: $a"; echo; usage; exit 1 ;;
  esac
done

# ===================== RENK / STIL YARDIMCILARI =====================
# Renk YALNIZ interaktif TTY'de + TERM!=dumb + NO_COLOR bosken uretilir.
# Aksi halde tum kodlar '' => CI/pipe/dumb'da ham \033 SIZMAZ (NO_COLOR saygi gorur).
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\033[0m'; B=$'\033[1m'; D=$'\033[2m'
  CY=$'\033[36m'; GR=$'\033[32m'; YE=$'\033[33m'; MG=$'\033[35m'
else
  R=''; B=''; D=''; CY=''; GR=''; YE=''; MG=''
fi
h1()   { printf '\n%s%s%s%s\n' "$B" "$CY" "$1" "$R"; }               # bolum basligi
sub()  { printf '%s%s%s\n' "$D" "$1" "$R"; }                         # dim aciklama
opt()  { # $1=no $2=etiket $3=varsayilan_mi $4=sag-rozet
  local mark=''; [ "${3:-0}" = 1 ] && mark=" ${GR}${B}(varsayilan)${R}"
  printf '  %s%s%s)%s %s%-24s%s %s%s%s%s\n' "$B" "$YE" "$1" "$R" "$B" "$2" "$R" "$MG" "${4:-}" "$R" "$mark"
}
add()  { printf '     %s+%s %s\n'      "$GR" "$R" "$1"; }            # KURULUR
skip() { printf '     %s-%s %s%s%s\n'  "$YE" "$R" "$D" "$1" "$R"; }  # KURULMAZ (tradeoff)
gate() { printf '     %s>%s %s\n'      "$CY" "$R" "$1"; }            # silahlanacak kapi
row()  { printf '  %s%-15s%s %s\n'     "$B" "$1" "$R" "$2"; }        # ozet satiri
rule() { printf '  %s------------------------------------------------%s\n' "$D" "$R"; }

h1  "Agentik Calisma Kiti · kurulum sihirbazi"
sub "3 adim: profil -> backend yigini -> ozet & onay."

# ===================== ADIM 1 · PROFIL =====================
# Bayrak verilmisse ($PROFILE dolu) bu blok komple ATLANIR (non-interactive yol korunur).
if [ -z "$PROFILE" ]; then
  h1  "[1/3] Proje profili"
  sub "Secim, kurulacak ajan + skill setini belirler."
  echo
  opt 1 "backend"   0 "~10 ajan · ~24 skill"
  add  "backend-expert-cck · database-expert-cck + db / api / migration skilleri"
  skip "frontend-expert-cck ve tum arayuz skilleri (frontend/a11y/i18n) KURULMAZ"
  echo
  opt 2 "frontend"  0 "~9 ajan · ~22 skill"
  add  "frontend-expert-cck + frontend / a11y / i18n skilleri"
  skip "backend-expert-cck · database-expert-cck ve tum sunucu skilleri KURULMAZ"
  echo
  opt 3 "fullstack" 1 "~11 ajan · ~27 skill"
  add  "her sey — tum ajanlar + tum skiller (on yuz + arka uc birlikte)"
  echo
  opt 4 "mobile"    0 "~9 ajan · ~23 skill"
  add  "frontend-expert-cck + React Native / Expo katmani (frontend-rn-expo)"
  skip "backend-expert-cck · database-expert-cck KURULMAZ"
  echo
  printf '  %s->%s Secim %s[1-4, bos=3]%s: ' "$CY" "$R" "$D" "$R"
  read -r s || s=""                 # EOF/non-TTY'de takilmaz; bos => varsayilan (fullstack)
  case "$s" in 1) PROFILE="backend" ;; 2) PROFILE="frontend" ;; 4) PROFILE="mobile" ;; *) PROFILE="fullstack" ;; esac
fi

# ===================== ADIM 2 · BACKEND YIGINI =====================
# Yalniz backend/fullstack sorulur; bayrak varsa atlanir.
HAS_BACKEND=0
case "$PROFILE" in backend|fullstack) HAS_BACKEND=1 ;; esac
if [ "$HAS_BACKEND" = 1 ] && [ -z "$STACK" ]; then
  h1  "[2/3] Backend yigini"
  sub "Arka uc kalibini ve .NET'e ozel skillerin gelip gelmeyecegini belirler."
  echo
  opt 1 ".NET / DevArchitecture" 1 "tam destek"
  add  "devarch-module + sonarqube-check skilleri (opinionated MediatR CQRS)"
  gate "DevArchitecture temel projesini ONAY KAPISIYLA klonlar (sifirdan proje)"
  echo
  opt 2 "Jenerik" 0 "yigin-bagimsiz"
  add  "yigin-bagimsiz backend-expert-cck — mevcut repo kalibina uyar"
  skip "devarch-module · sonarqube-check ve DevArchitecture temeli KURULMAZ"
  echo
  printf '  %s->%s Secim %s[1-2, bos=1]%s: ' "$CY" "$R" "$D" "$R"
  read -r s || s=""                 # bos => varsayilan (dotnet)
  case "$s" in 2) STACK="generic" ;; *) STACK="dotnet" ;; esac
fi
[ "$HAS_BACKEND" = 1 ] || STACK="none"

# --- Eslemeler: budanacak ajan/skiller + DevArch kapisi ---
DEVARCH_ON=0
case "$PROFILE" in
  frontend)
    EXCL_AGENTS="backend-expert-cck.md database-expert-cck.md"
    EXCL_SKILLS="db-migration devarch-module sonarqube-check frontend-rn-expo api-design" ;;
  mobile)
    EXCL_AGENTS="backend-expert-cck.md database-expert-cck.md"
    EXCL_SKILLS="db-migration devarch-module sonarqube-check api-design" ;;
  backend)
    EXCL_AGENTS="frontend-expert-cck.md"
    EXCL_SKILLS="frontend frontend-rn-expo a11y" ;;
  fullstack)
    EXCL_AGENTS=""
    EXCL_SKILLS="" ;;
esac
if [ "$HAS_BACKEND" = 1 ]; then
  if [ "$STACK" = "dotnet" ]; then
    DEVARCH_ON=1
  else
    EXCL_SKILLS="$EXCL_SKILLS devarch-module sonarqube-check"   # jenerik: .NET'e ozel skiller gelmez
  fi
fi

# ===================== ADIM 3 · OZET + ONAY =====================
# Bu blok ESLEMELERDEN (EXCL_AGENTS/EXCL_SKILLS/DEVARCH_ON) SONRA gelir -> sayim dogru budanir.
# Kurulacak ajan/skill adedini KAYNAKTAN canli say (gomulu sabit degil; eslemeler degisirse kendini duzeltir).
count_installed() {   # $1=EXCL listesi  $2=glob  -> kurulacak adet
  local excl=" $1 " n=0 base
  for p in $2; do
    [ -e "$p" ] || continue
    base="$(basename "$p")"
    case "$excl" in *" $base "*) ;; *) n=$((n+1)) ;; esac
  done
  printf '%s' "$n"
}
N_AG="$(count_installed "$EXCL_AGENTS" "$SRC/agents/*.md")"
N_SK="$(count_installed "$EXCL_SKILLS" "$SRC/skills/*/")"

case "$PROFILE" in
  backend)   P_TXT="backend ${D}— sunucu / API / DB (frontend yok)${R}" ;;
  frontend)  P_TXT="frontend ${D}— web arayuzu (backend yok)${R}" ;;
  mobile)    P_TXT="mobile ${D}— React Native / Expo (backend yok)${R}" ;;
  fullstack) P_TXT="fullstack ${D}— uctan uca (en genis)${R}" ;;
esac

h1 "[3/3] Ozet · onaylamadan once ne kurulacagini gor"
echo
row "Profil" "${B}${P_TXT}${R}"
row "Gelen"  "${MG}${B}${N_AG}${R} ajan · ${MG}${B}${N_SK}${R} skill kurulacak"
if [ "$HAS_BACKEND" = 1 ]; then
  if [ "$STACK" = "generic" ]; then
    row "Backend yigin" ".NET disi — jenerik ${D}(devarch-module + sonarqube-check kurulmaz)${R}"
  else
    row "Backend yigin" ".NET / DevArchitecture ${D}(tam destek)${R}"
  fi
fi
if [ "$DEVARCH_ON" = 1 ]; then
  row "DevArch temel" "${YE}kurulum onay kapisi calisacak${R}"
elif [ "$HAS_BACKEND" = 1 ]; then
  row "DevArch temel" "${D}kurulmaz${R}"
fi
echo
printf '  %sHer kurulumda silahlanan guvenlik kapilari:%s\n' "$B" "$R"
gate "commit/push onay kapisi — auto/bypass modda bile (guard-bash)"
gate "iz-denetimi — yapay-zeka izi / vendor adini git hook bloklar"
gate "gercek context olcumu + %75'te handoff (Stop hook)"
gate "destruktif komut guard'i (rm -rf / force-push vb.)"
echo
row "Yazilacak" "${D}./.claude (agents·skills·commands·hooks·eval·settings.json) + ./CLAUDE.md${R}"
rule
echo
# ask_yes stdin'den okur => CI'da `printf 'evet\n' | bash start.sh` calisir; EOF'ta 'hayir' (kaza kurulumu yok).
if ! ask_yes "  Bu ayarlarla kurulsun mu?"; then
  printf '  %sIptal edildi — hicbir sey degismedi.%s\n' "$YE" "$R"
  exit 0
fi
echo

# --- Adim 4: Backend temeli (yalniz .NET/DevArchitecture; ONAY KAPISI) ---
if [ "$DEVARCH_ON" = 1 ]; then
  echo "== Backend temeli (DevArchitecture) =="
  if has_devarch; then
    echo "  DevArchitecture tespit edildi — temel zaten var, kopyalama atlaniyor."
  elif project_has_source; then
    echo "  !!! DIKKAT: Mevcut bir proje var ve DevArchitecture backend temeli YOK."
    echo "  Onu mevcut projeye eklemek dosya/yapi cakismasi yaratip projeyi BOZABILIR."
    echo "  Bu kitin amaci SIFIRDAN proje kurmaktir. Yine de eklemek istiyorsaniz onaylayin."
    if ask_yes "  DevArchitecture'i bu MEVCUT projeye eklemek (riskli) istiyor musunuz?"; then
      clone_devarch || echo "  Backend temeli olmadan devam ediliyor."
    else
      echo "  Atlandi. Backend akisi DevArchitecture varsayar; elle uyarlamaniz gerekir."
    fi
  else
    echo "  Sifirdan proje: bu kit DevArchitecture backend temelini kurabilir."
    if ask_yes "  DevArchitecture backend temelini simdi projeye dahil edeyim mi?"; then
      clone_devarch || echo "  Backend temeli dahil edilemedi; kit kurulumuna devam."
    else
      echo "  Atlandi. Sonra elle ekleyebilirsiniz:  git clone $DEVARCH_URL"
    fi
  fi
  echo
fi

# --- Adim 5: Kit kurulumu (./.claude + ./CLAUDE.md) — profile gore budanmis ---
echo "== Kuruluyor: ./.claude + ./CLAUDE.md =="
mkdir -p .claude/agents .claude/skills .claude/commands .claude/hooks .claude/eval
cp -R "$SRC/agents/."   .claude/agents/
cp -R "$SRC/skills/."   .claude/skills/
cp -R "$SRC/commands/." .claude/commands/
cp -R "$SRC/hooks/."    .claude/hooks/ 2>/dev/null || true
cp -R "$SRC/eval/."     .claude/eval/ 2>/dev/null || true
for f in $EXCL_AGENTS; do rm -f  ".claude/agents/$f"; done
for d in $EXCL_SKILLS; do rm -rf ".claude/skills/$d"; done
# Jenerik backend: DevArchitecture'a bagli backend-expert-cck yerine yigin-bagimsiz varyanti kur.
if [ "$HAS_BACKEND" = 1 ] && [ "$STACK" = "generic" ] && [ -f "$SRC/agents-optional/backend-expert-generic.md" ]; then
  cp "$SRC/agents-optional/backend-expert-generic.md" .claude/agents/backend-expert-cck.md
fi
echo "  Profil '$PROFILE' (yigin: $STACK): $(ls .claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ') ajan, $(ls -d .claude/skills/*/ 2>/dev/null | wc -l | tr -d ' ') skill kuruldu."
[ -f "$SRC/settings.json" ] && cp "$SRC/settings.json" .claude/settings.json
[ -f "$HERE/VERSION" ] && cp "$HERE/VERSION" .claude/VERSION   # kurulan projede kit surumu izlenebilir olsun
chmod +x .claude/hooks/pre-commit .claude/hooks/commit-msg .claude/hooks/guard-bash.sh .claude/hooks/context-usage.sh .claude/hooks/session-guard.sh .claude/eval/smoke-test.sh .claude/eval/routing-eval.sh 2>/dev/null || true
cp "$SRC/AGENT_TEMPLATE.md" .claude/ 2>/dev/null || true
cp "$SRC/ILK_PROMPT.md"     .claude/ 2>/dev/null || true
cp "$SRC/README.md"         .claude/ 2>/dev/null || true
if [ -f ./CLAUDE.md ]; then
  echo "  ./CLAUDE.md var — elle birlestir (dokunmadim)."
else
  cp "$SRC/CLAUDE.md" ./CLAUDE.md
  echo "  ./CLAUDE.md olusturuldu — proje kismini DUZENLE."
fi
touch .gitignore
for e in 'docs/' '.claude/' 'CLAUDE.md'; do grep -qxF "$e" .gitignore || echo "$e" >> .gitignore; done
if [ -d .git ]; then
  git config core.hooksPath .claude/hooks
  echo "  iz-denetcisi: core.hooksPath -> .claude/hooks (§4.1/§4.2 commit kapisi aktif)"
else
  echo "  NOT: git deposu yok; 'git init' sonrasi calistir:  git config core.hooksPath .claude/hooks"
fi
rm -rf "$SRC"
echo
echo "== Tamam. ./.claude + ./CLAUDE.md hazir ($PROFILE/$STACK); claude-starter/ silindi. =="
echo "Sira: 1) CLAUDE.md proje kismini duzenle  2) Claude Code ac  3) /agents"
rm -f -- "$0"
