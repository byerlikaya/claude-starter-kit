#!/usr/bin/env bash
# The published site is the only artifact with NO source in this repo and NO build step: `gh-pages` holds a
# hand-written index.html and nothing regenerates it. So it drifts silently, and it already did — the version
# line sat at v1.6.0 through the entire 1.7.0 release while the counters had been hand-corrected separately.
# Every other count in this project is gated (README catalogue, plugin edition, byte budgets); this one was not.
#
# Compares the site's version and its agent/skill counters against the payload it claims to describe. Read-only.
#
# Usage:
#   bash packaging/check-gh-pages.sh              # reads the site from the gh-pages ref (origin/ then local)
#   bash packaging/check-gh-pages.sh path.html    # or from a file, e.g. a checked-out worktree
#
# Exit 0 in sync · 1 drifted · 2 the site could not be read (no ref, no file — never silently "in sync").
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

SRC="${1:-}"
HTML=""
if [ -n "$SRC" ]; then
  [ -f "$SRC" ] && HTML="$(cat "$SRC")" || { echo "check-gh-pages: no such file: $SRC" >&2; exit 2; }
else
  for ref in origin/gh-pages gh-pages; do
    HTML="$(git show "$ref:index.html" 2>/dev/null)" && [ -n "$HTML" ] && { SRC="$ref:index.html"; break; }
    HTML=""
  done
  [ -n "$HTML" ] || { echo "check-gh-pages: no gh-pages ref with an index.html (fetch it, or pass a file)" >&2; exit 2; }
fi

VER="$(tr -d ' \n\r' < VERSION 2>/dev/null)"
AGENTS=$(ls claude-starter/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
SKILLS=$(ls -d claude-starter/skills/*/ 2>/dev/null | wc -l | tr -d ' ')

# The site is markup, so read the NUMBERS the way the page renders them: the version marker, and each counter as
# the digits sitting immediately before its label. Anchored to the label, never to a bare number — the page is
# full of unrelated integers (SVG coordinates, CSS radii), and matching those would produce confident nonsense.
site_ver="$(printf '%s' "$HTML" | sed -n 's/.*id="ver"[^>]*>v\{0,1\}\([0-9][0-9.]*\)<.*/\1/p' | head -1)"
count_before() {   # $1 = label word as it appears in the page ("agents" / "skills")
  printf '%s' "$HTML" \
    | tr '\n' ' ' \
    | grep -oE "<b>[0-9]+</b> <span class=\"en\">$1|<div class=\"num\">[0-9]+</div><div class=\"cap\"><span class=\"en\">$1" \
    | grep -oE '[0-9]+' | sort -u | tr '\n' ' '
}
site_agents="$(count_before agents)"
site_skills="$(count_before skills)"

FAIL=0
echo "== published site vs payload  ($SRC) =="
chk() { # $1 label, $2 expected, $3 found(list)
  local found="$(printf '%s' "$3" | tr -s ' ' | sed 's/ $//')"
  if [ -z "$found" ]; then
    echo "  ⚠️  $1: not found on the page — the markup changed; update this check, don't ignore it"; FAIL=1
  elif [ "$found" = "$2" ]; then
    echo "  ✅ $1: $2"
  else
    echo "  ❌ $1: site says '$found', payload is '$2'"; FAIL=1
  fi
}
chk "version" "$VER" "$site_ver"
chk "agents"  "$AGENTS" "$site_agents"
chk "skills"  "$SKILLS" "$site_skills"

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "GH-PAGES: in sync ✅"; exit 0; fi
echo "GH-PAGES: drifted ❌ — update index.html on the gh-pages branch before publishing"
echo "  the site is hand-written and has no build step, so nothing else will do it"
exit 1
