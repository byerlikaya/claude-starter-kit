#!/usr/bin/env bash
# Distribution reach, captured before GitHub deletes it.
#
# GitHub's traffic API keeps only a FOURTEEN DAY window: clone and view counts older than that are gone, and
# nothing in this repo was writing them down. Every other number the project reports is either derivable from
# the tree (agent/skill counts) or permanent (npm totals); traffic is the one that evaporates. This script is
# the capture step — `.github/workflows/stats.yml` runs it weekly and appends the row to the `stats` branch.
#
# Emits ONE JSON object on stdout (a JSONL row). Everything else goes to stderr, so the caller can redirect
# stdout straight into the ledger.
#
# Sources, and what each is worth:
#   npm downloads      permanent, but almost entirely MIRROR NOISE — every published version, including ones
#                      nobody installs, draws a similar few-downloads-a-week baseline. The signal is the SPIKE
#                      on the current version against that baseline, which is why per-version numbers are kept
#                      rather than a single total.
#   release assets     permanent, cumulative, and a real install signal (a tarball download is deliberate).
#   traffic            EPHEMERAL — the whole reason this exists. Daily arrays are stored, not just the totals,
#                      so the resolution survives even though the runs overlap.
#
# Auth: the traffic endpoints require push access, and `administration` is NOT a permission the workflow's
# automatic GITHUB_TOKEN can be granted — so traffic needs a fine-grained PAT (Administration: read) in
# STATS_TOKEN. Releases work with either token. When traffic cannot be read the row records WHY, and the
# workflow warns: a ledger that silently writes nothing where the numbers should be would read, a year later,
# exactly like a repo nobody cloned.
#
# Usage:
#   bash packaging/collect-stats.sh                    # token from STATS_TOKEN, else GITHUB_TOKEN, else `gh`
#   REPO=owner/name bash packaging/collect-stats.sh    # defaults to byerlikaya/claude-starter-kit
#
# Exit 0 a row was written (traffic may be absent, and says so) · 1 every source failed — no row, no silent
# empty entry · 2 a prerequisite is missing (curl / jq).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

REPO="${REPO:-byerlikaya/claude-starter-kit}"
PKG="@byerlikaya/claude-starter-kit"
PKG_ENC="%40byerlikaya%2Fclaude-starter-kit"

for tool in curl jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "collect-stats: $tool is required" >&2; exit 2; }
done

# Token: STATS_TOKEN (traffic-capable) is preferred; GITHUB_TOKEN still gets releases; `gh` covers a local run.
TOKEN="${STATS_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -z "$TOKEN" ] && command -v gh >/dev/null 2>&1; then TOKEN="$(gh auth token 2>/dev/null || true)"; fi

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VERSION="$(cat VERSION 2>/dev/null || echo unknown)"

# gh_api <path> -> body on stdout, empty on failure (the caller decides whether that is fatal).
gh_api() {
  [ -n "$TOKEN" ] || return 1
  curl -sf -H "Authorization: Bearer $TOKEN" \
          -H "Accept: application/vnd.github+json" \
          -H "X-GitHub-Api-Version: 2022-11-28" \
          "https://api.github.com/repos/$REPO/$1" 2>/dev/null
}
npm_api() { curl -sf "https://api.npmjs.org/$1" 2>/dev/null; }

json_or_null() { # a body is only usable if it parses AND is an object
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$1" && printf '%s' "$1" || printf 'null'
}

OK=0

# --- npm ---------------------------------------------------------------------------------------------------
NPM_POINT="$(json_or_null "$(npm_api "downloads/point/last-week/$PKG")")"
NPM_RANGE="$(json_or_null "$(npm_api "downloads/range/last-week/$PKG")")"
NPM_VERS="$(json_or_null "$(npm_api "versions/$PKG_ENC/last-week")")"
[ "$NPM_POINT" != null ] && OK=1 || echo "collect-stats: npm download point unavailable" >&2

# --- release assets ----------------------------------------------------------------------------------------
RELEASES="$(gh_api releases)"
if [ -n "$RELEASES" ] && jq -e 'type == "array"' >/dev/null 2>&1 <<<"$RELEASES"; then
  RELEASES="$(jq -c '[.[] | {tag: .tag_name, published: .published_at,
                             assets: [.assets[] | {name, downloads: .download_count}]}]' <<<"$RELEASES")"
  OK=1
else
  RELEASES=null; echo "collect-stats: release list unavailable" >&2
fi

# --- traffic (the perishable half) ---------------------------------------------------------------------------
TRAFFIC_ERR=null
CLONES="$(gh_api traffic/clones)"; VIEWS="$(gh_api traffic/views)"
if [ -n "$CLONES" ] && [ -n "$VIEWS" ]; then
  CLONES="$(json_or_null "$CLONES")"; VIEWS="$(json_or_null "$VIEWS")"
  [ "$CLONES" != null ] && [ "$VIEWS" != null ] && OK=1
else
  CLONES=null; VIEWS=null
  if [ -z "$TOKEN" ]; then
    TRAFFIC_ERR='"no token: set STATS_TOKEN (fine-grained PAT, Administration: read)"'
  else
    TRAFFIC_ERR='"token lacks push/Administration access — the automatic GITHUB_TOKEN cannot read traffic"'
  fi
  echo "collect-stats: traffic unavailable — $(jq -r . <<<"$TRAFFIC_ERR")" >&2
fi

if [ "$OK" -eq 0 ]; then
  echo "collect-stats: every source failed — writing no row (an empty row is indistinguishable from zero reach)" >&2
  exit 1
fi

jq -cn \
  --arg at "$NOW" --arg version "$VERSION" --arg repo "$REPO" \
  --argjson point "$NPM_POINT" --argjson range "$NPM_RANGE" --argjson vers "$NPM_VERS" \
  --argjson releases "$RELEASES" --argjson clones "$CLONES" --argjson views "$VIEWS" \
  --argjson traffic_error "$TRAFFIC_ERR" \
  '{
     captured_at: $at,
     repo: $repo,
     kit_version: $version,
     npm: {
       window:      (if $point then {start: $point.start, end: $point.end} else null end),
       total:       (if $point then $point.downloads else null end),
       daily:       (if $range then $range.downloads else null end),
       by_version:  (if $vers  then $vers.downloads  else null end),
       current_version_downloads:
                    (if $vers then ($vers.downloads[$version] // 0) else null end)
     },
     github: {
       releases: $releases,
       traffic: (if $clones and $views
                 then {clones: {count: $clones.count, uniques: $clones.uniques, daily: $clones.clones},
                       views:  {count: $views.count,  uniques: $views.uniques,  daily: $views.views}}
                 else null end),
       traffic_error: $traffic_error
     }
   }'
