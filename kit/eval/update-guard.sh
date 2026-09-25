#!/usr/bin/env bash
# The two measured halves around an update, for /crew-update. Run from the project root.
#
#   update-guard.sh pre    before the update: names uncommitted changes in .claude/ and CLAUDE.md (it WARNS, it
#                          never stops anything — whether to go ahead is the user's call, asked by /crew-update),
#                          then records what is on disk now.
#   update-guard.sh post   after the update: lists what the update added, changed, moved and removed, and points
#                          at the release notes the updater extracted from the package's own CHANGELOG.
#
# It writes exactly one file, .claude/.state/update-snapshot, and changes nothing else. The snapshot is one
# `cksum` over every file (one process for the lot, not one per file — that is 200 forks on Git Bash), so a
# move is a removed path and an added path with the same checksum. The state directory and the gate log are
# left out: they change on every run and say nothing about the update.
set -u
MODE="${1:-}"
[ -d .claude ] || { echo "update-guard: no .claude/ here — run it from the project root" >&2; exit 2; }
SNAP=".claude/.state/update-snapshot"

snapshot(){ # -> "<crc> <size> <path>" per file, sorted by path
  { find .claude -type f ! -path '.claude/.state/*' ! -name gate-log.tsv -print0 2>/dev/null
    [ -f CLAUDE.md ] && printf 'CLAUDE.md\0'; } | xargs -0 cksum 2>/dev/null | LC_ALL=C sort -k3
}

case "$MODE" in
  pre)
    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # What git does not track, it cannot call uncommitted: a private install (the default) gitignores .claude/
      # and CLAUDE.md, and then "clean" would be a claim nobody measured. Say which paths are outside git instead.
      UNTR=""; for _p in .claude CLAUDE.md; do [ -e "$_p" ] && git check-ignore -q "$_p" 2>/dev/null && UNTR="$UNTR $_p"; done
      # The kit's own runtime state is left out: it changes on its own, and a repo that committed it before it
      # was ignored would otherwise warn on every update about a cache nobody edited.
      DIRTY="$(git status --porcelain --untracked-files=all -- .claude CLAUDE.md ':(exclude).claude/.state' 2>/dev/null)"
      if [ -n "$DIRTY" ]; then
        echo "UNCOMMITTED: .claude/ or CLAUDE.md has changes that are not committed:"
        printf '%s\n' "$DIRTY" | sed 's/^/    /' | head -n 20
        [ "$(printf '%s\n' "$DIRTY" | wc -l | tr -d ' ')" -gt 20 ] && echo "    …"
        echo "The update rewrites Crewforth's files under .claude/. Commit or stash first, or go ahead knowingly."
      elif [ -n "$UNTR" ]; then
        echo "NOT IN GIT:$UNTR — gitignored here, so uncommitted changes cannot be detected. The update replaces Crewforth's"
        echo "files under .claude/ (CLAUDE.md and project skills are kept); edits made to Crewforth files there are overwritten."
      else
        echo "clean: no uncommitted changes in .claude/ or CLAUDE.md"
      fi
    else
      echo "not a git repository: nothing to compare against — the file list after the update is the record"
    fi
    mkdir -p .claude/.state 2>/dev/null
    snapshot > "$SNAP" || { echo "update-guard: could not write $SNAP" >&2; exit 1; }
    ;;
  post)
    [ -f "$SNAP" ] || { echo "update-guard: no snapshot — run \`update-guard.sh pre\` before the update" >&2; exit 2; }
    # One tagged line per path (A added · C changed · M moved · R removed), sorted, then printed as four lists.
    OUT="$(snapshot | awk '
      FNR==NR { p=$0; sub(/^[^ ]+ [^ ]+ /,"",p); old[p]=$1" "$2; next }
      { p=$0; sub(/^[^ ]+ [^ ]+ /,"",p); new[p]=$1" "$2 }
      END {
        for (p in new) if (!(p in old)) added[p]=new[p]; else if (old[p]!=new[p]) print "C\t" p
        for (p in old) if (!(p in new)) removed[p]=old[p]
        # a move: gone from one path, the same bytes at another — only when those bytes are unambiguous on both
        # sides (one removed and one added file carry them) and not empty; otherwise it stays removed + added.
        for (r in removed) nr[removed[r]]++
        for (a in added) na[added[a]]++
        for (r in removed) if (nr[removed[r]]==1 && removed[r] !~ / 0$/) for (a in added) if (added[a]==removed[r] && na[added[a]]==1) { moved[r]=a; break }
        for (r in moved) { print "M\t" r " -> " moved[r]; delete removed[r]; delete added[moved[r]] }
        for (p in added) print "A\t" p
        for (p in removed) print "R\t" p
      }' "$SNAP" - | LC_ALL=C sort)"
    for _t in "A added" "C changed" "M moved" "R removed"; do
      _k="${_t%% *}"; _l="$(printf '%s\n' "$OUT" | sed -n "s/^$_k	//p")"
      printf '%s (%s):\n' "${_t#* }" "$(printf '%s' "$_l" | grep -c . || true)"
      [ -n "$_l" ] && printf '%s\n' "$_l" | sed 's/^/    /'
    done
    if [ -s .claude/.state/whats-new.md ]; then
      echo "what changed: .claude/.state/whats-new.md (the release notes from the installed package's own CHANGELOG)"
    else
      echo "what changed: no release notes were extracted (the package carried no CHANGELOG, or nothing is newer)"
    fi
    ;;
  *) echo "usage: update-guard.sh pre|post" >&2; exit 2 ;;
esac
exit 0
