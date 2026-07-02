#!/usr/bin/env bash
# Kurucu: yanindaki claude-starter/ klasorunu ./.claude ve ./CLAUDE.md'ye kurar.
# ONCE backend temelini (DevArchitecture) onay kapisiyla projeye dahil eder,
# SONRA kiti kurar; en son claude-starter/'i ve kendini siler.
# start.sh + claude-starter/ AYNI dizinde olmali. Proje kokunde:  bash start.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/claude-starter"
DEVARCH_URL="https://github.com/DevArchitecture/DevArchitecture"

if [ ! -d "$SRC" ]; then
  echo "HATA: 'claude-starter/' klasoru bulunamadi."
  echo "start.sh ile claude-starter/ AYNI dizinde olmali (zip'i acinca ikisi birlikte gelir)."
  exit 1
fi

# ---------------------------------------------------------------------------
# Adim 0: Backend temeli — DevArchitecture (ONAY KAPISI)
# ---------------------------------------------------------------------------
# Bu kit, SIFIRDAN bir .NET projesini DevArchitecture backend kalibi uzerine
# kurmak icin tasarlandi. Onun icin, kurulumdan ONCE backend temelini ele alir.
# Sinir: temel mevcut projeye zorla eklenmez; once var mi diye bakilir, yoksa
# kullanici acik onay verirse dahil edilir.

ask_yes() {  # $1 = soru metni; kullanici 'evet' derse 0 doner
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
  cp -R "$tmp/da/." ./      # proje kokune ac
  rm -rf "$tmp"
  echo "  DevArchitecture projeye birebir dahil edildi."
  echo "  NOT (§4.2): kalip adi namespace / dosya / csproj / appsettings'te KALMAMALI —"
  echo "  sonraki adimda proje adina gore yeniden adlandirin (kurulum sonrasi ajanlara yaptirin)."
}

echo "== Adim 0: Backend temeli (DevArchitecture) =="
if has_devarch; then
  echo "  DevArchitecture tespit edildi — temel zaten var, kopyalama atlaniyor."
elif project_has_source; then
  echo "  !!! DIKKAT: Mevcut bir proje var ve DevArchitecture backend temeli YOK."
  echo "  Bu kit backend akisini DevArchitecture kalibina gore kurar; onu mevcut bir"
  echo "  projeye eklemek dosya/yapi cakismasi yaratip projeyi BOZABILIR."
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

# ---------------------------------------------------------------------------
# Adim 1: Kit kurulumu (./.claude + ./CLAUDE.md)
# ---------------------------------------------------------------------------
echo "== Adim 1: Kuruluyor: ./.claude + ./CLAUDE.md =="
mkdir -p .claude/agents .claude/skills .claude/commands .claude/hooks .claude/eval
cp -R "$SRC/agents/."   .claude/agents/
cp -R "$SRC/skills/."   .claude/skills/
cp -R "$SRC/commands/." .claude/commands/
cp -R "$SRC/hooks/."    .claude/hooks/ 2>/dev/null || true
cp -R "$SRC/eval/."     .claude/eval/ 2>/dev/null || true
[ -f "$SRC/settings.json" ] && cp "$SRC/settings.json" .claude/settings.json
chmod +x .claude/hooks/pre-commit .claude/hooks/commit-msg .claude/hooks/guard-bash.sh .claude/eval/smoke-test.sh 2>/dev/null || true
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
echo "== Tamam. ./.claude + ./CLAUDE.md hazir; claude-starter/ silindi. =="
echo "Sira: 1) CLAUDE.md proje kismini duzenle  2) Claude Code ac  3) /agents"
rm -f -- "$0"
