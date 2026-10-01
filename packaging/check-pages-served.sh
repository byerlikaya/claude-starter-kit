#!/usr/bin/env bash
# Did GitHub Pages actually start serving the site this deploy built?
#
#   bash packaging/check-pages-served.sh <site-url> <expected-heading> <deploy-start-epoch> [tries] [wait-seconds]
#
#   <expected-heading>  the first release heading of the CHANGELOG the site was built from, e.g. "[3.0.1]" or
#                       "[Unreleased]" — its bracketed token is what the served /changelog/ page must lead with.
#   exit 0  served: the page leads with that heading, or it was modified after the deploy started
#   exit 1  STALE: reachable, but still the previous artefact (old heading, older than the deploy)
#   exit 3  NOT MEASURED: the page could not be fetched at all (no network, DNS, TLS) — never read as a pass
#
# WHY: `actions/deploy-pages` names a deployment after the commit the WORKFLOW was triggered from, not after the ref
# it built. A second deploy under the same name reports "success" and Pages keeps serving the FIRST artefact. Measured
# at launch: the site showed the rc.3 changelog for 30 minutes after v3.0.0 deployed "successfully" (not a cache:
# x-cache MISS, last-modified the first deploy's time). A green workflow was not evidence the site changed; this is.
#
# Either signal is enough, and both are needed as alternatives: a re-deploy of identical content keeps the old
# last-modified but serves the right heading (correct, green), while the launch failure had neither (red). Pages takes a
# little while to switch, so the check retries before it calls the site stale.
set -uo pipefail
URL="${1:?site url}"; WANT="${2:?expected heading}"; START="${3:?deploy start epoch}"
TRIES="${4:-10}"; WAIT="${5:-30}"
# PAGES_PATH: the page under the site root. The web serves /changelog/ as its index.html; a file:// fixture (the smoke
# test's) has no such mapping, so it names the file itself.
PAGE="${URL%/}/${PAGES_PATH:-changelog/}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
want_tok="$(printf '%s' "$WANT" | grep -oE '\[[^]]+\]' | head -1)"
[ -n "$want_tok" ] || { echo "check-pages-served: no [heading] in '$WANT'" >&2; exit 2; }

# Last-Modified as epoch seconds: GNU date and BSD date spell the parse differently; neither is assumed.
lm_epoch(){ local v="$1" e=""
  e="$(date -u -d "$v" +%s 2>/dev/null)" || e="$(date -u -j -f '%a, %d %b %Y %H:%M:%S GMT' "$v" +%s 2>/dev/null)" || e=""
  printf '%s' "$e"; }

i=0; got=""; lm=""; reached=0
while [ "$i" -lt "$TRIES" ]; do
  i=$((i+1))
  if curl -fsS --max-time 20 -D "$TMP/h" -o "$TMP/b" "$PAGE" 2>"$TMP/err"; then
    reached=1
    got="$(grep -oE '\[(Unreleased|[0-9]+\.[0-9]+\.[0-9]+[^]<]*)\]' "$TMP/b" | head -1)"
    lm="$(tr -d '\r' < "$TMP/h" | sed -n 's/^[Ll]ast-[Mm]odified:[[:space:]]*//p' | head -1)"
    lme="$(lm_epoch "$lm")"
    if [ "$got" = "$want_tok" ]; then
      echo "served: $PAGE leads with $got (the heading this deploy built) — try $i of $TRIES"; exit 0
    fi
    if [ -n "$lme" ] && [ "$lme" -ge "$START" ]; then
      echo "served: $PAGE was modified at $lm, after the deploy started — try $i of $TRIES"; exit 0
    fi
  fi
  [ "$i" -lt "$TRIES" ] && sleep "$WAIT"
done
if [ "$reached" = 0 ]; then
  echo "check-pages-served: NOT MEASURED — $PAGE could not be fetched in $TRIES tries: $(head -1 "$TMP/err" 2>/dev/null)" >&2
  exit 3
fi
echo "check-pages-served: STALE — after $TRIES tries $PAGE still leads with ${got:-no heading} (want $want_tok) and was last modified ${lm:-at an unknown time}, before this deploy started. Pages is serving the previous artefact: re-run site.yml from a commit whose SHA differs from the last deploy's." >&2
exit 1
