#!/usr/bin/env bash
# The published site is the only artifact with NO source in this repo and NO build step: `gh-pages` holds a
# hand-written index.html and nothing regenerates it. So it drifts silently, and it already did — the version
# line sat at v1.6.0 through the entire 1.7.0 release while the counters had been hand-corrected separately.
# Every other count in this project is gated (README catalogue, plugin edition, byte budgets); this one was not.
#
# Compares the site's version, and every count of agents, skills and commands it states — counters and prose, in
# English and Turkish — against the payload it claims to describe. Read-only.
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
COMMANDS=$(ls claude-starter/commands/*.md 2>/dev/null | wc -l | tr -d ' ')

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
site_commands="$(count_before commands)"

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
chk "commands" "$COMMANDS" "$site_commands"

# Counts written in prose are read too. Before 2.10.0 the page said "39 skills" in its hero, its pitch and its
# Turkish pitch while every counter said 40, and its commands counter said 7 against 11 — and this script was
# green, because it read only the counters. The text is the page with its tags removed, plus the description and
# title meta tags (attributes, so removing tags would lose them; either quote style). &nbsp; counts as a space.
# The text is read word by word rather than with one regular expression: the page writes its English and Turkish
# spans side by side ("12 agents 12 ajan"), and a pattern that consumes the space after one count cannot start a
# match on the next. A count is a word of one to three digits (optionally after "(") followed by the noun, with
# the one adjective the page puts between them ("specialist" / "uzman") allowed.
TEXT="$( { printf '%s' "$HTML" | tr '\n' ' ' | grep -oiE '<meta [^>]*>' \
            | grep -iE "(name|property)=[\"'](og:|twitter:)?(description|title)[\"']" \
            | sed -n -E -e "s/.*content=\"([^\"]*)\".*/\1/p" -e "s/.*content='([^']*)'.*/\1/p"
          printf '%s' "$HTML" | tr '\n' ' ' | sed 's/<[^>]*>/ /g'; } \
        | sed -e 's/&nbsp;/ /g' -e 's/&#160;/ /g' -e 's/&#[xX][aA]0;/ /g' | LC_ALL=C sed $'s/\xc2\xa0/ /g' | tr -s ' ' )"
prose_nums() {   # $1 noun alternation -> one number per count found
  printf '%s' "$TEXT" | tr -s ' \t' '\n\n' | awk -v nouns="$1" '
    { w[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        n = w[i]; sub(/^\(/, "", n)
        if (n !~ /^[0-9][0-9]?[0-9]?$/) continue
        j = i + 1; x = tolower(w[j])
        if (x == "specialist" || x == "uzman") { j++; x = tolower(w[j]) }
        sub(/[^a-z].*$/, "", x)
        if (x ~ ("^(" nouns ")$")) print n
      }
    }'
}
prose_chk() {   # $1 label, $2 expected, $3 noun alternation (EN|TR)
  local nums bad n
  nums="$(prose_nums "$3")"
  if [ -z "$nums" ]; then
    echo "  ⚠️  $1 in the page text: no count found — the page changed; update this check, don't ignore it"; FAIL=1; return
  fi
  bad="$(printf '%s\n' "$nums" | grep -v -x -F "$2" | sort -u | tr '\n' ' ')"
  if [ -z "$bad" ]; then
    echo "  ✅ $1 in the page text: $2 (stated $(printf '%s\n' "$nums" | wc -l | tr -d ' ') time(s))"
  else
    echo "  ❌ $1 in the page text: says ${bad}where the payload is $2"
    for n in $bad; do
      printf '%s' "$TEXT" | grep -oE ".{0,40}(^|[^0-9])$n ((specialist|uzman) )?($3)" | sed 's/^/        …/'
    done
    FAIL=1
  fi
}
prose_chk "agents"   "$AGENTS"   "agents?|ajan"
prose_chk "skills"   "$SKILLS"   "skills?"
prose_chk "commands" "$COMMANDS" "commands?|komut"

# The brand mark exists three times and no copy can see the others: assets/icon.svg is the source, the site
# inlines it as a data: URI favicon (no file reference, so a grep of the working tree finds nothing — and one
# did, which is how these were nearly deleted as unused), and packaging/gen-network.py hand-copies the same
# rects into the diagram core. Three hand-kept copies drift; that is what this repo gates everywhere else.
# Compared on SHAPE, not bytes: the site writes single quotes and %23 for #, and omits width/height, so both
# sides are reduced to the same canonical fragment before the strings are compared.
# Truncated at the FIRST </g> on purpose: gen-network wraps the mark in an extra translate/scale group, so a
# greedy match there swallows one closing tag more than the other two have and the comparison fails on the
# wrapper rather than on the artwork.
canon_mark() {   # stdin: any svg text -> the mark fragment, quote/encoding/whitespace normalised
  sed "s/%23/#/g; s/'/\"/g" | tr -d ' \n\r\t' \
    | grep -oE '<rectwidth="200".*' | head -1 | sed 's|</g>.*|</g>|'
}
# Displayed as a short digest — the fragment itself is 250 characters and three of them on one line is a wall
# nobody reads. A mismatch prints both digests; the fragments are two `canon_mark` calls away when you need them.
dig() { printf '%s' "$1" | cksum | awk '{print $1}'; }
SRC_MARK="$(canon_mark < assets/icon.svg 2>/dev/null || true)"
SITE_MARK="$(printf '%s' "$HTML" | grep -F 'rel="icon"' | canon_mark || true)"
GEN_MARK="$(grep -oE "'<rect[^']*'" packaging/gen-network.py 2>/dev/null | tr -d "'" | tr -d '\n' | canon_mark || true)"
# Not routed through chk(): its wording is "site says …", which would point a reader at the gh-pages branch for
# a mismatch that lives in a python file in this repo.
mark_chk() {   # $1 = where this copy lives, $2 = its fragment
  if [ -z "$2" ]; then
    echo "  ⚠️  brand mark in $1: not found — the markup changed; update this check, don't ignore it"; FAIL=1
  elif [ "$2" = "$SRC_MARK" ]; then
    echo "  ✅ brand mark in $1 matches assets/icon.svg ($(dig "$2"))"
  else
    echo "  ❌ brand mark in $1 drifted from assets/icon.svg ($(dig "$2") vs $(dig "$SRC_MARK"))"; FAIL=1
  fi
}
if [ -z "$SRC_MARK" ]; then
  echo "  ⚠️  brand mark: assets/icon.svg did not parse — it is the source of the other two copies"; FAIL=1
else
  mark_chk "the published favicon"      "$SITE_MARK"
  mark_chk "packaging/gen-network.py"   "$GEN_MARK"
fi

echo "---"
if [ "$FAIL" -eq 0 ]; then echo "GH-PAGES: in sync ✅"; exit 0; fi
echo "GH-PAGES: drifted ❌ — fix the copy named on the failing line above, before publishing"
echo "  version and the agent/skill/command counts live in index.html on the gh-pages branch, which is hand-written and has no"
echo "  build step, so nothing else will do it. A brand-mark line points at whichever copy moved: the site's"
echo "  inline favicon, packaging/gen-network.py, or assets/icon.svg itself if you meant to change the mark."
exit 1
