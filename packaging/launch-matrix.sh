#!/usr/bin/env bash
# One cell of the launch matrix (.github/workflows/launch-matrix.yml): the paths a user takes on day one, on this
# OS and this Node, through the package npm would publish (packed here, run with npx from the tarball).
#
#   init      a fresh project: `npx crewforth init`
#   update    a real 2.13.0 install (the released installer, taken with git archive) → `npx crewforth update`
#   again     a second update changes nothing (a hash over every file's path and bytes, .git and the gate log aside,
#             and .claude/.state/whats-new.md, which is a report of what changed since the last version: the first
#             update writes it, a same-version update has nothing to report and removes it — asserted on its own)
#   doctor    healthy in both projects (exit 0)
#   syntax    `bash -n` on every hook either install carries, the git hooks included
#   crlf      no carriage return in any installed shell file — the case core.autocrlf=true exists to break
#
# Needs git with v2.13.0 (841eb4e) reachable (fetch-depth 0), node and npm. Exit 0 all held, 1 one did not.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
W="${RUNNER_TEMP:-$(mktemp -d)}/launch-matrix"; rm -rf "$W"; mkdir -p "$W"
OLD=841eb4e

# npm on Windows is a native program: it gets C:/… paths, and a tarball as file:<path> (a bare absolute path is
# read by npx as a command to run).
nat(){ if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
tree(){ ( cd "$1" && find . -type f ! -path './.git/*' ! -name gate-log.tsv ! -path './.claude/.state/whats-new.md' | LC_ALL=C sort | while IFS= read -r f; do printf '%s ' "$f"; cksum < "$f"; done ) | cksum; }
N=0
step(){   # $1 label, then the command; its output goes to a log that is shown only when it fails
  local label="$1"; shift; N=$((N + 1)); local log="$W/step-$N.log"
  if "$@" >"$log" 2>&1; then return 0; fi
  local rc=$?; echo "FAIL [$label]: exit $rc. Last 20 lines:"; tail -n 20 "$log" | sed 's/^/    | /'; exit 1
}
die(){ echo "FAIL: $*"; exit 1; }

export npm_config_cache="$(nat "$W/npm-cache")" npm_config_update_notifier=false npm_config_fund=false npm_config_audit=false
export CREW_NO_STAR=1 CREW_LANG=en CLAUDE_CONFIG_DIR="$W/claude-config"; mkdir -p "$CLAUDE_CONFIG_DIR"
git cat-file -e "$OLD^{commit}" 2>/dev/null || die "commit $OLD (v2.13.0) is not in this clone — check out with fetch-depth 0"

echo "cell: $(uname -s) · node $(node --version) · npm $(npm --version) · git $(git --version | awk '{print $3}') · core.autocrlf=$(git config --get core.autocrlf || echo unset)"
step "npm pack" bash -c 'npm pack --silent --pack-destination "$1" | tail -n 1 > "$2"' _ "$(nat "$W")" "$W/tgz-name"
TGZ="file:$(nat "$W/$(cat "$W/tgz-name")")"

# init — a fresh project
P="$W/init"; mkdir -p "$P"; ( cd "$P" && git init -q )
step "init" bash -c 'cd "$1" && npx --yes "$2" init --yes --lang en' _ "$P" "$TGZ"
[ -f "$P/.claude/agents/crew-backend-expert.md" ] || die "init left no .claude/agents/crew-backend-expert.md"

# update — a real 2.13.0 install
U="$W/update"; mkdir -p "$U"; git archive "$OLD" start.sh VERSION claude-starter | ( cd "$U" && tar -xf - )
step "2.13.0 install" bash -c 'cd "$1" && git init -q && bash start.sh --generic --yes --lang en' _ "$U"
[ -f "$U/.claude/agents/backend-expert-csk.md" ] || die "the 2.13.0 install left no backend-expert-csk.md — the fixture broke"
step "update from 2.13.0" bash -c 'cd "$1" && npx --yes "$2" update --here --yes' _ "$U" "$TGZ"
[ -f "$U/.claude/agents/crew-backend-expert.md" ] && [ ! -e "$U/.claude/agents/backend-expert-csk.md" ] \
  || die "the update did not move 2.13.0 to 3.0 (crew-backend-expert.md missing or backend-expert-csk.md left)"
[ "$(tr -d '[:space:]' < "$U/.claude/VERSION")" = "$(tr -d '[:space:]' < VERSION)" ] || die "the updated project reports $(cat "$U/.claude/VERSION"), not $(cat VERSION)"

# again — idempotent
[ -s "$U/.claude/.state/whats-new.md" ] || die "the update from 2.13.0 wrote no .claude/.state/whats-new.md for /crew-update to report"
H1="$(tree "$U")"
step "second update" bash -c 'cd "$1" && npx --yes "$2" update --here --yes' _ "$U" "$TGZ"
[ "$(tree "$U")" = "$H1" ] || die "a second update changed the tree"
[ ! -e "$U/.claude/.state/whats-new.md" ] || die "a same-version update left a what's-new report with nothing new in it"

# doctor, syntax, crlf — in both projects
SH=0; CR=""
for d in "$P" "$U"; do
  step "doctor in ${d##*/}" bash -c 'cd "$1" && bash .claude/eval/doctor.sh' _ "$d"
  for f in "$d"/.claude/hooks/*.sh "$d"/.claude/hooks/pre-commit "$d"/.claude/hooks/commit-msg; do
    [ -f "$f" ] || continue; SH=$((SH + 1)); bash -n "$f" 2>"$W/syntax.err" || die "bash -n failed on ${f#"$W"/}: $(cat "$W/syntax.err")"
  done
  while IFS= read -r f; do CR="$CR ${f#"$W"/}"; done < <(find "$d/.claude" -type f \( -name '*.sh' -o -name pre-commit -o -name commit-msg \) -exec grep -l $'\r' {} + 2>/dev/null || true)
done
[ "$SH" -ge 20 ] || die "only $SH hook file(s) found across both installs — the installs broke, not the syntax"
[ -z "$CR" ] || die "installed shell files carry CR:$CR"

echo "launch-matrix: init ✓ · 2.13.0 → $(cat VERSION) ✓ · second update changed nothing ✓ · doctor healthy ×2 ✓ · bash -n on $SH hooks ✓ · 0 CR in installed shell files ✓"
