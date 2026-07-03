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
  --generic  jenerik backend (backend/database-expert + db-migration; devarch/sonarqube YOK)
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

echo "=== Kit Kurulum Sihirbazi ==="

# --- Adim 1: profil ---
if [ -z "$PROFILE" ]; then
  echo "1) Proje profili? Kurulacak ajan/skill setini belirler:"
  echo "   1) backend   2) frontend   3) fullstack (varsayilan)   4) mobile"
  printf '   Secim [1-4, bos=3]: '
  read -r s || s=""
  case "$s" in 1) PROFILE="backend" ;; 2) PROFILE="frontend" ;; 4) PROFILE="mobile" ;; *) PROFILE="fullstack" ;; esac
fi

# --- Adim 2: backend yigini (yalniz backend/fullstack) ---
HAS_BACKEND=0
case "$PROFILE" in backend|fullstack) HAS_BACKEND=1 ;; esac
if [ "$HAS_BACKEND" = 1 ] && [ -z "$STACK" ]; then
  echo "2) Backend yigini?"
  echo "   1) .NET / DevArchitecture (tam destek)   2) Jenerik (devarch-module + sonarqube-check YOK)"
  printf '   Secim [1-2, bos=1]: '
  read -r s || s=""
  case "$s" in 2) STACK="generic" ;; *) STACK="dotnet" ;; esac
fi
[ "$HAS_BACKEND" = 1 ] || STACK="none"

# --- Eslemeler: budanacak ajan/skiller + DevArch kapisi ---
DEVARCH_ON=0
case "$PROFILE" in
  frontend)
    EXCL_AGENTS="backend-expert.md database-expert.md"
    EXCL_SKILLS="db-migration devarch-module sonarqube-check frontend-rn-expo" ;;
  mobile)
    EXCL_AGENTS="backend-expert.md database-expert.md"
    EXCL_SKILLS="db-migration devarch-module sonarqube-check" ;;
  backend)
    EXCL_AGENTS="frontend-expert.md"
    EXCL_SKILLS="frontend frontend-rn-expo i18n-integrity" ;;
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

# --- Adim 3: ozet + son onay ---
echo
echo "=== Ozet ==="
echo "  Profil          : $PROFILE"
if [ "$HAS_BACKEND" = 1 ]; then
  if [ "$STACK" = "generic" ]; then
    echo "  Backend yigini  : jenerik (devarch-module + sonarqube-check kurulmaz)"
  else
    echo "  Backend yigini  : .NET / DevArchitecture (tam destek)"
  fi
fi
[ "$DEVARCH_ON" = 1 ] && echo "  DevArchitecture : kurulum kapisi calisacak" || echo "  DevArchitecture : kurulmaz"
echo
if ! ask_yes "Bu ayarlarla kurulsun mu?"; then
  echo "Iptal edildi; hicbir sey degismedi."
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
# Jenerik backend: DevArchitecture'a bagli backend-expert yerine yigin-bagimsiz varyanti kur.
if [ "$HAS_BACKEND" = 1 ] && [ "$STACK" = "generic" ] && [ -f "$SRC/agents-optional/backend-expert-generic.md" ]; then
  cp "$SRC/agents-optional/backend-expert-generic.md" .claude/agents/backend-expert.md
fi
echo "  Profil '$PROFILE' (yigin: $STACK): $(ls .claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ') ajan, $(ls -d .claude/skills/*/ 2>/dev/null | wc -l | tr -d ' ') skill kuruldu."
[ -f "$SRC/settings.json" ] && cp "$SRC/settings.json" .claude/settings.json
chmod +x .claude/hooks/pre-commit .claude/hooks/commit-msg .claude/hooks/guard-bash.sh .claude/hooks/context-usage.sh .claude/eval/smoke-test.sh .claude/eval/routing-eval.sh 2>/dev/null || true
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
