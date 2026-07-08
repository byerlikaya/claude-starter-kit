#!/usr/bin/env bash
# Produces a private release artifact: tar.gz's ONLY the distribution payload (start.sh +
# claude-starter/ + VERSION). Uses `git archive HEAD` -> no uncommitted/secret file leaks; via the
# WHITELIST, root CLAUDE.md / docs/ / .github / make-release.sh / CHANGELOG / README NEVER get in
# (§4.3 privacy + §4.1/§4.2 trace scan -> "rule=gate": if a single file outside the whitelist
# appears, production STOPS).
#
# Usage:  bash make-release.sh          -> dist/claude-starter-kit-<VERSION>.tgz
# Publish (SEPARATE + EXPLICIT approval; does not bump the version, makes the existing tag downloadable):
#   gh release create v<VER> dist/claude-starter-kit-<VER>.tgz -R <owner>/<repo> \
#     --title "v<VER>" --notes-file CHANGELOG.md
# Consumer (with private access):
#   gh release download v<VER> -p '*.tgz' && tar xzf claude-starter-kit-*.tgz && bash start.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

[ -f VERSION ] || { echo "ERROR: root VERSION file is missing." >&2; exit 1; }
VER="$(tr -d ' \n\r' < VERSION)"
[ -n "$VER" ] || { echo "ERROR: VERSION is empty." >&2; exit 1; }
OUT="dist/claude-starter-kit-$VER.tgz"
mkdir -p dist

# Only tracked whitelist paths (from HEAD) — no leak even if the working tree is dirty.
git archive --format=tar.gz -o "$OUT" HEAD start.sh adopt.sh claude-starter VERSION

# GATE: there must be no entry outside the whitelist.
bad="$(tar tzf "$OUT" | grep -vE '^(start\.sh$|update\.sh$|claude-starter($|/)|VERSION$)' || true)"
if [ -n "$bad" ]; then
  echo "ERROR: a file outside the whitelist leaked into the artifact (§4.3):" >&2
  printf '  %s\n' $bad >&2
  rm -f "$OUT"; exit 1
fi

echo "Produced: $OUT ($(du -h "$OUT" | cut -f1)) · $(tar tzf "$OUT" | wc -l | tr -d ' ') entries"
echo "Whitelist verified: only start.sh + adopt.sh + claude-starter/ + VERSION"
echo
echo "To publish (SEPARATE approval — §4.4):"
echo "  gh release create v$VER \"$OUT\" -R byerlikaya/claude-starter-kit --title \"v$VER\" --notes-file CHANGELOG.md"
