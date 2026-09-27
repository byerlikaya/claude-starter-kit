#!/usr/bin/env bash
# What a release tag may publish, decided before anything is built.
#
#   vX.Y.Z        a final release: VERSION and package.json say X.Y.Z, and the CHANGELOG's first heading is
#                 "## [X.Y.Z] — YYYY-MM-DD". An "[Unreleased]" heading fails it: the final date is written in the
#                 commit the tag points at, never after.
#   vX.Y.Z-rc.N   a rehearsal: the same VERSION and package.json (the repository never carries the rc suffix), and
#                 the heading may still be "## [Unreleased] — X.Y.Z". It publishes to npm under the `next` dist-tag,
#                 so `latest` does not move, and the release job skips the plugin channel and the site.
#
# Usage: bash packaging/release-check.sh <tag> [repo-root]
# Prints version= prerelease= npm_tag= — and appends them to $GITHUB_OUTPUT when that is set.
# Exit 0 publishable · 1 not (the line says why) · 2 usage.
set -euo pipefail

TAG="${1:-}"; ROOT="${2:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -n "$TAG" ] || { echo "usage: release-check.sh <tag> [repo-root]" >&2; exit 2; }

case "$TAG" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "::error::tag '$TAG' is not vX.Y.Z or vX.Y.Z-rc.N"; exit 1 ;;
esac
REST="${TAG#v}"
if printf '%s' "$REST" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  BASE="$REST"; RC=""
elif printf '%s' "$REST" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$'; then
  BASE="${REST%%-rc.*}"; RC="${REST#*-rc.}"
else
  echo "::error::tag '$TAG' is not vX.Y.Z or vX.Y.Z-rc.N"; exit 1
fi

FILE_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
PKG_VERSION="$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ROOT/package.json" | head -1)"
if [ "$FILE_VERSION" != "$BASE" ]; then
  echo "::error::VERSION ($FILE_VERSION) != tag ($BASE). Bump VERSION and package.json before tagging."; exit 1
fi
if [ "$PKG_VERSION" != "$BASE" ]; then
  echo "::error::package.json version ($PKG_VERSION) != tag ($BASE). The repository carries X.Y.Z; an rc suffix is set in CI only."; exit 1
fi

HEAD="$(grep -m1 '^## \[' "$ROOT/CHANGELOG.md" || true)"
ESC="$(printf '%s' "$BASE" | sed 's/\./\\./g')"
FINAL_RE="^## \\[$ESC\\] — [0-9]{4}-[0-9]{2}-[0-9]{2}\$"
RC_RE="^## \\[Unreleased\\] — $ESC\$"
if [ -z "$RC" ]; then
  printf '%s' "$HEAD" | grep -Eq "$FINAL_RE" \
    || { echo "::error::CHANGELOG's first heading is '$HEAD'; a final $BASE needs '## [$BASE] — YYYY-MM-DD'. Write the date in the commit you tag."; exit 1; }
  VERSION="$BASE"; PRE=false; NPM_TAG=latest
else
  printf '%s' "$HEAD" | grep -Eq "$FINAL_RE|$RC_RE" \
    || { echo "::error::CHANGELOG's first heading is '$HEAD'; an rc of $BASE needs '## [Unreleased] — $BASE' or '## [$BASE] — YYYY-MM-DD'."; exit 1; }
  VERSION="$BASE-rc.$RC"; PRE=true; NPM_TAG=next
fi

printf 'version=%s\nprerelease=%s\nnpm_tag=%s\n' "$VERSION" "$PRE" "$NPM_TAG"
[ -n "${GITHUB_OUTPUT:-}" ] && printf 'version=%s\nbase=%s\nprerelease=%s\nnpm_tag=%s\n' "$VERSION" "$BASE" "$PRE" "$NPM_TAG" >> "$GITHUB_OUTPUT"
exit 0
