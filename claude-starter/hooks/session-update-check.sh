#!/usr/bin/env bash
# SessionStart hook (startup only) — say ONCE that a newer kit version is published, and never make the session
# wait to find out.
#
# The gap it closes: a fix only reaches a project when somebody REMEMBERS to run /update-csk. Nothing surfaces a
# release, so shipped fixes sit unused in installs that would want them.
#
# The rule that shapes every line below: **this hook performs no network I/O in the foreground.** A SessionStart
# hook blocks the session until it returns, its timeout is 60s, and the version lookup is exactly the kind of call
# that hangs behind a corporate proxy or an offline machine. That is the same class of failure as the route-hint
# fork storm (2.0.1): the kit spending the user's session-open budget and getting blamed on the CLI. So:
#   - the foreground reads ONE cache file and exits — no curl, no npm, no subshell loop;
#   - when that cache is older than a day it starts a DETACHED refresher whose result is used by the NEXT session.
#     A version notice is not urgent; being one session late costs nothing, blocking costs everything.
#   - if the refresher is killed (session ends first) nothing is written and the next startup simply tries again.
#     The worst case is a notice that arrives late or not at all — never a hang, never a wrong version.
#
# Deliberate scope:
#   - `startup` ONLY. On resume/clear/compact this would re-announce the same thing inside one session, and the
#     session-start channel also carries the rehydrate and trust notices — training the user to skim it is a cost
#     paid by those two, not by this one.
#   - Full installs only: it needs `.claude/VERSION` to compare against and a repo-local place to cache. The plugin
#     edition has neither (it updates via `claude plugin update`), and writing state into a Claude-Code-managed
#     plugin directory is not this hook's business. No VERSION -> silent exit.
#   - Announced once per published version (`.state/update-notified`). A user who declines an update is not asked
#     again until the next release.
#   - Opt out entirely with CSK_NO_UPDATE_CHECK=1 — an outbound request nobody asked for is not acceptable in every
#     environment, and the answer to that is a switch, not a justification.
#
# The version string is treated as untrusted input: it comes off the network, is filtered to [0-9A-Za-z.-], and must
# look like a release before it is ever printed into the model's context.
set -uo pipefail

URL="${CSK_UPDATE_URL:-https://registry.npmjs.org/-/package/@byerlikaya%2fclaude-starter-kit/dist-tags}"
MAX_AGE="${CSK_UPDATE_MAX_AGE:-86400}"      # one day between checks

# DIGITS AND DOTS, exactly three fields — nothing else survives to be printed. Deliberately stricter than semver:
# the value arrives off the network and ends up inside a MODEL's context, and `latest` is never a pre-release, so
# accepting `9.9.9-<anything>` would buy nothing and hand a compromised endpoint a sentence to write. The control
# characters go first (a newline would let one response become several lines), then the shape decides.
sane_version(){
  v="$(printf '%s' "${1:-}" | tr -cd '0-9A-Za-z.-')"
  case "$v" in
    *[!0-9.]*)              return 1 ;;   # letters, dashes, anything but a number
    [0-9]*.[0-9]*.[0-9]*.*) return 1 ;;   # four or more fields
    [0-9]*.[0-9]*.[0-9]*)   printf '%s' "$v" ;;
    *)                      return 1 ;;
  esac
}

