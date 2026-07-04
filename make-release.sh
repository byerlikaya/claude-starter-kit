#!/usr/bin/env bash
# Private release artefakti uretir: SADECE dagitim payload'unu (start.sh + claude-starter/ + VERSION)
# tar.gz'ler. `git archive HEAD` kullanir -> commit'lenmemis/gizli dosya sizmaz; WHITELIST ile kok
# CLAUDE.md / docs/ / .github / make-release.sh / CHANGELOG / README ASLA girmez (§4.3 gizlilik +
# §4.1/§4.2 iz-denetimi -> "kural=kapi": whitelist disi tek dosya cikarsa uretim DURUR).
#
# Kullanim:  bash make-release.sh          -> dist/claude-starter-kit-<VERSION>.tgz
# Yayinla (AYRI + ACIK onay; surum bumlamaz, mevcut tag'i indirilebilir yapar):
#   gh release create v<VER> dist/claude-starter-kit-<VER>.tgz -R <owner>/<repo> \
#     --title "v<VER>" --notes-file CHANGELOG.md
# Tuketici (private erisimle):
#   gh release download v<VER> -p '*.tgz' && tar xzf claude-starter-kit-*.tgz && bash start.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

[ -f VERSION ] || { echo "HATA: kök VERSION dosyasi yok." >&2; exit 1; }
VER="$(tr -d ' \n\r' < VERSION)"
[ -n "$VER" ] || { echo "HATA: VERSION bos." >&2; exit 1; }
OUT="dist/claude-starter-kit-$VER.tgz"
mkdir -p dist

# Yalniz izlenen whitelist yollari (HEAD'den) — calisma agaci kirli olsa bile sizinti olmaz.
git archive --format=tar.gz -o "$OUT" HEAD start.sh claude-starter VERSION

# KAPI: whitelist disi hicbir giris olmamali.
bad="$(tar tzf "$OUT" | grep -vE '^(start\.sh$|claude-starter($|/)|VERSION$)' || true)"
if [ -n "$bad" ]; then
  echo "HATA: whitelist disi dosya artefakta sizdi (§4.3):" >&2
  printf '  %s\n' $bad >&2
  rm -f "$OUT"; exit 1
fi

echo "Uretildi: $OUT ($(du -h "$OUT" | cut -f1)) · $(tar tzf "$OUT" | wc -l | tr -d ' ') giris"
echo "Whitelist dogrulandi: yalniz start.sh + claude-starter/ + VERSION"
echo
echo "Yayinlamak icin (AYRI onay — §4.4):"
echo "  gh release create v$VER \"$OUT\" -R byerlikaya/claude-starter-kit --title \"v$VER\" --notes-file CHANGELOG.md"
