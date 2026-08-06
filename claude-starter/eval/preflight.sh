#!/usr/bin/env bash
# Preflight — name the tools this machine is missing BEFORE they turn into a surprise mid-session.
#
# Why this exists. The kit is written to degrade rather than break: no jq -> python -> py -> pure bash for the
# settings merge, sha256sum -> shasum -> cksum for digests, and so on. That is the right design, and it is also
# why a missing tool never announces itself — the fallback runs, something is quietly worse, and the user finds
# out later from a symptom that points somewhere else. A Windows Git Bash install with no jq and no python is
# the normal case, not the exotic one, and it was where every surprise in this project came from.
#
# So: report, do not install. Nothing here writes to the machine or blocks a run. The user asked for exactly
# that boundary — a scaffolding tool that silently installs software on someone's workstation is a worse problem
# than the one it solves, and on a managed corporate machine it simply fails in a new way.
#
# Called from start.sh and adopt.sh (before the install summary) and from doctor.sh (so it stays re-runnable).
#   bash preflight.sh            # human-readable report, always exit 0
#   bash preflight.sh --quiet    # print only what is missing; exit 1 if any REQUIRED tool is absent
set -uo pipefail

QUIET=0
case "${1:-}" in --quiet|-q) QUIET=1 ;; esac

B=""; D=""; R=""; YE=""; GR=""
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'; YE=$'\033[33m'; GR=$'\033[32m'; fi

MISSING_REQ=""; MISSING_OPT=""

have(){ command -v "$1" >/dev/null 2>&1; }
# any_of "label" "why it matters" "fix hint" cmd...
any_of(){
  label="$1"; why="$2"; fix="$3"; shift 3
  found=""
  for c in "$@"; do have "$c" && { found="$c"; break; }; done
  if [ -n "$found" ]; then
    [ "$QUIET" = 1 ] || printf '  %s✓%s %-22s %s%s%s\n' "$GR" "$R" "$label" "$D" "$found" "$R"
    return 0
  fi
  printf '  %s✗%s %-22s %s\n' "$YE" "$R" "$label" "$why"
  printf '      %sfix: %s%s\n' "$D" "$fix" "$R"
  return 1
}

[ "$QUIET" = 1 ] || printf '\n  %sPreflight — what this machine has%s\n' "$B" "$R"

# --- REQUIRED: without these the kit does not work at all -------------------------------------------------
any_of "bash" "the whole kit is bash" \
  "Windows: install Git for Windows (git-scm.com) and run from Git Bash" bash || MISSING_REQ="$MISSING_REQ bash"
any_of "awk" "context measurement, routing, doctor" \
  "Windows: ships with Git Bash · macOS: preinstalled · Linux: apt install gawk" awk gawk mawk || MISSING_REQ="$MISSING_REQ awk"
any_of "git" "the commit-time trace/secret gates are git hooks" \
  "git-scm.com · macOS: xcode-select --install · Linux: apt install git" git || MISSING_REQ="$MISSING_REQ git"

# --- OPTIONAL: the kit falls back, but the fallback is worse in a way worth knowing about ------------------
# jq/python are only needed to MERGE an existing settings.json on update. The pure-bash path replaces the file
# instead (keeping a backup), which is safe but loses hooks the project added itself — the sort of thing that
# is obvious in advance and baffling afterwards.
any_of "jq or python" "settings merge on update falls back to replace+backup (a project's OWN custom hooks are not preserved)" \
  "Windows: winget install jqlang.jq · macOS: brew install jq · Linux: apt install jq" jq python3 python py \
  || MISSING_OPT="$MISSING_OPT jq/python"
any_of "sha256 tool" "the skill-trust gate falls back to cksum (catches accidental edits, not crafted ones)" \
  "Windows/Linux: coreutils (sha256sum) · macOS: shasum is preinstalled" sha256sum shasum || MISSING_OPT="$MISSING_OPT sha256"

if [ -n "$MISSING_REQ" ]; then
  printf '\n  %sMissing REQUIRED:%s%s — install these first; the kit will not work without them.\n' "$YE$B" "$R" "$MISSING_REQ"
elif [ -n "$MISSING_OPT" ]; then
  [ "$QUIET" = 1 ] || printf '\n  %sAll required tools present.%s Optional gaps above are safe but worth closing.\n' "$GR" "$R"
else
  [ "$QUIET" = 1 ] || printf '\n  %sEverything the kit wants is here.%s\n' "$GR" "$R"
fi

# Report-only by design: a missing OPTIONAL tool never fails. `--quiet` exits non-zero only for REQUIRED gaps,
# so a caller can branch on it without having to parse this output.
[ "$QUIET" = 1 ] && [ -n "$MISSING_REQ" ] && exit 1
exit 0