# ---- detached half: fetch and cache. Runs with no terminal, no stdout, nobody waiting on it. ------------------
if [ "${1:-}" = "--refresh" ]; then
  ST="${2:-}"
  [ -d "$ST" ] || exit 0
  command -v curl >/dev/null 2>&1 || exit 0
  BODY="$(curl -fsS --max-time 10 "$URL" 2>/dev/null)" || exit 0
  V="$(sane_version "$(printf '%s' "$BODY" | sed -n 's/.*"latest"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)")" || exit 0
  T="$(date +%s 2>/dev/null || echo 0)"
  # Written whole or not at all: a refresher killed mid-flight must never leave a half-line the next startup reads.
  TMP="$ST/.update-check.$$"
  printf '%s %s\n' "$V" "$T" > "$TMP" 2>/dev/null && mv -f "$TMP" "$ST/update-check" 2>/dev/null
  rm -f "$TMP" 2>/dev/null
  exit 0
fi

# ---- foreground half: one file read, then a decision. ---------------------------------------------------------
[ -n "${CSK_NO_UPDATE_CHECK:-}" ] && exit 0

HERE="$(cd "$(dirname "$0")" && pwd)"
SELF="$HERE/$(basename "$0")"

IN=""
[ ! -t 0 ] && IN="$(cat 2>/dev/null || true)"
ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ROOT" ] || ROOT="$(printf '%s' "$IN" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
[ -n "$ROOT" ] || ROOT="$PWD"
# Windows hands this over as a native path, and the stdin copy arrives JSON-encoded on top (`C:\\Repos\\app`).
# Undo the escaping, then fold the separators; both are no-ops on POSIX. Skipping this is how a hook resolves a
# directory that cannot exist and then reports nothing, forever.
ROOT="${ROOT//\\\\//}"; ROOT="${ROOT//\\//}"

CL="$ROOT/.claude"
[ -f "$CL/VERSION" ] || exit 0                                  # plugin edition / not a full install
CUR="$(sane_version "$(head -1 "$CL/VERSION" 2>/dev/null)")" || exit 0

STATE="$CL/.state"
CACHE="$STATE/update-check"
LATEST=""; STAMP=0
if [ -f "$CACHE" ]; then
  read -r LATEST STAMP < "$CACHE" 2>/dev/null || true
  LATEST="$(printf '%s' "${LATEST:-}" | tr -cd '0-9A-Za-z.-')"
  STAMP="$(printf '%s' "${STAMP:-}" | tr -cd '0-9')"
fi
[ -n "$STAMP" ] || STAMP=0

NOW="$(date +%s 2>/dev/null || echo 0)"
if [ "$NOW" -gt 0 ] && [ "$((NOW - STAMP))" -gt "$MAX_AGE" ] && command -v curl >/dev/null 2>&1; then
  mkdir -p "$STATE" 2>/dev/null || true
  # stdin/stdout/stderr all detached. An inherited stdout keeps the hook's pipe open after it exits, and a caller
  # reading to EOF then waits on a curl that has nothing to do with it — a background job that blocks anyway.
  if [ -d "$STATE" ]; then bash "$SELF" --refresh "$STATE" </dev/null >/dev/null 2>&1 & fi
fi

# Nothing cached yet (first run, or every refresh so far failed) -> stay silent. Never guess a version.
[ -n "$LATEST" ] || exit 0
sane_version "$LATEST" >/dev/null || exit 0

# Numeric field compare, one awk. Pre-release suffixes degrade to their numeric prefix (`1-rc2` -> 1), which is
# the harmless direction: it can suppress a notice, never invent one.
awk -v a="$LATEST" -v b="$CUR" 'BEGIN{
  split(a,x,"."); split(b,y,".");
  for(i=1;i<=3;i++){ if(x[i]+0 > y[i]+0) exit 0; if(x[i]+0 < y[i]+0) exit 1 }
  exit 1 }' || exit 0

# Once per published version. The next release re-announces itself; this one does not nag.
SEEN="$STATE/update-notified"
[ -f "$SEEN" ] && [ "$(head -1 "$SEEN" 2>/dev/null | tr -cd '0-9A-Za-z.-')" = "$LATEST" ] && exit 0
mkdir -p "$STATE" 2>/dev/null || true
printf '%s\n' "$LATEST" > "$SEEN" 2>/dev/null || true

printf 'Kit update available: v%s is installed, v%s is published.\n' "$CUR" "$LATEST"
printf 'Mention this to the user in ONE line in your next reply, then carry on with what they asked. `/update-csk`\n'
printf 'performs the update and reports what changed — run it only if they ask for it. This notice is shown once\n'
printf 'per released version; CSK_NO_UPDATE_CHECK=1 turns the check off.\n'
exit 0
