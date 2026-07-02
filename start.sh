#!/usr/bin/env bash
# Kurucu: yanindaki claude-starter/ klasorunu ./.claude ve ./CLAUDE.md'ye kurar,
# sonra claude-starter/'i ve kendini siler.
# start.sh + claude-starter/ AYNI dizinde olmali. Repo kokunde:  bash start.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/claude-starter"
if [ ! -d "$SRC" ]; then
  echo "HATA: 'claude-starter/' klasoru bulunamadi."
  echo "start.sh ile claude-starter/ AYNI dizinde olmali (zip'i acinca ikisi birlikte gelir)."
  exit 1
fi
echo "== Kuruluyor: ./.claude + ./CLAUDE.md =="
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
